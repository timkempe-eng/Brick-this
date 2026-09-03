import Foundation

/// Which sticker starts which Mode.
///
/// A Brick has one puck and one Mode per puck, at $59 each. Here the stickers
/// cost thirty cents, so the interesting question is not *whether* a tag is
/// yours but *what it means*: the kitchen tag starts Dinner, the desk tag
/// starts Deep Work, the bedside tag starts Sleep. That is the whole feature,
/// and it is a mapping — so it lives in one value type rather than spread
/// across the engine, the store and the settings screen.
///
/// The mapping it owns is `tag UID → optional Mode id`:
///
/// - `.some(id)` — this tag names a Mode. Tapping it starts that Mode.
/// - `nil`       — this tag toggles and the app decides which Mode, which is
///                 exactly what every tag did before this type existed. Every
///                 tag paired by an older build reads back this way, so the
///                 old behaviour is the default rather than a special case.
///
/// An **empty** pairing list means "any tag works". That is the state before
/// anything has been paired and it has to keep meaning that: a fresh install
/// where the first tap is refused because no tag is paired yet, and no tag can
/// be paired without a tap, is a product that cannot be started.
struct TagPairing: Equatable, Codable {

    /// One sticker.
    ///
    /// UIDs are compared exactly, character for character as the adapter
    /// formatted them. Normalising case here would look tidier and would
    /// quietly stop matching the UIDs already on disk, which reads as "my tag
    /// stopped working" with nothing on screen to explain it. The adapter owns
    /// the format; this type owns the mapping.
    struct Pair: Equatable, Hashable, Codable {
        var uid: String

        /// The Mode this tag names, or `nil` for "toggle, app's choice".
        var modeID: UUID?

        init(uid: String, modeID: UUID? = nil) {
            self.uid = uid
            self.modeID = modeID
        }
    }

    /// What a tap on a given UID should do.
    ///
    /// An enum rather than an optional `UUID`, because there are three answers
    /// and only two of them are "a Mode": a stranger's tag is not the same
    /// thing as a tag of yours that doesn't name a Mode, and collapsing the two
    /// into `nil` is how a stranger's tag ends up Dadding your phone.
    enum Resolution: Equatable {
        /// Not one of yours. The engine refuses the tap.
        case unknownTag
        /// Yours, but unnamed — the app picks the Mode, as it always has.
        case anyMode
        /// Yours, and it names this Mode.
        case mode(UUID)
    }

    /// In pairing order, which is the order Settings lists them in. Order is
    /// preserved rather than sorted so that "the one I just paired" stays
    /// where the user last saw it.
    private(set) var pairs: [Pair]

    init() {
        self.pairs = []
    }

    /// Duplicate UIDs are collapsed, first occurrence winning.
    ///
    /// Two rows for one sticker is a state the API below cannot produce, but
    /// stored JSON can be anything — a half-written write, a hand-edited
    /// plist, a future build with a different idea. Deciding it here means
    /// every question below has one answer instead of "the first one,
    /// probably".
    init(_ pairs: [Pair]) {
        var seen = Set<String>()
        self.pairs = pairs.filter { seen.insert($0.uid).inserted }
    }

    /// The shape before this type existed: a flat list of UIDs, every one of
    /// them a toggle. Used by the migration, and by anything still holding a
    /// `[String]`.
    init(uids: [String]) {
        self.init(uids.map { Pair(uid: $0) })
    }

    // MARK: - The questions the engine asks

    /// Nothing paired at all. Means "any tag works", not "no tag works".
    var isEmpty: Bool { pairs.isEmpty }

    /// How many stickers are paired. Settings shows this, and it is also what
    /// "Forget paired tags" is offering to throw away.
    var count: Int { pairs.count }

    var uids: [String] { pairs.map(\.uid) }

    /// Whether a tap from this UID is allowed at all.
    ///
    /// The empty case is load-bearing and is the reason this is not simply
    /// `contains`. See the type comment.
    func isPaired(_ uid: String) -> Bool {
        pairs.isEmpty || pairs.contains { $0.uid == uid }
    }

    /// The Mode this tag names, if any — without judging whether that Mode
    /// still exists. `resolve` is what a caller acting on a tap should ask;
    /// this is for the settings screen, which wants to show what the user
    /// configured even when it currently points at nothing.
    func modeID(for uid: String) -> UUID? {
        pairs.first { $0.uid == uid }?.modeID
    }

