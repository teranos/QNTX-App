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

// The island against a QNTX node on the runner (.github/scripts/ci-node.py),
// in the session of a person logged in there: what it asks is what a phone
// asks, and the node does it or says why not.
final class TheIslandAgainstARealNode: XCTestCase {
    private var node: WaitsTestedAgainst!

    override func setUpWithError() throws {
        let env = ProcessInfo.processInfo.environment
        guard let at = env["QNTX_TEST_NODE"], let url = URL(string: at), let session = env["QNTX_TEST_SESSION"] else {
            // On CI a node is always there: a run that found none is no run of these.
            if env["CI"] != nil { XCTFail("no node to test the island against: QNTX_TEST_NODE and QNTX_TEST_SESSION are not set") }
            throw XCTSkip("no node to test against")
        }
        node = WaitsTestedAgainst(node: url, session: session)
        waitsTestedAgainst = node
    }

    override func tearDown() {
        waitsTestedAgainst = nil
    }

    // The phone's token, handed over as the island hands it, is taken.
    func testTheNodeTakesThePhonesToken() async throws {
        try await waitsNodeIsAsked("/api/phones", ["token": String(repeating: "cc33", count: 16), "platform": "ios"])
    }

    // What the node refuses comes back as the island's failure, with the node's words.
    func testWhatTheNodeRefusesIsTheIslandsFailure() async {
        waitsTestedAgainst = WaitsTestedAgainst(node: node.node, session: String(repeating: "0", count: 64))
        do {
            try await waitsNodeIsAsked("/api/phones", ["token": String(repeating: "cc33", count: 16), "platform": "ios"])
            XCTFail("the node took a token from a session it never made")
        } catch let error as SacredError {
            XCTAssertEqual(error.title, "the node did not do what was pressed")
            XCTAssertTrue(error.why.contains("401"), error.why)
        } catch {
            XCTFail("it failed with what is no SacredError: \(error)")
        }
    }

    // A token that is no token is refused by the node, and said.
    func testTheNodeSaysWhyItRefusedAToken() async {
        do {
            try await waitsNodeIsAsked("/api/phones", ["token": "not-hex", "platform": "ios"])
            XCTFail("the node took what is no token")
        } catch let error as SacredError {
            XCTAssertTrue(error.why.contains("400"), error.why)
            XCTAssertTrue(error.raw?.contains("token") == true, String(describing: error.raw))
        } catch {
            XCTFail("it failed with what is no SacredError: \(error)")
        }
    }
}

// A press, as the island asks it, on what waits on the node on the runner
// (.github/scripts/ci-node.py writes it): delay, send and cancel, each doing
// on the node what it says, and each failure the island's.
final class APressReachesARealNode: XCTestCase {
    private var node: WaitsTestedAgainst!
    private var waitsFor = ""

    override func setUpWithError() throws {
        let env = ProcessInfo.processInfo.environment
        guard let at = env["QNTX_TEST_NODE"], let url = URL(string: at), let session = env["QNTX_TEST_SESSION"],
            let waitsFor = env["QNTX_TEST_WAITS_FOR"]
        else {
            if env["CI"] != nil { XCTFail("no node to press against: QNTX_TEST_NODE, QNTX_TEST_SESSION and QNTX_TEST_WAITS_FOR are not set") }
            throw XCTSkip("no node to press against")
        }
        node = WaitsTestedAgainst(node: url, session: session)
        self.waitsFor = waitsFor
        waitsTestedAgainst = node
    }

    override func tearDown() {
        waitsTestedAgainst = nil
    }

    // What the node lists as waiting for the agent, as the page reads it.
    private func waiting() async throws -> [String: Any]? {
        var asks = URLRequest(url: node.node.appendingPathComponent("api/collected"))
        asks.setValue("Bearer \(node.session)", forHTTPHeaderField: "Authorization")
        let (said, _) = try await URLSession.shared.data(for: asks)
        let all = try XCTUnwrap(JSONSerialization.jsonObject(with: said) as? [String: Any])
        let collected = all["collected"] as? [[String: Any]] ?? []
        return collected.first { $0["did"] as? String == waitsFor }
    }

    func testDelaySendAndCancelDoOnTheNodeWhatTheySay() async throws {
        let listed = try await waiting()
        let before = try XCTUnwrap(listed, "nothing waits on the node to press")
        XCTAssertEqual((before["waiting"] as? [Any])?.count, 2)
        let dueBefore = try XCTUnwrap(before["due"] as? String)

        // Delay: what waits is held one more wait past when it was due.
        try await waitsNodeIsAsked("/api/collected/later", ["to": waitsFor])
        let afterDelay = try await waiting()
        let delayed = try XCTUnwrap(afterDelay)
        XCTAssertGreaterThan(try XCTUnwrap(delayed["due"] as? String), dueBefore, "a delay did not move when it goes")

        // Send: the node serves no agent named Birch, so it is not delivered,
        // and that comes back as the island's failure, counted on the node.
        do {
            try await waitsNodeIsAsked("/api/collected/release", ["to": waitsFor])
            XCTFail("what waits for an agent the node does not serve was sent")
        } catch let error as SacredError {
            XCTAssertEqual(error.title, "the node did not do what was pressed")
            XCTAssertTrue(error.raw?.contains("try 1") == true, String(describing: error.raw))
        }
        let afterSend = try await waiting()
        let failed = try XCTUnwrap(afterSend)
        XCTAssertEqual(failed["tries"] as? Int, 1, "the node did not keep the failed send with what waits")
        XCTAssertFalse((failed["failure"] as? String ?? "").isEmpty)

        // Cancel: nothing waits any more.
        try await waitsNodeIsAsked("/api/collected/cancel", ["to": waitsFor])
        let gone = try await waiting()
        XCTAssertNil(gone, "what was canceled still waits")
    }
}
