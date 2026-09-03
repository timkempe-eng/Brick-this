import XCTest
@testable import DadCore

/// The decisions in `GrantRequest.swift`, pinned.
///
/// Four of them are the reason the file exists and none of them are visible
/// from a device without waiting an evening: a grant that cannot be unbounded,
/// an ask that expires with nothing running, a lockout derived from stored
/// dates, and the fifteen-minute system floor being rounded up rather than
/// quietly ignored.

private let t0 = Date(timeIntervalSince1970: 1_756_000_000)
private let anyMode = UUID()

private func ask(at when: Date = t0,
                 reason: String? = nil,
                 lifetime: TimeInterval = GrantRequest.defaultLifetime) -> GrantExchange {
    GrantExchange(request: GrantRequest(modeID: anyMode,
                                        modeName: "Sleep",
                                        askedAt: when,
                                        reason: reason,
                                        lifetime: lifetime))
}

private let parent = Granter.inPerson(tagUID: "04A2B3")

// MARK: - Bounded by construction

final class GrantDurationTests: XCTestCase {

    func testTheFloorIsTheSchedulersOwnMinimum() {
        // Not an independent constant: `DeviceActivitySchedule` refuses to
        // monitor a shorter interval, so the two must not drift apart.
        XCTAssertEqual(GrantDuration.minimum, DadEngine.minimumScheduledRelease)
    }

    func testAGrantShorterThanTheFloorIsRoundedUpAndSaysSo() {
        let five = GrantDuration(requesting: 5 * 60)
        XCTAssertEqual(five.seconds, GrantDuration.minimum)
        XCTAssertEqual(five.adjustment, .roundedUpToFloor,
                       "a rounded grant must be able to explain itself, not lie about the number")
    }

    func testAGrantOfZeroOrLessIsStillAWholeFloorLong() {
        // Otherwise "grant nothing" is representable, and a phone released for
        // zero seconds is a UI that flickers rather than a decision.
        XCTAssertEqual(GrantDuration(requesting: 0).seconds, GrantDuration.minimum)
        XCTAssertEqual(GrantDuration(requesting: -3600).seconds, GrantDuration.minimum)
    }

    func testAnOverlongGrantIsClampedToTheCeiling() {
        let evening = GrantDuration(requesting: 8 * 60 * 60)
        XCTAssertEqual(evening.seconds, GrantDuration.maximum)
        XCTAssertEqual(evening.adjustment, .clampedToCeiling)
    }

    func testNoRequestAtAllProducesAnUnboundedGrant() {
        for absurd in [TimeInterval.infinity, .greatestFiniteMagnitude, .nan, -.infinity] {
            let d = GrantDuration(requesting: absurd)
            XCTAssertTrue(d.seconds.isFinite, "\(absurd) produced a non-finite grant")
            XCTAssertLessThanOrEqual(d.seconds, GrantDuration.maximum)
            XCTAssertGreaterThanOrEqual(d.seconds, GrantDuration.minimum)
        }
    }

    func testAReasonableGrantIsLeftExactlyAlone() {
        let half = GrantDuration(requesting: 30 * 60)
        XCTAssertEqual(half.seconds, 30 * 60)
        XCTAssertEqual(half.adjustment, .none)
    }

