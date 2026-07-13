#!/usr/bin/env python3
"""Fast, hermetic repository checks that remain active for docs-only CI."""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path, PurePosixPath
from typing import Iterable, Sequence
from urllib.parse import unquote

import plan as ci_plan


CONFLICT_MARKER = re.compile(r"^(?:<<<<<<<.*|=======|>>>>>>>.*)$")
FENCE = re.compile(r"^[ \t]*(`{3,}|~{3,})(.*)$")
MARKDOWN_LINK = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")
MARKDOWN_REFERENCE_DEFINITION = re.compile(
    r"^[ \t]{0,3}\[(?!\^)[^\]\r\n]+\]:[ \t]*"
    r"(?:\r?\n[ \t]*)?"
    r"(<[^>\r\n]+>|[^ \t\r\n]+)",
    re.MULTILINE,
)
SECRET_PATTERNS = {
    "private key": re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    "AWS access key": re.compile(r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b"),
    "GitHub token": re.compile(r"\bgh[pousr]_[A-Za-z0-9]{36,}\b"),
    "GitHub fine-grained token": re.compile(r"\bgithub_pat_[A-Za-z0-9_]{20,}\b"),
    "Google API key": re.compile(r"\bAIza[0-9A-Za-z_-]{35}\b"),
    "Slack token": re.compile(r"\bxox[baprs]-[0-9A-Za-z-]{20,}\b"),
    "Stripe live key": re.compile(r"\b(?:sk|rk)_live_[0-9A-Za-z]{16,}\b"),
}
GENERATED_NAMES = {
    ".DS_Store",
    ".build",
    ".spm-build",
    ".swiftpm",
    "DerivedData",
    "__pycache__",
    "build",
}
GENERATED_SUFFIXES = (
    ".app",
    ".dsym",
    ".dsym.zip",
    ".ipa",
    ".pyc",
    ".pyo",
    ".xcarchive",
    ".xcresult",
)


class CheckFailure(RuntimeError):
    """One or more repository safety checks failed."""


def _text(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return None


def check_conflict_markers(root: Path, paths: Iterable[str]) -> list[str]:
    failures: list[str] = []
    for relative in sorted(set(paths)):
        content = _text(root / relative)
        if content is None:
            continue
        for line_number, line in enumerate(content.splitlines(), start=1):
            if CONFLICT_MARKER.fullmatch(line):
                failures.append(f"{relative}:{line_number}: conflict marker")
    return failures


def check_markdown_fences(path: Path, content: str) -> list[str]:
    failures: list[str] = []
    active_character: str | None = None
    active_length = 0
    active_line = 0
    for line_number, line in enumerate(content.splitlines(), start=1):
        match = FENCE.match(line)
        if not match:
            continue
        token = match.group(1)
        trailing = match.group(2)
        if active_character is None:
            active_character = token[0]
            active_length = len(token)
            active_line = line_number
        elif (
            token[0] == active_character
            and len(token) >= active_length
            and not trailing.strip()
        ):
            active_character = None
            active_length = 0
            active_line = 0
    if active_character is not None:
        failures.append(f"{path}: unclosed Markdown fence opened at line {active_line}")
    return failures


def _link_target(raw_target: str) -> str:
    target = raw_target.strip()
    if target.startswith("<") and ">" in target:
        target = target[1 : target.index(">")]
    elif " " in target:
        target = target.split(" ", 1)[0]
    return unquote(target).split("#", 1)[0]


def markdown_link_targets(content: str) -> Iterable[str]:
    for match in MARKDOWN_LINK.finditer(content):
        yield match.group(1)
    for match in MARKDOWN_REFERENCE_DEFINITION.finditer(content):
        yield match.group(1)


def check_markdown_links(root: Path, relative: str, content: str) -> list[str]:
    failures: list[str] = []
    source = root / relative
    for raw_target in markdown_link_targets(content):
        target = _link_target(raw_target)
        if not target or target.startswith(
            ("#", "http://", "https://", "mailto:", "tel:", "data:")
        ):
            continue
        candidate = root / target.lstrip("/") if target.startswith("/") else source.parent / target
        try:
            candidate.resolve().relative_to(root.resolve())
        except ValueError:
            failures.append(f"{relative}: link escapes repository: {target}")
            continue
        if not candidate.exists():
            failures.append(f"{relative}: missing local link target: {target}")
    return failures


def check_markdown(root: Path, paths: Iterable[str]) -> list[str]:
    failures: list[str] = []
    for relative in sorted(set(paths)):
        if PurePosixPath(relative).suffix.lower() != ".md":
            continue
        content = _text(root / relative)
        if content is None:
            continue
        failures.extend(check_markdown_fences(Path(relative), content))
        failures.extend(check_markdown_links(root, relative, content))
    return failures


def tracked_markdown_paths(root: Path) -> list[str]:
    result = subprocess.run(
        ["git", "ls-files", "-z", "--", ":(glob)**/*.md", ":(glob)*.md"],
        cwd=root,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if result.returncode != 0:
        raise CheckFailure(
            result.stderr.decode("utf-8", errors="replace").strip()
            or "cannot list tracked Markdown"
        )
    return [
        item
        for item in result.stdout.decode("utf-8", errors="surrogateescape").split("\0")
        if item
    ]


def check_incoming_links_to_deleted(
    root: Path, deleted_paths: Iterable[str], markdown_paths: Iterable[str]
) -> list[str]:
    deleted = {(root / relative).resolve() for relative in deleted_paths}
    if not deleted:
        return []
    failures: list[str] = []
    for relative in sorted(set(markdown_paths)):
        source = root / relative
        content = _text(source)
        if content is None:
            continue
        for raw_target in markdown_link_targets(content):
            target = _link_target(raw_target)
            if not target or target.startswith(
                ("#", "http://", "https://", "mailto:", "tel:", "data:")
            ):
                continue
            candidate = (
                root / target.lstrip("/")
                if target.startswith("/")
                else source.parent / target
            )
            if candidate.resolve() in deleted:
                failures.append(
                    f"{relative}: local link targets deleted path: {target}"
                )
    return failures


def added_lines(diff_text: str) -> Iterable[tuple[int, str]]:
    for line_number, line in enumerate(diff_text.splitlines(), start=1):
        if line.startswith("+") and not line.startswith("+++"):
            yield line_number, line[1:]


def check_added_secrets(diff_text: str) -> list[str]:
    failures: list[str] = []
    for line_number, line in added_lines(diff_text):
        for name, pattern in SECRET_PATTERNS.items():
            if pattern.search(line):
                failures.append(f"diff line {line_number}: probable {name}")
    return failures


def check_generated_artifacts(paths: Iterable[str]) -> list[str]:
    failures: list[str] = []
    generated_names = {name.casefold() for name in GENERATED_NAMES}
    for relative in sorted(set(paths)):
        parts = PurePosixPath(relative).parts
        if any(
            part.casefold() in generated_names
            or part.casefold().endswith(GENERATED_SUFFIXES)
            for part in parts
        ):
            failures.append(f"{relative}: generated artifact must not be committed")
    return failures


def check_present_generated_artifacts(root: Path, paths: Iterable[str]) -> list[str]:
    """Reject generated artifacts that would exist at the candidate revision."""
    return check_generated_artifacts(
        relative for relative in paths if os.path.lexists(root / relative)
    )


def run_git_diff_check(root: Path, merge_base: str, head: str) -> list[str]:
    result = subprocess.run(
        ["git", "diff", "--check", merge_base, head],
        cwd=root,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    if result.returncode == 0:
        return []
    output = result.stdout.strip() or "git diff --check failed"
    return output.splitlines()


def read_diff(root: Path, merge_base: str, head: str) -> str:
    result = subprocess.run(
        ["git", "diff", "--no-ext-diff", "--no-color", "--unified=0", merge_base, head],
        cwd=root,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if result.returncode != 0:
        raise CheckFailure(result.stderr.strip() or "cannot read merge-base diff")
    return result.stdout


def run_checks(root: Path, paths: Sequence[str], merge_base: str, head: str) -> None:
    if not re.fullmatch(r"[0-9a-fA-F]{40}", merge_base):
        raise CheckFailure("valid merge-base unavailable for repository checks")
    failures = run_git_diff_check(root, merge_base, head)
    failures.extend(check_present_generated_artifacts(root, paths))
    failures.extend(check_conflict_markers(root, paths))
    failures.extend(check_markdown(root, paths))
    deleted = [relative for relative in paths if not os.path.lexists(root / relative)]
    if deleted:
        failures.extend(
            check_incoming_links_to_deleted(
                root,
                deleted,
                tracked_markdown_paths(root),
            )
        )
    failures.extend(check_added_secrets(read_diff(root, merge_base, head)))
    if failures:
        raise CheckFailure("\n".join(failures))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", required=True)
    parser.add_argument("--head", required=True)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    arguments = build_parser().parse_args(argv)
    root = ci_plan.repository_root()
    diff = ci_plan.resolve_git_diff(root, arguments.base, arguments.head)
    if diff.failed:
        print("repository checks: merge-base diff unavailable", file=sys.stderr)
        return 2
    try:
        run_checks(root, diff.paths, diff.merge_base, arguments.head)
    except CheckFailure as error:
        print(f"repository checks failed:\n{error}", file=sys.stderr)
        return 1
    print(
        "repository checks passed: git diff, conflict markers, added-secret patterns, "
        "generated artifacts, Markdown fences, and local links"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
