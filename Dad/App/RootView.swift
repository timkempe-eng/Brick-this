import SwiftUI
import FamilyControls

/// Lets the UI tests past the Screen Time gate.
///
/// A Simulator never grants Family Controls authorization, so without this
/// every screen except onboarding is unreachable in CI — six hundred lines of
/// SwiftUI that only ever run for the first time on someone's phone.
///
/// Compiled out of Release entirely, so a shipping build cannot contain the
/// bypass at all, let alone be talked into it. Launch arguments are not
/// something a user can set on an installed app in any case; the `#if DEBUG`
/// is belt as well as braces.
enum UITestHooks {
    static let bypassOnboarding = "-DadBypassOnboarding"

    static var isBypassingOnboarding: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains(bypassOnboarding)
        #else
        false
        #endif
    }
}

struct RootView: View {
    @EnvironmentObject private var model: DadModel

    var body: some View {
        if model.authorization != .approved && !UITestHooks.isBypassingOnboarding {
            OnboardingView()
        } else {
            HomeView()
        }
    }
}

/// The whole point of the home screen is to answer one question from across
/// the room: is the phone Dadded or not.
struct HomeView: View {
    @EnvironmentObject private var model: DadModel
    @StateObject private var scanner = TagScanner()
    @State private var showingModes = false
    @State private var showingSettings = false
    @State private var showingStats = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()

                Image(systemName: model.isDadded ? "lock.iphone" : "iphone.gen3")
                    .font(.system(size: 72, weight: .thin))
                    .foregroundStyle(model.isDadded ? Color.accentColor : .secondary)

                VStack(spacing: 8) {
                    Text(model.isDadded ? Vocab.activeTitle : Vocab.idleTitle)
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
                        scanner.scan(prompt: model.isDadded
                                     ? "Hold your iPhone near your \(Vocab.tagNoun) to \(Vocab.unVerb)."
                                     : "Hold your iPhone near your \(Vocab.tagNoun).") { uid in
                            model.tap(tagUID: uid)
                        }
                    } label: {
                        Label(model.isDadded ? Vocab.unDadAction : Vocab.dadAction,
                              systemImage: "wave.3.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!scanner.isAvailable)

                    if model.isDadded {
                        Button(role: .destructive) {
                            model.emergencyUnDad()
                        } label: {
                            Text("\(Vocab.emergencyUnDad) (\(model.emergencyUnDadsRemaining) left)")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(model.emergencyUnDadsRemaining == 0)
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
                        .accessibilityLabel("\(Vocab.modeNoun)s")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingStats = true } label: { Image(systemName: "chart.bar") }
                        .accessibilityLabel("Stats")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
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
