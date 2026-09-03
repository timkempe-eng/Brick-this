import SwiftUI
import FamilyControls

struct SettingsView: View {
    @EnvironmentObject private var model: DadModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var scanner = TagScanner()
    @StateObject private var writer = TagWriter()
    @State private var linkToWrite = ""

    @State private var showingSafePicker = false
    /// The picker gets its own state and writes back on dismiss, for the
    /// reason written out on `ModeEditorView`: binding a computed bridge that
    /// JSON round-trips on every read means the modifier clobbers the value
    /// during a render.
    @State private var safeSelection = FamilyActivitySelection()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        scanner.scan(prompt: "Hold your iPhone near the tag you want to pair.") { uid in
                            model.pair(tagUID: uid)
                        }
                    } label: {
                        Label("Pair a \(Vocab.tagNoun)", systemImage: "wave.3.right")
                    }

                    if model.pairedTagCount > 0 {
                        Button(role: .destructive) {
                            model.forgetAllTags()
                        } label: {
                            Label("Forget \(model.pairedTagCount) paired tag\(model.pairedTagCount == 1 ? "" : "s")",
                                  systemImage: "trash")
                        }
                    }
                } header: {
                    Text("Tags")
                } footer: {
                    Text(model.pairedTagCount == 0
                         ? "No tag paired yet, so any NFC tag will work. Pair one to lock Dad to it."
                         : "Only your paired tags can \(Vocab.verb) and \(Vocab.unVerb) this phone.")
                }

                Section {
                    Button {
                        showingSafePicker = true
                    } label: {
                        HStack {
                            Text("Apps and sites to keep")
                            Spacer()
                            Text("\(model.neverBlocked.totalCount)")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Never blocked")
                } footer: {
                    Text(model.neverBlocked.isEmpty
                         ? "Nothing is protected yet. Anything you put here stays reachable no matter which \(Vocab.modeNoun.lowercased()) is running — the place for your bank, your maps, and the people who need to reach you. Blocking a whole category is where this earns itself: it is easy to forget what is in one."
                         : "\(model.neverBlocked.summary) — reachable whatever is running. A \(Vocab.modeNoun.lowercased()) that names one of these anyway does not win; this list does.")
                }

                Section {
                    LabeledContent("Left this month", value: "\(model.emergencyUnDadsRemaining) of \(EmergencyAllowance.perWindow)")
                } header: {
                    Text(Vocab.emergencyUnDad)
                } footer: {
                    Text("Five overrides per rolling 30 days, for when the tag is genuinely out of reach. They come back on their own.")
                }

                Section {
                    Text("""
                         Set up a Shortcuts automation so a tap works with Dad closed: \
                         Shortcuts › Automation › NFC › scan your tag › add the \
                         “\(Vocab.dadAction)” action › turn off Ask Before Running.
                         """)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                } header: {
                    Text("Tapping without opening Dad")
                }

                Section {
                    TextField("https://dad.example.com/tap", text: $linkToWrite)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    Button {
                        guard let url = URL(string: linkToWrite), url.scheme == "https" else {
                            writer.lastError = "That needs to be an https link on a domain you own."
                            return
                        }
                        writer.write(url: url)
                    } label: {
                        Label(writer.didWrite ? "Written" : "Write link to a tag",
                              systemImage: writer.didWrite ? "checkmark" : "square.and.pencil")
                    }
                    .disabled(writer.isWriting || linkToWrite.isEmpty)
                } header: {
                    Text("Background tag reading")
                } footer: {
                    Text("""
                         Only needed if you want a tap to work with no Shortcuts automation \
                         at all. It takes a domain you control and an Associated Domains \
                         entitlement — see docs/nfc-and-tags.md. Most people should skip this.
                         """)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .familyActivityPicker(isPresented: $showingSafePicker, selection: $safeSelection)
            .onAppear { safeSelection = model.neverBlocked.familyActivitySelection }
            .onChange(of: showingSafePicker) { _, isShowing in
                if !isShowing { model.neverBlocked = BlockedSelection(safeSelection) }
            }
            .nfcErrorAlert($scanner.lastError)
            .nfcErrorAlert($writer.lastError)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }
}
