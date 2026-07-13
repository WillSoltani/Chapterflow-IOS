#!/usr/bin/env python3
"""Generate the iOS-owned native request inventory from pinned Swift source.

The checked-in source mapping owns producer -> operation -> matrix relationships.
This generator verifies those relationships against production Swift source and
emits deterministic records that the backend can consume without becoming the
authority for the iOS inventory.
"""

from __future__ import annotations

import argparse
from collections import defaultdict
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
from typing import Callable, Iterable, Mapping, Sequence


SOURCE_SCHEMA = "chapterflow-ios-native-inventory-source-v2"
MANIFEST_SCHEMA = "chapterflow-ios-native-inventory-v2"
IOS_REPOSITORY = "WillSoltani/Chapterflow-IOS"
SOURCE_MAPPING_PATH = "contracts/native-ios/v1/ios-native-contract-inventory-source.json"
GENERATOR_PATH = "scripts/contracts/generate_ios_native_inventory.py"
EXPECTED_OPERATION_COUNT = 83
EXPECTED_PRODUCER_COUNT = 93
EXPECTED_MATRIX_ROW_COUNT = 29

EXPECTED_MATRIX_ROW_IDS = frozenset(
    {
        "account-deactivation",
        "account-deletion",
        "apns-device-registration",
        "apple-purchase-verification",
        "ask-the-book",
        "audio-narration-plan",
        "book-detail-manifest",
        "book-state-cursor-preferences",
        "catalog",
        "chapter-content",
        "commitments",
        "data-export",
        "entitlements-paywall",
        "fsrs-reviews",
        "gifts-referrals",
        "mobile-config",
        "notebook",
        "notification-inbox",
        "notification-preferences",
        "onboarding",
        "profile-social",
        "progress-overview",
        "quiz-load-check-events",
        "quiz-submit",
        "reading-pairs",
        "reading-sessions",
        "saved-books",
        "search-index",
        "start-book",
    }
)

RECORD_FIELDS = (
    "operationId",
    "method",
    "routeTemplate",
    "matrixRowId",
    "operationVariantId",
    "producerKind",
    "producerSymbol",
    "producerSourcePath",
    "stableVariantSuffix",
    "sourceMethodExpression",
    "sourcePathExpression",
)

DIRECT_PRODUCER_SYMBOLS = {
    "Packages/PaywallFeature/Sources/PaywallFeature/LiveEntitlementRepository.swift":
        "LiveEntitlementRepository.directEndpoint",
    "Packages/EngagementFeature/Sources/EngagementFeature/Scenarios/ScenarioRepository.swift":
        "ScenarioRepository.replayDirectEndpoint",
}

ANALYTICS_SOURCE_PATH = (
    "Packages/CoreKit/Sources/CoreKit/Analytics/AnalyticsClient.swift"
)


class InventoryError(ValueError):
    """The source mapping, Git provenance, or generated inventory is invalid."""


def _run_git(repo_root: Path, args: Sequence[str], *, binary: bool = False):
    try:
        result = subprocess.run(
            ["git", *args],
            cwd=repo_root,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=not binary,
        )
    except subprocess.CalledProcessError as error:
        stderr = error.stderr
        if isinstance(stderr, bytes):
            stderr = stderr.decode("utf-8", errors="replace")
        detail = (stderr or "").strip()
        raise InventoryError(f"git {' '.join(args)} failed: {detail}") from error
    return result.stdout


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _validate_full_sha(value: str, label: str) -> None:
    if not re.fullmatch(r"[0-9a-f]{40}", value):
        raise InventoryError(f"{label} must be a full lowercase Git SHA")


def _parse_json_object(data: bytes, label: str) -> dict:
    try:
        parsed = json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise InventoryError(f"{label} is not valid UTF-8 JSON: {error}") from error
    if not isinstance(parsed, dict):
        raise InventoryError(f"{label} must be a JSON object")
    return parsed


def _is_production_swift_path(path: str) -> bool:
    parts = PurePosixPath(path).parts
    return (
        len(parts) >= 5
        and parts[0] == "Packages"
        and parts[2] == "Sources"
        and path.endswith(".swift")
    )


