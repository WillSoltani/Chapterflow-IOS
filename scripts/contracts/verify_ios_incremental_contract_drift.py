#!/usr/bin/env python3
"""Verify exact historical provenance and current iOS contract semantics.

The committed inventory is a historical artifact. It must reproduce from the
generator, mapping, and Swift blobs at its pinned Git revision. The current
working tree is a different proof: every production Swift file is scanned, but
only producer relationships and request semantics are compared with that
historical artifact. Unrelated source bytes are intentionally irrelevant.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from functools import lru_cache
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import tempfile
from typing import Iterable, Mapping, Sequence

import generate_ios_native_inventory as inventory


_UNCACHED_SWIFT_CODE_PROJECTION = inventory._swift_code_projection
_UNCACHED_SWIFT_WITHOUT_COMMENTS = inventory._swift_without_comments


@lru_cache(maxsize=4_096)
def _cached_swift_code_projection(source: str) -> str:
    return _UNCACHED_SWIFT_CODE_PROJECTION(source)


@lru_cache(maxsize=4_096)
def _cached_swift_without_comments(source: str) -> str:
    return _UNCACHED_SWIFT_WITHOUT_COMMENTS(source)


@lru_cache(maxsize=4_096)
def _cached_brace_depths(source: str) -> tuple[int, ...]:
    code = _cached_swift_code_projection(source)
    depths = [0]
    depth = 0
    for character in code:
        if character == "{":
            depth += 1
        elif character == "}":
            depth -= 1
        depths.append(depth)
    return tuple(depths)


def _cached_brace_depth_at(source: str, position: int) -> int:
    depths = _cached_brace_depths(source)
    return depths[min(max(position, 0), len(depths) - 1)]


@lru_cache(maxsize=4_096)
def _swift_structure_projection(source: str) -> str:
    """Mask strings including embedded newlines while preserving all offsets."""

    projected = list(_cached_swift_code_projection(source))
    cursor = 0
    while cursor < len(source):
        following = source[cursor + 1] if cursor + 1 < len(source) else ""
        if source[cursor] == "/" and following == "/":
            newline = source.find("\n", cursor + 2)
            cursor = len(source) if newline < 0 else newline + 1
            continue
        if source[cursor] == "/" and following == "*":
            depth = 1
            cursor += 2
            while cursor < len(source) and depth:
                following = source[cursor + 1] if cursor + 1 < len(source) else ""
                if source[cursor] == "/" and following == "*":
                    depth += 1
                    cursor += 2
                elif source[cursor] == "*" and following == "/":
                    depth -= 1
                    cursor += 2
                else:
                    cursor += 1
            continue
        hash_count = 0
        while cursor + hash_count < len(source) and source[cursor + hash_count] == "#":
            hash_count += 1
        quote_start = cursor + hash_count
        if quote_start < len(source) and source[quote_start] == '"':
            multiline = source.startswith('"""', quote_start)
            quote_width = 3 if multiline else 1
            closing = ('"' * quote_width) + ('#' * hash_count)
            start = cursor
            cursor = quote_start + quote_width
            while cursor < len(source):
                if source.startswith(closing, cursor):
                    cursor += len(closing)
                    break
                if hash_count == 0 and source[cursor] == "\\":
                    cursor = min(cursor + 2, len(source))
                else:
                    cursor += 1
            else:
                raise inventory.InventoryError("unterminated Swift string literal")
            for position in range(start, cursor):
                projected[position] = " "
            continue
        cursor += 1
    return "".join(projected)


# The pinned generator is imported as a library by this verifier. Its scanners
# repeatedly project the same immutable source strings, so process-local caches
# preserve behavior while keeping the complete canary lane within its CI budget.
inventory._swift_code_projection = _cached_swift_code_projection
inventory._swift_without_comments = _cached_swift_without_comments
inventory._brace_depth_at = _cached_brace_depth_at


DEFAULT_MANIFEST_PATH = (
    "contracts/native-ios/v1/ios-source-inventory-manifest.json"
)
INCREMENTAL_POLICY_PATH = (
    "contracts/native-ios/v1/incremental-drift-policy.json"
)
INCREMENTAL_VERIFIER_PATH = (
    "scripts/contracts/verify_ios_incremental_contract_drift.py"
)
CURRENT_PRODUCTION_SWIFT_ROOTS = (
    "Packages",
    "ChapterFlow",
    "ChapterflowWidgets",
    "NotificationService",
    "NotificationContent",
    "ShareExtension",
    "ActionExtension",
    "SharedExtensionKit",
)
SEMANTIC_FIELDS = (
    "operationKeyCount",
    "operationKeySha256",
    "producerVariantCount",
    "producerVariantIdSha256",
    "producerIdentitySha256",
    "matrixRowCount",
    "relationalRecordCount",
    "relationalRecordSha256",
)
GENERIC_BODY_CALLSITE_BINDINGS = {
    "updateSettings": {
        (
            "Packages/SettingsFeature/Sources/SettingsFeature/SettingsRepository.swift",
            "patchReadingSettings",
        ): {"bodyType": "ReadingSettingsPatch", "source": "local"},
        (
            "Packages/SocialFeature/Sources/SocialFeature/Repository/LiveSocialRepository.swift",
            "updateSettings",
        ): {"bodyType": "UpdateSettingsBody", "source": "parameter"},
    },
    "patchNotificationSettings": {
        (
            "Packages/NotificationsFeature/Sources/NotificationsFeature/"
            "NotificationPreferencesRepository.swift",
            "savePreferences",
        ): {"bodyType": "NotificationSettingsUpdate", "source": "local"},
    },
}


class DriftError(ValueError):
    """Historical provenance or current contract semantics are invalid."""


class _CurrentValidationSources(Mapping[str, bytes]):
    """Use current blobs for record checks and the historical set for legacy discovery.

    Current all-source discovery is performed separately with stricter, return-type
    based rules. The pinned generator's record validation remains authoritative for
    every mapped producer, while its historical filename heuristic cannot reject an
    unrelated helper added beside a producer.
    """

    def __init__(
        self,
        current: Mapping[str, bytes],
        historical_discovery: Mapping[str, bytes],
    ) -> None:
        self._current = current
        self._historical_discovery = historical_discovery

    def __getitem__(self, key: str) -> bytes:
        return self._current[key]

    def __iter__(self):
        return iter(self._current)

    def __len__(self) -> int:
        return len(self._current)

    def items(self):
        return self._historical_discovery.items()


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _parse_json_object(data: bytes, label: str) -> dict:
    try:
        parsed = json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise DriftError(f"{label} is not valid UTF-8 JSON: {error}") from error
    if not isinstance(parsed, dict):
        raise DriftError(f"{label} must be a JSON object")
    return parsed


def _run(
    command: Sequence[str],
    *,
    cwd: Path,
    label: str,
    env: Mapping[str, str] | None = None,
) -> str:
    try:
        result = subprocess.run(
            list(command),
            cwd=cwd,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=None if env is None else dict(env),
        )
    except subprocess.CalledProcessError as error:
        detail = (error.stderr or error.stdout or "").strip()
        raise DriftError(f"{label} failed: {detail}") from error
    return result.stdout.strip()


def _is_current_production_swift_path(path: str) -> bool:
    """Return whether a path is compiled production Swift in this repository."""

    if inventory._is_production_swift_path(path):
        return True
    parts = PurePosixPath(path).parts
    return (
        len(parts) >= 2
        and parts[0] in CURRENT_PRODUCTION_SWIFT_ROOTS[1:]
        and path.endswith(".swift")
    )


def _load_current_worktree_sources(repo_root: Path) -> dict[str, bytes]:
    """Load every tracked or untracked production Swift source from the worktree."""

    sources: dict[str, bytes] = {}
    for root_name in CURRENT_PRODUCTION_SWIFT_ROOTS:
        root = repo_root / root_name
        if not root.is_dir():
            raise DriftError(f"production Swift root is missing: {root_name}")
        for source_path in root.rglob("*.swift"):
            if not source_path.is_file():
                continue
            relative_path = source_path.relative_to(repo_root).as_posix()
            if _is_current_production_swift_path(relative_path):
                sources[relative_path] = source_path.read_bytes()
    return dict(sorted(sources.items()))