    /// What a tap on `uid` means, given the Modes that currently exist.
    ///
    /// `knownModeIDs` is passed in rather than reached for: this type never
    /// holds Modes, so a Mode list and a tag list cannot drift apart inside it.
    ///
    /// **A tag naming a deleted Mode falls back to toggling — it does not stop
    /// working.** The alternative is a sticker on the fridge that silently
    /// does nothing, which is the failure this codebase exists to avoid, and
    /// it would arrive weeks after the delete that caused it with no screen
    /// anywhere connecting the two. Deleting a Mode is a statement about
    /// Modes; the user never touched the sticker. Falling back returns the tag
    /// to precisely the behaviour it had before it was named — a tap still
    /// Dads the phone — and a Dad session is the least silent thing this app
    /// does, since every app on the phone disappears and the shield says which
    /// Mode took them. A surprising Mode is visible and one tap from undone; a
    /// dead tag is invisible.
    ///
    /// The fallback is decided *here*, on read, and the stored pairing is
    /// deliberately left pointing at the missing id. Rewriting it at delete
    /// time would look tidier and would be wrong: `modes` decodes leniently,
    /// so a Mode can also vanish because one record was briefly unreadable —
    /// and a build that repaired pairings on sight would permanently forget
    /// which Mode the kitchen tag meant, over a Mode that came back on the
    /// next launch. Read-time resolution costs nothing and forgets nothing.
    ///
    /// `danglingUIDs` exists so this stays a fallback rather than a secret:
    /// Settings can offer to re-point the tag instead of leaving the user to
    /// notice on their own.
    func resolve(_ uid: String, knownModeIDs: Set<UUID>) -> Resolution {
        guard isPaired(uid) else { return .unknownTag }
        guard let modeID = modeID(for: uid) else { return .anyMode }
        return knownModeIDs.contains(modeID) ? .mode(modeID) : .anyMode
    }

    /// Tags pointing at a Mode that no longer exists, in pairing order.
    ///
    /// Empty is the normal answer. A non-empty one is something to say out
    /// loud — "the kitchen tag pointed at Dinner, which is gone; it now starts
    /// whatever you pick" — because the only thing worse than a tag doing the
    /// wrong thing is a tag doing the wrong thing quietly.
    func danglingUIDs(knownModeIDs: Set<UUID>) -> [String] {
        pairs.compactMap { pair in
            guard let modeID = pair.modeID, !knownModeIDs.contains(modeID) else { return nil }
            return pair.uid
        }
    }

    // MARK: - Editing

    /// Pairs a tag, or re-points one already paired.
    ///
    /// Idempotent in both senses: pairing the same tag twice does not add a
    /// second row, and re-pointing keeps the tag's place in the list. Tapping
    /// a tag you already own is the normal way to find out its UID, so it
    /// happens constantly.
    mutating func pair(_ uid: String, to modeID: UUID? = nil) {
        if let i = pairs.firstIndex(where: { $0.uid == uid }) {
            pairs[i].modeID = modeID
        } else {
            pairs.append(Pair(uid: uid, modeID: modeID))
        }
    }

    mutating func unpair(_ uid: String) {
        pairs.removeAll { $0.uid == uid }
    }

    /// Back to "any tag works". What the Settings button means: not "lock me
    /// out", but "forget the stickers I have and let me start again".
    mutating func forgetAll() {
        pairs.removeAll()
    }

    // MARK: - Coding

