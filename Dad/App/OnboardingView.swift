import SwiftUI
import FamilyControls

/// One screen, one ask. Screen Time authorization is the only thing standing
/// between install and a working tap, so nothing else competes with it here.
struct OnboardingView: View {
    @EnvironmentObject private var model: DadModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "iphone.gen3.slash")
                .font(.system(size: 64, weight: .thin))
                .foregroundStyle(Color.accentColor)

            Text(Vocab.tagline)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)

            Text("""
                 Dad hides the apps you choose until you tap an NFC tag. \
                 Leave the tag in another room and the apps stay gone.

                 To do that it needs Screen Time access — the same system \
                 that powers Apple's own app limits. Dad never sees which \
                 apps you picked; iOS keeps that to itself.
                 """)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            if model.authorization == .denied {
                Text("Screen Time access is off. Turn it on in Settings › Screen Time to use Dad.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Asked before the permission, because the answer decides which
            // permission is requested. `.child` is a different, stricter ask
            // that Apple gates on an iCloud Family, and getting it wrong means
            // a household finds out weeks later that the arrangement was never
            // binding.
            Picker("Whose phone is this?", selection: Binding(
                get: { model.household.role },
                set: { model.setRole($0) }
            )) {
                Text("Mine").tag(HouseholdRole.grownUp)
                Text("A young person's").tag(HouseholdRole.youngPerson)
            }
            .pickerStyle(.segmented)

            Button {
                Task { await model.requestAuthorization() }
            } label: {
                Text("Allow Screen Time access").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(28)
        // The model's banner alerts are otherwise only rendered by HomeView,
        // which doesn't exist yet while onboarding is on screen.
        .alert(Vocab.appName, isPresented: Binding(get: { model.banner != nil },
                                                   set: { if !$0 { model.banner = nil } })) {
            Button("OK") { model.banner = nil }
        } message: {
            Text(model.banner ?? "")
        }
    }
}
