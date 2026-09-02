import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: DadModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var scanner = TagScanner()
    @StateObject private var writer = TagWriter()
    @State private var linkToWrite = ""

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
            .nfcErrorAlert($scanner.lastError)
            .nfcErrorAlert($writer.lastError)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }
}
