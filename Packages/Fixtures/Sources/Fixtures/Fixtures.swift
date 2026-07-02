/// Fixtures — pre-decoded sample data for every SwiftUI `#Preview` and unit test.
///
/// All static properties are lazily decoded from JSON resource files bundled with
/// this module. Decoding failures are intentional `fatalError`s: a broken fixture
/// file is a programming error that must be caught during development, not silently
/// swallowed at runtime.
///
/// Usage:
/// ```swift
/// #Preview {
///     ReaderView(chapter: Fixtures.chapterEMH.chapter)
/// }
/// ```
///
/// Or inject the full set via `PreviewDependencies.shared`.

import Foundation
import Models

public enum Fixtures {

    // MARK: - JSON loader

    static func load<T: Decodable>(_ filename: String) -> T {
        guard let url = Bundle.module.url(forResource: filename, withExtension: "json") else {
            fatalError("Fixtures: missing resource '\(filename).json'")
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder.chapterFlow.decode(T.self, from: data)
        } catch {
            fatalError("Fixtures: failed to decode '\(filename).json': \(error)")
        }
    }

    /// Returns raw `Data` for a fixture JSON file. Used by evolution tests that
    /// mutate the JSON before re-decoding it. `@testable import Fixtures` required.
    static func rawData(_ filename: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: filename, withExtension: "json") else {
            struct MissingFixture: Error { let name: String }
            throw MissingFixture(name: filename)
        }
        return try Data(contentsOf: url)
    }
}