    func testDecodingCannotSmuggleInAnUnboundedGrant() throws {
        // The synthesised decoder would have assigned this straight through,
        // which is exactly the second door this file refuses to leave open.
        let stored = Data(#"{"seconds": 86400}"#.utf8)
        let decoded = try JSONDecoder().decode(GrantDuration.self, from: stored)
        XCTAssertEqual(decoded.seconds, GrantDuration.maximum)
        XCTAssertEqual(decoded.adjustment, .clampedToCeiling)
    }

    func testDurationSurvivesARoundTrip() throws {
        let original = GrantDuration(requesting: 20 * 60)
        let restored = try JSONDecoder().decode(
            GrantDuration.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(restored, original)
    }

    func testAGrantsEndIsAlwaysItsStartPlusABoundedLength() {
        let grant = Grant(requesting: .infinity, grantedBy: parent, startsAt: t0)
        XCTAssertEqual(grant.endsAt, t0.addingTimeInterval(GrantDuration.maximum))
        XCTAssertLessThan(grant.endsAt, Date.distantFuture)
    }
}

// MARK: - The ask

final class GrantRequestShapeTests: XCTestCase {

    func testAReasonOfNothingButSpaceIsNoReason() {
        XCTAssertNil(ask(reason: "   \n ").request.reason)
        XCTAssertNil(ask(reason: "").request.reason)
        XCTAssertEqual(ask(reason: "  homework  ").request.reason, "homework")
    }

    func testALongReasonIsCappedBecauseTheShieldReadsItUnderAMemoryLimit() {
        let essay = String(repeating: "a", count: 500)
        XCTAssertEqual(ask(reason: essay).request.reason?.count, GrantRequest.reasonLimit)
    }

    func testALifetimeIsClampedIntoTheRangeThatMakesSense() {
        XCTAssertEqual(ask(lifetime: 1).request.lifetime, GrantRequest.minimumLifetime)
        XCTAssertEqual(ask(lifetime: 7 * 24 * 3600).request.lifetime,
                       GrantRequest.maximumLifetime)
        XCTAssertEqual(ask(lifetime: .nan).request.lifetime, GrantRequest.defaultLifetime)
    }

    func testExpiryIsDerivedFromWhenItWasAskedNotStoredSeparately() {
        let request = ask(at: t0, lifetime: 600).request
        XCTAssertEqual(request.expiresAt, t0.addingTimeInterval(600))
    }

    func testDecodingCannotSmuggleInARequestThatNeverExpires() throws {
        let stored = Data("""
        {"id":"\(UUID().uuidString)","modeID":"\(anyMode.uuidString)","modeName":"Sleep",
         "askedAt":0,"lifetime":604800}
        """.utf8)
        let decoded = try JSONDecoder().decode(GrantRequest.self, from: stored)
        XCTAssertEqual(decoded.lifetime, GrantRequest.maximumLifetime)
    }

    func testAnExchangeSurvivesCoding() throws {
        let granted = try ask().granting(20 * 60, by: parent, now: t0).get()
        let restored = try JSONDecoder().decode(
            GrantExchange.self, from: JSONEncoder().encode(granted))
        XCTAssertEqual(restored, granted)
    }
}

// MARK: - State without a timer

final class GrantStateTests: XCTestCase {

    func testAnUnansweredRequestIsPendingUntilItsLifetimeRunsOut() {
        let exchange = ask(at: t0, lifetime: 600)
        XCTAssertEqual(exchange.state(at: t0), .pending(expiresAt: t0.addingTimeInterval(600)))
        XCTAssertEqual(exchange.state(at: t0.addingTimeInterval(599)),
                       .pending(expiresAt: t0.addingTimeInterval(600)))
    }

    func testARequestExpiresOnItsOwnWithNothingHavingRun() {
        // Nothing wrote `.expired` anywhere. No job fired. The phone was in a
        // drawer. It is still expired, because expiry is a subtraction.
        let exchange = ask(at: t0, lifetime: 600)
        XCTAssertEqual(exchange.state(at: t0.addingTimeInterval(6 * 3600)),
                       .expired(at: t0.addingTimeInterval(600)))
    }

    func testARequestIsExpiredExactlyAtItsExpiryInstant() {
        let exchange = ask(at: t0, lifetime: 600)
        XCTAssertEqual(exchange.state(at: t0.addingTimeInterval(600)),
                       .expired(at: t0.addingTimeInterval(600)),
                       "the boundary instant belongs to expiry, or two taps can disagree")
    }

    func testAGrantIsActiveUntilItsEndAndElapsedAfterwards() throws {
        let granted = try ask().granting(20 * 60, by: parent, now: t0).get()
        let end = t0.addingTimeInterval(20 * 60)

        XCTAssertEqual(granted.state(at: t0), .active(until: end))
        XCTAssertEqual(granted.state(at: end.addingTimeInterval(-1)), .active(until: end))
        XCTAssertEqual(granted.state(at: end), .elapsed(at: end))
    }

    func testAGrantElapsesEvenIfTheReDadNeverFired() throws {
        // The backstop. If the only thing that ended a grant was the
        // DeviceActivity wake, a lost registration would mean a phone that is
        // free forever — which is precisely `DadEngine.reconcile`'s overdue
        // check, transplanted.
        let granted = try ask().granting(15 * 60, by: parent, now: t0).get()
        XCTAssertEqual(granted.state(at: t0.addingTimeInterval(24 * 3600)),
                       .elapsed(at: t0.addingTimeInterval(15 * 60)))
        XCTAssertFalse(granted.isReleasing(at: t0.addingTimeInterval(24 * 3600)))
    }

    func testRemainingCountsDownAndThenStopsExisting() throws {
        let granted = try ask().granting(15 * 60, by: parent, now: t0).get()
        XCTAssertEqual(granted.remaining(at: t0), 15 * 60)
        XCTAssertEqual(granted.remaining(at: t0.addingTimeInterval(5 * 60)), 10 * 60)
        XCTAssertNil(granted.remaining(at: t0.addingTimeInterval(15 * 60)),
                     "a finished grant has no time left, not negative time left")
    }

    func testAShortGrantStillReDadsThePhoneAtTheSystemFloor() throws {
        // The visible half of rounding up: ask for five minutes, and the phone
        // comes back at fifteen rather than never.
        let granted = try ask().granting(5 * 60, by: parent, now: t0).get()
        XCTAssertEqual(granted.state(at: t0.addingTimeInterval(5 * 60 + 1)),
                       .active(until: t0.addingTimeInterval(DadEngine.minimumScheduledRelease)))
        XCTAssertEqual(granted.state(at: t0.addingTimeInterval(DadEngine.minimumScheduledRelease)),
                       .elapsed(at: t0.addingTimeInterval(DadEngine.minimumScheduledRelease)))
    }

    func testDecliningAndWithdrawingAreStatesOfTheirOwn() throws {
        let declined = try ask().declining(now: t0).get()
        XCTAssertEqual(declined.state(at: t0.addingTimeInterval(9_999)), .declined(at: t0))

        let withdrawn = try ask().withdrawing(now: t0).get()
        XCTAssertEqual(withdrawn.state(at: t0.addingTimeInterval(9_999)), .withdrawn(at: t0))
    }
}

// MARK: - Illegal transitions

final class GrantTransitionTests: XCTestCase {

    func testAnExpiredRequestCannotBeGrantedAtMidnight() {
        let exchange = ask(at: t0, lifetime: 600)
        let midnight = t0.addingTimeInterval(8 * 3600)

        XCTAssertEqual(exchange.granting(15 * 60, by: parent, now: midnight),
                       .failure(.requestExpired(at: t0.addingTimeInterval(600))))
    }

    func testAnExpiredRequestCannotBeDeclinedOrWithdrawnEither() {
        let exchange = ask(at: t0, lifetime: 600)
        let late = t0.addingTimeInterval(3600)
        XCTAssertEqual(exchange.declining(now: late),
                       .failure(.requestExpired(at: t0.addingTimeInterval(600))))
        XCTAssertEqual(exchange.withdrawing(now: late),
                       .failure(.requestExpired(at: t0.addingTimeInterval(600))))
    }

    func testAnAnswerIsFinal() throws {
        let declined = try ask().declining(now: t0).get()
        XCTAssertEqual(declined.granting(15 * 60, by: parent, now: t0),
                       .failure(.alreadyAnswered(.declined(at: t0))))
        XCTAssertEqual(declined.declining(now: t0),
                       .failure(.alreadyAnswered(.declined(at: t0))))
    }

    func testARunningGrantCannotBeWithdrawnBecauseThatIsATagTapNotADecision() throws {
        let granted = try ask().granting(20 * 60, by: parent, now: t0).get()
        let end = t0.addingTimeInterval(20 * 60)
        XCTAssertEqual(granted.withdrawing(now: t0),
                       .failure(.alreadyAnswered(.active(until: end))))
    }

    func testAnElapsedGrantCannotBeReAnsweredIntoASecondRelease() throws {
        let granted = try ask().granting(20 * 60, by: parent, now: t0).get()
        let after = t0.addingTimeInterval(3 * 3600)
        let end = t0.addingTimeInterval(20 * 60)
        XCTAssertEqual(granted.granting(20 * 60, by: parent, now: after),
                       .failure(.alreadyAnswered(.elapsed(at: end))))
    }

    func testARefusedTransitionChangesNothing() {
        // Transitions return a new value; a refusal must not have left a
        // half-answered record behind for the next foreground to find.
        let exchange = ask(at: t0, lifetime: 600)
        _ = exchange.granting(15 * 60, by: parent, now: t0.addingTimeInterval(3600))
        XCTAssertNil(exchange.decision)
    }

    func testWithdrawingWhilePendingIsAllowed() throws {
        let withdrawn = try ask().withdrawing(now: t0.addingTimeInterval(60)).get()
        XCTAssertEqual(withdrawn.decision, .withdrawn(at: t0.addingTimeInterval(60)))
    }
}

// MARK: - The PIN

final class PINCheckTests: XCTestCase {

    private let stored = Data([0x01, 0x02, 0x03, 0x04])
    private var credential: PINCredential { PINCredential(salt: Data([0xAA]), hash: stored) }

    func testTheSameBytesMatch() {
        XCTAssertTrue(PINCheck.matches(Data([0x01, 0x02, 0x03, 0x04]), stored))
    }

    func testADifferenceInTheLastByteIsStillCaught() {
        // The whole hash is walked, so a mismatch at the end is as fatal as
        // one at the start.
        XCTAssertFalse(PINCheck.matches(Data([0x01, 0x02, 0x03, 0x05]), stored))
    }

    func testAPrefixOfTheStoredHashDoesNotMatch() {
        // The length check is folded into the accumulator rather than being an
        // early return; it still has to reject.
        XCTAssertFalse(PINCheck.matches(Data([0x01, 0x02]), stored))
        XCTAssertFalse(PINCheck.matches(Data([0x01, 0x02, 0x03, 0x04, 0x00]), stored))
    }

    func testNoPINSetIsNotTheSameAsEveryPINCorrect() {
        XCTAssertFalse(PINCheck.matches(Data(), Data()))
        XCTAssertFalse(PINCheck.matches(Data([0x01]), Data()))
    }

    func testTheFirstWrongAttemptsOnlyCostAttempts() {
        var failures: [Date] = []
        for expected in stride(from: PINCheck.freeAttempts - 1, through: 1, by: -1) {
            let (result, updated) = PINCheck.verify(candidateHash: Data([0xFF]),
                                                    against: credential,
                                                    failures: failures, now: t0)
            XCTAssertEqual(result, .rejected(attemptsRemaining: expected))
            failures = updated
        }
    }

    func testTheLockoutStartsWhenTheFreeAttemptsAreGone() {
        let failures = Array(repeating: t0, count: PINCheck.freeAttempts - 1)
        let (result, _) = PINCheck.verify(candidateHash: Data([0xFF]),
                                          against: credential,
                                          failures: failures, now: t0)
        XCTAssertEqual(result, .locked(until: t0.addingTimeInterval(PINCheck.baseLockout)))
    }

    func testTheLockoutIsDerivedFromStoredDatesRatherThanATimer() {
        // Nothing scheduled anything. The phone rebooted. It is still locked,
        // and it still lifts exactly when it said it would.
        let failures = Array(repeating: t0, count: PINCheck.freeAttempts)
        let until = t0.addingTimeInterval(PINCheck.baseLockout)
        XCTAssertEqual(PINCheck.lockout(failures: failures, now: t0), .locked(until: until))
        XCTAssertEqual(PINCheck.lockout(failures: failures, now: until.addingTimeInterval(-1)),
                       .locked(until: until))
        XCTAssertEqual(PINCheck.lockout(failures: failures, now: until),
                       .open(attemptsRemaining: 1))
    }

    func testAnExpiredLockoutGivesBackOneAttemptNotThree() {
        // Otherwise waiting out a one-minute lockout buys three more guesses,
        // forever, and the lockout costs an attacker nothing.
        let failures = Array(repeating: t0, count: PINCheck.freeAttempts)
        let after = t0.addingTimeInterval(PINCheck.baseLockout + 1)
        XCTAssertEqual(PINCheck.lockout(failures: failures, now: after),
                       .open(attemptsRemaining: 1))
    }

    func testEachFurtherWrongAttemptDoublesTheLockout() {
        func lockLength(afterFailures n: Int) -> TimeInterval? {
            guard case .locked(let until) = PINCheck.lockout(
                failures: Array(repeating: t0, count: n), now: t0) else { return nil }
            return until.timeIntervalSince(t0)
        }
        XCTAssertEqual(lockLength(afterFailures: PINCheck.freeAttempts),
                       PINCheck.baseLockout)
        XCTAssertEqual(lockLength(afterFailures: PINCheck.freeAttempts + 1),
                       PINCheck.baseLockout * 2)
        XCTAssertEqual(lockLength(afterFailures: PINCheck.freeAttempts + 2),
                       PINCheck.baseLockout * 4)
    }

    func testTheLockoutIsCappedSoATypoCannotCostADay() {
        guard case .locked(let until) = PINCheck.lockout(
            failures: Array(repeating: t0, count: PINCheck.freeAttempts + 30), now: t0) else {
            return XCTFail("thirty wrong attempts should be locked out")
        }
        XCTAssertEqual(until.timeIntervalSince(t0), PINCheck.maximumLockout)
    }

    func testTheFailureWindowIsAtLeastTheLongestLockout() {
        // Not a taste call: a shorter window prunes the failures that caused a
        // lockout while the lockout is still running.
        XCTAssertGreaterThanOrEqual(PINCheck.window, PINCheck.maximumLockout)
    }

    func testAMaximumLockoutStaysLockedForItsWholeLength() {
        // The behavioural half of the invariant above.
        let failures = Array(repeating: t0, count: PINCheck.freeAttempts + 30)
        let justBeforeItLifts = t0.addingTimeInterval(PINCheck.maximumLockout - 1)
        XCTAssertEqual(PINCheck.lockout(failures: failures, now: justBeforeItLifts),
                       .locked(until: t0.addingTimeInterval(PINCheck.maximumLockout)))
    }

    func testFailuresOlderThanTheWindowStopCounting() {
        let ancient = Array(repeating: t0.addingTimeInterval(-PINCheck.window - 1),
                            count: 20)
        XCTAssertEqual(PINCheck.lockout(failures: ancient, now: t0),
                       .open(attemptsRemaining: PINCheck.freeAttempts))
    }

    func testAttemptsDuringALockoutAreRefusedWithoutPushingItBack() {
        // A stuck keyboard must not extend a one-minute lockout indefinitely —
        // the countdown on screen is a promise.
        let failures = Array(repeating: t0, count: PINCheck.freeAttempts)
        let until = t0.addingTimeInterval(PINCheck.baseLockout)
        let (result, updated) = PINCheck.verify(candidateHash: Data([0xFF]),
                                                against: credential,
                                                failures: failures,
                                                now: t0.addingTimeInterval(30))
        XCTAssertEqual(result, .locked(until: until))
        XCTAssertEqual(updated, failures, "a refused attempt is not a recorded attempt")
        XCTAssertEqual(PINCheck.lockout(failures: updated, now: until),
                       .open(attemptsRemaining: 1))
    }

    func testEvenTheCorrectPINIsRefusedWhileLockedOut() {
        let failures = Array(repeating: t0, count: PINCheck.freeAttempts)
        let (result, _) = PINCheck.verify(candidateHash: stored,
                                          against: credential,
                                          failures: failures, now: t0)
        XCTAssertEqual(result, .locked(until: t0.addingTimeInterval(PINCheck.baseLockout)))
    }

    func testTheRightPINClearsTheSlate() {
        let (result, updated) = PINCheck.verify(candidateHash: stored,
                                                against: credential,
                                                failures: [t0, t0],
                                                now: t0.addingTimeInterval(60))
        XCTAssertEqual(result, .accepted)
        XCTAssertEqual(updated, [], "this morning's fumble must not count against tonight")
    }

    func testTheStoredFailureListCannotGrowWithoutBound() {
        let ancient = (0..<50).map { t0.addingTimeInterval(-PINCheck.window - Double($0)) }
        let (_, updated) = PINCheck.verify(candidateHash: Data([0xFF]),
                                           against: credential,
                                           failures: ancient, now: t0)
        XCTAssertEqual(updated.count, 1, "expired failures are dropped, not carried")
    }

    func testACredentialNeverCarriesTheDigits() throws {
        // Structural, but worth pinning: the only thing that reaches storage is
        // a salt and a hash. Hashing itself is `PINHashing`, an adapter's job.
        let json = String(decoding: try JSONEncoder().encode(credential), as: UTF8.self)
        XCTAssertTrue(json.contains("salt"))
        XCTAssertTrue(json.contains("hash"))
        XCTAssertFalse(json.lowercased().contains("pin"))
    }
}

// MARK: - The in-person flow, end to end

final class GrantAuthorizationTests: XCTestCase {

    private let hash = Data([0x0A, 0x0B, 0x0C, 0x0D])
    private var credential: PINCredential { PINCredential(salt: Data([1]), hash: hash) }

    func testTheRightPINGrantsABoundedRelease() {
        let (outcome, failures) = GrantAuthorization.authorise(
            ask(), requesting: 5 * 60, by: parent,
            candidateHash: hash, credential: credential, failures: [], now: t0)

        guard case .granted(let granted) = outcome else { return XCTFail("expected a grant") }
        XCTAssertEqual(granted.state(at: t0),
                       .active(until: t0.addingTimeInterval(DadEngine.minimumScheduledRelease)),
                       "even a five-minute ask comes back at the system floor")
        XCTAssertEqual(failures, [])
    }

    func testAWrongPINLeavesTheRequestPending() {
        let exchange = ask()
        let (outcome, failures) = GrantAuthorization.authorise(
            exchange, requesting: 15 * 60, by: parent,
            candidateHash: Data([0xFF]), credential: credential, failures: [], now: t0)

        XCTAssertEqual(outcome, .wrongPIN(attemptsRemaining: PINCheck.freeAttempts - 1))
        XCTAssertEqual(failures, [t0])
        XCTAssertNil(exchange.decision, "a wrong PIN must not answer the request")
    }

    func testALockedOutParentCannotGrant() {
        let (outcome, _) = GrantAuthorization.authorise(
            ask(), requesting: 15 * 60, by: parent,
            candidateHash: hash, credential: credential,
            failures: Array(repeating: t0, count: PINCheck.freeAttempts), now: t0)
        XCTAssertEqual(outcome, .lockedOut(until: t0.addingTimeInterval(PINCheck.baseLockout)))
    }

    func testFumblingThePINOnADeadRequestCostsNoAttempts() {
        // The ordering decision: the request's state is not a secret, and
        // checking it first means a midnight typo against an expired ask
        // cannot lock the parent out of the live one made a moment later.
        let (outcome, failures) = GrantAuthorization.authorise(
            ask(at: t0, lifetime: 600), requesting: 15 * 60, by: parent,
            candidateHash: Data([0xFF]), credential: credential,
            failures: [], now: t0.addingTimeInterval(8 * 3600))

        XCTAssertEqual(outcome, .refused(.requestExpired(at: t0.addingTimeInterval(600))))
        XCTAssertEqual(failures, [], "a dead request must not burn a PIN attempt")
    }

    func testAnAlreadyAnsweredRequestIsRefusedBeforeThePINIsConsulted() throws {
        let declined = try ask().declining(now: t0).get()
        let (outcome, failures) = GrantAuthorization.authorise(
            declined, requesting: 15 * 60, by: parent,
            candidateHash: Data([0xFF]), credential: credential, failures: [], now: t0)

        XCTAssertEqual(outcome, .refused(.alreadyAnswered(.declined(at: t0))))
        XCTAssertEqual(failures, [])
    }
}
