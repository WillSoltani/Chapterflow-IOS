#!/usr/bin/env python3
"""Append-only, externally rooted validation evidence for ChapterFlow packages."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import re
import shlex
import shutil
import signal
import stat
import subprocess
import sys
from pathlib import Path, PurePosixPath
from types import TracebackType
from typing import Any, Callable, Iterable, Sequence
from urllib.parse import unquote, urlsplit


SCHEMA_VERSION = 1
RECOVERY_INVENTORY_SCHEMA_VERSION = 2
FULL_SHA = re.compile(r"^[0-9a-fA-F]{40}$")
SAFE_COMPONENT = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
ATTEMPT_REFERENCE = re.compile(r"^attempt://([^/]+)/results/(.+)$")
MUTABLE_ATTEMPT_ALIASES = {"current", "latest", "newest"}
LEASE_TRIGGERS = (
    "xcodebuild test",
    "run_native_matrix.py",
    "scripts/qa/device/run_matrix.py",
    "run_paired_performance.py",
)
INPUT_OPTIONS = {
    "--baseline",
    "--input",
    "--inventory",
    "--manifest",
    "--source",
}
OUTPUT_OPTIONS = {
    "--artifact",
    "--output",
    "--report",
    "--result",
    "--result-bundle-path",
    "-resultBundlePath",
}


class EvidenceError(RuntimeError):
    """The evidence contract could not be satisfied."""


class LockedError(EvidenceError):
    """A required atomic resource claim collided."""


def utc_now() -> str:
    return dt.datetime.now(dt.UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def canonical_json_bytes(value: Any) -> bytes:
    return (
        json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
        + "\n"
    ).encode("utf-8")


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def open_regular_readonly(path: Path) -> tuple[int, os.stat_result]:
    flags = os.O_RDONLY
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(path, flags)
    observed = os.fstat(descriptor)
    if not stat.S_ISREG(observed.st_mode):
        os.close(descriptor)
        raise EvidenceError(f"input must be a regular non-symlink file: {path}")
    return descriptor, observed


def read_regular_bytes(path: Path, *, maximum_bytes: int | None = None) -> bytes:
    descriptor, observed = open_regular_readonly(path)
    try:
        if maximum_bytes is not None and observed.st_size > maximum_bytes:
            raise EvidenceError(f"input is too large: {path}")
        handle = os.fdopen(descriptor, "rb")
        descriptor = -1
        with handle:
            value = handle.read()
        if len(value) != observed.st_size:
            raise EvidenceError(f"input changed while being read: {path}")
        return value
    finally:
        if descriptor >= 0:
            os.close(descriptor)


def read_regular_bytes_at(
    directory_fd: int, name: str, *, maximum_bytes: int | None = None
) -> bytes:
    if not name or "/" in name or name in {".", ".."}:
        raise EvidenceError("directory-relative input name is invalid")
    flags = os.O_RDONLY
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(name, flags, dir_fd=directory_fd)
    try:
        observed = os.fstat(descriptor)
        if not stat.S_ISREG(observed.st_mode):
            raise EvidenceError("directory-relative input is not a regular file")
        if stat.S_IMODE(observed.st_mode) != 0o600:
            raise EvidenceError("directory-relative input is not private")
        if maximum_bytes is not None and observed.st_size > maximum_bytes:
            raise EvidenceError("directory-relative input is too large")
        chunks: list[bytes] = []
        consumed = 0
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                break
            chunks.append(chunk)
            consumed += len(chunk)
        if consumed != observed.st_size:
            raise EvidenceError("directory-relative input changed while being read")
        return b"".join(chunks)
    finally:
        os.close(descriptor)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    descriptor, observed = open_regular_readonly(path)
    consumed = 0
    try:
        handle = os.fdopen(descriptor, "rb")
        descriptor = -1
        with handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
                consumed += len(chunk)
    finally:
        if descriptor >= 0:
            os.close(descriptor)
    if consumed != observed.st_size:
        raise EvidenceError(f"input changed while hashing: {path}")
    return digest.hexdigest()


def read_json(path: Path) -> Any:
    try:
        return json.loads(
            read_regular_bytes(path, maximum_bytes=64 * 1024 * 1024).decode("utf-8")
        )
    except EvidenceError:
        raise
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise EvidenceError(f"cannot read canonical JSON input {path}: {error}") from error


def read_json_bytes(value: bytes, label: str) -> Any:
    if len(value) > 64 * 1024 * 1024:
        raise EvidenceError(f"JSON input is too large: {label}")
    try:
        return json.loads(value.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise EvidenceError(f"cannot read canonical JSON input {label}: {error}") from error


def write_bytes_exclusive(
    path: Path, value: bytes, *, directory_fd: int | None = None
) -> None:
    if directory_fd is not None and (path.is_absolute() or len(path.parts) != 1):
        raise EvidenceError("directory-relative artifact name must be one path component")
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    blocked = {
        item
        for item in (
            getattr(signal, "SIGINT", None),
            getattr(signal, "SIGTERM", None),
            getattr(signal, "SIGHUP", None),
        )
        if isinstance(item, int)
    }
    descriptor: int | None = None
    created: os.stat_result | None = None
    previous_mask: set[signal.Signals] | None = None
    try:
        if blocked and hasattr(signal, "pthread_sigmask"):
            previous_mask = signal.pthread_sigmask(signal.SIG_BLOCK, blocked)
        try:
            descriptor = os.open(path, flags, 0o600, dir_fd=directory_fd)
        except FileExistsError as error:
            raise EvidenceError(
                f"append-only artifact already exists: {path}"
            ) from error
        created = os.fstat(descriptor)
        if previous_mask is not None:
            signal.pthread_sigmask(signal.SIG_SETMASK, previous_mask)
            previous_mask = None
        os.fchmod(descriptor, 0o600)
        remaining = memoryview(value)
        while remaining:
            written = os.write(descriptor, remaining)
            if written <= 0:
                raise OSError("exclusive artifact write made no progress")
            remaining = remaining[written:]
        os.fsync(descriptor)
    except BaseException as error:
        error_traceback = error.__traceback__
        if previous_mask is not None:
            try:
                signal.pthread_sigmask(signal.SIG_SETMASK, previous_mask)
                previous_mask = None
            except BaseException as restore_error:
                if not isinstance(restore_error, Exception) and isinstance(
                    error, Exception
                ):
                    restore_error.add_note(
                        "exclusive artifact creation had already failed with: "
                        f"{type(error).__name__}"
                    )
                    error = restore_error
                    error_traceback = restore_error.__traceback__
                else:
                    error.add_note(
                        "restoring the signal mask also failed with: "
                        f"{type(restore_error).__name__}"
                    )
        if created is None and descriptor is not None:
            try:
                created = os.fstat(descriptor)
            except BaseException as identity_error:
                if not isinstance(identity_error, Exception) and isinstance(
                    error, Exception
                ):
                    identity_error.add_note(
                        "exclusive artifact creation had already failed with: "
                        f"{type(error).__name__}"
                    )
                    error = identity_error
                    error_traceback = identity_error.__traceback__
                else:
                    error.add_note(
                        "cannot recover exclusive artifact identity after: "
                        f"{type(identity_error).__name__}"
                    )
        if created is not None:
            try:
                current = (
                    path.lstat()
                    if directory_fd is None
                    else os.stat(path, dir_fd=directory_fd, follow_symlinks=False)
                )
                if (
                    not stat.S_ISLNK(current.st_mode)
                    and stat.S_ISREG(current.st_mode)
                    and (current.st_dev, current.st_ino)
                    == (created.st_dev, created.st_ino)
                ):
                    if directory_fd is None:
                        path.unlink()
                    else:
                        os.unlink(path, dir_fd=directory_fd)
            except OSError:
                pass
        raise error.with_traceback(error_traceback)
    finally:
        if descriptor is not None:
            try:
                os.close(descriptor)
            except OSError:
                pass


def write_json_exclusive(path: Path, value: Any) -> None:
    write_bytes_exclusive(path, canonical_json_bytes(value))


def private_directory_identity(path: Path, label: str) -> tuple[int, int]:
    try:
        observed = path.lstat()
    except FileNotFoundError as error:
        raise EvidenceError(f"{label} is missing: {path}") from error
    if stat.S_ISLNK(observed.st_mode) or not stat.S_ISDIR(observed.st_mode):
        raise EvidenceError(f"{label} must be a real directory: {path}")
    mode = stat.S_IMODE(observed.st_mode)
    if mode != 0o700:
        raise EvidenceError(
            f"{label} must have private 0700 permissions, found {mode:04o}: {path}"
        )
    return observed.st_dev, observed.st_ino


def require_private_regular_file(path: Path, label: str) -> os.stat_result:
    try:
        observed = path.lstat()
    except FileNotFoundError as error:
        raise EvidenceError(f"{label} is missing: {path}") from error
    if stat.S_ISLNK(observed.st_mode) or not stat.S_ISREG(observed.st_mode):
        raise EvidenceError(f"{label} must be a regular non-symlink file: {path}")
    mode = stat.S_IMODE(observed.st_mode)
    if mode != 0o600:
        raise EvidenceError(
            f"{label} must have private 0600 permissions, found {mode:04o}: {path}"
        )
    return observed


def create_private_directory(path: Path, label: str, *, exclusive: bool = False) -> tuple[int, int]:
    created = False
    try:
        os.mkdir(path, 0o700)
        created = True
    except FileExistsError:
        if exclusive:
            raise
    if created:
        os.chmod(path, 0o700, follow_symlinks=False)
    return private_directory_identity(path, label)


def validate_component(value: str, label: str) -> str:
    if not SAFE_COMPONENT.fullmatch(value) or value.casefold() in MUTABLE_ATTEMPT_ALIASES:
        raise EvidenceError(f"invalid {label}: {value!r}")
    return value


def canonicalize_repo_heads(values: Sequence[str]) -> tuple[list[dict[str, str]], str]:
    if not values:
        raise EvidenceError("at least one --repo-head repository=fullSHA is required")
    repositories: dict[str, str] = {}
    for raw in values:
        if raw.count("=") != 1:
            raise EvidenceError(f"invalid --repo-head value: {raw!r}")
        repository, revision = raw.split("=", 1)
        validate_component(repository, "repository name")
        if repository in repositories:
            raise EvidenceError(f"duplicate repository head: {repository}")
        if not FULL_SHA.fullmatch(revision):
            raise EvidenceError(f"repository head must be a full 40-character SHA: {raw!r}")
        repositories[repository] = revision.lower()
    ordered = [
        {"repository": repository, "head": repositories[repository]}
        for repository in sorted(repositories)
    ]
    canonical = "".join(
        f"{item['repository']}={item['head']}\n" for item in ordered
    ).encode("ascii")
    return ordered, sha256_bytes(canonical)


def required_repository_head(
    repositories: Sequence[dict[str, str]], repository: str
) -> str:
    matches = [
        item["head"] for item in repositories if item["repository"] == repository
    ]
    if len(matches) != 1:
        raise EvidenceError(
            f"exactly one --repo-head {repository}=<fullSHA> is required"
        )
    return matches[0]


def git_output(cwd: Path, arguments: Sequence[str], *, check: bool = True) -> str:
    result = subprocess.run(
        ["git", *arguments],
        cwd=cwd,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=git_discovery_environment(),
    )
    if check and result.returncode != 0:
        raise EvidenceError(
            f"git {' '.join(arguments)} failed with status {result.returncode}; "
            f"stdoutSha256={sha256_bytes(result.stdout.encode('utf-8'))}; "
            f"stderrSha256={sha256_bytes(result.stderr.encode('utf-8'))}"
        )
    return result.stdout.strip()


def git_discovery_environment() -> dict[str, str]:
    environment = {
        name: value
        for name, value in os.environ.items()
        if not name.startswith("GIT_")
    }
    environment["GIT_OPTIONAL_LOCKS"] = "0"
    return environment


def repository_root(cwd: Path) -> Path:
    return Path(git_output(cwd, ["rev-parse", "--show-toplevel"])).resolve()


def canonical_root_leaf(root: Path, label: str) -> Path:
    declared = Path(os.path.abspath(root.expanduser()))
    if os.path.lexists(declared) and stat.S_ISLNK(declared.lstat().st_mode):
        raise EvidenceError(f"{label} must not be a symlink: {declared}")
    try:
        canonical_parent = declared.parent.resolve(strict=True)
    except OSError as error:
        raise EvidenceError(
            f"{label} parent must already exist: {declared.parent}"
        ) from error
    resolved = canonical_parent / declared.name
    if os.path.lexists(resolved) and stat.S_ISLNK(resolved.lstat().st_mode):
        raise EvidenceError(f"{label} must not be a symlink: {resolved}")
    return resolved


def containing_git_repository(path: Path) -> Path | None:
    probe = path if path.is_dir() else path.parent
    for candidate in (probe, *probe.parents):
        if os.path.lexists(candidate / ".git"):
            return candidate
    result = subprocess.run(
        ["git", "-C", str(probe), "rev-parse", "--absolute-git-dir"],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=git_discovery_environment(),
    )
    if result.returncode != 0:
        return None
    top_level = result.stdout.strip()
    return Path(top_level).resolve() if top_level else probe


def ensure_external_root(root: Path, source_root: Path, label: str) -> Path:
    resolved = canonical_root_leaf(root, label)
    try:
        resolved.relative_to(source_root)
    except ValueError:
        pass
    else:
        raise EvidenceError(
            f"{label} must be outside the source repository: {resolved}"
        )
    containing_repository = containing_git_repository(resolved)
    if containing_repository is not None:
        raise EvidenceError(
            f"{label} must be outside every Git repository; "
            f"{resolved} is contained by {containing_repository}"
        )
    return resolved


def verify_candidate_head(
    cwd: Path, repositories: Sequence[dict[str, str]]
) -> tuple[str, str]:
    actual = git_output(cwd, ["rev-parse", "HEAD"])
    if not FULL_SHA.fullmatch(actual):
        raise EvidenceError("source worktree HEAD is not a full commit SHA")
    heads = {item["repository"]: item["head"] for item in repositories}
    remote = git_output(cwd, ["remote", "get-url", "origin"], check=False)
    identity = github_repository_identity(remote)
    if identity == ("willsoltani", "chapterflow-ios") and "ios" in heads:
        selected = "ios"
    elif identity == ("willsoltani", "chapterflow") and "backend" in heads:
        selected = "backend"
    elif len(heads) == 1:
        selected = next(iter(heads))
    elif "ios" in heads:
        selected = "ios"
    else:
        raise EvidenceError("cannot bind source worktree to a declared repository head")
    if actual.lower() != heads[selected]:
        raise EvidenceError(
            f"source HEAD {actual.lower()} does not match {selected}={heads[selected]}"
        )
    return selected, actual.lower()


def source_state(cwd: Path, expected_head: str) -> dict[str, Any]:
    head = git_output(cwd, ["rev-parse", "HEAD"]).lower()
    if head != expected_head:
        raise EvidenceError(
            f"source HEAD drifted from declared candidate {expected_head} to {head}"
        )
    result = subprocess.run(
        ["git", "status", "--porcelain=v2", "--branch", "--untracked-files=all"],
        cwd=cwd,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=git_discovery_environment(),
    )
    if result.returncode != 0:
        raise EvidenceError(
            "cannot fingerprint source status: "
            f"Git exited with status {result.returncode}; "
            f"stderrSha256={sha256_bytes(result.stderr)}"
        )
    dirty_entries = sum(
        1 for line in result.stdout.splitlines() if line and not line.startswith(b"#")
    )
    return {
        "head": head,
        "statusSha256": sha256_bytes(result.stdout),
        "dirtyEntries": dirty_entries,
        "clean": dirty_entries == 0,
    }


def git_bytes(cwd: Path, arguments: Sequence[str], label: str) -> bytes:
    result = subprocess.run(
        ["git", *arguments],
        cwd=cwd,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=git_discovery_environment(),
    )
    if result.returncode != 0:
        raise EvidenceError(
            f"cannot capture {label}: Git exited with status {result.returncode}; "
            f"stderrSha256={sha256_bytes(result.stderr)}"
        )
    return result.stdout


def stat_identity(value: os.stat_result) -> tuple[int, int, int, int, int, int]:
    return (
        value.st_dev,
        value.st_ino,
        value.st_mode,
        value.st_size,
        value.st_mtime_ns,
        value.st_ctime_ns,
    )


def private_path_digest(relative: str) -> str:
    return sha256_bytes(b"git-owner-untracked-path\0" + os.fsencode(relative))


def stable_untracked_record(repository: Path, relative: str) -> dict[str, Any]:
    path_digest = private_path_digest(relative)
    pure = PurePosixPath(relative)
    if pure.is_absolute() or not pure.parts or any(part in {"", ".", ".."} for part in pure.parts):
        raise EvidenceError(
            f"Git reported an unsafe untracked path identifier: {path_digest}"
        )
    path = repository / Path(*pure.parts)
    try:
        path.relative_to(repository)
    except ValueError as error:
        raise EvidenceError(
            f"untracked path escapes repository: {path_digest}"
        ) from error
    try:
        before = path.lstat()
    except OSError as error:
        raise EvidenceError(
            f"cannot inspect untracked path identifier: {path_digest}"
        ) from error
    before_identity = stat_identity(before)
    record: dict[str, Any] = {
        "pathSha256": path_digest,
        "mode": stat.S_IMODE(before.st_mode),
        "bytes": before.st_size,
    }
    if stat.S_ISREG(before.st_mode):
        try:
            descriptor, opened = open_regular_readonly(path)
        except (EvidenceError, OSError) as error:
            raise EvidenceError(
                f"cannot open untracked file identifier: {path_digest}"
            ) from error
        digest = hashlib.sha256()
        consumed = 0
        try:
            if stat_identity(opened) != before_identity:
                raise EvidenceError(
                    f"untracked file changed before hashing: {path_digest}"
                )
            while True:
                try:
                    chunk = os.read(descriptor, 1024 * 1024)
                except OSError as error:
                    raise EvidenceError(
                        f"cannot hash untracked file identifier: {path_digest}"
                    ) from error
                if not chunk:
                    break
                digest.update(chunk)
                consumed += len(chunk)
            after_open = os.fstat(descriptor)
        finally:
            os.close(descriptor)
        try:
            after_path = path.lstat()
        except OSError as error:
            raise EvidenceError(
                f"cannot recheck untracked file identifier: {path_digest}"
            ) from error
        if (
            consumed != before.st_size
            or stat_identity(after_open) != before_identity
            or stat_identity(after_path) != before_identity
        ):
            raise EvidenceError(
                f"untracked file changed while hashing: {path_digest}"
            )
        record.update({"kind": "file", "sha256": digest.hexdigest()})
        return record
    if stat.S_ISLNK(before.st_mode):
        try:
            target = os.fsencode(os.readlink(path))
            after_path = path.lstat()
        except OSError as error:
            raise EvidenceError(
                f"cannot inspect untracked symlink identifier: {path_digest}"
            ) from error
        if stat_identity(after_path) != before_identity:
            raise EvidenceError(
                f"untracked symlink changed while hashing: {path_digest}"
            )
        record.update(
            {
                "kind": "symlink",
                "targetBytes": len(target),
                "targetSha256": sha256_bytes(target),
            }
        )
        return record
    raise EvidenceError(
        "untracked path has unsupported type for byte fingerprinting: "
        f"{path_digest}"
    )


def untracked_records_from_status(
    repository: Path, status: bytes
) -> list[dict[str, Any]]:
    records = [
        stable_untracked_record(repository, os.fsdecode(entry[2:]))
        for entry in status.split(b"\0")
        if entry.startswith(b"? ")
    ]
    return sorted(records, key=lambda item: str(item["pathSha256"]))


def status_branch_oid(status: bytes) -> str:
    prefix = b"# branch.oid "
    values = [entry[len(prefix) :] for entry in status.split(b"\0") if entry.startswith(prefix)]
    if len(values) != 1:
        raise EvidenceError("owner status must contain exactly one branch.oid")
    try:
        value = values[0].decode("ascii").lower()
    except UnicodeDecodeError as error:
        raise EvidenceError("owner status branch.oid is not ASCII") from error
    if not FULL_SHA.fullmatch(value):
        raise EvidenceError("owner status branch.oid is not a full commit SHA")
    return value


def git_owner_state_fingerprint(path: Path) -> dict[str, Any]:
    repository = repository_root(path)
    status_arguments = [
        "status",
        "--porcelain=v2",
        "--branch",
        "-z",
        "--untracked-files=all",
    ]
    diff_arguments = ["diff", "--binary", "--no-ext-diff", "--no-textconv"]
    index_diff_arguments = [
        "diff",
        "--cached",
        "--binary",
        "--no-ext-diff",
        "--no-textconv",
    ]
    head_before = git_output(repository, ["rev-parse", "HEAD"]).lower()
    if not FULL_SHA.fullmatch(head_before):
        raise EvidenceError("owner repository HEAD is not a full commit SHA")
    status_before = git_bytes(repository, status_arguments, "owner status")
    if status_branch_oid(status_before) != head_before:
        raise EvidenceError("owner status branch.oid does not match repository HEAD")
    diff_before = git_bytes(repository, diff_arguments, "owner working-tree diff")
    index_diff_before = git_bytes(repository, index_diff_arguments, "owner index diff")
    untracked = untracked_records_from_status(repository, status_before)
    status_after = git_bytes(repository, status_arguments, "owner status recheck")
    diff_after = git_bytes(repository, diff_arguments, "owner working-tree diff recheck")
    index_diff_after = git_bytes(repository, index_diff_arguments, "owner index diff recheck")
    if (
        status_after != status_before
        or diff_after != diff_before
        or index_diff_after != index_diff_before
    ):
        raise EvidenceError("owner Git-visible state changed while fingerprinting")
    untracked_after = untracked_records_from_status(repository, status_after)
    if untracked_after != untracked:
        raise EvidenceError("owner untracked bytes changed while fingerprinting")
    if (
        git_bytes(repository, status_arguments, "owner final status recheck")
        != status_before
        or git_bytes(repository, diff_arguments, "owner final working-tree diff recheck")
        != diff_before
        or git_bytes(repository, index_diff_arguments, "owner final index diff recheck")
        != index_diff_before
    ):
        raise EvidenceError("owner Git-visible state changed during final fingerprint recheck")
    head_after = git_output(repository, ["rev-parse", "HEAD"]).lower()
    if head_after != head_before:
        raise EvidenceError("owner repository HEAD changed while fingerprinting")
    state: dict[str, Any] = {
        "schemaVersion": 2,
        "kind": "git-owner-state-fingerprint",
        "repositoryRoot": str(repository),
        "head": head_before,
        "statusSha256": sha256_bytes(status_before),
        "workingTreeDiffSha256": sha256_bytes(diff_before),
        "indexDiffSha256": sha256_bytes(index_diff_before),
        "untrackedEntries": untracked,
        "untrackedCount": len(untracked),
        "untrackedTreeSha256": sha256_bytes(canonical_json_bytes(untracked)),
    }
    state["stateSha256"] = sha256_bytes(canonical_json_bytes(state))
    return state


def validate_results_relative(value: str) -> PurePosixPath:
    decoded = unquote(value)
    if "\\" in decoded or "\x00" in decoded or "?" in decoded or "#" in decoded:
        raise EvidenceError(f"invalid results path: {value!r}")
    pure = PurePosixPath(decoded)
    if (
        pure.is_absolute()
        or not pure.parts
        or pure.parts[0] != "results"
        or len(pure.parts) < 2
        or any(part in {"", ".", ".."} for part in pure.parts)
    ):
        raise EvidenceError(f"path must be a non-escaping results/... path: {value!r}")
    return pure


def resolve_output_path(attempt_root: Path, value: str) -> Path:
    pure = validate_results_relative(value)
    candidate = attempt_root / Path(*pure.parts)
    try:
        candidate.relative_to(attempt_root)
    except ValueError as error:
        raise EvidenceError(f"results path escapes attempt root: {value!r}") from error
    return candidate


def directory_artifact_record(path: Path, attempt_root: Path) -> dict[str, Any]:
    private_directory_identity(path, "directory artifact")
    tree: list[dict[str, Any]] = []
    total_bytes = 0
    file_count = 0
    directory_count = 0
    for base, directories, files in os.walk(path, followlinks=False):
        base_path = Path(base)
        for name in sorted(directories):
            child = base_path / name
            private_directory_identity(child, "evidence artifact directory")
            directory_count += 1
            tree.append(
                {
                    "path": child.relative_to(path).as_posix(),
                    "kind": "directory",
                }
            )
        for name in sorted(files):
            child = base_path / name
            observed = require_private_regular_file(child, "evidence artifact file")
            size = observed.st_size
            total_bytes += size
            file_count += 1
            tree.append(
                {
                    "path": child.relative_to(path).as_posix(),
                    "kind": "file",
                    "sha256": sha256_file(child),
                    "bytes": size,
                }
            )
    tree.sort(key=lambda item: (str(item["path"]), str(item["kind"])))
    return {
        "path": path.relative_to(attempt_root).as_posix(),
        "kind": "directory",
        "sha256": sha256_bytes(canonical_json_bytes(tree)),
        "bytes": total_bytes,
        "fileCount": file_count,
        "directoryCount": directory_count,
    }


def artifact_records(
    results_root: Path, attempt_root: Path, primary_artifact: Path
) -> list[dict[str, Any]]:
    if not results_root.exists():
        return []
    private_directory_identity(results_root, "results root")
    records: list[dict[str, Any]] = []
    for base, directories, files in os.walk(results_root, followlinks=False):
        base_path = Path(base)
        for name in sorted(directories):
            path = base_path / name
            private_directory_identity(path, "evidence artifact directory")
        for name in sorted(files):
            path = base_path / name
            observed = require_private_regular_file(path, "evidence artifact file")
            records.append(
                {
                    "path": path.relative_to(attempt_root).as_posix(),
                    "kind": "file",
                    "sha256": sha256_file(path),
                    "bytes": observed.st_size,
                }
            )
    if primary_artifact.is_dir():
        records.append(directory_artifact_record(primary_artifact, attempt_root))
    return sorted(records, key=lambda item: item["path"])


def snapshot_repository_results(source_root: Path) -> list[dict[str, Any]]:
    results = source_root / "results"
    if not os.path.lexists(results):
        return [{"path": "results", "kind": "absent"}]
    root_mode = results.lstat().st_mode
    if stat.S_ISLNK(root_mode):
        return [
            {
                "path": "results",
                "kind": "symlink",
                "mode": stat.S_IMODE(root_mode),
            }
        ]
    if stat.S_ISREG(root_mode):
        return [
            {
                "path": "results",
                "kind": "file",
                "mode": stat.S_IMODE(root_mode),
                "bytes": results.stat().st_size,
                "sha256": sha256_file(results),
            }
        ]
    if not stat.S_ISDIR(root_mode):
        return [
            {
                "path": "results",
                "kind": "other",
                "mode": stat.S_IMODE(root_mode),
            }
        ]
    records: list[dict[str, Any]] = [
        {
            "path": "results",
            "kind": "directory",
            "mode": stat.S_IMODE(root_mode),
        }
    ]
    for base, directories, files in os.walk(results, followlinks=False):
        base_path = Path(base)
        for name in sorted(directories):
            path = base_path / name
            mode = path.lstat().st_mode
            records.append(
                {
                    "path": path.relative_to(source_root).as_posix(),
                    "kind": "symlink" if stat.S_ISLNK(mode) else "directory",
                    "mode": stat.S_IMODE(mode),
                }
            )
        for name in sorted(files):
            path = base_path / name
            mode = path.lstat().st_mode
            record: dict[str, Any] = {
                "path": path.relative_to(source_root).as_posix(),
                "kind": "symlink" if stat.S_ISLNK(mode) else "file",
                "mode": stat.S_IMODE(mode),
                "bytes": path.lstat().st_size,
            }
            if stat.S_ISREG(mode):
                record["sha256"] = sha256_file(path)
            records.append(record)
    return sorted(records, key=lambda item: item["path"])


def snapshot_digest(snapshot: Sequence[dict[str, Any]]) -> str:
    return sha256_bytes(canonical_json_bytes(list(snapshot)))


class AttemptContext:
    def __init__(
        self,
        *,
        root: Path,
        package: str,
        assertion: str,
        attempt: str,
        repositories: Sequence[dict[str, str]],
        head_set_digest: str,
        cwd: Path,
    ) -> None:
        self.root = root
        self.package = package
        self.assertion = assertion
        self.attempt = attempt
        self.repositories = list(repositories)
        self.head_set_digest = head_set_digest
        self.cwd = cwd
        self.attempts_root = root / package / head_set_digest / "attempts"
        self.attempt_root = self.attempts_root / attempt
        self.inputs: list[dict[str, Any]] = []
        self._layout_identities: dict[Path, tuple[int, int]] = {}

    def _layout_paths(self) -> list[tuple[Path, str]]:
        return [
            (self.root, "evidence root"),
            (self.root / self.package, "package evidence directory"),
            (
                self.root / self.package / self.head_set_digest,
                "head-set evidence directory",
            ),
            (self.attempts_root, "attempt collection directory"),
            (self.attempt_root, "attempt directory"),
        ]

    def create(self) -> None:
        if not self.root.parent.is_dir():
            raise EvidenceError(
                f"evidence root parent must already exist: {self.root.parent}"
            )
        for path, label in self._layout_paths()[:-1]:
            self._layout_identities[path] = create_private_directory(path, label)
        try:
            identity = create_private_directory(
                self.attempt_root, "attempt directory", exclusive=True
            )
        except FileExistsError as error:
            raise EvidenceError(
                f"attempt ID is append-only and already exists: {self.attempt}"
            ) from error
        self._layout_identities[self.attempt_root] = identity
        self.verify_private_layout()

    def verify_private_layout(self) -> None:
        for path, label in self._layout_paths():
            observed = private_directory_identity(path, label)
            expected = self._layout_identities.get(path)
            if expected is None or observed != expected:
                raise EvidenceError(f"{label} identity changed during evidence execution: {path}")

    def ensure_private_subdirectory(self, path: Path) -> None:
        self.verify_private_layout()
        try:
            relative = path.relative_to(self.attempt_root)
        except ValueError as error:
            raise EvidenceError("private evidence directory escapes its attempt") from error
        current = self.attempt_root
        for part in relative.parts:
            current = current / part
            create_private_directory(current, "attempt evidence subdirectory")

    def harden_private_tree(self) -> None:
        self.verify_private_layout()
        for base, directories, files in os.walk(self.attempt_root, followlinks=False):
            base_path = Path(base)
            for name in sorted(directories):
                child = base_path / name
                mode = child.lstat().st_mode
                if stat.S_ISLNK(mode) or not stat.S_ISDIR(mode):
                    raise EvidenceError(
                        f"attempt evidence contains a non-directory: {child}"
                    )
                os.chmod(child, 0o700, follow_symlinks=False)
            for name in sorted(files):
                child = base_path / name
                mode = child.lstat().st_mode
                if stat.S_ISLNK(mode) or not stat.S_ISREG(mode):
                    raise EvidenceError(f"attempt evidence contains a non-file: {child}")
                os.chmod(child, 0o600, follow_symlinks=False)
        self.verify_private_layout()

    def referenced_attempt_root(self, attempt_id: str) -> tuple[Path, tuple[int, int]]:
        self.verify_private_layout()
        declared = self.attempts_root / attempt_id
        self._reject_symlink_components(
            self.root, declared, "referenced attempt directory"
        )
        identity = private_directory_identity(declared, "referenced attempt directory")
        return declared, identity

    def output_path(self, value: str) -> Path:
        return resolve_output_path(self.attempt_root, value)

    @staticmethod
    def _reject_symlink_components(root: Path, path: Path, label: str) -> None:
        try:
            relative = path.relative_to(root)
        except ValueError as error:
            raise EvidenceError(f"{label} escapes its attempt") from error
        current = root
        if os.path.lexists(current) and stat.S_ISLNK(current.lstat().st_mode):
            raise EvidenceError(f"{label} contains a symlink: {current}")
        for part in relative.parts:
            current = current / part
            if os.path.lexists(current) and stat.S_ISLNK(current.lstat().st_mode):
                raise EvidenceError(f"{label} contains a symlink: {current}")

    @staticmethod
    def _observed_artifact(path: Path, root: Path, kind: str) -> dict[str, Any]:
        AttemptContext._reject_symlink_components(root, path, "referenced artifact")
        if kind == "directory":
            return directory_artifact_record(path, root)
        if kind != "file" or not path.is_file():
            raise EvidenceError("referenced artifact has an invalid type")
        observed = require_private_regular_file(path, "referenced artifact")
        return {
            "kind": "file",
            "sha256": sha256_file(path),
            "bytes": observed.st_size,
        }

    def _resolve_input(self, reference: str) -> Path:
        match = ATTEMPT_REFERENCE.fullmatch(reference)
        if not match:
            raise EvidenceError(
                "cross-attempt input must use attempt://<attempt-id>/results/..."
            )
        attempt_id = unquote(match.group(1))
        validate_component(attempt_id, "referenced attempt ID")
        if attempt_id == self.attempt:
            raise EvidenceError("an attempt cannot consume its own mutable output")
        if any(item["reference"] == reference for item in self.inputs):
            raise EvidenceError(f"duplicate immutable input reference: {reference}")
        relative = validate_results_relative(f"results/{match.group(2)}")
        referenced_root, referenced_identity = self.referenced_attempt_root(attempt_id)
        manifest_path = referenced_root / "manifest.json"
        self._reject_symlink_components(
            referenced_root, manifest_path, "referenced manifest"
        )
        if not manifest_path.is_file():
            raise EvidenceError(f"referenced attempt manifest is missing: {attempt_id}")
        require_private_regular_file(manifest_path, "referenced attempt manifest")
        manifest = read_json(manifest_path)
        if not isinstance(manifest, dict):
            raise EvidenceError(f"referenced attempt manifest is malformed: {attempt_id}")
        required = {
            "packageId": self.package,
            "headSetDigest": self.head_set_digest,
            "attemptId": attempt_id,
            "status": "passed",
        }
        for key, expected in required.items():
            if manifest.get(key) != expected:
                raise EvidenceError(
                    f"referenced attempt {attempt_id} has incompatible {key}"
                )
        release_record_path: Path | None = None
        release_record_sha256: str | None = None
        lease = manifest.get("lease")
        if isinstance(lease, dict) and lease.get("mode") == "attempt-claim":
            if (
                lease.get("releaseAfterManifest") is not True
                or lease.get("released") is not False
            ):
                raise EvidenceError(
                    f"referenced attempt {attempt_id} used an invalid lease sequence"
                )
            release_name = lease.get("releaseRecord")
            if release_name != "lease-release.json":
                raise EvidenceError(
                    f"referenced attempt {attempt_id} lacks a lease release record"
                )
            release_path = referenced_root / release_name
            self._reject_symlink_components(
                referenced_root, release_path, "lease release record"
            )
            require_private_regular_file(release_path, "lease release record")
            release = read_json(release_path)
            if (
                not isinstance(release, dict)
                or release.get("schemaVersion") != 1
                or release.get("packageId") != manifest.get("packageId")
                or release.get("assertionId") != manifest.get("assertionId")
                or release.get("released") is not True
                or release.get("attemptId") != attempt_id
                or release.get("owner") != manifest.get("owner")
                or release.get("manifest") != "manifest.json"
                or not isinstance(release.get("releasedAt"), str)
                or not release.get("releasedAt")
                or "failure" in release
                or release.get("manifestSha256") != sha256_file(manifest_path)
            ):
                raise EvidenceError(
                    f"referenced attempt {attempt_id} has an invalid lease release record"
                )
            release_record_path = release_path
            release_record_sha256 = sha256_file(release_path)
        artifact_name = relative.as_posix()
        matches = [
            item
            for item in manifest.get("artifacts", [])
            if isinstance(item, dict) and item.get("path") == artifact_name
        ]
        if len(matches) != 1:
            raise EvidenceError(
                f"referenced artifact is missing or ambiguous: {reference}"
            )
        declared_artifact = referenced_root / Path(*relative.parts)
        self._reject_symlink_components(
            referenced_root, declared_artifact, "referenced artifact"
        )
        artifact = declared_artifact.resolve(strict=True)
        try:
            artifact.relative_to(referenced_root)
        except ValueError as error:
            raise EvidenceError(f"referenced artifact escapes its attempt: {reference}") from error
        observed = self._observed_artifact(
            artifact, referenced_root, str(matches[0].get("kind"))
        )
        observed_digest = observed["sha256"]
        observed_bytes = observed["bytes"]
        if (
            observed_digest != matches[0].get("sha256")
            or observed_bytes != matches[0].get("bytes")
        ):
            raise EvidenceError(f"referenced artifact digest mismatch: {reference}")
        input_record = {
            "reference": reference,
            "attemptId": attempt_id,
            "path": artifact_name,
            "manifestPath": str(manifest_path),
            "manifestSha256": sha256_file(manifest_path),
            "attemptRoot": str(referenced_root),
            "attemptRootDevice": referenced_identity[0],
            "attemptRootInode": referenced_identity[1],
            "artifactSha256": observed_digest,
            "bytes": observed_bytes,
            "kind": matches[0].get("kind"),
            "sourcePath": str(declared_artifact),
        }
        if release_record_path is not None:
            input_record["releaseRecordPath"] = str(release_record_path)
            input_record["releaseRecordSha256"] = release_record_sha256
        self.inputs.append(input_record)
        return artifact

    def input_path(self, reference: str) -> Path:
        artifact = self._resolve_input(reference)
        input_record = self.inputs[-1]
        staged = self._stage_input(artifact, input_record)
        input_record["stagedPath"] = str(staged)
        input_record["stagedSha256"] = input_record["artifactSha256"]
        return staged

    def _stage_input(self, source: Path, record: dict[str, Any]) -> Path:
        inputs_root = self.attempt_root / "inputs"
        self.ensure_private_subdirectory(inputs_root)
        suffix = "".join(source.suffixes)
        staged = inputs_root / f"input-{len(self.inputs) + 1:04d}{suffix}"
        kind = str(record["kind"])
        if kind == "file":
            value = read_regular_bytes(source)
            if (
                sha256_bytes(value) != record["artifactSha256"]
                or len(value) != record["bytes"]
            ):
                raise EvidenceError(
                    f"referenced artifact changed while staging: {record['reference']}"
                )
            write_bytes_exclusive(staged, value)
        elif kind == "directory":
            create_private_directory(staged, "staged input directory", exclusive=True)
            for base, directories, files in os.walk(source, followlinks=False):
                base_path = Path(base)
                relative = base_path.relative_to(source)
                destination_base = staged / relative
                for name in sorted(directories):
                    child = base_path / name
                    if child.is_symlink():
                        raise EvidenceError(
                            f"referenced directory input contains a symlink: {child}"
                        )
                    create_private_directory(
                        destination_base / name, "staged input subdirectory"
                    )
                for name in sorted(files):
                    child = base_path / name
                    mode = child.lstat().st_mode
                    if stat.S_ISLNK(mode) or not stat.S_ISREG(mode):
                        raise EvidenceError(
                            f"referenced directory input contains a non-file: {child}"
                        )
                    write_bytes_exclusive(
                        destination_base / name, read_regular_bytes(child)
                    )
        else:
            raise EvidenceError(f"referenced artifact has an invalid type: {kind}")
        observed = self._observed_artifact(staged, self.attempt_root, kind)
        if (
            observed["sha256"] != record["artifactSha256"]
            or observed["bytes"] != record["bytes"]
        ):
            raise EvidenceError(
                f"staged immutable input does not match its source: {record['reference']}"
            )
        return staged

    def input_bytes(self, reference: str) -> bytes:
        path = self._resolve_input(reference)
        record = self.inputs[-1]
        if record["kind"] != "file":
            raise EvidenceError(f"referenced input is not a file: {reference}")
        value = read_regular_bytes(path)
        if sha256_bytes(value) != record["artifactSha256"] or len(value) != record["bytes"]:
            raise EvidenceError(f"referenced artifact changed while being read: {reference}")
        return value

    def verify_inputs_unchanged(self) -> None:
        for record in self.inputs:
            attempt_root = Path(record["attemptRoot"])
            if private_directory_identity(
                attempt_root, "referenced attempt directory"
            ) != (record["attemptRootDevice"], record["attemptRootInode"]):
                raise EvidenceError(
                    f"referenced attempt changed during consumption: {record['reference']}"
                )
            manifest_path = Path(record["manifestPath"])
            self._reject_symlink_components(
                attempt_root, manifest_path, "referenced manifest"
            )
            require_private_regular_file(manifest_path, "referenced attempt manifest")
            if (
                not manifest_path.is_file()
                or sha256_file(manifest_path) != record["manifestSha256"]
            ):
                raise EvidenceError(
                    f"referenced manifest changed during consumption: {record['reference']}"
                )
            if "releaseRecordPath" in record:
                release_path = Path(record["releaseRecordPath"])
                self._reject_symlink_components(
                    attempt_root, release_path, "lease release record"
                )
                require_private_regular_file(release_path, "lease release record")
                if sha256_file(release_path) != record["releaseRecordSha256"]:
                    raise EvidenceError(
                        f"lease release record changed during consumption: {record['reference']}"
                    )
            source = Path(record["sourcePath"])
            observed = self._observed_artifact(
                source, attempt_root, record["kind"]
            )
            if (
                observed["sha256"] != record["artifactSha256"]
                or observed["bytes"] != record["bytes"]
            ):
                raise EvidenceError(
                    f"referenced artifact changed during consumption: {record['reference']}"
                )
            if "stagedPath" in record:
                staged = Path(record["stagedPath"])
                staged_observed = self._observed_artifact(
                    staged, self.attempt_root, record["kind"]
                )
                if (
                    staged_observed["sha256"] != record["stagedSha256"]
                    or staged_observed["bytes"] != record["bytes"]
                ):
                    raise EvidenceError(
                        f"staged immutable input changed during consumption: {record['reference']}"
                    )


def rewrite_argument(context: AttemptContext, argument: str) -> tuple[str, dict[str, str] | None]:
    if argument.startswith("attempt://"):
        resolved = context.input_path(argument)
        return str(resolved), {
            "kind": "input",
            "declared": argument,
            "resolved": str(resolved),
        }
    if argument.startswith("results/"):
        resolved = context.output_path(argument)
        context.ensure_private_subdirectory(resolved.parent)
        return str(resolved), {
            "kind": "output",
            "declared": argument,
            "resolved": str(resolved),
        }
    if "=" in argument:
        prefix, value = argument.split("=", 1)
        if value.startswith("attempt://"):
            resolved = context.input_path(value)
            rewritten = f"{prefix}={resolved}"
            return rewritten, {
                "kind": "input",
                "declared": argument,
                "resolved": rewritten,
            }
        if value.startswith("results/"):
            resolved = context.output_path(value)
            context.ensure_private_subdirectory(resolved.parent)
            rewritten = f"{prefix}={resolved}"
            return rewritten, {
                "kind": "output",
                "declared": argument,
                "resolved": rewritten,
            }
    return argument, None


def rewrite_command(
    context: AttemptContext, command: Sequence[str]
) -> tuple[list[str], list[dict[str, str]]]:
    rewritten: list[str] = []
    changes: list[dict[str, str]] = []
    previous_option: str | None = None
    for argument in command:
        option = argument.split("=", 1)[0]
        if argument.startswith("results/") and previous_option in INPUT_OPTIONS:
            raise EvidenceError(
                f"cross-row input for {previous_option} must use an immutable attempt:// reference"
            )
        if argument.startswith("attempt://") and previous_option in OUTPUT_OPTIONS:
            raise EvidenceError(
                f"output for {previous_option} cannot use an attempt:// input reference"
            )
        if "=" in argument:
            prefix, argument_value = argument.split("=", 1)
            if argument_value.startswith("results/") and prefix in INPUT_OPTIONS:
                raise EvidenceError(
                    f"cross-row input for {prefix} must use an immutable attempt:// reference"
                )
            if argument_value.startswith("attempt://") and prefix in OUTPUT_OPTIONS:
                raise EvidenceError(
                    f"output for {prefix} cannot use an attempt:// input reference"
                )
        value, change = rewrite_argument(context, argument)
        rewritten.append(value)
        if change is not None:
            changes.append(change)
        previous_option = option if option.startswith("-") and "=" not in argument else None
    return rewritten, changes


def is_pytest_command(command: Sequence[str]) -> bool:
    executable = Path(command[0]).name.casefold() if command else ""
    if executable.startswith("pytest") or executable.startswith("py.test"):
        return True
    return any(
        command[index] == "-m" and command[index + 1].casefold() == "pytest"
        for index in range(len(command) - 1)
    )


def command_requires_selector(command: Sequence[str]) -> bool:
    normalized = " ".join(command)
    selector_tokens = {
        "--filter",
        "--scenario",
        "--scenarios",
        "--suite",
        "--test",
        "-only-testing",
    }
    if any(
        token in selector_tokens
        or token.startswith("--filter=")
        or token.startswith("--test=")
        or token.startswith("-only-testing:")
        for token in command
    ):
        return True
    if is_pytest_command(command):
        return True
    if any(
        command[index] == "-m"
        and command[index + 1].casefold() in {"pytest", "unittest"}
        for index in range(len(command) - 1)
    ):
        return True
    return any(
        marker in normalized
        for marker in (
            "xcodebuild test",
            "swift test",
            " -m unittest",
            " pytest",
            "tsx --test",
        )
    )


def structured_counts(value: Any) -> dict[str, int] | None:
    if not isinstance(value, dict):
        return None
    candidate = value.get("counts") if isinstance(value.get("counts"), dict) else value
    required = ("matched", "failed", "skipped")
    if not all(
        isinstance(candidate.get(key), int)
        and not isinstance(candidate.get(key), bool)
        and candidate[key] >= 0
        for key in required
    ):
        return None
    return {key: candidate[key] for key in required}


def parse_test_counts(
    output: bytes,
    artifact: Path | None,
    return_code: int,
    command: Sequence[str] = (),
) -> dict[str, Any]:
    text = output.decode("utf-8", errors="replace")
    matched = 0
    failed = 0
    skipped = 0
    selector_found = False
    selector_required = command_requires_selector(command)

    xctest = list(
        re.finditer(
            r"Executed\s+(\d+)\s+tests?,\s+with\s+(\d+)\s+failures?",
            text,
            re.IGNORECASE,
        )
    ) if selector_required else []
    if xctest:
        selector_found = True
        matched = int(xctest[-1].group(1))
        failed = int(xctest[-1].group(2))
        skipped = len(
            re.findall(r"^Test Case .+ skipped(?: \(|$)", text, re.IGNORECASE | re.MULTILINE)
        )
        if re.search(r"expected failure|XCTExpectFailure|known issue", text, re.IGNORECASE):
            failed = max(failed, 1)

    swift = list(
        re.finditer(
            r"Test run with\s+(\d+)\s+tests?(?:\s+in\s+\d+\s+suites?)?\s+"
            r"(passed|failed|skipped)",
            text,
            re.IGNORECASE,
        )
    ) if selector_required else []
    if swift:
        selector_found = True
        matched = int(swift[-1].group(1))
        if swift[-1].group(2).casefold() == "failed":
            failed = max(failed, 1)
        elif swift[-1].group(2).casefold() == "skipped":
            skipped = max(skipped, matched)
    swift_skip_lines = (
        re.findall(r"^↷.+\bskipped\b", text, re.IGNORECASE | re.MULTILINE)
        if selector_required
        else []
    )
    if swift_skip_lines:
        selector_found = True
        skipped = max(skipped, len(swift_skip_lines))
        matched = max(matched, len(swift_skip_lines))

    unittest_matches = (
        list(re.finditer(r"^Ran\s+(\d+)\s+tests?", text, re.MULTILINE))
        if selector_required
        else []
    )
    if unittest_matches:
        selector_found = True
        matched = int(unittest_matches[-1].group(1))
        failed_match = re.search(r"FAILED\s*\(([^)]*)\)", text)
        if failed_match:
            failed = sum(
                int(value)
                for value in re.findall(
                    r"(?:failures|errors)=(\d+)", failed_match.group(1)
                )
            )
            failed = max(failed, 1)
            skipped_match = re.search(r"skipped=(\d+)", failed_match.group(1))
            if skipped_match:
                skipped = int(skipped_match.group(1))
        ok_match = re.search(r"OK\s*\(([^)]*)\)", text)
        if ok_match:
            skipped_match = re.search(r"skipped=(\d+)", ok_match.group(1))
            if skipped_match:
                skipped = int(skipped_match.group(1))

    pytest = list(
        re.finditer(
            r"^(?:(\d+)\s+passed)?(?:,?\s*(\d+)\s+failed)?(?:,?\s*(\d+)\s+skipped)?(?:\s+in\s+.+)?$",
            text,
            re.IGNORECASE | re.MULTILINE,
        )
    ) if selector_required and is_pytest_command(command) else []
    pytest = [match for match in pytest if any(match.groups())]
    if pytest:
        final = pytest[-1]
        passed_count = int(final.group(1) or 0)
        failed_count = int(final.group(2) or 0)
        skipped_count = int(final.group(3) or 0)
        if passed_count or failed_count or skipped_count:
            selector_found = True
            matched = passed_count + failed_count + skipped_count
            failed = max(failed, failed_count)
            skipped = max(skipped, skipped_count)

    if selector_required and not selector_found:
        tap_tests = re.findall(r"^[#ℹ]\s*tests\s+(\d+)\s*$", text, re.MULTILINE)
        tap_failures = re.findall(r"^[#ℹ]\s*fail\s+(\d+)\s*$", text, re.MULTILINE)
        tap_skips = re.findall(r"^[#ℹ]\s*skipped\s+(\d+)\s*$", text, re.MULTILINE)
        if tap_tests:
            selector_found = True
            matched = int(tap_tests[-1])
            failed = int(tap_failures[-1]) if tap_failures else 0
            skipped = int(tap_skips[-1]) if tap_skips else 0

    if not selector_found and artifact is not None and artifact.is_file():
        raw = artifact.read_bytes()
        try:
            value = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            worktrees = sum(1 for line in raw.splitlines() if line.startswith(b"worktree "))
            if not selector_required:
                matched = worktrees if worktrees else int(bool(raw))
        else:
            counts = structured_counts(value)
            if counts is not None:
                matched = counts["matched"]
                failed = max(failed, counts["failed"])
                skipped = max(skipped, counts["skipped"])
                selector_found = True
            elif isinstance(value, list) and not selector_required:
                if value and all(isinstance(page, list) for page in value):
                    matched = sum(len(page) for page in value)
                else:
                    matched = len(value)
            elif isinstance(value, dict) and not selector_required:
                matched = 1
            elif not selector_required:
                matched = int(value is not None)
    elif not selector_found and artifact is not None and artifact.is_dir():
        manifest = artifact / "manifest.json"
        counts = structured_counts(read_json(manifest)) if manifest.is_file() else None
        if counts is not None:
            matched = counts["matched"]
            failed = max(failed, counts["failed"])
            skipped = max(skipped, counts["skipped"])
            selector_found = True
        elif not selector_required:
            matched = 1
    if return_code != 0:
        failed = max(failed, 1)
    return {
        "matched": matched,
        "failed": failed,
        "skipped": skipped,
        "selectorDetected": selector_found,
        "selectorRequired": selector_required,
    }


def command_triggers_lease(command: Sequence[str]) -> str | None:
    normalized = " ".join(command)
    for trigger in LEASE_TRIGGERS:
        if trigger in normalized:
            return trigger
    return None


def validate_lease_policy(source_root: Path) -> None:
    policy_path = source_root / "upgrade/program/resource-locks.json"
    if not policy_path.is_file():
        return
    policy = read_json(policy_path)
    scoped = policy.get("commandScopedLeasing") if isinstance(policy, dict) else None
    locks = policy.get("locks") if isinstance(policy, dict) else None
    simulator = locks.get("simulator-device") if isinstance(locks, dict) else None
    patterns = scoped.get("triggerPatterns") if isinstance(scoped, dict) else None
    if (
        not isinstance(patterns, list)
        or tuple(patterns) != LEASE_TRIGGERS
        or not isinstance(simulator, dict)
        or simulator.get("mode") != "capacity"
        or simulator.get("capacity") != 1
        or simulator.get("commandScoped") is not True
    ):
        raise EvidenceError(
            "checked-in simulator/device lease policy drifted from the evidence runner contract"
        )


def read_claim(path: Path) -> dict[str, Any] | None:
    claim = path / "claim.json"
    if not claim.is_file():
        return None
    try:
        value = read_json(claim)
    except EvidenceError:
        return None
    return value if isinstance(value, dict) else None


def resolve_owner(package: str, lock_root: Path, declared: str | None) -> str:
    if declared:
        return validate_component(declared, "owner")
    environment = os.environ.get("CODEX_TASK_ID") or os.environ.get("GITHUB_RUN_ID")
    if environment:
        cleaned = re.sub(r"[^A-Za-z0-9._-]", "-", environment)
        return validate_component(cleaned, "owner")
    package_claim = read_claim(lock_root / f"package-{package}")
    if package_claim and isinstance(package_claim.get("ownerTaskId"), str):
        cleaned = re.sub(r"[^A-Za-z0-9._-]", "-", package_claim["ownerTaskId"])
        return validate_component(cleaned, "owner")
    return f"local-pid-{os.getpid()}"


def cleanup_exclusively_created_lease_slot(
    slot: Path,
    expected_identity: tuple[int, int],
    expected_claim_identity: tuple[int, int] | None = None,
) -> None:
    if private_directory_identity(slot, "owned simulator-device lease") != expected_identity:
        raise EvidenceError("refusing to clean a replaced simulator-device lease slot")
    claim_path = slot / "claim.json"
    try:
        claim = claim_path.lstat()
    except FileNotFoundError:
        claim = None
    if claim is not None:
        if (
            stat.S_ISLNK(claim.st_mode)
            or not stat.S_ISREG(claim.st_mode)
            or claim.st_nlink != 1
        ):
            raise EvidenceError(
                "refusing to clean an invalid simulator-device lease claim"
            )
        if expected_claim_identity is not None and (
            claim.st_dev,
            claim.st_ino,
        ) != expected_claim_identity:
            raise EvidenceError(
                "refusing to clean a replaced simulator-device lease claim"
            )
        claim_path.unlink()
    if private_directory_identity(slot, "owned simulator-device lease") != expected_identity:
        raise EvidenceError("simulator-device lease slot changed during cleanup")
    slot.rmdir()


def create_exclusive_owned_lease_slot(slot: Path) -> tuple[int, int]:
    blocked = {
        item
        for item in (
            getattr(signal, "SIGINT", None),
            getattr(signal, "SIGTERM", None),
            getattr(signal, "SIGHUP", None),
        )
        if isinstance(item, int)
    }
    previous_mask: set[signal.Signals] | None = None
    if blocked and hasattr(signal, "pthread_sigmask"):
        previous_mask = signal.pthread_sigmask(signal.SIG_BLOCK, blocked)
    owned_identity: tuple[int, int] | None = None
    pending_error: BaseException | None = None
    pending_traceback: TracebackType | None = None
    try:
        os.mkdir(slot, 0o700)
        observed = slot.lstat()
        if stat.S_ISLNK(observed.st_mode) or not stat.S_ISDIR(observed.st_mode):
            raise EvidenceError("new simulator-device lease slot is not a real directory")
        owned_identity = (observed.st_dev, observed.st_ino)
        os.chmod(slot, 0o700, follow_symlinks=False)
        if private_directory_identity(slot, "simulator-device lease") != owned_identity:
            raise EvidenceError("simulator-device lease changed during creation")
    except BaseException as error:
        pending_error = error
        pending_traceback = error.__traceback__
    finally:
        if previous_mask is not None:
            try:
                signal.pthread_sigmask(signal.SIG_SETMASK, previous_mask)
            except BaseException as error:
                if pending_error is None:
                    pending_error = error
                    pending_traceback = error.__traceback__
                elif not isinstance(error, Exception) and isinstance(
                    pending_error, Exception
                ):
                    error.add_note(
                        "lease-slot creation had already failed with: "
                        f"{type(pending_error).__name__}"
                    )
                    pending_error = error
                    pending_traceback = error.__traceback__
                else:
                    pending_error.add_note(
                        "restoring the signal mask also failed: "
                        f"{type(error).__name__}"
                    )
    if pending_error is not None:
        if owned_identity is not None:
            try:
                cleanup_exclusively_created_lease_slot(slot, owned_identity)
            except (EvidenceError, OSError) as cleanup_error:
                pending_error.add_note(
                    "interrupted lease-slot creation cleanup failed: "
                    f"{type(cleanup_error).__name__}"
                )
        raise pending_error.with_traceback(pending_traceback)
    assert owned_identity is not None
    return owned_identity


def acquire_command_lease(
    *,
    lock_root: Path,
    package: str,
    assertion: str,
    attempt: str,
    owner: str,
    command_digest: str,
    trigger: str,
    on_acquired: (
        Callable[[dict[str, Any], Path, tuple[int, int], tuple[int, int]], None]
        | None
    ) = None,
    on_rollback: (
        Callable[[dict[str, Any], Path, tuple[int, int], tuple[int, int]], None]
        | None
    ) = None,
) -> tuple[dict[str, Any], Path | None]:
    if not lock_root.parent.is_dir():
        raise EvidenceError(f"lease root parent must already exist: {lock_root.parent}")
    create_private_directory(lock_root, "lease root")
    slot = lock_root / "resource-simulator-device-slot-1"
    metadata = {
        "schemaVersion": 1,
        "resource": "simulator-device",
        "slot": 1,
        "scope": "command",
        "packageId": package,
        "assertionId": assertion,
        "attemptId": attempt,
        "ownerTaskId": owner,
        "pid": os.getpid(),
        "commandDigest": command_digest,
        "trigger": trigger,
        "startedAt": utc_now(),
        "heartbeat": "command-start",
    }
    lease_record: dict[str, Any] = {
        "resource": "simulator-device",
        "slot": 1,
        "mode": "attempt-claim",
        "claim": str(slot),
        "released": False,
    }
    owned_slot_identity: tuple[int, int] | None = None
    claim_identity: tuple[int, int] | None = None
    callback_started = False
    foreign_slot = False
    try:
        try:
            owned_slot_identity = create_exclusive_owned_lease_slot(slot)
        except FileExistsError as error:
            foreign_slot = True
            private_directory_identity(slot, "simulator-device lease")
            claim_path = slot / "claim.json"
            if claim_path.is_file():
                require_private_regular_file(
                    claim_path, "simulator-device lease claim"
                )
            existing = read_claim(slot)
            if (
                existing
                and existing.get("scope") == "package"
                and existing.get("packageId") == package
                and existing.get("ownerTaskId") == owner
            ):
                return (
                    {
                        "resource": "simulator-device",
                        "slot": 1,
                        "mode": "parent-claim-reentrant",
                        "parentClaim": str(slot),
                        "released": False,
                    },
                    None,
                )
            raise LockedError(
                "LOCKED: simulator-device slot 1 is already claimed"
            ) from error
        write_json_exclusive(slot / "claim.json", metadata)
        claim_stat = require_private_regular_file(
            slot / "claim.json", "simulator-device lease claim"
        )
        claim_identity = (claim_stat.st_dev, claim_stat.st_ino)
        if on_acquired is not None:
            callback_started = True
            on_acquired(
                lease_record, slot, owned_slot_identity, claim_identity
            )
        return lease_record, slot
    except BaseException as error:
        dominant_error = error
        dominant_traceback = error.__traceback__
        if foreign_slot:
            raise
        if owned_slot_identity is None:
            error.add_note(
                "simulator-device lease ownership was not established; any extant path was preserved"
            )
            raise
        cleanup_succeeded = False
        try:
            cleanup_exclusively_created_lease_slot(
                slot, owned_slot_identity, claim_identity
            )
            cleanup_succeeded = True
        except (EvidenceError, OSError) as cleanup_error:
            detail = (
                "simulator-device lease acquisition cleanup failed: "
                f"{cleanup_error}"
            )
            if isinstance(error, Exception):
                raise EvidenceError(detail) from error
            error.add_note(detail)
        if (
            cleanup_succeeded
            and callback_started
            and on_rollback is not None
            and claim_identity is not None
        ):
            try:
                on_rollback(
                    lease_record, slot, owned_slot_identity, claim_identity
                )
            except BaseException as rollback_error:
                if not isinstance(rollback_error, Exception) and isinstance(
                    dominant_error, Exception
                ):
                    rollback_error.add_note(
                        "simulator-device lease acquisition had already failed with: "
                        f"{type(dominant_error).__name__}"
                    )
                    dominant_error = rollback_error
                    dominant_traceback = rollback_error.__traceback__
                else:
                    dominant_error.add_note(
                        "simulator-device lease finalizer rollback also failed: "
                        f"{type(rollback_error).__name__}"
                    )
        raise dominant_error.with_traceback(dominant_traceback)


def release_command_lease(
    lease: dict[str, Any],
    owned_slot: Path | None,
    expected_identity: tuple[int, int],
    expected_claim_identity: tuple[int, int],
    *,
    package: str,
    assertion: str,
    attempt: str,
    owner: str,
    command_digest: str,
    trigger: str,
) -> None:
    if owned_slot is None:
        return
    if (
        private_directory_identity(owned_slot, "owned simulator-device lease")
        != expected_identity
    ):
        raise EvidenceError("refusing to release a replaced simulator-device lease")
    existing = read_claim(owned_slot)
    if not existing:
        raise EvidenceError("owned simulator-device lease metadata disappeared")
    if (
        existing.get("scope") != "command"
        or existing.get("packageId") != package
        or existing.get("assertionId") != assertion
        or existing.get("attemptId") != attempt
        or existing.get("ownerTaskId") != owner
        or existing.get("pid") != os.getpid()
        or existing.get("commandDigest") != command_digest
        or existing.get("trigger") != trigger
    ):
        raise EvidenceError("refusing to release another owner's simulator-device lease")
    cleanup_exclusively_created_lease_slot(
        owned_slot, expected_identity, expected_claim_identity
    )
    lease["released"] = True
    lease["releasedAt"] = utc_now()


def validate_retry(
    context: AttemptContext,
    retry_of: str | None,
    reason: str | None,
    *,
    invocation: dict[str, Any],
    primary_artifact: str,
) -> dict[str, Any] | None:
    if retry_of is None:
        if reason:
            raise EvidenceError("--reason is valid only with --retry-of")
        return None
    validate_component(retry_of, "retry attempt ID")
    if not reason or not reason.strip():
        raise EvidenceError("a retry requires a non-empty --reason")
    if retry_of == context.attempt:
        raise EvidenceError("a retry cannot reference itself")
    original_root, _ = context.referenced_attempt_root(retry_of)
    manifest_path = original_root / "manifest.json"
    require_private_regular_file(manifest_path, "retry source manifest")
    manifest = read_json(manifest_path)
    if not isinstance(manifest, dict):
        raise EvidenceError("retry source manifest is malformed")
    expected = {
        "packageId": context.package,
        "headSetDigest": context.head_set_digest,
        "assertionId": context.assertion,
        "attemptId": retry_of,
    }
    for key, value in expected.items():
        if manifest.get(key) != value:
            raise EvidenceError(f"retry source has incompatible {key}")
    if manifest.get("status") not in {"failed", "locked", "blocked"}:
        raise EvidenceError("only a failed, locked, or blocked attempt may be retried")
    if manifest.get("retryOf") is not None:
        raise EvidenceError("retry chains are prohibited; only one exact retry is allowed")
    if manifest.get("primaryArtifact") != primary_artifact:
        raise EvidenceError("retry primary artifact differs from the original attempt")
    if manifest.get("source", {}).get("cwd") != str(context.cwd):
        raise EvidenceError("retry source worktree differs from the original attempt")
    original_result = manifest.get("result")
    if (
        not isinstance(original_result, dict)
        or original_result.get("invocation") != invocation
    ):
        raise EvidenceError("retry invocation differs from the original attempt")
    for sibling in context.attempts_root.iterdir():
        context._reject_symlink_components(
            context.attempts_root, sibling, "attempt sibling"
        )
        sibling_manifest = sibling / "manifest.json"
        if sibling_manifest == manifest_path or not sibling_manifest.is_file():
            continue
        require_private_regular_file(sibling_manifest, "attempt sibling manifest")
        value = read_json(sibling_manifest)
        if isinstance(value, dict) and value.get("retryOf") == retry_of:
            raise EvidenceError("an exact retry already exists for this attempt")
    retry_claims = context.attempts_root.parent / "retry-claims"
    create_private_directory(retry_claims, "retry claim collection")
    retry_claim = retry_claims / retry_of
    try:
        create_private_directory(retry_claim, "retry claim", exclusive=True)
    except FileExistsError as error:
        raise EvidenceError("an exact retry is already reserved for this attempt") from error
    write_json_exclusive(
        retry_claim / "claim.json",
        {
            "schemaVersion": 1,
            "packageId": context.package,
            "headSetDigest": context.head_set_digest,
            "assertionId": context.assertion,
            "retryOf": retry_of,
            "retryAttemptId": context.attempt,
            "invocationSha256": sha256_bytes(canonical_json_bytes(invocation)),
            "reservedAt": utc_now(),
        },
    )
    return {
        "attemptId": retry_of,
        "manifestSha256": sha256_file(manifest_path),
        "reason": reason.strip(),
        "claim": str(retry_claim / "claim.json"),
    }


def flatten_gh_pages(value: Any, label: str) -> list[dict[str, Any]]:
    if not isinstance(value, list) or not value:
        raise EvidenceError(f"{label} must be a non-empty --paginate --slurp page array")
    if not all(isinstance(page, list) for page in value):
        raise EvidenceError(f"{label} is not a complete --paginate --slurp capture")
    flattened: list[dict[str, Any]] = []
    for page in value:
        for item in page:
            if not isinstance(item, dict):
                raise EvidenceError(f"{label} page contains a non-object")
            flattened.append(item)
    return flattened


def parse_worktrees(value: bytes) -> list[dict[str, Any]]:
    try:
        text = value.decode("utf-8")
    except UnicodeDecodeError as error:
        raise EvidenceError("worktree capture is not UTF-8") from error
    blocks = [block for block in text.strip().split("\n\n") if block.strip()]
    if not blocks:
        raise EvidenceError("worktree capture matched zero worktrees")
    normalized: list[dict[str, Any]] = []
    seen: set[str] = set()
    for block in blocks:
        record: dict[str, Any] = {"detached": False, "locked": False}
        for line in block.splitlines():
            key, _, raw_value = line.partition(" ")
            if key == "worktree":
                record["path"] = raw_value
            elif key == "HEAD":
                record["head"] = raw_value.lower()
            elif key == "branch":
                record["branch"] = raw_value.removeprefix("refs/heads/")
            elif key == "detached":
                record["detached"] = True
            elif key == "locked":
                record["locked"] = True
                record["lockedReason"] = raw_value or None
            elif key == "prunable":
                record["prunable"] = True
                record["prunableReason"] = raw_value or None
            elif key in {"bare"}:
                record[key] = True
            else:
                raise EvidenceError(f"unknown worktree porcelain field: {key}")
        path = record.get("path")
        head = record.get("head")
        if not isinstance(path, str) or not path.startswith("/"):
            raise EvidenceError("worktree capture contains an invalid path")
        if not isinstance(head, str) or not FULL_SHA.fullmatch(head):
            raise EvidenceError(f"worktree {path} has an invalid HEAD")
        state_count = int(isinstance(record.get("branch"), str)) + int(record["detached"]) + int(bool(record.get("bare")))
        if state_count != 1:
            raise EvidenceError(
                f"worktree {path} must identify exactly one branch/detached/bare state"
            )
        if path in seen:
            raise EvidenceError(f"duplicate worktree path: {path}")
        seen.add(path)
        normalized.append(record)
    return sorted(normalized, key=lambda item: item["path"])


def parse_prs(value: Any, repository: str) -> list[dict[str, Any]]:
    items = flatten_gh_pages(value, f"{repository} PR capture")
    normalized: list[dict[str, Any]] = []
    seen: set[int] = set()
    for item in items:
        number = item.get("number")
        head = item.get("head")
        base = item.get("base")
        if (
            not isinstance(number, int)
            or not isinstance(head, dict)
            or not isinstance(base, dict)
            or not FULL_SHA.fullmatch(str(head.get("sha", "")))
            or not FULL_SHA.fullmatch(str(base.get("sha", "")))
            or not isinstance(head.get("ref"), str)
            or not isinstance(base.get("ref"), str)
            or item.get("state") != "open"
        ):
            raise EvidenceError(f"{repository} PR capture contains a malformed PR")
        if number in seen:
            raise EvidenceError(f"duplicate {repository} PR number: {number}")
        seen.add(number)
        normalized.append(
            {
                "number": number,
                "state": item["state"],
                "draft": bool(item.get("draft", False)),
                "head": head["sha"].lower(),
                "headRef": head["ref"],
                "base": base["sha"].lower(),
                "baseRef": base["ref"],
                "url": item.get("html_url"),
            }
        )
    return sorted(normalized, key=lambda item: item["number"])


def parse_branches(value: Any, repository: str) -> list[dict[str, Any]]:
    items = flatten_gh_pages(value, f"{repository} branch capture")
    if not items:
        raise EvidenceError(f"{repository} branch capture matched zero branches")
    normalized: list[dict[str, Any]] = []
    seen: set[str] = set()
    for item in items:
        name = item.get("name")
        commit = item.get("commit")
        if (
            not isinstance(name, str)
            or not name
            or not isinstance(commit, dict)
            or not FULL_SHA.fullmatch(str(commit.get("sha", "")))
        ):
            raise EvidenceError(f"{repository} branch capture contains a malformed branch")
        if name in seen:
            raise EvidenceError(f"duplicate {repository} branch: {name}")
        seen.add(name)
        normalized.append(
            {
                "name": name,
                "head": commit["sha"].lower(),
                "protected": bool(item.get("protected", False)),
            }
        )
    return sorted(normalized, key=lambda item: item["name"])


def canonical_repository_name(value: str) -> str | None:
    normalized = value.casefold().rstrip("/")
    if normalized.endswith(".git"):
        normalized = normalized[:-4]
    if normalized in {"chapterflow-ios", "willsoltani/chapterflow-ios"}:
        return "ios"
    if normalized in {"chapterflow", "willsoltani/chapterflow"}:
        return "backend"
    return None


def github_repository_identity(value: str) -> tuple[str, str] | None:
    remote = value.strip()
    scp_match = re.fullmatch(
        r"git@github\.com:([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+?)(?:\.git)?",
        remote,
        flags=re.IGNORECASE,
    )
    if scp_match:
        return scp_match.group(1).casefold(), scp_match.group(2).casefold()
    try:
        parsed = urlsplit(remote)
        port = parsed.port
    except ValueError:
        return None
    if parsed.query or parsed.fragment or port is not None:
        return None
    if parsed.scheme == "https":
        if (
            parsed.hostname != "github.com"
            or parsed.username is not None
            or parsed.password is not None
        ):
            return None
    elif parsed.scheme == "ssh":
        if parsed.hostname != "github.com" or parsed.username != "git":
            return None
    else:
        return None
    path_match = re.fullmatch(
        r"/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+?)(?:\.git)?/?",
        parsed.path,
    )
    if path_match is None:
        return None
    return path_match.group(1).casefold(), path_match.group(2).casefold()


def git_common_directory(repository: Path) -> Path:
    value = git_output(repository, ["rev-parse", "--git-common-dir"])
    path = Path(value)
    if not path.is_absolute():
        path = repository / path
    return path.resolve(strict=True)


def validate_backend_repository(value: str) -> Path:
    backend_root = Path(value).expanduser().resolve(strict=True)
    if not backend_root.is_dir() or repository_root(backend_root) != backend_root:
        raise EvidenceError(
            "backend repository must name its canonical worktree root"
        )
    remote = git_output(backend_root, ["remote", "get-url", "origin"])
    if github_repository_identity(remote) != ("willsoltani", "chapterflow"):
        raise EvidenceError(
            "backend repository origin must be github.com/WillSoltani/ChapterFlow"
        )
    git_common_directory(backend_root)
    return backend_root


def recovery_repository_bindings(
    ios_root: Path,
    backend_root: Path,
    declared_backend_source_head: str,
) -> dict[str, dict[str, Any]]:
    verified_backend = validate_backend_repository(str(backend_root))
    verified_ios = repository_root(ios_root)
    if not FULL_SHA.fullmatch(declared_backend_source_head):
        raise EvidenceError("declared backend source head is not a full commit SHA")
    source_object = subprocess.run(
        [
            "git",
            "cat-file",
            "-e",
            f"{declared_backend_source_head}^{{commit}}",
        ],
        cwd=verified_backend,
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        env=git_discovery_environment(),
    )
    if source_object.returncode != 0:
        raise EvidenceError("declared backend source head is unavailable in backend ODB")
    local_checkout_head = git_output(verified_backend, ["rev-parse", "HEAD"]).lower()
    local_dirty, local_status_digest = run_git_status(verified_backend)
    if local_dirty is None or local_status_digest is None:
        raise EvidenceError("cannot bind protected backend checkout state")
    return {
        "backend": {
            "root": str(verified_backend),
            "repository": "WillSoltani/ChapterFlow",
            "origin": "github.com/WillSoltani/ChapterFlow",
            "commonGitDir": str(git_common_directory(verified_backend)),
            "declaredSourceHead": declared_backend_source_head.lower(),
            "localCheckoutHead": local_checkout_head,
            "localStatusSha256": local_status_digest,
            "localDirty": local_dirty,
        },
        "ios": {
            "root": str(verified_ios),
            "commonGitDir": str(git_common_directory(verified_ios)),
        },
    }


def successor_package_map(cwd: Path) -> dict[tuple[str, str], dict[str, str]]:
    workstreams = cwd / "upgrade" / "workstreams"
    mapping: dict[tuple[str, str], dict[str, str]] = {}
    if not workstreams.is_dir():
        return mapping
    for path in sorted(workstreams.glob("*/WP-*/package.json")):
        value = read_json(path)
        if not isinstance(value, dict) or not isinstance(value.get("git"), dict):
            continue
        branch = value["git"].get("branch")
        repository = value["git"].get("repository")
        package_id = value.get("id")
        if (
            not isinstance(branch, str)
            or not isinstance(repository, str)
            or not isinstance(package_id, str)
        ):
            continue
        repository_name = canonical_repository_name(repository)
        if repository_name is None:
            continue
        key = (repository_name, branch)
        if key in mapping:
            raise EvidenceError(
                f"duplicate planned package branch: {repository_name}:{branch}"
            )
        mapping[key] = {
            "packageId": package_id,
            "evidence": path.relative_to(cwd).as_posix(),
        }
    return mapping


def consume_capture(
    context: AttemptContext, reference: str, expected_command: Sequence[str]
) -> bytes:
    value = context.input_bytes(reference)
    input_record = context.inputs[-1]
    manifest_path = Path(input_record["manifestPath"])
    manifest_bytes = manifest_path.read_bytes()
    if sha256_bytes(manifest_bytes) != input_record["manifestSha256"]:
        raise EvidenceError(f"capture manifest changed while being read: {reference}")
    manifest = read_json_bytes(manifest_bytes, str(manifest_path))
    result = manifest.get("result") if isinstance(manifest, dict) else None
    command = result.get("command") if isinstance(result, dict) else None
    declared = command.get("declared") if isinstance(command, dict) else None
    if declared != list(expected_command):
        raise EvidenceError(
            f"capture {reference} was not produced by the declared literal command"
        )
    if expected_command[:3] == ["gh", "api", "--paginate"]:
        tool = result.get("tool") if isinstance(result, dict) else None
        if (
            not isinstance(tool, dict)
            or not isinstance(tool.get("version"), str)
            or tool.get("authHost") != "github.com"
            or tool.get("authVerified") is not True
            or not isinstance(manifest.get("observedAt"), str)
        ):
            raise EvidenceError(f"GitHub capture provenance is incomplete: {reference}")
    return value


def consume_backend_worktree_capture(
    context: AttemptContext, reference: str, backend_root: Path
) -> bytes:
    value = context.input_bytes(reference)
    input_record = context.inputs[-1]
    manifest_path = Path(input_record["manifestPath"])
    manifest_bytes = manifest_path.read_bytes()
    if sha256_bytes(manifest_bytes) != input_record["manifestSha256"]:
        raise EvidenceError(f"capture manifest changed while being read: {reference}")
    manifest = read_json_bytes(manifest_bytes, str(manifest_path))
    result = manifest.get("result") if isinstance(manifest, dict) else None
    command = result.get("command") if isinstance(result, dict) else None
    declared = command.get("declared") if isinstance(command, dict) else None
    if (
        not isinstance(declared, list)
        or len(declared) != 6
        or declared[0:2] != ["git", "-C"]
        or declared[3:] != ["worktree", "list", "--porcelain"]
        or not isinstance(declared[2], str)
    ):
        raise EvidenceError(
            f"backend worktree capture {reference} must use "
            "git -C <backend-repository> worktree list --porcelain"
        )
    declared_root = Path(declared[2]).expanduser().resolve(strict=True)
    verified_backend = validate_backend_repository(str(backend_root))
    if declared_root != verified_backend:
        raise EvidenceError(
            "backend worktree capture used a different repository root"
        )
    tool = result.get("tool") if isinstance(result, dict) else None
    if (
        not isinstance(tool, dict)
        or not isinstance(tool.get("version"), str)
        or not isinstance(manifest.get("observedAt"), str)
    ):
        raise EvidenceError(f"backend worktree capture provenance is incomplete: {reference}")
    return value


def validate_recovery_inventory_provenance(
    context: AttemptContext,
    input_record: dict[str, Any],
    inventory_ref: str,
    backend_root: Path,
) -> None:
    manifest_path = Path(input_record["manifestPath"])
    manifest_bytes = read_regular_bytes(manifest_path)
    if sha256_bytes(manifest_bytes) != input_record["manifestSha256"]:
        raise EvidenceError(
            f"inventory source manifest changed while being read: {inventory_ref}"
        )
    manifest = read_json_bytes(manifest_bytes, str(manifest_path))
    result = manifest.get("result") if isinstance(manifest, dict) else None
    invocation = result.get("invocation") if isinstance(result, dict) else None
    if (
        not isinstance(manifest, dict)
        or manifest.get("primaryArtifact") != input_record["path"]
        or not isinstance(result, dict)
        or result.get("mode") != "build-recovery-inventory"
        or not isinstance(invocation, dict)
        or invocation.get("mode") != "build-recovery-inventory"
        or invocation.get("backendRepository") != str(backend_root)
    ):
        raise EvidenceError(
            "recovery inventory must come from the provenance-bound built-in mode"
        )


def build_recovery_inventory(
    context: AttemptContext,
    *,
    backend_root: Path,
    worktrees_ref: str,
    backend_worktrees_ref: str,
    ios_prs_ref: str,
    backend_prs_ref: str,
    ios_branches_ref: str,
    backend_branches_ref: str,
) -> dict[str, Any]:
    declared_backend_source_head = required_repository_head(
        context.repositories, "backend"
    )
    ios_worktrees = parse_worktrees(
        consume_capture(
            context,
            worktrees_ref,
            ["git", "worktree", "list", "--porcelain"],
        )
    )
    backend_worktrees = parse_worktrees(
        consume_backend_worktree_capture(
            context, backend_worktrees_ref, backend_root
        )
    )
    ios_prs = parse_prs(
        read_json_bytes(
            consume_capture(
                context,
                ios_prs_ref,
                [
                    "gh",
                    "api",
                    "--paginate",
                    "--slurp",
                    "repos/WillSoltani/Chapterflow-IOS/pulls?state=open&per_page=100",
                ],
            ),
            ios_prs_ref,
        ),
        "ios",
    )
    backend_prs = parse_prs(
        read_json_bytes(
            consume_capture(
                context,
                backend_prs_ref,
                [
                    "gh",
                    "api",
                    "--paginate",
                    "--slurp",
                    "repos/WillSoltani/ChapterFlow/pulls?state=open&per_page=100",
                ],
            ),
            backend_prs_ref,
        ),
        "backend",
    )
    ios_branches = parse_branches(
        read_json_bytes(
            consume_capture(
                context,
                ios_branches_ref,
                [
                    "gh",
                    "api",
                    "--paginate",
                    "--slurp",
                    "repos/WillSoltani/Chapterflow-IOS/branches?per_page=100",
                ],
            ),
            ios_branches_ref,
        ),
        "ios",
    )
    backend_branches = parse_branches(
        read_json_bytes(
            consume_capture(
                context,
                backend_branches_ref,
                [
                    "gh",
                    "api",
                    "--paginate",
                    "--slurp",
                    "repos/WillSoltani/ChapterFlow/branches?per_page=100",
                ],
            ),
            backend_branches_ref,
        ),
        "backend",
    )
    links = successor_package_map(context.cwd)
    candidates: list[dict[str, Any]] = []
    for repository, worktrees in (
        ("ios", ios_worktrees),
        ("backend", backend_worktrees),
    ):
        for item in worktrees:
            candidate = {
                "candidateId": f"{repository}:worktree:{item['path']}",
                "repository": repository,
                "kind": "worktree",
                **item,
            }
            branch = item.get("branch")
            if isinstance(branch, str) and (repository, branch) in links:
                candidate["successorPackage"] = links[(repository, branch)]
            candidates.append(candidate)
    for repository, prs in (("ios", ios_prs), ("backend", backend_prs)):
        for item in prs:
            candidate = {
                "candidateId": f"{repository}:pr:{item['number']}",
                "repository": repository,
                "kind": "pr",
                **item,
            }
            if (repository, item["headRef"]) in links:
                candidate["successorPackage"] = links[(repository, item["headRef"])]
            candidates.append(candidate)
    for repository, branches in (
        ("ios", ios_branches),
        ("backend", backend_branches),
    ):
        for item in branches:
            candidate = {
                "candidateId": f"{repository}:branch:{item['name']}",
                "repository": repository,
                "kind": "branch",
                **item,
            }
            if (repository, item["name"]) in links:
                candidate["successorPackage"] = links[(repository, item["name"])]
            candidates.append(candidate)
    candidates.sort(key=lambda item: item["candidateId"])
    ids = [item["candidateId"] for item in candidates]
    if len(ids) != len(set(ids)):
        raise EvidenceError("recovery inventory contains duplicate candidate IDs")
    return {
        "schemaVersion": RECOVERY_INVENTORY_SCHEMA_VERSION,
        "headSetDigest": context.head_set_digest,
        "repositoryBindings": recovery_repository_bindings(
            context.cwd, backend_root, declared_backend_source_head
        ),
        "sources": sorted(context.inputs, key=lambda item: item["reference"]),
        "counts": {
            "worktrees": len(ios_worktrees) + len(backend_worktrees),
            "iosWorktrees": len(ios_worktrees),
            "backendWorktrees": len(backend_worktrees),
            "iosOpenPRs": len(ios_prs),
            "backendOpenPRs": len(backend_prs),
            "iosBranches": len(ios_branches),
            "backendBranches": len(backend_branches),
            "candidates": len(candidates),
        },
        "candidates": candidates,
    }


def run_git_status(path: Path) -> tuple[bool | None, str | None]:
    result = subprocess.run(
        ["git", "-C", str(path), "status", "--porcelain=v2", "--branch"],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=git_discovery_environment(),
    )
    if result.returncode != 0:
        return None, None
    lines = result.stdout.splitlines()
    dirty = any(line and not line.startswith("#") for line in lines)
    digest = sha256_bytes(result.stdout.encode("utf-8"))
    return dirty, digest


def worktree_open_files(path: Path) -> dict[str, Any]:
    executable = shutil.which("lsof")
    if executable is None:
        return {"available": False, "count": None, "pids": []}
    try:
        result = subprocess.run(
            [executable, "-Fn", "+D", str(path)],
            check=False,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
        )
    except subprocess.TimeoutExpired:
        return {"available": False, "count": None, "pids": [], "timedOut": True}
    pids = sorted(
        {
            int(line[1:])
            for line in result.stdout.splitlines()
            if line.startswith("p") and line[1:].isdigit()
        }
    )
    if result.returncode not in {0, 1} or result.stderr.strip():
        return {
            "available": False,
            "count": None,
            "pids": [],
            "exitCode": result.returncode,
            "stderrSha256": sha256_bytes(result.stderr.encode("utf-8")),
        }
    return {"available": True, "count": len(pids), "pids": pids}


def live_worktree_registry(repository: Path) -> list[dict[str, Any]]:
    return parse_worktrees(
        git_bytes(
            repository,
            ["worktree", "list", "--porcelain"],
            "live worktree registry",
        )
    )


def worktree_registry_projection(record: dict[str, Any]) -> dict[str, Any]:
    return {
        "path": record.get("path"),
        "head": record.get("head"),
        "branch": record.get("branch"),
        "detached": bool(record.get("detached")),
        "bare": bool(record.get("bare")),
        "locked": bool(record.get("locked")),
        "prunable": bool(record.get("prunable")),
    }


def direct_worktree_state(
    path: Path, expected_common_git_dir: Path
) -> dict[str, Any]:
    try:
        canonical = path.resolve(strict=True)
    except OSError as error:
        raise EvidenceError("worktree path is unavailable") from error
    if canonical != path or str(path) != str(canonical):
        raise EvidenceError("worktree path is not canonical")
    if repository_root(canonical) != canonical:
        raise EvidenceError("worktree path is not its canonical repository root")
    if git_common_directory(canonical) != expected_common_git_dir:
        raise EvidenceError("worktree belongs to a different Git registry")
    head = git_output(canonical, ["rev-parse", "HEAD"]).lower()
    if not FULL_SHA.fullmatch(head):
        raise EvidenceError("live worktree HEAD is not a full commit SHA")
    branch = git_output(canonical, ["branch", "--show-current"], check=False)
    return {
        "path": str(canonical),
        "head": head,
        "branch": branch or None,
        "detached": not bool(branch),
        "bare": False,
    }


def git_relationship(cwd: Path, head: str, target: str) -> dict[str, Any]:
    exists = subprocess.run(
        ["git", "cat-file", "-e", f"{head}^{{commit}}"],
        cwd=cwd,
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        env=git_discovery_environment(),
    ).returncode == 0
    if not exists:
        return {"disposition": "unsafe-to-touch", "reason": "commit-object-unavailable"}
    head_tree = git_output(cwd, ["rev-parse", f"{head}^{{tree}}"])
    target_tree = git_output(cwd, ["rev-parse", f"{target}^{{tree}}"])
    diff = subprocess.run(
        ["git", "diff", "--binary", target, head],
        cwd=cwd,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=git_discovery_environment(),
    )
    if diff.returncode != 0:
        return {"disposition": "unsafe-to-touch", "reason": "diff-unavailable"}
    evidence = {
        "headTree": head_tree,
        "targetTree": target_tree,
        "targetDiffSha256": sha256_bytes(diff.stdout),
    }
    contained = subprocess.run(
        ["git", "merge-base", "--is-ancestor", head, target],
        cwd=cwd,
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        env=git_discovery_environment(),
    )
    if contained.returncode not in {0, 1}:
        return {**evidence, "disposition": "unsafe-to-touch", "reason": "git-ancestry-failed"}
    if head == target or contained.returncode == 0:
        return {**evidence, "disposition": "merged", "reason": "head-contained-in-target"}
    if head_tree == target_tree:
        return {**evidence, "disposition": "stale", "reason": "tree-equivalent-to-target"}
    descendant = subprocess.run(
        ["git", "merge-base", "--is-ancestor", target, head],
        cwd=cwd,
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        env=git_discovery_environment(),
    )
    if descendant.returncode not in {0, 1}:
        return {**evidence, "disposition": "unsafe-to-touch", "reason": "git-ancestry-failed"}
    if descendant.returncode == 0:
        return {**evidence, "disposition": "novel", "reason": "head-ahead-of-target"}
    unique_result = subprocess.run(
        [
            "git",
            "log",
            "--cherry-pick",
            "--right-only",
            "--no-merges",
            "--format=%H",
            f"{target}...{head}",
        ],
        cwd=cwd,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=git_discovery_environment(),
    )
    if unique_result.returncode != 0:
        return {**evidence, "disposition": "unsafe-to-touch", "reason": "git-log-failed"}
    unique = unique_result.stdout.strip()
    if unique:
        return {**evidence, "disposition": "novel", "reason": "diverged-with-unique-patches"}
    return {
        **evidence,
        "disposition": "unsafe-to-touch",
        "reason": "diverged-without-proven-equivalence",
    }


def classify_recovery_inventory(
    context: AttemptContext,
    inventory_ref: str,
    targets: Sequence[str],
    backend_root: Path,
) -> dict[str, Any]:
    inventory_bytes = context.input_bytes(inventory_ref)
    inventory_input = context.inputs[-1]
    validate_recovery_inventory_provenance(
        context, inventory_input, inventory_ref, backend_root
    )
    inventory = read_json_bytes(inventory_bytes, inventory_ref)
    if (
        not isinstance(inventory, dict)
        or inventory.get("schemaVersion") != RECOVERY_INVENTORY_SCHEMA_VERSION
    ):
        raise EvidenceError("recovery inventory is malformed")
    candidates = inventory.get("candidates")
    if not isinstance(candidates, list) or not candidates:
        raise EvidenceError("recovery inventory candidates are malformed")
    counts = inventory.get("counts")
    sources = inventory.get("sources")
    if (
        inventory.get("headSetDigest") != context.head_set_digest
        or not isinstance(counts, dict)
        or counts.get("candidates") != len(candidates)
        or not isinstance(sources, list)
        or len(sources) != 6
    ):
        raise EvidenceError("recovery inventory metadata is incomplete or inconsistent")
    declared_backend_source_head = required_repository_head(
        context.repositories, "backend"
    )
    expected_bindings = recovery_repository_bindings(
        context.cwd, backend_root, declared_backend_source_head
    )
    if inventory.get("repositoryBindings") != expected_bindings:
        raise EvidenceError(
            "recovery inventory repository bindings do not match current repositories"
        )
    graph_roots = {"ios": context.cwd, "backend": backend_root}
    target_map: dict[str, str] = {}
    for raw in targets:
        repository, revision = raw.split("=", 1) if "=" in raw else ("ios", raw)
        validate_component(repository, "target repository")
        if repository in target_map or not FULL_SHA.fullmatch(revision):
            raise EvidenceError(f"invalid or duplicate --target: {raw!r}")
        if repository not in graph_roots:
            raise EvidenceError(f"unsupported --target repository: {repository}")
        target_map[repository] = revision.lower()
    if not target_map:
        raise EvidenceError("classification requires at least one --target")
    if set(target_map) != set(graph_roots):
        raise EvidenceError("classification requires exactly one iOS and backend target")
    if target_map.get("backend") != declared_backend_source_head:
        raise EvidenceError(
            "backend classification target must equal declared backend source head"
        )
    for repository, target in target_map.items():
        target_exists = subprocess.run(
            ["git", "cat-file", "-e", f"{target}^{{commit}}"],
            cwd=graph_roots[repository],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env=git_discovery_environment(),
        ).returncode == 0
        if not target_exists:
            raise EvidenceError(
                f"{repository} classification target object is unavailable"
            )
    initial_registries = {
        repository: live_worktree_registry(root)
        for repository, root in graph_roots.items()
    }
    live_rows = {
        repository: {item["path"]: item for item in rows}
        for repository, rows in initial_registries.items()
    }
    classified: list[dict[str, Any]] = []
    seen: set[str] = set()
    current_branch = git_output(context.cwd, ["branch", "--show-current"], check=False)
    current_root = str(repository_root(context.cwd))
    for candidate in sorted(candidates, key=lambda item: str(item.get("candidateId"))):
        if not isinstance(candidate, dict) or not isinstance(candidate.get("candidateId"), str):
            raise EvidenceError("recovery inventory contains a malformed candidate")
        candidate_id = candidate["candidateId"]
        if candidate_id in seen:
            raise EvidenceError(f"duplicate recovery candidate: {candidate_id}")
        seen.add(candidate_id)
        repository = candidate.get("repository")
        kind = candidate.get("kind")
        head = candidate.get("head")
        if (
            not isinstance(repository, str)
            or not isinstance(kind, str)
            or not isinstance(head, str)
            or not FULL_SHA.fullmatch(head)
        ):
            raise EvidenceError(f"candidate lacks repository/kind/head: {candidate_id}")
        if repository not in graph_roots:
            raise EvidenceError(
                f"candidate identifies an unsupported repository: {candidate_id}"
            )
        result: dict[str, Any]
        branch = candidate.get("branch") or candidate.get("name") or candidate.get("headRef")
        declared_frozen = repository == "ios" and (
            candidate.get("number") == 117 or branch == "codex/wp-rel-01"
        )
        worktree_path: Path | None = None
        worktree_state_before: dict[str, Any] | None = None
        worktree_guard_failure: str | None = None
        if kind == "worktree":
            raw_path = candidate.get("path")
            if not isinstance(raw_path, str) or not raw_path.startswith("/"):
                raise EvidenceError(f"worktree candidate has an invalid path: {candidate_id}")
            worktree_path = Path(raw_path)
            live_row = live_rows[repository].get(raw_path)
            if live_row is None:
                worktree_guard_failure = "worktree-missing-from-live-registry"
            elif (
                bool(candidate.get("locked"))
                or bool(candidate.get("prunable"))
                or bool(live_row.get("locked"))
                or bool(live_row.get("prunable"))
            ):
                worktree_guard_failure = "locked-or-prunable-worktree"
            elif worktree_registry_projection(candidate) != worktree_registry_projection(
                live_row
            ):
                worktree_guard_failure = "worktree-registry-drift"
            elif bool(live_row.get("bare")):
                worktree_guard_failure = "bare-worktree-is-not-classifiable"
            else:
                try:
                    worktree_state_before = direct_worktree_state(
                        worktree_path,
                        Path(expected_bindings[repository]["commonGitDir"]),
                    )
                except (EvidenceError, OSError):
                    worktree_guard_failure = "worktree-live-state-unverified"
                else:
                    direct_projection = {
                        key: worktree_state_before[key]
                        for key in ("path", "head", "branch", "detached", "bare")
                    }
                    live_projection = {
                        key: worktree_registry_projection(live_row)[key]
                        for key in ("path", "head", "branch", "detached", "bare")
                    }
                    if direct_projection != live_projection:
                        worktree_guard_failure = "worktree-direct-state-drift"

        if declared_frozen:
            result = {"disposition": "frozen", "reason": "declared-frozen-release-work"}
            if worktree_guard_failure is not None:
                result["worktreeGuard"] = worktree_guard_failure
        elif worktree_guard_failure is not None:
            result = {
                "disposition": "unsafe-to-touch",
                "reason": worktree_guard_failure,
            }
        elif (
            repository == "ios"
            and kind == "worktree"
            and candidate.get("path") == "/Users/radinsoltani/Chapterflow-IOS"
        ):
            assert worktree_path is not None
            dirty, status_digest = run_git_status(worktree_path)
            result = {
                "disposition": "unsafe-to-touch",
                "reason": "protected-primary-checkout",
                "dirty": dirty,
                "statusSha256": status_digest,
            }
        elif repository == "ios" and kind == "worktree" and (
            candidate.get("path") == current_root or branch == current_branch
        ):
            result = {"disposition": "active", "reason": "current-package-worktree"}
        elif kind == "worktree" and repository not in target_map:
            result = {"disposition": "unsafe-to-touch", "reason": "target-not-declared"}
        elif kind == "worktree":
            assert worktree_path is not None
            dirty, status_digest = run_git_status(worktree_path)
            open_files = worktree_open_files(worktree_path)
            if dirty is None or not open_files.get("available"):
                result = {
                    "disposition": "unsafe-to-touch",
                    "reason": "worktree-liveness-incomplete",
                }
            elif dirty:
                result = {
                    "disposition": "unsafe-to-touch",
                    "reason": "dirty-owner-worktree",
                }
            elif int(open_files.get("count") or 0) > 0:
                result = {"disposition": "active", "reason": "live-open-files"}
            else:
                result = git_relationship(
                    graph_roots[repository], head, target_map[repository]
                )
                dirty_after, status_digest_after = run_git_status(worktree_path)
                open_files_after = worktree_open_files(worktree_path)
                if (
                    dirty_after is None
                    or dirty_after
                    or status_digest_after != status_digest
                    or not open_files_after.get("available")
                    or open_files_after != open_files
                ):
                    result = {
                        "disposition": "unsafe-to-touch",
                        "reason": "worktree-liveness-drift",
                    }
                result["statusAfterSha256"] = status_digest_after
                result["openFilesAfter"] = open_files_after
            result["dirty"] = dirty
            result["statusSha256"] = status_digest
            result["openFiles"] = open_files
        elif kind == "pr" and str(candidate.get("state", "")).casefold() == "open":
            result = {"disposition": "active", "reason": "open-pull-request"}
        elif repository == "ios" and branch == current_branch:
            result = {"disposition": "active", "reason": "current-package-branch"}
        elif repository not in target_map:
            result = {"disposition": "unsafe-to-touch", "reason": "target-not-declared"}
        else:
            result = git_relationship(
                graph_roots[repository], head, target_map[repository]
            )
        if worktree_state_before is not None:
            assert worktree_path is not None
            try:
                worktree_state_after = direct_worktree_state(
                    worktree_path,
                    Path(expected_bindings[repository]["commonGitDir"]),
                )
            except (EvidenceError, OSError) as error:
                raise EvidenceError(
                    f"worktree changed while being classified: {candidate_id}"
                ) from error
            if worktree_state_after != worktree_state_before:
                raise EvidenceError(
                    f"worktree changed while being classified: {candidate_id}"
                )
        classified.append(
            {
                "candidateId": candidate_id,
                "repository": repository,
                "kind": kind,
                "head": head,
                **result,
            }
        )
    if len(classified) != len(candidates):
        raise EvidenceError("classification did not emit exactly one row per candidate")
    final_registries = {
        repository: live_worktree_registry(root)
        for repository, root in graph_roots.items()
    }
    if final_registries != initial_registries:
        raise EvidenceError("worktree registry changed during recovery classification")
    counts: dict[str, int] = {}
    for item in classified:
        disposition = item["disposition"]
        counts[disposition] = counts.get(disposition, 0) + 1
    return {
        "schemaVersion": RECOVERY_INVENTORY_SCHEMA_VERSION,
        "inventoryReference": inventory_ref,
        "inputSha256": sha256_bytes(inventory_bytes),
        "targets": [
            {"repository": repository, "head": target_map[repository]}
            for repository in sorted(target_map)
        ],
        "counts": counts,
        "classifications": classified,
    }


def parse_sha256_value(value: bytes) -> str:
    try:
        decoded = json.loads(value.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        decoded = None
    candidates: list[str] = []
    if isinstance(decoded, dict):
        for key in ("sha256", "digest", "value"):
            if isinstance(decoded.get(key), str):
                candidates.append(decoded[key])
    elif isinstance(decoded, str):
        candidates.append(decoded)
    candidates.extend(re.findall(r"(?<![0-9A-Fa-f])[0-9A-Fa-f]{64}(?![0-9A-Fa-f])", value.decode("utf-8", errors="replace")))
    normalized = sorted({item.lower() for item in candidates if re.fullmatch(r"[0-9A-Fa-f]{64}", item)})
    if len(normalized) != 1:
        raise EvidenceError("sha256-value input must contain exactly one SHA-256 value")
    return normalized[0]


def pr_projection(value: bytes) -> dict[str, Any]:
    try:
        record = json.loads(value.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise EvidenceError("PR comparison input is not JSON") from error
    if not isinstance(record, dict) or not isinstance(record.get("head"), dict) or not isinstance(record.get("base"), dict):
        raise EvidenceError("PR comparison input is malformed")
    projection = {
        "number": record.get("number"),
        "headRef": record["head"].get("ref"),
        "headSha": record["head"].get("sha"),
        "baseRef": record["base"].get("ref"),
        "state": record.get("state"),
        "draft": bool(record.get("draft", False)),
    }
    if (
        projection["number"] != 117
        or not isinstance(projection["headRef"], str)
        or not FULL_SHA.fullmatch(str(projection["headSha"]))
        or not isinstance(projection["baseRef"], str)
        or not isinstance(projection["state"], str)
    ):
        raise EvidenceError("PR comparison input does not identify frozen PR #117")
    projection["headSha"] = str(projection["headSha"]).lower()
    return projection


def compare_artifacts(
    context: AttemptContext, references: Sequence[str], comparison: str
) -> tuple[dict[str, Any], bool]:
    if len(references) != 2:
        raise EvidenceError("artifact comparison requires exactly two inputs")
    values = [context.input_bytes(reference) for reference in references]
    if comparison == "exact-bytes":
        projections: list[Any] = [sha256_bytes(value) for value in values]
    elif comparison == "sha256-value":
        projections = [parse_sha256_value(value) for value in values]
    elif comparison == "pr-number-head-base-state":
        projections = [pr_projection(value) for value in values]
    else:
        raise EvidenceError(f"unsupported comparison schema: {comparison}")
    equal = projections[0] == projections[1]
    return (
        {
            "schemaVersion": 1,
            "comparison": comparison,
            "equal": equal,
            "inputs": sorted(context.inputs, key=lambda item: item["reference"]),
            "projections": projections,
        },
        equal,
    )


def check_exact_paths(
    cwd: Path, base: str, head: str, allowed: Sequence[str]
) -> tuple[dict[str, Any], bool]:
    if not FULL_SHA.fullmatch(base) or not FULL_SHA.fullmatch(head):
        raise EvidenceError("--base and --head must be full commit SHAs")
    if not allowed or len(allowed) != len(set(allowed)):
        raise EvidenceError("--allow paths must be non-empty and unique")
    if subprocess.run(
        ["git", "merge-base", "--is-ancestor", base, head],
        cwd=cwd,
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        env=git_discovery_environment(),
    ).returncode != 0:
        raise EvidenceError("exact-path base is not an ancestor of head")
    for path in allowed:
        pure = PurePosixPath(path)
        if pure.is_absolute() or any(part in {"", ".", ".."} for part in pure.parts):
            raise EvidenceError(f"invalid allowed path: {path}")
    result = subprocess.run(
        ["git", "diff", "--name-status", "--no-renames", base, head],
        cwd=cwd,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=git_discovery_environment(),
    )
    if result.returncode != 0:
        raise EvidenceError(
            "git diff --name-status failed; "
            f"stderrSha256={sha256_bytes(result.stderr.encode('utf-8'))}"
        )
    changes: list[dict[str, str]] = []
    for line in result.stdout.splitlines():
        status_value, separator, path = line.partition("\t")
        if not separator or not path:
            raise EvidenceError(f"malformed Git name-status row: {line!r}")
        changes.append({"status": status_value, "path": path})
    actual = sorted(item["path"] for item in changes)
    expected = sorted(allowed)
    equal = actual == expected
    return (
        {
            "schemaVersion": 1,
            "base": base.lower(),
            "head": head.lower(),
            "equal": equal,
            "expectedPaths": expected,
            "actualPaths": actual,
            "changes": sorted(changes, key=lambda item: item["path"]),
        },
        equal,
    )


def tool_provenance(command: Sequence[str] | None) -> dict[str, Any]:
    if not command:
        return {}
    executable = shutil.which(command[0])
    record: dict[str, Any] = {"declaredExecutable": command[0], "resolvedExecutable": executable}
    if command[0] == "gh" and executable:
        version = subprocess.run(
            [executable, "--version"],
            check=False,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        record["version"] = version.stdout.splitlines()[0] if version.stdout else None
        auth = subprocess.run(
            [executable, "auth", "status", "--active", "--json", "hosts"],
            check=False,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        active_hosts: list[str] = []
        try:
            auth_value = json.loads(auth.stdout)
        except json.JSONDecodeError:
            auth_value = {}
        hosts = auth_value.get("hosts") if isinstance(auth_value, dict) else None
        if isinstance(hosts, dict):
            for host, accounts in hosts.items():
                if not isinstance(host, str) or not isinstance(accounts, list):
                    continue
                if any(
                    isinstance(account, dict)
                    and account.get("active") is True
                    and account.get("state") == "success"
                    for account in accounts
                ):
                    active_hosts.append(host)
        record["authHost"] = (
            os.environ.get("GH_HOST", "github.com")
            if os.environ.get("GH_HOST", "github.com") in active_hosts
            else None
        )
        record["authVerified"] = auth.returncode == 0 and bool(active_hosts)
    elif command[0] == "git" and executable:
        version = subprocess.run(
            [executable, "--version"],
            check=False,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        record["version"] = version.stdout.strip() or None
    return record


def execute_command(
    context: AttemptContext,
    *,
    command: Sequence[str],
    shell: bool,
    artifact: Path,
    lease: dict[str, Any],
) -> tuple[
    dict[str, Any],
    bytes,
    bytes,
    dict[str, Any],
    str | None,
]:
    if not command:
        raise EvidenceError("command mode requires arguments after --")
    if shell and any(marker in command[0] for marker in ("results/", "attempt://")):
        raise EvidenceError(
            "shell commands cannot embed evidence paths; use direct argv so paths can be rewritten safely"
        )
    rewritten, rewrites = rewrite_command(context, command)
    if shell:
        if len(rewritten) != 1:
            raise EvidenceError("--shell requires one quoted compound command string")
        executed = ["/bin/zsh", "-lc", f"set -o pipefail\n{rewritten[0]}"]
    else:
        executed = rewritten
    command_digest = sha256_bytes(canonical_json_bytes(list(command)))
    stdout = b""
    stderr = b""
    failure: str | None = None
    return_code: int | None = None
    command_environment = git_discovery_environment()
    try:
        result = subprocess.run(
            executed,
            cwd=context.cwd,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            umask=0o077,
            env=command_environment,
        )
        stdout = result.stdout
        stderr = result.stderr
        return_code = result.returncode
        context.harden_private_tree()
        context._reject_symlink_components(
            context.attempt_root, artifact.parent, "artifact parent"
        )
        if not artifact.exists():
            captured = stdout
            if stderr:
                captured += (b"\n" if captured and not captured.endswith(b"\n") else b"") + stderr
            if captured:
                if artifact.suffix.casefold() == ".json":
                    try:
                        json.loads(stdout.decode("utf-8"))
                    except (UnicodeDecodeError, json.JSONDecodeError):
                        try:
                            observed_sha = parse_sha256_value(captured)
                        except EvidenceError:
                            preliminary = parse_test_counts(
                                stdout + b"\n" + stderr,
                                None,
                                result.returncode,
                                command,
                            )
                            if (
                                not preliminary["selectorDetected"]
                                and not preliminary["selectorRequired"]
                                and result.returncode == 0
                            ):
                                preliminary["matched"] = 1
                            generated = {
                                "schemaVersion": 1,
                                "kind": "command-result",
                                "repositories": context.repositories,
                                "commandSha256": command_digest,
                                "exitCode": result.returncode,
                                "counts": preliminary,
                                "stdoutSha256": sha256_bytes(stdout),
                                "stderrSha256": sha256_bytes(stderr),
                            }
                        else:
                            generated = {
                                "schemaVersion": 1,
                                "kind": "sha256-value",
                                "value": observed_sha,
                            }
                        write_json_exclusive(artifact, generated)
                    else:
                        write_bytes_exclusive(artifact, stdout)
                else:
                    write_bytes_exclusive(artifact, captured)
        if not (artifact.is_file() or artifact.is_dir()):
            failure = "declared primary artifact is missing"
        counts = parse_test_counts(
            stdout + b"\n" + stderr,
            artifact if artifact.exists() else None,
            result.returncode,
            command,
        )
        if result.returncode != 0:
            failure = failure or f"command exited with status {result.returncode}"
        elif counts["matched"] == 0:
            failure = failure or "selector matched zero objects or tests"
        elif counts["failed"] != 0:
            failure = failure or f"selector reported {counts['failed']} failures"
        elif counts["skipped"] != 0:
            failure = failure or f"selector reported {counts['skipped']} skipped tests"
    except LockedError:
        raise
    counts = parse_test_counts(
        stdout + b"\n" + stderr,
        artifact if artifact.exists() else None,
        return_code if return_code is not None else 1,
        command,
    )
    return (
        {
            "declared": list(command),
            "executed": executed,
            "sha256": command_digest,
            "shell": shell,
            "rewrites": rewrites,
            "exitCode": return_code,
            "counts": counts,
        },
        stdout,
        stderr,
        lease,
        failure,
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root",
        default=os.environ.get("CHAPTERFLOW_EVIDENCE_ROOT", "/private/tmp/chapterflow-upgrade-results"),
    )
    parser.add_argument("--package", required=True)
    parser.add_argument("--assertion", required=True)
    parser.add_argument("--attempt", required=True)
    parser.add_argument("--repo-head", action="append", default=[])
    parser.add_argument("--cwd", required=True)
    parser.add_argument("--artifact", required=True)
    parser.add_argument("--owner")
    parser.add_argument("--retry-of")
    parser.add_argument("--reason")
    parser.add_argument("--shell", action="store_true")
    parser.add_argument(
        "--lock-root",
        default=os.environ.get("CHAPTERFLOW_LOCK_ROOT", "/private/tmp/chapterflow-upgrade-locks"),
    )
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--build-recovery-inventory", action="store_true")
    mode.add_argument("--classify-recovery-inventory")
    mode.add_argument("--compare-artifacts", nargs=2)
    mode.add_argument("--check-exact-paths", action="store_true")
    mode.add_argument("--fingerprint-git-owner-state")
    parser.add_argument("--worktrees")
    parser.add_argument("--backend-worktrees")
    parser.add_argument("--backend-repository")
    parser.add_argument("--ios-prs")
    parser.add_argument("--backend-prs")
    parser.add_argument("--ios-branches")
    parser.add_argument("--backend-branches")
    parser.add_argument("--comparison", choices=("exact-bytes", "sha256-value", "pr-number-head-base-state"))
    parser.add_argument("--target", action="append", default=[])
    parser.add_argument("--base")
    parser.add_argument("--head")
    parser.add_argument("--allow", action="append", default=[])
    parser.add_argument("command", nargs=argparse.REMAINDER)
    return parser


def apply_recovery_environment_defaults(args: argparse.Namespace) -> None:
    recovery_mode = bool(
        args.build_recovery_inventory
        or args.classify_recovery_inventory is not None
    )
    if not recovery_mode:
        return
    if not args.backend_repository:
        args.backend_repository = os.environ.get("CHAPTERFLOW_BACKEND_REPOSITORY")
    if args.build_recovery_inventory and not args.backend_worktrees:
        args.backend_worktrees = os.environ.get(
            "CHAPTERFLOW_BACKEND_WORKTREES_REF"
        )


def effective_recovery_repo_heads(
    values: Sequence[str], mode: str
) -> list[str]:
    effective = list(values)
    if mode not in {"build-recovery-inventory", "classify-recovery-inventory"}:
        return effective
    explicit_backend = [
        raw.split("=", 1)[1]
        for raw in effective
        if raw.startswith("backend=") and "=" in raw
    ]
    environment_head = os.environ.get("CHAPTERFLOW_BACKEND_HEAD")
    if explicit_backend:
        if (
            environment_head
            and len(explicit_backend) == 1
            and explicit_backend[0].lower() != environment_head.lower()
        ):
            raise EvidenceError(
                "explicit backend repo head conflicts with CHAPTERFLOW_BACKEND_HEAD"
            )
    else:
        if not environment_head:
            raise EvidenceError(
                "recovery inventory modes require backend=<fullSHA> via --repo-head "
                "or CHAPTERFLOW_BACKEND_HEAD"
            )
        effective.append(f"backend={environment_head}")
    return effective


def add_default_backend_target(
    targets: Sequence[str], repositories: Sequence[dict[str, str]]
) -> list[str]:
    effective = list(targets)
    backend_targets = [
        raw for raw in effective if raw.startswith("backend=") and "=" in raw
    ]
    if not backend_targets:
        effective.append(
            f"backend={required_repository_head(repositories, 'backend')}"
        )
    return effective


def validate_mode(args: argparse.Namespace, command: list[str]) -> str:
    if command and command[0] == "--":
        command.pop(0)
    modes = [
        args.build_recovery_inventory,
        args.classify_recovery_inventory is not None,
        args.compare_artifacts is not None,
        args.check_exact_paths,
        args.fingerprint_git_owner_state is not None,
    ]
    if sum(bool(value) for value in modes) + int(bool(command)) != 1:
        raise EvidenceError("select exactly one command or deterministic built-in mode")
    if args.build_recovery_inventory:
        if not all(
            (
                args.worktrees,
                args.backend_worktrees,
                args.ios_prs,
                args.backend_prs,
                args.ios_branches,
                args.backend_branches,
            )
        ):
            raise EvidenceError("recovery inventory mode requires all six named captures")
        if not args.backend_repository:
            raise EvidenceError(
                "recovery inventory mode requires --backend-repository"
            )
        return "build-recovery-inventory"
    if args.classify_recovery_inventory is not None:
        if not args.target:
            raise EvidenceError("classification mode requires --target")
        if not args.backend_repository:
            raise EvidenceError("classification mode requires --backend-repository")
        return "classify-recovery-inventory"
    if args.backend_repository:
        raise EvidenceError(
            "--backend-repository is valid only for recovery inventory modes"
        )
    if args.compare_artifacts is not None:
        if not args.comparison:
            raise EvidenceError("artifact comparison mode requires --comparison")
        return "compare-artifacts"
    if args.check_exact_paths:
        if not args.base or not args.head or not args.allow:
            raise EvidenceError("exact-path mode requires --base, --head, and --allow")
        return "check-exact-paths"
    if args.fingerprint_git_owner_state is not None:
        return "fingerprint-git-owner-state"
    return "command"


def canonical_invocation(
    args: argparse.Namespace,
    mode: str,
    command: Sequence[str],
    backend_root: Path | None,
) -> dict[str, Any]:
    if mode == "command":
        return {
            "mode": mode,
            "command": list(command),
            "shell": bool(args.shell),
        }
    if mode == "build-recovery-inventory":
        return {
            "mode": mode,
            "worktrees": args.worktrees,
            "backendWorktrees": args.backend_worktrees,
            "iosPRs": args.ios_prs,
            "backendPRs": args.backend_prs,
            "iosBranches": args.ios_branches,
            "backendBranches": args.backend_branches,
            "backendRepository": str(backend_root),
        }
    if mode == "classify-recovery-inventory":
        return {
            "mode": mode,
            "inventory": args.classify_recovery_inventory,
            "targets": list(args.target),
            "backendRepository": str(backend_root),
        }
    if mode == "compare-artifacts":
        return {
            "mode": mode,
            "inputs": list(args.compare_artifacts),
            "comparison": args.comparison,
        }
    if mode == "check-exact-paths":
        return {
            "mode": mode,
            "base": args.base,
            "head": args.head,
            "allow": list(args.allow),
        }
    if mode == "fingerprint-git-owner-state":
        return {
            "mode": mode,
            "repository": args.fingerprint_git_owner_state,
        }
    raise EvidenceError(f"unsupported invocation mode: {mode}")


class AttemptLeaseFinalizer:
    def __init__(self) -> None:
        self.lease: dict[str, Any] | None = None
        self.owned_slot: Path | None = None
        self.owned_slot_identity: tuple[int, int] | None = None
        self.owned_claim_identity: tuple[int, int] | None = None
        self.package: str | None = None
        self.assertion: str | None = None
        self.attempt: str | None = None
        self.owner: str | None = None
        self.command_digest: str | None = None
        self.trigger: str | None = None
        self.context: AttemptContext | None = None
        self.summary: dict[str, Any] | None = None

    def arm(
        self,
        *,
        lease: dict[str, Any],
        owned_slot: Path,
        owned_slot_identity: tuple[int, int],
        owned_claim_identity: tuple[int, int],
        package: str,
        assertion: str,
        attempt: str,
        owner: str,
        command_digest: str,
        trigger: str,
        context: AttemptContext,
    ) -> None:
        if self.owned_slot is not None:
            raise EvidenceError("attempt lease finalizer is already armed")
        if (
            private_directory_identity(owned_slot, "owned simulator-device lease")
            != owned_slot_identity
        ):
            raise EvidenceError("simulator-device lease changed before registration")
        claim_stat = require_private_regular_file(
            owned_slot / "claim.json", "simulator-device lease claim"
        )
        if (claim_stat.st_dev, claim_stat.st_ino) != owned_claim_identity:
            raise EvidenceError("simulator-device lease claim changed before registration")
        self.lease = lease
        self.owned_slot_identity = owned_slot_identity
        self.owned_claim_identity = owned_claim_identity
        self.package = package
        self.assertion = assertion
        self.attempt = attempt
        self.owner = owner
        self.command_digest = command_digest
        self.trigger = trigger
        self.context = context
        self.owned_slot = owned_slot

    def disarm(
        self,
        *,
        lease: dict[str, Any],
        owned_slot: Path,
        owned_slot_identity: tuple[int, int],
        owned_claim_identity: tuple[int, int],
    ) -> None:
        if self.owned_slot is None:
            return
        if (
            self.lease is not lease
            or self.owned_slot != owned_slot
            or self.owned_slot_identity != owned_slot_identity
            or self.owned_claim_identity != owned_claim_identity
        ):
            raise EvidenceError("refusing to disarm a different attempt lease")
        self.owned_slot = None

    def finalize(self) -> str | None:
        if self.owned_slot is None:
            return None
        assert self.lease is not None
        assert self.owned_slot_identity is not None
        assert self.owned_claim_identity is not None
        assert self.package is not None
        assert self.assertion is not None
        assert self.attempt is not None
        assert self.owner is not None
        assert self.command_digest is not None
        assert self.trigger is not None
        assert self.context is not None
        failures: list[str] = []
        deferred_interrupt: BaseException | None = None
        try:
            release_command_lease(
                self.lease,
                self.owned_slot,
                self.owned_slot_identity,
                self.owned_claim_identity,
                package=self.package,
                assertion=self.assertion,
                attempt=self.attempt,
                owner=self.owner,
                command_digest=self.command_digest,
                trigger=self.trigger,
            )
        except (EvidenceError, OSError) as error:
            failures.append(f"command-scoped lease release failed: {error}")
        except BaseException as error:
            deferred_interrupt = error
            failures.append(
                "command-scoped lease release was interrupted after manifest finalization"
            )
            try:
                if os.path.lexists(self.owned_slot):
                    cleanup_exclusively_created_lease_slot(
                        self.owned_slot,
                        self.owned_slot_identity,
                        self.owned_claim_identity,
                    )
                self.lease["released"] = True
                self.lease["releasedAt"] = utc_now()
            except (EvidenceError, OSError) as cleanup_error:
                detail = (
                    "interrupted command-scoped lease release cleanup failed: "
                    f"{cleanup_error}"
                )
                failures.append(detail)
                error.add_note(detail)
        manifest_path = self.context.attempt_root / "manifest.json"
        manifest_digest: str | None = None
        try:
            before_manifest = require_private_regular_file(
                manifest_path, "finalized attempt manifest"
            )
            manifest_bytes = read_regular_bytes(
                manifest_path, maximum_bytes=64 * 1024 * 1024
            )
            after_manifest = require_private_regular_file(
                manifest_path, "finalized attempt manifest"
            )
            if (
                before_manifest.st_dev,
                before_manifest.st_ino,
                before_manifest.st_size,
            ) != (
                after_manifest.st_dev,
                after_manifest.st_ino,
                after_manifest.st_size,
            ):
                raise EvidenceError("finalized attempt manifest changed while being read")
            manifest = read_json_bytes(manifest_bytes, "finalized attempt manifest")
            manifest_lease = manifest.get("lease") if isinstance(manifest, dict) else None
            if (
                not isinstance(manifest, dict)
                or manifest.get("packageId") != self.package
                or manifest.get("assertionId") != self.assertion
                or manifest.get("attemptId") != self.attempt
                or manifest.get("owner") != self.owner
                or not isinstance(manifest_lease, dict)
                or manifest_lease.get("mode") != "attempt-claim"
                or manifest_lease.get("released") is not False
                or manifest_lease.get("releaseAfterManifest") is not True
                or manifest_lease.get("releaseRecord") != "lease-release.json"
            ):
                raise EvidenceError("finalized manifest lease protocol is invalid")
            manifest_digest = sha256_bytes(manifest_bytes)
        except (EvidenceError, OSError) as error:
            failures.append(f"cannot validate finalized manifest: {error}")
        release_record: dict[str, Any] = {
            "schemaVersion": 1,
            "packageId": self.package,
            "assertionId": self.assertion,
            "attemptId": self.attempt,
            "owner": self.owner,
            "manifest": "manifest.json",
            "manifestSha256": manifest_digest,
            "released": self.lease.get("released") is True,
            "releasedAt": self.lease.get("releasedAt"),
        }
        if failures:
            release_record["failure"] = "; ".join(failures)
        layout_valid = True
        receipt_directory_fd: int | None = None
        try:
            self.context.verify_private_layout()
            directory_flags = os.O_RDONLY
            if hasattr(os, "O_DIRECTORY"):
                directory_flags |= os.O_DIRECTORY
            if hasattr(os, "O_NOFOLLOW"):
                directory_flags |= os.O_NOFOLLOW
            receipt_directory_fd = os.open(
                self.context.attempt_root, directory_flags
            )
            receipt_directory_stat = os.fstat(receipt_directory_fd)
            expected_attempt_identity = self.context._layout_identities.get(
                self.context.attempt_root
            )
            if (
                not stat.S_ISDIR(receipt_directory_stat.st_mode)
                or stat.S_IMODE(receipt_directory_stat.st_mode) != 0o700
                or expected_attempt_identity is None
                or (
                    receipt_directory_stat.st_dev,
                    receipt_directory_stat.st_ino,
                )
                != expected_attempt_identity
            ):
                raise EvidenceError(
                    "attempt directory changed before lease release record publication"
                )
        except (EvidenceError, OSError) as error:
            failures.append(f"cannot verify layout before lease release record: {error}")
            layout_valid = False
        try:
            if layout_valid:
                if failures:
                    release_record["failure"] = "; ".join(failures)
                release_bytes = canonical_json_bytes(release_record)
                try:
                    assert receipt_directory_fd is not None
                    write_bytes_exclusive(
                        Path("lease-release.json"),
                        release_bytes,
                        directory_fd=receipt_directory_fd,
                    )
                    self.context.verify_private_layout()
                    if (
                        read_regular_bytes_at(
                            receipt_directory_fd, "lease-release.json"
                        )
                        != release_bytes
                    ):
                        raise EvidenceError("lease release record read-back mismatch")
                except (EvidenceError, OSError) as error:
                    failures.append(f"cannot finalize lease release record: {error}")
        finally:
            if receipt_directory_fd is not None:
                os.close(receipt_directory_fd)
        self.owned_slot = None
        if deferred_interrupt is not None:
            raise deferred_interrupt
        return "; ".join(failures) if failures else None


def _run_with_lease_finalizer(
    argv: Sequence[str] | None, lease_finalizer: AttemptLeaseFinalizer
) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    command = list(args.command)
    try:
        apply_recovery_environment_defaults(args)
        mode = validate_mode(args, command)
        package = validate_component(args.package, "package ID")
        assertion = validate_component(args.assertion, "assertion ID")
        attempt = validate_component(args.attempt, "attempt ID")
        repositories, head_set_digest = canonicalize_repo_heads(
            effective_recovery_repo_heads(args.repo_head, mode)
        )
        if mode == "classify-recovery-inventory":
            args.target = add_default_backend_target(args.target, repositories)
        primary_relative = validate_results_relative(args.artifact)
        cwd = Path(args.cwd).expanduser().resolve(strict=True)
        if not cwd.is_dir():
            raise EvidenceError("--cwd must name an existing directory")
        source_root = repository_root(cwd)
        backend_root = (
            validate_backend_repository(args.backend_repository)
            if args.backend_repository
            else None
        )
        invocation = canonical_invocation(args, mode, command, backend_root)
        validate_lease_policy(source_root)
        root = ensure_external_root(Path(args.root), source_root, "evidence root")
        lock_root = ensure_external_root(
            Path(args.lock_root), source_root, "lease root"
        )
        selected_repository, candidate_head = verify_candidate_head(cwd, repositories)
        before_snapshot = snapshot_repository_results(source_root)
        context = AttemptContext(
            root=root,
            package=package,
            assertion=assertion,
            attempt=attempt,
            repositories=repositories,
            head_set_digest=head_set_digest,
            cwd=cwd,
        )
        context.create()
    except (EvidenceError, OSError) as error:
        print(f"evidence runner failed: {error}", file=sys.stderr)
        return 1

    observed_at = utc_now()
    owner = resolve_owner(package, lock_root, args.owner)
    artifact = context.attempt_root / Path(*primary_relative.parts)
    stdout = b""
    stderr = b""
    status = "passed"
    failure: str | None = None
    result_record: dict[str, Any] = {
        "mode": mode,
        "invocation": invocation,
        "invocationSha256": sha256_bytes(canonical_json_bytes(invocation)),
    }
    lease: dict[str, Any] = {
        "resource": "simulator-device",
        "mode": "not-required",
        "released": False,
    }
    owned_slot: Path | None = None
    owned_lease_acquired = False
    retry_record: dict[str, Any] | None = None
    source_before: dict[str, Any] | None = None
    source_after: dict[str, Any] | None = None
    deferred_base_error: BaseException | None = None
    deferred_base_traceback: TracebackType | None = None

    def defer_base_exception(error: BaseException, phase: str) -> None:
        nonlocal deferred_base_error, deferred_base_traceback, status, failure
        if deferred_base_error is None:
            deferred_base_error = error
            deferred_base_traceback = error.__traceback__
        status = "failed"
        interruption = (
            f"evidence runner interrupted during {phase}: {type(error).__name__}"
        )
        failure = interruption if failure is None else f"{interruption}; {failure}"

    try:
        source_before = source_state(cwd, candidate_head)
        if not source_before["clean"]:
            raise EvidenceError("source worktree must be clean before evidence execution")
        retry_record = validate_retry(
            context,
            args.retry_of,
            args.reason,
            invocation=invocation,
            primary_artifact=primary_relative.as_posix(),
        )
        context.ensure_private_subdirectory(artifact.parent)
        if mode == "command":
            trigger = command_triggers_lease(command)
            if trigger:
                command_digest = sha256_bytes(canonical_json_bytes(list(command)))

                def register_owned_lease(
                    acquired_lease: dict[str, Any],
                    acquired_slot: Path,
                    acquired_identity: tuple[int, int],
                    acquired_claim_identity: tuple[int, int],
                ) -> None:
                    nonlocal lease, owned_lease_acquired
                    lease = acquired_lease
                    owned_lease_acquired = True
                    lease_finalizer.arm(
                        lease=acquired_lease,
                        owned_slot=acquired_slot,
                        owned_slot_identity=acquired_identity,
                        owned_claim_identity=acquired_claim_identity,
                        package=context.package,
                        assertion=context.assertion,
                        attempt=context.attempt,
                        owner=owner,
                        command_digest=command_digest,
                        trigger=trigger,
                        context=context,
                    )

                def rollback_owned_lease(
                    acquired_lease: dict[str, Any],
                    acquired_slot: Path,
                    acquired_identity: tuple[int, int],
                    acquired_claim_identity: tuple[int, int],
                ) -> None:
                    nonlocal lease, owned_lease_acquired
                    lease_finalizer.disarm(
                        lease=acquired_lease,
                        owned_slot=acquired_slot,
                        owned_slot_identity=acquired_identity,
                        owned_claim_identity=acquired_claim_identity,
                    )
                    lease = {
                        "resource": "simulator-device",
                        "mode": "not-required",
                        "released": False,
                    }
                    owned_lease_acquired = False

                lease, owned_slot = acquire_command_lease(
                    lock_root=lock_root,
                    package=context.package,
                    assertion=context.assertion,
                    attempt=context.attempt,
                    owner=owner,
                    command_digest=command_digest,
                    trigger=trigger,
                    on_acquired=register_owned_lease,
                    on_rollback=rollback_owned_lease,
                )
                owned_lease_acquired = owned_slot is not None
            (
                command_record,
                stdout,
                stderr,
                lease,
                failure,
            ) = execute_command(
                context,
                command=command,
                shell=args.shell,
                artifact=artifact,
                lease=lease,
            )
            result_record["command"] = command_record
            result_record["tool"] = tool_provenance(command)
        elif mode == "build-recovery-inventory":
            if backend_root is None:
                raise EvidenceError("backend repository binding is missing")
            value = build_recovery_inventory(
                context,
                backend_root=backend_root,
                worktrees_ref=args.worktrees,
                backend_worktrees_ref=args.backend_worktrees,
                ios_prs_ref=args.ios_prs,
                backend_prs_ref=args.backend_prs,
                ios_branches_ref=args.ios_branches,
                backend_branches_ref=args.backend_branches,
            )
            write_json_exclusive(artifact, value)
            result_record["counts"] = {
                "matched": value["counts"]["candidates"],
                "failed": 0,
                "skipped": 0,
            }
        elif mode == "classify-recovery-inventory":
            if backend_root is None:
                raise EvidenceError("backend repository binding is missing")
            value = classify_recovery_inventory(
                context,
                args.classify_recovery_inventory,
                args.target,
                backend_root,
            )
            write_json_exclusive(artifact, value)
            result_record["counts"] = {
                "matched": len(value["classifications"]),
                "failed": 0,
                "skipped": 0,
            }
        elif mode == "compare-artifacts":
            value, equal = compare_artifacts(
                context, args.compare_artifacts, args.comparison
            )
            write_json_exclusive(artifact, value)
            result_record["counts"] = {
                "matched": 1,
                "failed": 0 if equal else 1,
                "skipped": 0,
            }
            if not equal:
                failure = f"{args.comparison} inputs are not equal"
        elif mode == "check-exact-paths":
            if args.head.lower() != candidate_head:
                raise EvidenceError(
                    "exact-path --head must equal the source candidate HEAD"
                )
            value, equal = check_exact_paths(cwd, args.base, args.head, args.allow)
            write_json_exclusive(artifact, value)
            result_record["counts"] = {
                "matched": len(value["actualPaths"]),
                "failed": 0 if equal else 1,
                "skipped": 0,
            }
            if not equal:
                failure = "changed paths do not exactly match the declared allowlist"
        elif mode == "fingerprint-git-owner-state":
            value = git_owner_state_fingerprint(
                Path(args.fingerprint_git_owner_state).expanduser().resolve(strict=True)
            )
            write_json_exclusive(artifact, value)
            result_record["counts"] = {
                "matched": max(1, int(value["untrackedCount"])),
                "failed": 0,
                "skipped": 0,
            }
        if not (artifact.is_file() or artifact.is_dir()):
            failure = failure or "declared primary artifact is missing"
        context.verify_inputs_unchanged()
        context.verify_private_layout()
    except LockedError as error:
        status = "locked"
        failure = str(error)
    except (EvidenceError, OSError, subprocess.SubprocessError) as error:
        status = "failed"
        failure = str(error)
    except Exception as error:  # Defensive boundary keeps an acquired lease releasable.
        status = "failed"
        failure = f"unexpected evidence runner error: {type(error).__name__}: {error}"
    except BaseException as error:
        defer_base_exception(error, "execution")

    try:
        source_after = source_state(cwd, candidate_head)
        if source_before is None or source_after != source_before:
            status = "failed"
            failure = failure or "source HEAD or working-tree state changed during evidence execution"
    except (EvidenceError, OSError, subprocess.SubprocessError) as error:
        status = "failed"
        failure = failure or str(error)
    except BaseException as error:
        defer_base_exception(error, "source-state verification")

    after_snapshot: list[dict[str, Any]] | None = None
    try:
        after_snapshot = snapshot_repository_results(source_root)
        if after_snapshot != before_snapshot:
            status = "failed"
            failure = (
                "repository-local results write detected"
                if failure is None
                else f"repository-local results write detected; {failure}"
            )
    except Exception as error:  # An owned command lease remains held through finalization.
        status = "failed"
        snapshot_failure = (
            f"cannot verify repository-local results after command: "
            f"{type(error).__name__}: {error}"
        )
        failure = snapshot_failure if failure is None else f"{snapshot_failure}; {failure}"
    except BaseException as error:
        defer_base_exception(error, "repository-results verification")
    if failure and status == "passed":
        status = "failed"

    manifest_path = context.attempt_root / "manifest.json"
    finalization_failure: str | None = None
    if owned_lease_acquired:
        lease["releaseRecord"] = "lease-release.json"
        lease["releaseAfterManifest"] = True
    try:
        context.verify_private_layout()
        write_bytes_exclusive(context.attempt_root / "stdout.txt", stdout)
        write_bytes_exclusive(context.attempt_root / "stderr.txt", stderr)
        try:
            artifacts = artifact_records(
                context.attempt_root / "results", context.attempt_root, artifact
            )
        except EvidenceError as error:
            artifacts = []
            status = "failed"
            failure = failure or str(error)
        manifest = {
            "schemaVersion": SCHEMA_VERSION,
            "packageId": package,
            "assertionId": assertion,
            "attemptId": attempt,
            "retryOf": args.retry_of,
            "retry": retry_record,
            "reason": args.reason,
            "owner": owner,
            "observedAt": observed_at,
            "retentionDisposition": "retain-through-merge-and-post-merge-verification",
            "repositories": repositories,
            "headSetDigest": head_set_digest,
            "source": {
                "repository": selected_repository,
                "head": candidate_head,
                "cwd": str(cwd),
                "repositoryRoot": str(source_root),
            },
            "sourceState": {
                "before": source_before,
                "after": source_after,
                "unchanged": source_before is not None and source_after == source_before,
            },
            "primaryArtifact": primary_relative.as_posix(),
            "artifacts": artifacts,
            "inputs": sorted(context.inputs, key=lambda item: item["reference"]),
            "stdout": {
                "path": "stdout.txt",
                "sha256": sha256_file(context.attempt_root / "stdout.txt"),
                "bytes": len(stdout),
            },
            "stderr": {
                "path": "stderr.txt",
                "sha256": sha256_file(context.attempt_root / "stderr.txt"),
                "bytes": len(stderr),
            },
            "repositoryLocalResults": {
                "beforeSha256": snapshot_digest(before_snapshot),
                "afterSha256": (
                    snapshot_digest(after_snapshot)
                    if after_snapshot is not None
                    else None
                ),
                "changed": (
                    before_snapshot != after_snapshot
                    if after_snapshot is not None
                    else None
                ),
            },
            "lease": lease,
            "result": result_record,
            "status": status,
            "failure": failure,
        }
        write_json_exclusive(manifest_path, manifest)
        context.verify_private_layout()
    except (EvidenceError, OSError) as error:
        finalization_failure = str(error)
    except BaseException as error:
        if deferred_base_error is None:
            raise
        deferred_base_error.add_note(
            "manifest finalization was also interrupted: "
            f"{type(error).__name__}"
        )
        raise deferred_base_error.with_traceback(deferred_base_traceback)

    if finalization_failure is not None:
        if deferred_base_error is not None:
            deferred_base_error.add_note(
                "manifest finalization also failed after the original interruption"
            )
            raise deferred_base_error.with_traceback(deferred_base_traceback)
        print(
            f"evidence runner finalization failed: {finalization_failure}",
            file=sys.stderr,
        )
        return 1

    lease_finalizer.summary = {
        "status": status,
        "attempt": attempt,
        "headSetDigest": head_set_digest,
        "manifest": str(manifest_path),
        "failure": failure,
    }
    if deferred_base_error is not None:
        raise deferred_base_error.with_traceback(deferred_base_traceback)
    return 0 if status == "passed" else 1


def run(argv: Sequence[str] | None = None) -> int:
    lease_finalizer = AttemptLeaseFinalizer()
    result = 1
    release_failure: str | None = None
    pending_error: BaseException | None = None
    try:
        try:
            result = _run_with_lease_finalizer(argv, lease_finalizer)
        except BaseException as error:
            pending_error = error
            raise
    finally:
        try:
            release_failure = lease_finalizer.finalize()
        except BaseException as cleanup_error:
            if pending_error is None:
                raise
            pending_error.add_note(
                "lease finalizer was also interrupted after identity-checked cleanup: "
                f"{type(cleanup_error).__name__}: {cleanup_error}"
            )
        if release_failure is not None:
            print(
                f"evidence runner lease finalization failed: {release_failure}",
                file=sys.stderr,
            )
            result = 1
    if lease_finalizer.summary is not None:
        summary = dict(lease_finalizer.summary)
        if release_failure is not None:
            summary["status"] = "failed"
            summary["failure"] = (
                release_failure
                if summary.get("failure") is None
                else f"{summary['failure']}; {release_failure}"
            )
        print(json.dumps(summary, sort_keys=True))
    return result


def main() -> None:
    raise SystemExit(run())


if __name__ == "__main__":
    main()
