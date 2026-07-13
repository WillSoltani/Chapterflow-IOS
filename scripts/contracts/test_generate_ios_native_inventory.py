#!/usr/bin/env python3
"""Regression canaries for the iOS-owned native contract inventory."""

from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

import generate_ios_native_inventory as inventory


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parents[1]
SOURCE_MAPPING = REPO_ROOT / "contracts/native-ios/v1/ios-native-contract-inventory-source.json"


class IOSNativeInventoryCanaries(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.mapping = json.loads(SOURCE_MAPPING.read_text(encoding="utf-8"))
        cls.sources = inventory.load_worktree_source_bytes(REPO_ROOT, cls.mapping)

    def assert_mapping_rejected(self, mutate, message_pattern: str) -> None:
        candidate = copy.deepcopy(self.mapping)
        mutate(candidate)
        with self.assertRaisesRegex(inventory.InventoryError, message_pattern):
            inventory.validate_inventory_source(candidate, self.sources)

    def assert_sources_rejected(self, mutate, message_pattern: str) -> None:
        candidate = copy.deepcopy(self.sources)
        mutate(candidate)
        with self.assertRaisesRegex(inventory.InventoryError, message_pattern):
            inventory.validate_inventory_source(self.mapping, candidate)

    def test_current_source_mapping_is_complete_and_deterministic(self) -> None:
        first = inventory.build_draft_manifest(REPO_ROOT, SOURCE_MAPPING)
        second = inventory.build_draft_manifest(REPO_ROOT, SOURCE_MAPPING)

        self.assertEqual(inventory.serialize_manifest(first), inventory.serialize_manifest(second))
        self.assertEqual(first["operationKeyCount"], 83)
        self.assertEqual(first["producerVariantCount"], 93)
        self.assertEqual(first["matrixRowCount"], 29)
        self.assertEqual(first["relationalRecordCount"], 93)
        self.assertEqual(len(first["records"]), 93)
        self.assertEqual(len(first["matrixRows"]), 29)
        self.assertEqual(
            {item["path"] for item in first["sourceInputs"]},
            {
                inventory.SOURCE_MAPPING_PATH,
                inventory.GENERATOR_PATH,
                *self.sources.keys(),
            },
        )

        lines = inventory.canonical_record_bytes(first["records"])
        self.assertEqual(first["relationalRecordSha256"], hashlib.sha256(lines).hexdigest())

    def test_duplicate_record_is_rejected(self) -> None:
        self.assert_mapping_rejected(
            lambda candidate: candidate["records"].__setitem__(
                -1, copy.deepcopy(candidate["records"][0])
            ),
            "duplicate (operation variant|producer identity|relational record)",
        )

    def test_count_preserving_producer_reassignment_is_rejected(self) -> None:
        relation_fields = (
            "producerKind",
            "producerSymbol",
            "producerSourcePath",
            "stableVariantSuffix",
            "sourceMethodExpression",
            "sourcePathExpression",
        )

        def mutate(candidate) -> None:
            track = next(record for record in candidate["records"] if record["operationId"] == "analytics-track.post")
            beacon = next(record for record in candidate["records"] if record["operationId"] == "analytics-beacon.post")
            before = {field: track[field] for field in relation_fields}
            for field in relation_fields:
                track[field] = beacon[field]
                beacon[field] = before[field]
            track["operationVariantId"] = f"{track['operationId']}:{track['stableVariantSuffix']}"
            beacon["operationVariantId"] = f"{beacon['operationId']}:{beacon['stableVariantSuffix']}"

        self.assert_mapping_rejected(mutate, "route.*source path")

    def test_count_preserving_analytics_symbol_reassignment_is_rejected(self) -> None:
        relation_fields = ("producerSymbol", "stableVariantSuffix")

        def mutate(candidate) -> None:
            track = next(record for record in candidate["records"] if record["operationId"] == "analytics-track.post")
            beacon = next(record for record in candidate["records"] if record["operationId"] == "analytics-beacon.post")
            before = {field: track[field] for field in relation_fields}
            for field in relation_fields:
                track[field] = beacon[field]
                beacon[field] = before[field]
            track["operationVariantId"] = f"{track['operationId']}:{track['stableVariantSuffix']}"
            beacon["operationVariantId"] = f"{beacon['operationId']}:{beacon['stableVariantSuffix']}"

        self.assert_mapping_rejected(mutate, "analytics producer symbol.*source path expression")

    def test_stale_comment_cannot_hide_endpoint_method_drift(self) -> None:
        path = "Packages/Networking/Sources/Networking/Endpoint.swift"

        def mutate(candidate) -> None:
            source = candidate[path].decode("utf-8")
            old = 'Endpoint(method: .get, path: "/book/me/commitments/\\(id)", requiresAuth: true)'
            new = (
                'Endpoint(method: .post, path: "/book/me/commitments/\\(id)", requiresAuth: true) '
                '// method: .get'
            )
            self.assertEqual(source.count(old), 1)
            candidate[path] = source.replace(old, new).encode("utf-8")

        self.assert_sources_rejected(mutate, "Endpoint method argument")

    def test_stale_comment_cannot_hide_endpoint_path_drift(self) -> None:
        path = "Packages/Networking/Sources/Networking/Endpoint.swift"

        def mutate(candidate) -> None:
            source = candidate[path].decode("utf-8")
            old = 'Endpoint(method: .get, path: "/book/me/commitments/\\(id)", requiresAuth: true)'
            new = (
                'Endpoint(method: .get, path: "/book/me/commitments/wrong", requiresAuth: true) '
                '// "/book/me/commitments/\\(id)"'
            )
            self.assertEqual(source.count(old), 1)
            candidate[path] = source.replace(old, new).encode("utf-8")

        self.assert_sources_rejected(mutate, "Endpoint path argument")

    def test_stale_comment_cannot_hide_analytics_path_drift(self) -> None:
        path = inventory.ANALYTICS_SOURCE_PATH

        def mutate(candidate) -> None:
            source = candidate[path].decode("utf-8")
            old = 'static let track = "/book/me/analytics/track"'
            new = (
                'static let track = "/book/me/analytics/wrong" '
                '// "/book/me/analytics/track"'
            )
            self.assertEqual(source.count(old), 1)
            candidate[path] = source.replace(old, new).encode("utf-8")

        self.assert_sources_rejected(mutate, "analytics producer symbol.*source path expression")

    def test_string_literal_cannot_hide_analytics_method_drift(self) -> None:
        path = inventory.ANALYTICS_SOURCE_PATH

        def mutate(candidate) -> None:
            source = candidate[path].decode("utf-8")
            old = 'request.httpMethod = "POST"'
            new = (
                'request.httpMethod = "GET"\n'
                '        _ = #"request.httpMethod = "POST""#'
            )
            self.assertEqual(source.count(old), 1)
            candidate[path] = source.replace(old, new).encode("utf-8")

        self.assert_sources_rejected(mutate, "live analytics method assignment")

    def test_dead_closure_cannot_hide_analytics_method_drift(self) -> None:
        path = inventory.ANALYTICS_SOURCE_PATH

        def mutate(candidate) -> None:
            source = candidate[path].decode("utf-8")
            old = 'request.httpMethod = "POST"'
            new = (
                "let inventoryWitness = {\n"
                '            request.httpMethod = "POST"\n'
                "        }\n"
                "        _ = inventoryWitness"
            )
            self.assertEqual(source.count(old), 1)
            candidate[path] = source.replace(old, new).encode("utf-8")

        self.assert_sources_rejected(mutate, "not in its expected live scope")

    def test_analytics_path_declaration_must_feed_its_transport_calls(self) -> None:
        path = inventory.ANALYTICS_SOURCE_PATH

        def mutate(candidate) -> None:
            source = candidate[path].decode("utf-8")
            old = "transport.send(path: Path.track"
            self.assertEqual(source.count(old), 2)
            candidate[path] = source.replace(
                old,
                "transport.send(path: Path.beacon",
            ).encode("utf-8")

        self.assert_sources_rejected(mutate, "Path.track must feed all flush transport sends")

    def test_analytics_method_witness_must_be_on_the_sent_request(self) -> None:
        path = inventory.ANALYTICS_SOURCE_PATH

        def mutate(candidate) -> None:
            source = candidate[path].decode("utf-8")
            old = "_ = try await session.data(for: request)"
            new = (
                "var actualRequest = request\n"
                '        actualRequest.httpMethod = "GET"\n'
                "        _ = try await session.data(for: actualRequest)"
            )
            self.assertEqual(source.count(old), 1)
            candidate[path] = source.replace(old, new).encode("utf-8")

        self.assert_sources_rejected(mutate, "analytics URLSession send")

    def test_analytics_path_parameter_cannot_be_shadowed(self) -> None:
        path = inventory.ANALYTICS_SOURCE_PATH

        def mutate(candidate) -> None:
            source = candidate[path].decode("utf-8")
            old = "let url = baseURL.appending(path: path)"
            new = (
                'let path = "/book/wrong"\n'
                "        let url = baseURL.appending(path: path)"
            )
            self.assertEqual(source.count(old), 1)
            candidate[path] = source.replace(old, new).encode("utf-8")

        self.assert_sources_rejected(mutate, "shadowed or rebound request dataflow")

    def test_analytics_path_type_cannot_be_shadowed(self) -> None:
        path = inventory.ANALYTICS_SOURCE_PATH

        def mutate(candidate) -> None:
            source = candidate[path].decode("utf-8")
            old = "public func flush() async {\n        if let diskQueue"
            new = (
                "public func flush() async {\n"
                '        let Path = (track: "/book/wrong", beacon: "/book/wrong")\n'
                "        if let diskQueue"
            )
            self.assertEqual(source.count(old), 1)
            candidate[path] = source.replace(old, new).encode("utf-8")

        self.assert_sources_rejected(mutate, "must not shadow Path")

    def test_analytics_request_cannot_be_reassigned_after_method_binding(self) -> None:
        path = inventory.ANALYTICS_SOURCE_PATH

        def mutate(candidate) -> None:
            source = candidate[path].decode("utf-8")
            old = 'request.httpMethod = "POST"'
            new = (
                'request.httpMethod = "POST"\n'
                "        request = URLRequest(url: URL(string: \"https://example.invalid\")!)"
            )
            self.assertEqual(source.count(old), 1)
            candidate[path] = source.replace(old, new).encode("utf-8")

        self.assert_sources_rejected(mutate, "must not reassign request")

    def test_default_closure_cannot_replace_endpoint_factory_body(self) -> None:
        path = "Packages/Networking/Sources/Networking/Endpoint.swift"

        def mutate(candidate) -> None:
            source = candidate[path].decode("utf-8")
            old = (
                "public static func getBooks() -> Endpoint {\n"
                '        Endpoint(method: .get, path: "/book/books", requiresAuth: false)\n'
                "    }"
            )
            new = (
                "public static func getBooks(\n"
                "        _ witness: @escaping () -> Endpoint = {\n"
                '            Endpoint(method: .get, path: "/book/books", requiresAuth: false)\n'
                "        }\n"
                "    ) -> Endpoint {\n"
                '        Endpoint(method: .post, path: "/book/books/wrong", requiresAuth: false)\n'
                "    }"
            )
            self.assertEqual(source.count(old), 1)
            candidate[path] = source.replace(old, new).encode("utf-8")

        self.assert_sources_rejected(
            mutate,
            "factory parameter list may not shadow Endpoint|Endpoint method argument",
        )

    def test_dead_body_closure_cannot_replace_returned_endpoint_factory(self) -> None:
        path = "Packages/Networking/Sources/Networking/Endpoint.swift"

        def mutate(candidate) -> None:
            source = candidate[path].decode("utf-8")
            old = (
                "public static func getBooks() -> Endpoint {\n"
                '        Endpoint(method: .get, path: "/book/books", requiresAuth: false)\n'
                "    }"
            )
            new = (
                "public static func getBooks() -> Endpoint {\n"
                "        let inventoryWitness = {\n"
                '            Endpoint(method: .get, path: "/book/books", requiresAuth: false)\n'
                "        }\n"
                "        _ = inventoryWitness\n"
                "        return getSearchIndex()\n"
                "    }"
            )
            self.assertEqual(source.count(old), 1)
            candidate[path] = source.replace(old, new).encode("utf-8")

        self.assert_sources_rejected(mutate, "top-level factory expression")

    def test_dead_closure_cannot_stand_in_for_direct_endpoint_callsite(self) -> None:
        path = (
            "Packages/EngagementFeature/Sources/EngagementFeature/Scenarios/"
            "ScenarioRepository.swift"
        )

        def mutate(candidate) -> None:
            source = candidate[path].decode("utf-8")
            old = (
                "let endpoint = Endpoint(\n"
                "                method: .post,\n"
                '                path: "/book/me/books/\\(ticket.bookId)/chapters/'
                '\\(ticket.chapterNumber)/scenarios",\n'
                "                httpBody: bodyData\n"
                "            )"
            )
            new = (
                "let inventoryWitness: (PendingScenarioUpload, Data) -> Endpoint = "
                "{ ticket, bodyData in\n"
                "                Endpoint(\n"
                "                    method: .post,\n"
                '                    path: "/book/me/books/\\(ticket.bookId)/chapters/'
                '\\(ticket.chapterNumber)/scenarios",\n'
                "                    httpBody: bodyData\n"
                "                )\n"
                "            }\n"
                "            _ = inventoryWitness\n"
                "            let endpoint = Endpoints.getBooks()"
            )
            self.assertEqual(source.count(old), 1)
            candidate[path] = source.replace(old, new).encode("utf-8")

        self.assert_sources_rejected(mutate, "bind exactly one direct Endpoint")

    def test_direct_endpoint_shadow_before_send_is_rejected(self) -> None:
        path = (
            "Packages/EngagementFeature/Sources/EngagementFeature/Scenarios/"
            "ScenarioRepository.swift"
        )

        def mutate(candidate) -> None:
            source = candidate[path].decode("utf-8")
            old = "do {\n                let resp: ScenarioResponse = try await apiClient.send(endpoint)"
            new = (
                "do {\n"
                "                let endpoint = Endpoints.getBooks()\n"
                "                let resp: ScenarioResponse = try await apiClient.send(endpoint)"
            )
            self.assertEqual(source.count(old), 1)
            candidate[path] = source.replace(old, new).encode("utf-8")

        self.assert_sources_rejected(mutate, "shadow or rebind endpoint")

    def test_direct_endpoint_wrong_transport_is_rejected(self) -> None:
        path = (
            "Packages/EngagementFeature/Sources/EngagementFeature/Scenarios/"
            "ScenarioRepository.swift"
        )

        def mutate(candidate) -> None:
            source = candidate[path].decode("utf-8")
            old = (
                "            do {\n"
                "                let resp: ScenarioResponse = try await apiClient.send(endpoint)"
            )
            new = (
                "            do {\n"
                "                let otherClient = apiClient\n"
                "                let resp: ScenarioResponse = try await otherClient.send(endpoint)"
            )
            self.assertEqual(source.count(old), 1)
            candidate[path] = source.replace(old, new).encode("utf-8")

        self.assert_sources_rejected(mutate, "send the bound endpoint through apiClient")

    def test_dead_closure_cannot_replace_direct_endpoint_send(self) -> None:
        path = (
            "Packages/PaywallFeature/Sources/PaywallFeature/"
            "LiveEntitlementRepository.swift"
        )

        def mutate(candidate) -> None:
            source = candidate[path].decode("utf-8")
            old = "return try await client.send(endpoint)"
            new = (
                "let inventoryWitness = { [client] in\n"
                "            try await client.send(endpoint)\n"
                "        }\n"
                "        _ = inventoryWitness\n"
                "        return try await getEntitlements()"
            )
            self.assertEqual(source.count(old), 1)
            candidate[path] = source.replace(old, new).encode("utf-8")

        self.assert_sources_rejected(mutate, "transport send is not in its expected live scope")

    def test_matrix_row_move_changes_the_canonical_relation(self) -> None:
        baseline = inventory.validate_inventory_source(self.mapping, self.sources)
        candidate = copy.deepcopy(self.mapping)
        record = next(
            item for item in candidate["records"] if item["operationId"] == "commitment.get"
        )
        record["matrixRowId"] = "catalog"
        moved = inventory.validate_inventory_source(candidate, self.sources)

        self.assertNotEqual(
            hashlib.sha256(inventory.canonical_record_bytes(baseline)).hexdigest(),
            hashlib.sha256(inventory.canonical_record_bytes(moved)).hexdigest(),
        )
        baseline_rows = inventory._matrix_rows(baseline)
        moved_rows = inventory._matrix_rows(moved)
        self.assertNotEqual(baseline_rows, moved_rows)

    def test_method_mutation_is_rejected(self) -> None:
        def mutate(candidate) -> None:
            record = next(record for record in candidate["records"] if record["operationId"] == "commitment.get")
            record["method"] = "POST"

        self.assert_mapping_rejected(mutate, "method.*source expression")

    def test_route_mutation_is_rejected(self) -> None:
        def mutate(candidate) -> None:
            record = next(record for record in candidate["records"] if record["operationId"] == "commitment.get")
            record["routeTemplate"] = "/book/me/commitments/{otherId}/history"

        self.assert_mapping_rejected(mutate, "route.*source path")

    def test_symbol_mutation_is_rejected(self) -> None:
        def mutate(candidate) -> None:
            record = next(record for record in candidate["records"] if record["operationId"] == "commitment.get")
            record["producerSymbol"] = "getOtherCommitment"
            record["stableVariantSuffix"] = "getothercommitment"
            record["operationVariantId"] = "commitment.get:getothercommitment"

        self.assert_mapping_rejected(mutate, "discovered producer set|producer symbol")

    def test_source_path_mutation_is_rejected(self) -> None:
        def mutate(candidate) -> None:
            record = next(record for record in candidate["records"] if record["operationId"] == "commitment.get")
            record["producerSourcePath"] = "Packages/Networking/Sources/Networking/Endpoint+Missing.swift"

        self.assert_mapping_rejected(mutate, "source file is missing|discovered producer set")

    def test_source_method_expression_mutation_is_rejected(self) -> None:
        def mutate(candidate) -> None:
            record = next(record for record in candidate["records"] if record["operationId"] == "commitment.get")
            record["sourceMethodExpression"] = "method: .post"

        self.assert_mapping_rejected(mutate, "source method expression")

    def test_source_path_expression_mutation_is_rejected(self) -> None:
        def mutate(candidate) -> None:
            record = next(record for record in candidate["records"] if record["operationId"] == "commitment.get")
            record["sourcePathExpression"] = '"/book/me/commitments/\\(otherId)/history"'

        self.assert_mapping_rejected(mutate, "source path expression|route.*source path")


class IOSNativeInventoryGitObjectCanaries(unittest.TestCase):
    def run_git(self, root: Path, *args: str) -> str:
        result = subprocess.run(
            ["git", *args],
            cwd=root,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        return result.stdout.strip()

    def make_repo(self) -> tuple[tempfile.TemporaryDirectory[str], Path, str, list[str]]:
        temporary = tempfile.TemporaryDirectory(prefix="chapterflow-ios-inventory-canary.")
        root = Path(temporary.name)
        paths = [
            "scripts/contracts/generate_ios_native_inventory.py",
            "contracts/native-ios/v1/ios-native-contract-inventory-source.json",
            "Packages/Networking/Sources/Networking/Endpoint.swift",
            "Packages/ReaderFeature/Sources/ReaderFeature/ReaderModel.swift",
        ]
        for path in paths:
            target = root / path
            target.parent.mkdir(parents=True, exist_ok=True)
            if path.endswith(".py"):
                target.write_bytes((SCRIPT_DIR / "generate_ios_native_inventory.py").read_bytes())
            elif path.endswith(".json"):
                target.write_text('{"schemaVersion":"fixture"}\n', encoding="utf-8")
            else:
                if path.endswith("Endpoint.swift"):
                    target.write_text(
                        'public static func getBooks() -> Endpoint {\n'
                        '    Endpoint(method: .get, path: "/book/books")\n'
                        '}\n',
                        encoding="utf-8",
                    )
                else:
                    target.write_text("struct ReaderModel {}\n", encoding="utf-8")
        self.run_git(root, "init", "-q")
        self.run_git(root, "config", "user.name", "Contract Canary")
        self.run_git(root, "config", "user.email", "contract-canary@example.invalid")
        self.run_git(root, "add", ".")
        self.run_git(root, "commit", "-q", "-m", "fixture")
        revision = self.run_git(root, "rev-parse", "HEAD")
        return temporary, root, revision, paths

    def test_revision_inputs_are_hashed_from_git_objects(self) -> None:
        temporary, root, revision, paths = self.make_repo()
        self.addCleanup(temporary.cleanup)

        inputs = inventory.collect_revision_input_hashes(root, revision, paths)
        for item in inputs:
            git_bytes = subprocess.run(
                ["git", "show", f"{revision}:{item['path']}"],
                cwd=root,
                check=True,
                stdout=subprocess.PIPE,
            ).stdout
            self.assertEqual(item["sha256"], hashlib.sha256(git_bytes).hexdigest())

    def test_generation_inputs_include_nonmapped_scanned_swift_source(self) -> None:
        temporary, root, revision, _ = self.make_repo()
        self.addCleanup(temporary.cleanup)

        paths = inventory.revision_generation_input_paths(
            root,
            revision,
            "contracts/native-ios/v1/ios-native-contract-inventory-source.json",
        )
        self.assertIn(
            "Packages/ReaderFeature/Sources/ReaderFeature/ReaderModel.swift",
            paths,
        )
        inputs = inventory.collect_revision_input_hashes(root, revision, paths)
        self.assertIn(
            "Packages/ReaderFeature/Sources/ReaderFeature/ReaderModel.swift",
            {item["path"] for item in inputs},
        )

    def test_dirty_nonmapped_scanned_source_is_rejected(self) -> None:
        temporary, root, revision, paths = self.make_repo()
        self.addCleanup(temporary.cleanup)

        nonmapped = "Packages/ReaderFeature/Sources/ReaderFeature/ReaderModel.swift"
        (root / nonmapped).write_text("struct ReaderModel { let dirty = true }\n", encoding="utf-8")
        with self.assertRaisesRegex(inventory.InventoryError, "relevant worktree input"):
            inventory.assert_worktree_matches_revision(root, revision, paths)

    def test_dirty_relevant_source_is_rejected(self) -> None:
        temporary, root, revision, paths = self.make_repo()
        self.addCleanup(temporary.cleanup)

        inventory.assert_worktree_matches_revision(root, revision, paths)
        (root / paths[-1]).write_text("// dirty route\n", encoding="utf-8")
        with self.assertRaisesRegex(inventory.InventoryError, "relevant worktree input"):
            inventory.assert_worktree_matches_revision(root, revision, paths)

    def test_staged_relevant_source_is_rejected(self) -> None:
        temporary, root, revision, paths = self.make_repo()
        self.addCleanup(temporary.cleanup)

        (root / paths[-1]).write_text("// staged route\n", encoding="utf-8")
        self.run_git(root, "add", paths[-1])
        with self.assertRaisesRegex(inventory.InventoryError, "relevant worktree input"):
            inventory.assert_worktree_matches_revision(root, revision, paths)

    def test_untracked_producer_source_is_rejected(self) -> None:
        temporary, root, revision, paths = self.make_repo()
        self.addCleanup(temporary.cleanup)

        new_source = root / "Packages/Networking/Sources/Networking/Endpoint+New.swift"
        new_source.write_text(
            'static func surprise() -> Endpoint { Endpoint(method: .get, path: "/book/surprise") }\n',
            encoding="utf-8",
        )
        with self.assertRaisesRegex(inventory.InventoryError, "untracked production source"):
            inventory.assert_worktree_matches_revision(root, revision, paths)

    def test_tracked_production_source_addition_is_rejected_as_path_set_drift(self) -> None:
        temporary, root, revision, paths = self.make_repo()
        self.addCleanup(temporary.cleanup)

        added = root / "Packages/ReaderFeature/Sources/ReaderFeature/Added.swift"
        added.write_text("struct Added {}\n", encoding="utf-8")
        self.run_git(root, "add", added.relative_to(root).as_posix())
        self.run_git(root, "commit", "-q", "-m", "add scanned source")
        with self.assertRaisesRegex(inventory.InventoryError, "production Swift path set"):
            inventory.assert_worktree_matches_revision(root, revision, paths)

    def test_tracked_production_source_removal_is_rejected_as_path_set_drift(self) -> None:
        temporary, root, revision, paths = self.make_repo()
        self.addCleanup(temporary.cleanup)

        removed = root / "Packages/ReaderFeature/Sources/ReaderFeature/ReaderModel.swift"
        removed.unlink()
        self.run_git(root, "add", "-u", removed.relative_to(root).as_posix())
        self.run_git(root, "commit", "-q", "-m", "remove scanned source")
        with self.assertRaisesRegex(inventory.InventoryError, "production Swift path set"):
            inventory.assert_worktree_matches_revision(root, revision, paths)


if __name__ == "__main__":
    unittest.main()
