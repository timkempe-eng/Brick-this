import SwiftUI
import FamilyControls

struct RootView: View {
    @EnvironmentObject private var model: TimModel

    var body: some View {
        if model.authorization != .approved {
            OnboardingView()
        } else {
            HomeView()
        }
    }
}

/// The whole point of the home screen is to answer one question from across
/// the room: is the phone Timmed or not.
struct HomeView: View {
    @EnvironmentObject private var model: TimModel
    @StateObject private var scanner = TagScanner()
    @State private var showingModes = false
    @State private var showingSettings = false
    @State private var showingStats = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()

                Image(systemName: model.isTimmed ? "lock.iphone" : "iphone.gen3")
                    .font(.system(size: 72, weight: .thin))
                    .foregroundStyle(model.isTimmed ? Color.accentColor : .secondary)

                VStack(spacing: 8) {
                    Text(model.isTimmed ? Vocab.activeTitle : Vocab.idleTitle)
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)

                    if let session = model.activeSession {
                        Text(Vocab.activeSubtitle(mode: session.modeName))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Text(model.elapsedText)
                            .font(.system(size: 44, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .padding(.top, 4)
                    } else {
                        Text(Vocab.idleSubtitle)
                            .foregroundStyle(.secondary)

                        if model.stats.currentStreak > 0 {
                            let days = model.stats.currentStreak
                            Label("\(days) day\(days == 1 ? "" : "s") in a row",
                                  systemImage: "flame.fill")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                        }
                    }
                }
                .padding(.horizontal)

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        scanner.scan(prompt: model.isTimmed
                                     ? "Hold your iPhone near your \(Vocab.tagNoun) to \(Vocab.unVerb)."
                                     : "Hold your iPhone near your \(Vocab.tagNoun).") { uid in
                            model.tap(tagUID: uid)
                        }
                    } label: {
                        Label(model.isTimmed ? Vocab.unTimAction : Vocab.timAction,
                              systemImage: "wave.3.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!scanner.isAvailable)

                    if model.isTimmed {
                        Button(role: .destructive) {
                            model.emergencyUnTim()
                        } label: {
                            Text("\(Vocab.emergencyUnTim) (\(model.emergencyUnTimsRemaining) left)")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(model.emergencyUnTimsRemaining == 0)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .navigationTitle(Vocab.appName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingModes = true } label: { Image(systemName: "square.grid.2x2") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingStats = true } label: { Image(systemName: "chart.bar") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .nfcErrorAlert($scanner.lastError)
            .sheet(isPresented: $showingModes) { ModesView() }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(isPresented: $showingStats) { StatsView() }
            // Reached when a tap arrives and more than one mode could apply.
            .confirmationDialog("Which \(Vocab.modeNoun.lowercased())?",
                                isPresented: $model.pendingModeChoice,
                                titleVisibility: .visible) {
                ForEach(model.modes.filter(\.blocksAnything)) { mode in
                    Button(mode.name) { model.tap(mode: mode) }
                }
                if model.modes.allSatisfy({ !$0.blocksAnything }) {
                    Button("Set up a \(Vocab.modeNoun.lowercased())") { showingModes = true }
                }
            }
            .alert(Vocab.appName, isPresented: Binding(get: { model.banner != nil },
                                            set: { if !$0 { model.banner = nil } })) {
                Button("OK") { model.banner = nil }
            } message: {
                Text(model.banner ?? "")
            }
        }
    }
}

/// NFC failures are published by `TagScanner` and `TagWriter`; this puts them
/// in front of the user rather than leaving them on a property nobody reads.
extension View {
    func nfcErrorAlert(_ message: Binding<String?>) -> some View {
        alert("Tag trouble", isPresented: Binding(
            get: { message.wrappedValue != nil },
            set: { if !$0 { message.wrappedValue = nil } }
        )) {
            Button("OK") { message.wrappedValue = nil }
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}
