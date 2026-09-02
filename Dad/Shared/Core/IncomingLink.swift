import Foundation

/// What an incoming URL is asking for.
///
/// Three things open Dad by URL — a background NFC tag read, a Shortcuts
/// automation, and the Lock Screen widget — and they mean different things.
/// Deciding which is which used to live in the view model with an unrecognised
/// URL falling through to "toggle", so merely opening the app from the widget
/// would have released a live session. Now it is a pure function with an
/// explicit vocabulary, and anything unrecognised does nothing.
enum IncomingLink {

    enum Action: Equatable {
        /// `/tap` — what a tag means: start if free, release if Dadded.
        case toggle
        /// `/dad` — start, and do nothing if already Dadded.
        case dad
        /// `/undad` — release, and do nothing if already free.
        case unDad
        /// `/open` — just bring the app forward. Changes nothing.
        case open
    }

    static func action(for url: URL) -> Action? {
        // Two URL shapes reach here and they put the verb in different places.
        // A universal link from a tag is `https://host/tap` — path component.
        // A custom-scheme link like `dad://open` has no path at all: "open" is
        // the *host*. Reading only one of the two silently drops the other.
        let token = url.lastPathComponent.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let candidate = token.isEmpty ? (url.host ?? "") : token

        switch candidate.lowercased() {
        case "tap":   return .toggle
        case "dad":   return .dad
        case "undad": return .unDad
        case "open":  return .open
        default:
            // Deliberately not `.toggle`. An unrecognised link is far more
            // likely to be a typo, a stale automation, or a link we added for
            // some other purpose than a genuine request to change state — and
            // guessing wrong silently un-Dads someone.
            return nil
        }
    }

    /// The URL the widget opens. `/open` so a glance at the Lock Screen can
    /// never change anything.
    static let widgetURL = URL(string: "dad://open")!
}