def _is_endpoint_definition_path(path: str) -> bool:
    name = PurePosixPath(path).name
    return name.startswith("Endpoint") or name == "BillingEndpoints.swift"


def _list_worktree_swift_paths(repo_root: Path) -> list[str]:
    packages = repo_root / "Packages"
    if not packages.is_dir():
        raise InventoryError(f"production Packages directory is missing: {packages}")
    return sorted(
        path.relative_to(repo_root).as_posix()
        for path in packages.glob("**/Sources/**/*.swift")
        if path.is_file() and _is_production_swift_path(path.relative_to(repo_root).as_posix())
    )


def _list_revision_swift_paths(repo_root: Path, revision: str) -> list[str]:
    output = _run_git(repo_root, ["ls-tree", "-r", "--name-only", revision, "--", "Packages"])
    return sorted(path for path in output.splitlines() if _is_production_swift_path(path))


def _git_object_bytes(repo_root: Path, revision: str, path: str) -> bytes:
    return _git_object_bytes_many(repo_root, revision, [path])[path]


def _git_object_bytes_many(
    repo_root: Path, revision: str, relative_paths: Iterable[str]
) -> dict[str, bytes]:
    paths = sorted(set(relative_paths))
    if not paths:
        return {}
    requests = "".join(f"{revision}:{path}\n" for path in paths).encode("utf-8")
    try:
        result = subprocess.run(
            ["git", "cat-file", "--batch"],
            cwd=repo_root,
            check=True,
            input=requests,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except subprocess.CalledProcessError as error:
        detail = error.stderr.decode("utf-8", errors="replace").strip()
        raise InventoryError(f"git cat-file --batch failed: {detail}") from error

    stream = io.BytesIO(result.stdout)
    objects: dict[str, bytes] = {}
    for path in paths:
        header = stream.readline().decode("utf-8", errors="replace").rstrip("\n")
        parts = header.split()
        if len(parts) == 2 and parts[1] == "missing":
            raise InventoryError(f"selected revision does not contain required input: {path}")
        if len(parts) != 3 or parts[1] != "blob" or not parts[2].isdigit():
            raise InventoryError(f"unexpected Git object response for {path}: {header}")
        size = int(parts[2])
        value = stream.read(size)
        if len(value) != size or stream.read(1) != b"\n":
            raise InventoryError(f"truncated Git object response for {path}")
        objects[path] = value
    if stream.read(1):
        raise InventoryError("unexpected trailing bytes from Git object batch")
    return objects


def load_worktree_source_bytes(repo_root: Path, mapping: Mapping) -> dict[str, bytes]:
    del mapping  # The discovery universe is intentionally independent of mapping membership.
    sources: dict[str, bytes] = {}
    for relative_path in _list_worktree_swift_paths(repo_root):
        sources[relative_path] = (repo_root / relative_path).read_bytes()
    return sources


def _load_revision_source_bytes(repo_root: Path, revision: str) -> dict[str, bytes]:
    paths = _list_revision_swift_paths(repo_root, revision)
    return _git_object_bytes_many(repo_root, revision, paths)


def _producer_symbol_for_factory(path: str, source_symbol: str) -> str:
    if source_symbol != "submitQuiz":
        return source_symbol
    if path == "Packages/QuizFeature/Sources/QuizFeature/Endpoints+Quiz.swift":
        return "submitQuiz.online"
    if path == "Packages/Networking/Sources/Networking/Endpoint+Sync.swift":
        return "submitQuiz.sync"
    raise InventoryError(f"unclassified submitQuiz producer: {path}")


def discover_producers(sources: Mapping[str, bytes]) -> set[tuple[str, str, str]]:
    """Discover every production endpoint factory, direct Endpoint, and analytics path."""
    discovered: set[tuple[str, str, str]] = set()
    factory_pattern = re.compile(
        r"^\s*(?:public\s+)?static\s+func\s+([A-Za-z_][A-Za-z0-9_]*)",
        re.MULTILINE,
    )
    direct_pattern = re.compile(r"\bEndpoint\s*\(")

    for path, raw_source in sources.items():
        try:
            source = raw_source.decode("utf-8")
        except UnicodeDecodeError as error:
            raise InventoryError(f"production Swift source is not UTF-8: {path}") from error

        if _is_endpoint_definition_path(path):
            for match in factory_pattern.finditer(source):
                source_symbol = match.group(1)
                if source_symbol == "getSession":
                    continue
                producer_symbol = _producer_symbol_for_factory(path, source_symbol)
                item = ("endpoint_factory", producer_symbol, path)
                if item in discovered:
                    raise InventoryError(f"duplicate discovered endpoint factory: {producer_symbol}@{path}")
                discovered.add(item)
            continue

        direct_matches = list(direct_pattern.finditer(source))
        if direct_matches:
            producer_symbol = DIRECT_PRODUCER_SYMBOLS.get(path)
            if producer_symbol is None:
                line = source.count("\n", 0, direct_matches[0].start()) + 1
                raise InventoryError(f"unclassified direct Endpoint producer: {path}:{line}")
            if len(direct_matches) != 1:
                raise InventoryError(
                    f"direct Endpoint producer must be unique in {path}; found {len(direct_matches)}"
                )
            discovered.add(("direct_endpoint", producer_symbol, path))

    analytics_raw = sources.get(ANALYTICS_SOURCE_PATH)
    if analytics_raw is None:
        raise InventoryError(f"analytics producer source is missing: {ANALYTICS_SOURCE_PATH}")
    analytics_source = analytics_raw.decode("utf-8")
    analytics_matches = re.findall(
        r'^\s*static\s+let\s+(track|beacon)\s*=\s*"/book/me/analytics/[^"]+"',
        analytics_source,
        re.MULTILINE,
    )
    if sorted(analytics_matches) != ["beacon", "track"]:
        raise InventoryError("analytics path producer discovery must find exactly track and beacon")
    for symbol in analytics_matches:
        discovered.add(
            (
                "analytics_path",
                f"URLSessionAnalyticsTransport.Path.{symbol}",
                ANALYTICS_SOURCE_PATH,
            )
        )
    return discovered


def _extract_braced_region(source: str, opening_brace: int, label: str) -> str:
    depth = 0
    index = opening_brace
    quote: str | None = None
    line_comment = False
    block_comment_depth = 0
    while index < len(source):
        char = source[index]
        following = source[index + 1] if index + 1 < len(source) else ""
        if line_comment:
            if char == "\n":
                line_comment = False
            index += 1
            continue
        if block_comment_depth:
            if char == "/" and following == "*":
                block_comment_depth += 1
                index += 2
                continue
            if char == "*" and following == "/":
                block_comment_depth -= 1
                index += 2
                continue
            index += 1
            continue
        if quote is not None:
            if char == "\\":
                index += 2
                continue
            if char == quote:
                quote = None
            index += 1
            continue
        if char == "/" and following == "/":
            line_comment = True
            index += 2
            continue
        if char == "/" and following == "*":
            block_comment_depth = 1
            index += 2
            continue
        if char in {'"', "'"}:
            quote = char
            index += 1
            continue
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return source[opening_brace:index + 1]
        index += 1
    raise InventoryError(f"could not find closing brace for {label}")


def _factory_region(source: str, producer_symbol: str, path: str) -> str:
    source_symbol = producer_symbol.split(".", 1)[0]
    pattern = re.compile(
        rf"^\s*(?:public\s+)?static\s+func\s+{re.escape(source_symbol)}"
        r"(?:<[^>{}]*>)?\s*\(",
        re.MULTILINE,
    )
    matches = list(pattern.finditer(source))
    if len(matches) != 1:
        raise InventoryError(
            f"producer symbol {producer_symbol} must resolve to one factory in {path}; "
            f"found {len(matches)}"
        )
    opening_brace = source.find("{", matches[0].end())
    if opening_brace < 0:
        raise InventoryError(f"producer symbol {producer_symbol} has no function body in {path}")
    return _extract_braced_region(source, opening_brace, f"{producer_symbol}@{path}")


def _method_from_source_expression(expression: str, producer_kind: str) -> str:
    if producer_kind == "analytics_path":
        match = re.fullmatch(r'request\.httpMethod = "([A-Z]+)"', expression)
    else:
        match = re.fullmatch(r"method: \.([a-z]+)", expression)
    if match is None:
        raise InventoryError(f"invalid source method expression: {expression}")
    return match.group(1).upper()


def _route_from_source_expression(expression: str, route_template: str) -> str:
    if len(expression) < 2 or expression[0] != '"' or expression[-1] != '"':
        raise InventoryError(f"source path expression must be one exact Swift string literal: {expression}")
    source_path = expression[1:-1]
    interpolations = list(re.finditer(r"\\\([^)]*\)", source_path))
    placeholders = re.findall(r"\{[^{}]+\}", route_template)
    if len(interpolations) != len(placeholders):
        raise InventoryError(
            f"route placeholder count does not match source path expression: {route_template} / {expression}"
        )
    pieces: list[str] = []
    cursor = 0
    for match, placeholder in zip(interpolations, placeholders):
        pieces.append(source_path[cursor:match.start()])
        pieces.append(placeholder)
        cursor = match.end()
    pieces.append(source_path[cursor:])
    return "".join(pieces)


def _stable_suffix(producer_symbol: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", producer_symbol.lower()).strip("-")


def _validate_text_field(record: Mapping, field: str) -> str:
    value = record.get(field)
    if not isinstance(value, str) or not value:
        raise InventoryError(f"inventory record has invalid {field}")
    if "\t" in value or "\n" in value or "\r" in value:
        raise InventoryError(f"inventory record {field} contains a canonicalization delimiter")
    return value


def validate_inventory_source(mapping: Mapping, sources: Mapping[str, bytes]) -> list[dict]:
    if mapping.get("schemaVersion") != SOURCE_SCHEMA:
        raise InventoryError(f"source mapping schema must be {SOURCE_SCHEMA}")
    if mapping.get("iosRepository") != IOS_REPOSITORY:
        raise InventoryError(f"source mapping repository must be {IOS_REPOSITORY}")
    ios_base_revision = mapping.get("iosBaseRevision")
    if not isinstance(ios_base_revision, str):
        raise InventoryError("source mapping iosBaseRevision is missing")
    _validate_full_sha(ios_base_revision, "source mapping iosBaseRevision")

    matrix_row_ids = mapping.get("matrixRowIds")
    if not isinstance(matrix_row_ids, list) or any(not isinstance(item, str) for item in matrix_row_ids):
        raise InventoryError("source mapping matrixRowIds must be a string array")
    if len(matrix_row_ids) != len(set(matrix_row_ids)):
        raise InventoryError("source mapping matrixRowIds contains duplicates")
    if set(matrix_row_ids) != EXPECTED_MATRIX_ROW_IDS:
        raise InventoryError("source mapping must contain the exact authoritative 29 matrix rows")

    raw_records = mapping.get("records")
    if not isinstance(raw_records, list):
        raise InventoryError("source mapping records must be an array")
    if len(raw_records) != EXPECTED_PRODUCER_COUNT:
        raise InventoryError(
            f"source mapping must contain exactly {EXPECTED_PRODUCER_COUNT} producer records"
        )

    records: list[dict] = []
    variant_ids: set[str] = set()
    producer_identities: set[tuple[str, str, str]] = set()
    relational_lines: set[str] = set()
    operation_contracts: dict[str, tuple[str, str, str | None]] = {}

    for index, raw_record in enumerate(raw_records):
        if not isinstance(raw_record, dict):
            raise InventoryError(f"inventory record {index} must be an object")
        if set(raw_record) != set(RECORD_FIELDS):
            missing = sorted(set(RECORD_FIELDS) - set(raw_record))
            extra = sorted(set(raw_record) - set(RECORD_FIELDS))
            raise InventoryError(f"inventory record {index} fields differ; missing={missing} extra={extra}")
        record = {field: raw_record[field] for field in RECORD_FIELDS}
        operation_id = _validate_text_field(record, "operationId")
        method = _validate_text_field(record, "method")
        route_template = _validate_text_field(record, "routeTemplate")
        operation_variant_id = _validate_text_field(record, "operationVariantId")
        producer_kind = _validate_text_field(record, "producerKind")
        producer_symbol = _validate_text_field(record, "producerSymbol")
        producer_source_path = _validate_text_field(record, "producerSourcePath")
        stable_variant_suffix = _validate_text_field(record, "stableVariantSuffix")
        source_method_expression = _validate_text_field(record, "sourceMethodExpression")
        source_path_expression = _validate_text_field(record, "sourcePathExpression")
        matrix_row_id = record["matrixRowId"]

        if matrix_row_id is not None and not isinstance(matrix_row_id, str):
            raise InventoryError(f"{operation_id} matrixRowId must be a string or null")
        if matrix_row_id is not None and matrix_row_id not in EXPECTED_MATRIX_ROW_IDS:
            raise InventoryError(f"{operation_id} has an unknown matrix row: {matrix_row_id}")
        if not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*\.(?:get|post|patch|delete)", operation_id):
            raise InventoryError(f"inventory record has invalid operationId: {operation_id}")
        if method not in {"GET", "POST", "PATCH", "DELETE"}:
            raise InventoryError(f"{operation_id} has unsupported method: {method}")
        if not route_template.startswith("/book/"):
            raise InventoryError(f"{operation_id} has invalid route template: {route_template}")
        if producer_kind not in {"endpoint_factory", "direct_endpoint", "analytics_path"}:
            raise InventoryError(f"{operation_id} has invalid producer kind: {producer_kind}")
        if not _is_production_swift_path(producer_source_path):
            raise InventoryError(f"{operation_id} has invalid production source path: {producer_source_path}")
        if not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", stable_variant_suffix):
            raise InventoryError(f"{operation_id} has invalid stable variant suffix")
        if stable_variant_suffix != _stable_suffix(producer_symbol):
            raise InventoryError(
                f"{operation_id} stable variant suffix does not match producer symbol"
            )
        if operation_variant_id != f"{operation_id}:{stable_variant_suffix}":
            raise InventoryError(f"{operation_id} operation variant does not match its stable suffix")

        operation_contract = (method, route_template, matrix_row_id)
        previous_contract = operation_contracts.setdefault(operation_id, operation_contract)
        if previous_contract != operation_contract:
            raise InventoryError(f"{operation_id} producer records disagree on method, route, or matrix row")
        if operation_variant_id in variant_ids:
            raise InventoryError(f"duplicate operation variant: {operation_variant_id}")
        variant_ids.add(operation_variant_id)
        producer_identity = (producer_kind, producer_symbol, producer_source_path)
        if producer_identity in producer_identities:
            raise InventoryError(
                f"duplicate producer identity: {producer_symbol}@{producer_source_path}"
            )
        producer_identities.add(producer_identity)

        raw_source = sources.get(producer_source_path)
        if raw_source is None:
            raise InventoryError(f"producer source file is missing: {producer_source_path}")
        try:
            source = raw_source.decode("utf-8")
        except UnicodeDecodeError as error:
            raise InventoryError(f"producer source file is not UTF-8: {producer_source_path}") from error
        if producer_kind == "endpoint_factory":
            validation_region = _factory_region(source, producer_symbol, producer_source_path)
            endpoint_initializers = len(re.findall(r"\bEndpoint\s*\(", validation_region))
            if endpoint_initializers != 1:
                raise InventoryError(
                    f"{operation_id} factory must contain exactly one Endpoint initializer; "
                    f"found {endpoint_initializers}"
                )
        else:
            validation_region = source
        if validation_region.count(source_method_expression) != 1:
            raise InventoryError(
                f"{operation_id} source method expression must occur exactly once in {producer_symbol}"
            )
        if validation_region.count(source_path_expression) != 1:
            raise InventoryError(
                f"{operation_id} source path expression must occur exactly once in {producer_symbol}"
            )
        if method != _method_from_source_expression(source_method_expression, producer_kind):
            raise InventoryError(f"{operation_id} method does not match source expression")
        if route_template != _route_from_source_expression(source_path_expression, route_template):
            raise InventoryError(f"{operation_id} route does not match source path expression")

        line = canonical_record_line(record)
        if line in relational_lines:
            raise InventoryError(f"duplicate relational record: {line}")
        relational_lines.add(line)
        records.append(record)

    if len(operation_contracts) != EXPECTED_OPERATION_COUNT:
        raise InventoryError(
            f"source mapping must contain exactly {EXPECTED_OPERATION_COUNT} unique operations"
        )
    method_routes: dict[tuple[str, str], str] = {}
    for operation_id, (method, route_template, _) in operation_contracts.items():
        key = (method, route_template)
        previous_operation = method_routes.setdefault(key, operation_id)
        if previous_operation != operation_id:
            raise InventoryError(
                f"duplicate method and route mapping: {method} {route_template} "
                f"({previous_operation}, {operation_id})"
            )
    represented_matrix_rows = {
        matrix_row_id
        for _, _, matrix_row_id in operation_contracts.values()
        if matrix_row_id is not None
    }
    if represented_matrix_rows != EXPECTED_MATRIX_ROW_IDS:
        raise InventoryError("source mapping operations do not represent the exact 29 matrix rows")

    discovered = discover_producers(sources)
    if producer_identities != discovered:
        missing = sorted(producer_identities - discovered)
        unexpected = sorted(discovered - producer_identities)
        raise InventoryError(
            f"discovered producer set differs from mapping; missing={missing} unexpected={unexpected}"
        )
    return sorted(records, key=canonical_record_line)


def canonical_record_line(record: Mapping) -> str:
    values = []
    for field in RECORD_FIELDS:
        value = record[field]
        values.append("" if value is None else value)
    return "\t".join(values)


def canonical_record_bytes(records: Iterable[Mapping]) -> bytes:
    lines = sorted(canonical_record_line(record) for record in records)
    return ("\n".join(lines) + "\n").encode("utf-8")


def _sha256_sorted_lines(values: Iterable[str]) -> str:
    return _sha256(("\n".join(sorted(values)) + "\n").encode("utf-8"))


def _matrix_rows(records: Sequence[Mapping]) -> list[dict]:
    operation_rows: dict[str, str | None] = {}
    for record in records:
        operation_id = record["operationId"]
        matrix_row_id = record["matrixRowId"]
        existing = operation_rows.setdefault(operation_id, matrix_row_id)
        if existing != matrix_row_id:
            raise InventoryError(f"{operation_id} has inconsistent matrix membership")
    grouped: dict[str, list[str]] = defaultdict(list)
    for operation_id, matrix_row_id in operation_rows.items():
        if matrix_row_id is not None:
            grouped[matrix_row_id].append(operation_id)
    return [
        {"id": matrix_row_id, "operationIds": sorted(grouped[matrix_row_id])}
        for matrix_row_id in sorted(grouped)
    ]


def collect_revision_input_hashes(
    repo_root: Path, revision: str, relative_paths: Iterable[str]
) -> list[dict]:
    _validate_full_sha(revision, "iOS source revision")
    objects = _git_object_bytes_many(repo_root, revision, relative_paths)
    return [
        {"path": path, "sha256": _sha256(value)}
        for path, value in sorted(objects.items())
    ]


def revision_generation_input_paths(
    repo_root: Path,
    revision: str,
    mapping_relative_path: str = SOURCE_MAPPING_PATH,
) -> list[str]:
    """Return the complete Git-object closure read by committed generation."""
    return sorted(
        {
            mapping_relative_path,
            GENERATOR_PATH,
            *_list_revision_swift_paths(repo_root, revision),
        }
    )


def _worktree_input_hashes(repo_root: Path, relative_paths: Iterable[str]) -> list[dict]:
    inputs = []
    for path in sorted(set(relative_paths)):
        absolute_path = repo_root / path
        if not absolute_path.is_file():
            raise InventoryError(f"required worktree input is missing: {path}")
        inputs.append({"path": path, "sha256": _sha256(absolute_path.read_bytes())})
    return inputs


def _input_tree_sha256(inputs: Sequence[Mapping[str, str]]) -> str:
    lines = [f"{item['path']}\t{item['sha256']}" for item in inputs]
    return _sha256(("\n".join(sorted(lines)) + "\n").encode("utf-8"))


def assert_worktree_matches_revision(
    repo_root: Path, revision: str, relevant_paths: Iterable[str]
) -> None:
    _validate_full_sha(revision, "iOS source revision")
    paths = sorted(set(relevant_paths))
    untracked = _run_git(
        repo_root,
        ["ls-files", "--others", "--exclude-standard", "--", "Packages"],
    )
    untracked_sources = sorted(path for path in untracked.splitlines() if _is_production_swift_path(path))
    if untracked_sources:
        raise InventoryError(f"untracked production source may add a producer: {untracked_sources}")

    revision_source_paths = set(_list_revision_swift_paths(repo_root, revision))
    tracked_output = _run_git(repo_root, ["ls-files", "--cached", "--", "Packages"])
    current_tracked_source_paths = {
        path for path in tracked_output.splitlines() if _is_production_swift_path(path)
    }
    if current_tracked_source_paths != revision_source_paths:
        added = sorted(current_tracked_source_paths - revision_source_paths)
        removed = sorted(revision_source_paths - current_tracked_source_paths)
        raise InventoryError(
            f"production Swift path set differs from selected revision; "
            f"added={added} removed={removed}"
        )

    expected_objects = _git_object_bytes_many(repo_root, revision, paths)
    for path, expected in expected_objects.items():
        absolute_path = repo_root / path
        if not absolute_path.is_file() or absolute_path.read_bytes() != expected:
            raise InventoryError(f"relevant worktree input differs from selected revision: {path}")

    status = _run_git(
        repo_root,
        ["status", "--porcelain=v1", "--untracked-files=all", "--", *paths],
    )
    if status.strip():
        raise InventoryError(f"relevant worktree input is staged, modified, or untracked: {status.strip()}")


def _manifest(
    mapping: Mapping,
    records: list[dict],
    inputs: list[dict],
    source_revision: str | None,
    source_revision_phase: str,
) -> dict:
    operation_keys = {
        f"{record['operationId']}|{record['method']}|{record['routeTemplate']}"
        for record in records
    }
    variant_ids = [record["operationVariantId"] for record in records]
    producer_identities = [
        f"{record['producerKind']}|{record['producerSymbol']}|{record['producerSourcePath']}"
        for record in records
    ]
    matrix_rows = _matrix_rows(records)
    return {
        "schemaVersion": MANIFEST_SCHEMA,
        "iosRepository": IOS_REPOSITORY,
        "iosBaseRevision": mapping["iosBaseRevision"],
        "iosSourceRevision": source_revision,
        "iosSourceRevisionPhase": source_revision_phase,
        "canonicalization": (
            "UTF-8 records; fixed field order; TAB-separated fields; null matrix row is empty; "
            "lexicographically sorted lines joined with LF and a terminal LF"
        ),
        "operationKeyCount": len(operation_keys),
        "operationKeySha256": _sha256_sorted_lines(operation_keys),
        "producerVariantCount": len(variant_ids),
        "producerVariantIdSha256": _sha256_sorted_lines(variant_ids),
        "producerIdentitySha256": _sha256_sorted_lines(producer_identities),
        "matrixRowCount": len(matrix_rows),
        "relationalRecordCount": len(records),
        "relationalRecordSha256": _sha256(canonical_record_bytes(records)),
        "sourceInputTreeSha256": _input_tree_sha256(inputs),
        "sourceInputs": inputs,
        "records": records,
        "matrixRows": matrix_rows,
        "exactFactoryTestedProducerCount": 6,
        "bundleSuccessDecoderTestedOperationCount": 24,
        "backendRuntimeFactoryValidationPerformed": False,
        "evidence": [
            "The iOS repository owns the complete producer-to-operation-to-matrix mapping.",
            "Every producer record is checked against exact production Swift method and path expressions.",
            "Committed manifests hash generator, mapping, and every scanned production Swift input from the named Git object.",
            "The backend consumes these records but does not replace or regenerate iOS inventory authority.",
        ],
    }


def build_draft_manifest(repo_root: Path, mapping_path: Path) -> dict:
    mapping = _parse_json_object(mapping_path.read_bytes(), mapping_path.as_posix())
    sources = load_worktree_source_bytes(repo_root, mapping)
    records = validate_inventory_source(mapping, sources)
    input_paths = [
        SOURCE_MAPPING_PATH,
        GENERATOR_PATH,
        *sources.keys(),
    ]
    inputs = _worktree_input_hashes(repo_root, input_paths)
    return _manifest(mapping, records, inputs, None, "uncommitted_contract_branch")


def build_committed_manifest(
    repo_root: Path, mapping_relative_path: str, source_revision: str
) -> dict:
    _validate_full_sha(source_revision, "iOS source revision")
    _run_git(repo_root, ["cat-file", "-e", f"{source_revision}^{{commit}}"])
    mapping_bytes = _git_object_bytes(repo_root, source_revision, mapping_relative_path)
    mapping = _parse_json_object(mapping_bytes, f"{source_revision}:{mapping_relative_path}")
    revision_sources = _load_revision_source_bytes(repo_root, source_revision)
    records = validate_inventory_source(mapping, revision_sources)
    input_paths = revision_generation_input_paths(
        repo_root,
        source_revision,
        mapping_relative_path,
    )
    assert_worktree_matches_revision(repo_root, source_revision, input_paths)

    current_sources = load_worktree_source_bytes(repo_root, mapping)
    current_records = validate_inventory_source(mapping, current_sources)
    if canonical_record_bytes(current_records) != canonical_record_bytes(records):
        raise InventoryError("current worktree producer relationships differ from selected revision")

    inputs = collect_revision_input_hashes(repo_root, source_revision, input_paths)
    return _manifest(
        mapping,
        records,
        inputs,
        source_revision,
        "committed_contract_branch",
    )


def serialize_manifest(manifest: Mapping) -> str:
    return json.dumps(manifest, ensure_ascii=False, indent=2) + "\n"


def _default_repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, default=_default_repo_root())
    parser.add_argument("--mapping", default=SOURCE_MAPPING_PATH)
    source_group = parser.add_mutually_exclusive_group(required=True)
    source_group.add_argument("--source-revision")
    source_group.add_argument("--worktree-draft", action="store_true")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args(argv)

    repo_root = args.repo_root.resolve()
    mapping_relative_path = PurePosixPath(args.mapping).as_posix()
    mapping_path = repo_root / mapping_relative_path
    if args.worktree_draft:
        manifest = build_draft_manifest(repo_root, mapping_path)
    else:
        manifest = build_committed_manifest(repo_root, mapping_relative_path, args.source_revision)
    serialized = serialize_manifest(manifest)

    if args.check:
        if not args.output.is_file():
            raise InventoryError(f"inventory output is missing: {args.output}")
        if args.output.read_text(encoding="utf-8") != serialized:
            raise InventoryError(f"inventory output has drifted: {args.output}")
        print(
            f"iOS native inventory is current "
            f"({manifest['operationKeyCount']} operations / "
            f"{manifest['producerVariantCount']} producers / "
            f"{manifest['matrixRowCount']} matrix rows)"
        )
        return 0

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(serialized, encoding="utf-8")
    print(
        f"wrote {args.output} "
        f"({manifest['operationKeyCount']} operations / "
        f"{manifest['producerVariantCount']} producers / "
        f"{manifest['matrixRowCount']} matrix rows)"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except InventoryError as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1) from error
