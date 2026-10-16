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
    /// The Mode the setup card's "choose apps" step is filling in.
    @State private var settingUpMode: DadMode?

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()

                Image(systemName: model.statusSymbol)
                    .font(.system(size: 72, weight: .thin))
                    .foregroundStyle(model.isDadded ? Color.accentColor : .secondary)

                VStack(spacing: 8) {
                    Text(model.statusTitle)
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)

                    if model.isDadded {
                        Text(model.statusSubtitle)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Text(model.elapsedText)
                            .font(.system(size: 44, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .padding(.top, 4)
                        if let progress = model.hourProgressText {
                            VStack(spacing: 2) {
                                Label(progress, systemImage: "star.circle")
                                    .font(.subheadline)
                                    .monospacedDigit()
                                Text(HourProgress.caveat)
                                    .font(.caption)
                            }
                            .foregroundStyle(.secondary)
                        }
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
                    // Idle only: while outside the screen has one job, and a
                    // checklist under the timer is a second one.
                    if model.showsSetupCard, !model.isDadded, model.pendingResume == nil {
                        SetupCard(checklist: model.setupChecklist,
                                  canScan: scanner.isAvailable,
                                  chooseApps: {
                                      settingUpMode = model.modes.first
                                          ?? DadMode(name: "Deep Work", symbol: "brain.head.profile")
                                  },
                                  pairTag: { pairTag() },
                                  finish: { model.finishSetup() })
                    }

                    Button {
                        scanner.scan(prompt: model.isDadded
                                     ? "Hold your iPhone near your \(Vocab.tagNoun) to \(Vocab.releaseInProse)."
                                     : "Hold your iPhone near your \(Vocab.tagNoun).",
                                     // The household exchange rides along on the
                                     // same session, so it costs no second
                                     // prompt and no separate ceremony. It is
                                     // also the only moment it can happen: a tap
                                     // through a Shortcuts automation has no UI
                                     // and cannot open a write session.
                                     ledger: model.ledgerToWrite,
                                     own: model.myStanding,
                                     onLedger: { model.absorb(tagLedger: $0) }) { uid in
                            model.tap(tagUID: uid)
                        }
                    } label: {
                        Label(model.tapActionText, systemImage: "wave.3.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!scanner.isAvailable)

                    // Asking is offered before the override, deliberately: on a
                    // young person's phone the override is the last resort and
                    // the ask is the everyday thing, and a screen that offers
                    // the hatch first teaches you to reach for it.
                    if model.isDadded, model.household.role == .youngPerson {
                        if let asking = model.pendingRequest {
                            VStack(spacing: 8) {
                                Text(Vocab.asking(mode: asking.request.modeName))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                Button("Take the ask back") { model.withdrawRequest() }
                                    .buttonStyle(.bordered)
                                    .controlSize(.large)
                                    .frame(maxWidth: .infinity)
                            }
                        } else {
                            Button(Vocab.askAction) { model.askForARelease() }
                                .buttonStyle(.bordered)
                                .controlSize(.large)
                                .frame(maxWidth: .infinity)
                        }
                    }

                    if model.isDadded {
                        Button(role: .destructive) {
                            model.emergencyUnDad()
                        } label: {
                            Text("\(Vocab.emergencyRelease) (\(model.emergencyUnDadsRemaining) left)")
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
                    // Named, not just drawn: an unlabelled grid was where a
                    // new user had to guess the apps were chosen.
                    Button { showingModes = true } label: {
                        Label("\(Vocab.modeNoun)s", systemImage: "square.grid.2x2")
                            .labelStyle(.titleAndIcon)
                    }
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
            // Assigned, not gated on `true`: a successful write has to be able
            // to clear it, or the copy about pairing an unlocked tag never
            // goes away after somebody pairs one.
            .onChange(of: scanner.tagIsReadOnly) { _, isReadOnly in
                model.tagIsWriteProtected = isReadOnly
            }
            .onChange(of: scanner.membersThatDidNotFit) { _, count in
                model.membersThatDidNotFit = count
            }
            .nfcErrorAlert($scanner.lastError)
            .sheet(isPresented: $showingModes) { ModesView() }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(isPresented: $showingStats) { StatsView() }
            .sheet(item: $settingUpMode) { mode in
                ModeEditorView(mode: mode, opensPicker: true) { model.save($0) }
            }
            // Reached when a tap arrives and more than one mode could apply.
            .confirmationDialog("Which \(Vocab.modeNoun.lowercased())?",
                                isPresented: $model.pendingModeChoice,
                                titleVisibility: .visible) {
                // Never empty: a tap with nothing to choose between says
                // `Vocab.nothingToHideYet` instead of asking.
                ForEach(model.modeChoices) { mode in
                    Button(mode.name) { model.tap(mode: mode) }
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

extension HomeView {
    /// The same pairing Settings does, offered where a new user is looking.
    fileprivate func pairTag() {
        scanner.scan(prompt: "Hold your iPhone near the tag you want to pair.") { uid in
            if !model.tags.contains(where: { $0.uid == uid }) {
                model.pair(tagUID: uid)
            }
        }
    }
}

/// What is left between this phone and a tap that takes something away.
///
/// Every step but the last card is read off the data — see `SetupChecklist` —
/// so it ticks itself off when the thing is done from anywhere, Settings
/// included, and comes back if it is undone.
private struct SetupCard: View {
    let checklist: SetupChecklist
    let canScan: Bool
    let chooseApps: @MainActor () -> Void
    let pairTag: @MainActor () -> Void
    let finish: @MainActor () -> Void

    private let steps = SetupChecklist.Step.allCases

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let next = checklist.next {
                HStack {
                    Text(Vocab.setupTitle).font(.headline)
                    Spacer()
                    Text("\(checklist.done.count) of \(steps.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                ForEach(steps, id: \.self) { step in
                    row(step, isNext: step == next)
                }
            } else {
                Text(Vocab.setupFinishingTitle).font(.headline)
                Label(Vocab.setupShortcutsTip, systemImage: "bolt.horizontal")
                    .font(.subheadline)
                Label(Vocab.setupPlacementTip, systemImage: "house")
                    .font(.subheadline)
                Button(Vocab.setupDoneAction, action: finish)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
    }

    private func row(_ step: SetupChecklist.Step, isNext: Bool) -> some View {
        let isDone = checklist.done.contains(step)
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isDone ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(Vocab.setupStepTitle(step))
                    .font(.subheadline.weight(isNext ? .semibold : .regular))
                    .foregroundStyle(isDone ? .secondary : .primary)
                if isNext {
                    Text(Vocab.setupStepDetail(step))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let action = Vocab.setupStepAction(step) {
                        Button(action) {
                            if step == .chooseApps { chooseApps() } else { pairTag() }
                        }
                        .buttonStyle(.bordered)
                        .disabled(step == .pairTag && !canScan)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(Vocab.setupStepTitle(step)), \(isDone ? "done" : "not done yet")")
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
