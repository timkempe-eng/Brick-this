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

    var isAvailable: Bool { NFCTagReaderSession.readingAvailable }

    /// Prompts for a tap and calls back with the tag's UID as a hex string.
    func scan(prompt: String, onRead: @escaping (String) -> Void) {
        guard isAvailable else {
            lastError = "This iPhone can't scan NFC tags."
            return
        }
        self.onRead = onRead
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
                session.invalidate(errorMessage: "That tag isn't a type Tim can use.")
                return
            }
            session.alertMessage = "Got it."
            session.invalidate()
            Task { @MainActor in
                self.isScanning = false
                self.onRead?(uid.hexString)
                self.onRead = nil
            }
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
