import SwiftUI
// For `AuthorizationStatus`: `model.authorization` is a FamilyControls type,
// and `.approved` cannot be named without the module in scope. `RootView`
// carries the same import for the same one comparison.
import FamilyControls

/// Dad on a phone that is running in Assistive Access.
///
/// Layout only. What it says — including whether the one button appears at all
/// — is `AssistiveAccessScreen`, in Core, where `swift test` covers it.
///
/// What is deliberately *not* here is the rest of the app. The standard home
/// screen carries four toolbar destinations, a streak flame and a live timer;
/// Modes, Stats, Settings, the rewards ledger and the household board are all
/// a tap away. None of that belongs on a screen whose whole premise is that
/// there is one question and at most one thing to do. Nothing is unreachable
/// as a result — a trusted supporter turns Assistive Access off the same way
/// they turned it on, and the full app is there.
struct AssistiveAccessView: View {
    @EnvironmentObject private var model: DadModel

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            if model.authorization == .approved {
                screen
            } else {
                // Onboarding asks for Screen Time authorization, which is a
                // system prompt, a role question and a Mode picker — three
                // workflows that do not belong here. Say who can finish it
                // instead of starting something that cannot be completed.
                Text("Dad isn't set up yet.")
                    .font(.system(size: 34, weight: .bold))
                    .multilineTextAlignment(.center)
                Text("Ask whoever set up this phone to finish it.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var screen: some View {
        let state = model.assistiveAccessScreen

        Image(systemName: state.symbolName)
            .font(.system(size: 96, weight: .thin))
            .foregroundStyle(state.isDadded ? Color.accentColor : .secondary)
            .accessibilityHidden(true)

        Text(state.headline)
            .font(.system(size: 34, weight: .bold))
            .multilineTextAlignment(.center)

        Text(state.detail)
            .font(.title3)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)

        if let title = state.actionTitle {
            VStack(spacing: 8) {
                Button(title) { model.emergencyUnDad() }
                    .font(.title2.bold())
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                if let footnote = state.actionFootnote {
                    Text(footnote)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 12)
        }

        if let banner = model.banner {
            Text(banner)
                .font(.title3)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
        }
    }
}
