#!/usr/bin/env python3
"""Canaries for historical provenance and incremental iOS contract drift."""

from __future__ import annotations

import copy
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

import generate_ios_native_inventory as inventory
import verify_ios_incremental_contract_drift as drift


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parents[1]
MANIFEST_PATH = (
    REPO_ROOT / "contracts/native-ios/v1/ios-source-inventory-manifest.json"
)
MAPPING_PATH = (
    REPO_ROOT / "contracts/native-ios/v1/ios-native-contract-inventory-source.json"
)
GENERATOR_PATH = REPO_ROOT / "scripts/contracts/generate_ios_native_inventory.py"
POLICY_PATH = REPO_ROOT / "contracts/native-ios/v1/incremental-drift-policy.json"
VERIFIER_PATH = REPO_ROOT / "scripts/contracts/verify_ios_incremental_contract_drift.py"


class IOSIncrementalContractDriftCanaries(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
        cls.mapping_bytes = MAPPING_PATH.read_bytes()
        cls.generator_bytes = GENERATOR_PATH.read_bytes()
        cls.mapping = json.loads(cls.mapping_bytes.decode("utf-8"))
        cls.sources = drift._load_current_worktree_sources(REPO_ROOT)
        cls.historical_sources = inventory._load_revision_source_bytes(
            REPO_ROOT,
            cls.manifest["iosSourceRevision"],
        )

    def assert_sources_accepted(self, mutate) -> None:
        candidate = copy.deepcopy(self.sources)
        mutate(candidate)
        drift.compare_worktree_semantics(
            manifest=self.manifest,
            mapping_bytes=self.mapping_bytes,
            generator_bytes=self.generator_bytes,
            current_sources=candidate,
            historical_sources=self.historical_sources,
        )

    def assert_sources_rejected(self, mutate, message_pattern: str) -> None:
        candidate = copy.deepcopy(self.sources)
        mutate(candidate)
        with self.assertRaisesRegex(drift.DriftError, message_pattern):
            drift.compare_worktree_semantics(
                manifest=self.manifest,
                mapping_bytes=self.mapping_bytes,
                generator_bytes=self.generator_bytes,
                current_sources=candidate,
                historical_sources=self.historical_sources,
            )

    @staticmethod
    def replace_once(candidate: dict[str, bytes], path: str, old: str, new: str) -> None:
        source = candidate[path].decode("utf-8")
        if source.count(old) != 1:
            raise AssertionError(f"expected exactly one canary target in {path}: {old}")
        candidate[path] = source.replace(old, new, 1).encode("utf-8")

    def test_unrelated_swiftui_view_body_change_passes(self) -> None:
        path = (
            "Packages/LibraryFeature/Sources/LibraryFeature/Views/Components/"
            "BookCoverView.swift"
        )

        def mutate(candidate) -> None:
            self.replace_once(
                candidate,
                path,
                "        .accessibilityHidden(true)\n",
                "        .accessibilityHidden(true)\n        .opacity(1)\n",
            )

        self.assert_sources_accepted(mutate)

    def test_every_production_swift_root_is_scanned(self) -> None:
        expected = {
            "Packages/Networking/Sources/Networking/Endpoint.swift",
            "ChapterFlow/ChapterFlowApp.swift",
            "ChapterflowWidgets/ChapterflowWidgetsBundle.swift",
            "NotificationService/NotificationServiceExtension.swift",
            "NotificationContent/NotificationViewController.swift",
            "ShareExtension/ShareView.swift",
            "ActionExtension/ActionView.swift",
            "SharedExtensionKit/ExtensionOutboxWriter.swift",
        }
        self.assertTrue(expected.issubset(self.sources))
        self.assertFalse(
            drift._is_current_production_swift_path(
                "ChapterFlowUITests/ChapterFlowUITests.swift"
            )
        )

    def test_contract_workflow_is_narrow_after_fast_semantic_split(self) -> None:
        workflow = (
            REPO_ROOT / ".github/workflows/contract-drift.yml"
        ).read_text(encoding="utf-8")
        required_paths = {
            "contracts/native-ios/**",
            "scripts/contracts/**",
            "scripts/refresh-fixtures.sh",
            "scripts/verify-backend-contract-provenance.sh",
            "scripts/test-backend-contract-provenance.sh",
            ".github/workflows/contract-drift.yml",
            "Packages/Models/Tests/**/*Contract*.swift",
            "Packages/Networking/Tests/**/*Contract*.swift",
            "Packages/SocialFeature/Tests/**/*Contract*.swift",
        }
        for path in required_paths:
            self.assertIn(f'      - "{path}"', workflow)

        broad_paths = {
            "Packages/Models/**",
            "Packages/Networking/**",
            "Packages/SocialFeature/**",
            "Packages/**/Sources/**/*.swift",
            *(f"{root}/**/*.swift" for root in drift.CURRENT_PRODUCTION_SWIFT_ROOTS[1:]),
        }
        for path in broad_paths:
            self.assertNotIn(f'      - "{path}"', workflow)
        for package in ("Models", "Networking", "SocialFeature"):
            contract_tests = list(
                (REPO_ROOT / "Packages" / package / "Tests").rglob("*Contract*.swift")
            )
            self.assertTrue(contract_tests, f"no contract tests found for {package}")
        self.assertIn("  schedule:", workflow)
        self.assertIn("  workflow_dispatch:", workflow)

    def test_design_system_implementation_change_passes(self) -> None:
        path = "Packages/DesignSystem/Sources/DesignSystem/Spacing+CF.swift"

        def mutate(candidate) -> None:
            self.replace_once(
                candidate,
                path,
                "static let cfSpacing2:  CGFloat = 2",
                "static let cfSpacing2:  CGFloat = 2.0",
            )

        self.assert_sources_accepted(mutate)

    def test_model_implementation_change_passes(self) -> None:
        path = "Packages/Models/Sources/Models/Common/ToneKey.swift"

        def mutate(candidate) -> None:
            self.replace_once(
                candidate,
                path,
                "case .unknown(let s): return s",
                "case .unknown(let value): return value",
            )

        self.assert_sources_accepted(mutate)

    def test_producer_documentation_change_passes(self) -> None:
        path = "Packages/Networking/Sources/Networking/Endpoint.swift"

        def mutate(candidate) -> None:
            self.replace_once(
                candidate,
                path,
                "    public static func getBooks() -> Endpoint {",
                (
                    "    /// See <Documentation> for editorial notes only.\n"
                    "    public static func getBooks() -> Endpoint {"
                ),
            )

        self.assert_sources_accepted(mutate)

    def test_non_endpoint_static_helper_beside_producer_passes(self) -> None:
        path = "Packages/Networking/Sources/Networking/Endpoint+Config.swift"

        def mutate(candidate) -> None:
            self.replace_once(
                candidate,
                path,
                "    }\n}\n\n// MARK: - Response model",
                (
                    "    }\n\n"
                    "    static func contractDebugLabel() -> String { \"config\" }\n"
                    "}\n\n// MARK: - Response model"
                ),
            )

        self.assert_sources_accepted(mutate)

    def test_same_named_non_request_type_in_other_module_passes(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/AppleVerifyBody.swift"
            ] = (
                "private struct AppleVerifyBody: Encodable {\n"
                "    let localOnly: String\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_accepted(mutate)

    def test_file_private_same_named_request_type_in_same_module_passes(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/Networking/Sources/Networking/DebugNotebookRequest.swift"
            ] = (
                "private struct NotebookEntryRequest: Encodable {\n"
                "    let debugOnly: String\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_accepted(mutate)

    def test_unimported_public_endpoint_alias_does_not_leak_modules(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/Networking/Sources/Networking/PublicAliasCanary.swift"
            ] = b"public typealias Foreign = Endpoint\n"
            candidate[
                "Packages/Models/Sources/Models/ForeignType.swift"
            ] = b"struct Foreign {}\n"
            candidate[
                "Packages/Models/Sources/Models/ForeignUse.swift"
            ] = b"func debugForeign() -> Foreign { Foreign() }\n"

        self.assert_sources_accepted(mutate)

    def test_file_private_closure_alias_does_not_leak_sibling_file(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/PrivateFactory.swift"
            ] = (
                "import Networking\n"
                "private typealias F = @Sendable () -> Endpoint\n"
            ).encode("utf-8")
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/PrivateString.swift"
            ] = (
                "private typealias F = String\n"
                'struct DebugHolder { static let debug: F = "not a request" }\n'
            ).encode("utf-8")

        self.assert_sources_accepted(mutate)

    def test_computed_request_property_does_not_change_wire_identity(self) -> None:
        path = "Packages/Networking/Sources/Networking/NotebookEntryRequest.swift"

        def mutate(candidate) -> None:
            self.replace_once(
                candidate,
                path,
                "    public let anchor: Anchor?\n\n    public init(\n",
                (
                    "    public let anchor: Anchor?\n\n"
                    "    public var contractDebugLabel: String { bookId }\n\n"
                    "    public init(\n"
                ),
            )

        self.assert_sources_accepted(mutate)

    def test_inferred_stored_request_property_changes_wire_identity(self) -> None:
        path = "Packages/Networking/Sources/Networking/NotebookEntryRequest.swift"

        def mutate(candidate) -> None:
            self.replace_once(
                candidate,
                path,
                "    public let anchor: Anchor?\n\n    public init(\n",
                (
                    "    public let anchor: Anchor?\n"
                    '    public let unexpectedWireKey = "surprise"\n\n'
                    "    public init(\n"
                ),
            )

        self.assert_sources_rejected(mutate, "request semantics.*postNotebookEntry")

    def test_multiline_inferred_property_default_is_witnessed(self) -> None:
        before, _ = drift._stored_property_witnesses(
            "struct Body: Encodable {\n    let wireVersion =\n        2\n}\n"
        )
        after, _ = drift._stored_property_witnesses(
            "struct Body: Encodable {\n    let wireVersion =\n        3\n}\n"
        )
        self.assertNotEqual(before, after)

    def test_multi_binding_property_tail_is_witnessed(self) -> None:
        before, _ = drift._stored_property_witnesses(
            "struct Body: Encodable {\n    let first = 1, second = 2\n}\n"
        )
        after, _ = drift._stored_property_witnesses(
            "struct Body: Encodable {\n    let first = 1, second = 3\n}\n"
        )
        self.assertNotEqual(before, after)

    def test_property_wrapper_changes_request_wire_witness(self) -> None:
        before, _ = drift._type_wire_witness(
            "struct Body: Encodable { let value: String }",
            (),
        )
        after, _ = drift._type_wire_witness(
            "struct Body: Encodable { @Wire var value: String }",
            (),
        )
        self.assertNotEqual(before, after)

    def test_non_contract_analytics_log_change_passes(self) -> None:
        path = "Packages/CoreKit/Sources/CoreKit/Analytics/AnalyticsClient.swift"

        def mutate(candidate) -> None:
            self.replace_once(
                candidate,
                path,
                'log.error("track flush retained \\(batch.count) event(s)")',
                'log.error("track delivery retained \\(batch.count) event(s)")',
            )

        self.assert_sources_accepted(mutate)

    def test_non_contract_logic_in_producer_file_passes(self) -> None:
        path = "Packages/Networking/Sources/Networking/Endpoint.swift"

        def mutate(candidate) -> None:
            self.replace_once(
                candidate,
                path,
                "public enum HTTPMethod: String, Sendable {\n",
                (
                    "public enum HTTPMethod: String, Sendable {\n"
                    "    public var isContractCanary: Bool { true }\n"
                ),
            )

        self.assert_sources_accepted(mutate)

    def test_non_contract_endpoint_computed_property_passes(self) -> None:
        path = "Packages/Networking/Sources/Networking/Endpoint.swift"

        def mutate(candidate) -> None:
            self.replace_once(
                candidate,
                path,
                "    public let requiresAuth: Bool\n",
                (
                    "    public let requiresAuth: Bool\n"
                    "    public var contractDebugLabel: String { path }\n"
                ),
            )

        self.assert_sources_accepted(mutate)

    def test_non_contract_endpoint_stored_property_passes(self) -> None:
        path = "Packages/Networking/Sources/Networking/Endpoint.swift"

        def mutate(candidate) -> None:
            self.replace_once(
                candidate,
                path,
                "    public let requiresAuth: Bool\n",
                (
                    "    public let requiresAuth: Bool\n"
                    "    public let debugTag: String? = nil\n"
                ),
            )

        self.assert_sources_accepted(mutate)

    def test_shared_json_decoder_change_passes(self) -> None:
        path = "Packages/Networking/Sources/Networking/JSONCoding.swift"

        def mutate(candidate) -> None:
            self.replace_once(
                candidate,
                path,
                (
                    "if let date = try? Date.ISO8601FormatStyle("
                    "includingFractionalSeconds: true).parse(string)"
                ),
                (
                    "if let date = try? Date.ISO8601FormatStyle("
                    "includingFractionalSeconds: false).parse(string)"
                ),
            )

        self.assert_sources_accepted(mutate)

    def test_local_query_diagnostic_read_passes(self) -> None:
        path = "Packages/Networking/Sources/Networking/Endpoint.swift"

        def mutate(candidate) -> None:
            self.replace_once(
                candidate,
                path,
                (
                    "        return Endpoint(method: .get, path: \"/book/me/notebook\", "
                    "query: query)\n"
                ),
                (
                    "        let diagnosticCount = query.count\n"
                    "        _ = diagnosticCount\n"
                    "        return Endpoint(method: .get, path: \"/book/me/notebook\", "
                    "query: query)\n"
                ),
            )

        self.assert_sources_accepted(mutate)

    def test_mapped_endpoint_method_change_fails(self) -> None:
        path = "Packages/Networking/Sources/Networking/Endpoint.swift"

        def mutate(candidate) -> None:
            self.replace_once(
                candidate,
                path,
                'Endpoint(method: .get, path: "/book/books", requiresAuth: false)',
                'Endpoint(method: .post, path: "/book/books", requiresAuth: false)',
            )

        self.assert_sources_rejected(mutate, "method|semantic")

    def test_http_method_raw_value_change_fails(self) -> None:
        path = "Packages/Networking/Sources/Networking/Endpoint.swift"

        def mutate(candidate) -> None:
            self.replace_once(
                candidate,
                path,
                'case get = "GET"',
                'case get = "POST"',
            )

        self.assert_sources_rejected(mutate, "request semantics|HTTPMethod")

    def test_mapped_route_change_fails(self) -> None:
        path = "Packages/Networking/Sources/Networking/Endpoint.swift"

        def mutate(candidate) -> None:
            self.replace_once(
                candidate,
                path,
                'Endpoint(method: .get, path: "/book/books", requiresAuth: false)',
                'Endpoint(method: .get, path: "/book/catalog", requiresAuth: false)',
            )

        self.assert_sources_rejected(mutate, "path|route|semantic")

    def test_authentication_change_fails(self) -> None:
        path = "Packages/Networking/Sources/Networking/Endpoint.swift"

        def mutate(candidate) -> None:
            self.replace_once(
                candidate,
                path,
                'Endpoint(method: .get, path: "/book/books", requiresAuth: false)',
                'Endpoint(method: .get, path: "/book/books", requiresAuth: true)',
            )

        self.assert_sources_rejected(mutate, "request semantics.*getBooks")

    def test_query_identity_change_fails(self) -> None:
        path = "Packages/Networking/Sources/Networking/Endpoint.swift"

        def mutate(candidate) -> None:
            self.replace_once(
                candidate,
                path,
                'URLQueryItem(name: "mode", value: $0)',
                'URLQueryItem(name: "format", value: $0)',
            )

        self.assert_sources_rejected(mutate, "request semantics.*getChapter")

    def test_local_query_condition_change_fails(self) -> None:
        path = "Packages/Networking/Sources/Networking/Endpoint.swift"

        def mutate(candidate) -> None:
            self.replace_once(
                candidate,
                path,
                (
                    "if let bookId { query.append(URLQueryItem(name: \"bookId\", value: bookId)) }\n"
                    "        if let chapterId { query.append(URLQueryItem(name: \"chapterId\", value: chapterId)) }\n"
                    "        return Endpoint(method: .get, path: \"/book/me/notebook\", query: query)"
                ),
                (
                    "if let chapterId { query.append(URLQueryItem(name: \"bookId\", value: chapterId)) }\n"
                    "        if let chapterId { query.append(URLQueryItem(name: \"chapterId\", value: chapterId)) }\n"
                    "        return Endpoint(method: .get, path: \"/book/me/notebook\", query: query)"
                ),
            )

        self.assert_sources_rejected(mutate, "request semantics.*getNotebook")

    def test_local_query_reordering_call_fails(self) -> None:
        path = "Packages/Networking/Sources/Networking/Endpoint.swift"

        def mutate(candidate) -> None:
            self.replace_once(
                candidate,
                path,
                (
                    "        if let chapterId { query.append(URLQueryItem(name: \"chapterId\", "
                    "value: chapterId)) }\n"
                    "        return Endpoint(method: .get, path: \"/book/me/notebook\", "
                    "query: query)\n"
                ),
                (
                    "        if let chapterId { query.append(URLQueryItem(name: \"chapterId\", "
                    "value: chapterId)) }\n"
                    "        query.swapAt(0, 1)\n"
                    "        return Endpoint(method: .get, path: \"/book/me/notebook\", "
                    "query: query)\n"
                ),
            )

        self.assert_sources_rejected(mutate, "request semantics.*getNotebook")

    def test_local_query_custom_mutator_call_fails(self) -> None:
        path = "Packages/Networking/Sources/Networking/Endpoint.swift"

        def mutate(candidate) -> None:
            candidate[
                "Packages/Networking/Sources/Networking/QueryCanary.swift"
            ] = (
                "import Foundation\n"
                "extension Array where Element == URLQueryItem {\n"
                "    mutating func scrambleForContract() { reverse() }\n"
                "}\n"
            ).encode("utf-8")
            self.replace_once(
                candidate,
                path,
                (
                    "        if let chapterId { query.append(URLQueryItem(name: \"chapterId\", "
                    "value: chapterId)) }\n"
                    "        return Endpoint(method: .get, path: \"/book/me/notebook\", "
                    "query: query)\n"
                ),
                (
                    "        if let chapterId { query.append(URLQueryItem(name: \"chapterId\", "
                    "value: chapterId)) }\n"
                    "        query.scrambleForContract()\n"
                    "        return Endpoint(method: .get, path: \"/book/me/notebook\", "
                    "query: query)\n"
                ),
            )

        self.assert_sources_rejected(mutate, "request semantics.*getNotebook")

    def test_local_query_trailing_closure_sort_fails(self) -> None:
        path = "Packages/Networking/Sources/Networking/Endpoint.swift"

        def mutate(candidate) -> None:
            self.replace_once(
                candidate,
                path,
                (
                    "        return Endpoint(method: .get, path: \"/book/me/notebook\", "
                    "query: query)\n"
                ),
                (
                    "        query.sort { $0.name < $1.name }\n"
                    "        return Endpoint(method: .get, path: \"/book/me/notebook\", "
                    "query: query)\n"
                ),
            )

        self.assert_sources_rejected(mutate, "request semantics.*getNotebook")

    def test_local_query_element_member_assignment_fails(self) -> None:
        path = "Packages/Networking/Sources/Networking/Endpoint.swift"

        def mutate(candidate) -> None:
            self.replace_once(
                candidate,
                path,
                (
                    "        return Endpoint(method: .get, path: \"/book/me/notebook\", "
                    "query: query)\n"
                ),
                (
                    '        query[0].value = "surprise"\n'
                    "        return Endpoint(method: .get, path: \"/book/me/notebook\", "
                    "query: query)\n"
                ),
            )

        self.assert_sources_rejected(mutate, "request semantics.*getNotebook")

    def test_shared_json_encoder_change_fails(self) -> None:
        path = "Packages/Networking/Sources/Networking/JSONCoding.swift"

        def mutate(candidate) -> None:
            self.replace_once(
                candidate,
                path,
                (
                    "container.encode(date.formatted(Date.ISO8601FormatStyle("
                    "includingFractionalSeconds: true)))"
                ),
                (
                    "container.encode(date.formatted(Date.ISO8601FormatStyle("
                    "includingFractionalSeconds: false)))"
                ),
            )

        self.assert_sources_rejected(mutate, "request semantics|endpoint_core")

    def test_generic_request_body_model_change_fails(self) -> None:
        path = "Packages/SocialFeature/Sources/SocialFeature/Models/OwnProfile.swift"

        def mutate(candidate) -> None:
            self.replace_once(
                candidate,
                path,
                (
                    "    public let displayName: String?\n"
                    "    public let avatarEmoji: String?\n"
                    "    /// Privacy-settings update (P7.8). When non-nil, the entire settings object\n"
                ),
                (
                    "    public let displayName: String?\n"
                    "    public let avatarEmoji: String?\n"
                    "    public let unexpectedWireKey: String? = nil\n"
                    "    /// Privacy-settings update (P7.8). When non-nil, the entire settings object\n"
                ),
            )

        self.assert_sources_rejected(mutate, "request semantics.*updateSettings")

    def test_request_body_identity_change_fails(self) -> None:
        path = "Packages/Networking/Sources/Networking/Endpoint.swift"

        def mutate(candidate) -> None:
            self.replace_once(
                candidate,
                path,
                "struct Body: Encodable { let bookId: String; let saved: Bool }",
                "struct Body: Encodable { let bookId: String; let isSaved: Bool }",
            )
            self.replace_once(
                candidate,
                path,
                "body: Body(bookId: bookId, saved: saved)",
                "body: Body(bookId: bookId, isSaved: saved)",
            )

        self.assert_sources_rejected(mutate, "request semantics.*toggleSaved")

    def test_custom_request_encoder_change_fails(self) -> None:
        path = "Packages/Networking/Sources/Networking/NotebookEntryRequest.swift"

        def mutate(candidate) -> None:
            source = candidate[path].decode("utf-8")
            source += (
                "\nextension NotebookEntryRequest {\n"
                "    public func encode(to encoder: any Encoder) throws {\n"
                "        var container = encoder.singleValueContainer()\n"
                "        try container.encode(bookId)\n"
                "    }\n"
                "}\n"
            )
            candidate[path] = source.encode("utf-8")

        self.assert_sources_rejected(mutate, "request semantics.*postNotebookEntry")

    def test_new_endpoint_producer_in_new_file_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/Networking/Sources/Networking/Endpoint+Surprise.swift"
            ] = (
                "extension Endpoints {\n"
                "    static func surprise() -> Endpoint {\n"
                '        Endpoint(method: .get, path: "/book/surprise")\n'
                "    }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(mutate, "unexpected|producer set")

    def test_indirect_endpoint_producer_in_arbitrary_file_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/IndirectContract.swift"
            ] = (
                "import Networking\n"
                "extension Endpoints {\n"
                "    static func surpriseAlias() -> Endpoint {\n"
                "        Endpoints.getBooks()\n"
                "    }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(mutate, "all-source producer set|surpriseAlias")

    def test_computed_endpoint_property_in_arbitrary_file_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/ComputedContract.swift"
            ] = (
                "import Networking\n"
                "extension Endpoints {\n"
                "    static var surprise: Endpoint { Endpoints.getBooks() }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(mutate, "all-source producer set|surprise")

    def test_inferred_static_endpoint_property_in_arbitrary_file_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/InferredContract.swift"
            ] = (
                "import Networking\n"
                "extension Endpoints {\n"
                "    static let surprise = Endpoints.getBooks()\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(mutate, "all-source producer set|surprise")

    def test_inferred_endpoint_factory_reference_property_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/FactoryReference.swift"
            ] = (
                "import Networking\n"
                "struct ContractHolder {\n"
                "    static let surprise = Endpoints.getBooks\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(mutate, "all-source producer set|surprise")

    def test_inferred_endpoint_initializer_reference_property_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/InitReference.swift"
            ] = (
                "import Networking\n"
                "struct ContractHolder {\n"
                "    static let surprise = Endpoint.init\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(mutate, "all-source producer set|surprise")

    def test_endpoint_typealias_returning_function_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/AliasedContract.swift"
            ] = (
                "import Networking\n"
                "typealias APIEndpoint = (Endpoint)\n"
                "func surpriseAlias() -> APIEndpoint { Endpoints.getBooks() }\n"
            ).encode("utf-8")

        self.assert_sources_rejected(mutate, "all-source producer set|surpriseAlias")

    def test_generic_endpoint_closure_alias_returning_function_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/GenericFunctionContract.swift"
            ] = (
                "import Networking\n"
                "typealias Producer<Value> = @Sendable () -> Value\n"
                "func surpriseGeneric() -> Producer<Endpoint> {\n"
                "    { Endpoints.getBooks() }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(
            mutate,
            "current all-source producer set differs.*surpriseGeneric",
        )

    def test_nested_generic_constraint_function_head_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/NestedGenericHead.swift"
            ] = (
                "import Networking\n"
                "class Box<Value> {}\n"
                "typealias Producer<Value> = () -> Value\n"
                "func surpriseNestedHead<Value: Box<Int>>() -> Producer<Endpoint> {\n"
                "    { Endpoints.getBooks() }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(
            mutate,
            "current all-source producer set differs.*surpriseNestedHead",
        )

    def test_endpoint_closure_alias_returning_operator_function_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/OperatorContract.swift"
            ] = (
                "import Networking\n"
                "prefix operator +++\n"
                "typealias Producer<Value> = () -> Value\n"
                "prefix func +++(value: Int) -> Producer<Endpoint> {\n"
                "    { Endpoints.getBooks() }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(
            mutate,
            r"current all-source producer set differs.*\+\+\+",
        )

    def test_optional_endpoint_returning_function_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/OptionalContract.swift"
            ] = (
                "import Networking\n"
                "func surpriseOptional() -> Optional<Endpoint> { Endpoints.getBooks() }\n"
            ).encode("utf-8")

        self.assert_sources_rejected(mutate, "all-source producer set|surpriseOptional")

    def test_parenthesized_endpoint_returning_function_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/ParenContract.swift"
            ] = (
                "import Networking\n"
                "func surpriseParen() -> (Endpoint) { Endpoints.getBooks() }\n"
            ).encode("utf-8")

        self.assert_sources_rejected(mutate, "all-source producer set|surpriseParen")

    def test_sending_endpoint_returning_function_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/SendingContract.swift"
            ] = (
                "import Networking\n"
                "func surpriseSending() -> sending Endpoint { Endpoints.getBooks() }\n"
            ).encode("utf-8")

        self.assert_sources_rejected(mutate, "all-source producer set|surpriseSending")

    def test_nested_endpoint_alias_returning_function_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/NestedAliasContract.swift"
            ] = (
                "import Networking\n"
                "enum API { typealias Request = Endpoint }\n"
                "func surpriseNested() -> API.Request { Endpoints.getBooks() }\n"
            ).encode("utf-8")

        self.assert_sources_rejected(mutate, "all-source producer set|surpriseNested")

    def test_backticked_endpoint_returning_function_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/BacktickContract.swift"
            ] = (
                "import Networking\n"
                "func `switch`() -> Endpoint { Endpoints.getBooks() }\n"
            ).encode("utf-8")

        self.assert_sources_rejected(mutate, "all-source producer set|switch")

    def test_endpoint_returning_subscript_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/SubscriptContract.swift"
            ] = (
                "import Networking\n"
                "struct RequestTable {\n"
                "    subscript(index: Int) -> Endpoint { Endpoints.getBooks() }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(mutate, "all-source producer set|subscript")

    def test_generic_endpoint_closure_alias_returning_subscript_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/GenericSubscriptContract.swift"
            ] = (
                "import Networking\n"
                "typealias Producer<Value> = () -> Value\n"
                "struct RequestTable {\n"
                "    subscript(index: Int) -> Producer<Endpoint> {\n"
                "        { Endpoints.getBooks() }\n"
                "    }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(
            mutate,
            "current all-source producer set differs.*subscript",
        )

    def test_generic_subscript_endpoint_closure_alias_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/GenericSubscriptHead.swift"
            ] = (
                "import Networking\n"
                "typealias Producer<Value> = () -> Value\n"
                "struct RequestTable {\n"
                "    subscript<Key>(key: Key) -> Producer<Endpoint> {\n"
                "        { Endpoints.getBooks() }\n"
                "    }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(
            mutate,
            "current all-source producer set differs.*subscript",
        )

    def test_endpoint_shorthand_initializer_in_arbitrary_function_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/ShorthandContract.swift"
            ] = (
                "import Networking\n"
                "func surpriseRequest() {\n"
                "    let endpoint: Endpoint = .init(method: .get, path: \"/surprise\")\n"
                "    _ = endpoint\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(mutate, "all-source producer set|unmapped")

    def test_endpoint_qualified_initializer_in_arbitrary_function_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/QualifiedContract.swift"
            ] = (
                "import Networking\n"
                "func surpriseRequest() {\n"
                "    _ = Networking.Endpoint.init(method: .get, path: \"/surprise\")\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(mutate, "all-source producer set|unmapped")

    def test_endpoint_shorthand_initializer_reassignment_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/ReassignedContract.swift"
            ] = (
                "import Networking\n"
                "func surpriseRequest() {\n"
                "    var endpoint: Endpoint\n"
                "    endpoint = .init(method: .get, path: \"/surprise\")\n"
                "    _ = endpoint\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(mutate, "all-source producer set|unmapped")

    def test_endpoint_metatype_function_is_not_a_producer(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/EndpointMetatype.swift"
            ] = (
                "import Networking\n"
                "func endpointMetatype() -> Endpoint.Type { Endpoint.self }\n"
            ).encode("utf-8")

        self.assert_sources_accepted(mutate)

    def test_new_endpoint_producer_in_app_host_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate["ChapterFlow/SurpriseEndpoint.swift"] = (
                "import Networking\n"
                "func surpriseHostRequest() -> Endpoint { Endpoints.getBooks() }\n"
            ).encode("utf-8")

        self.assert_sources_rejected(mutate, "all-source producer set|surpriseHostRequest")

    def test_instance_stored_endpoint_property_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/StoredContract.swift"
            ] = (
                "import Networking\n"
                "struct ContractHolder {\n"
                "    let surprise: Endpoint = Endpoints.getBooks()\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(mutate, "all-source producer set|surprise")

    def test_endpoint_returning_closure_property_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/ClosureContract.swift"
            ] = (
                "import Networking\n"
                "struct ContractHolder {\n"
                "    static let surprise: @Sendable () -> Endpoint = { Endpoints.getBooks() }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(mutate, "all-source producer set|surprise")

    def test_endpoint_returning_closure_typealias_property_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/ClosureAliasContract.swift"
            ] = (
                "import Networking\n"
                "typealias EndpointFactory = @Sendable () -> Endpoint\n"
                "struct ContractHolder {\n"
                "    static let surprise: EndpointFactory = { Endpoints.getBooks() }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(mutate, "all-source producer set|surprise")

    def test_generic_endpoint_closure_typealias_property_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/GenericClosureAlias.swift"
            ] = (
                "import Networking\n"
                "typealias Factory<T> = @Sendable () -> T\n"
                "struct H {\n"
                "    static let surprise: Factory<Endpoint> = {\n"
                "        Endpoints.getBooks()\n"
                "    }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(
            mutate,
            "current all-source producer set differs.*surprise",
        )

    def test_generic_alias_resolver_substitutes_endpoint_and_string_arguments(self) -> None:
        path = (
            "Packages/LibraryFeature/Sources/LibraryFeature/ResolverCanary.swift"
        )
        sources = {
            path: (
                "import Networking\n"
                "typealias Producer<Value> = @Sendable () -> Value\n"
            ).encode("utf-8")
        }
        resolver = drift._SwiftAliasResolver(sources, {path: {"Endpoint"}})
        endpoint = resolver.parse_and_resolve(
            "Producer<Endpoint>",
            path=path,
            position=len(sources[path]),
        )
        string = resolver.parse_and_resolve(
            "Producer<String>",
            path=path,
            position=len(sources[path]),
        )
        self.assertTrue(
            resolver.endpoint_relation(endpoint, path=path, position=len(sources[path]))
        )
        self.assertFalse(
            resolver.endpoint_relation(string, path=path, position=len(sources[path]))
        )

    def test_generic_endpoint_closure_direct_factory_reference_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/GenericFactoryReference.swift"
            ] = (
                "import Networking\n"
                "typealias Producer<Value> = @Sendable () -> Value\n"
                "struct H {\n"
                "    static let surprise: Producer<Endpoint> = Endpoints.getBooks\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(mutate, "all-source producer set|surprise")

    def test_generic_factory_endpoint_alias_argument_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/GenericEndpointAlias.swift"
            ] = (
                "import Networking\n"
                "typealias E = Endpoint\n"
                "typealias Producer<Value> = () -> Value\n"
                "struct H {\n"
                "    static let surprise: Producer<E> = { Endpoints.getBooks() }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(mutate, "all-source producer set|surprise")

    def test_chained_generic_endpoint_closure_alias_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/GenericAliasChain.swift"
            ] = (
                "import Networking\n"
                "typealias First<Value> = Second<Value>\n"
                "typealias Second<Output> = @Sendable () -> Output\n"
                "struct H {\n"
                "    static let surprise: First<Endpoint> = { Endpoints.getBooks() }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(mutate, "all-source producer set|surprise")

    def test_async_throwing_generic_endpoint_closure_alias_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/AsyncGenericAlias.swift"
            ] = (
                "import Networking\n"
                "typealias Producer<Value> = @Sendable () async throws -> Value\n"
                "struct H {\n"
                "    static let surprise: Producer<Endpoint> = { Endpoints.getBooks() }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(mutate, "all-source producer set|surprise")

    def test_optional_endpoint_generic_return_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/OptionalGenericAlias.swift"
            ] = (
                "import Networking\n"
                "typealias Producer<Value> = () -> Value?\n"
                "struct H {\n"
                "    static let surprise: Producer<Endpoint> = { Endpoints.getBooks() }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(mutate, "all-source producer set|surprise")

    def test_result_endpoint_generic_return_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/ResultGenericAlias.swift"
            ] = (
                "import Networking\n"
                "typealias Producer<Value> = () -> Result<Value, Error>\n"
                "struct H {\n"
                "    static let surprise: Producer<Endpoint> = {\n"
                "        .success(Endpoints.getBooks())\n"
                "    }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(mutate, "all-source producer set|surprise")

    def test_tuple_endpoint_generic_return_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/TupleGenericAlias.swift"
            ] = (
                "import Networking\n"
                "typealias Producer<Value> = () -> (Int, Value)\n"
                "struct H {\n"
                "    static let surprise: Producer<Endpoint> = {\n"
                "        (1, Endpoints.getBooks())\n"
                "    }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(mutate, "all-source producer set|surprise")

    def test_qualified_endpoint_generic_return_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/QualifiedGenericAlias.swift"
            ] = (
                "import Networking\n"
                "typealias Producer<Value> = () -> Value\n"
                "struct H {\n"
                "    static let surprise: Producer<Networking.Endpoint> = {\n"
                "        Endpoints.getBooks()\n"
                "    }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(mutate, "all-source producer set|surprise")

    def test_multiline_constrained_generic_endpoint_alias_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/MultilineGenericAlias.swift"
            ] = (
                "import Networking\n"
                "typealias Producer<Value: Sendable> =\n"
                "    @Sendable\n"
                "    () async throws\n"
                "    -> Value\n"
                "struct H {\n"
                "    static let surprise: Producer<Endpoint> = { Endpoints.getBooks() }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(mutate, "all-source producer set|surprise")

    def test_nearest_nested_generic_alias_resolving_endpoint_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/NestedGenericAlias.swift"
            ] = (
                "import Networking\n"
                "typealias Producer<Value> = () -> String\n"
                "struct H {\n"
                "    typealias Producer<Value> = () -> Value\n"
                "    static let surprise: Producer<Endpoint> = { Endpoints.getBooks() }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(mutate, "all-source producer set|surprise")

    def test_generic_alias_cycle_with_endpoint_evidence_fails_closed(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/CyclicGenericAlias.swift"
            ] = (
                "import Networking\n"
                "typealias First<Value> = Second<Value>\n"
                "typealias Second<Value> = First<Value>\n"
                "struct H {\n"
                "    static let surprise: First<Endpoint> = { Endpoints.getBooks() }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(mutate, "alias cycle|proof is incomplete")

    def test_generic_alias_arity_mismatch_with_endpoint_evidence_fails_closed(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/ArityGenericAlias.swift"
            ] = (
                "import Networking\n"
                "typealias Producer<Value> = () -> Value\n"
                "struct H {\n"
                "    static let surprise: Producer<Endpoint, String> = {\n"
                "        Endpoints.getBooks()\n"
                "    }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(mutate, "arity mismatch|proof is incomplete")

    def test_unresolved_enclosing_generic_parameter_with_endpoint_evidence_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/OuterGenericAlias.swift"
            ] = (
                "import Networking\n"
                "typealias Producer<Value> = () -> Value\n"
                "struct H<Value> {\n"
                "    let surprise: Producer<Value> = { Endpoints.getBooks() }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(mutate, "unresolved enclosing generic parameter|proof is incomplete")

    def test_generic_alias_direct_endpoint_construction_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/GenericDirectEndpoint.swift"
            ] = (
                "import Networking\n"
                "typealias Producer<Value> = () -> Value\n"
                "struct H {\n"
                "    static let surprise: Producer<Endpoint> = {\n"
                "        Endpoint(method: .get, path: \"/surprise\")\n"
                "    }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(mutate, "all-source producer set|surprise")

    def test_generic_alias_typed_computed_property_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/GenericComputed.swift"
            ] = (
                "import Networking\n"
                "typealias Producer<Value> = () -> Value\n"
                "struct H {\n"
                "    static var surprise: Producer<Endpoint> {\n"
                "        { Endpoints.getBooks() }\n"
                "    }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(
            mutate,
            "current all-source producer set differs.*surprise",
        )

    def test_same_module_member_alias_concealing_endpoint_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/AliasNamespace.swift"
            ] = (
                "import Networking\n"
                "enum API {\n"
                "    typealias Producer<Value> = () -> Endpoint\n"
                "}\n"
            ).encode("utf-8")
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/CrossFileAliasUse.swift"
            ] = (
                "import Networking\n"
                "struct H {\n"
                "    static let surprise: API.Producer<String> = {\n"
                "        Endpoints.getBooks()\n"
                "    }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(
            mutate,
            "current all-source producer set differs.*surprise",
        )

    def test_stored_generic_closure_alternate_endpoint_returns_fail(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/AlternateGenericReturns.swift"
            ] = (
                "import Networking\n"
                "typealias Producer<Value> = (Bool) -> Value\n"
                "struct H {\n"
                "    static let surprise: Producer<Endpoint> = { flag in\n"
                "        if flag { return Endpoints.getBooks() }\n"
                "        return Endpoints.getSession()\n"
                "    }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(mutate, "all-source producer set|surprise")

    def test_endpoint_closure_passed_to_unresolved_api_fails_closed(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/UnresolvedEscape.swift"
            ] = (
                "import Networking\n"
                "func retainUnknown<Value>(_ value: Value) -> Value { value }\n"
                "struct H {\n"
                "    static let surprise = retainUnknown { Endpoints.getBooks() }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(mutate, "all-source producer set|surprise")

    def test_nested_endpoint_closure_passed_to_unresolved_api_fails_closed(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/NestedUnresolvedEscape.swift"
            ] = (
                "import Networking\n"
                "func retainUnknown<Value>(_ value: Value) -> Value { value }\n"
                "struct H {\n"
                "    static let surprise: () -> String = {\n"
                "        let local = { Endpoints.getBooks() }\n"
                "        _ = retainUnknown(local)\n"
                "        return \"debug\"\n"
                "    }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(mutate, "proof is incomplete|unresolved escape")

    def test_anonymous_endpoint_closure_passed_to_unresolved_api_fails_closed(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/AnonymousEscape.swift"
            ] = (
                "import Networking\n"
                "func retainUnknown<Value>(_ value: Value) -> Value { value }\n"
                "struct H {\n"
                "    static let debug: () -> String = {\n"
                "        _ = retainUnknown { Endpoints.getBooks() }\n"
                "        return \"debug\"\n"
                "    }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(mutate, "proof is incomplete|unresolved escape")

    def test_returned_nested_endpoint_closure_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/ReturnedNestedClosure.swift"
            ] = (
                "import Networking\n"
                "struct H {\n"
                "    static let surprise = {\n"
                "        let local = { Endpoints.getBooks() }\n"
                "        return local\n"
                "    }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(mutate, "all-source producer set|surprise")

    def test_inferred_local_endpoint_value_returned_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/ReturnedLocalValue.swift"
            ] = (
                "import Networking\n"
                "struct H {\n"
                "    static let surprise = {\n"
                "        let value = Endpoints.getBooks()\n"
                "        return value\n"
                "    }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(
            mutate,
            "current all-source producer set differs.*surprise",
        )

    def test_inferred_local_factory_reference_invoked_and_returned_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/ReturnedLocalFactory.swift"
            ] = (
                "import Networking\n"
                "struct H {\n"
                "    static let surprise = {\n"
                "        let make = Endpoints.getBooks\n"
                "        return make()\n"
                "    }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(
            mutate,
            "current all-source producer set differs.*surprise",
        )

    def test_second_stored_binding_endpoint_closure_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/SecondStoredBinding.swift"
            ] = (
                "import Networking\n"
                "typealias Producer<Value> = () -> Value\n"
                "struct H {\n"
                "    static let debug = 1, surprise: Producer<Endpoint> = {\n"
                "        Endpoints.getBooks()\n"
                "    }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(mutate, "all-source producer set|surprise")

    def test_unqualified_factory_reference_inside_endpoints_owner_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/Networking/Sources/Networking/UnqualifiedFactory.swift"
            ] = (
                "extension Endpoints {\n"
                "    static let surprise = getBooks\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(
            mutate,
            "current all-source producer set differs.*surprise",
        )

    def test_unqualified_factory_call_inside_endpoints_owner_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/Networking/Sources/Networking/UnqualifiedFactoryCall.swift"
            ] = (
                "extension Endpoints {\n"
                "    static let surprise = { getBooks() }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(
            mutate,
            "current all-source producer set differs.*surprise",
        )

    def test_multiline_inferred_factory_reference_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/MultilineFactoryRef.swift"
            ] = (
                "import Networking\n"
                "struct H {\n"
                "    static let surprise = Endpoints\n"
                "        .getBooks\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(
            mutate,
            "current all-source producer set differs.*surprise",
        )

    def test_generic_alias_producer_in_unrelated_production_source_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/DesignSystem/Sources/DesignSystem/ContractEscape.swift"
            ] = (
                "import Networking\n"
                "typealias DesignProducer<Value> = () -> Value\n"
                "enum ContractEscape {\n"
                "    static let surprise: DesignProducer<Endpoint> = {\n"
                "        Endpoints.getBooks()\n"
                "    }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(mutate, "all-source producer set|surprise")

    def test_generic_non_endpoint_closure_alias_property_passes(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/GenericStringAlias.swift"
            ] = (
                "import Networking\n"
                "typealias Producer<Value> = @Sendable () -> Value\n"
                "struct H { static let debug: Producer<String> = { \"debug\" } }\n"
            ).encode("utf-8")

        self.assert_sources_accepted(mutate)

    def test_endpoint_closure_parameter_with_non_endpoint_result_passes(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/EndpointConsumerAlias.swift"
            ] = (
                "import Networking\n"
                "typealias Consumer = (() -> Endpoint) -> String\n"
                "struct H { static let debug: Consumer = { _ in \"debug\" } }\n"
            ).encode("utf-8")

        self.assert_sources_accepted(mutate)

    def test_same_module_member_alias_resolving_non_endpoint_passes(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/ConsumerNamespace.swift"
            ] = (
                "enum API {\n"
                "    typealias Consumer<Value> = () -> String\n"
                "}\n"
            ).encode("utf-8")
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/CrossFileConsumer.swift"
            ] = (
                "import Networking\n"
                "struct H {\n"
                "    static let debug: API.Consumer<Endpoint> = { \"debug\" }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_accepted(mutate)

    def test_function_generic_parameter_shadows_endpoint_alias_passes(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/GenericShadow.swift"
            ] = (
                "import Networking\n"
                "typealias Output = () -> Endpoint\n"
                "func debug<Output>() -> Output { fatalError() }\n"
            ).encode("utf-8")

        self.assert_sources_accepted(mutate)

    def test_nearest_nested_generic_alias_resolving_non_endpoint_passes(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/NestedStringAlias.swift"
            ] = (
                "import Networking\n"
                "typealias Producer<Value> = () -> Value\n"
                "struct H {\n"
                "    typealias Producer<Value> = () -> String\n"
                "    static let debug: Producer<Endpoint> = { \"debug\" }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_accepted(mutate)

    def test_local_direct_call_only_generic_endpoint_closure_passes(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/LocalGenericClosure.swift"
            ] = (
                "import Networking\n"
                "typealias Producer<Value> = () -> Value\n"
                "func debugLocalClosure() {\n"
                "    let local: Producer<Endpoint> = { Endpoints.getBooks() }\n"
                "    _ = local()\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_accepted(mutate)

    def test_nested_local_endpoint_closure_direct_call_discarded_passes(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/NestedLocalClosure.swift"
            ] = (
                "import Networking\n"
                "struct H {\n"
                "    static let debug: () -> String = {\n"
                "        let local: () -> Endpoint = {\n"
                "            return Endpoints.getBooks()\n"
                "        }\n"
                "        _ = local()\n"
                "        return \"debug\"\n"
                "    }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_accepted(mutate)

    def test_nested_local_endpoint_function_direct_call_discarded_passes(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/NestedLocalFunction.swift"
            ] = (
                "import Networking\n"
                "typealias Producer<Value> = () -> Value\n"
                "struct H {\n"
                "    static let debug: () -> String = {\n"
                "        func local() -> Producer<Endpoint> {\n"
                "            { Endpoints.getBooks() }\n"
                "        }\n"
                "        _ = local()()\n"
                "        return \"debug\"\n"
                "    }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_accepted(mutate)

    def test_immediately_invoked_endpoint_closure_discarded_passes(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/ImmediateClosure.swift"
            ] = (
                "import Networking\n"
                "struct H {\n"
                "    static let debug: () -> String = {\n"
                "        _ = ({ () -> Endpoint in return Endpoints.getBooks() })()\n"
                "        return \"debug\"\n"
                "    }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_accepted(mutate)

    def test_comparison_only_stored_closure_passes(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/ComparisonClosure.swift"
            ] = (
                "struct H { static let debug = { 1 < 2 } }\n"
            ).encode("utf-8")

        self.assert_sources_accepted(mutate)

    def test_endpoint_side_effect_confined_to_property_observer_passes(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/ObserverSideEffect.swift"
            ] = (
                "import Networking\n"
                "struct H {\n"
                "    static var debug = \"debug\" {\n"
                "        didSet { _ = Endpoints.getBooks() }\n"
                "    }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_accepted(mutate)

    def test_discarded_endpoint_call_in_string_closure_passes(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/DiscardedEndpoint.swift"
            ] = (
                "import Networking\n"
                "typealias Producer<Value> = () -> Value\n"
                "struct H {\n"
                "    static let debug: Producer<String> = {\n"
                "        _ = Endpoints.getBooks()\n"
                "        return \"debug\"\n"
                "    }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_accepted(mutate)

    def test_discarded_endpoint_call_in_inferred_string_closure_passes(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/DiscardedInferredEndpoint.swift"
            ] = (
                "import Networking\n"
                "struct H {\n"
                "    static let debug = {\n"
                "        _ = Endpoints.getBooks()\n"
                "        return \"debug\"\n"
                "    }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_accepted(mutate)

    def test_generic_alias_examples_in_comments_and_strings_pass(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/GenericAliasText.swift"
            ] = (
                "// typealias Producer<T> = () -> T\n"
                "// static let surprise: Producer<Endpoint> = { Endpoints.getBooks() }\n"
                "struct AliasText {\n"
                "    static let ordinary = \"Factory<Endpoint> = Endpoints.getBooks\"\n"
                "    static let raw = #\"Factory<Endpoint> { Endpoints.getBooks() }\"#\n"
                "    static let multiline = \"\"\"\n"
                "    typealias Producer<T> = () -> T\n"
                "    static let surprise: Producer<Endpoint> = { Endpoints.getBooks() }\n"
                "    \"\"\"\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_accepted(mutate)

    def test_private_endpoint_typealias_shadow_passes(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/LocalAlias.swift"
            ] = (
                "private typealias Endpoint = String\n"
                'private func debugLabel() -> Endpoint { "debug" }\n'
            ).encode("utf-8")

        self.assert_sources_accepted(mutate)

    def test_private_endpoint_struct_shadow_passes(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/LocalEndpoint.swift"
            ] = (
                "private struct Endpoint {}\n"
                "private func debugValue() -> Endpoint { Endpoint() }\n"
            ).encode("utf-8")

        self.assert_sources_accepted(mutate)

    def test_nested_endpoint_struct_shadow_passes(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/NestedEndpoint.swift"
            ] = (
                "import Networking\n"
                "struct DebugNamespace {\n"
                "    struct Endpoint {}\n"
                "    func debugValue() -> Endpoint { Endpoint() }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_accepted(mutate)

    def test_protocol_endpoint_requirements_are_not_producers(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/EndpointProtocol.swift"
            ] = (
                "import Networking\n"
                "protocol EndpointProviding {\n"
                "    var endpoint: Endpoint { get }\n"
                "    func makeEndpoint() -> Endpoint\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_accepted(mutate)

    def test_computed_endpoint_property_with_local_did_set_name_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/ComputedDidSet.swift"
            ] = (
                "import Networking\n"
                "struct ContractHolder {\n"
                "    static var surprise: Endpoint {\n"
                "        let didSet = false\n"
                "        _ = didSet\n"
                "        return Endpoints.getBooks()\n"
                "    }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(mutate, "all-source producer set|surprise")

    def test_scenario_outbox_body_construction_change_fails(self) -> None:
        path = (
            "Packages/EngagementFeature/Sources/EngagementFeature/Scenarios/"
            "ScenarioRepository.swift"
        )

        def mutate(candidate) -> None:
            self.replace_once(
                candidate,
                path,
                "let json = String(data: body, encoding: .utf8)",
                'let json = String(data: Data("{\\\"surprise\\\":true}".utf8), encoding: .utf8)',
            )

        self.assert_sources_rejected(mutate, "request semantics.*syncPendingUploads")

    def test_scenario_outbox_persisted_payload_change_fails(self) -> None:
        path = (
            "Packages/EngagementFeature/Sources/EngagementFeature/Scenarios/"
            "ScenarioRepository.swift"
        )

        def mutate(candidate) -> None:
            self.replace_once(
                candidate,
                path,
                "            requestJSON: json\n",
                '            requestJSON: "{}"\n',
            )

        self.assert_sources_rejected(mutate, "request semantics.*syncPendingUploads")

    def test_scenario_submit_endpoint_handoff_change_fails(self) -> None:
        path = (
            "Packages/EngagementFeature/Sources/EngagementFeature/Scenarios/"
            "ScenarioRepository.swift"
        )

        def mutate(candidate) -> None:
            self.replace_once(
                candidate,
                path,
                (
                    "let endpoint = try Endpoints.postScenario(bookId: bookId, "
                    "chapterNumber: chapterNumber, body: body)"
                ),
                "let endpoint = Endpoints.getBooks()",
            )

        self.assert_sources_rejected(mutate, "request semantics.*syncPendingUploads")

    def test_scenario_persisted_payload_assignment_change_fails(self) -> None:
        path = "Packages/Persistence/Sources/Persistence/PendingScenarioUpload.swift"

        def mutate(candidate) -> None:
            self.replace_once(
                candidate,
                path,
                "self.requestJSON = requestJSON",
                'self.requestJSON = "{}"',
            )

        self.assert_sources_rejected(mutate, "request semantics.*syncPendingUploads")

    def test_analytics_encoder_strategy_change_fails(self) -> None:
        path = "Packages/CoreKit/Sources/CoreKit/Analytics/AnalyticsClient.swift"

        def mutate(candidate) -> None:
            self.replace_once(
                candidate,
                path,
                "e.dateEncodingStrategy = .iso8601",
                "e.dateEncodingStrategy = .secondsSince1970",
            )

        self.assert_sources_rejected(mutate, "request semantics.*Analytics")

    def test_duplicate_producer_becomes_ambiguous_and_fails(self) -> None:
        path = "Packages/Networking/Sources/Networking/Endpoint.swift"

        def mutate(candidate) -> None:
            source = candidate[path].decode("utf-8")
            source += (
                "\nextension Endpoints {\n"
                "    static func getBooks() -> Endpoint {\n"
                "        Endpoint(method: .get, path: \"/book/books\")\n"
                "    }\n"
                "}\n"
            )
            candidate[path] = source.encode("utf-8")

        self.assert_sources_rejected(mutate, "ambiguous|getBooks")

    def test_removed_producer_fails(self) -> None:
        path = "Packages/Networking/Sources/Networking/Endpoint+Config.swift"

        def mutate(candidate) -> None:
            source = candidate[path].decode("utf-8")
            start = source.index("    public static func getIOSConfig")
            end = source.index("    }", start) + len("    }")
            candidate[path] = (source[:start] + source[end:]).encode("utf-8")

        self.assert_sources_rejected(mutate, "getIOSConfig|producer")

    def test_producer_source_path_move_fails(self) -> None:
        old_path = "Packages/Networking/Sources/Networking/Endpoint+Config.swift"
        new_path = "Packages/Networking/Sources/Networking/Endpoint+ConfigMoved.swift"

        def mutate(candidate) -> None:
            candidate[new_path] = candidate.pop(old_path)

        self.assert_sources_rejected(mutate, "source file is missing|producer")

    def test_operation_or_matrix_reassignment_fails(self) -> None:
        candidate = copy.deepcopy(self.mapping)
        record = next(
            item for item in candidate["records"]
            if item["operationId"] == "commitment.get"
        )
        record["matrixRowId"] = "catalog"
        mapping_bytes = (json.dumps(candidate, indent=2) + "\n").encode("utf-8")
        with self.assertRaisesRegex(
            drift.DriftError,
            "source mapping changed.*coordinated evidence regeneration",
        ):
            drift.compare_worktree_semantics(
                manifest=self.manifest,
                mapping_bytes=mapping_bytes,
                generator_bytes=self.generator_bytes,
                current_sources=self.sources,
                historical_sources=self.historical_sources,
            )

    def test_operation_reassignment_requires_mapping_regeneration(self) -> None:
        candidate = copy.deepcopy(self.mapping)
        record = next(
            item for item in candidate["records"]
            if item["operationId"] == "commitment.get"
        )
        record["operationId"] = "catalog.get"
        mapping_bytes = (json.dumps(candidate, indent=2) + "\n").encode("utf-8")
        with self.assertRaisesRegex(
            drift.DriftError,
            "source mapping changed.*coordinated evidence regeneration",
        ):
            drift.compare_worktree_semantics(
                manifest=self.manifest,
                mapping_bytes=mapping_bytes,
                generator_bytes=self.generator_bytes,
                current_sources=self.sources,
                historical_sources=self.historical_sources,
            )

    def test_generator_change_requires_coordinated_regeneration(self) -> None:
        with self.assertRaisesRegex(
            drift.DriftError,
            "inventory generator changed.*coordinated evidence regeneration",
        ):
            drift.compare_worktree_semantics(
                manifest=self.manifest,
                mapping_bytes=self.mapping_bytes,
                generator_bytes=self.generator_bytes + b"\n# canary\n",
                current_sources=self.sources,
                historical_sources=self.historical_sources,
            )

    def test_incremental_verifier_change_requires_policy_regeneration(self) -> None:
        with self.assertRaisesRegex(
            drift.DriftError,
            "incremental drift verifier changed.*policy regeneration",
        ):
            drift.assert_incremental_policy_lock(
                POLICY_PATH.read_bytes(),
                VERIFIER_PATH.read_bytes() + b"\n# canary\n",
            )

    def test_incremental_policy_declares_local_use_boundary(self) -> None:
        policy = json.loads(POLICY_PATH.read_text(encoding="utf-8"))
        classification = policy["classification"]
        self.assertIn("immediate syntactic callee", classification["localDirectInvocation"])
        self.assertIn("bare argument", classification["functionValueEscape"])
        self.assertEqual(classification["unsupportedOrAmbiguous"], "fail-closed")
        self.assertIn(
            "general Swift type-system",
            policy["verificationBoundary"]["doesNotClaim"],
        )

    def test_mapping_change_requires_coordinated_regeneration(self) -> None:
        with self.assertRaisesRegex(
            drift.DriftError,
            "source mapping changed.*coordinated evidence regeneration",
        ):
            drift.compare_worktree_semantics(
                manifest=self.manifest,
                mapping_bytes=self.mapping_bytes + b"\n",
                generator_bytes=self.generator_bytes,
                current_sources=self.sources,
                historical_sources=self.historical_sources,
            )

    def test_old_gate_rejects_but_incremental_gate_accepts_unrelated_view_change(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="chapterflow-ios-incremental-repro."
        ) as temporary:
            clone = Path(temporary) / "repo"
            subprocess.run(
                [
                    "git", "clone", "--quiet", "--shared", "--no-checkout",
                    str(REPO_ROOT), str(clone),
                ],
                check=True,
            )
            head = subprocess.run(
                ["git", "rev-parse", "HEAD"],
                cwd=REPO_ROOT,
                check=True,
                stdout=subprocess.PIPE,
                text=True,
            ).stdout.strip()
            subprocess.run(
                ["git", "checkout", "--quiet", "--detach", head],
                cwd=clone,
                check=True,
            )
            for relative_path in (
                Path(drift.INCREMENTAL_POLICY_PATH),
                Path(drift.INCREMENTAL_VERIFIER_PATH),
            ):
                destination = clone / relative_path
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes((REPO_ROOT / relative_path).read_bytes())
            relative = (
                "Packages/LibraryFeature/Sources/LibraryFeature/Views/Components/"
                "BookCoverView.swift"
            )
            target = clone / relative
            source = target.read_text(encoding="utf-8")
            target.write_text(
                source.replace(
                    "        .accessibilityHidden(true)\n",
                    "        .accessibilityHidden(true)\n        .opacity(1)\n",
                    1,
                ),
                encoding="utf-8",
            )
            input_paths = inventory.revision_generation_input_paths(
                clone,
                self.manifest["iosSourceRevision"],
            )
            with self.assertRaisesRegex(
                inventory.InventoryError,
                r"(?:production Swift path set differs from selected revision"
                r"|relevant worktree input differs from selected revision)",
            ):
                inventory.assert_worktree_matches_revision(
                    clone,
                    self.manifest["iosSourceRevision"],
                    input_paths,
                )
            drift.verify_current_worktree_semantics(
                clone,
                clone / MANIFEST_PATH.relative_to(REPO_ROOT),
            )

    def test_type_erased_endpoint_function_body_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/TypeErasedFunction.swift"
            ] = (
                "import Networking\n"
                "func surprise() -> Any { Endpoints.getBooks }\n"
            ).encode("utf-8")

        self.assert_sources_rejected(
            mutate,
            "current all-source producer set differs.*surprise",
        )

    def test_type_erased_endpoint_computed_property_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/TypeErasedProperty.swift"
            ] = (
                "import Networking\n"
                "struct H {\n"
                "    static var surprise: Any { Endpoints.getBooks }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(
            mutate,
            "current all-source producer set differs.*surprise",
        )

    def test_type_erased_endpoint_subscript_body_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/TypeErasedSubscript.swift"
            ] = (
                "import Networking\n"
                "struct H {\n"
                "    subscript(index: Int) -> Any { Endpoints.getBooks }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(
            mutate,
            "current all-source producer set differs.*subscript",
        )

    def test_generic_type_erased_endpoint_closure_body_fails_closed(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/GenericTypeErasure.swift"
            ] = (
                "import Networking\n"
                "typealias Producer<Value> = () -> Value\n"
                "func surprise<Value>() -> Producer<Value> {\n"
                "    { Endpoints.getBooks() as! Value }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(
            mutate,
            "Endpoint producer proof is incomplete.*surprise",
        )

    def test_multiline_trailing_endpoint_closure_initializer_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/TrailingClosureEscape.swift"
            ] = (
                "import Networking\n"
                "func retainUnknown<Value>(\n"
                "    _ value: @escaping () -> Value\n"
                ") -> () -> Value { value }\n"
                "struct H {\n"
                "    static let surprise = retainUnknown\n"
                "    {\n"
                "        Endpoints.getBooks()\n"
                "    }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(
            mutate,
            "current all-source producer set differs.*surprise|"
            "Endpoint producer proof is incomplete.*surprise",
        )

    def test_nested_endpoint_function_direct_call_then_escape_fails_closed(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/NestedFunctionEscape.swift"
            ] = (
                "import Networking\n"
                "func retainUnknown<Value>(_ value: Value) -> Value { value }\n"
                "struct H {\n"
                "    static let debug: () -> String = {\n"
                "        func local() -> Endpoint { Endpoints.getBooks() }\n"
                "        _ = local()\n"
                "        _ = retainUnknown(local)\n"
                "        return \"debug\"\n"
                "    }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(
            mutate,
            "nested Endpoint-producing function local has an unresolved escape",
        )

    def test_endpoint_factory_namespace_metatype_indirection_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/NamespaceFactory.swift"
            ] = (
                "import Networking\n"
                "struct H {\n"
                "    static let namespace = Endpoints.self\n"
                "    static let surprise = namespace.getBooks\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(
            mutate,
            "current all-source producer set differs.*surprise",
        )

    def test_local_endpoint_factory_namespace_metatype_escape_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/LocalNamespaceFactory.swift"
            ] = (
                "import Networking\n"
                "struct H {\n"
                "    static let surprise = {\n"
                "        let namespace = Endpoints.self\n"
                "        return namespace.getBooks()\n"
                "    }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(
            mutate,
            "current all-source producer set differs.*surprise",
        )

    def test_local_endpoint_factory_namespace_discarded_passes(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/DiscardedNamespaceFactory.swift"
            ] = (
                "import Networking\n"
                "struct H {\n"
                "    static let debug: () -> String = {\n"
                "        let namespace = Endpoints.self\n"
                "        _ = namespace.getBooks()\n"
                "        return \"debug\"\n"
                "    }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_accepted(mutate)

    def test_preconcurrency_import_endpoint_function_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/AttributedImport.swift"
            ] = (
                "@preconcurrency import Networking\n"
                "func surprise() -> Endpoint { Endpoints.getBooks() }\n"
            ).encode("utf-8")

        self.assert_sources_rejected(
            mutate,
            "current all-source producer set differs.*surprise",
        )

    def test_access_level_import_endpoint_function_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/AccessImport.swift"
            ] = (
                "internal import Networking\n"
                "func surprise() -> Endpoint { Endpoints.getBooks() }\n"
            ).encode("utf-8")

        self.assert_sources_rejected(
            mutate,
            "current all-source producer set differs.*surprise",
        )

    def test_concrete_carrier_function_factory_escape_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/ConcreteCarrierFunction.swift"
            ] = (
                "import Networking\n"
                "struct EndpointCarrier { let make: () -> Endpoint }\n"
                "func surprise() -> EndpointCarrier {\n"
                "    EndpointCarrier(make: Endpoints.getBooks)\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(
            mutate,
            "current all-source producer set differs.*surprise",
        )

    def test_concrete_carrier_computed_property_factory_escape_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/ConcreteCarrierProperty.swift"
            ] = (
                "import Networking\n"
                "struct EndpointCarrier { let make: () -> Endpoint }\n"
                "struct H {\n"
                "    static var surprise: EndpointCarrier {\n"
                "        EndpointCarrier(make: Endpoints.getBooks)\n"
                "    }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(
            mutate,
            "current all-source producer set differs.*surprise",
        )

    def test_concrete_carrier_local_factory_escape_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/LocalCarrierFactory.swift"
            ] = (
                "import Networking\n"
                "struct EndpointCarrier { let make: () -> Endpoint }\n"
                "func surprise() -> EndpointCarrier {\n"
                "    let make = Endpoints.getBooks\n"
                "    return EndpointCarrier(make: make)\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(
            mutate,
            "Endpoint producer proof is incomplete.*surprise|"
            "local Endpoint-producing binding make has an unresolved escape",
        )

    def test_concrete_carrier_nested_endpoint_closure_fails_closed(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/NestedCarrierClosure.swift"
            ] = (
                "import Networking\n"
                "struct EndpointCarrier { let make: () -> Endpoint }\n"
                "func surprise() -> EndpointCarrier {\n"
                "    EndpointCarrier(make: { Endpoints.getBooks() })\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(
            mutate,
            "Endpoint producer proof is incomplete.*surprise|"
            "current all-source producer set differs.*surprise",
        )

    def test_concrete_response_consuming_endpoint_request_passes(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/EndpointConsumer.swift"
            ] = (
                "import Networking\n"
                "struct Response {}\n"
                "func send(_ endpoint: Endpoint) -> Response { Response() }\n"
                "func debug() -> Response { send(Endpoints.getBooks()) }\n"
            ).encode("utf-8")

        self.assert_sources_accepted(mutate)

    def test_local_factory_async_direct_invocation_inside_return_passes(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/AsyncEndpointConsumer.swift"
            ] = (
                "import Networking\n"
                "struct Response {}\n"
                "func send(_ endpoint: Endpoint) async throws -> Response { Response() }\n"
                "func debug() async throws -> Response {\n"
                "    let make = Endpoints.getBooks\n"
                "    return try await send(make())\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_accepted(mutate)

    def test_local_factory_direct_invocation_matrix_passes(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/LocalFactoryConsumers.swift"
            ] = (
                "import Networking\n"
                "struct LocalFactoryResponse {}\n"
                "func sendSync(_ endpoint: Endpoint) -> LocalFactoryResponse { .init() }\n"
                "func sendAsync(_ endpoint: Endpoint) async throws -> LocalFactoryResponse { .init() }\n"
                "func exact() -> LocalFactoryResponse {\n"
                "    let construct = Endpoints.getBooks\n"
                "    return sendSync(construct())\n"
                "}\n"
                "func separateValue() async throws -> LocalFactoryResponse {\n"
                "    let construct = Endpoints.getBooks\n"
                "    let endpoint = construct()\n"
                "    return try await sendAsync(endpoint)\n"
                "}\n"
                "func parenthesized() -> LocalFactoryResponse {\n"
                "    let construct = Endpoints.getBooks\n"
                "    return sendSync((construct)())\n"
                "}\n"
                "func repeated(_ flag: Bool) -> LocalFactoryResponse {\n"
                "    let construct = Endpoints.getBooks\n"
                "    if flag { _ = construct() } else { _ = construct() }\n"
                "    _ = construct()\n"
                "    return sendSync(construct())\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_accepted(mutate)

    def test_local_factory_endpoint_returning_wrapper_still_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/LocalFactoryWrapper.swift"
            ] = (
                "import Networking\n"
                "func wrapper() -> Endpoint {\n"
                "    let construct = Endpoints.getBooks\n"
                "    return construct()\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(
            mutate,
            "current all-source producer set differs.*wrapper",
        )

    def test_generic_identity_alias_endpoint_property_fails(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/IdentityEndpoint.swift"
            ] = (
                "import Networking\n"
                "typealias Identity<Value> = Value\n"
                "struct H {\n"
                "    static let surprise: Identity<Endpoint> =\n"
                "        unsafeBitCast(0, to: Endpoint.self)\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_rejected(
            mutate,
            "current all-source producer set differs.*surprise",
        )

    def test_generic_identity_alias_non_endpoint_property_passes(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/IdentityString.swift"
            ] = (
                "typealias Identity<Value> = Value\n"
                "struct H { static let debug: Identity<String> = \"debug\" }\n"
            ).encode("utf-8")

        self.assert_sources_accepted(mutate)

    def test_type_erased_callable_discarded_endpoint_side_effect_passes(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/ErasedSideEffect.swift"
            ] = (
                "import Networking\n"
                "func debug() -> Any {\n"
                "    _ = Endpoints.getBooks()\n"
                "    return \"debug\"\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_accepted(mutate)

    def test_protocol_associatedtype_named_endpoint_passes(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/AssociatedTypeShadow.swift"
            ] = (
                "import Networking\n"
                "protocol LocalProvider {\n"
                "    associatedtype Endpoint\n"
                "}\n"
                "extension LocalProvider {\n"
                "    static var debug: () -> Endpoint { { fatalError() } }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_accepted(mutate)

    def test_extension_inherited_generic_parameter_named_endpoint_passes(self) -> None:
        def mutate(candidate) -> None:
            candidate[
                "Packages/LibraryFeature/Sources/LibraryFeature/ExtensionGenericShadow.swift"
            ] = (
                "import Networking\n"
                "struct GenericHolder<Endpoint> {}\n"
                "extension GenericHolder {\n"
                "    var debug: () -> Endpoint { { fatalError() } }\n"
                "}\n"
            ).encode("utf-8")

        self.assert_sources_accepted(mutate)

    def test_current_unmodified_worktree_passes(self) -> None:
        drift.verify_current_worktree_semantics(REPO_ROOT, MANIFEST_PATH)


class IOSLocalFunctionValueUseClassifierCanaries(unittest.TestCase):
    def assert_roles(
        self,
        source: str,
        expected: list[str],
        *,
        symbol: str = "construct",
    ) -> None:
        uses = drift._classify_local_function_value_uses(source, symbol)
        self.assertEqual([use.role for use in uses], expected)

    def test_immediate_callee_forms_are_direct_invocations(self) -> None:
        direct_sources = {
            "plain": "construct()",
            "try": "try construct()",
            "optional_try": "try? construct()",
            "forced_try": "try! construct()",
            "await": "await construct()",
            "try_await": "try await construct()",
            "nested_argument": "return send(construct())",
            "async_nested_argument": "return try await send(construct())",
            "local_result": "let endpoint = construct()\nreturn send(endpoint)",
            "parenthesized": "return send((construct)())",
        }
        for label, source in direct_sources.items():
            with self.subTest(label=label):
                self.assert_roles(source, ["direct_invocation"])

    def test_every_occurrence_must_be_a_direct_invocation(self) -> None:
        self.assert_roles(
            "_ = construct()\nlet first = construct()\nreturn send(construct())",
            ["direct_invocation"] * 3,
        )
        self.assert_roles(
            "if flag { construct() } else { return send(construct()) }",
            ["direct_invocation", "direct_invocation"],
        )
        self.assert_roles(
            "let count = 1\n"
            "if flag &&\n"
            "    otherFlag\n"
            "{\n"
            "    construct()\n"
            "}",
            ["direct_invocation"],
        )

    def test_bare_value_roles_fail_closed_as_escapes(self) -> None:
        escape_sources = {
            "bare_return": "return construct",
            "parenthesized_return": "return (construct)",
            "yield": "yield construct",
            "bare_argument": "consumeFactory(construct)",
            "member_storage": "self.factory = construct",
            "global_storage": "globalFactory = construct",
            "local_alias": "let other = construct",
            "collection": "let factories = [construct]",
            "tuple": "let pair = (construct, value)",
            "stored_capture": "escapingClosure = { construct() }",
            "returned_capture": "return { construct() }",
            "call_as_function": "construct.callAsFunction()",
            "returned_argument_then_call": "receiver(construct)()",
        }
        for label, source in escape_sources.items():
            with self.subTest(label=label):
                self.assert_roles(source, ["escape"])

    def test_labels_members_comments_and_strings_are_not_local_uses(self) -> None:
        self.assert_roles(
            "consume(construct: other)\n"
            "self.construct()\n"
            "// construct\n"
            "let text = \"construct\"\n",
            [],
        )

    def test_structural_role_does_not_depend_on_example_identifier(self) -> None:
        self.assert_roles(
            "return send(builder())",
            ["direct_invocation"],
            symbol="builder",
        )
        self.assert_roles(
            "consumeFactory(builder)",
            ["escape"],
            symbol="builder",
        )


class IOSHistoricalManifestProvenanceCanaries(unittest.TestCase):
    def test_historical_manifest_reproduces_exactly(self) -> None:
        drift.verify_historical_manifest(REPO_ROOT, MANIFEST_PATH)

    def test_tampered_committed_manifest_fails(self) -> None:
        manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
        manifest["operationKeyCount"] = 82
        with tempfile.TemporaryDirectory(
            prefix="chapterflow-ios-manifest-tamper."
        ) as temporary:
            candidate = Path(temporary) / MANIFEST_PATH.name
            candidate.write_text(
                json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(
                drift.DriftError,
                "committed iOS inventory manifest does not reproduce",
            ):
                drift.verify_historical_manifest(REPO_ROOT, candidate)

    def test_missing_historical_revision_fails(self) -> None:
        manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
        manifest["iosSourceRevision"] = "0" * 40
        with tempfile.TemporaryDirectory(
            prefix="chapterflow-ios-manifest-missing-revision."
        ) as temporary:
            candidate = Path(temporary) / MANIFEST_PATH.name
            candidate.write_text(
                json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(
                drift.DriftError,
                "historical iOS source revision does not exist",
            ):
                drift.verify_historical_manifest(REPO_ROOT, candidate)

    def test_shallow_ios_history_fails(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="chapterflow-ios-shallow-history."
        ) as temporary:
            clone = Path(temporary) / "repo"
            subprocess.run(
                [
                    "git", "clone", "--quiet", "--shared", "--no-checkout",
                    str(REPO_ROOT), str(clone),
                ],
                check=True,
            )
            head = subprocess.run(
                ["git", "rev-parse", "HEAD"],
                cwd=REPO_ROOT,
                check=True,
                stdout=subprocess.PIPE,
                text=True,
            ).stdout.strip()
            subprocess.run(
                ["git", "checkout", "--quiet", "--detach", head],
                cwd=clone,
                check=True,
            )
            (clone / ".git" / "shallow").write_text(head + "\n", encoding="utf-8")
            with self.assertRaisesRegex(
                drift.DriftError,
                "requires non-shallow Git history",
            ):
                drift.verify_historical_manifest(
                    clone,
                    clone / MANIFEST_PATH.relative_to(REPO_ROOT),
                )

    def test_missing_historical_generator_object_fails(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="chapterflow-ios-missing-history-input."
        ) as temporary:
            repo = Path(temporary) / "repo"
            repo.mkdir()
            subprocess.run(["git", "init", "--quiet"], cwd=repo, check=True)
            (repo / "README.md").write_text("fixture\n", encoding="utf-8")
            subprocess.run(["git", "add", "README.md"], cwd=repo, check=True)
            subprocess.run(
                [
                    "git", "-c", "user.name=Contract Canary", "-c",
                    "user.email=contract-canary", "commit", "--quiet",
                    "-m", "fixture",
                ],
                cwd=repo,
                check=True,
            )
            revision = subprocess.run(
                ["git", "rev-parse", "HEAD"],
                cwd=repo,
                check=True,
                stdout=subprocess.PIPE,
                text=True,
            ).stdout.strip()
            manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
            manifest["iosSourceRevision"] = revision
            candidate = Path(temporary) / MANIFEST_PATH.name
            candidate.write_text(
                json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(
                drift.DriftError,
                "missing required input",
            ):
                drift.verify_historical_manifest(repo, candidate)

    def test_backend_manifest_one_byte_mismatch_fails(self) -> None:
        expected = MANIFEST_PATH.read_bytes()
        actual = expected[:-2] + b" \n"
        with self.assertRaisesRegex(
            drift.DriftError,
            "backend manifest copy is not byte-identical",
        ):
            drift.assert_byte_identical(
                "backend manifest copy",
                expected,
                actual,
            )


if __name__ == "__main__":
    unittest.main()
