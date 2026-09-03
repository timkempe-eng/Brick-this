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
            }
            .navigationTitle("Stats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
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
