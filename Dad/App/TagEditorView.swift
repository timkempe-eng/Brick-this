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
    /// What the list showed ticked on arrival. A deleted Mode is not shown —
    /// a tap no longer starts it — and nor is one that blocks nothing, which
    /// a tap passes over. Either is the tag is only re-pointed if the
    /// person changes something: `TagPairing.resolve` keeps the old id on
    /// purpose, in case the Mode was only briefly unreadable.
    private let originalModeIDs: [UUID]

    @State private var name: String
    /// In the order they were ticked, which is the order a tap offers them.
    @State private var modeIDs: [UUID]

    init(pair: TagPairing.Pair, modes: [DadMode]) {
        uid = pair.uid
        originalName = pair.name ?? ""
        let live = pair.modeIDs.filter { id in modes.contains { $0.id == id && $0.blocksAnything } }
        originalModeIDs = live
        _name = State(initialValue: pair.name ?? "")
        _modeIDs = State(initialValue: live)
    }

    private func toggle(_ id: UUID) {
        if let i = modeIDs.firstIndex(of: id) {
            modeIDs.remove(at: i)
        } else {
            modeIDs.append(id)
        }
    }

    private var startsFooter: String {
        switch modeIDs.count {
        case 0:
            return "Nothing ticked: a tap starts your only \(Vocab.modeNoun.lowercased()), or asks which if you have several."
        case 1:
            return "A tap starts it straight away. Tick another and a tap asks which, offering only the ones ticked here."
        default:
            return "A tap asks which, offering only these."
        }
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
                    ForEach(model.modes.filter(\.blocksAnything)) { mode in
                        Button { toggle(mode.id) } label: {
                            HStack {
                                Text(mode.name)
                                Spacer()
                                if modeIDs.contains(mode.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                } header: {
                    Text("A tap starts")
                } footer: {
                    Text("""
                         \(startsFooter) When you're outside, any of your \(Vocab.tagNoun)s \
                         brings the phone back in.
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
                        if modeIDs != originalModeIDs { model.point(tagUID: uid, to: modeIDs) }
                        dismiss()
                    }
                }
            }
        }
    }
}
