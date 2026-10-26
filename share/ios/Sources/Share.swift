import Foundation
import InboxCore
import SwiftRs
import Tauri

struct ShareID: Decodable { let id: String }
struct ImageID: Decodable { let id: String; let imageId: String }

class Share: Plugin {
    // Serialize reads and acknowledgements, off the main/UI thread.
    private let work = DispatchQueue(label: "nl.sbvh.qntx.share-inbox")

    private func inbox() throws -> Inbox {
        guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Inbox.group) else {
            throw InboxFailure.invalid("QNTX's shared container is unavailable; check App Group signing")
        }
        return try Inbox(root: group.appendingPathComponent("ShareInbox", isDirectory: true))
    }

    @objc public func pending(_ invoke: Invoke) {
        work.async {
            do {
                let batches = try self.inbox().list()
                let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(batches))
                invoke.resolve(["batches": json])
            } catch { invoke.reject("Cannot list shared screenshots: \(error.localizedDescription)") }
        }
    }

    @objc public func readImage(_ invoke: Invoke) throws {
        let args = try invoke.parseArgs(ImageID.self)
        work.async {
            do {
                let (image, bytes) = try self.inbox().read(id: args.id, imageId: args.imageId)
                invoke.resolve(["mime": image.mime, "base64": bytes.base64EncodedString()])
            } catch { invoke.reject("Cannot read shared screenshot: \(error.localizedDescription)") }
        }
    }

    @objc public func acknowledge(_ invoke: Invoke) throws {
        let args = try invoke.parseArgs(ShareID.self)
        work.async {
            do {
                try self.inbox().acknowledge(id: args.id)
                invoke.resolve()
            } catch { invoke.reject("Cannot acknowledge shared screenshots: \(error.localizedDescription)") }
        }
    }
}

@_cdecl("init_share")
func initPlugin() -> Plugin { Share() }
