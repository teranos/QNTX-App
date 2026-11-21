import Foundation

public struct SharedImage: Codable, Equatable {
    public let id: String
    public let name: String
    public let mime: String
    public let bytes: Int
}

public struct SharedBatch: Codable, Equatable {
    public let id: String
    public let createdAt: Double // Unix milliseconds, matching the web's Date.
    public let note: String
    public let images: [SharedImage]
}

public enum InboxFailure: LocalizedError {
    case invalid(String)
    public var errorDescription: String? {
        switch self { case .invalid(let reason): return reason }
    }
}

/// Immutable, complete batches only. Listing and reading never consume a share.
/// A draft is published by one directory rename, on the same filesystem.
public final class Inbox {
    public static let group = "group.nl.sbvh.qntx"
    public static let maxImages = 10
    public static let maxImageBytes = 10 * 1024 * 1024
    public static let maxBatchBytes = 50 * 1024 * 1024
    private let root: URL
    private let files = FileManager.default

    public init(root: URL) throws {
        self.root = root
        try files.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func location(_ id: String) throws -> URL {
        guard UUID(uuidString: id)?.uuidString == id else {
            throw InboxFailure.invalid("Invalid share identifier")
        }
        return root.appendingPathComponent(id, isDirectory: true)
    }

    public func list() throws -> [SharedBatch] {
        try files.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            .map { url in
                let manifest = try JSONDecoder().decode(SharedBatch.self, from: Data(contentsOf: url.appendingPathComponent("batch.json")))
                guard manifest.id == url.lastPathComponent else { throw InboxFailure.invalid("Share manifest does not match its directory") }
                return manifest
            }
            .sorted { $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt < $1.createdAt }
    }

    public func read(id: String, imageId: String) throws -> (SharedImage, Data) {
        let folder = try location(id)
        let batch = try JSONDecoder().decode(SharedBatch.self, from: Data(contentsOf: folder.appendingPathComponent("batch.json")))
        guard UUID(uuidString: imageId)?.uuidString == imageId,
              let image = batch.images.first(where: { $0.id == imageId }) else {
            throw InboxFailure.invalid("Image does not belong to this share")
        }
        let data = try Data(contentsOf: folder.appendingPathComponent(image.id))
        guard data.count == image.bytes, data.count <= Self.maxImageBytes else {
            throw InboxFailure.invalid("Shared image size does not match its manifest")
        }
        return (image, data)
    }

    /// Call only after durable import/delivery, or an explicit user discard.
    /// Retrying an acknowledgement is harmless; other batches are untouched.
    public func acknowledge(id: String) throws {
        let folder = try location(id)
        if files.fileExists(atPath: folder.path) { try files.removeItem(at: folder) }
    }

    public func begin(note: String) throws -> Draft {
        guard note.utf8.count <= 16_384 else { throw InboxFailure.invalid("The note is too long") }
        return try Draft(root: root, note: note)
    }
}

public final class Draft {
    private let id: String
    private let root: URL
    private let folder: URL
    private let note: String
    private var images: [SharedImage] = []
    private var bytes = 0
    private var finished = false

    fileprivate init(root: URL, note: String) throws {
        let identifier = UUID().uuidString
        self.id = identifier
        self.root = root
        self.note = note
        folder = root.appendingPathComponent(".pending-" + identifier, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    }

    public func append(data: Data, name: String, mime: String) throws {
        guard !finished else { throw InboxFailure.invalid("Share is already finished") }
        guard images.count < Inbox.maxImages, !data.isEmpty, data.count <= Inbox.maxImageBytes,
              data.count <= Inbox.maxBatchBytes - bytes else {
            throw InboxFailure.invalid("Share at most 10 images, 10 MiB each and 50 MiB in total")
        }
        guard mime == "image/png" || mime == "image/jpeg" else {
            throw InboxFailure.invalid("Only PNG and JPEG screenshots are supported")
        }
        let image = SharedImage(id: UUID().uuidString, name: String(name.prefix(255)), mime: mime, bytes: data.count)
        try data.write(to: folder.appendingPathComponent(image.id), options: .atomic)
        images.append(image)
        bytes += data.count
    }

    @discardableResult public func publish() throws -> SharedBatch {
        guard !finished, !images.isEmpty else { throw InboxFailure.invalid("Share has no images or is already finished") }
        let batch = SharedBatch(id: id, createdAt: Date().timeIntervalSince1970 * 1000, note: note, images: images)
        try JSONEncoder().encode(batch).write(to: folder.appendingPathComponent("batch.json"), options: .atomic)
        try FileManager.default.moveItem(at: folder, to: root.appendingPathComponent(id, isDirectory: true))
        finished = true
        return batch
    }

    public func cancel() throws {
        if !finished {
            try FileManager.default.removeItem(at: folder)
            finished = true
        }
    }
}
