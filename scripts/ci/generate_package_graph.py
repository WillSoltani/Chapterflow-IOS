#!/usr/bin/env python3
"""Generate or verify the checked local-package graph using SwiftPM semantics."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path
from typing import Sequence


SCHEMA_VERSION = 2


class GraphError(RuntimeError):
    """The semantic package graph could not be generated or verified."""


def repository_root() -> Path:
    return Path(__file__).resolve().parents[2]


def manifest_digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def dump_manifest(package_root: Path) -> dict[str, object]:
    result = subprocess.run(
        [
            "swift",
            "package",
            "dump-package",
            "--package-path",
            str(package_root),
        ],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if result.returncode != 0:
        raise GraphError(
            f"swift package dump-package failed for {package_root.name}: "
            f"{result.stderr.strip()}"
        )
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise GraphError(
            f"SwiftPM returned malformed JSON for {package_root.name}: {error}"
        ) from error
    if not isinstance(payload, dict):
        raise GraphError(f"SwiftPM returned a non-object for {package_root.name}")
    return payload


def local_dependencies(
    payload: dict[str, object], packages_root: Path, known_packages: set[str]
) -> list[str]:
    dependencies = payload.get("dependencies")
    if not isinstance(dependencies, list):
        raise GraphError("SwiftPM dump has no dependency array")

    local: set[str] = set()
    resolved_packages_root = packages_root.resolve()
    for dependency in dependencies:
        if not isinstance(dependency, dict) or "fileSystem" not in dependency:
            continue
        entries = dependency["fileSystem"]
        if not isinstance(entries, list) or len(entries) != 1:
            raise GraphError("SwiftPM fileSystem dependency has an unknown shape")
        entry = entries[0]
        if not isinstance(entry, dict) or not isinstance(entry.get("path"), str):
            raise GraphError("SwiftPM fileSystem dependency has no path")
        resolved = Path(entry["path"]).resolve()
        if resolved.parent != resolved_packages_root or resolved.name not in known_packages:
            raise GraphError(f"local dependency escapes Packages/: {resolved}")
        local.add(resolved.name)
    return sorted(local)


def build_payload(root: Path) -> dict[str, object]:
    packages_root = root / "Packages"
    manifests = sorted(packages_root.glob("*/Package.swift"))
    known_packages = {manifest.parent.name for manifest in manifests}
    if not known_packages:
        raise GraphError("no Packages/*/Package.swift manifests found")

    packages: dict[str, object] = {}
    for manifest in manifests:
        package = manifest.parent.name
        dump = dump_manifest(manifest.parent)
        packages[package] = {
            "dependencies": local_dependencies(dump, packages_root, known_packages),
            "manifest_sha256": manifest_digest(manifest),
        }
    return {
        "schema_version": SCHEMA_VERSION,
        "generated_by": "swift package dump-package",
        "packages": packages,
    }


def checked_payload(root: Path) -> dict[str, object]:
    path = root / "scripts/ci/package-graph.json"
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise GraphError(f"cannot read checked package graph: {error}") from error
    if not isinstance(payload, dict):
        raise GraphError("checked package graph is not an object")
    return payload


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="fail unless SwiftPM's current semantic graph equals the checked artifact",
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    arguments = build_parser().parse_args(argv)
    root = repository_root()
    try:
        generated = build_payload(root)
        if arguments.check:
            if generated != checked_payload(root):
                raise GraphError(
                    "checked package graph differs from SwiftPM semantics; regenerate "
                    "scripts/ci/package-graph.json"
                )
            print("checked package graph matches SwiftPM semantics for every manifest")
        else:
            print(json.dumps(generated, indent=2, sort_keys=True))
    except GraphError as error:
        print(f"package graph error: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