    /// Stored as the bare array of pairs — no wrapper object — so the value on
    /// disk is one step from the flat `["04A2", …]` it replaces, and a future
    /// migration reading it has as little shape to recognise as possible.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Element by element, for the same reason `LenientDecoding` exists:
        // one unreadable row should cost one sticker, not the keyring. That
        // helper takes `Data` rather than a `Decoder`, so the trick is spelled
        // out again here.
        //
        // A payload that is not an array at all still throws, which is what
        // lets `SchemaCoding` tell "stored but corrupt" from "stored empty" —
        // and the two are not the same, because only the first one is a reason
        // to say anything to the user.
        let rows = try container.decode([LenientPair].self)
        self.init(rows.compactMap(\.pair))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(pairs)
    }

    /// Decoding is deliberately strict about the *old* shape: a bare
    /// `["04A2"]` does not decode as a `TagPairing`, it is migrated into one.
    /// A decoder that quietly accepted both would make the ladder step below
    /// untestable and would hide a step that was never wired in — the data
    /// would read fine forever through a compatibility path nobody knew was
    /// load-bearing.
    private struct LenientPair: Decodable {
        let pair: Pair?

        init(from decoder: Decoder) throws {
            pair = try? Pair(from: decoder)
        }
    }

    // MARK: - Migration

    /// The stored-shape change this type causes, written as a step for
    /// `SchemaCoding`'s ladder.
    ///
    /// `SchemaCoding.current` is 1 and its only step, 0 → 1, moved no data at
    /// all — it wrapped values in an envelope and the payload was untouched.
    /// This is the first time a stored shape actually changes, so it is the
    /// first step that has to do something. It lives here rather than in
    /// `SchemaCoding` because the ladder is a mechanism, while the knowledge
    /// of what a paired-tag payload looks like belongs beside the type that
    /// defines it.
    enum Migration {

        /// The version that stores `["04A2", "0B11"]`.
        static let flatUIDList = 1
        /// The version that stores `[{"uid": "04A2", "modeID": "…"}, …]`.
        static let namedPairs = 2

        private enum Key {
            static let uid = "uid"
        }

        /// 1 → 2: a flat list of UIDs becomes a list of pairs, each toggling.
        ///
        /// Written against JSON — `[Any]`, `[String: Any]` — rather than
        /// against `[String]` and `TagPairing`, exactly as `SchemaCoding`
        /// already does, for a reason that only bites later: a migration
        /// outlives the type it migrates *from*. The day `[String]` stops
        /// being how tags are stored, the Swift type describing it is deleted,
        /// and a migration written in terms of that type either stops
        /// compiling or — worse — gets quietly "fixed" into meaning something
        /// else. JSON is the only description of the old shape that cannot
        /// rot, because it is what is actually on the device.
        ///
        /// Three properties this step must have, none of them optional:
        ///
        /// 1. **Shape-directed.** `SchemaCoding.migrate` does not know which
        ///    key it is reading — the same ladder runs over Modes, history,
        ///    the active session and the emergency-use log — so a step that
        ///    rewrote every payload would rewrite all of them. Today a bare
        ///    array of strings is the paired-tag list and nothing else (Modes,
        ///    history and synced schedules are arrays of objects; emergency
        ///    uses are numbers), which is what makes recognition by shape
        ///    safe. If a future key ever stores a bare `[String]`, that stops
        ///    being true and migration has to become key-aware. That is the
        ///    trade, written down here rather than discovered later.
        ///
        /// 2. **Idempotent.** A value already in the new shape is an array of
        ///    objects, not of strings, so it is not recognised and comes back
        ///    untouched. Migrating twice would produce pairs whose UIDs were
        ///    the *description* of a dictionary, and every sticker in the
        ///    house would stop being recognised on the same launch.
        ///
        /// 3. **Total.** It returns `Any`, never `nil`. In the ladder `nil`
        ///    means "unreadable", and unreadable means the caller falls back
        ///    to its default — for the Modes key that is the user's Modes
        ///    replaced by the starters. A step that does not recognise a
        ///    payload hands it back unchanged and lets decoding be the judge.
        static func flatUIDListToNamedPairs(_ payload: Any) -> Any {
            // An empty array is ambiguous — empty tags, empty Modes and empty
            // history all look identical — and `[]` is already correct in both
            // shapes, so there is nothing to do and no reason to claim this
            // payload as ours.
            guard let array = payload as? [Any], !array.isEmpty else { return payload }

            // Every element a string, or it is not the tag list. A mixed array
            // is not a half-valid tag list to be salvaged; it is another key,
            // or damage, and either way this step is not the place to decide.
            // Handing it back unchanged lets it decode or fail on its own
            // merits.
            guard let uids = array as? [String] else { return payload }

            // `modeID` is left out rather than written as null: an absent key
            // decodes to `nil` for an optional, and every migrated tag is a
            // toggle — the behaviour it had before this file existed.
            return uids.map { [Key.uid: $0] }
        }
    }
}
