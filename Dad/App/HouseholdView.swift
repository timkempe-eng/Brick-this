import SwiftUI

/// Who this phone is for, and — if it belongs to a young person — the ladder.
///
/// The ladder screen is not decoration. "A reward you cannot predict is not an
/// incentive" is the finding the whole feature rests on, so every rung, what it
/// costs and what it unlocks has to be visible *before* it is reached. That is
/// why `AutonomyLadder` exposes requirements and progress as data rather than
/// prose: this file renders numbers the tests are already asserting on.
///
/// It shows the same thing to both people. There is no parent view and no child
/// view, deliberately — a household where one person can see a screen the other
/// cannot is one where the tool is a surveillance product, and the README says
/// plainly that this one is not.
struct HouseholdView: View {
    @EnvironmentObject private var model: DadModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingRewards = false
    @State private var showingAgreements = false

    var body: some View {
        NavigationStack {
            List {
                roleSection
                sharedStreakSection
                agreementsSection
                rewardsSection

                if model.household.role == .youngPerson {
                    ladderSection
                    rungsSection
                }
            }
            .navigationTitle("This phone")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingRewards) { RewardsView() }
            .sheet(isPresented: $showingAgreements) { AgreementsBoardView() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }

    // MARK: - Whose phone

    private var roleSection: some View {
        Section {
            Picker("Whose phone", selection: Binding(
                get: { model.household.role },
                set: { model.setRole($0) }
            )) {
                Text("Mine").tag(HouseholdRole.grownUp)
                Text("A young person's").tag(HouseholdRole.youngPerson)
            }
            .pickerStyle(.inline)
        } header: {
            Text("Whose phone this is")
        } footer: {
            Text(model.household.role == .grownUp
                 ? "You chose the \(Vocab.modeNoun.lowercased())s and you hold the \(Vocab.tagNoun). Nothing on this phone asks anyone's permission."
                 : "The \(Vocab.modeNoun.lowercased())s here were agreed with a grown-up, so this phone can't rewrite them on its own. How much of the arrangement it *can* change grows as the habit holds — see below.")
        }
    }

    // MARK: - Why each rule is here

    /// The way in to the agreements board, with the one number worth putting
    /// on the row: how many rules are due to be talked about.
    ///
    /// Due, not overdue-and-you-should-feel-bad. The count is a fact and the
    /// row says nothing when it is nought — an empty household gets an empty
    /// string rather than a congratulation, which `AgreementCopy` handles.
    private var agreementsSection: some View {
        Section {
            Button { showingAgreements = true } label: {
                HStack {
                    Text("Why each \(Vocab.modeNoun.lowercased()) is here")
                    Spacer()
                    Text(model.householdAgreements.nothingToRaise
                         ? "" : AgreementCopy.overdueHeadline(count: model.householdAgreements.overdue.count))
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text("""
                 Written in your own words, with a date to talk about it again. \
                 Restrictions are meant to shrink as trust grows, and a rule with no \
                 date to come up again cannot shrink — it can only be argued about.
                 """)
        }
    }

    // MARK: - What the days buy

    /// The way in to the rewards ledger.
    ///
    /// On the household screen rather than in Settings because it is an
    /// arrangement between two people, not a preference. The subtitle is the
    /// balance, so the screen is worth opening before it is opened.
    private var rewardsSection: some View {
        Section {
            Button { showingRewards = true } label: {
                HStack {
                    Text("Rewards")
                    Spacer()
                    Text(model.rewardLedger.balance.description)
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text("""
                 Days earned at the \(Vocab.tagNoun), spent on things a grown-up offers — \
                 never on minutes. A blocker that pays you in the thing it took away has \
                 agreed the thing was worth having.
                 """)
        }
    }

    // MARK: - The number both phones see

    /// The shared streak, and how fresh it is.
    ///
    /// A parent's own device habits are among the strongest predictors of
    /// their child's, and a blocker running on exactly one phone in the house
    /// reads as a punishment. So this counts the days *everyone* took part —
    /// which means the grown-up's phone can end it, and that is the point
    /// rather than a side effect.
    ///
    /// The freshness is never hidden. The exchange happens on a tap made
    /// inside the app, so the number can lag by days, and a lagging number
    /// presented as a live one is worse than no number at all.
    @ViewBuilder
    private var sharedStreakSection: some View {
        Section {
            if let streak = model.householdStreak {
                LabeledContent("Everyone, together") {
                    Text(streak.days == 1 ? "1 day" : "\(streak.days) days")
                        .foregroundStyle(streak.isCurrent ? .primary : .secondary)
                }
                LabeledContent("Phones in it", value: "\(streak.members)")
            } else {
                Text("Just this phone so far.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Together")
        } footer: {
            Text(sharedStreakFooter)
        }
    }

    private var sharedStreakFooter: String {
        guard let streak = model.householdStreak else {
            return """
                Tap the same \(Vocab.tagNoun) with another phone in the house and it \
                joins in. The \(Vocab.tagNoun) carries the count itself — no account, \
                no sign-in, and nothing about either of you leaves it. A grown-up who \
                \(Vocab.verbThirdPerson) too is the single strongest thing this app has.
                """
        }
        if model.tagIsWriteProtected {
            // Never tell somebody to tap a tag that cannot answer. This phone
            // read the household off it and could not write back, so the
            // number is frozen wherever it is until a different tag is used.
            return """
                That \(Vocab.tagNoun) is write-protected, so this phone can read the \
                household from it but never add itself. Counted to \
                \(streak.asOf?.description ?? "an earlier day"). Pair a \(Vocab.tagNoun) \
                that isn't locked and the number starts moving again.
                """
        }
        if !streak.isCurrent {
            return """
                Counted to \(streak.asOf?.description ?? "an earlier day"), because that \
                is the last time every phone touched the \(Vocab.tagNoun). Tap it to bring \
                this up to date — the number only moves when the \(Vocab.tagNoun) sees you.
                """
        }
        return """
            Days every phone in the house took part, so anyone can end it and nobody \
            can carry it alone. Updated whenever a phone taps the \(Vocab.tagNoun) from \
            inside \(Vocab.appName) — a Shortcuts tap is too quick to write to it.
            """
    }

    // MARK: - Where they are

    private var ladderSection: some View {
        Section {
            LabeledContent("Now", value: model.ladder.rung.title)
            LabeledContent("Clean days", value: "\(model.ladder.cleanDayCount)")
            LabeledContent("Longest run", value: "\(model.ladder.longestCleanStreak) days")

            if let next = model.ladder.nextRung, let progress = model.ladder.progressToNextRung {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Next: \(next.title)")
                        .font(.subheadline.weight(.semibold))
                    ProgressView(value: progress.fraction)
                    Text(remaining(progress))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Where this phone is")
        } footer: {
            Text(ladderFooter)
        }
    }

    private var ladderFooter: String {
        switch model.ladder.demotionWarning {
        case .none:
            return model.ladder.nextRung == nil
                ? "Top of the ladder. This phone runs \(Vocab.appName) the way an adult's does."
                : "Rungs are earned by using the tag, never by anything else, and never bought with screen time."
        case .approaching(let rung, let inDays):
            return "\(rung.title) goes back on the shelf in \(inDays) day\(inDays == 1 ? "" : "s") without a session. It comes back after \(AutonomyLadder.restoreDays) clean days."
        case .withheld(let rung, let cleanDays):
            return "\(rung.title) is set aside for now. \(cleanDays) clean day\(cleanDays == 1 ? "" : "s") brings it back — nothing is ever lost, only put down."
        }
    }

    /// What is still owed for the next rung, in the same two numbers the
    /// ladder is actually tested against.
    private func remaining(_ progress: AutonomyLadder.Progress) -> String {
        var parts: [String] = []
        if progress.cleanDaysRemaining > 0 {
            parts.append("\(progress.cleanDaysRemaining) more clean day\(progress.cleanDaysRemaining == 1 ? "" : "s")")
        }
        if progress.cleanStreakRemaining > 0 {
            parts.append("a run of \(progress.requirement.cleanStreak)")
        }
        return parts.isEmpty ? "Earned — it lands after your next session." : parts.joined(separator: " and ")
    }

    private func cost(_ requirement: AutonomyLadder.Requirement) -> String {
        "\(requirement.cleanDays) days · run of \(requirement.cleanStreak)"
    }

    // MARK: - Every rung, in advance

    private var rungsSection: some View {
        Section {
            ForEach(AutonomyLadder.Rung.allCases, id: \.rawValue) { rung in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(rung.title)
                            .font(.subheadline.weight(rung == model.ladder.rung ? .bold : .regular))
                        Spacer()
                        if rung <= model.ladder.rung {
                            Text("Reached").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text(cost(rung.requirement))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    ForEach(rung.unlocks, id: \.self) { unlock in
                        Text("· \(unlock)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("The whole ladder")
        } footer: {
            Text("Every rung is here from the first day, with what it costs. Knowing what is coming is the point — a reward you can't predict isn't one.")
        }
    }
}
