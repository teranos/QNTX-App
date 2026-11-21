// "cant we make it easier on me, in terms of being able to test most testable mechanical things, before its like, live on my phone ??"
//
// What the island asks of a QNTX node, tested in the iPhone Simulator before
// any build reaches a phone. What it decides on its own is tested where it is
// kept, in teranos/ios-common's ci/island-tests.

import SacredError
import XCTest

@testable import Island

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
