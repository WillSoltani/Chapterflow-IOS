import UIKit
import SwiftUI
import MobileCoreServices
import UniformTypeIdentifiers

/// Root view controller for the Action Extension ("Ask ChapterFlow about this").
///
/// Reads the selected text from the action's `NSExtensionItem` payload and embeds
/// `ActionView` (SwiftUI) via `UIHostingController`. Saves the text as an ask-query
/// item in the App Group outbox and then opens the main app via a deep link.
/// Never imports or opens the main SwiftData store (RF4).
final class ActionViewController: UIViewController {

    private var hostingController: UIHostingController<ActionView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        loadSelectedText()
    }

    // MARK: - Text extraction

    private func loadSelectedText() {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem else {
            presentActionView(selectedText: nil, sourceTitle: nil)
            return
        }

        let providers = item.attachments ?? []
        let sourceTitle = item.attributedTitle?.string
            ?? item.attributedContentText?.string

        let textType = UTType.plainText.identifier

        if let textProvider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(textType) }) {
            textProvider.loadItem(forTypeIdentifier: textType) { [weak self] itemValue, _ in
                let text = itemValue as? String
                DispatchQueue.main.async {
                    self?.presentActionView(selectedText: text, sourceTitle: sourceTitle)
                }
            }
        } else {
            presentActionView(selectedText: nil, sourceTitle: sourceTitle)
        }
    }

    private func presentActionView(selectedText: String?, sourceTitle: String?) {
        let actionView = ActionView(
            selectedText: selectedText,
            sourceTitle: sourceTitle,
            onAsk: { [weak self] in self?.performAsk(text: selectedText ?? "", sourceTitle: sourceTitle) },
            onCancel: { [weak self] in self?.dismissExtension() },
            onOpenApp: { [weak self] in self?.openApp(text: nil) }
        )

        if let existing = hostingController {
            existing.rootView = actionView
        } else {
            let hc = UIHostingController(rootView: actionView)
            addChild(hc)
            hc.view.frame = view.bounds
            hc.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            hc.view.backgroundColor = .clear
            view.addSubview(hc.view)
            hc.didMove(toParent: self)
            hostingController = hc
        }
    }

    // MARK: - Actions

    private func performAsk(text: String, sourceTitle: String?) {
        guard !text.isEmpty else {
            dismissExtension()
            return
        }

        // Write query to the App Group outbox so the main app can display it.
        let item = ExtensionItem(
            id: UUID().uuidString,
            kind: .askQuery,
            text: text,
            userNote: nil,
            sourceTitle: sourceTitle,
            sourceURL: nil,
            createdAt: Date()
        )
        writeToOutbox(item)

        // Open the main app. The outbox banner will confirm the save.
        openApp(text: text)
    }

    private func openApp(text: String?) {
        // Encode the selected text into the deep link so the main app can pre-fill
        // an Ask query if a book is open.
        var urlString = "chapterflow://home"
        if let text, !text.isEmpty,
           let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            urlString = "chapterflow://ask?text=\(encoded)"
        }

        guard let url = URL(string: urlString) else {
            dismissExtension()
            return
        }
        extensionContext?.open(url) { [weak self] _ in
            self?.dismissExtension()
        }
    }

    private func dismissExtension() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}
