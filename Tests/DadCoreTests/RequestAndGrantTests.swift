import XCTest
@testable import DadCore

/// Asking for a release, and being given a bounded one.
///
/// `GrantRequest.swift` owns the state machine and tests it exhaustively.
/// These are about the seam: that granting actually releases the phone, that
/// the release is bounded by construction all the way through to the engine,
/// and that the two ways a phone comes back — a Mode's own break and a
/// grant — do not stack.
///
/// The granter is a **tag tap**, not a PIN. `GrantRequest` defines a
/// `PINHashing` port for the remote case and nothing implements it yet, on
/// purpose: the parent is in the room and already holds a tag, which needs no
/// account, no server and no crypto anybody here has to get right.
final class RequestAndGrantTests: XCTestCase {

    private func dadded(_ breakLength: TimeInterval? = nil) -> (Harness, DadMode) {
        let h = Harness()
        let mode = h.addMode(breakLength: breakLength)
        h.engine.pair(tagUID: "PARENT")
        h.engine.dad(with: mode)
        return (h, mode)
    }

    // MARK: - Asking

    func testYouCanOnlyAskWhileTheresSomethingToAskAbout() {
        let h = Harness()
        h.addMode()
        XCTAssertNil(h.engine.requestRelease(), "nothing is taken away yet")
    }

    func testASecondAskIsRefusedWhileOneIsOutstanding() {
        // Two asks at once is not a stricter product, it is a queue nobody
        // wanted — and a parent looking at two would have to guess which the
        // young person still means.
        let (h, _) = dadded()
        XCTAssertNotNil(h.engine.requestRelease())
        XCTAssertNil(h.engine.requestRelease())
        XCTAssertEqual(h.store.grantExchanges.count, 1)
    }

    func testAnUnansweredAskDiesOnItsOwn() {
        // The midnight case: nobody looked, and the ask must not still be
        // sitting there to be granted by accident the next morning.
        let (h, _) = dadded()
        h.engine.requestRelease()
        XCTAssertNotNil(h.engine.pendingRequest)

        h.clock.advance(GrantRequest.defaultLifetime + 60)

        XCTAssertNil(h.engine.pendingRequest)
        XCTAssertNil(h.engine.grantRelease(byTagUID: "PARENT"))
    }

    func testAnUnansweredAskLastsTenMinutes() {
        // Ten minutes is the number, spelled out. Every other test here
        // advances by `GrantRequest.defaultLifetime`, which is correct style
        // and means the entire suite moves with the constant: a ten-minute ask
        // could quietly become a sixteen-hour one without a single failure,
        // and the failure that causes is the one this lifetime exists to
        // prevent — granting at midnight an ask made at four o'clock.
        let (h, _) = dadded()
        h.engine.requestRelease()

        h.clock.advance(9 * 60)
        XCTAssertNotNil(h.engine.pendingRequest, "still worth answering at nine minutes")

        h.clock.advance(2 * 60)
        XCTAssertNil(h.engine.pendingRequest, "and gone by eleven")
    }

    func testTheExchangeHistoryIsBoundedAtAHundred() {
        // For the reason the session history is bounded at five hundred: the
        // shield extension decodes this file under a tight memory budget, and
        // an unbounded array is a crash on somebody's phone a year from now.
        // It is the newest exchanges that are worth keeping.
        let (h, _) = dadded()

        var firstID: UUID?
        var lastID: UUID?
        for _ in 0..<150 {
            guard let exchange = h.engine.requestRelease() else {
                return XCTFail("an expired ask must not block the next one")
            }
            if firstID == nil { firstID = exchange.id }
            lastID = exchange.id
            h.clock.advance(GrantRequest.defaultLifetime + 60)
        }

        XCTAssertEqual(h.store.grantExchanges.count, 100)
        XCTAssertFalse(h.store.grantExchanges.contains { $0.id == firstID },
                       "the oldest ask is the one to drop")
        XCTAssertTrue(h.store.grantExchanges.contains { $0.id == lastID },
                      "and the newest is the one that must survive")
    }

    // MARK: - Granting releases the phone

    func testGrantingGivesTheAppsBackAndBringsTheModeBack() {
        let (h, mode) = dadded()
        h.engine.requestRelease(reason: "homework")

        h.engine.grantRelease(byTagUID: "PARENT")

        XCTAssertNil(h.store.activeSession, "released")
        XCTAssertNil(h.shield.appliedMode)
        XCTAssertEqual(h.store.pendingResume?.modeID, mode.id, "and coming back")
        XCTAssertEqual(h.store.pendingResume?.at,
                       h.clock.now.addingTimeInterval(GrantDuration.standard.seconds))
    }