def _git_object_exists(repo_root: Path, revision: str, path: str | None = None) -> bool:
    object_name = f"{revision}^{{commit}}" if path is None else f"{revision}:{path}"
    result = subprocess.run(
        ["git", "cat-file", "-e", object_name],
        cwd=repo_root,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return result.returncode == 0


def _validate_revision(manifest: Mapping, repo_root: Path) -> str:
    revision = manifest.get("iosSourceRevision")
    if not isinstance(revision, str) or re.fullmatch(r"[0-9a-f]{40}", revision) is None:
        raise DriftError(
            "committed iOS inventory must pin a full lowercase iosSourceRevision"
        )
    if not _git_object_exists(repo_root, revision):
        raise DriftError(f"historical iOS source revision does not exist: {revision}")
    return revision


def _manifest_input_sha(manifest: Mapping, path: str) -> str:
    raw_inputs = manifest.get("sourceInputs")
    if not isinstance(raw_inputs, list):
        raise DriftError("committed iOS inventory sourceInputs must be an array")
    matches = [
        item for item in raw_inputs
        if isinstance(item, dict) and item.get("path") == path
    ]
    if len(matches) != 1:
        raise DriftError(f"committed iOS inventory must contain one source input for {path}")
    digest = matches[0].get("sha256")
    if not isinstance(digest, str) or re.fullmatch(r"[0-9a-f]{64}", digest) is None:
        raise DriftError(f"committed iOS inventory has an invalid source hash for {path}")
    return digest


def assert_byte_identical(label: str, expected: bytes, actual: bytes) -> None:
    if expected != actual:
        raise DriftError(f"{label} is not byte-identical")


def assert_incremental_policy_lock(policy_bytes: bytes, verifier_bytes: bytes) -> None:
    policy = _parse_json_object(policy_bytes, INCREMENTAL_POLICY_PATH)
    expected_fields = {
        "schemaVersion",
        "verifierPath",
        "verifierSha256",
        "classification",
        "verificationBoundary",
    }
    if set(policy) != expected_fields:
        raise DriftError("incremental drift policy fields are invalid")
    if policy.get("schemaVersion") != "chapterflow-ios-incremental-drift-policy-v2":
        raise DriftError("incremental drift policy schema is unsupported")
    if policy.get("verifierPath") != INCREMENTAL_VERIFIER_PATH:
        raise DriftError("incremental drift policy verifier path is invalid")
    expected_classification = {
        "contractOriginatingProducer": (
            "file-or-type stored value or declaration result carrying Endpoint, "
            "direct Endpoint or native wire construction, or mapped analytics transport"
        ),
        "localDirectInvocation": (
            "immediate syntactic callee use consumes a mapped producer and is not "
            "an independent producer"
        ),
        "functionValueEscape": (
            "bare argument, return, assignment, storage, collection, tuple, or "
            "captured closure use leaves the proven local direct-call boundary"
        ),
        "unsupportedOrAmbiguous": "fail-closed",
    }
    if policy.get("classification") != expected_classification:
        raise DriftError("incremental drift policy classification is invalid")
    expected_boundary = {
        "covers": "native wire-contract origin, provenance, and mapped semantic drift",
        "doesNotClaim": "general Swift type-system or application call-graph correctness",
    }
    if policy.get("verificationBoundary") != expected_boundary:
        raise DriftError("incremental drift policy verification boundary is invalid")
    expected_digest = policy.get("verifierSha256")
    if (
        not isinstance(expected_digest, str)
        or re.fullmatch(r"[0-9a-f]{64}", expected_digest) is None
    ):
        raise DriftError("incremental drift policy verifier hash is invalid")
    if _sha256(verifier_bytes) != expected_digest:
        raise DriftError(
            "incremental drift verifier changed; deliberate policy regeneration "
            "and coordinated evidence review are required"
        )


def verify_incremental_policy_lock(repo_root: Path) -> None:
    policy_path = repo_root / INCREMENTAL_POLICY_PATH
    verifier_path = repo_root / INCREMENTAL_VERIFIER_PATH
    if not policy_path.is_file() or not verifier_path.is_file():
        raise DriftError("incremental drift verifier or policy lock is missing")
    assert_incremental_policy_lock(
        policy_path.read_bytes(),
        verifier_path.read_bytes(),
    )


def verify_historical_manifest(repo_root: Path, manifest_path: Path) -> None:
    """Execute the pinned generator in a clean detached clone and compare bytes."""

    repo_root = repo_root.resolve()
    manifest_path = manifest_path.resolve()
    if not manifest_path.is_file():
        raise DriftError(f"committed iOS inventory manifest is missing: {manifest_path}")
    committed_bytes = manifest_path.read_bytes()
    manifest = _parse_json_object(committed_bytes, str(manifest_path))
    revision = _validate_revision(manifest, repo_root)

    shallow = _run(
        ["git", "rev-parse", "--is-shallow-repository"],
        cwd=repo_root,
        label="inspect iOS repository history",
    )
    if shallow != "false":
        raise DriftError("historical iOS manifest provenance requires non-shallow Git history")

    for path in (inventory.GENERATOR_PATH, inventory.SOURCE_MAPPING_PATH):
        if not _git_object_exists(repo_root, revision, path):
            raise DriftError(
                f"historical iOS source revision is missing required input: {path}"
            )

    with tempfile.TemporaryDirectory(
        prefix="chapterflow-ios-historical-contract."
    ) as temporary:
        temporary_root = Path(temporary)
        clone = temporary_root / "repo"
        generated = temporary_root / "generated-manifest.json"
        _run(
            [
                "git",
                "clone",
                "--quiet",
                "--shared",
                "--no-checkout",
                str(repo_root),
                str(clone),
            ],
            cwd=repo_root,
            label="create detached historical iOS contract checkout",
        )
        _run(
            ["git", "checkout", "--quiet", "--detach", revision],
            cwd=clone,
            label="check out historical iOS contract revision",
        )
        pinned_generator = clone / inventory.GENERATOR_PATH
        if not pinned_generator.is_file():
            raise DriftError(
                "historical iOS source revision does not materialize the pinned generator"
            )
        generation_env = dict(os.environ)
        generation_env["PYTHONDONTWRITEBYTECODE"] = "1"
        generation_env["PYTHONHASHSEED"] = "0"
        _run(
            [
                sys.executable,
                str(pinned_generator),
                "--repo-root",
                str(clone),
                "--mapping",
                inventory.SOURCE_MAPPING_PATH,
                "--source-revision",
                revision,
                "--output",
                str(generated),
            ],
            cwd=clone,
            label="reproduce historical iOS inventory from pinned Git objects",
            env=generation_env,
        )
        if not generated.is_file() or generated.read_bytes() != committed_bytes:
            raise DriftError(
                "committed iOS inventory manifest does not reproduce from its pinned "
                "generator, mapping, and source Git objects"
            )


@lru_cache(maxsize=8_192)
def _canonical_swift_tokens(source: str) -> str:
    """Return a comment/format-insensitive, string-preserving Swift token stream."""

    tokens: list[str] = []
    index = 0
    block_depth = 0
    length = len(source)
    while index < length:
        following = source[index + 1] if index + 1 < length else ""
        if block_depth:
            if source[index] == "/" and following == "*":
                block_depth += 1
                index += 2
            elif source[index] == "*" and following == "/":
                block_depth -= 1
                index += 2
            else:
                index += 1
            continue
        if source[index].isspace():
            index += 1
            continue
        if source[index] == "/" and following == "/":
            newline = source.find("\n", index + 2)
            index = length if newline < 0 else newline + 1
            continue
        if source[index] == "/" and following == "*":
            block_depth = 1
            index += 2
            continue

        hash_count = 0
        while index + hash_count < length and source[index + hash_count] == "#":
            hash_count += 1
        quote_start = index + hash_count
        if quote_start < length and source[quote_start] == '"':
            multiline = source.startswith('"""', quote_start)
            quote_width = 3 if multiline else 1
            closing = ('"' * quote_width) + ('#' * hash_count)
            cursor = quote_start + quote_width
            while cursor < length:
                if source.startswith(closing, cursor):
                    cursor += len(closing)
                    break
                if hash_count == 0 and source[cursor] == "\\":
                    cursor = min(cursor + 2, length)
                else:
                    cursor += 1
            else:
                raise DriftError("request-semantic projection found an unterminated Swift string")
            literal = source[index:cursor]
            tokens.append(f"S{len(literal)}:{literal}")
            index = cursor
            continue

        identifier = re.match(r"[A-Za-z_][A-Za-z0-9_]*", source[index:])
        if identifier is not None:
            value = identifier.group(0)
            tokens.append(f"I{len(value)}:{value}")
            index += len(value)
            continue
        number = re.match(r"[0-9][0-9A-Za-z_.]*", source[index:])
        if number is not None:
            value = number.group(0)
            tokens.append(f"N{len(value)}:{value}")
            index += len(value)
            continue
        tokens.append(f"P:{source[index]}")
        index += 1

    if block_depth:
        raise DriftError("request-semantic projection found an unterminated Swift comment")
    return "|".join(tokens)


def _endpoint_returning_functions(
    source: str,
    path: str,
    endpoint_type_names: set[str],
) -> list[tuple[str, int, int]]:
    """Find live Swift function declarations whose declared result is Endpoint."""

    code = inventory._swift_code_projection(source)
    declaration = re.compile(
        r"\bfunc\s+(?:`([^`\n]+)`|([A-Za-z_][A-Za-z0-9_]*))"
        r"(?:\s*<[^>{}]*>)?\s*\("
    )
    functions: list[tuple[str, int, int]] = []
    for match in declaration.finditer(code):
        source_symbol = match.group(1) or match.group(2)
        if not _is_global_or_type_member(source, match.start()):
            continue
        opening_parenthesis = code.find("(", match.start(), match.end())
        closing_parenthesis = inventory._closing_delimiter_index(
            source,
            opening_parenthesis,
            "(",
            ")",
            f"current Endpoint-returning function {source_symbol}@{path}",
        )
        opening_brace = code.find("{", closing_parenthesis + 1)
        if opening_brace < 0:
            continue
        intervening_closing = code.find("}", closing_parenthesis + 1, opening_brace)
        if intervening_closing >= 0:
            continue
        suffix = code[closing_parenthesis + 1:opening_brace]
        endpoint_type = _endpoint_type_pattern(source, path, endpoint_type_names)
        arrow = suffix.find("->")
        if arrow < 0:
            continue
        result_type = suffix[arrow + 2:]
        result_matches = list(
            re.finditer(
                rf"(?<![A-Za-z0-9_.]){endpoint_type}(?![A-Za-z0-9_])",
                result_type,
            )
        )
        if not any(
            re.match(r"\s*\.\s*Type\b", result_type[item.end():]) is None
            and (
                re.search(r"\bNetworking\s*\.", item.group(0)) is not None
                or not _lexical_nominal_shadow(
                    source,
                    path,
                    re.findall(r"[A-Za-z_][A-Za-z0-9_]*", item.group(0))[-1],
                    match.start(),
                )
            )
            for item in result_matches
        ):
            continue
        closing_brace = inventory._closing_delimiter_index(
            source,
            opening_brace,
            "{",
            "}",
            f"current Endpoint-returning function {source_symbol}@{path}",
        )
        functions.append((source_symbol, match.start(), closing_brace + 1))
    return functions


def _endpoint_returning_subscripts(
    source: str,
    path: str,
    endpoint_type_names: set[str],
) -> list[tuple[str, int, int]]:
    """Find concrete subscripts whose declared result is Endpoint."""

    code = inventory._swift_code_projection(source)
    declaration = re.compile(r"\bsubscript\s*\(")
    endpoint_type = _endpoint_type_pattern(source, path, endpoint_type_names)
    subscripts: list[tuple[str, int, int]] = []
    for match in declaration.finditer(code):
        if not _is_global_or_type_member(source, match.start()):
            continue
        opening_parenthesis = code.find("(", match.start(), match.end())
        closing_parenthesis = inventory._closing_delimiter_index(
            source,
            opening_parenthesis,
            "(",
            ")",
            f"current Endpoint-returning subscript@{path}",
        )
        opening_brace = code.find("{", closing_parenthesis + 1)
        if opening_brace < 0:
            continue
        intervening_closing = code.find("}", closing_parenthesis + 1, opening_brace)
        if intervening_closing >= 0:
            continue
        suffix = code[closing_parenthesis + 1:opening_brace]
        arrow = suffix.find("->")
        if arrow < 0:
            continue
        result_type = suffix[arrow + 2:]
        result_matches = list(
            re.finditer(
                rf"(?<![A-Za-z0-9_.]){endpoint_type}(?![A-Za-z0-9_])",
                result_type,
            )
        )
        if not any(
            re.match(r"\s*\.\s*Type\b", result_type[item.end():]) is None
            and not _endpoint_reference_is_shadowed(
                source,
                path,
                item.group(0),
                endpoint_type_names,
                match.start(),
            )
            for item in result_matches
        ):
            continue
        closing_brace = inventory._closing_delimiter_index(
            source,
            opening_brace,
            "{",
            "}",
            f"current Endpoint-returning subscript@{path}",
        )
        subscripts.append(("subscript", match.start(), closing_brace + 1))
    return subscripts


def _shadowed_endpoint_type_names(
    source: str,
    path: str,
    endpoint_type_names: set[str],
) -> set[str]:
    code = inventory._swift_code_projection(source)
    shadowed: set[str] = set()
    nominal = re.compile(
        r"\b(?:struct|enum|class|actor|protocol)\s+"
        r"([A-Za-z_][A-Za-z0-9_]*)\b"
    )
    canonical_endpoint_path = "Packages/Networking/Sources/Networking/Endpoint.swift"
    for match in nominal.finditer(code):
        name = match.group(1)
        if (
            inventory._brace_depth_at(source, match.start()) == 0
            and name in endpoint_type_names
            and not (path == canonical_endpoint_path and name == "Endpoint")
        ):
            shadowed.add(name)

    alias = re.compile(
        r"\btypealias\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\(?\s*"
        r"(?:(Networking)\s*\.\s*)?([A-Za-z_][A-Za-z0-9_]*)"
    )
    for match in alias.finditer(code):
        name, qualifier, target = match.groups()
        if inventory._brace_depth_at(source, match.start()) != 0:
            continue
        if name not in endpoint_type_names:
            continue
        resolves_endpoint = qualifier == "Networking" or target in endpoint_type_names
        if not resolves_endpoint:
            shadowed.add(name)
    return shadowed


def _lexical_nominal_shadow(
    source: str,
    path: str,
    type_name: str,
    position: int,
) -> bool:
    code = inventory._swift_code_projection(source)
    position_stack: list[int] = []
    for index, character in enumerate(code[:position]):
        if character == "{":
            position_stack.append(index)
        elif character == "}" and position_stack:
            position_stack.pop()
    declaration = re.compile(
        rf"\b(?:struct|enum|class|actor|protocol)\s+{re.escape(type_name)}\b"
    )
    canonical = "Packages/Networking/Sources/Networking/Endpoint.swift"
    for match in declaration.finditer(code):
        if (
            path == canonical
            and type_name == "Endpoint"
            and inventory._brace_depth_at(source, match.start()) == 0
        ):
            continue
        owner_stack: list[int] = []
        for index, character in enumerate(code[:match.start()]):
            if character == "{":
                owner_stack.append(index)
            elif character == "}" and owner_stack:
                owner_stack.pop()
        if not owner_stack or owner_stack[-1] in position_stack:
            return True
    return False


def _endpoint_reference_is_shadowed(
    source: str,
    path: str,
    reference: str,
    endpoint_type_names: set[str],
    position: int,
) -> bool:
    if re.search(r"\bNetworking\s*\.", reference):
        return False
    identifiers = re.findall(r"[A-Za-z_][A-Za-z0-9_]*", reference)
    type_name = next(
        (name for name in reversed(identifiers) if name in endpoint_type_names),
        None,
    )
    return (
        type_name is not None
        and _lexical_nominal_shadow(source, path, type_name, position)
    )


def _endpoint_type_pattern(
    source: str,
    path: str,
    endpoint_type_names: set[str],
) -> str:
    ordered = sorted(endpoint_type_names, key=len, reverse=True)
    qualified = sorted(endpoint_type_names | {"Endpoint"}, key=len, reverse=True)
    all_names = "|".join(re.escape(name) for name in qualified)
    shadowed = _shadowed_endpoint_type_names(source, path, endpoint_type_names)
    visible = [name for name in ordered if name not in shadowed]
    alternatives = [rf"Networking\s*\.\s*(?:{all_names})"]
    if visible:
        visible_patterns = [
            re.escape(name)
            if name == "Endpoint"
            else rf"(?:[A-Za-z_][A-Za-z0-9_]*\s*\.\s*)?{re.escape(name)}"
            for name in visible
        ]
        alternatives.append("(?:" + "|".join(visible_patterns) + ")")
    return "(?:" + "|".join(alternatives) + ")"


def _lexical_owner_kind(source: str, position: int) -> str:
    code = inventory._swift_code_projection(source)
    stack: list[int] = []
    for index, character in enumerate(code[:position]):
        if character == "{":
            stack.append(index)
        elif character == "}" and stack:
            stack.pop()
    if not stack:
        return "global"
    opening = stack[-1]
    header_start = max(
        code.rfind("}", 0, opening),
        code.rfind("{", 0, opening),
        code.rfind(";", 0, opening),
    ) + 1
    header = code[header_start:opening]
    owner = re.search(
        r"\b(struct|enum|class|actor|protocol|extension)\b[^{}]*$",
        header,
    )
    return owner.group(1) if owner is not None else "local"


def _is_global_or_type_member(source: str, position: int) -> bool:
    return _lexical_owner_kind(source, position) in {
        "global", "struct", "enum", "class", "actor", "extension",
    }


def _swift_imports(source: str) -> set[str]:
    code = inventory._swift_code_projection(source)
    return set(
        re.findall(
            r"^\s*(?:(?:@[A-Za-z_][A-Za-z0-9_]*"
            r"(?:\([^()\n]*\))?|private|fileprivate|internal|package|public)"
            r"\s+)*import\s+"
            r"(?:(?:class|enum|func|protocol|struct|typealias|var)\s+)?"
            r"([A-Za-z_][A-Za-z0-9_]*)",
            code,
            re.MULTILINE,
        )
    )


def _swift_module_name(path: str) -> str:
    return PurePosixPath(_swift_module_key(path)).name


def _endpoint_type_names_by_path(
    sources: Mapping[str, bytes],
) -> dict[str, set[str]]:
    """Resolve Endpoint aliases with Swift file/module visibility and imports."""

    aliases: dict[str, list[tuple[str, str | None, str, str]]] = {}
    pattern = re.compile(
        r"\b(?:(public|package|private|fileprivate|internal)\s+)?"
        r"typealias\s+([A-Za-z_][A-Za-z0-9_]*)"
        r"\s*=\s*\(?\s*(?:([A-Za-z_][A-Za-z0-9_]*)\s*\.\s*)?"
        r"([A-Za-z_][A-Za-z0-9_]*)\s*[?!]?\s*\)?"
        r"(?![A-Za-z0-9_.])"
    )
    imports: dict[str, set[str]] = {}
    module_nominal_shadows: dict[str, set[str]] = {}
    file_nominal_shadows: dict[str, set[str]] = {}
    nominal = re.compile(
        r"\b(?:(public|package|private|fileprivate|internal)\s+)?"
        r"(?:struct|enum|class|actor|protocol)\s+"
        r"([A-Za-z_][A-Za-z0-9_]*)\b"
    )
    for path, raw_source in sorted(sources.items()):
        source = raw_source.decode("utf-8")
        module = _swift_module_key(path)
        imports[path] = _swift_imports(source)
        code = inventory._swift_code_projection(source)
        for match in pattern.finditer(code):
            visibility = match.group(1) or "internal"
            if inventory._brace_depth_at(source, match.start()) != 0:
                visibility = "private"
            aliases.setdefault(path, []).append(
                (match.group(2), match.group(3), match.group(4), visibility)
            )
        for match in nominal.finditer(code):
            if inventory._brace_depth_at(source, match.start()) != 0:
                continue
            name = match.group(2)
            if (
                path == "Packages/Networking/Sources/Networking/Endpoint.swift"
                and name == "Endpoint"
            ):
                continue
            visibility = match.group(1) or "internal"
            if visibility in {"private", "fileprivate"}:
                file_nominal_shadows.setdefault(path, set()).add(name)
            else:
                module_nominal_shadows.setdefault(module, set()).add(name)

    local = {path: set() for path in sources}
    module_visible: dict[str, set[str]] = {}
    exported: dict[str, set[str]] = {"Networking": {"Endpoint"}}
    resolved_aliases: set[tuple[str, str]] = set()
    for path in sources:
        if _swift_module_name(path) == "Networking" or "Networking" in imports[path]:
            local[path].add("Endpoint")
    changed = True
    while changed:
        changed = False
        for path, path_names in local.items():
            module = _swift_module_key(path)
            module_name = _swift_module_name(path)
            imported = set().union(
                *(exported.get(name, set()) for name in imports[path])
            ) if imports[path] else set()
            visible = path_names | module_visible.get(module, set()) | imported
            for alias, qualifier, target, visibility in aliases.get(path, ()):
                if qualifier is None:
                    resolves = target in visible
                else:
                    resolves = (
                        qualifier == module_name or qualifier in imports[path]
                    ) and target in exported.get(qualifier, set())
                if resolves:
                    resolved_aliases.add((path, alias))
                    if alias not in path_names:
                        path_names.add(alias)
                        changed = True
                    if (
                        visibility not in {"private", "fileprivate"}
                        and alias not in module_visible.setdefault(module, set())
                    ):
                        module_visible[module].add(alias)
                        changed = True
                    if (
                        visibility == "public"
                        and alias not in exported.setdefault(module_name, set())
                    ):
                        exported[module_name].add(alias)
                        changed = True

    result: dict[str, set[str]] = {}
    unresolved_module_aliases: dict[str, set[str]] = {}
    unresolved_file_aliases: dict[str, set[str]] = {}
    for path, declarations in aliases.items():
        module = _swift_module_key(path)
        for alias, _, _, visibility in declarations:
            if (path, alias) in resolved_aliases:
                continue
            if visibility in {"private", "fileprivate"}:
                unresolved_file_aliases.setdefault(path, set()).add(alias)
            else:
                unresolved_module_aliases.setdefault(module, set()).add(alias)
    for path, path_names in local.items():
        module = _swift_module_key(path)
        imported = set().union(
            *(exported.get(name, set()) for name in imports[path])
        ) if imports[path] else set()
        visible = path_names | module_visible.get(module, set()) | imported
        visible -= module_nominal_shadows.get(module, set())
        visible -= file_nominal_shadows.get(path, set())
        visible -= unresolved_module_aliases.get(module, set())
        visible -= unresolved_file_aliases.get(path, set())
        result[path] = visible
    return result


def _endpoint_closure_type_names_by_path(
    sources: Mapping[str, bytes],
    endpoint_types_by_path: Mapping[str, set[str]],
) -> dict[str, set[str]]:
    direct: dict[str, list[tuple[str, str]]] = {}
    chains: dict[str, list[tuple[str, str, str]]] = {}
    imports = {
        path: _swift_imports(raw_source.decode("utf-8"))
        for path, raw_source in sources.items()
    }
    direct_prefix = re.compile(
        r"\b(?:(public|package|private|fileprivate|internal)\s+)?"
        r"typealias\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"
        r"(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^()]*\))?\s+)*"
        r"\([^\n{}]*\)\s*(?:async\s+)?(?:throws\s+)?->\s*"
    )
    chain_pattern = re.compile(
        r"\b(?:(public|package|private|fileprivate|internal)\s+)?"
        r"typealias\s+([A-Za-z_][A-Za-z0-9_]*)"
        r"\s*=\s*(?:[A-Za-z_][A-Za-z0-9_]*\s*\.\s*)?"
        r"([A-Za-z_][A-Za-z0-9_]*)\b"
    )
    for path, raw_source in sorted(sources.items()):
        source = raw_source.decode("utf-8")
        code = inventory._swift_code_projection(source)
        module = _swift_module_key(path)
        endpoint_type = _endpoint_type_pattern(
            source,
            path,
            endpoint_types_by_path[path],
        )
        for prefix in direct_prefix.finditer(code):
            suffix = code[prefix.end():]
            if re.match(rf"{endpoint_type}\s*[?!]?(?![A-Za-z0-9_])", suffix):
                visibility = prefix.group(1) or "internal"
                if inventory._brace_depth_at(source, prefix.start()) != 0:
                    visibility = "private"
                direct.setdefault(path, []).append(
                    (prefix.group(2), visibility)
                )
        for alias in chain_pattern.finditer(code):
            visibility = alias.group(1) or "internal"
            if inventory._brace_depth_at(source, alias.start()) != 0:
                visibility = "private"
            chains.setdefault(path, []).append(
                (alias.group(2), alias.group(3), visibility)
            )

    local = {path: set() for path in sources}
    module_visible: dict[str, set[str]] = {}
    exported: dict[str, set[str]] = {}
    for path, aliases in direct.items():
        module = _swift_module_key(path)
        for alias, visibility in aliases:
            local[path].add(alias)
            if visibility not in {"private", "fileprivate"}:
                module_visible.setdefault(module, set()).add(alias)
            if visibility == "public":
                exported.setdefault(_swift_module_name(path), set()).add(alias)
    changed = True
    while changed:
        changed = False
        for path, path_names in local.items():
            module = _swift_module_key(path)
            imported = set().union(
                *(exported.get(name, set()) for name in imports[path])
            ) if imports[path] else set()
            visible = path_names | module_visible.get(module, set()) | imported
            for alias, target, visibility in chains.get(path, ()):
                if target in visible:
                    if alias not in path_names:
                        path_names.add(alias)
                        changed = True
                    if (
                        visibility not in {"private", "fileprivate"}
                        and alias not in module_visible.setdefault(module, set())
                    ):
                        module_visible[module].add(alias)
                        changed = True
                    module_name = _swift_module_name(path)
                    if (
                        visibility == "public"
                        and alias not in exported.setdefault(module_name, set())
                    ):
                        exported[module_name].add(alias)
                        changed = True

    result: dict[str, set[str]] = {}
    nominal = re.compile(
        r"\b(?:struct|enum|class|actor|protocol)\s+"
        r"([A-Za-z_][A-Za-z0-9_]*)\b"
    )
    for path, raw_source in sources.items():
        source = raw_source.decode("utf-8")
        code = inventory._swift_code_projection(source)
        module = _swift_module_key(path)
        imported = set().union(
            *(exported.get(name, set()) for name in imports[path])
        ) if imports[path] else set()
        visible = set(local[path]) | module_visible.get(module, set()) | imported
        direct_names = {alias for alias, _ in direct.get(path, ())}
        for alias, target, _ in chains.get(path, ()):
            if alias not in direct_names and target not in visible:
                visible.discard(alias)
        for declaration in nominal.finditer(code):
            if inventory._brace_depth_at(source, declaration.start()) == 0:
                visible.discard(declaration.group(1))
        result[path] = visible
    return result


class _TypeProofError(ValueError):
    """A bounded Swift type or initializer proof could not be completed."""

    def __init__(self, reason: str, *, alias: str | None = None) -> None:
        super().__init__(reason)
        self.reason = reason
        self.alias = alias


@dataclass(frozen=True)
class _SwiftTypeToken:
    kind: str
    value: str
    start: int
    end: int


@dataclass(frozen=True)
class _SwiftTypeNode:
    kind: str
    name: str = ""
    children: tuple["_SwiftTypeNode", ...] = ()


@dataclass(frozen=True)
class _TypeAliasDeclaration:
    path: str
    module: str
    module_name: str
    name: str
    parameters: tuple[str, ...]
    expression: _SwiftTypeNode | None
    visibility: str
    owner_stack: tuple[int, ...]
    owner_names: tuple[str, ...]
    position: int
    line: int
    parse_error: str | None

    @property
    def identity(self) -> tuple[str, int, str]:
        return (self.path, self.position, self.name)


@dataclass(frozen=True)
class _StoredPropertyDeclaration:
    symbol: str
    start: int
    end: int
    type_source: str | None
    initializer: str
    initializer_start: int


@dataclass(frozen=True)
class _InitializerEndpointEvidence:
    operations: tuple[str, ...] = ()
    direct_endpoint: bool = False
    endpoint_capable: bool = False
    ambiguous_reason: str | None = None

    @property
    def is_endpoint_producing(self) -> bool:
        return bool(self.operations) or self.direct_endpoint or self.endpoint_capable


@dataclass(frozen=True)
class _LocalFunctionValueUse:
    start: int
    end: int
    role: str
    reason: str


@dataclass(frozen=True)
class _CallableDeclarationHead:
    symbol: str
    start: int
    opening_parenthesis: int
    closing_parenthesis: int
    generic_parameters: tuple[str, ...] = ()
    generic_error: str | None = None


_SWIFT_IDENTIFIER_PATTERN = r"(?:`[^`\n]+`|[^\W\d]\w*)"
_TYPE_PREFIX_KEYWORDS = {
    "any", "borrowing", "consuming", "each", "inout", "isolated",
    "sending", "some", "repeat",
}
_FUNCTION_EFFECT_KEYWORDS = {"async", "throws", "rethrows"}
_TYPE_DECLARATION_STARTERS = {
    "actor", "case", "class", "deinit", "enum", "extension", "func",
    "import", "init", "let", "operator", "precedencegroup", "protocol",
    "struct", "subscript", "typealias", "var",
}


def _swift_identifier_value(value: str) -> str:
    return value[1:-1] if value.startswith("`") and value.endswith("`") else value


def _tokenize_swift_type(source: str) -> tuple[_SwiftTypeToken, ...]:
    code = inventory._swift_code_projection(source)
    tokens: list[_SwiftTypeToken] = []
    cursor = 0
    while cursor < len(code):
        if code[cursor].isspace():
            cursor += 1
            continue
        if code.startswith("->", cursor):
            tokens.append(_SwiftTypeToken("symbol", "->", cursor, cursor + 2))
            cursor += 2
            continue
        if code[cursor] == "`":
            closing = code.find("`", cursor + 1)
            if closing < 0:
                raise _TypeProofError("unterminated backticked identifier")
            tokens.append(
                _SwiftTypeToken(
                    "identifier",
                    code[cursor + 1:closing],
                    cursor,
                    closing + 1,
                )
            )
            cursor = closing + 1
            continue
        character = code[cursor]
        if character == "_" or character.isalpha() or ord(character) >= 128:
            end = cursor + 1
            while end < len(code):
                following = code[end]
                if not (
                    following == "_"
                    or following.isalnum()
                    or ord(following) >= 128
                ):
                    break
                end += 1
            tokens.append(
                _SwiftTypeToken("identifier", code[cursor:end], cursor, end)
            )
            cursor = end
            continue
        if code.startswith("...", cursor):
            tokens.append(_SwiftTypeToken("symbol", "...", cursor, cursor + 3))
            cursor += 3
            continue
        if character in "@.,:=<>()[]?!&":
            tokens.append(_SwiftTypeToken("symbol", character, cursor, cursor + 1))
            cursor += 1
            continue
        raise _TypeProofError(
            f"unsupported token {source[cursor:cursor + 1]!r} in Swift type"
        )
    if len(tokens) > 1_024:
        raise _TypeProofError("type expression exceeds the 1024-token proof limit")
    return tuple(tokens)


class _SwiftTypeParser:
    def __init__(self, tokens: Sequence[_SwiftTypeToken]) -> None:
        self.tokens = tokens
        self.index = 0

    def _peek(self, value: str | None = None) -> _SwiftTypeToken | None:
        if self.index >= len(self.tokens):
            return None
        token = self.tokens[self.index]
        if value is not None and token.value != value:
            return None
        return token

    def _take(self, value: str | None = None) -> _SwiftTypeToken:
        token = self._peek(value)
        if token is None:
            expected = "type token" if value is None else repr(value)
            raise _TypeProofError(f"expected {expected} in Swift type")
        self.index += 1
        return token

    def parse(self) -> _SwiftTypeNode:
        if not self.tokens:
            raise _TypeProofError("empty Swift type expression")
        node = self._parse_function_type()
        if self.index != len(self.tokens):
            remainder = " ".join(token.value for token in self.tokens[self.index:self.index + 8])
            raise _TypeProofError(f"unsupported trailing Swift type syntax: {remainder}")
        return node

    def _parse_function_type(self) -> _SwiftTypeNode:
        left = self._parse_composition()
        while self._peek() is not None and self._peek().value in _FUNCTION_EFFECT_KEYWORDS:
            effect = self._take().value
            if effect in {"throws", "rethrows"} and self._peek("(") is not None:
                self._skip_balanced("(", ")")
        if self._peek("->") is not None:
            self._take("->")
            result = self._parse_function_type()
            return _SwiftTypeNode("function", children=(left, result))
        return left

    def _parse_composition(self) -> _SwiftTypeNode:
        children = [self._parse_primary()]
        while self._peek("&") is not None:
            self._take("&")
            children.append(self._parse_primary())
        if len(children) == 1:
            return children[0]
        return _SwiftTypeNode("composition", children=tuple(children))

    def _parse_primary(self) -> _SwiftTypeNode:
        while self._peek("@") is not None:
            self._take("@")
            attribute = self._take()
            if attribute.kind != "identifier":
                raise _TypeProofError("attribute name is not an identifier")
            if (
                self._peek("(") is not None
                and attribute.end == self._peek("(").start
            ):
                self._skip_balanced("(", ")")
        while (
            self._peek() is not None
            and self._peek().kind == "identifier"
            and self._peek().value in _TYPE_PREFIX_KEYWORDS
        ):
            self._take()

        if self._peek("(") is not None:
            self._take("(")
            elements: list[_SwiftTypeNode] = []
            if self._peek(")") is None:
                while True:
                    self._skip_tuple_label()
                    elements.append(self._parse_function_type())
                    if self._peek(",") is None:
                        break
                    self._take(",")
            self._take(")")
            node = _SwiftTypeNode("tuple", children=tuple(elements))
        elif self._peek("[") is not None:
            self._take("[")
            first = self._parse_function_type()
            if self._peek(":") is not None:
                self._take(":")
                second = self._parse_function_type()
                node = _SwiftTypeNode("dictionary", children=(first, second))
            else:
                node = _SwiftTypeNode("array", children=(first,))
            self._take("]")
        else:
            first = self._take()
            if first.kind != "identifier":
                raise _TypeProofError(f"expected a named Swift type, found {first.value!r}")
            segments = [first.value]
            while (
                self._peek(".") is not None
                and self.index + 1 < len(self.tokens)
                and self.tokens[self.index + 1].kind == "identifier"
                and self.tokens[self.index + 1].value not in {"Type", "Protocol"}
            ):
                self._take(".")
                segments.append(self._take().value)
            arguments: list[_SwiftTypeNode] = []
            if self._peek("<") is not None:
                self._take("<")
                if self._peek(">") is not None:
                    raise _TypeProofError("generic argument list is empty")
                while True:
                    arguments.append(self._parse_function_type())
                    if len(arguments) > 32:
                        raise _TypeProofError("generic arity exceeds the 32-argument proof limit")
                    if self._peek(",") is None:
                        break
                    self._take(",")
                self._take(">")
            node = _SwiftTypeNode(
                "nominal",
                name=".".join(segments),
                children=tuple(arguments),
            )

        while True:
            if self._peek("?") is not None or self._peek("!") is not None:
                self._take()
                node = _SwiftTypeNode("optional", children=(node,))
                continue
            if (
                self._peek(".") is not None
                and self.index + 1 < len(self.tokens)
                and self.tokens[self.index + 1].value in {"Type", "Protocol"}
            ):
                self._take(".")
                self._take()
                node = _SwiftTypeNode("metatype", children=(node,))
                continue
            if self._peek("...") is not None:
                self._take("...")
                node = _SwiftTypeNode("variadic", children=(node,))
                continue
            break
        return node

    def _skip_tuple_label(self) -> None:
        if self._peek() is None or self._peek().kind != "identifier":
            return
        if self.index + 1 < len(self.tokens) and self.tokens[self.index + 1].value == ":":
            self.index += 2
            return
        if (
            self.index + 2 < len(self.tokens)
            and self.tokens[self.index + 1].kind == "identifier"
            and self.tokens[self.index + 2].value == ":"
        ):
            self.index += 3

    def _skip_balanced(self, opening: str, closing: str) -> None:
        self._take(opening)
        depth = 1
        while depth:
            token = self._take()
            if token.value == opening:
                depth += 1
            elif token.value == closing:
                depth -= 1


def _parse_swift_type(source: str) -> _SwiftTypeNode:
    return _SwiftTypeParser(_tokenize_swift_type(source)).parse()


@lru_cache(maxsize=8_192)
def _brace_stack_at(source: str, position: int) -> tuple[int, ...]:
    code = inventory._swift_code_projection(source)
    stack: list[int] = []
    for index, character in enumerate(code[:position]):
        if character == "{":
            stack.append(index)
        elif character == "}" and stack:
            stack.pop()
    return tuple(stack)


def _owner_names_at(source: str, position: int) -> tuple[str, ...]:
    code = inventory._swift_code_projection(source)
    names: list[str] = []
    for opening in _brace_stack_at(source, position):
        header_start = max(
            code.rfind("}", 0, opening),
            code.rfind("{", 0, opening),
            code.rfind(";", 0, opening),
            code.rfind("\n", 0, opening),
        ) + 1
        header = code[header_start:opening]
        owner = re.search(
            rf"\b(?:struct|enum|class|actor|protocol|extension)\s+({_SWIFT_IDENTIFIER_PATTERN})"
            r"(?:\s*\.\s*([^\s<{]+))?[^{}]*$",
            header,
        )
        if owner is not None:
            names.append(_swift_identifier_value(owner.group(2) or owner.group(1)))
    return tuple(names)


def _typealias_rhs_end(source: str, start: int, label: str) -> int:
    code = inventory._swift_code_projection(source)
    pairs = {"(": ")", "[": "]", "<": ">"}
    closing = {value: key for key, value in pairs.items()}
    stack: list[str] = []
    cursor = start
    lines = 0
    limit = min(len(code), start + 16_384)
    while cursor < limit:
        character = code[cursor]
        if character in pairs:
            stack.append(character)
        elif character in closing and stack and stack[-1] == closing[character]:
            stack.pop()
        elif not stack and character in {";", "}"}:
            return cursor
        elif not stack and character in {"\n", "\r"}:
            lines += 1
            if lines > 64:
                raise _TypeProofError(f"{label} exceeds the 64-line proof limit")
            candidate = source[start:cursor].strip()
            lookahead = cursor + 1
            while lookahead < len(code) and code[lookahead].isspace():
                lookahead += 1
            following = re.match(r"(?:->|[?!&.<]|async\b|throws\b|rethrows\b)", code[lookahead:])
            if candidate and following is None:
                try:
                    _parse_swift_type(candidate)
                except _TypeProofError:
                    pass
                else:
                    return cursor
        cursor += 1
    if cursor >= len(code):
        return len(code)
    raise _TypeProofError(f"{label} exceeds the 16384-character proof limit")


def _alias_generic_parameter_names(source: str) -> tuple[str, ...]:
    tokens = _tokenize_swift_type(source)
    groups: list[list[_SwiftTypeToken]] = [[]]
    stack: list[str] = []
    pairs = {"(": ")", "[": "]", "<": ">"}
    closing = {value: key for key, value in pairs.items()}
    for token in tokens:
        if token.value in pairs:
            stack.append(token.value)
        elif token.value in closing and stack and stack[-1] == closing[token.value]:
            stack.pop()
        if token.value == "," and not stack:
            groups.append([])
        else:
            groups[-1].append(token)
    names: list[str] = []
    for group in groups:
        identifiers = [token.value for token in group if token.kind == "identifier"]
        if not identifiers:
            raise _TypeProofError("generic parameter has no identifier")
        if identifiers[0] in {"each", "repeat"}:
            raise _TypeProofError("generic parameter packs are unsupported")
        names.append(identifiers[0])
    if len(set(names)) != len(names):
        raise _TypeProofError("generic parameter names are duplicated")
    return tuple(names)


def _type_alias_declarations(
    sources: Mapping[str, bytes],
) -> tuple[_TypeAliasDeclaration, ...]:
    declarations: list[_TypeAliasDeclaration] = []
    head = re.compile(
        rf"\btypealias\s+({_SWIFT_IDENTIFIER_PATTERN})"
    )
    for path, raw_source in sorted(sources.items()):
        source = raw_source.decode("utf-8")
        code = inventory._swift_code_projection(source)
        for match in head.finditer(code):
            name = _swift_identifier_value(match.group(1))
            cursor = match.end()
            while cursor < len(code) and code[cursor].isspace():
                cursor += 1
            parameters: tuple[str, ...] = ()
            parse_error: str | None = None
            if cursor < len(code) and code[cursor] == "<":
                try:
                    closing = inventory._closing_delimiter_index(
                        source,
                        cursor,
                        "<",
                        ">",
                        f"generic typealias {name}@{path}",
                    )
                    parameters = _alias_generic_parameter_names(
                        source[cursor + 1:closing]
                    )
                    cursor = closing + 1
                except (inventory.InventoryError, _TypeProofError) as error:
                    parse_error = str(error)
            while cursor < len(code) and code[cursor].isspace():
                cursor += 1
            expression: _SwiftTypeNode | None = None
            if parse_error is None and (cursor >= len(code) or code[cursor] != "="):
                parse_error = "typealias declaration has no resolvable equals sign"
            if parse_error is None:
                try:
                    end = _typealias_rhs_end(
                        source,
                        cursor + 1,
                        f"typealias {name}@{path}",
                    )
                    expression = _parse_swift_type(source[cursor + 1:end].strip())
                except _TypeProofError as error:
                    parse_error = error.reason
            prefix_start = max(
                code.rfind("\n", 0, match.start()),
                code.rfind(";", 0, match.start()),
                code.rfind("{", 0, match.start()),
            ) + 1
            prefix = code[prefix_start:match.start()]
            visibility_match = re.search(
                r"\b(public|package|private|fileprivate|internal)\b",
                prefix,
            )
            visibility = visibility_match.group(1) if visibility_match else "internal"
            owner_stack = _brace_stack_at(source, match.start())
            declarations.append(
                _TypeAliasDeclaration(
                    path=path,
                    module=_swift_module_key(path),
                    module_name=_swift_module_name(path),
                    name=name,
                    parameters=parameters,
                    expression=expression,
                    visibility=visibility,
                    owner_stack=owner_stack,
                    owner_names=_owner_names_at(source, match.start()),
                    position=match.start(),
                    line=source.count("\n", 0, match.start()) + 1,
                    parse_error=parse_error,
                )
            )
    return tuple(declarations)


def _nominal_type_parameters_by_owner(
    sources: Mapping[str, bytes],
) -> dict[tuple[str, tuple[str, ...]], set[str]]:
    """Index nominal generic and protocol associated types by lexical owner."""

    result: dict[tuple[str, tuple[str, ...]], set[str]] = {}
    declaration = re.compile(
        rf"\b(struct|enum|class|actor|protocol)\s+({_SWIFT_IDENTIFIER_PATTERN})"
    )
    for path, raw_source in sorted(sources.items()):
        source = raw_source.decode("utf-8")
        code = inventory._swift_code_projection(source)
        module = _swift_module_key(path)
        for match in declaration.finditer(code):
            name = _swift_identifier_value(match.group(2))
            owner = (*_owner_names_at(source, match.start()), name)
            key = (module, owner)
            parameters = result.setdefault(key, set())
            cursor = match.end()
            while cursor < len(code) and code[cursor].isspace():
                cursor += 1
            if cursor < len(code) and code[cursor] == "<":
                try:
                    closing_generic = inventory._closing_delimiter_index(
                        source,
                        cursor,
                        "<",
                        ">",
                        f"nominal generic parameters {'.'.join(owner)}@{path}",
                    )
                    parameters.update(
                        _alias_generic_parameter_names(
                            source[cursor + 1:closing_generic]
                        )
                    )
                    cursor = closing_generic + 1
                except (inventory.InventoryError, _TypeProofError):
                    # The declaration's own bounded producer parse will reject
                    # endpoint-bearing evidence if this unsupported syntax matters.
                    pass
            opening_brace = code.find("{", cursor)
            if opening_brace < 0:
                continue
            intervening_semicolon = code.find(";", cursor, opening_brace)
            if intervening_semicolon >= 0:
                continue
            try:
                closing_brace = inventory._closing_delimiter_index(
                    source,
                    opening_brace,
                    "{",
                    "}",
                    f"nominal declaration {'.'.join(owner)}@{path}",
                )
            except inventory.InventoryError:
                continue
            if match.group(1) != "protocol":
                continue
            body = source[opening_brace + 1:closing_brace]
            body_code = inventory._swift_code_projection(body)
            for associated in re.finditer(
                rf"\bassociatedtype\s+({_SWIFT_IDENTIFIER_PATTERN})",
                body_code,
            ):
                if inventory._brace_depth_at(body, associated.start()) == 0:
                    parameters.add(_swift_identifier_value(associated.group(1)))
    return result


class _SwiftAliasResolver:
    def __init__(
        self,
        sources: Mapping[str, bytes],
        endpoint_types_by_path: Mapping[str, set[str]],
    ) -> None:
        self.sources = sources
        self.endpoint_types_by_path = endpoint_types_by_path
        self.aliases = _type_alias_declarations(sources)
        self.imports = {
            path: _swift_imports(raw_source.decode("utf-8"))
            for path, raw_source in sources.items()
        }
        self.nominal_type_parameters = _nominal_type_parameters_by_owner(sources)

    def generic_parameters_at(self, path: str, position: int) -> tuple[str, ...]:
        source = self.sources[path].decode("utf-8")
        parameters = set(_enclosing_generic_parameters(source, position))
        owner_names = _owner_names_at(source, position)
        module = _swift_module_key(path)
        for depth in range(1, len(owner_names) + 1):
            parameters.update(
                self.nominal_type_parameters.get(
                    (module, owner_names[:depth]),
                    set(),
                )
            )
        return tuple(sorted(parameters))

    def parse_and_resolve(
        self,
        type_source: str,
        *,
        path: str,
        position: int,
        generic_parameters: Iterable[str] = (),
    ) -> _SwiftTypeNode:
        parsed = _parse_swift_type(type_source)
        budget = [0]
        environment = {
            name: _SwiftTypeNode("generic_parameter", name=name)
            for name in generic_parameters
        }
        return self._resolve(
            parsed,
            path=path,
            position=position,
            environment=environment,
            stack=(),
            depth=0,
            budget=budget,
        )

    def _resolve(
        self,
        node: _SwiftTypeNode,
        *,
        path: str,
        position: int,
        environment: Mapping[str, _SwiftTypeNode],
        stack: tuple[tuple[str, int, str], ...],
        depth: int,
        budget: list[int],
    ) -> _SwiftTypeNode:
        if depth > 64:
            raise _TypeProofError("alias resolution exceeds the 64-level depth limit")
        budget[0] += 1
        if budget[0] > 4_096:
            raise _TypeProofError("alias resolution exceeds the 4096-node expansion limit")
        if node.kind == "nominal" and "." not in node.name and node.name in environment:
            if node.children:
                raise _TypeProofError(
                    f"generic parameter {node.name} is applied as a generic type"
                )
            return environment[node.name]
        if node.kind == "metatype":
            return _SwiftTypeNode(
                "metatype",
                children=(
                    self._resolve(
                        node.children[0],
                        path=path,
                        position=position,
                        environment=environment,
                        stack=stack,
                        depth=depth + 1,
                        budget=budget,
                    ),
                ),
            )
        if node.kind != "nominal":
            return _SwiftTypeNode(
                node.kind,
                name=node.name,
                children=tuple(
                    self._resolve(
                        child,
                        path=path,
                        position=position,
                        environment=environment,
                        stack=stack,
                        depth=depth + 1,
                        budget=budget,
                    )
                    for child in node.children
                ),
            )

        resolved_arguments = tuple(
            self._resolve(
                child,
                path=path,
                position=position,
                environment=environment,
                stack=stack,
                depth=depth + 1,
                budget=budget,
            )
            for child in node.children
        )
        declaration = self._lookup_alias(node.name, path=path, position=position)
        if declaration is None:
            return _SwiftTypeNode("nominal", name=node.name, children=resolved_arguments)
        if declaration.parse_error is not None or declaration.expression is None:
            raise _TypeProofError(
                declaration.parse_error or "alias expression is unresolved",
                alias=declaration.name,
            )
        if len(resolved_arguments) != len(declaration.parameters):
            raise _TypeProofError(
                f"generic arity mismatch: expected {len(declaration.parameters)}, "
                f"found {len(resolved_arguments)}",
                alias=declaration.name,
            )
        if declaration.identity in stack:
            chain = " -> ".join(item[2] for item in (*stack, declaration.identity))
            raise _TypeProofError(
                f"alias cycle detected: {chain}",
                alias=declaration.name,
            )
        alias_environment = dict(zip(declaration.parameters, resolved_arguments))
        return self._resolve(
            declaration.expression,
            path=declaration.path,
            position=declaration.position,
            environment=alias_environment,
            stack=(*stack, declaration.identity),
            depth=depth + 1,
            budget=budget,
        )

    def _lookup_alias(
        self,
        qualified_name: str,
        *,
        path: str,
        position: int,
    ) -> _TypeAliasDeclaration | None:
        parts = qualified_name.split(".")
        name = parts[-1]
        qualifier = ".".join(parts[:-1]) or None
        source = self.sources[path].decode("utf-8")
        if qualifier is None and _lexical_nominal_shadow(source, path, name, position):
            return None
        use_stack = _brace_stack_at(source, position)
        use_owner_names = _owner_names_at(source, position)
        use_module = _swift_module_key(path)
        use_module_name = _swift_module_name(path)
        use_package = _swift_package_key(path)
        imports = self.imports[path]
        ranked: list[tuple[int, _TypeAliasDeclaration]] = []
        for declaration in self.aliases:
            if declaration.name != name:
                continue
            rank: int | None = None
            if declaration.owner_stack:
                if declaration.path == path and tuple(use_stack[:len(declaration.owner_stack)]) == declaration.owner_stack:
                    rank = 100 + len(declaration.owner_stack)
                elif (
                    qualifier is not None
                    and declaration.owner_names
                    and qualifier.endswith(".".join(declaration.owner_names))
                ):
                    if declaration.path == path:
                        rank = 90 + len(declaration.owner_stack)
                    elif (
                        declaration.module == use_module
                        and declaration.visibility not in {"private", "fileprivate"}
                    ):
                        rank = 85
                    elif (
                        declaration.visibility == "package"
                        and _swift_package_key(declaration.path) == use_package
                    ):
                        rank = 80
                    elif (
                        declaration.visibility == "public"
                        and declaration.module_name in imports
                    ):
                        rank = 70
                elif (
                    qualifier is None
                    and declaration.owner_names
                    and use_owner_names
                    and declaration.owner_names == use_owner_names
                    and declaration.module == use_module
                    and declaration.visibility not in {"private", "fileprivate"}
                ):
                    rank = 82
            elif qualifier is not None:
                if qualifier == declaration.module_name:
                    if declaration.module == use_module:
                        rank = 80
                    elif declaration.visibility == "public" and qualifier in imports:
                        rank = 70
                elif declaration.owner_names and qualifier.endswith(".".join(declaration.owner_names)):
                    rank = 75
            elif declaration.path == path:
                rank = 65
            elif declaration.module == use_module and declaration.visibility not in {"private", "fileprivate"}:
                rank = 60
            elif (
                declaration.visibility == "package"
                and _swift_package_key(declaration.path) == use_package
            ):
                rank = 55
            elif declaration.visibility == "public" and declaration.module_name in imports:
                rank = 50
            if rank is not None:
                ranked.append((rank, declaration))
        if not ranked:
            return None
        best_rank = max(rank for rank, _ in ranked)
        best = [declaration for rank, declaration in ranked if rank == best_rank]
        if len(best) != 1:
            names = ", ".join(f"{item.path}:{item.line}" for item in best)
            raise _TypeProofError(
                f"ambiguous alias lookup for {qualified_name}: {names}",
                alias=qualified_name,
            )
        return best[0]

    def endpoint_relation(
        self,
        node: _SwiftTypeNode,
        *,
        path: str,
        position: int,
    ) -> bool:
        if node.kind == "metatype":
            return False
        if node.kind == "function":
            return self._endpoint_value_relation(
                node.children[-1],
                path=path,
                position=position,
            )
        if node.kind != "nominal":
            return False
        if node.name == "Networking.Endpoint":
            return True
        return (
            node.name == "Endpoint"
            and "Endpoint" in self.endpoint_types_by_path[path]
            and not _lexical_nominal_shadow(
                self.sources[path].decode("utf-8"),
                path,
                "Endpoint",
                position,
            )
        )

    def _endpoint_value_relation(
        self,
        node: _SwiftTypeNode,
        *,
        path: str,
        position: int,
    ) -> bool:
        if node.kind == "metatype":
            return False
        if node.kind == "function":
            return self._endpoint_value_relation(
                node.children[-1],
                path=path,
                position=position,
            )
        if node.kind == "nominal":
            if node.name == "Networking.Endpoint":
                return True
            if (
                node.name == "Endpoint"
                and "Endpoint" in self.endpoint_types_by_path[path]
                and not _lexical_nominal_shadow(
                    self.sources[path].decode("utf-8"),
                    path,
                    "Endpoint",
                    position,
                )
            ):
                return True
            return any(
                self._endpoint_value_relation(child, path=path, position=position)
                for child in node.children
            )
        return any(
            self._endpoint_value_relation(child, path=path, position=position)
            for child in node.children
        )


def _find_stored_property_assignment(
    source: str,
    type_start: int,
    label: str,
) -> tuple[int, str] | None:
    code = inventory._swift_code_projection(source)
    pairs = {"(": ")", "[": "]", "<": ">"}
    closing = {value: key for key, value in pairs.items()}
    stack: list[str] = []
    cursor = type_start
    limit = min(len(code), type_start + 16_384)
    while cursor < limit:
        character = code[cursor]
        if character in pairs:
            stack.append(character)
        elif character in closing and stack and stack[-1] == closing[character]:
            stack.pop()
        elif not stack and character == "=":
            return cursor, source[type_start:cursor].strip()
        elif not stack and character in {"{", "}", ";"}:
            return None
        elif not stack and character in {"\n", "\r"}:
            candidate = source[type_start:cursor].strip()
            lookahead = cursor + 1
            while lookahead < len(code) and code[lookahead].isspace():
                lookahead += 1
            if lookahead < len(code) and code[lookahead] == "=":
                cursor = lookahead
                continue
            if candidate:
                try:
                    _parse_swift_type(candidate)
                except _TypeProofError:
                    pass
                else:
                    return None
        cursor += 1
    if cursor >= limit and limit < len(code):
        raise _TypeProofError(f"{label} exceeds the 16384-character proof limit")
    return None


def _stored_initializer_expression_end(source: str, start: int, label: str) -> int:
    code = _swift_structure_projection(source)
    pairs = {"(": ")", "[": "]", "{": "}"}
    closing = {value: key for key, value in pairs.items()}
    stack: list[str] = []
    cursor = start
    while cursor < len(source) and source[cursor].isspace():
        cursor += 1
    expression_start = cursor
    while cursor < len(code):
        character = code[cursor]
        if character == "<" and _looks_like_generic_angle(code, cursor):
            stack.append(character)
        elif character == ">" and stack and stack[-1] == "<":
            stack.pop()
        elif character == "{" and not stack and cursor > expression_start:
            closing_brace = inventory._closing_delimiter_index(
                source,
                cursor,
                "{",
                "}",
                label,
            )
            observer = code[cursor + 1:closing_brace]
            if re.match(r"\s*(?:willSet|didSet)\b", observer):
                break
            stack.append(character)
        elif character in pairs:
            stack.append(character)
        elif character in closing:
            if stack and stack[-1] == closing[character]:
                stack.pop()
            elif not stack:
                break
        elif not stack and character in {",", ";", "\n", "\r"}:
            if character in {"\n", "\r"} and _continues_swift_expression(
                code,
                cursor,
                expression_start,
            ):
                cursor += 1
                continue
            break
        cursor += 1
    if stack:
        raise _TypeProofError(f"{label} has an unbalanced initializer")
    return cursor


def _looks_like_generic_angle(code: str, position: int) -> bool:
    previous = position - 1
    while previous >= 0 and code[previous].isspace():
        previous -= 1
    following = position + 1
    while following < len(code) and code[following].isspace():
        following += 1
    if previous < 0 or following >= len(code):
        return False
    if previous != position - 1:
        return False
    return (
        (code[previous].isalnum() or code[previous] in {"_", ")", "]", ">"})
        and (code[following].isalpha() or code[following] in {"_", "(", "[", "@"})
    )


def _continues_swift_expression(code: str, position: int, start: int) -> bool:
    previous = position - 1
    while previous >= start and code[previous] in {" ", "\t", "\n", "\r"}:
        previous -= 1
    following = position + 1
    while following < len(code) and code[following].isspace():
        following += 1
    if following < len(code) and code[following] in {".", "{"}:
        return True
    if previous >= start and code[previous] in {".", ",", "=", "+", "-", "*", "/", "?", ":", "&", "|"}:
        return True
    return False


def _stored_binding_tail_end(source: str, start: int) -> int:
    code = _swift_structure_projection(source)
    pairs = {"(": ")", "[": "]", "{": "}"}
    closing = {value: key for key, value in pairs.items()}
    stack: list[str] = []
    cursor = start
    while cursor < len(code):
        character = code[cursor]
        if character == "<" and _looks_like_generic_angle(code, cursor):
            stack.append(character)
        elif character == ">" and stack and stack[-1] == "<":
            stack.pop()
        elif character in pairs:
            stack.append(character)
        elif character in closing:
            if stack and stack[-1] == closing[character]:
                stack.pop()
            elif not stack:
                break
        elif not stack and character in {";", "}"}:
            break
        elif not stack and character in {"\n", "\r"}:
            previous = cursor - 1
            while previous >= start and code[previous] in {" ", "\t"}:
                previous -= 1
            if previous < start or code[previous] != ",":
                if not _continues_swift_expression(code, cursor, start):
                    break
        cursor += 1
    return cursor


def _top_level_binding_segments(
    source: str,
    start: int,
    end: int,
) -> tuple[tuple[int, int], ...]:
    code = _swift_structure_projection(source)
    pairs = {"(": ")", "[": "]", "{": "}"}
    closing = {value: key for key, value in pairs.items()}
    stack: list[str] = []
    segments: list[tuple[int, int]] = []
    segment_start = start
    cursor = start
    while cursor < end:
        character = code[cursor]
        if character == "<" and _looks_like_generic_angle(code, cursor):
            stack.append(character)
        elif character == ">" and stack and stack[-1] == "<":
            stack.pop()
        elif character in pairs:
            stack.append(character)
        elif character in closing and stack and stack[-1] == closing[character]:
            stack.pop()
        elif character == "," and not stack:
            segments.append((segment_start, cursor))
            segment_start = cursor + 1
        cursor += 1
    segments.append((segment_start, end))
    return tuple(segments)


def _binding_type_and_assignment(
    source: str,
    start: int,
    end: int,
) -> tuple[int, str | None] | None:
    code = _swift_structure_projection(source)
    pairs = {"(": ")", "[": "]", "{": "}"}
    closing = {value: key for key, value in pairs.items()}
    stack: list[str] = []
    colon: int | None = None
    cursor = start
    while cursor < end:
        character = code[cursor]
        if character == "<" and _looks_like_generic_angle(code, cursor):
            stack.append(character)
        elif character == ">" and stack and stack[-1] == "<":
            stack.pop()
        elif character in pairs:
            stack.append(character)
        elif character in closing and stack and stack[-1] == closing[character]:
            stack.pop()
        elif not stack and character == ":" and colon is None:
            colon = cursor
        elif not stack and character == "=":
            type_source = None if colon is None else source[colon + 1:cursor].strip()
            return cursor, type_source
        cursor += 1
    return None


def _stored_property_declarations(source: str, path: str) -> list[_StoredPropertyDeclaration]:
    code = inventory._swift_code_projection(source)
    pattern = re.compile(r"\b(?:let|var)\b")
    declarations: list[_StoredPropertyDeclaration] = []
    for match in pattern.finditer(code):
        if not _is_global_or_type_member(source, match.start()):
            continue
        tail_end = _stored_binding_tail_end(source, match.end())
        for segment_start, segment_end in _top_level_binding_segments(
            source,
            match.end(),
            tail_end,
        ):
            symbol_match = re.match(
                rf"\s*({_SWIFT_IDENTIFIER_PATTERN})",
                code[segment_start:segment_end],
            )
            if symbol_match is None:
                continue
            symbol = _swift_identifier_value(symbol_match.group(1))
            symbol_start = segment_start + symbol_match.start(1)
            after_symbol = segment_start + symbol_match.end(1)
            assignment = _binding_type_and_assignment(
                source,
                after_symbol,
                segment_end,
            )
            if assignment is None:
                continue
            equals, type_source = assignment
            initializer_end = min(
                segment_end,
                _stored_initializer_expression_end(
                    source,
                    equals + 1,
                    f"stored property initializer {symbol}@{path}",
                ),
            )
            declarations.append(
                _StoredPropertyDeclaration(
                    symbol=symbol,
                    start=symbol_start,
                    end=initializer_end,
                    type_source=type_source,
                    initializer=source[equals + 1:initializer_end].strip(),
                    initializer_start=equals + 1,
                )
            )
    return declarations


def _local_binding_declarations(
    source: str,
    path: str,
    excluded_regions: Sequence[tuple[int, int]],
) -> list[tuple[str, _StoredPropertyDeclaration]]:
    code = inventory._swift_code_projection(source)
    pattern = re.compile(r"\b(let|var)\b")
    declarations: list[tuple[str, _StoredPropertyDeclaration]] = []
    for match in pattern.finditer(code):
        if any(start <= match.start() < end for start, end in excluded_regions):
            continue
        tail_end = _stored_binding_tail_end(source, match.end())
        for segment_start, segment_end in _top_level_binding_segments(
            source,
            match.end(),
            tail_end,
        ):
            symbol_match = re.match(
                rf"\s*({_SWIFT_IDENTIFIER_PATTERN})",
                code[segment_start:segment_end],
            )
            if symbol_match is None:
                continue
            symbol = _swift_identifier_value(symbol_match.group(1))
            symbol_start = segment_start + symbol_match.start(1)
            after_symbol = segment_start + symbol_match.end(1)
            assignment = _binding_type_and_assignment(
                source,
                after_symbol,
                segment_end,
            )
            if assignment is None:
                continue
            equals, type_source = assignment
            initializer_end = min(
                segment_end,
                _stored_initializer_expression_end(
                    source,
                    equals + 1,
                    f"local binding initializer {symbol}@{path}",
                ),
            )
            declarations.append(
                (
                    match.group(1),
                    _StoredPropertyDeclaration(
                        symbol=symbol,
                        start=symbol_start,
                        end=initializer_end,
                        type_source=type_source,
                        initializer=source[equals + 1:initializer_end].strip(),
                        initializer_start=equals + 1,
                    ),
                )
            )
    return declarations


def _endpoint_namespace_aliases_at(
    source: str,
    path: str,
    position: int,
) -> set[str]:
    """Return file/type-scope names proven equal to Endpoints.self at a use site."""

    code = inventory._swift_code_projection(source)
    declaration = re.compile(
        rf"\b(?:let|var)\s+({_SWIFT_IDENTIFIER_PATTERN})"
        r"(?:\s*:[^=\n{}]+)?\s*=\s*"
        r"(?:(Networking)\s*\.\s*)?Endpoints\s*\.\s*self\b"
    )
    use_owner = _owner_names_at(source, position)
    aliases: set[str] = set()
    for match in declaration.finditer(code):
        if not _is_global_or_type_member(source, match.start()):
            continue
        if match.group(2) is None and _lexical_nominal_shadow(
            source,
            path,
            "Endpoints",
            match.start(),
        ):
            continue
        declaration_owner = _owner_names_at(source, match.start())
        if declaration_owner and declaration_owner != use_owner:
            continue
        aliases.add(_swift_identifier_value(match.group(1)))
    return aliases


def _endpoint_initializer_matches(
    initializer: str,
    *,
    source: str,
    path: str,
    absolute_start: int,
    endpoint_type_names: set[str],
    endpoint_factory_names: set[str],
    endpoint_namespace_names: set[str] | None = None,
    factory_references_only: bool = False,
) -> tuple[list[tuple[int, int, str]], list[tuple[int, int]]]:
    code = inventory._swift_code_projection(initializer)
    factories: list[tuple[int, int, str]] = []
    if endpoint_factory_names:
        names = "|".join(
            re.escape(name)
            for name in sorted(endpoint_factory_names, key=len, reverse=True)
        )
        pattern = re.compile(
            rf"\b(?:(Networking)\s*\.\s*)?Endpoints\s*\.\s*"
            rf"({names})(?![A-Za-z0-9_])"
        )
        for match in pattern.finditer(code):
            if match.group(1) is None and _lexical_nominal_shadow(
                source,
                path,
                "Endpoints",
                absolute_start + match.start(),
            ):
                continue
            if factory_references_only and _call_follows(code, match.end()):
                continue
            factories.append((match.start(), match.end(), match.group(2)))
        namespace_aliases = _endpoint_namespace_aliases_at(
            source,
            path,
            absolute_start,
        )
        namespace_aliases.update(endpoint_namespace_names or set())
        if namespace_aliases:
            alias_pattern = "|".join(
                re.escape(name)
                for name in sorted(namespace_aliases, key=len, reverse=True)
            )
            indirect = re.compile(
                rf"(?<![A-Za-z0-9_.])(?:Self\s*\.\s*)?"
                rf"(?P<namespace>{alias_pattern})\s*\.\s*"
                rf"(?P<factory>{names})"
                r"(?![A-Za-z0-9_])"
            )
            for match in indirect.finditer(code):
                if factory_references_only and _call_follows(code, match.end()):
                    continue
                factories.append(
                    (match.start(), match.end(), match.group("factory"))
                )
        if (
            "Endpoints" in _owner_names_at(source, absolute_start)
            and not _lexical_nominal_shadow(source, path, "Endpoints", absolute_start)
        ):
            unqualified = re.compile(
                rf"(?<![A-Za-z0-9_.])({names})(?![A-Za-z0-9_])"
            )
            for match in unqualified.finditer(code):
                if factory_references_only and _call_follows(code, match.end()):
                    continue
                factories.append((match.start(), match.end(), match.group(1)))
            self_qualified = re.compile(
                rf"\bSelf\s*\.\s*({names})(?![A-Za-z0-9_])"
            )
            for match in self_qualified.finditer(code):
                if factory_references_only and _call_follows(code, match.end()):
                    continue
                factories.append((match.start(), match.end(), match.group(1)))
    endpoint_type = _endpoint_type_pattern(source, path, endpoint_type_names)
    direct_pattern = re.compile(
        rf"(?<![A-Za-z0-9_.]){endpoint_type}"
        r"(?:\s*\.\s*init\b(?:\s*\()?|\s*\()"
    )
    direct: list[tuple[int, int]] = []
    for match in direct_pattern.finditer(code):
        if _endpoint_reference_is_shadowed(
            source,
            path,
            match.group(0),
            endpoint_type_names,
            absolute_start + match.start(),
        ):
            continue
        if factory_references_only and (
            "(" in code[match.start():match.end()]
            or _call_follows(code, match.end())
        ):
            continue
        direct.append((match.start(), match.end()))
    return factories, direct


def _call_follows(code: str, position: int) -> bool:
    cursor = position
    while cursor < len(code) and code[cursor].isspace():
        cursor += 1
    return cursor < len(code) and code[cursor] == "("


def _previous_nonwhitespace(code: str, position: int) -> int:
    cursor = position - 1
    while cursor >= 0 and code[cursor].isspace():
        cursor -= 1
    return cursor


def _next_nonwhitespace(code: str, position: int) -> int:
    cursor = position
    while cursor < len(code) and code[cursor].isspace():
        cursor += 1
    return cursor


def _grouping_parenthesis_is_local_expression(
    code: str,
    opening: int,
) -> bool:
    """Reject a call argument list such as ``receiver(make)()`` as grouping."""

    previous = _previous_nonwhitespace(code, opening)
    if previous < 0:
        return True
    if code[previous] in ".)]`":
        return False
    if code[previous] in "?!":
        keyword_end = _previous_nonwhitespace(code, previous)
        keyword_match = re.search(r"([A-Za-z_][A-Za-z0-9_]*)$", code[:keyword_end + 1])
        return keyword_match is not None and keyword_match.group(1) == "try"
    if code[previous].isalnum() or code[previous] == "_":
        keyword_match = re.search(r"([A-Za-z_][A-Za-z0-9_]*)$", code[:previous + 1])
        return keyword_match is not None and keyword_match.group(1) in {
            "await",
            "return",
            "throw",
            "try",
            "yield",
        }
    return True


def _identifier_is_immediate_callee(
    code: str,
    start: int,
    end: int,
) -> bool:
    """Prove a bounded identifier occurrence is the immediate call callee."""

    expression_start = start
    expression_end = end
    for _ in range(64):
        opening = _previous_nonwhitespace(code, expression_start)
        closing = _next_nonwhitespace(code, expression_end)
        if (
            opening < 0
            or closing >= len(code)
            or code[opening] != "("
            or code[closing] != ")"
        ):
            break
        try:
            matching = inventory._closing_delimiter_index(
                code,
                opening,
                "(",
                ")",
                "local function-value grouping",
            )
        except inventory.InventoryError:
            return False
        if matching != closing or not _grouping_parenthesis_is_local_expression(
            code,
            opening,
        ):
            return False
        expression_start = opening
        expression_end = closing + 1
    else:
        return False

    cursor = _next_nonwhitespace(code, expression_end)
    if cursor < len(code) and code[cursor] in "?!":
        cursor = _next_nonwhitespace(code, cursor + 1)
    return cursor < len(code) and code[cursor] == "("


def _local_identifier_occurrences(
    code: str,
    symbol: str,
) -> tuple[re.Match[str], ...]:
    raw_symbol = re.escape(symbol)
    pattern = re.compile(
        rf"(?<![A-Za-z0-9_])(?:`{raw_symbol}`|{raw_symbol})(?![A-Za-z0-9_])"
    )
    occurrences: list[re.Match[str]] = []
    for match in pattern.finditer(code):
        previous = _previous_nonwhitespace(code, match.start())
        if previous >= 0 and code[previous] == ".":
            continue
        following = _next_nonwhitespace(code, match.end())
        if following < len(code) and code[following] == ":":
            continue
        occurrences.append(match)
        if len(occurrences) > 256:
            raise _TypeProofError(
                f"local function value {symbol} exceeds the 256-use proof limit"
            )
    return tuple(occurrences)


def _classify_local_function_value_uses(
    source: str,
    symbol: str,
) -> tuple[_LocalFunctionValueUse, ...]:
    """Classify local function-value references without general Swift parsing."""

    code = inventory._swift_code_projection(source)
    uses: list[_LocalFunctionValueUse] = []
    for occurrence in _local_identifier_occurrences(code, symbol):
        direct = _identifier_is_immediate_callee(
            code,
            occurrence.start(),
            occurrence.end(),
        )
        closure_opening = next(
            (
                opening
                for opening in _brace_stack_at(code, occurrence.start())
                if not _is_control_flow_brace(code, opening)
            ),
            None,
        )
        if closure_opening is not None:
            role = "escape"
            reason = "captured by an unresolved closure or declaration scope"
        elif direct:
            role = "direct_invocation"
            reason = "identifier is the immediate syntactic callee"
        else:
            role = "escape"
            reason = "bare or unsupported function-value use"
        uses.append(
            _LocalFunctionValueUse(
                start=occurrence.start(),
                end=occurrence.end(),
                role=role,
                reason=reason,
            )
        )
    return tuple(uses)


def _mask_source_region(masked: list[str], start: int, end: int) -> None:
    for index in range(max(0, start), min(len(masked), end)):
        if masked[index] not in {"\n", "\r"}:
            masked[index] = " "


def _reference_is_in_return_expression(code: str, position: int) -> bool:
    statement_start = max(
        code.rfind("\n", 0, position),
        code.rfind("\r", 0, position),
        code.rfind(";", 0, position),
        code.rfind("{", 0, position),
        code.rfind("}", 0, position),
    ) + 1
    return re.search(r"\breturn\b", code[statement_start:position]) is not None


def _reference_is_direct_discard(
    code: str,
    symbol: str,
    position: int,
) -> bool:
    statement_start = max(
        code.rfind("\n", 0, position),
        code.rfind("\r", 0, position),
        code.rfind(";", 0, position),
        code.rfind("{", 0, position),
        code.rfind("}", 0, position),
    ) + 1
    endings = [
        value for value in (
            code.find("\n", position),
            code.find("\r", position),
            code.find(";", position),
        )
        if value >= 0
    ]
    statement_end = min(endings) if endings else len(code)
    statement = code[statement_start:statement_end].strip()
    return re.fullmatch(rf"_\s*=\s*`?{re.escape(symbol)}`?", statement) is not None


def _brace_regions(code: str) -> tuple[tuple[int, int], ...]:
    stack: list[int] = []
    regions: list[tuple[int, int]] = []
    for index, character in enumerate(code):
        if character == "{":
            stack.append(index)
        elif character == "}" and stack:
            regions.append((stack.pop(), index + 1))
    return tuple(regions)


def _is_control_flow_brace(code: str, opening: int) -> bool:
    header_start = max(
        code.rfind(";", 0, opening),
        code.rfind("{", 0, opening),
        code.rfind("}", 0, opening),
    ) + 1
    header = code[header_start:opening].strip()
    matches = list(
        re.finditer(
            r"(?<![A-Za-z0-9_.#])"
            r"(?:if|else|guard|switch|for|while|repeat|do|catch|defer)"
            r"(?=\s|$)",
            header,
        )
    )
    return bool(matches)


def _initializer_endpoint_evidence(
    declaration: _StoredPropertyDeclaration,
    *,
    source: str,
    path: str,
    resolver: _SwiftAliasResolver,
    endpoint_type_names: set[str],
    endpoint_factory_names: set[str],
    propagate_endpoint_locals: bool = True,
    normal_result_factory_references_only: bool = False,
) -> _InitializerEndpointEvidence:
    initializer = declaration.initializer
    factories, direct = _endpoint_initializer_matches(
        initializer,
        source=source,
        path=path,
        absolute_start=declaration.initializer_start,
        endpoint_type_names=endpoint_type_names,
        endpoint_factory_names=endpoint_factory_names,
    )
    code = inventory._swift_code_projection(initializer)
    first = next((index for index, value in enumerate(code) if not value.isspace()), -1)
    if first < 0 or code[first] != "{":
        if not factories and not direct:
            return _InitializerEndpointEvidence()
        return _InitializerEndpointEvidence(
            operations=tuple(sorted({item[2] for item in factories})),
            direct_endpoint=bool(direct),
        )
    closing = inventory._closing_delimiter_index(
        initializer,
        first,
        "{",
        "}",
        f"stored closure {declaration.symbol}@{path}",
    )
    body = initializer[first + 1:closing]
    body_offset = first + 1

    nested_regions: list[tuple[int, int, str]] = []
    nested_function = re.compile(
        rf"\bfunc\s+({_SWIFT_IDENTIFIER_PATTERN})(?:\s*<[^>{{}}]*>)?\s*\("
    )
    body_code = inventory._swift_code_projection(body)
    for match in nested_function.finditer(body_code):
        opening_parenthesis = body_code.find("(", match.start(), match.end())
        closing_parenthesis = inventory._closing_delimiter_index(
            body,
            opening_parenthesis,
            "(",
            ")",
            f"nested function {match.group(1)}@{path}",
        )
        opening_brace = body_code.find("{", closing_parenthesis + 1)
        if opening_brace < 0:
            continue
        closing_brace = inventory._closing_delimiter_index(
            body,
            opening_brace,
            "{",
            "}",
            f"nested function {match.group(1)}@{path}",
        )
        nested_regions.append(
            (match.start(), closing_brace + 1, _swift_identifier_value(match.group(1)))
        )

    local_bindings = _local_binding_declarations(
        body,
        path,
        [(start, end) for start, end, _ in nested_regions],
    )
    endpoint_namespace_names: set[str] = set()
    mutable_endpoint_namespaces: set[str] = set()
    endpoint_namespace = re.compile(
        r"^\s*\(?\s*(?:(Networking)\s*\.\s*)?"
        r"Endpoints\s*\.\s*self\s*\)?\s*$"
    )
    for mutability, local in local_bindings:
        namespace_match = endpoint_namespace.fullmatch(
            inventory._swift_code_projection(local.initializer)
        )
        if namespace_match is None:
            continue
        absolute_local_start = (
            declaration.initializer_start + body_offset + local.initializer_start
        )
        if namespace_match.group(1) is None and _lexical_nominal_shadow(
            source,
            path,
            "Endpoints",
            absolute_local_start,
        ):
            continue
        endpoint_namespace_names.add(local.symbol)
        if mutability == "var":
            mutable_endpoint_namespaces.add(local.symbol)

    if endpoint_factory_names:
        factory_pattern = "|".join(
            re.escape(name)
            for name in sorted(endpoint_factory_names, key=len, reverse=True)
        )
        for namespace in mutable_endpoint_namespaces:
            if re.search(
                rf"\b{re.escape(namespace)}\s*\.\s*(?:{factory_pattern})"
                r"(?![A-Za-z0-9_])",
                body_code,
            ):
                return _InitializerEndpointEvidence(
                    ambiguous_reason=(
                        f"mutable Endpoint factory namespace {namespace} cannot "
                        "be proven stable"
                    )
                )

    masked_body = list(body_code)
    propagated_operations: set[str] = set()
    propagated_direct = False
    for start, end, symbol in nested_regions:
        region = body[start:end]
        nested_factories, nested_direct = _endpoint_initializer_matches(
            region,
            source=source,
            path=path,
            absolute_start=declaration.initializer_start + body_offset + start,
            endpoint_type_names=endpoint_type_names,
            endpoint_factory_names=endpoint_factory_names,
            endpoint_namespace_names=endpoint_namespace_names,
        )
        if nested_factories or nested_direct:
            outside = body_code[:start] + (" " * (end - start)) + body_code[end:]
            try:
                uses = _classify_local_function_value_uses(outside, symbol)
            except _TypeProofError as error:
                return _InitializerEndpointEvidence(
                    ambiguous_reason=(
                        f"nested Endpoint-producing function {symbol} has an "
                        f"unsupported use: {error.reason}"
                    )
                )
            escaping = next(
                (use for use in uses if use.role != "direct_invocation"),
                None,
            )
            returned_directly = propagate_endpoint_locals and any(
                _reference_is_in_return_expression(outside, use.start)
                for use in uses
            )
            if escaping is not None:
                return _InitializerEndpointEvidence(
                    ambiguous_reason=(
                        f"nested Endpoint-producing function {symbol} has an unresolved "
                        f"escape: {escaping.reason}"
                    )
                )
            if returned_directly:
                propagated_operations.update(item[2] for item in nested_factories)
                propagated_direct = propagated_direct or bool(nested_direct)
        for index in range(start, end):
            if masked_body[index] not in {"\n", "\r"}:
                masked_body[index] = " "
    masked = "".join(masked_body)

    propagated_capable = False
    for mutability, local in local_bindings:
        local_absolute_start = (
            declaration.initializer_start + body_offset + local.initializer_start
        )
        local_factories, local_direct = _endpoint_initializer_matches(
            local.initializer,
            source=source,
            path=path,
            absolute_start=local_absolute_start,
            endpoint_type_names=endpoint_type_names,
            endpoint_factory_names=endpoint_factory_names,
            endpoint_namespace_names=endpoint_namespace_names,
        )
        local_type_endpoint = False
        local_type_endpoint_factory = False
        if local.type_source is not None:
            try:
                local_resolved = resolver.parse_and_resolve(
                    local.type_source,
                    path=path,
                    position=(
                        declaration.initializer_start + body_offset + local.start
                    ),
                    generic_parameters=resolver.generic_parameters_at(
                        path,
                        declaration.start,
                    ),
                )
                local_type_endpoint = resolver._endpoint_value_relation(
                    local_resolved,
                    path=path,
                    position=(
                        declaration.initializer_start + body_offset + local.start
                    ),
                )
                local_type_endpoint_factory = (
                    local_resolved.kind == "function"
                    and resolver.endpoint_relation(
                        local_resolved,
                        path=path,
                        position=(
                            declaration.initializer_start
                            + body_offset
                            + local.start
                        ),
                    )
                )
            except _TypeProofError as error:
                if local_factories or local_direct:
                    return _InitializerEndpointEvidence(
                        ambiguous_reason=(
                            f"local Endpoint-producing binding {local.symbol} has "
                            f"an unresolved type: {error.reason}"
                        )
                    )
        if not local_factories and not local_direct and not local_type_endpoint:
            continue
        local_code = inventory._swift_code_projection(local.initializer)
        local_first = next(
            (index for index, value in enumerate(local_code) if not value.isspace()),
            -1,
        )
        local_factory_value = (
            local_type_endpoint_factory
            or (
                (local_factories or local_direct)
                and local_first >= 0
                and local_code[local_first] == "{"
            )
            or any(
                not _call_follows(local_code, end)
                for _, end, _ in local_factories
            )
            or any(
                "(" not in local_code[start:end]
                and not _call_follows(local_code, end)
                for start, end in local_direct
            )
        )
        if not propagate_endpoint_locals and not local_factory_value:
            _mask_source_region(masked_body, local.start, local.end)
            continue
        if (
            (local_factories or local_direct)
            and local_first >= 0
            and local_code[local_first] != "{"
        ):
            for opening, end in _brace_regions(local_code):
                region_factories, region_direct = _endpoint_initializer_matches(
                    local.initializer[opening:end],
                    source=source,
                    path=path,
                    absolute_start=local_absolute_start + opening,
                    endpoint_type_names=endpoint_type_names,
                    endpoint_factory_names=endpoint_factory_names,
                    endpoint_namespace_names=endpoint_namespace_names,
                )
                if region_factories or region_direct:
                    return _InitializerEndpointEvidence(
                        ambiguous_reason=(
                            f"local binding {local.symbol} passes an Endpoint-producing "
                            "closure through an unresolved initializer"
                        )
                    )
        current_masked = "".join(masked_body)
        outside = (
            current_masked[:local.start]
            + (" " * (local.end - local.start))
            + current_masked[local.end:]
        )
        local_uses = outside[local.end:]
        if local_factory_value:
            try:
                uses = _classify_local_function_value_uses(
                    local_uses,
                    local.symbol,
                )
            except _TypeProofError as error:
                return _InitializerEndpointEvidence(
                    ambiguous_reason=(
                        f"local Endpoint-producing binding {local.symbol} has an "
                        f"unsupported use: {error.reason}"
                    )
                )
            escaping = next(
                (use for use in uses if use.role != "direct_invocation"),
                None,
            )
            if escaping is not None:
                return _InitializerEndpointEvidence(
                    ambiguous_reason=(
                        f"local Endpoint-producing binding {local.symbol} has an "
                        f"unresolved escape: {escaping.reason}"
                    )
                )
            returned_directly = propagate_endpoint_locals and any(
                _reference_is_in_return_expression(local_uses, use.start)
                for use in uses
            )
            use_count = len(uses)
        else:
            try:
                value_uses = _local_identifier_occurrences(
                    inventory._swift_code_projection(local_uses),
                    local.symbol,
                )
            except _TypeProofError as error:
                return _InitializerEndpointEvidence(
                    ambiguous_reason=(
                        f"local Endpoint value {local.symbol} has an unsupported "
                        f"use: {error.reason}"
                    )
                )
            returned_directly = propagate_endpoint_locals and any(
                _reference_is_in_return_expression(local_uses, use.start())
                for use in value_uses
            )
            unresolved_value_use = next(
                (
                    use
                    for use in value_uses
                    if not _reference_is_in_return_expression(
                        local_uses,
                        use.start(),
                    )
                    and not _reference_is_direct_discard(
                        local_uses,
                        local.symbol,
                        use.start(),
                    )
                ),
                None,
            )
            if unresolved_value_use is not None:
                return _InitializerEndpointEvidence(
                    ambiguous_reason=(
                        f"local Endpoint value {local.symbol} has an unresolved use"
                    )
                )
            use_count = len(value_uses)
        if mutability == "var" and use_count:
            return _InitializerEndpointEvidence(
                ambiguous_reason=(
                    f"mutable Endpoint-producing local binding {local.symbol} "
                    "cannot be proven nonescaping"
                )
            )
        if returned_directly:
            propagated_operations.update(item[2] for item in local_factories)
            propagated_direct = propagated_direct or bool(local_direct)
            propagated_capable = propagated_capable or local_type_endpoint
        _mask_source_region(masked_body, local.start, local.end)

    masked = "".join(masked_body)
    for opening, end in sorted(
        _brace_regions(masked),
        key=lambda item: item[1] - item[0],
    ):
        region_factories, region_direct = _endpoint_initializer_matches(
            body[opening:end],
            source=source,
            path=path,
            absolute_start=(
                declaration.initializer_start + body_offset + opening
            ),
            endpoint_type_names=endpoint_type_names,
            endpoint_factory_names=endpoint_factory_names,
            endpoint_namespace_names=endpoint_namespace_names,
        )
        if not region_factories and not region_direct:
            continue
        cursor = end
        while cursor < len(masked) and masked[cursor].isspace():
            cursor += 1
        if cursor < len(masked) and masked[cursor] == ")":
            cursor += 1
            while cursor < len(masked) and masked[cursor].isspace():
                cursor += 1
        immediately_invoked = cursor < len(masked) and masked[cursor] == "("
        statement_start = max(
            masked.rfind("\n", 0, opening),
            masked.rfind("\r", 0, opening),
            masked.rfind(";", 0, opening),
        ) + 1
        prefix = masked[statement_start:opening]
        discarded_immediate = (
            immediately_invoked
            and re.fullmatch(r"\s*_\s*=\s*\(?\s*", prefix) is not None
        )
        if discarded_immediate:
            _mask_source_region(masked_body, opening, end)

    masked = "".join(masked_body)
    for opening, end in _brace_regions(masked):
        if _is_control_flow_brace(masked, opening):
            continue
        region_factories, region_direct = _endpoint_initializer_matches(
            body[opening:end],
            source=source,
            path=path,
            absolute_start=(
                declaration.initializer_start + body_offset + opening
            ),
            endpoint_type_names=endpoint_type_names,
            endpoint_factory_names=endpoint_factory_names,
            endpoint_namespace_names=endpoint_namespace_names,
        )
        if region_factories or region_direct:
            return _InitializerEndpointEvidence(
                ambiguous_reason=(
                    "nested Endpoint-producing closure has an unresolved escape"
                )
            )

    owned_returns: list[tuple[int, int]] = []
    for match in re.finditer(r"\breturn\b", masked):
        end = _stored_initializer_expression_end(
            body,
            match.end(),
            f"stored closure return {declaration.symbol}@{path}",
        )
        owned_returns.append((match.end(), end))
    relevant_ranges: list[tuple[int, int]] = []
    if owned_returns:
        relevant_ranges.extend(owned_returns)
    else:
        stack: list[str] = []
        statement_start = 0
        statements: list[tuple[int, int]] = []
        pairs = {"(": ")", "[": "]", "<": ">", "{": "}"}
        closing_pairs = {value: key for key, value in pairs.items()}
        for index, character in enumerate(masked):
            if character in pairs:
                stack.append(character)
            elif character in closing_pairs and stack and stack[-1] == closing_pairs[character]:
                stack.pop()
            elif not stack and character in {";", "\n", "\r"}:
                if masked[statement_start:index].strip():
                    statements.append((statement_start, index))
                statement_start = index + 1
        if masked[statement_start:].strip():
            statements.append((statement_start, len(masked)))
        if statements:
            relevant_ranges.append(statements[-1])

    operations = set(propagated_operations)
    direct_endpoint = propagated_direct
    for start, end in relevant_ranges:
        absolute_start = declaration.initializer_start + body_offset + start
        range_factories, range_direct = _endpoint_initializer_matches(
            body[start:end],
            source=source,
            path=path,
            absolute_start=absolute_start,
            endpoint_type_names=endpoint_type_names,
            endpoint_factory_names=endpoint_factory_names,
            endpoint_namespace_names=endpoint_namespace_names,
            factory_references_only=normal_result_factory_references_only,
        )
        operations.update(item[2] for item in range_factories)
        direct_endpoint = direct_endpoint or bool(range_direct)

    return _InitializerEndpointEvidence(
        operations=tuple(sorted(operations)),
        direct_endpoint=direct_endpoint,
        endpoint_capable=propagated_capable,
    )


def _declaration_body_endpoint_evidence(
    *,
    symbol: str,
    declaration_start: int,
    opening_brace: int,
    closing_brace: int,
    source: str,
    path: str,
    resolver: _SwiftAliasResolver,
    endpoint_type_names: set[str],
    endpoint_factory_names: set[str],
    propagate_endpoint_locals: bool = True,
    normal_result_factory_references_only: bool = False,
) -> _InitializerEndpointEvidence:
    """Apply the stored-closure normal-result proof to a declaration body."""

    return _initializer_endpoint_evidence(
        _StoredPropertyDeclaration(
            symbol=symbol,
            start=declaration_start,
            end=closing_brace + 1,
            type_source=None,
            initializer=source[opening_brace:closing_brace + 1],
            initializer_start=opening_brace,
        ),
        source=source,
        path=path,
        resolver=resolver,
        endpoint_type_names=endpoint_type_names,
        endpoint_factory_names=endpoint_factory_names,
        propagate_endpoint_locals=propagate_endpoint_locals,
        normal_result_factory_references_only=normal_result_factory_references_only,
    )


def _alias_proof_diagnostic(
    *,
    path: str,
    source: str,
    declaration: _StoredPropertyDeclaration,
    error: _TypeProofError,
) -> DriftError:
    line = source.count("\n", 0, declaration.start) + 1
    alias = error.alias or "unresolved type expression"
    return DriftError(
        "Endpoint producer proof is incomplete: "
        f"path={path}; declaration={declaration.symbol}@line-{line}; "
        f"alias={alias}; reason={error.reason}; "
        "remediation=spell the Endpoint-bearing function type explicitly or use a "
        "supported bounded alias and add mapping/evidence"
    )


def _resolved_endpoint_stored_properties(
    source: str,
    path: str,
    *,
    resolver: _SwiftAliasResolver,
    endpoint_type_names: set[str],
    endpoint_factory_names: set[str],
) -> list[tuple[str, int, int]]:
    properties: list[tuple[str, int, int]] = []
    for declaration in _stored_property_declarations(source, path):
        evidence = _initializer_endpoint_evidence(
            declaration,
            source=source,
            path=path,
            resolver=resolver,
            endpoint_type_names=endpoint_type_names,
            endpoint_factory_names=endpoint_factory_names,
        )
        if evidence.ambiguous_reason is not None:
            raise DriftError(
                "Endpoint producer proof is incomplete: "
                f"path={path}; declaration={declaration.symbol}; "
                f"reason={evidence.ambiguous_reason}; "
                "remediation=keep the closure local and direct-call-only, or map its "
                "escaping Endpoint production explicitly"
            )
        type_produces_endpoint = False
        if declaration.type_source is not None:
            owner_parameters = set(
                resolver.generic_parameters_at(path, declaration.start)
            )
            try:
                resolved = resolver.parse_and_resolve(
                    declaration.type_source,
                    path=path,
                    position=declaration.start,
                    generic_parameters=owner_parameters,
                )
                type_produces_endpoint = resolver.endpoint_relation(
                    resolved,
                    path=path,
                    position=declaration.start,
                )
                if evidence.is_endpoint_producing and owner_parameters.intersection(
                    _type_node_generic_parameter_names(resolved)
                ):
                    raise _TypeProofError(
                        "stored producer retains an unresolved enclosing generic parameter"
                    )
            except _TypeProofError as error:
                if evidence.is_endpoint_producing:
                    raise _alias_proof_diagnostic(
                        path=path,
                        source=source,
                        declaration=declaration,
                        error=error,
                    ) from error
        if type_produces_endpoint or evidence.is_endpoint_producing:
            properties.append((declaration.symbol, declaration.start, declaration.end))
    return properties


def _computed_property_type_and_body(
    source: str,
    start: int,
    label: str,
) -> tuple[str, int, int] | None:
    code = inventory._swift_code_projection(source)
    pairs = {"(": ")", "[": "]", "<": ">"}
    closing = {value: key for key, value in pairs.items()}
    stack: list[str] = []
    cursor = start
    limit = min(len(code), start + 16_384)
    while cursor < limit:
        character = code[cursor]
        if character in pairs:
            stack.append(character)
        elif character in closing and stack and stack[-1] == closing[character]:
            stack.pop()
        elif not stack and character == "=":
            return None
        elif not stack and character == "{":
            type_source = source[start:cursor].strip()
            closing_brace = inventory._closing_delimiter_index(
                source,
                cursor,
                "{",
                "}",
                label,
            )
            return type_source, cursor, closing_brace
        elif not stack and character in {";", "}"}:
            return None
        cursor += 1
    if cursor >= limit and limit < len(code):
        raise _TypeProofError(f"{label} exceeds the 16384-character proof limit")
    return None


def _resolved_endpoint_computed_properties(
    source: str,
    path: str,
    *,
    resolver: _SwiftAliasResolver,
    endpoint_type_names: set[str],
    endpoint_factory_names: set[str],
) -> list[tuple[str, int, int]]:
    code = inventory._swift_code_projection(source)
    declaration = re.compile(
        rf"\b(?:let|var)\s+({_SWIFT_IDENTIFIER_PATTERN})\s*:"
    )
    properties: list[tuple[str, int, int]] = []
    for match in declaration.finditer(code):
        if not _is_global_or_type_member(source, match.start()):
            continue
        symbol = _swift_identifier_value(match.group(1))
        computed = _computed_property_type_and_body(
            source,
            match.end(),
            f"computed property {symbol}@{path}",
        )
        if computed is None:
            continue
        type_source, opening_brace, closing_brace = computed
        try:
            resolved = resolver.parse_and_resolve(
                type_source,
                path=path,
                position=match.start(),
                generic_parameters=resolver.generic_parameters_at(
                    path,
                    match.start(),
                ),
            )
        except _TypeProofError as error:
            body_evidence = _declaration_body_endpoint_evidence(
                symbol=symbol,
                declaration_start=match.start(),
                opening_brace=opening_brace,
                closing_brace=closing_brace,
                source=source,
                path=path,
                resolver=resolver,
                endpoint_type_names=endpoint_type_names,
                endpoint_factory_names=endpoint_factory_names,
            )
            if (
                body_evidence.ambiguous_reason is not None
                or body_evidence.is_endpoint_producing
                or error.alias is not None
            ):
                line = source.count("\n", 0, match.start()) + 1
                raise DriftError(
                    "Endpoint producer proof is incomplete: "
                    f"path={path}; declaration={symbol}@line-{line}; "
                    f"alias={error.alias or 'computed property type'}; "
                    f"reason={error.reason}; remediation=use a supported bounded "
                    "computed property type and add mapping/evidence"
                ) from error
            continue
        type_produces_endpoint = resolver._endpoint_value_relation(
            resolved,
            path=path,
            position=match.start(),
        )
        body_evidence = _InitializerEndpointEvidence()
        if not type_produces_endpoint:
            propagate_endpoint_locals = _type_requires_normal_result_proof(
                resolved,
                type_source,
            )
            body_evidence = _declaration_body_endpoint_evidence(
                symbol=symbol,
                declaration_start=match.start(),
                opening_brace=opening_brace,
                closing_brace=closing_brace,
                source=source,
                path=path,
                resolver=resolver,
                endpoint_type_names=endpoint_type_names,
                endpoint_factory_names=endpoint_factory_names,
                propagate_endpoint_locals=propagate_endpoint_locals,
                normal_result_factory_references_only=(
                    not propagate_endpoint_locals
                ),
            )
            if body_evidence.ambiguous_reason is not None:
                line = source.count("\n", 0, match.start()) + 1
                raise DriftError(
                    "Endpoint producer proof is incomplete: "
                    f"path={path}; declaration={symbol}@line-{line}; "
                    f"reason={body_evidence.ambiguous_reason}; "
                    "remediation=use a supported bounded computed-property result "
                    "or map its Endpoint production explicitly"
                )
        if type_produces_endpoint or body_evidence.is_endpoint_producing:
            properties.append((symbol, match.start(), closing_brace + 1))
    return properties


def _type_node_nominal_names(node: _SwiftTypeNode) -> set[str]:
    names = {node.name} if node.kind == "nominal" else set()
    for child in node.children:
        names.update(_type_node_nominal_names(child))
    return names


def _type_node_generic_parameter_names(node: _SwiftTypeNode) -> set[str]:
    names = {node.name} if node.kind == "generic_parameter" else set()
    for child in node.children:
        names.update(_type_node_generic_parameter_names(child))
    return names


def _type_requires_normal_result_proof(
    node: _SwiftTypeNode,
    original_type_source: str,
) -> bool:
    """Whether a resolved type can erase the concrete normal-result identity."""

    if _type_node_generic_parameter_names(node):
        return True
    if _type_node_nominal_names(node).intersection({"Any", "AnyObject"}):
        return True
    code = inventory._swift_code_projection(original_type_source)
    return re.search(r"\b(?:any|some)\s+", code) is not None


def _enclosing_generic_parameters(source: str, position: int) -> tuple[str, ...]:
    code = inventory._swift_code_projection(source)
    parameters: list[str] = []
    for opening in _brace_stack_at(source, position):
        header_start = max(
            code.rfind("}", 0, opening),
            code.rfind("{", 0, opening),
            code.rfind(";", 0, opening),
            code.rfind("\n", 0, opening),
        ) + 1
        header = source[header_start:opening]
        generic = re.search(
            rf"\b(?:struct|enum|class|actor|extension)\s+{_SWIFT_IDENTIFIER_PATTERN}"
            r"\s*<(.+)>",
            inventory._swift_code_projection(header),
            re.DOTALL,
        )
        if generic is not None:
            try:
                parameters.extend(_alias_generic_parameter_names(generic.group(1)))
            except _TypeProofError:
                continue
    return tuple(parameters)


def _callable_declaration_heads(
    source: str,
    path: str,
    keyword: str,
) -> tuple[_CallableDeclarationHead, ...]:
    code = inventory._swift_code_projection(source)
    heads: list[_CallableDeclarationHead] = []
    for match in re.finditer(rf"\b{re.escape(keyword)}\b", code):
        if not _is_global_or_type_member(source, match.start()):
            continue
        cursor = match.end()
        while cursor < len(code) and code[cursor].isspace():
            cursor += 1
        if keyword == "func":
            identifier = re.match(_SWIFT_IDENTIFIER_PATTERN, code[cursor:])
            if identifier is not None:
                raw_symbol = identifier.group(0)
            else:
                operator = re.match(r"[^\w\s(){}\[\],;]+", code[cursor:])
                if operator is None:
                    continue
                raw_symbol = operator.group(0)
            symbol = _swift_identifier_value(raw_symbol)
            cursor += len(raw_symbol)
        else:
            symbol = "subscript"
        while cursor < len(code) and code[cursor].isspace():
            cursor += 1
        generic_parameters: tuple[str, ...] = ()
        generic_error: str | None = None
        if cursor < len(code) and code[cursor] == "<":
            try:
                closing_generic = inventory._closing_delimiter_index(
                    source,
                    cursor,
                    "<",
                    ">",
                    f"generic {keyword} {symbol}@{path}",
                )
                generic_parameters = _alias_generic_parameter_names(
                    source[cursor + 1:closing_generic]
                )
                cursor = closing_generic + 1
            except (inventory.InventoryError, _TypeProofError) as error:
                generic_error = str(error)
                next_parenthesis = code.find("(", cursor + 1)
                if next_parenthesis < 0:
                    continue
                cursor = next_parenthesis
        while cursor < len(code) and code[cursor].isspace():
            cursor += 1
        if cursor >= len(code) or code[cursor] != "(":
            continue
        closing_parenthesis = inventory._closing_delimiter_index(
            source,
            cursor,
            "(",
            ")",
            f"{keyword} declaration {symbol}@{path}",
        )
        heads.append(
            _CallableDeclarationHead(
                symbol=symbol,
                start=match.start(),
                opening_parenthesis=cursor,
                closing_parenthesis=closing_parenthesis,
                generic_parameters=generic_parameters,
                generic_error=generic_error,
            )
        )
    return tuple(heads)


def _callable_result_and_body(
    source: str,
    path: str,
    head: _CallableDeclarationHead,
) -> tuple[str, int, int] | None:
    code = inventory._swift_code_projection(source)
    opening_brace = code.find("{", head.closing_parenthesis + 1)
    if opening_brace < 0:
        return None
    intervening_closing = code.find("}", head.closing_parenthesis + 1, opening_brace)
    intervening_semicolon = code.find(";", head.closing_parenthesis + 1, opening_brace)
    if intervening_closing >= 0 or intervening_semicolon >= 0:
        return None
    suffix = source[head.closing_parenthesis + 1:opening_brace]
    suffix_code = inventory._swift_code_projection(suffix)
    arrow = suffix_code.find("->")
    if arrow < 0:
        return None
    result_source = suffix[arrow + 2:]
    where_clause = re.search(
        r"\bwhere\b",
        inventory._swift_code_projection(result_source),
    )
    if where_clause is not None:
        result_source = result_source[:where_clause.start()]
    closing_brace = inventory._closing_delimiter_index(
        source,
        opening_brace,
        "{",
        "}",
        f"resolved Endpoint-returning {head.symbol}@{path}",
    )
    return result_source.strip(), opening_brace, closing_brace


def _resolved_endpoint_returning_callables(
    source: str,
    path: str,
    resolver: _SwiftAliasResolver,
    keyword: str,
    endpoint_factory_names: set[str] | None = None,
) -> list[tuple[str, int, int]]:
    declarations: list[tuple[str, int, int]] = []
    for head in _callable_declaration_heads(source, path, keyword):
        result_and_body = _callable_result_and_body(source, path, head)
        if result_and_body is None:
            continue
        result_source, opening_brace, closing_brace = result_and_body
        generic_parameters = {
            *head.generic_parameters,
            *resolver.generic_parameters_at(path, head.start),
        }
        try:
            if head.generic_error is not None:
                raise _TypeProofError(head.generic_error)
            resolved = resolver.parse_and_resolve(
                result_source,
                path=path,
                position=head.start,
                generic_parameters=generic_parameters,
            )
        except _TypeProofError as error:
            body_evidence = _declaration_body_endpoint_evidence(
                symbol=head.symbol,
                declaration_start=head.start,
                opening_brace=opening_brace,
                closing_brace=closing_brace,
                source=source,
                path=path,
                resolver=resolver,
                endpoint_type_names=resolver.endpoint_types_by_path[path],
                endpoint_factory_names=endpoint_factory_names or set(),
            )
            endpoint_evidence = (
                error.alias is not None
                or re.search(r"\bEndpoint\b", result_source) is not None
                or body_evidence.is_endpoint_producing
                or body_evidence.ambiguous_reason is not None
            )
            if endpoint_evidence:
                line = source.count("\n", 0, head.start) + 1
                raise DriftError(
                    "Endpoint producer proof is incomplete: "
                    f"path={path}; declaration={head.symbol}@line-{line}; "
                    f"alias={error.alias or 'return type'}; reason={error.reason}; "
                    "remediation=use a supported bounded return alias and add mapping/evidence"
                ) from error
            continue
        type_produces_endpoint = resolver.endpoint_relation(
            _SwiftTypeNode("function", children=(_SwiftTypeNode("tuple"), resolved)),
            path=path,
            position=head.start,
        )
        body_evidence = _InitializerEndpointEvidence()
        if not type_produces_endpoint:
            propagate_endpoint_locals = _type_requires_normal_result_proof(
                resolved,
                result_source,
            )
            body_evidence = _declaration_body_endpoint_evidence(
                symbol=head.symbol,
                declaration_start=head.start,
                opening_brace=opening_brace,
                closing_brace=closing_brace,
                source=source,
                path=path,
                resolver=resolver,
                endpoint_type_names=resolver.endpoint_types_by_path[path],
                endpoint_factory_names=endpoint_factory_names or set(),
                propagate_endpoint_locals=propagate_endpoint_locals,
                normal_result_factory_references_only=(
                    not propagate_endpoint_locals
                ),
            )
            if body_evidence.ambiguous_reason is not None:
                line = source.count("\n", 0, head.start) + 1
                raise DriftError(
                    "Endpoint producer proof is incomplete: "
                    f"path={path}; declaration={head.symbol}@line-{line}; "
                    f"reason={body_evidence.ambiguous_reason}; "
                    "remediation=use a supported bounded callable result or map its "
                    "Endpoint production explicitly"
                )
        if type_produces_endpoint or body_evidence.is_endpoint_producing:
            declarations.append((head.symbol, head.start, closing_brace + 1))
    return declarations


def _resolved_endpoint_returning_functions(
    source: str,
    path: str,
    resolver: _SwiftAliasResolver,
    endpoint_factory_names: set[str] | None = None,
) -> list[tuple[str, int, int]]:
    return _resolved_endpoint_returning_callables(
        source,
        path,
        resolver,
        "func",
        endpoint_factory_names,
    )


def _resolved_endpoint_returning_subscripts(
    source: str,
    path: str,
    resolver: _SwiftAliasResolver,
    endpoint_factory_names: set[str] | None = None,
) -> list[tuple[str, int, int]]:
    return _resolved_endpoint_returning_callables(
        source,
        path,
        resolver,
        "subscript",
        endpoint_factory_names,
    )


def _endpoint_returning_properties(
    source: str,
    path: str,
    endpoint_type_names: set[str],
    endpoint_closure_type_names: set[str],
) -> list[tuple[str, int, int]]:
    """Find computed/global/static properties whose declared value is Endpoint."""

    code = inventory._swift_code_projection(source)
    endpoint_type = _endpoint_type_pattern(source, path, endpoint_type_names)
    declaration = re.compile(
        r"\b(?:let|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*"
        rf"{endpoint_type}\s*[?!]?"
        r"(?![A-Za-z0-9_])"
    )
    properties: list[tuple[str, int, int]] = []
    for match in declaration.finditer(code):
        if not _is_global_or_type_member(source, match.start()):
            continue
        if _endpoint_reference_is_shadowed(
            source,
            path,
            match.group(0),
            endpoint_type_names,
            match.start(),
        ):
            continue
        cursor = match.end()
        while cursor < len(code) and code[cursor] in {" ", "\t"}:
            cursor += 1
        if cursor < len(code) and code[cursor] == "{":
            closing = inventory._closing_delimiter_index(
                source,
                cursor,
                "{",
                "}",
                f"current Endpoint-returning property {match.group(1)}@{path}",
            )
            observer = source[cursor:closing + 1]
            if not _has_property_observers(observer):
                properties.append((match.group(1), match.start(), closing + 1))
        elif cursor < len(code) and code[cursor] == "=":
            end = _initializer_expression_end(
                source,
                cursor + 1,
                f"Endpoint property initializer {match.group(1)}@{path}",
            )
            properties.append((match.group(1), match.start(), end))

    closure_declaration = re.compile(
        r"\b(?:let|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*"
        r"(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^()]*\))?\s+)*"
        r"\([^\n{}]*\)\s*(?:async\s+)?(?:throws\s+)?->\s*"
        rf"{endpoint_type}\s*[?!]?"
        r"\s*=\s*"
    )
    for match in closure_declaration.finditer(code):
        if not _is_global_or_type_member(source, match.start()):
            continue
        if _endpoint_reference_is_shadowed(
            source,
            path,
            match.group(0),
            endpoint_type_names,
            match.start(),
        ):
            continue
        end = _initializer_expression_end(
            source,
            match.end(),
            f"Endpoint closure initializer {match.group(1)}@{path}",
        )
        properties.append((match.group(1), match.start(), end))

    if endpoint_closure_type_names:
        closure_types = "|".join(
            re.escape(name)
            for name in sorted(endpoint_closure_type_names, key=len, reverse=True)
        )
        closure_alias_declaration = re.compile(
            r"\b(?:let|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*"
            rf"(?:[A-Za-z_][A-Za-z0-9_]*\s*\.\s*)?(?:{closure_types})"
            r"\s*=\s*"
        )
        for match in closure_alias_declaration.finditer(code):
            if not _is_global_or_type_member(source, match.start()):
                continue
            end = _initializer_expression_end(
                source,
                match.end(),
                f"Endpoint closure alias initializer {match.group(1)}@{path}",
            )
            properties.append((match.group(1), match.start(), end))

    return properties


def _current_producer_identities(
    sources: Mapping[str, bytes],
) -> set[tuple[str, str, str]]:
    """Discover producers across every production Swift file without filename trust."""

    identities: list[tuple[str, str, str]] = []
    endpoint_types_by_path = _endpoint_type_names_by_path(sources)
    alias_resolver = _SwiftAliasResolver(sources, endpoint_types_by_path)
    decoded_sources: dict[str, str] = {}
    endpoint_functions_by_path: dict[str, list[tuple[str, int, int]]] = {}
    endpoint_subscripts_by_path: dict[str, list[tuple[str, int, int]]] = {}
    for path, raw_source in sorted(sources.items()):
        try:
            source = raw_source.decode("utf-8")
        except UnicodeDecodeError as error:
            raise DriftError(f"production Swift source is not UTF-8: {path}") from error
        decoded_sources[path] = source
        resolved_functions = _resolved_endpoint_returning_functions(
            source,
            path,
            alias_resolver,
        )
        endpoint_functions_by_path[path] = resolved_functions
        resolved_subscripts = _resolved_endpoint_returning_subscripts(
            source,
            path,
            alias_resolver,
        )
        endpoint_subscripts_by_path[path] = resolved_subscripts
    endpoint_factory_names = {
        source_symbol
        for functions in endpoint_functions_by_path.values()
        for source_symbol, _, _ in functions
    }
    for path in sorted(sources):
        source = decoded_sources[path]
        endpoint_functions_by_path[path] = _resolved_endpoint_returning_functions(
            source,
            path,
            alias_resolver,
            endpoint_factory_names,
        )
        endpoint_subscripts_by_path[path] = _resolved_endpoint_returning_subscripts(
            source,
            path,
            alias_resolver,
            endpoint_factory_names,
        )
    endpoint_factory_names = {
        source_symbol
        for functions in endpoint_functions_by_path.values()
        for source_symbol, _, _ in functions
    }

    for path in sorted(sources):
        source = decoded_sources[path]
        code = inventory._swift_code_projection(source)
        endpoint_type_names = endpoint_types_by_path[path]
        endpoint_functions = endpoint_functions_by_path[path]
        endpoint_subscripts = endpoint_subscripts_by_path[path]
        for source_symbol, _, _ in endpoint_functions:
            if (
                source_symbol == "getSession"
                and path == "Packages/Networking/Sources/Networking/Endpoint.swift"
            ):
                continue
            producer_symbol = inventory._producer_symbol_for_factory(path, source_symbol)
            identities.append(("endpoint_factory", producer_symbol, path))

        resolved_properties = _resolved_endpoint_stored_properties(
            source,
            path,
            resolver=alias_resolver,
            endpoint_type_names=endpoint_type_names,
            endpoint_factory_names=endpoint_factory_names,
        )
        resolved_computed_properties = _resolved_endpoint_computed_properties(
            source,
            path,
            resolver=alias_resolver,
            endpoint_type_names=endpoint_type_names,
            endpoint_factory_names=endpoint_factory_names,
        )
        endpoint_properties = list(
            {
                (source_symbol, start): (source_symbol, start, end)
                for source_symbol, start, end in (
                    *resolved_properties,
                    *resolved_computed_properties,
                )
            }.values()
        )
        for source_symbol, _, _ in endpoint_properties:
            producer_symbol = inventory._producer_symbol_for_factory(path, source_symbol)
            identities.append(("endpoint_factory", producer_symbol, path))

        for source_symbol, _, _ in endpoint_subscripts:
            identities.append(("endpoint_factory", source_symbol, path))

        endpoint_type = _endpoint_type_pattern(source, path, endpoint_type_names)
        endpoint_call = re.compile(
            rf"(?<![A-Za-z0-9_.]){endpoint_type}(?:\s*\.\s*init)?\s*\("
        )
        shorthand_init = re.compile(
            r"\b(?:let|var)\s+[A-Za-z_][A-Za-z0-9_]*\s*:\s*"
            rf"{endpoint_type}\s*[?!]?"
            r"\s*=\s*\.\s*init\s*\("
        )
        producer_regions = [
            (start, end)
            for _, start, end in (
                *endpoint_functions,
                *endpoint_properties,
                *endpoint_subscripts,
            )
        ]
        direct_matches = [
            match
            for pattern in (endpoint_call, shorthand_init)
            for match in pattern.finditer(code)
            if not _endpoint_reference_is_shadowed(
                source,
                path,
                match.group(0),
                endpoint_type_names,
                match.start(),
            )
        ]
        typed_declaration = re.compile(
            r"\b(?:let|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*"
            rf"{endpoint_type}\s*[?!]?(?!\s*\.\s*Type\b)"
        )
        shorthand_reassignments: list[int] = []
        for declaration in typed_declaration.finditer(code):
            if _endpoint_reference_is_shadowed(
                source,
                path,
                declaration.group(0),
                endpoint_type_names,
                declaration.start(),
            ):
                continue
            assignment = re.compile(
                rf"\b{re.escape(declaration.group(1))}\s*=\s*\.\s*init\s*\("
            )
            shorthand_reassignments.extend(
                match.start()
                for match in assignment.finditer(code, declaration.end())
            )
        direct_positions = sorted(
            {
                match.start()
                for match in direct_matches
                if not any(start <= match.start() < end for start, end in producer_regions)
            }
            | {
                position
                for position in shorthand_reassignments
                if not any(start <= position < end for start, end in producer_regions)
            }
        )
        if direct_positions:
            binding = inventory.DIRECT_PRODUCER_BINDINGS.get(path)
            if binding is not None and len(direct_positions) == 1:
                identities.append(
                    ("direct_endpoint", binding["producerSymbol"], path)
                )
            else:
                for position in direct_positions:
                    line = source.count("\n", 0, position) + 1
                    identities.append(
                        ("direct_endpoint", f"unmapped@line-{line}", path)
                    )

    analytics_raw = sources.get(inventory.ANALYTICS_SOURCE_PATH)
    if analytics_raw is None:
        raise DriftError(
            f"analytics producer source is missing: {inventory.ANALYTICS_SOURCE_PATH}"
        )
    analytics_paths = inventory._analytics_path_declarations(
        analytics_raw.decode("utf-8")
    )
    for symbol in sorted(analytics_paths):
        identities.append(
            (
                "analytics_path",
                f"DefaultAnalyticsClient.Path.{symbol}",
                inventory.ANALYTICS_SOURCE_PATH,
            )
        )

    duplicates = sorted(
        identity for identity in set(identities) if identities.count(identity) > 1
    )
    if duplicates:
        raise DriftError(f"current producer discovery is ambiguous: {duplicates}")
    return set(identities)


def _expected_producer_identities(mapping: Mapping) -> set[tuple[str, str, str]]:
    records = mapping.get("records")
    if not isinstance(records, list):
        raise DriftError("inventory source mapping records must be an array")
    try:
        return {
            (
                record["producerKind"],
                record["producerSymbol"],
                record["producerSourcePath"],
            )
            for record in records
        }
    except (KeyError, TypeError) as error:
        raise DriftError("inventory source mapping has invalid producer identities") from error


def _validate_current_inventory(
    mapping: Mapping,
    current_sources: Mapping[str, bytes],
    historical_sources: Mapping[str, bytes],
) -> list[dict]:
    expected = _expected_producer_identities(mapping)
    discovered = _current_producer_identities(current_sources)
    if discovered != expected:
        missing = sorted(expected - discovered)
        unexpected = sorted(discovered - expected)
        raise DriftError(
            "current all-source producer set differs from the committed mapping; "
            f"missing={missing} unexpected={unexpected}"
        )
    return inventory.validate_inventory_source(
        mapping,
        _CurrentValidationSources(current_sources, historical_sources),
    )


def _generic_parameter_clause(declaration_prefix: str) -> str:
    match = re.search(r"<[^<>]*>", declaration_prefix, re.DOTALL)
    return "" if match is None else match.group(0)


def _generic_parameter_names(generic_clause: str) -> set[str]:
    if not generic_clause:
        return set()
    return set(
        re.findall(
            r"(?:^|,)\s*([A-Z][A-Za-z0-9_]*)\s*(?=[:,])",
            generic_clause[1:-1],
        )
    )


def _factory_parts(
    source: str,
    producer_symbol: str,
    path: str,
) -> tuple[str, str, dict[str, str], str]:
    source_symbol = producer_symbol.split(".", 1)[0]
    pattern = re.compile(
        rf"^\s*(?:public\s+)?static\s+func\s+{re.escape(source_symbol)}"
        r"(?:<[^>{}]*>)?\s*\(",
        re.MULTILINE,
    )
    code = inventory._swift_code_projection(source)
    matches = list(pattern.finditer(code))
    if len(matches) != 1:
        raise DriftError(
            f"request semantics cannot resolve {producer_symbol}@{path}; found {len(matches)}"
        )
    parameters = inventory._function_parameters_from_declaration(
        source,
        matches[0],
        f"{producer_symbol}@{path}",
    )
    opening_parenthesis = code.find("(", matches[0].start(), matches[0].end())
    generic_clause = _generic_parameter_clause(
        code[matches[0].start():opening_parenthesis]
    )
    body = inventory._factory_region(source, producer_symbol, path)
    initializer = inventory._factory_endpoint_initializer_region(
        body,
        f"{producer_symbol}@{path}",
    )
    return (
        parameters,
        body,
        inventory._endpoint_arguments(
            initializer,
            f"{producer_symbol}@{path}",
        ),
        generic_clause,
    )


def _direct_parts(
    source: str,
    producer_symbol: str,
    path: str,
) -> tuple[str, str, dict[str, str], str]:
    binding = inventory.DIRECT_PRODUCER_BINDINGS.get(path)
    if binding is None:
        raise DriftError(f"request semantics have no direct binding for {producer_symbol}@{path}")
    declaration = inventory._function_declaration(
        source,
        binding["functionSymbol"],
        producer_symbol,
    )
    parameters = inventory._function_parameters_from_declaration(
        source,
        declaration,
        producer_symbol,
    )
    body = inventory._function_body_region(source, declaration, producer_symbol)
    initializer = inventory._direct_endpoint_initializer_region(
        source,
        producer_symbol,
        path,
    )
    return (
        parameters,
        body,
        inventory._endpoint_arguments(initializer, producer_symbol),
        "",
    )


def _function_region_in_scope(scope: str, function_symbol: str, label: str) -> str:
    pattern = re.compile(
        rf"^\s*(?:(?:public|private|internal|fileprivate|package)\s+)?"
        rf"(?:nonisolated\s+)?func\s+{re.escape(function_symbol)}"
        r"(?:<[^>{}]*>)?\s*\(",
        re.MULTILINE,
    )
    code = inventory._swift_code_projection(scope)
    matches = list(pattern.finditer(code))
    if len(matches) != 1:
        raise DriftError(f"request semantics cannot resolve {label}; found {len(matches)}")
    parameters = inventory._function_parameters_from_declaration(
        scope,
        matches[0],
        label,
    )
    body = inventory._function_body_region(scope, matches[0], label)
    return parameters + body


def _enclosing_function_at(source: str, position: int, label: str) -> tuple[str, str, str]:
    code = inventory._swift_code_projection(source)
    declaration = re.compile(
        r"\bfunc\s+([A-Za-z_][A-Za-z0-9_]*)"
        r"(?:\s*<[^>{}]*>)?\s*\("
    )
    candidates: list[tuple[int, str, str, str]] = []
    for match in declaration.finditer(code):
        if match.start() > position:
            break
        opening_parenthesis = code.find("(", match.start(), match.end())
        closing_parenthesis = inventory._closing_delimiter_index(
            source,
            opening_parenthesis,
            "(",
            ")",
            label,
        )
        opening_brace = code.find("{", closing_parenthesis + 1)
        if opening_brace < 0 or opening_brace > position:
            continue
        closing_brace = inventory._closing_delimiter_index(
            source,
            opening_brace,
            "{",
            "}",
            label,
        )
        if position >= closing_brace:
            continue
        candidates.append(
            (
                closing_brace - match.start(),
                match.group(1),
                source[opening_parenthesis:closing_parenthesis + 1],
                source[match.start():closing_brace + 1],
            )
        )
    if not candidates:
        raise DriftError(f"request semantics cannot resolve enclosing function for {label}")
    _, symbol, parameters, region = min(candidates, key=lambda item: item[0])
    return symbol, parameters, region


def _generic_body_callsite_witnesses(
    producer_symbol: str,
    sources: Mapping[str, bytes],
    type_index: Mapping[str, Sequence[tuple[str, str, str]]],
    extension_index: Mapping[tuple[str, str], Sequence[str]],
) -> list[dict]:
    expected = GENERIC_BODY_CALLSITE_BINDINGS.get(producer_symbol)
    if expected is None:
        return []
    call_pattern = re.compile(
        rf"\bEndpoints\s*\.\s*{re.escape(producer_symbol)}\s*\("
    )
    discovered: list[tuple[tuple[str, str], dict]] = []
    for path, raw_source in sorted(sources.items()):
        source = raw_source.decode("utf-8")
        code = inventory._swift_code_projection(source)
        for call in call_pattern.finditer(code):
            function_symbol, parameters, function_region = _enclosing_function_at(
                source,
                call.start(),
                f"{producer_symbol} call site at {path}",
            )
            key = (path, function_symbol)
            binding = expected.get(key)
            if binding is None:
                discovered.append((key, {"unexpected": True}))
                continue
            opening = code.find("(", call.start(), call.end())
            call_region = inventory._extract_delimited_region(
                source,
                opening,
                "(",
                ")",
                f"{producer_symbol} call at {path}",
            )
            if inventory._swift_without_comments(call_region[1:-1]).strip() != "body":
                raise DriftError(
                    f"generic request body call {producer_symbol}@{path} must pass body directly"
                )
            body_type = binding["bodyType"]
            origin: list[str]
            if binding["source"] == "parameter":
                parameter_code = inventory._swift_code_projection(parameters)
                parameter = re.search(
                    rf"\bbody\s*:\s*{re.escape(body_type)}\b",
                    parameter_code,
                )
                if parameter is None:
                    raise DriftError(
                        f"generic request body parameter changed for {producer_symbol}@{path}"
                    )
                origin = [
                    _canonical_swift_tokens(
                        parameters[parameter.start():parameter.end()]
                    )
                ]
            elif binding["source"] == "local":
                origin = _call_witnesses(function_region, (re.escape(body_type),))
                if len(origin) != 1:
                    raise DriftError(
                        f"generic request body constructor {body_type}@{path} "
                        f"must resolve once; found {len(origin)}"
                    )
            else:
                raise DriftError(f"unsupported generic body binding for {producer_symbol}@{path}")
            wire_types = _request_type_witnesses(
                {body_type},
                path,
                type_index,
                extension_index,
            )
            if not any(type_key.endswith(f":{body_type}") for type_key in wire_types):
                raise DriftError(
                    f"generic request body type {body_type}@{path} is not resolvable"
                )
            discovered.append(
                (
                    key,
                    {
                        "path": path,
                        "function": function_symbol,
                        "call": _canonical_swift_tokens(
                            source[call.start():opening] + call_region
                        ),
                        "origin": origin,
                        "wireTypes": wire_types,
                    },
                )
            )
    discovered_keys = sorted(key for key, _ in discovered)
    expected_keys = sorted(expected)
    if discovered_keys != expected_keys:
        raise DriftError(
            f"generic request body call-site set changed for {producer_symbol}; "
            f"expected={expected_keys} discovered={discovered_keys}"
        )
    return [witness for _, witness in sorted(discovered, key=lambda item: item[0])]


def _initializer_witnesses(declaration: str) -> list[str]:
    code = inventory._swift_code_projection(declaration)
    witnesses: list[str] = []
    pattern = re.compile(r"\binit(?:\s*<[^>{}]*>)?\s*\(")
    for match in pattern.finditer(code):
        if inventory._brace_depth_at(declaration, match.start()) != 1:
            continue
        opening_parenthesis = code.find("(", match.start(), match.end())
        closing_parenthesis = inventory._closing_delimiter_index(
            declaration,
            opening_parenthesis,
            "(",
            ")",
            "Endpoint initializer parameters",
        )
        opening_brace = code.find("{", closing_parenthesis + 1)
        if opening_brace < 0:
            raise DriftError("Endpoint initializer has no body")
        closing_brace = inventory._closing_delimiter_index(
            declaration,
            opening_brace,
            "{",
            "}",
            "Endpoint initializer",
        )
        witnesses.append(
            _canonical_swift_tokens(
                declaration[match.start():closing_brace + 1]
            )
        )
    return witnesses


def _endpoint_core_witness(sources: Mapping[str, bytes]) -> dict:
    path = "Packages/Networking/Sources/Networking/Endpoint.swift"
    raw_source = sources.get(path)
    if raw_source is None:
        raise DriftError("request semantics are missing the Endpoint definition")
    source = raw_source.decode("utf-8")
    pattern = re.compile(r"^\s*public\s+struct\s+Endpoint\b[^\{]*\{", re.MULTILINE)
    code = inventory._swift_code_projection(source)
    matches = list(pattern.finditer(code))
    if len(matches) != 1:
        raise DriftError(f"request semantics must resolve one Endpoint definition; found {len(matches)}")
    opening = code.find("{", matches[0].start(), matches[0].end())
    closing = inventory._closing_delimiter_index(
        source,
        opening,
        "{",
        "}",
        "Endpoint request-semantic definition",
    )
    declaration = source[matches[0].start():closing + 1]
    properties = [
        property_witness
        for property_witness in _stored_property_witnesses(declaration)[0]
        if property_witness["name"]
        in {"method", "path", "query", "httpBody", "requiresAuth"}
    ]
    expected_properties = {"method", "path", "query", "httpBody", "requiresAuth"}
    if len(properties) != len(expected_properties) or {
        item["name"] for item in properties
    } != expected_properties:
        raise DriftError("Endpoint request-semantic properties are incomplete or ambiguous")
    json_coding_path = "Packages/Networking/Sources/Networking/JSONCoding.swift"
    json_coding_raw = sources.get(json_coding_path)
    if json_coding_raw is None:
        raise DriftError("request semantics are missing the shared JSONCoding definition")
    return {
        "storedProperties": properties,
        "initializers": _initializer_witnesses(declaration),
        "jsonEncoder": _static_property_initializer_witness(
            json_coding_raw.decode("utf-8"),
            property_name="encoder",
            type_name="JSONEncoder",
            label="JSONCoding.encoder",
        ),
    }


def _static_property_initializer_witness(
    source: str,
    *,
    property_name: str,
    type_name: str,
    label: str,
) -> str:
    code = inventory._swift_code_projection(source)
    pattern = re.compile(
        rf"\bstatic\s+let\s+{re.escape(property_name)}\s*:\s*"
        rf"{re.escape(type_name)}\s*=\s*"
    )
    matches = list(pattern.finditer(code))
    if len(matches) != 1:
        raise DriftError(f"request semantics cannot resolve {label}; found {len(matches)}")
    end = _initializer_expression_end(source, matches[0].end(), label)
    return _canonical_swift_tokens(source[matches[0].start():end])


def _http_method_witness(sources: Mapping[str, bytes]) -> dict[str, str]:
    path = "Packages/Networking/Sources/Networking/Endpoint.swift"
    raw_source = sources.get(path)
    if raw_source is None:
        raise DriftError("request semantics are missing the HTTPMethod definition")
    source = raw_source.decode("utf-8")
    region = inventory._declaration_region(
        source,
        re.compile(
            r"^[ \t]*public\s+enum\s+HTTPMethod\s*:\s*String\b[^\{]*",
            re.MULTILINE,
        ),
        "HTTPMethod",
    )
    code = inventory._swift_without_comments(region)
    cases: dict[str, str] = {}
    pattern = re.compile(
        r"\bcase\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"
        r"((?:#*)\"(?:[^\"\\]|\\.)*\"(?:#*))"
    )
    for match in pattern.finditer(code):
        if inventory._brace_depth_at(region, match.start()) != 1:
            continue
        name = match.group(1)
        if name in cases:
            raise DriftError(f"HTTPMethod has a duplicate case declaration: {name}")
        cases[name] = _canonical_swift_tokens(match.group(2))
    if not cases:
        raise DriftError("HTTPMethod must declare raw-value cases")
    return dict(sorted(cases.items()))


def _local_type_declaration(body: str, type_name: str) -> str | None:
    pattern = re.compile(
        rf"\b(?:struct|enum|class)\s+{re.escape(type_name)}\b[^\{{]*\{{"
    )
    code = inventory._swift_code_projection(body)
    matches = list(pattern.finditer(code))
    if not matches:
        return None
    if len(matches) != 1:
        raise DriftError(f"request semantics found ambiguous local type {type_name}")
    opening = code.find("{", matches[0].start(), matches[0].end())
    closing = inventory._closing_delimiter_index(
        body,
        opening,
        "{",
        "}",
        f"local request type {type_name}",
    )
    return body[matches[0].start():closing + 1]


def _request_type_names(
    arguments: Mapping[str, str],
    parameters: str,
    body: str,
) -> set[str]:
    expression = arguments.get("body")
    if expression is None:
        return set()
    names = set(re.findall(r"\b([A-Z][A-Za-z0-9_]*)\s*\(", expression))
    bare = re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", expression)
    if bare is not None:
        parameter_type = re.search(
            rf"\b{re.escape(expression)}\s*:\s*(?:(?:some|any)\s+)?"
            r"([A-Z][A-Za-z0-9_]*)",
            parameters,
        )
        if parameter_type is not None:
            names.add(parameter_type.group(1))
        local_binding = re.search(
            rf"\b(?:let|var)\s+{re.escape(expression)}(?:\s*:\s*"
            r"[A-Za-z_][A-Za-z0-9_.<>\[\]:, ]*)?\s*=\s*"
            r"([A-Z][A-Za-z0-9_]*)\s*\(",
            inventory._swift_without_comments(body),
        )
        if local_binding is not None:
            names.add(local_binding.group(1))
    return names - {"Endpoint", "URLQueryItem"}


def _swift_module_key(path: str) -> str:
    parts = PurePosixPath(path).parts
    if len(parts) >= 4 and parts[0] == "Packages" and parts[2] == "Sources":
        return "/".join(parts[:4])
    return parts[0] if parts else path


def _swift_package_key(path: str) -> str:
    parts = PurePosixPath(path).parts
    if len(parts) >= 2 and parts[0] == "Packages":
        return "/".join(parts[:2])
    return parts[0] if parts else path


def _type_visibility(declaration: str) -> str:
    code = inventory._swift_code_projection(declaration)
    match = re.match(
        r"\s*(?:(public|package|private|fileprivate|internal)\s+)?"
        r"(?:(?:final|indirect|nonisolated)\s+)*"
        r"(?:struct|enum|class)\b",
        code,
    )
    if match is None or match.group(1) is None:
        return "internal"
    return match.group(1)


def _visible_type_candidates(
    candidates: Sequence[tuple[str, str, str]],
    *,
    lookup_module: str,
    lookup_path: str,
) -> list[tuple[str, str, str]]:
    same_file = [item for item in candidates if item[1] == lookup_path]
    if same_file:
        return same_file
    same_module = [
        item
        for item in candidates
        if item[0] == lookup_module
        and _type_visibility(item[2]) not in {"private", "fileprivate"}
    ]
    if same_module:
        return same_module
    return [
        item
        for item in candidates
        if _type_visibility(item[2]) in {"public", "package"}
    ]


def _request_type_indexes(
    sources: Mapping[str, bytes],
) -> tuple[
    dict[str, list[tuple[str, str, str]]],
    dict[tuple[str, str], list[str]],
]:
    declarations: dict[str, list[tuple[str, str, str]]] = {}
    extensions: dict[tuple[str, str], list[str]] = {}
    declaration_pattern = re.compile(
        r"^[ \t]*(?:(?:public|private|internal|fileprivate|package)\s+)?"
        r"(?:(?:final|indirect|nonisolated)\s+)*"
        r"(struct|enum|class)\s+([A-Z][A-Za-z0-9_]*)\b[^\{]*\{",
        re.MULTILINE,
    )
    extension_pattern = re.compile(
        r"^[ \t]*(?:(?:public|private|internal|fileprivate|package)\s+)?"
        r"extension\s+([A-Z][A-Za-z0-9_]*)\b[^\{]*\{",
        re.MULTILINE,
    )
    for path, raw_source in sorted(sources.items()):
        source = raw_source.decode("utf-8")
        code = inventory._swift_code_projection(source)
        module = _swift_module_key(path)
        for match in declaration_pattern.finditer(code):
            if inventory._brace_depth_at(source, match.start()) != 0:
                continue
            type_name = match.group(2)
            opening = code.find("{", match.start(), match.end())
            closing = inventory._closing_delimiter_index(
                source,
                opening,
                "{",
                "}",
                f"request type {type_name}@{path}",
            )
            declarations.setdefault(type_name, []).append(
                (module, path, source[match.start():closing + 1])
            )
        for match in extension_pattern.finditer(code):
            if inventory._brace_depth_at(source, match.start()) != 0:
                continue
            type_name = match.group(1)
            opening = code.find("{", match.start(), match.end())
            closing = inventory._closing_delimiter_index(
                source,
                opening,
                "{",
                "}",
                f"request type extension {type_name}@{path}",
            )
            extensions.setdefault((module, type_name), []).append(
                source[match.start():closing + 1]
            )
    return declarations, extensions


def _type_expression_end(code: str, start: int) -> int:
    pairs = {"(": ")", "[": "]", "<": ">"}
    closing = {value: key for key, value in pairs.items()}
    stack: list[str] = []
    cursor = start
    while cursor < len(code):
        character = code[cursor]
        if character in pairs:
            stack.append(character)
        elif character in closing:
            if stack and stack[-1] == closing[character]:
                stack.pop()
        elif not stack and character in {"=", "{", "}", ";", "\n", "\r"}:
            break
        cursor += 1
    return cursor


def _initializer_expression_end(source: str, start: int, label: str) -> int:
    """Return the end of one stored-property initializer.

    Newlines and commas terminate a declaration only when they are outside a
    call, collection literal, generic clause, or closure. Property observers
    are not part of the encoded default-value witness.
    """

    code = inventory._swift_code_projection(source)
    pairs = {"(": ")", "[": "]", "<": ">", "{": "}"}
    closing = {value: key for key, value in pairs.items()}
    stack: list[str] = []
    cursor = start
    while cursor < len(code) and code[cursor].isspace():
        cursor += 1
    while cursor < len(code):
        character = code[cursor]
        if character == "{" and not stack:
            closing_brace = inventory._closing_delimiter_index(
                source,
                cursor,
                "{",
                "}",
                label,
            )
            observer = code[cursor + 1:closing_brace]
            if re.match(r"\s*(?:willSet|didSet)\b", observer):
                break
            stack.append(character)
        elif character in pairs:
            stack.append(character)
        elif character in closing:
            if stack and stack[-1] == closing[character]:
                stack.pop()
            elif not stack:
                break
        elif not stack and character in {",", ";", "\n", "\r"}:
            break
        cursor += 1
    return cursor


def _multi_binding_tail_end(source: str, start: int) -> int:
    code = inventory._swift_code_projection(source)
    pairs = {"(": ")", "[": "]", "<": ">", "{": "}"}
    closing = {value: key for key, value in pairs.items()}
    stack: list[str] = []
    cursor = start
    while cursor < len(code):
        character = code[cursor]
        if character in pairs:
            stack.append(character)
        elif character in closing:
            if stack and stack[-1] == closing[character]:
                stack.pop()
            elif not stack:
                break
        elif not stack and character in {";", "}"}:
            break
        elif not stack and character in {"\n", "\r"}:
            previous = cursor - 1
            while previous >= start and code[previous] in {" ", "\t"}:
                previous -= 1
            if previous < start or code[previous] != ",":
                break
        cursor += 1
    return cursor


def _property_attribute_witness(source: str, position: int) -> str:
    code = inventory._swift_code_projection(source)
    window_start = max(0, position - 2_000)
    prefix = code[window_start:position]
    block = re.search(
        r"(?P<attributes>"
        r"(?:@[A-Za-z_][A-Za-z0-9_]*(?:\s*\([^@]*?\))?\s*)+)"
        r"(?:(?:public|package|private|fileprivate|internal|lazy|weak|unowned|"
        r"nonisolated)(?:\s*\([^)]*\))?\s+)*$",
        prefix,
        re.DOTALL,
    )
    if block is None:
        return ""
    start = window_start + block.start("attributes")
    end = window_start + block.end("attributes")
    return _canonical_swift_tokens(source[start:end])


def _has_property_observers(accessor_block: str) -> bool:
    code = inventory._swift_code_projection(accessor_block)
    pattern = re.compile(
        r"\b(?:willSet|didSet)\b(?:\s*\([^()]*\))?\s*\{"
    )
    return any(
        inventory._brace_depth_at(accessor_block, match.start()) == 1
        for match in pattern.finditer(code)
    )


def _stored_property_witnesses(declaration: str) -> tuple[list[dict[str, str]], set[str]]:
    code = inventory._swift_code_projection(declaration)
    properties: list[dict[str, str]] = []
    referenced: set[str] = set()
    pattern = re.compile(r"\b(let|var)\s+([A-Za-z_][A-Za-z0-9_]*)\b")
    for match in pattern.finditer(code):
        if inventory._brace_depth_at(declaration, match.start()) != 1:
            continue
        line_start = max(
            code.rfind("\n", 0, match.start()),
            code.rfind(";", 0, match.start()),
            code.rfind("{", 0, match.start()),
        ) + 1
        modifiers = code[line_start:match.start()]
        if re.search(r"\b(?:class|static)\b", modifiers):
            continue

        cursor = match.end()
        while cursor < len(code) and code[cursor] in {" ", "\t"}:
            cursor += 1
        type_source = ""
        if cursor < len(code) and code[cursor] == ":":
            type_start = cursor + 1
            type_end = _type_expression_end(code, type_start)
            type_source = declaration[type_start:type_end].strip()
            cursor = type_end
            while cursor < len(code) and code[cursor] in {" ", "\t"}:
                cursor += 1

        if cursor < len(code) and code[cursor] == "{":
            closing = inventory._closing_delimiter_index(
                declaration,
                cursor,
                "{",
                "}",
                f"property {match.group(2)}",
            )
            observer = declaration[cursor:closing + 1]
            if not _has_property_observers(observer):
                continue
        default = ""
        continuation = ""
        if cursor < len(code) and code[cursor] == "=":
            default_end = _initializer_expression_end(
                declaration,
                cursor + 1,
                f"property initializer {match.group(2)}",
            )
            default = declaration[cursor + 1:default_end].strip()
            if default_end < len(code) and code[default_end] == ",":
                tail_end = _multi_binding_tail_end(declaration, default_end)
                continuation = declaration[default_end:tail_end].strip()
        elif cursor < len(code) and code[cursor] == ",":
            tail_end = _multi_binding_tail_end(declaration, cursor)
            continuation = declaration[cursor:tail_end].strip()
        elif not type_source:
            # An untyped declaration without an initializer cannot be a valid
            # stored property. In practice this is a pattern match in a nested
            # declaration that the lexical scan should not bind as wire state.
            continue
        properties.append(
            {
                "name": match.group(2),
                "attributes": _property_attribute_witness(declaration, match.start()),
                "type": _canonical_swift_tokens(type_source),
                "default": _canonical_swift_tokens(default),
                "continuation": _canonical_swift_tokens(continuation),
            }
        )
        referenced.update(
            re.findall(
                r"\b([A-Z][A-Za-z0-9_]*)\b",
                f"{type_source} {default} {continuation}",
            )
        )
    return properties, referenced


def _nested_declaration_witnesses(declaration: str) -> dict[str, dict]:
    code = inventory._swift_code_projection(declaration)
    pattern = re.compile(
        r"\b(struct|enum|class)\s+([A-Z][A-Za-z0-9_]*)\b[^\{]*\{"
    )
    result: dict[str, dict] = {}
    for match in pattern.finditer(code):
        if inventory._brace_depth_at(declaration, match.start()) != 1:
            continue
        opening = code.find("{", match.start(), match.end())
        closing = inventory._closing_delimiter_index(
            declaration,
            opening,
            "{",
            "}",
            f"nested request type {match.group(2)}",
        )
        nested, _ = _type_wire_witness(
            declaration[match.start():closing + 1],
            (),
        )
        result[match.group(2)] = nested
    return result


def _named_nested_regions(
    source: str,
    kind: str,
    name: str,
) -> list[str]:
    code = inventory._swift_code_projection(source)
    pattern = re.compile(
        rf"\b{re.escape(kind)}\s+{re.escape(name)}\b[^\{{]*\{{"
    )
    regions: list[str] = []
    for match in pattern.finditer(code):
        if inventory._brace_depth_at(source, match.start()) != 1:
            continue
        opening = code.find("{", match.start(), match.end())
        closing = inventory._closing_delimiter_index(
            source,
            opening,
            "{",
            "}",
            f"{kind} {name}",
        )
        regions.append(source[match.start():closing + 1])
    return regions


def _custom_encoder_witnesses(source: str) -> list[str]:
    code = inventory._swift_code_projection(source)
    pattern = re.compile(
        r"\bfunc\s+encode\s*\(\s*to\b",
    )
    witnesses: list[str] = []
    for match in pattern.finditer(code):
        if inventory._brace_depth_at(source, match.start()) != 1:
            continue
        opening_parenthesis = code.find("(", match.start(), match.end())
        parameters = inventory._extract_delimited_region(
            source,
            opening_parenthesis,
            "(",
            ")",
            "custom request encoder parameters",
        )
        closing_parenthesis = opening_parenthesis + len(parameters) - 1
        opening_brace = code.find("{", closing_parenthesis + 1)
        if opening_brace < 0:
            raise DriftError("custom request encoder has no body")
        body = inventory._extract_braced_region(
            source,
            opening_brace,
            "custom request encoder",
        )
        witnesses.append(_canonical_swift_tokens(parameters + body))
    return witnesses


def _enum_case_witnesses(declaration: str) -> list[str]:
    code = inventory._swift_code_projection(declaration)
    witnesses: list[str] = []
    for match in re.finditer(r"\bcase\s+", code):
        if inventory._brace_depth_at(declaration, match.start()) != 1:
            continue
        end = match.end()
        while end < len(code) and code[end] not in {"\n", "\r", ";", "}"}:
            end += 1
        witnesses.append(_canonical_swift_tokens(declaration[match.start():end]))
    return witnesses


def _type_wire_witness(
    declaration: str,
    extensions: Sequence[str],
) -> tuple[dict, set[str]]:
    code = inventory._swift_code_projection(declaration)
    header = re.search(
        r"\b(struct|enum|class)\s+([A-Z][A-Za-z0-9_]*)\b",
        code,
    )
    if header is None:
        raise DriftError("request type declaration has no resolvable type header")
    properties, referenced = _stored_property_witnesses(declaration)
    coding_keys: list[str] = []
    encoders = _custom_encoder_witnesses(declaration)
    for index, region in enumerate((declaration, *extensions)):
        coding_keys.extend(
            _canonical_swift_tokens(item)
            for item in _named_nested_regions(region, "enum", "CodingKeys")
        )
        if index > 0:
            encoders.extend(_custom_encoder_witnesses(region))
    return (
        {
            "kind": header.group(1),
            "storedProperties": properties,
            "enumCases": _enum_case_witnesses(declaration),
            "codingKeys": sorted(coding_keys),
            "customEncoders": sorted(encoders),
            "initializers": _initializer_witnesses(declaration),
            "nestedTypes": _nested_declaration_witnesses(declaration),
        },
        referenced,
    )


def _request_type_witnesses(
    initial_names: Iterable[str],
    producer_source_path: str,
    type_index: Mapping[str, Sequence[tuple[str, str, str]]],
    extension_index: Mapping[tuple[str, str], Sequence[str]],
) -> dict[str, dict]:
    initial_module = _swift_module_key(producer_source_path)
    pending = [
        (name, initial_module, producer_source_path)
        for name in sorted(set(initial_names))
    ]
    result: dict[str, dict] = {}
    ignored = {
        "Any", "Array", "Bool", "CodingKey", "Data", "Date", "Decimal",
        "Dictionary", "Double", "Float", "Int", "Int8", "Int16", "Int32",
        "Int64", "Optional", "Set", "String", "UInt", "UInt64", "URL", "UUID",
    }
    while pending:
        name, lookup_module, lookup_path = pending.pop(0)
        if name in ignored:
            continue
        candidates = _visible_type_candidates(
            type_index.get(name, ()),
            lookup_module=lookup_module,
            lookup_path=lookup_path,
        )
        if not candidates:
            continue
        if len(candidates) != 1:
            paths = [path for _, path, _ in candidates]
            raise DriftError(
                f"request type {name} is ambiguous for {lookup_module}: {paths}"
            )
        module, path, declaration = candidates[0]
        key = f"{module}:{name}"
        if key in result:
            continue
        witness, referenced = _type_wire_witness(
            declaration,
            extension_index.get((module, name), ()),
        )
        result[key] = {"path": path, "wire": witness}
        pending.extend(
            (nested, module, path)
            for nested in sorted(referenced - ignored)
        )
    return result


def _resolved_endpoint_arguments(arguments: Mapping[str, str]) -> dict[str, str]:
    body_labels = [label for label in ("body", "httpBody") if label in arguments]
    if len(body_labels) > 1:
        raise DriftError("request semantics found both body and httpBody Endpoint arguments")
    body_label = body_labels[0] if body_labels else "none"
    body_expression = arguments.get(body_label, "") if body_labels else ""
    return {
        "method": _canonical_swift_tokens(arguments.get("method", "")),
        "path": _canonical_swift_tokens(arguments.get("path", "")),
        "query": _canonical_swift_tokens(arguments.get("query", "[]")),
        "bodyKind": body_label,
        "body": _canonical_swift_tokens(body_expression),
        "requiresAuth": _canonical_swift_tokens(arguments.get("requiresAuth", "true")),
    }


def _enclosing_control_witness(source: str, position: int) -> str:
    code = inventory._swift_code_projection(source)
    stack: list[int] = []
    for index, character in enumerate(code[:position]):
        if character == "{":
            stack.append(index)
        elif character == "}" and stack:
            stack.pop()
    for opening in reversed(stack):
        line_start = max(
            code.rfind("\n", 0, opening),
            code.rfind(";", 0, opening),
            code.rfind("{", 0, opening),
            code.rfind("}", 0, opening),
        ) + 1
        header = code[line_start:opening + 1]
        if re.search(r"\b(?:if|for|while|switch)\b", header):
            return _canonical_swift_tokens(source[line_start:opening + 1])
    return ""


def _local_query_witness(body: str, name: str, producer_symbol: str) -> dict:
    code = inventory._swift_code_projection(body)
    declaration_pattern = re.compile(
        rf"\b(?:let|var)\s+{re.escape(name)}\b(?:\s*:\s*[^=\n\r]+)?\s*=\s*"
    )
    declarations: list[str] = []
    for declaration in declaration_pattern.finditer(code):
        if inventory._brace_depth_at(body, declaration.start()) != 1:
            continue
        end = _initializer_expression_end(
            body,
            declaration.end(),
            f"local query declaration {name}@{producer_symbol}",
        )
        declarations.append(
            _canonical_swift_tokens(body[declaration.start():end])
        )
    if len(declarations) != 1:
        raise DriftError(
            f"request semantics cannot resolve local query {name}@{producer_symbol}; "
            f"found {len(declarations)} declarations"
        )

    mutations: list[dict[str, str]] = []
    method_pattern = re.compile(
        rf"\b{re.escape(name)}\s*\.\s*([A-Za-z_][A-Za-z0-9_]*)\s*\("
    )
    for method in method_pattern.finditer(code):
        opening = code.find("(", method.start(), method.end())
        call = inventory._extract_delimited_region(
            body,
            opening,
            "(",
            ")",
            f"local query mutation {name}.{method.group(1)}@{producer_symbol}",
        )
        mutations.append(
            {
                "control": _enclosing_control_witness(body, method.start()),
                "write": _canonical_swift_tokens(
                    body[method.start():opening] + call
                ),
            }
        )

    trailing_closure_pattern = re.compile(
        rf"\b{re.escape(name)}\s*\.\s*([A-Za-z_][A-Za-z0-9_]*)\s*\{{"
    )
    for method in trailing_closure_pattern.finditer(code):
        opening = code.find("{", method.start(), method.end())
        closing = inventory._closing_delimiter_index(
            body,
            opening,
            "{",
            "}",
            f"local query trailing closure {name}.{method.group(1)}@{producer_symbol}",
        )
        mutations.append(
            {
                "control": _enclosing_control_witness(body, method.start()),
                "write": _canonical_swift_tokens(body[method.start():closing + 1]),
            }
        )

    assignment_pattern = re.compile(
        rf"\b{re.escape(name)}(?:\s*\[[^\]\n\r]+\])?"
        r"(?:\s*\.\s*[A-Za-z_][A-Za-z0-9_]*)*\s*"
        r"(?:(?<![=!<>])=(?!=)|\+=|-=|\*=|/=)\s*"
    )
    for assignment in assignment_pattern.finditer(code):
        if any(
            declaration.start() <= assignment.start() < declaration.end()
            for declaration in declaration_pattern.finditer(code)
        ):
            continue
        end = _initializer_expression_end(
            body,
            assignment.end(),
            f"local query assignment {name}@{producer_symbol}",
        )
        mutations.append(
            {
                "control": _enclosing_control_witness(body, assignment.start()),
                "write": _canonical_swift_tokens(body[assignment.start():end]),
            }
        )

    inout_pattern = re.compile(rf"&\s*{re.escape(name)}\b")
    for escape in inout_pattern.finditer(code):
        mutations.append(
            {
                "control": _enclosing_control_witness(body, escape.start()),
                "write": _canonical_swift_tokens(body[escape.start():escape.end()]),
            }
        )
    return {"declaration": declarations[0], "mutations": mutations}


def _request_context(
    *,
    arguments: Mapping[str, str],
    parameters: str,
    body: str,
    producer_symbol: str,
    producer_source_path: str,
    producer_source: str,
    generic_clause: str,
    type_index: Mapping[str, Sequence[tuple[str, str, str]]],
    extension_index: Mapping[tuple[str, str], Sequence[str]],
) -> dict:
    generic_names = _generic_parameter_names(generic_clause)
    type_names = _request_type_names(arguments, parameters, body) - generic_names
    local_types: dict[str, dict] = {}
    external_types: set[str] = set()
    for name in sorted(type_names):
        declaration = _local_type_declaration(body, name)
        if declaration is None:
            external_types.add(name)
        else:
            local_types[name] = _type_wire_witness(declaration, ())[0]

    dependency_tokens: list[object] = []
    for label in ("query", "body", "httpBody"):
        expression = arguments.get(label)
        if expression is None:
            continue
        bare = re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", expression)
        if bare is None or re.search(
            rf"\b{re.escape(expression)}\s*:",
            parameters,
        ):
            continue
        if producer_symbol == "ScenarioRepository.syncPendingUploads" and expression == "bodyData":
            lines = [
                line for line in inventory._swift_without_comments(body).splitlines()
                if re.search(r"\bbodyData\b", line)
            ]
            dependency_tokens.append(_canonical_swift_tokens("\n".join(lines)))
        elif label == "query":
            dependency_tokens.append(
                _local_query_witness(body, expression, producer_symbol)
            )
        else:
            # Non-query local request bodies are uncommon and can involve
            # arbitrary data flow. Preserve the conservative seam unless a
            # narrower producer-specific witness exists above.
            dependency_tokens.append(_canonical_swift_tokens(body))

    context = {
        "arguments": _resolved_endpoint_arguments(arguments),
        "parameters": _canonical_swift_tokens(parameters),
        "genericClause": _canonical_swift_tokens(generic_clause),
        "localRequestTypes": local_types,
        "externalRequestTypes": _request_type_witnesses(
            external_types,
            producer_source_path,
            type_index,
            extension_index,
        ),
        "dependencies": dependency_tokens,
    }
    if producer_symbol == "ScenarioRepository.syncPendingUploads":
        context["scenarioOutbox"] = _scenario_outbox_witness(
            producer_source,
            producer_source_path,
            type_index,
        )
    return context


def _call_witnesses(source: str, call_patterns: Sequence[str]) -> list[str]:
    code = inventory._swift_code_projection(source)
    matches: list[tuple[int, str]] = []
    for expression in call_patterns:
        pattern = re.compile(rf"\b(?:{expression})\s*\(")
        for match in pattern.finditer(code):
            opening = code.find("(", match.start(), match.end())
            call = inventory._extract_delimited_region(
                source,
                opening,
                "(",
                ")",
                f"request-semantic call {expression}",
            )
            matches.append(
                (
                    match.start(),
                    _canonical_swift_tokens(source[match.start():opening] + call),
                )
            )
    return [witness for _, witness in sorted(matches)]


def _guard_binding_witness(
    source: str,
    binding_names: Sequence[str],
    label: str,
) -> str:
    code = inventory._swift_code_projection(source)
    matches: list[str] = []
    for guard in re.finditer(r"\bguard\b", code):
        guard_depth = inventory._brace_depth_at(source, guard.start())
        for else_match in re.finditer(r"\belse\s*\{", code[guard.end():]):
            else_start = guard.end() + else_match.start()
            opening = code.find("{", else_start, guard.end() + else_match.end())
            if inventory._brace_depth_at(source, else_start) != guard_depth:
                continue
            condition = code[guard.start():else_start]
            if not all(
                re.search(rf"\blet\s+{re.escape(name)}\b", condition)
                for name in binding_names
            ):
                break
            closing = inventory._closing_delimiter_index(
                source,
                opening,
                "{",
                "}",
                label,
            )
            matches.append(
                _canonical_swift_tokens(source[guard.start():closing + 1])
            )
            break
    if len(matches) != 1:
        raise DriftError(f"request semantics cannot resolve {label}; found {len(matches)}")
    return matches[0]


def _named_type_property_witness(
    *,
    type_name: str,
    property_name: str,
    producer_source_path: str,
    type_index: Mapping[str, Sequence[tuple[str, str, str]]],
) -> dict:
    lookup_module = _swift_module_key(producer_source_path)
    candidates = _visible_type_candidates(
        type_index.get(type_name, ()),
        lookup_module=lookup_module,
        lookup_path=producer_source_path,
    )
    if len(candidates) != 1:
        paths = [path for _, path, _ in candidates]
        raise DriftError(
            f"request semantics cannot resolve {type_name}.{property_name}: {paths}"
        )
    _, path, declaration = candidates[0]
    matches = [
        property_witness
        for property_witness in _stored_property_witnesses(declaration)[0]
        if property_witness["name"] == property_name
    ]
    if len(matches) != 1:
        raise DriftError(
            f"request semantics cannot resolve {type_name}.{property_name}; "
            f"found {len(matches)}"
        )
    code = inventory._swift_code_projection(declaration)
    assignments: list[str] = []
    assignment_pattern = re.compile(
        rf"\bself\s*\.\s*{re.escape(property_name)}\s*="
    )
    for assignment in assignment_pattern.finditer(code):
        end = assignment.end()
        while end < len(code) and code[end] not in {"\n", "\r", ";", "}"}:
            end += 1
        assignments.append(
            _canonical_swift_tokens(declaration[assignment.start():end])
        )
    if len(assignments) != 1:
        raise DriftError(
            f"request semantics cannot resolve assignment to "
            f"{type_name}.{property_name}; found {len(assignments)}"
        )
    return {"path": path, "property": matches[0], "assignment": assignments[0]}


def _scenario_outbox_witness(
    source: str,
    producer_source_path: str,
    type_index: Mapping[str, Sequence[tuple[str, str, str]]],
) -> dict:
    enqueue = _function_region_in_scope(
        source,
        "enqueueUpload",
        "ScenarioRepository.enqueueUpload",
    )
    submit = _function_region_in_scope(
        source,
        "submitScenario",
        "ScenarioRepository.submitScenario",
    )
    return {
        "enqueueParameters": _canonical_swift_tokens(enqueue[:enqueue.find("{")]),
        "bodyPersistenceGuard": _guard_binding_witness(
            enqueue,
            ("body", "json"),
            "ScenarioRepository.enqueueUpload body persistence guard",
        ),
        "ticketCalls": _call_witnesses(enqueue, (r"PendingScenarioUpload",)),
        "enqueueCalls": _call_witnesses(submit, (r"enqueueUpload",)),
        "submitEndpointCalls": _call_witnesses(
            submit,
            (r"Endpoints\s*\.\s*[A-Za-z_][A-Za-z0-9_]*",),
        ),
        "persistedPayload": _named_type_property_witness(
            type_name="PendingScenarioUpload",
            property_name="requestJSON",
            producer_source_path=producer_source_path,
            type_index=type_index,
        ),
    }


def _request_assignment_witnesses(source: str) -> list[str]:
    code = inventory._swift_code_projection(source)
    witnesses: list[tuple[int, str]] = []
    for match in re.finditer(r"\brequest\.(?:httpMethod|httpBody)\s*=", code):
        end = match.end()
        while end < len(code) and code[end] not in {"\n", "\r", ";", "}"}:
            end += 1
        witnesses.append(
            (match.start(), _canonical_swift_tokens(source[match.start():end]))
        )
    return [witness for _, witness in sorted(witnesses)]


def _analytics_request_witnesses(
    source: str,
    type_index: Mapping[str, Sequence[tuple[str, str, str]]],
    extension_index: Mapping[tuple[str, str], Sequence[str]],
) -> dict[str, dict]:
    client_scope = inventory._analytics_client_region(source)
    transport_scope = inventory._declaration_region(
        source,
        re.compile(r"^\s*public\s+struct\s+URLSessionAnalyticsTransport\b", re.MULTILINE),
        "URLSessionAnalyticsTransport",
    )
    send = _function_region_in_scope(
        transport_scope,
        "send",
        "URLSessionAnalyticsTransport.send",
    )
    wire_models = _request_type_witnesses(
        {"AnalyticsTrackBatch", "AnalyticsWireEvent"},
        inventory.ANALYTICS_SOURCE_PATH,
        type_index,
        extension_index,
    )
    encoder_properties = [
        property_witness
        for property_witness in _stored_property_witnesses(client_scope)[0]
        if property_witness["name"] == "encoder"
    ]
    if len(encoder_properties) != 1:
        raise DriftError(
            "request semantics must resolve DefaultAnalyticsClient.encoder exactly once; "
            f"found {len(encoder_properties)}"
        )
    transport = {
        "parameters": _canonical_swift_tokens(send[:send.find("{")]),
        "calls": _call_witnesses(
            send,
            (
                r"baseURL\s*\.\s*appending",
                r"URLRequest",
                r"request\s*\.\s*setValue",
                r"tokenProvider",
                r"session\s*\.\s*data",
            ),
        ),
        "assignments": _request_assignment_witnesses(send),
        "encoder": encoder_properties[0],
    }
    result: dict[str, dict] = {}
    for path_symbol, binding in inventory.ANALYTICS_PRODUCER_BINDINGS.items():
        producer = _function_region_in_scope(
            client_scope,
            binding["functionSymbol"],
            f"DefaultAnalyticsClient.{binding['functionSymbol']}",
        )
        result[path_symbol] = {
            "parameters": _canonical_swift_tokens(
                producer[:producer.find("{")]
            ),
            "producerCalls": _call_witnesses(
                producer,
                (
                    r"AnalyticsWireEvent",
                    r"AnalyticsTrackBatch",
                    r"encoder\s*\.\s*encode",
                    r"transport\s*\.\s*send",
                ),
            ),
            "transport": transport,
            "wireModels": wire_models,
        }
    return result


def _producer_request_witnesses(
    records: Sequence[Mapping],
    sources: Mapping[str, bytes],
) -> dict[str, dict]:
    witnesses: dict[str, dict] = {
        "__endpoint_core__": {"wire": _endpoint_core_witness(sources)},
        "__http_methods__": {"cases": _http_method_witness(sources)},
    }
    type_index, extension_index = _request_type_indexes(sources)
    analytics_cache: dict[str, dict] | None = None
    for record in records:
        kind = record["producerKind"]
        symbol = record["producerSymbol"]
        path = record["producerSourcePath"]
        variant = record["operationVariantId"]
        raw_source = sources.get(path)
        if raw_source is None:
            raise DriftError(f"request semantics are missing producer source: {path}")
        source = raw_source.decode("utf-8")
        if kind == "analytics_path":
            if analytics_cache is None:
                analytics_cache = _analytics_request_witnesses(
                    source,
                    type_index,
                    extension_index,
                )
            path_symbol = symbol.rsplit(".", 1)[-1]
            context = analytics_cache[path_symbol]
        elif kind == "endpoint_factory":
            parameters, body, arguments, generic_clause = _factory_parts(
                source,
                symbol,
                path,
            )
            context = _request_context(
                arguments=arguments,
                parameters=parameters,
                body=body,
                producer_symbol=symbol,
                producer_source_path=path,
                producer_source=source,
                generic_clause=generic_clause,
                type_index=type_index,
                extension_index=extension_index,
            )
            source_symbol = symbol.split(".", 1)[0]
            if source_symbol in GENERIC_BODY_CALLSITE_BINDINGS:
                context["genericBodyCallsites"] = _generic_body_callsite_witnesses(
                    source_symbol,
                    sources,
                    type_index,
                    extension_index,
                )
        elif kind == "direct_endpoint":
            parameters, body, arguments, generic_clause = _direct_parts(
                source,
                symbol,
                path,
            )
            context = _request_context(
                arguments=arguments,
                parameters=parameters,
                body=body,
                producer_symbol=symbol,
                producer_source_path=path,
                producer_source=source,
                generic_clause=generic_clause,
                type_index=type_index,
                extension_index=extension_index,
            )
        else:
            raise DriftError(f"request semantics found unsupported producer kind: {kind}")
        witnesses[variant] = {
            "producerSymbol": symbol,
            "producerSourcePath": path,
            "context": context,
        }
    return witnesses


def _semantic_projection(mapping: Mapping, records: list[dict]) -> dict:
    generated = inventory._manifest(
        mapping,
        records,
        [],
        None,
        "uncommitted_contract_branch",
    )
    return {
        **{field: generated[field] for field in SEMANTIC_FIELDS},
        "recordsCanonical": inventory.canonical_record_bytes(records),
        "matrixRows": generated["matrixRows"],
    }


def _committed_semantic_projection(manifest: Mapping) -> dict:
    records = manifest.get("records")
    matrix_rows = manifest.get("matrixRows")
    if not isinstance(records, list) or not all(isinstance(item, dict) for item in records):
        raise DriftError("committed iOS inventory records must be an object array")
    if not isinstance(matrix_rows, list):
        raise DriftError("committed iOS inventory matrixRows must be an array")
    try:
        fields = {field: manifest[field] for field in SEMANTIC_FIELDS}
    except KeyError as error:
        raise DriftError(f"committed iOS inventory is missing semantic field: {error.args[0]}") from error
    return {
        **fields,
        "recordsCanonical": inventory.canonical_record_bytes(records),
        "matrixRows": matrix_rows,
    }


def compare_worktree_semantics(
    *,
    manifest: Mapping,
    mapping_bytes: bytes,
    generator_bytes: bytes,
    current_sources: Mapping[str, bytes],
    historical_sources: Mapping[str, bytes],
) -> None:
    """Compare current all-source discovery and request semantics with the pin."""

    expected_generator = _manifest_input_sha(manifest, inventory.GENERATOR_PATH)
    if _sha256(generator_bytes) != expected_generator:
        raise DriftError(
            "inventory generator changed; coordinated evidence regeneration is required"
        )
    expected_mapping = _manifest_input_sha(manifest, inventory.SOURCE_MAPPING_PATH)
    if _sha256(mapping_bytes) != expected_mapping:
        raise DriftError(
            "inventory source mapping changed; coordinated evidence regeneration is required"
        )
    mapping = _parse_json_object(mapping_bytes, inventory.SOURCE_MAPPING_PATH)

    try:
        historical_records = inventory.validate_inventory_source(
            mapping,
            historical_sources,
        )
        current_records = _validate_current_inventory(
            mapping,
            current_sources,
            historical_sources,
        )
    except inventory.InventoryError as error:
        raise DriftError(f"current worktree contract scan failed: {error}") from error

    expected_projection = _committed_semantic_projection(manifest)
    historical_projection = _semantic_projection(mapping, historical_records)
    if historical_projection != expected_projection:
        raise DriftError(
            "pinned source semantics do not match the committed relational inventory"
        )
    current_projection = _semantic_projection(mapping, current_records)
    if current_projection != expected_projection:
        raise DriftError(
            "current worktree producer relationships drifted from the committed inventory"
        )

    try:
        historical_requests = _producer_request_witnesses(
            historical_records,
            historical_sources,
        )
        current_requests = _producer_request_witnesses(current_records, current_sources)
    except inventory.InventoryError as error:
        raise DriftError(f"request-semantic projection failed: {error}") from error
    if historical_requests != current_requests:
        keys = sorted(set(historical_requests) | set(current_requests))
        changed = next(
            key for key in keys
            if historical_requests.get(key) != current_requests.get(key)
        )
        witness = current_requests.get(changed) or historical_requests.get(changed) or {}
        symbol = witness.get("producerSymbol", changed)
        raise DriftError(
            f"current request semantics drifted for {symbol} ({changed}); "
            "coordinated evidence regeneration is required"
        )


def verify_current_worktree_semantics(repo_root: Path, manifest_path: Path) -> None:
    repo_root = repo_root.resolve()
    manifest_path = manifest_path.resolve()
    verify_incremental_policy_lock(repo_root)
    if not manifest_path.is_file():
        raise DriftError(f"committed iOS inventory manifest is missing: {manifest_path}")
    manifest = _parse_json_object(manifest_path.read_bytes(), str(manifest_path))
    revision = _validate_revision(manifest, repo_root)
    mapping_path = repo_root / inventory.SOURCE_MAPPING_PATH
    generator_path = repo_root / inventory.GENERATOR_PATH
    if not mapping_path.is_file() or not generator_path.is_file():
        raise DriftError("current worktree is missing the inventory generator or source mapping")
    mapping_bytes = mapping_path.read_bytes()
    generator_bytes = generator_path.read_bytes()
    mapping = _parse_json_object(mapping_bytes, str(mapping_path))
    try:
        current_sources = _load_current_worktree_sources(repo_root)
        historical_sources = inventory._load_revision_source_bytes(repo_root, revision)
    except inventory.InventoryError as error:
        raise DriftError(f"unable to load iOS contract source inputs: {error}") from error
    compare_worktree_semantics(
        manifest=manifest,
        mapping_bytes=mapping_bytes,
        generator_bytes=generator_bytes,
        current_sources=current_sources,
        historical_sources=historical_sources,
    )


def _default_repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, default=_default_repo_root())
    parser.add_argument("--manifest", default=DEFAULT_MANIFEST_PATH)
    parser.add_argument("--backend-manifest", type=Path)
    parser.add_argument(
        "--layer",
        choices=("all", "historical", "worktree"),
        default="all",
    )
    args = parser.parse_args(argv)

    repo_root = args.repo_root.resolve()
    manifest_path = Path(args.manifest)
    if not manifest_path.is_absolute():
        manifest_path = repo_root / PurePosixPath(args.manifest)
    if args.layer in {"all", "historical"}:
        verify_historical_manifest(repo_root, manifest_path)
        manifest = _parse_json_object(manifest_path.read_bytes(), str(manifest_path))
        print(
            "Historical iOS inventory provenance passed "
            f"({manifest['iosSourceRevision']}; {len(manifest['sourceInputs'])} Git-object inputs)."
        )
    if args.layer in {"all", "worktree"}:
        verify_current_worktree_semantics(repo_root, manifest_path)
        manifest = _parse_json_object(manifest_path.read_bytes(), str(manifest_path))
        print(
            "Current iOS contract semantics passed "
            f"({manifest['operationKeyCount']} operations / "
            f"{manifest['producerVariantCount']} producers / "
            f"{manifest['matrixRowCount']} matrix rows / "
            f"{manifest['relationalRecordCount']} relations)."
        )
    if args.backend_manifest is not None:
        backend_manifest = args.backend_manifest.resolve()
        if not backend_manifest.is_file():
            raise DriftError(f"backend manifest copy is missing: {backend_manifest}")
        assert_byte_identical(
            "backend manifest copy",
            manifest_path.read_bytes(),
            backend_manifest.read_bytes(),
        )
        print("Backend manifest copy is byte-identical to the iOS authority.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except DriftError as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1) from error
