import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// Root view controller for the Share Extension.
///
/// Embeds `ShareView` (SwiftUI) inside a `UIHostingController`.  Receives the
/// shared `NSExtensionItem` payloads (text, URL, web page) and passes them to the
/// SwiftUI layer.  Never imports or opens the main SwiftData store (RF4).
final class ShareViewController: UIViewController {

    private var hostingController: UIHostingController<ShareView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        loadSharedContent()
    }

    // MARK: - Shared content extraction

    private func loadSharedContent() {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem else {
            presentShareView(text: nil, url: nil, sourceTitle: nil)
            return
        }

        let providers = item.attachments ?? []
        let title = item.attributedContentText?.string
            ?? item.attributedTitle?.string

        // Prefer URL over plain text when both are present.
        let urlType = UTType.url.identifier
        let textType = UTType.plainText.identifier
        let webpageType = "public.url"

        if let urlProvider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(urlType) || $0.hasItemConformingToTypeIdentifier(webpageType) }) {
            let typeId = urlProvider.hasItemConformingToTypeIdentifier(urlType) ? urlType : webpageType
            urlProvider.loadItem(forTypeIdentifier: typeId) { [weak self] item, _ in
                let urlString: String?
                if let url = item as? URL {
                    urlString = url.absoluteString
                } else if let str = item as? String {
                    urlString = str
                } else {
                    urlString = nil
                }
                DispatchQueue.main.async {
                    self?.presentShareView(text: nil, url: urlString, sourceTitle: title)
                }
            }
        } else if let textProvider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(textType) }) {
            textProvider.loadItem(forTypeIdentifier: textType) { [weak self] item, _ in
                let text = item as? String
                DispatchQueue.main.async {
                    self?.presentShareView(text: text, url: nil, sourceTitle: title)
                }
            }
        } else {
            presentShareView(text: nil, url: nil, sourceTitle: title)
        }
    }

    private func presentShareView(text: String?, url: String?, sourceTitle: String?) {
        let shareView = ShareView(
            sharedText: text,
            sharedURL: url,
            sourceTitle: sourceTitle,
            onSave: { [weak self] in self?.dismiss(saved: true) },
            onCancel: { [weak self] in self?.dismiss(saved: false) },
            onOpenApp: { [weak self] in self?.openApp() }
        )

        if let existing = hostingController {
            existing.rootView = shareView
        } else {
            let hc = UIHostingController(rootView: shareView)
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

    private func dismiss(saved: Bool) {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    private func openApp() {
        guard let url = URL(string: "chapterflow://notebook") else {
            extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
            return
        }
        extensionContext?.open(url) { [weak self] _ in
            self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }
}
