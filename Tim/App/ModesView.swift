import SwiftUI
import FamilyControls

struct ModesView: View {
    @EnvironmentObject private var model: TimModel
    @Environment(\.dismiss) private var dismiss
    @State private var editing: TimMode?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.modes) { mode in
                        Button { editing = mode } label: {
                            HStack {
                                Image(systemName: mode.symbol)
                                    .frame(width: 28)
                                    .foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mode.name).foregroundStyle(.primary)
                                    Text(summary(for: mode))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        offsets.map { model.modes[$0] }.forEach(model.delete)
                    }
                } footer: {
                    Text("A \(Vocab.modeNoun.lowercased()) is a set of apps to take away. Pick one when you \(Vocab.verb.lowercased()) your phone.")
                }

                Button {
                    editing = TimMode(name: "New \(Vocab.modeNoun)", symbol: "circle.dashed")
                } label: {
                    Label("Add a \(Vocab.modeNoun.lowercased())", systemImage: "plus")
                }
            }
            .navigationTitle("\(Vocab.modeNoun)s")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .sheet(item: $editing) { mode in
                ModeEditorView(mode: mode) { model.save($0) }
            }
        }
    }

    private func summary(for mode: TimMode) -> String {
        let apps = mode.selection.applicationTokens.count
        let categories = mode.selection.categoryTokens.count
        let sites = mode.selection.webDomainTokens.count
        guard apps + categories + sites > 0 else { return "Nothing blocked yet" }
        var parts: [String] = []
        if apps > 0 { parts.append("\(apps) app\(apps == 1 ? "" : "s")") }
        if categories > 0 { parts.append("\(categories) categor\(categories == 1 ? "y" : "ies")") }
        if sites > 0 { parts.append("\(sites) site\(sites == 1 ? "" : "s")") }
        if mode.isStrict { parts.append("strict") }
        return parts.joined(separator: " · ")
    }
}

struct ModeEditorView: View {
    @State var mode: TimMode
    let onSave: (TimMode) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showingPicker = false

    /// Offered auto-release lengths. `DeviceActivitySchedule` won't monitor an
    /// interval under 15 minutes, so the shortest option is 15.
    private struct AutoRelease: Identifiable {
        let id: String
        let seconds: TimeInterval?
    }

    private let durations: [AutoRelease] = [
        AutoRelease(id: "Until I tap again", seconds: nil),
        AutoRelease(id: "15 minutes", seconds: 15 * 60),
        AutoRelease(id: "30 minutes", seconds: 30 * 60),
        AutoRelease(id: "1 hour", seconds: 60 * 60),
        AutoRelease(id: "2 hours", seconds: 2 * 60 * 60),
        AutoRelease(id: "4 hours", seconds: 4 * 60 * 60),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $mode.name)
                }

                Section {
                    Button {
                        showingPicker = true
                    } label: {
                        HStack {
                            Text("Apps and sites to hide")
                            Spacer()
                            Text("\(mode.selection.applicationTokens.count + mode.selection.categoryTokens.count + mode.selection.webDomainTokens.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("Chosen with Apple's own picker. Tim receives anonymous tokens, not the names of your apps.")
                }

                Section {
                    Picker("\(Vocab.unVerb) automatically", selection: $mode.autoUnTimAfter) {
                        ForEach(durations) { option in
                            Text(option.id).tag(option.seconds)
                        }
                    }
                    Toggle("Strict", isOn: $mode.isStrict)
                } footer: {
                    Text("Strict stops Tim being deleted while your phone is \(Vocab.verbPast.lowercased()) — the fastest way to cheat.")
                }
            }
            .navigationTitle(mode.name)
            .navigationBarTitleDisplayMode(.inline)
            .familyActivityPicker(isPresented: $showingPicker, selection: $mode.selection)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { onSave(mode); dismiss() }
                        .disabled(mode.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
