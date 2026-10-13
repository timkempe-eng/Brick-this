import SwiftUI

extension TagPairing.Pair: Identifiable {
    var id: String { uid }
}

/// One tag: what it is called, and what a tap on it starts.
///
/// The name is what Shortcuts lists the tag by, so it is asked for here rather
/// than left as a UID fragment. The steps for the automation sit beside it
/// because Apple gives an app no way to build that automation itself — the
/// most Clover can do is have the action already waiting, named after the tag.
struct TagEditorView: View {
    @EnvironmentObject private var model: DadModel
    @Environment(\.dismiss) private var dismiss

    private let uid: String
    private let originalName: String
    /// What the picker showed on arrival. A tag naming a deleted Mode shows
    /// "whichever you pick" — which is what it does — but is only re-pointed
    /// if the person changes it: `TagPairing.resolve` keeps the old id on
    /// purpose, in case the Mode was only briefly unreadable.
    private let originalModeID: UUID?

    @State private var name: String
    @State private var modeID: UUID?

    init(pair: TagPairing.Pair, modes: [DadMode]) {
        uid = pair.uid
        originalName = pair.name ?? ""
        let live = pair.modeID.flatMap { id in modes.contains { $0.id == id } ? id : nil }
        originalModeID = live
        _name = State(initialValue: pair.name ?? "")
        _modeID = State(initialValue: live)
    }

    private var shownName: String {
        TagPairing.Pair(uid: uid, name: name).displayName
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Home, Work, Kitchen…", text: $name)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Name")
                } footer: {
                    Text("Shortcuts lists this \(Vocab.tagNoun) by its name.")
                }

                Section {
                    Picker(Vocab.modeNoun, selection: $modeID) {
                        Text("Whichever you pick").tag(UUID?.none)
                        ForEach(model.modes.filter(\.blocksAnything)) { mode in
                            Text(mode.name).tag(UUID?.some(mode.id))
                        }
                    }
                } header: {
                    Text("A tap starts")
                } footer: {
                    Text("""
                         When you're outside, any of your \(Vocab.tagNoun)s brings the phone \
                         back in — this one included, whichever \(Vocab.modeNoun.lowercased()) \
                         is running.
                         """)
                }

                Section {
                    Label("Shortcuts › Automation › New Automation › NFC › Scan, and hold the phone near \(shownName).",
                          systemImage: "1.circle")
                    Label("Choose Run Immediately, then New Blank Automation.",
                          systemImage: "2.circle")
                    Label("Add the “\(Vocab.action)” action from \(Vocab.appName), tap Tag, and pick \(shownName).",
                          systemImage: "3.circle")
                } header: {
                    Text("Tapping without opening \(Vocab.appName)")
                } footer: {
                    Text("""
                         Apple doesn't let an app set this up for you, so it's three steps, \
                         once per \(Vocab.tagNoun). The automation then starts whatever \
                         this \(Vocab.tagNoun) starts — change the \(Vocab.modeNoun.lowercased()) \
                         above and it follows.
                         """)
                }
                .font(.footnote)

                Section {
                    Button(role: .destructive) {
                        model.unpair(tagUID: uid)
                        dismiss()
                    } label: {
                        Label("Unpair this \(Vocab.tagNoun)", systemImage: "trash")
                    }
                }
            }
            .navigationTitle(shownName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if name != originalName { model.rename(tagUID: uid, to: name) }
                        if modeID != originalModeID { model.point(tagUID: uid, to: modeID) }
                        dismiss()
                    }
                }
            }
        }
    }
}
