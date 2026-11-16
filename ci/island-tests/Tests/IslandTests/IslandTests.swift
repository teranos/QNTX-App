// "cant we make it easier on me, in terms of being able to test most testable mechanical things, before its like, live on my phone ??"
//
// What the island decides, tested in the iPhone Simulator before any build
// reaches a phone: the failures it makes, what a press may ask, and how a
// press is drawn and held.

import SacredError
import XCTest

@testable import Island

final class EveryFailureIsASacredError: XCTestCase {
    func testAFailureSaysWhatWhyWhereAndAt() {
        let error = Island.failed("the node was not reached", "the network is down", region: "node", severity: .warn)
        XCTAssertEqual(error.title, "the node was not reached")
        XCTAssertEqual(error.why, "the network is down")
        XCTAssertEqual(error.severity, .warn)
        XCTAssertEqual(error.context, Context(surface: "island", region: "node"))
        XCTAssertEqual(error.source, "swift")
        XCTAssertTrue(error.id.hasPrefix("err-island-"))
        XCTAssertTrue(error.location?.contains("IslandTests.swift") == true, "it does not say where it was made: \(String(describing: error.location))")
        XCTAssertFalse(error.at.isEmpty)
    }

    func testEachFailureIsItsOwn() {
        let one = Island.failed("t", "w", region: "node")
        let two = Island.failed("t", "w", region: "node")
        XCTAssertNotEqual(one.id, two.id)
    }

    // What another layer threw keeps what it said and what it is.
    func testWhatAnotherLayerThrewIsMadeTheIslands() {
        let thrown = URLError(.notConnectedToInternet)
        let error = Island.failed("the node was not reached", from: thrown, region: "node")
        XCTAssertEqual(error.why, thrown.localizedDescription)
        XCTAssertTrue(error.raw?.contains("URLError") == true)
    }

    // One that is already the island's stays the one it is, and is not made twice.
    func testASacredErrorStaysTheOneItIs() {
        let made = Island.failed("t", "w", region: "node")
        XCTAssertEqual(Island.failed("another", from: made, region: "press"), made)
    }
}

final class APressAsksTheNodeAndNothingElse: XCTestCase {
    func testAPathOutsideTheNodesAPIIsRefused() async {
        for path in ["/auth/logout", "/api/../auth/logout", "/api//evil", "https://evil.example/api/x", "/api/x@evil"] {
            do {
                try await waitsNodeIsAsked(path, [:])
                XCTFail("\(path) was asked")
            } catch let error as SacredError {
                XCTAssertEqual(error.title, "a press asked outside the node", path)
            } catch {
                XCTFail("\(path) failed with what is no SacredError: \(error)")
            }
        }
    }

    // The test bundle names no node, as a build that names none: it says so, as the island's.
    func testABuildThatNamesNoNodeSaysSo() async {
        do {
            try await waitsNodeIsAsked("/api/phones", [:])
            XCTFail("a build that names no node asked one")
        } catch let error as SacredError {
            XCTAssertEqual(error.title, "this build names no node")
            XCTAssertEqual(error.context.region, "node")
        } catch {
            XCTFail("it failed with what is no SacredError: \(error)")
        }
    }
}

final class APressIsDrawnAndHeld: XCTestCase {
    // One mark for each kind of press, wherever it stands, and none mistaken for another.
    func testEachPressHasItsOwnMark() {
        let marks = ["approve", "delay", "cancel"].map(markOf)
        XCTAssertEqual(Set(marks).count, 3)
        XCTAssertEqual(markOf("approve"), "checkmark")
        XCTAssertEqual(markOf("cancel"), "nosign")
        XCTAssertEqual(markOf("something new"), "questionmark.square.dashed")
    }

    // What a press asks is one thing to compare, whatever order its fields were sent in.
    func testWhatAPressAsksIsTheSameHoweverItWasSent() {
        let one = WaitsPress(says: "cancel", does: "cancel", then: "canceled", path: "/api/collected/cancel",
                             sent: ["to": "did:key:z6Mkbirch", "drawn": "abc"], armed: true)
        var other = one
        other.sent = ["drawn": "abc", "to": "did:key:z6Mkbirch"]
        XCTAssertEqual(one.asks, other.asks)
        XCTAssertEqual(one.asks, "/api/collected/cancel?drawn=abc&to=did:key:z6Mkbirch")
        other.sent["drawn"] = "changed"
        XCTAssertNotEqual(one.asks, other.asks, "a press drawn with other things asks the same")
    }

    // A second tap while the first is asked asks nothing: one press of one thing at a time.
    func testASecondTapIsHeldWhileTheFirstIsAsked() {
        XCTAssertTrue(PressesInHand.take("activity-1"))
        XCTAssertFalse(PressesInHand.take("activity-1"), "a second tap was let through")
        XCTAssertTrue(PressesInHand.take("activity-2"), "a press of another thing was held")
        PressesInHand.give("activity-1")
        PressesInHand.give("activity-2")
        XCTAssertTrue(PressesInHand.take("activity-1"), "a press given back was not let go")
        PressesInHand.give("activity-1")
    }
}
