import Foundation
import XCTest
@testable import InboxCore

final class InboxTests: XCTestCase {
    private func withInbox(_ run: (Inbox, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let inbox = try Inbox(root: root)
        defer { do { try FileManager.default.removeItem(at: root) } catch { XCTFail("Cleanup failed: \(error)") } }
        try run(inbox, root)
    }

    func testBatchSurvivesRestartInOrderUntilAcknowledged() throws {
        try withInbox { inbox, root in
            let draft = try inbox.begin(note: "I like this navigation")
            try draft.append(data: Data([1, 2]), name: "first.png", mime: "image/png")
            try draft.append(data: Data([3]), name: "second.jpg", mime: "image/jpeg")
            XCTAssertTrue(try inbox.list().isEmpty)
            let saved = try draft.publish()
            let restarted = try Inbox(root: root)
            XCTAssertEqual(try restarted.list(), [saved])
            XCTAssertEqual(saved.images.map(\.name), ["first.png", "second.jpg"])
            let image = try XCTUnwrap(saved.images.first)
            XCTAssertEqual(try restarted.read(id: saved.id, imageId: image.id).1, Data([1, 2]))
            XCTAssertEqual(try restarted.list(), [saved])
            try restarted.acknowledge(id: saved.id)
            try restarted.acknowledge(id: saved.id)
            XCTAssertTrue(try restarted.list().isEmpty)
        }
    }

    func testCancellationAndInterruptedDraftsNeverAppear() throws {
        try withInbox { inbox, root in
            let draft = try inbox.begin(note: "")
            try draft.append(data: Data([1]), name: "a.png", mime: "image/png")
            XCTAssertTrue(try Inbox(root: root).list().isEmpty)
            try draft.cancel()
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        }
    }

    func testBadIdentifiersAndCrossBatchReadsAreRejected() throws {
        try withInbox { inbox, _ in
            XCTAssertThrowsError(try inbox.acknowledge(id: "../outside"))
            let first = try inbox.begin(note: "")
            try first.append(data: Data([1]), name: "../name-is-not-a-path.png", mime: "image/png")
            let a = try first.publish()
            let second = try inbox.begin(note: "")
            try second.append(data: Data([2]), name: "b.png", mime: "image/png")
            let b = try second.publish()
            let image = try XCTUnwrap(a.images.first)
            XCTAssertThrowsError(try inbox.read(id: b.id, imageId: image.id))
            try inbox.acknowledge(id: a.id)
            XCTAssertEqual(try inbox.list(), [b])
        }
    }

    func testLimitsAndEmptyBatchAreRejected() throws {
        try withInbox { inbox, _ in
            let draft = try inbox.begin(note: "")
            XCTAssertThrowsError(try draft.publish())
            XCTAssertThrowsError(try draft.append(data: Data(), name: "empty.png", mime: "image/png"))
            XCTAssertThrowsError(try draft.append(data: Data([1]), name: "bad.gif", mime: "image/gif"))
            XCTAssertThrowsError(try draft.append(data: Data(repeating: 0, count: Inbox.maxImageBytes + 1), name: "large.png", mime: "image/png"))
            for _ in 0..<Inbox.maxImages {
                try draft.append(data: Data([1]), name: "a.png", mime: "image/png")
            }
            XCTAssertThrowsError(try draft.append(data: Data([1]), name: "extra.png", mime: "image/png"))
            try draft.cancel()
        }
    }

    func testBatchByteLimitAndCorruptionAreVisible() throws {
        try withInbox { inbox, root in
            let draft = try inbox.begin(note: "")
            for _ in 0..<5 {
                try draft.append(data: Data(repeating: 0, count: Inbox.maxImageBytes), name: "a.png", mime: "image/png")
            }
            XCTAssertThrowsError(try draft.append(data: Data([1]), name: "extra.png", mime: "image/png"))
            let batch = try draft.publish()
            let image = try XCTUnwrap(batch.images.first)
            try Data([1]).write(to: root.appendingPathComponent(batch.id).appendingPathComponent(image.id))
            XCTAssertThrowsError(try inbox.read(id: batch.id, imageId: image.id))
            try Data("invalid".utf8).write(to: root.appendingPathComponent(batch.id).appendingPathComponent("batch.json"))
            XCTAssertThrowsError(try inbox.list())
        }
    }
}
