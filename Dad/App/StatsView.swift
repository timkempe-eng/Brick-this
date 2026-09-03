import SwiftUI

/// What the sessions add up to. All the arithmetic lives in `DadStats`, which
/// is covered by `swift test`; this file only lays it out.
struct StatsView: View {
    @EnvironmentObject private var model: DadModel
    @Environment(\.dismiss) private var dismiss

    private var stats: DadStats { model.stats }

    var body: some View {
        NavigationStack {
            List {
                if stats.sessionCount == 0 {
                    Section {
                        ContentUnavailableView(
                            "No sessions yet",
                            systemImage: "chart.bar",
                            description: Text("Dad your phone once and this fills in.")
                        )
                    }
                } else {
                    Section {
                        HStack(spacing: 12) {
                            Tile(value: "\(stats.currentStreak)",
                                 unit: stats.currentStreak == 1 ? "day" : "days",
                                 label: "Streak")
                            Tile(value: stats.timeThisWeek.dadDurationText,
                                 label: "This week")
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }

                    Section("Last 7 days") {
                        WeekChart(days: stats.lastDays(7))
                            .frame(height: 120)
                            .padding(.vertical, 8)
                    }

                    Section {
                        LabeledContent("Sessions", value: "\(stats.sessionCount)")
                        LabeledContent("Total time", value: stats.totalTime.dadDurationText)
                        LabeledContent("Longest session", value: stats.longestSession.dadDurationText)
                        LabeledContent("Longest streak",
                                       value: "\(stats.longestStreak) day\(stats.longestStreak == 1 ? "" : "s")")
                    }

                    Section {
                        LabeledContent("Finished at the tag", value: "\(stats.cleanFinishes)")
                        LabeledContent(Vocab.emergencyUnDad, value: "\(stats.emergencyBails)")
                        if let rate = stats.cleanFinishRate {
                            LabeledContent("Clean finishes",
                                           value: rate.formatted(.percent.precision(.fractionLength(0))))
                        }
                    } footer: {
                        Text("The ratio worth watching. Overrides aren't failure — needing one every session means the \(Vocab.modeNoun.lowercased()) is wrong, not you.")
                    }

                    // A week's narrative, aimed at a conversation rather than
                    // a report card. `WeeklyReview` decides what can honestly
                    // be said — including whether there is enough of a week to
                    // say anything — so this is layout, and the judgement that
                    // a reviewer once called "annoying and intrusive and
                    // somewhat judgmental" is not being made here.
                    if case .enough = model.week.adequacy {
                        Section {
                            ForEach(model.week.timeByMode.prefix(4), id: \.modeID) { entry in
                                LabeledContent(entry.modeName, value: entry.total.dadDurationText)
                            }
                            if case .contrast(let busiest, let quietest) = model.week.dayContrast {
                                LabeledContent("Busiest",
                                               value: busiest.date.formatted(.dateTime.weekday(.wide)))
                                LabeledContent("Quietest",
                                               value: quietest.date.formatted(.dateTime.weekday(.wide)))
                            }
                            if model.week.daysTheRationRanOutCount > 0 {
                                LabeledContent("Days a limit ran out",
                                               value: "\(model.week.daysTheRationRanOutCount)")
                            }
                        } header: {
                            Text("This week")
                        } footer: {
                            Text(model.week.headline)
                        }
                    }

                    // Only for people who actually ration something. A row of
                    // zeroes about a feature you don't use is noise.
                    if stats.allowancesReached > 0 {
                        Section {
                            LabeledContent("Sessions that hit the limit",
                                           value: "\(stats.allowancesReached)")
                            LabeledContent("Days you ran out",
                                           value: "\(stats.daysAllowanceReached)")
                        } header: {
                            Text("Allowances")
                        } footer: {
                            Text("A limit you never reach is one you didn't need. A limit you reach every day is set too low — or the \(Vocab.modeNoun.lowercased()) should be hiding those apps outright.")
                        }
                    }
                }

                shieldGapSection
            }
            .navigationTitle("Stats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }
}

private extension StatsView {

    /// When the records cannot account for a stretch, and what that is worth.
    ///
    /// Outside the `sessionCount == 0` branch on purpose: the setup note — that
    /// Screen Time access is missing, so the next tap will hold nothing — is
    /// exactly what a phone with no sessions yet most needs to hear.
    ///
    /// Everything about the wording is `ShieldGap`'s and not this file's. It is
    /// rendered as a list of bounds rather than a total, because the app is
    /// absent during a gap by construction: it knows the shield was in place at
    /// one edge and gone at the other, and nothing about the middle. A single
    /// confident number would be a measurement it did not take.
    @ViewBuilder
    var shieldGapSection: some View {
        if !model.shieldGap.isSilent {
            Section {
                if let note = model.shieldGap.setupNote {
                    Label(note, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                ForEach(Array(model.shieldGap.gaps.enumerated()), id: \.offset) { _, gap in
                    LabeledContent(gap.evidenceText, value: gap.boundText)
                }
            } header: {
                Text(model.shieldGap.headline ?? "Screen Time access")
            } footer: {
                Text(model.shieldGap.detail ?? "")
            }
        }
    }
}

private struct Tile: View {
    let value: String
    var unit: String?
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                if let unit {
                    Text(unit).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Deliberately hand-drawn rather than pulled from Swift Charts — seven bars
/// don't justify the dependency, and this keeps the extensions' build light.
private struct WeekChart: View {
    let days: [DadStats.Day]

    private var peak: TimeInterval { max(days.map(\.total).max() ?? 0, 1) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(days) { day in
                VStack(spacing: 6) {
                    GeometryReader { geo in
                        VStack {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(day.total > 0 ? Color.accentColor : Color.secondary.opacity(0.18))
                                // Empty days keep a sliver so the day is still
                                // legible as "nothing", not as missing data.
                                .frame(height: max(geo.size.height * (day.total / peak), 3))
                        }
                    }
                    Text(day.date.formatted(.dateTime.weekday(.narrow)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement()
                .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide)))
                .accessibilityValue(day.total > 0 ? day.total.dadDurationText : "nothing")
            }
        }
    }
}
