import Foundation
import CoreNFC

/// Foreground NFC scanning — used to pair a new tag and as the in-app way to
/// tap when you would rather not set up a Shortcuts automation.
///
/// This reads the tag's hardware UID rather than its NDEF payload. The UID is
/// factory-burned and read-only, so a paired tag cannot be cloned by writing
/// the same text onto a second sticker. A blank NTAG215 straight out of the
/// bag works: nothing has to be written to it for pairing.
@MainActor
final class TagScanner: NSObject, ObservableObject {

    @Published var isScanning = false
    @Published var lastError: String?

    private var session: NFCTagReaderSession?
    private var onRead: ((String) -> Void)?
    private var onLedger: ((String) -> Void)?

    /// The household ledger this phone would leave on the tag, and what it
    /// found there.
    ///
    /// Carried on the same scan as the tap rather than run as its own action,
    /// because `NFCMiFareTag` and `NFCISO15693Tag` both conform to
    /// `NFCNDEFTag` — so one session yields the hardware UID *and* NDEF read
    /// and write. A separate session would mean a second "hold your iPhone
    /// near the tag" prompt for something nobody asked for.
    ///
    /// Values rather than a callback, and that is the load-bearing choice: the
    /// merge runs inside an NFC completion handler on a background queue,
    /// where nothing that touches the store or the screen can go. Everything
    /// it needs is computed before the session opens, and the result is handed
    /// back afterwards on the main actor.
    ///
    /// Best-effort by construction: every failure below leaves the tap intact
    /// and the shared number where it was. A tag that will not write is a
    /// number that lags, which the UI already says out loud — not a reason to
    /// fail somebody's Sleep Mode.
    private let exchange = LedgerExchange()

    var isAvailable: Bool { NFCTagReaderSession.readingAvailable }

    /// Prompts for a tap and calls back with the tag's UID as a hex string.
    ///
    /// - Parameters:
    ///   - ledger: what this phone would leave on the tag. Omit it and the
    ///     session behaves exactly as it did before the household streak
    ///     existed: read the UID, invalidate, call back.
    ///   - own: this phone's standing, re-applied after the merge so the tag's
    ///     stale copy of us can never beat our own history.
    ///   - onLedger: whatever was found on the tag, delivered on the main
    ///     actor after the session closes so the engine can take it in.
    func scan(prompt: String,
              ledger: HouseholdLedger? = nil,
              own: MemberStanding? = nil,
              onLedger: ((String) -> Void)? = nil,
              onRead: @escaping (String) -> Void) {
        guard isAvailable else {
            lastError = "This iPhone can't scan NFC tags."
            return
        }
        self.onRead = onRead
        self.onLedger = onLedger
        exchange.mine = ledger
        exchange.own = own
        exchange.found = nil
        // .iso14443 covers the NTAG21x stickers almost everyone buys;
        // .iso15693 covers NFC Forum Type 5 (ICODE and friends). FeliCa is
        // left out deliberately — polling for it needs a separate entitlement
        // listing system codes, and it isn't hardware you'd buy for this.
        session = NFCTagReaderSession(pollingOption: [.iso14443, .iso15693], delegate: self, queue: nil)
        session?.alertMessage = prompt
        session?.begin()
        isScanning = true
    }
}

extension TagScanner: NFCTagReaderSessionDelegate {

    nonisolated func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