    func testTheModeReallyComesBack() {
        let (h, mode) = dadded()
        h.engine.requestRelease()
        h.engine.grantRelease(byTagUID: "PARENT")

        h.clock.advance(GrantDuration.standard.seconds)
        h.engine.resumeFromBreak()

        XCTAssertEqual(h.store.activeSession?.modeID, mode.id)
        XCTAssertEqual(h.shield.appliedMode, mode.id)
    }

    func testAGrantIsBoundedNoMatterWhatIsAskedFor() {
        // Bounded by construction, all the way to the engine: saying yes must
        // never be the same as giving up for the evening.
        let (h, _) = dadded()
        h.engine.requestRelease()

        h.engine.grantRelease(24 * 60 * 60, byTagUID: "PARENT")

        let ends = h.store.pendingResume!.at
        XCTAssertLessThanOrEqual(ends.timeIntervalSince(h.clock.now), GrantDuration.maximum)
    }

    func testAGrantTooShortForTheSystemToWatchIsRoundedUp() {
        let (h, _) = dadded()
        h.engine.requestRelease()
        h.engine.grantRelease(60, byTagUID: "PARENT")

        XCTAssertEqual(h.store.pendingResume?.at,
                       h.clock.now.addingTimeInterval(DadEngine.minimumScheduledRelease))
    }

    // MARK: - Only a paired tag grants

    func testAnUnknownTagCannotGrant() {
        let (h, _) = dadded()
        h.engine.requestRelease()

        XCTAssertNil(h.engine.grantRelease(byTagUID: "STRANGER"))

        XCTAssertNotNil(h.store.activeSession, "still Dadded")
        XCTAssertNotNil(h.engine.pendingRequest, "and still asking")
    }

    // MARK: - The two ways back do not stack

    func testAGrantOnAModeThatTakesBreaksRegistersExactlyOneComingBack() {
        // Asserted on the *scheduler*, not just the stored value, and that
        // distinction is the whole test. If the release ended the session as
        // `.tapped`, the Mode's own break would arm first and the grant would
        // overwrite `pendingResume` — so the store would read one hour and
        // look right. But `DeviceActivityScheduler.scheduleResume` skips a
        // window that is already registered, on purpose, so the *system* would
        // keep the fifteen-minute one and bring the Mode back three quarters
        // of an hour early. The bound the parent agreed to would not be the
        // bound, and nothing in the app would say so.
        let (h, _) = dadded(15 * 60)
        h.engine.requestRelease()

        h.engine.grantRelease(60 * 60, byTagUID: "PARENT")

        XCTAssertEqual(h.scheduler.resumes, [h.clock.now.addingTimeInterval(60 * 60)],
                       "one registration, and it is the grant's")
        XCTAssertEqual(h.store.pendingResume?.at, h.clock.now.addingTimeInterval(60 * 60))
    }

    // MARK: - Declining

    func testDecliningLeavesThePhoneDaddedAndSaysSo() {
        let (h, mode) = dadded()
        h.engine.requestRelease()

        h.engine.declineRequest()

        XCTAssertEqual(h.shield.appliedMode, mode.id)
        XCTAssertNil(h.engine.pendingRequest)
        XCTAssertEqual(h.store.grantExchanges.count, 1, "and the ask is still in the record")
    }

    func testADeclinedAskCannotThenBeGranted() {
        let (h, _) = dadded()
        h.engine.requestRelease()
        h.engine.declineRequest()

        XCTAssertNil(h.engine.grantRelease(byTagUID: "PARENT"))
        XCTAssertNotNil(h.store.activeSession)
    }

    func testWithdrawingAnAskLeavesNothingOutstanding() {
        let (h, _) = dadded()
        h.engine.requestRelease()

        h.engine.withdrawRequest()

        XCTAssertNil(h.engine.pendingRequest)
        XCTAssertNotNil(h.store.activeSession)
    }

    func testDeclinedAsksStayInTheRecord() {
        // A household that can only read the answers it liked is one where the
        // log is worth nothing.
        let (h, _) = dadded()
        h.engine.requestRelease(reason: "one thing")
        h.engine.declineRequest()
        h.engine.requestRelease(reason: "another thing")

        XCTAssertEqual(h.store.grantExchanges.count, 2)
        XCTAssertEqual(h.store.grantExchanges.first?.request.reason, "one thing")
    }
}
