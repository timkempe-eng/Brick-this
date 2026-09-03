import SwiftUI

/// Every Mode and the agreement behind it.
///
/// The list is driven by the Modes, never by the agreements — an agreement
/// whose Mode was deleted describes a rule that no longer exists, and counting
/// it would show a household four agreements for three Modes. `HouseholdAgreements`
/// does that; this file only renders it.
///
/// What it deliberately does not render: a percentage, a score, a comparison
/// between two people, or any sentence with a verdict in it. Those phrasings
/// are listed and rejected in `ModeAgreement.swift`, and the rule they follow
/// from is that the screen only works if it reads like the start of a
/// conversation.
struct AgreementsBoardView: View {
    @EnvironmentObject private var model: DadModel
    @Environment(\.dismiss) private var dismiss

    @State private var editing: DadMode?

    private var board: HouseholdAgreements { model.householdAgreements }

    var body: some View {
        NavigationStack {
            List {
                if !board.overdue.isEmpty {
                    Section {
                        ForEach(board.overdue) { entry in row(entry) }
                    } header: {
                        Text(AgreementCopy.overdueHeadline(count: board.overdue.count))
                    }
                }

                Section {
                    ForEach(board.entries) { entry in row(entry) }
                } header: {
                    Text("Every \(Vocab.modeNoun.lowercased())")
                } footer: {
                    Text("""
                         What predicts a rule being kept is having written down why it \
                         exists — not having been told. So this is free text, and \
                         "agreed together" comes from the \(Vocab.tagNoun) rather than \
                         from a box anybody can tick.
                         """)
                }
            }
            .navigationTitle("Agreements")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editing) { AgreementView(mode: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }

    private func row(_ entry: HouseholdAgreements.Entry) -> some View {
        Button {
            editing = model.modes.first { $0.id == entry.modeID }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.modeName).foregroundStyle(.primary)
                Text(AgreementCopy.standingLabel(entry.standing))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(AgreementCopy.dueLine(daysUntil: entry.daysUntilRenegotiation))
                    .font(.caption)
                    .foregroundStyle(entry.isOverdue ? .orange : .secondary)
            }
        }
    }
}
