import Testing
import Foundation
@testable import Persistence

// MARK: - ExtensionOutboxTests

@Suite("ExtensionOutbox")
struct ExtensionOutboxTests {

    private func makeOutbox() -> ExtensionOutbox {
        // Use a unique suite name per test to avoid cross-test interference.
        ExtensionOutbox(suiteName: "test.outbox.\(UUID().uuidString)")
    }

    @Test("Empty outbox returns empty array")
    func emptyOutboxIsEmpty() {
        let outbox = makeOutbox()
        #expect(outbox.readAll().isEmpty)
    }

    @Test("Write and readAll round-trips a single item")
    func writeSingleItem() {
        let outbox = makeOutbox()
        let item = PendingExtensionItem(kind: .text, text: "Hello, ChapterFlow")
        outbox.write(item)

        let all = outbox.readAll()
        #expect(all.count == 1)
        #expect(all[0].text == "Hello, ChapterFlow")
        #expect(all[0].kind == .text)
    }

    @Test("Write multiple items preserves insertion order")
    func writeMultipleItems() {
        let outbox = makeOutbox()
        let a = PendingExtensionItem(kind: .text, text: "first")
        let b = PendingExtensionItem(kind: .link, text: "https://example.com")
        let c = PendingExtensionItem(kind: .askQuery, text: "What is the main theme?")
        outbox.write(a)
        outbox.write(b)
        outbox.write(c)

        let all = outbox.readAll()
        #expect(all.count == 3)
        #expect(all[0].text == "first")
        #expect(all[1].kind == .link)
        #expect(all[2].kind == .askQuery)
    }

    @Test("Clear empties the outbox")
    func clearEmptiesOutbox() {
        let outbox = makeOutbox()
        outbox.write(PendingExtensionItem(kind: .text, text: "to be removed"))
        outbox.clear()
        #expect(outbox.readAll().isEmpty)
    }

    @Test("Optional fields round-trip correctly")
    func optionalFieldRoundTrip() {
        let outbox = makeOutbox()
        let item = PendingExtensionItem(
            kind: .link,
            text: "https://example.com/article",
            userNote: "Read this",
            sourceTitle: "Example Domain",
            sourceURL: "https://example.com/article"
        )
        outbox.write(item)

        let read = outbox.readAll().first
        #expect(read?.userNote == "Read this")
        #expect(read?.sourceTitle == "Example Domain")
        #expect(read?.sourceURL == "https://example.com/article")
    }

    @Test("PendingExtensionItem.Kind covers all expected cases")
    func kindCoverage() {
        let kinds: [PendingExtensionItem.Kind] = [.text, .link, .askQuery]
        #expect(kinds.count == 3)
        for kind in kinds {
            let item = PendingExtensionItem(kind: kind, text: "test")
            let outbox = makeOutbox()
            outbox.write(item)
            let read = outbox.readAll().first
            #expect(read?.kind == kind)
        }
    }

    @Test("Corrupt data in UserDefaults falls back to empty array")
    func corruptDataFallback() {
        let suiteName = "test.corrupt.\(UUID().uuidString)"
        let outbox = ExtensionOutbox(suiteName: suiteName)
        // Manually write garbage bytes under the outbox key.
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(Data([0xFF, 0x00, 0xAB]), forKey: ExtensionOutbox.outboxKey)

        #expect(outbox.readAll().isEmpty)
    }
}
