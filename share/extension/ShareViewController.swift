import UIKit
import Social
import UniformTypeIdentifiers
import ImageIO
import InboxCore

/// An offline handoff, never an agent request. The containing app owns identity
/// and destination selection. No credentials or network client live here.
final class ShareViewController: SLComposeServiceViewController {
    private var providers: [NSItemProvider] = []
    private let work = DispatchQueue(label: "nl.sbvh.qntx.share-import")

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Save to QNTX"
        placeholder = "What do you like about this UI? (optional)"
        providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
        validateContent()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        navigationController?.navigationBar.topItem?.rightBarButtonItem?.title = "Save"
    }

    override func configurationItems() -> [Any]! {
        guard let destination = SLComposeSheetConfigurationItem() else { return [] }
        destination.title = "Agent"
        destination.value = "Choose in QNTX after saving"
        return [destination]
    }

    override func isContentValid() -> Bool {
        !providers.isEmpty && providers.count <= Inbox.maxImages &&
            providers.allSatisfy { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) } &&
            (contentText ?? "").utf8.count <= 16_384
    }

    override func didSelectPost() {
        guard isContentValid() else { fail(InboxFailure.invalid("Share between 1 and 10 images")); return }
        let note = contentText ?? ""
        let items = providers
        work.async {
            do {
                guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Inbox.group) else {
                    throw InboxFailure.invalid("QNTX's shared container is unavailable; check App Group signing")
                }
                let inbox = try Inbox(root: group.appendingPathComponent("ShareInbox", isDirectory: true))
                let draft = try inbox.begin(note: note)
                self.load(items: items, index: 0, draft: draft)
            } catch { self.fail(error) }
        }
    }

    // Providers are loaded sequentially. Copy bytes while the provider's file
    // URL is valid; it may be deleted as soon as the completion handler returns.
    private func load(items: [NSItemProvider], index: Int, draft: Draft) {
        if index == items.count {
            do {
                try draft.publish()
                DispatchQueue.main.async {
                    self.extensionContext?.completeRequest(returningItems: nil)
                }
            } catch { abort(draft, because: error) }
            return
        }
        let provider = items[index]
        provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, error in
            let loaded: Result<(Data, String, String), Error> = Result {
                if let error = error { throw error }
                guard let url = url else { throw InboxFailure.invalid("The source app supplied no image file") }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
                guard let size = size, size > 0, size <= Inbox.maxImageBytes else {
                    throw InboxFailure.invalid("A screenshot exceeds the 10 MiB limit")
                }
                let data = try Data(contentsOf: url)
                guard data.count <= Inbox.maxImageBytes,
                      let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let type = CGImageSourceGetType(source) as String?,
                      type == UTType.png.identifier || type == UTType.jpeg.identifier else {
                    throw InboxFailure.invalid("Share PNG or JPEG screenshots")
                }
                let mime = type == UTType.png.identifier ? "image/png" : "image/jpeg"
                let name = provider.suggestedName ?? ("Screenshot-\(index + 1)" + (mime == "image/png" ? ".png" : ".jpg"))
                return (data, name, mime)
            }
            self.work.async {
                do {
                    let (data, name, mime) = try loaded.get()
                    try draft.append(data: data, name: name, mime: mime)
                    self.load(items: items, index: index + 1, draft: draft)
                } catch { self.abort(draft, because: error) }
            }
        }
    }

    private func abort(_ draft: Draft, because error: Error) {
        do { try draft.cancel(); fail(error) }
        catch let cleanup {
            fail(InboxFailure.invalid("\(error.localizedDescription). Could not remove the incomplete share: \(cleanup.localizedDescription)"))
        }
    }

    private func fail(_ error: Error) {
        DispatchQueue.main.async {
            let alert = UIAlertController(title: "Screenshots were not saved", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Close", style: .default) { _ in
                self.extensionContext?.cancelRequest(withError: error)
            })
            self.present(alert, animated: true)
        }
    }
}
