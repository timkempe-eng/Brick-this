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

    var body: some View {
        NavigationStack {
            List {
                roleSection

                if model.household.role == .youngPerson {
                    ladderSection
                    rungsSection
                }
            }
            .navigationTitle("This phone")
            .navigationBarTitleDisplayMode(.inline)
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
