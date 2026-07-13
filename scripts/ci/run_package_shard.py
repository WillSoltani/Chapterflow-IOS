#!/usr/bin/env python3
"""Run a validated package shard with per-package timing and failure logs."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import Sequence

import plan as ci_plan


TEST_COUNT_PATTERNS = (
    re.compile(r"Executed\s+(\d+)\s+tests?"),
    re.compile(r"Test run with\s+(\d+)\s+tests?"),
    re.compile(r"\b(\d+)\s+tests? passed\b"),
)


def parse_test_count(output: str) -> int | None:
    values = [
        int(match.group(1))
        for pattern in TEST_COUNT_PATTERNS
        for match in pattern.finditer(output)
    ]
    return max(values) if values else None


def parse_packages(raw: str) -> list[str]:
    try:
        packages = json.loads(raw)
    except json.JSONDecodeError as error:
        raise ci_plan.PlanError(f"packages must be a JSON array: {error}") from error
    if not isinstance(packages, list) or not packages or not all(
        isinstance(package, str) and package for package in packages
    ):
        raise ci_plan.PlanError("packages must be a nonempty string array")
    if len(packages) != len(set(packages)):
        raise ci_plan.PlanError("package shard contains duplicates")
    return packages


def run_package(
    root: Path, package: str, scratch: Path, log_path: Path
) -> dict[str, object]:
    command = [
        "swift",
        "test",
        "--package-path",
        str(root / "Packages" / package),
        "--scratch-path",
        str(scratch),
        "--parallel",
    ]
    started = time.monotonic()
    captured: list[str] = []
    print(f"--- Testing {package} ---", flush=True)
    with log_path.open("w", encoding="utf-8") as log:
        process = subprocess.Popen(
            command,
            cwd=root,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
            env=os.environ.copy(),
        )
        assert process.stdout is not None
        for line in process.stdout:
            print(line, end="", flush=True)
            log.write(line)
            captured.append(line)
        return_code = process.wait()
    duration = round(time.monotonic() - started, 1)
    output = "".join(captured)
    result = {
        "package": package,
        "status": "passed" if return_code == 0 else "failed",
        "duration_seconds": duration,
        "test_count": parse_test_count(output),
        "return_code": return_code,
        "log": str(log_path),
    }
    print(
        f"--- {package}: {result['status']} in {duration:.1f}s; "
        f"tests={result['test_count'] if result['test_count'] is not None else 'unreported'} ---",
        flush=True,
    )
    return result


def append_summary(results: Sequence[dict[str, object]], shard: str) -> None:
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if not summary_path:
        return
    with Path(summary_path).open("a", encoding="utf-8") as stream:
        stream.write(f"### Package shard {shard}\n\n")
        stream.write("| Package | Result | Duration | Tests |\n")
        stream.write("|---|---:|---:|---:|\n")
        for result in results:
            count = result["test_count"] if result["test_count"] is not None else "unreported"
            stream.write(
                f"| {result['package']} | {result['status']} | "
                f"{result['duration_seconds']}s | {count} |\n"
            )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--packages-json", required=True)
    parser.add_argument("--scratch-path", required=True)
    parser.add_argument("--logs-dir", required=True)
    parser.add_argument("--metrics-output", required=True)
    parser.add_argument("--shard", required=True)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    arguments = build_parser().parse_args(argv)
    root = ci_plan.repository_root()
    try:
        graph = ci_plan.load_graph(root)
        ci_plan.verify_graph(root, graph)
        allowed = set(ci_plan.testable_packages(root, graph))
        packages = parse_packages(arguments.packages_json)
        invalid = sorted(set(packages) - allowed)
        if invalid:
            raise ci_plan.PlanError(f"shard requested unknown packages: {invalid}")
    except ci_plan.PlanError as error:
        print(f"package shard error: {error}", file=sys.stderr)
        return 2

    scratch = Path(arguments.scratch_path)
    logs = Path(arguments.logs_dir)
    metrics = Path(arguments.metrics_output)
    scratch.mkdir(parents=True, exist_ok=True)
    logs.mkdir(parents=True, exist_ok=True)
    metrics.parent.mkdir(parents=True, exist_ok=True)

    results = [
        run_package(root, package, scratch, logs / f"{package}.log")
        for package in packages
    ]
    payload = {
        "schema_version": 1,
        "shard": arguments.shard,
        "requested_packages": packages,
        "executed_packages": [result["package"] for result in results],
        "results": results,
        "total_duration_seconds": round(
            sum(float(result["duration_seconds"]) for result in results), 1
        ),
        "reported_test_count": sum(
            int(result["test_count"])
            for result in results
            if result["test_count"] is not None
        ),
    }
    metrics.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    append_summary(results, arguments.shard)

    if payload["executed_packages"] != packages:
        print("requested and executed package lists differ", file=sys.stderr)
        return 2
    failed = [result["package"] for result in results if result["return_code"] != 0]
    if failed:
        print(f"failed packages: {', '.join(str(package) for package in failed)}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