    nonisolated func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        Task { @MainActor in
            self.isScanning = false
            self.session = nil
            // A user-cancelled or timed-out scan is a normal way to back out,
            // not something to put an error banner in front of.
            let code = (error as? NFCReaderError)?.code
            if code != .readerSessionInvalidationErrorUserCanceled,
               code != .readerSessionInvalidationErrorSessionTimeout,
               code != .readerSessionInvalidationErrorFirstNDEFTagRead {
                self.lastError = error.localizedDescription
            }
        }
    }

    nonisolated func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let tag = tags.first else { return }

        session.connect(to: tag) { error in
            if let error {
                session.invalidate(errorMessage: error.localizedDescription)
                return
            }
            guard let uid = Self.identifier(of: tag) else {
                session.invalidate(errorMessage: "That tag isn't a type Dad can use.")
                return
            }
            self.exchangeLedger(on: tag) {
                session.alertMessage = "Got it."
                session.invalidate()
                Task { @MainActor in
                    self.isScanning = false
                    // The ledger first: the tap can start a session, and a
                    // household number that arrived a moment after it would
                    // render one frame late.
                    if let text = self.exchange.found { self.onLedger?(text) }
                    self.onLedger = nil
                    self.onRead?(uid.hexString)
                    self.onRead = nil
                }
            }
        }
    }

    /// Reads the ledger off the tag, merges it with what this phone brought,
    /// writes the result back, and calls `finish` whatever happened.
    ///
    /// `finish` is called on every path — including every failure — because
    /// the tap is the thing the user asked for and the shared streak is not.
    /// A tag that is locked, full, or holding something this build cannot read
    /// must still Dad the phone.
    nonisolated private func exchangeLedger(on tag: NFCTag,
                                            finish: @escaping () -> Void) {
        guard let mine = exchange.mine, let ndef = Self.ndefTag(of: tag) else { return finish() }

        ndef.queryNDEFStatus { status, capacity, _ in
            // A locked tag is still perfectly readable, and a household whose
            // tag someone write-protected should still pick up everyone
            // else's standings — they simply cannot leave their own. Skipping
            // the read as well was giving up more than the tag took away.
            guard status != .notSupported else { return finish() }
            ndef.readNDEF { message, _ in
                // A blank tag reads as an error rather than an empty message,
                // and a blank tag is the normal first case: nothing has to be
                // written to a sticker for pairing to work.
                let existing = message?.records ?? []
                let found = Self.ledgerText(in: existing)
                self.exchange.found = found

                guard status == .readWrite else { return finish() }

                let reply = mine.afterExchange(with: found, own: self.exchange.own).encoded()
                guard reply != found else { return finish() }

                let outgoing = Self.message(replacingLedgerIn: existing, with: reply)
                guard outgoing.length <= capacity else { return finish() }
                ndef.writeNDEF(outgoing) { _ in finish() }
            }
        }
    }

    /// The tag's ledger record, if it has one.
    ///
    /// Matched by the format's own prefix rather than by position, because the
    /// tag may also carry the universal link that makes background reading
    /// work and the two must not fight over record zero.
    nonisolated private static func ledgerText(in records: [NFCNDEFPayload]) -> String? {
        records.lazy
            .compactMap { $0.wellKnownTypeTextPayload().0 }
            .first { HouseholdLedgerFormat.isOurRecord($0) }
    }

    /// Every record the tag had, with its ledger record replaced.
    ///
    /// Keeps the others. Overwriting the whole message would silently destroy
    /// a universal link somebody wrote in Settings, and they would find out by
    /// their tag quietly no longer working with the app closed.
    nonisolated private static func message(replacingLedgerIn records: [NFCNDEFPayload],
                                            with ledger: String) -> NFCNDEFMessage {
        let kept = records.filter {
            !HouseholdLedgerFormat.isOurRecord($0.wellKnownTypeTextPayload().0)
        }
        guard let payload = NFCNDEFPayload.wellKnownTypeTextPayload(string: ledger,
                                                                   locale: Locale(identifier: "en")) else {
            return NFCNDEFMessage(records: kept)
        }
        return NFCNDEFMessage(records: kept + [payload])
    }

    /// The NDEF face of a tag we already have by UID.
    ///
    /// Both tag types anyone would buy for this conform to `NFCNDEFTag`, which
    /// is what lets one session do both jobs. `iso7816` does not, and a
    /// payment card is not a thing to write a streak onto anyway.
    nonisolated private static func ndefTag(of tag: NFCTag) -> NFCNDEFTag? {
        switch tag {
        case .miFare(let t):   return t
        case .iso15693(let t): return t
        default:               return nil
        }
    }

    nonisolated private static func identifier(of tag: NFCTag) -> Data? {
        switch tag {
        case .miFare(let t):    return t.identifier      // NTAG213/215/216 land here
        case .iso15693(let t):  return t.identifier      // NFC Forum Type 5
        case .iso7816(let t):   return t.identifier      // payment-style cards; unlikely but harmless
        @unknown default:       return nil
        }
    }
}

extension Data {
    var hexString: String { map { String(format: "%02X", $0) }.joined() }
}

/// Carries the ledger values across the NFC delegate queue.
///
/// The same shape as `TagWriter.PendingMessage`, and for the same reason: the
/// NFC callbacks arrive on a background queue while the values are set and
/// read where the engine lives. Only values cross — no closure, so nothing on
/// that queue can reach the store or the screen.
private final class LedgerExchange: @unchecked Sendable {
    private let lock = NSLock()
    private var storedMine: HouseholdLedger?
    private var storedOwn: MemberStanding?
    private var storedFound: String?

    var mine: HouseholdLedger? {
        get { lock.withLock { storedMine } }
        set { lock.withLock { storedMine = newValue } }
    }

    var own: MemberStanding? {
        get { lock.withLock { storedOwn } }
        set { lock.withLock { storedOwn = newValue } }
    }

    /// What the tag turned out to be carrying, for the engine to take in once
    /// the session has closed.
    var found: String? {
        get { lock.withLock { storedFound } }
        set { lock.withLock { storedFound = newValue } }
    }
}
