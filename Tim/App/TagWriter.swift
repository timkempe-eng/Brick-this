import Foundation
import CoreNFC

/// Writes a universal link onto a tag.
///
/// This is optional. Pairing works off the tag's UID, and the Shortcuts
/// automation route needs nothing written at all. Writing a link only matters
/// if you want iOS's *background* tag reading — the tap-and-it-just-happens
/// behaviour Brick has, with no automation set up and the app closed. iOS
/// only offers that for NDEF URI records whose domain is in the app's
/// Associated Domains entitlement, which means you need a website you control.
/// See docs/nfc-and-tags.md.
@MainActor
final class TagWriter: NSObject, ObservableObject {

    @Published var isWriting = false
    @Published var lastError: String?
    @Published var didWrite = false

    private var session: NFCNDEFReaderSession?

    /// The message waiting to be written. The NFC callbacks arrive on a
    /// background queue, so this cannot live on the MainActor with the rest of
    /// the class — hence the box.
    private let pending = PendingMessage()

    /// - Parameter url: the universal link to burn onto the tag, e.g.
    ///   `https://tim.example.com/tap`.
    func write(url: URL) {
        guard NFCNDEFReaderSession.readingAvailable else {
            lastError = "This iPhone can't write NFC tags."
            return
        }
        guard let uriPayload = NFCNDEFPayload.wellKnownTypeURIPayload(url: url) else {
            lastError = "That isn't a URL Tim can write."
            return
        }
        pending.value = NFCNDEFMessage(records: [uriPayload])
        session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: false)
        session?.alertMessage = "Hold your iPhone near the tag."
        session?.begin()
        isWriting = true
    }
}

extension TagWriter: NFCNDEFReaderSessionDelegate {

    nonisolated func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        // Unused: we take the richer `didDetect tags:` callback below, which
        // is the one that lets us write rather than only read.
    }

    nonisolated func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        Task { @MainActor in
            self.isWriting = false
            self.session = nil
            let code = (error as? NFCReaderError)?.code
            if code != .readerSessionInvalidationErrorUserCanceled,
               code != .readerSessionInvalidationErrorSessionTimeout {
                self.lastError = error.localizedDescription
            }
        }
    }

    nonisolated func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        guard let tag = tags.first else { return }
        guard let message = pending.value else {
            session.invalidate(errorMessage: "Nothing to write.")
            return
        }

        session.connect(to: tag) { error in
            if let error {
                session.invalidate(errorMessage: error.localizedDescription)
                return
            }
            tag.queryNDEFStatus { status, capacity, error in
                if let error {
                    session.invalidate(errorMessage: error.localizedDescription)
                    return
                }
                switch status {
                case .notSupported:
                    session.invalidate(errorMessage: "That tag can't hold a link.")
                case .readOnly:
                    session.invalidate(errorMessage: "That tag is locked.")
                case .readWrite:
                    guard message.length <= capacity else {
                        session.invalidate(errorMessage: "That tag is too small for this link.")
                        return
                    }
                    tag.writeNDEF(message) { error in
                        if let error {
                            session.invalidate(errorMessage: error.localizedDescription)
                            return
                        }
                        session.alertMessage = "Tag ready."
                        session.invalidate()
                        Task { @MainActor in
                            self.isWriting = false
                            self.didWrite = true
                        }
                    }
                @unknown default:
                    session.invalidate(errorMessage: "Unrecognised tag.")
                }
            }
        }
    }
}

/// Minimal lock-guarded holder so the NFC delegate queue and the MainActor can
/// both touch the outgoing message.
private final class PendingMessage: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: NFCNDEFMessage?

    var value: NFCNDEFMessage? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
