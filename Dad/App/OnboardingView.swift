import SwiftUI
import FamilyControls

/// Three short screens: what this is, whose phone it is, then the permission.
///
/// It was one screen with all three on it, and a beta tester found it hard to
/// follow: the role question sat under a paragraph with no explanation of
/// either answer, and the one that needs an iCloud Family said so only in an
/// error after the system prompt. The rest of setup — apps, tag, first tap —
/// lives on the home screen's checklist, because each of those needs the app
/// running and can be skipped and come back to.
struct OnboardingView: View {
    @EnvironmentObject private var model: DadModel

    private enum Page { case welcome, role, permission }
    @State private var page = Page.welcome

    var body: some View {
        VStack(spacing: 24) {
            switch page {
            case .welcome:    welcome
            case .role:       role
            case .permission: permission
            }
        }
        .padding(28)
        .animation(.default, value: page)
        // The model's banner alerts are otherwise only rendered by HomeView,
        // which doesn't exist yet while onboarding is on screen.
        .alert(Vocab.appName, isPresented: Binding(get: { model.banner != nil },
                                                   set: { if !$0 { model.banner = nil } })) {
            Button("OK") { model.banner = nil }
        } message: {
            Text(model.banner ?? "")
        }
    }

    // MARK: - Pages

    private var welcome: some View {
        Group {
            Spacer()
            Image(systemName: "iphone.gen3.slash")
                .font(.system(size: 64, weight: .thin))
                .foregroundStyle(Color.accentColor)
            Text(Vocab.tagline)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text("""
                 Choose the apps that eat your time. Tap your phone to an NFC tag \
                 and they disappear until you tap it again. Keep the tag in another \
                 room and the apps stay gone.
                 """)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Label("You'll need an NFC sticker — NTAG215 stickers are a safe buy.",
                  systemImage: "wave.3.right")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            primaryButton("Get started") { page = .role }
        }
    }

    private var role: some View {
        Group {
            Text("Whose phone is this?")
                .font(.title.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 24)

            // Asked before the permission, because the answer decides which
            // permission is requested. `.child` is a different, stricter ask
            // that Apple gates on an iCloud Family, and getting it wrong means
            // a household finds out weeks later that the arrangement was never
            // binding.
            roleChoice(.grownUp, title: "Mine", symbol: "person")
            roleChoice(.youngPerson, title: "A young person's", symbol: "figure.and.child.holdinghands")

            Spacer()
            primaryButton("Continue") { page = .permission }
            Button("Back") { page = .welcome }
        }
    }

    private var permission: some View {
        Group {
            Spacer()
            Image(systemName: "hourglass")
                .font(.system(size: 56, weight: .thin))
                .foregroundStyle(Color.accentColor)
            Text("Allow Screen Time access")
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text("""
                 \(Vocab.appName) hides apps through Screen Time — the same system \
                 behind Apple's own app limits. iOS asks you once. \(Vocab.appName) \
                 never learns which apps you pick; iOS keeps that to itself.
                 """)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            if model.authorization == .denied {
                Text("Screen Time access is off. Turn it on in Settings › Screen Time to use \(Vocab.appName).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            primaryButton("Allow") {
                Task { await model.requestAuthorization() }
            }
            Button("Back") { page = .role }
        }
    }

    // MARK: - Pieces

    private func roleChoice(_ value: HouseholdRole, title: String, symbol: String) -> some View {
        let isChosen = model.household.role == value
        return Button {
            model.setRole(value)
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbol)
                    .font(.title2)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(Vocab.roleExplanation(value))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: isChosen ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isChosen ? Color.accentColor : .secondary)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isChosen ? Color.accentColor : Color.secondary.opacity(0.3),
                              lineWidth: isChosen ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }
}
