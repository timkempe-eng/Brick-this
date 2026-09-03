import SwiftUI

/// Why a Mode is here, in the household's own words, and when it comes up
/// again.
///
/// Backlog #3, and the finding it rests on is narrow: what predicts a young
/// person keeping to a rule is having *written down* why it exists, not having
/// been told. So the reason is free text and never a dropdown — a picked-from-
/// a-list justification is not writing.
///
/// The screen shows the same thing to both people, like every other screen
/// here. What it will not do is grade anybody: no percentage, no streak of
/// agreements, no "3 of 4 — nice work". `AgreementCopy` holds every sentence
/// for exactly that reason, and its own comments list the phrasings that were
/// considered and rejected.
///
/// "Agreed together" is earned by a tag tap and cannot be typed. The engine
/// derives it; this screen offers the tap and reports what came back.
struct AgreementView: View {
    @EnvironmentObject private var model: DadModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var scanner = TagScanner()

    let mode: DadMode

    @State private var reason = ""
    @State private var comesUpAgain = true
    @State private var days = 30

    /// The tag tap that turns this into "agreed together", held until Save.
    ///
    /// Collected before saving rather than during it, and that is not a
    /// detail. Tying Save to an NFC sheet leaves the screen stuck when
    /// somebody cancels the sheet — there is no callback for a cancelled scan
    /// — so the Save button would sometimes do nothing. Here the tap is its
    /// own act: cancel it and the flag simply stays unset, which records what
    /// actually happened.
    @State private var togetherTag: String?

    /// Review lengths offered. Weeks and months as people say them, and
    /// nothing shorter than a fortnight: a rule renegotiated every few days is
    /// not a rule, it is a negotiation with a timer on it.
    private let offered = [14, 30, 60, 90, 180]

    private var existing: ModeAgreement? { model.agreement(for: mode.id) }

    var body: some View {
        NavigationStack {
            List {
                reasonSection
                reviewSection
                if let existing, !existing.history.isEmpty { historySection(existing) }
            }
            .navigationTitle(mode.name)
            .navigationBarTitleDisplayMode(.inline)
            .nfcErrorAlert($scanner.lastError)
            .onAppear {
                reason = existing?.reason ?? ""
                comesUpAgain = existing?.comesUpAgain ?? true
                days = nextReviewLength
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(reason.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // MARK: - The reason

    private var reasonSection: some View {
        Section {
            TextField(AgreementCopy.reasonPrompt, text: $reason, axis: .vertical)
                .lineLimit(3...8)

            if model.household.role == .youngPerson {
                Button {
                    if togetherTag != nil { togetherTag = nil } else { markAgreedTogether() }
                } label: {
                    HStack {
                        Text("We agreed this together")
                        Spacer()
                        if togetherTag != nil {
                            Image(systemName: "checkmark")
                                .accessibilityLabel("Recorded as agreed together")
                        }
                    }
                }
            }
        } header: {
            Text(AgreementCopy.reasonPrompt)
        } footer: {
            Text(footerForReason)
        }
    }

    /// The tag is the proof, and it is offered rather than demanded. Saving
    /// without it records "set by one person", which is true — a rule one
    /// person wrote is a real thing that happens, and the record's job is to
    /// stay visibly what it is rather than to nag anybody into fetching a tag.
    private func markAgreedTogether() {
        scanner.scan(prompt: "Hold your iPhone near the \(Vocab.tagNoun).") { uid in
            togetherTag = uid
        }
    }

    /// Says what the record currently is, and what the tag would make it.
    /// Never says anybody *should* fetch the tag: a rule one person wrote is a
    /// real thing, and the record's job is to stay visibly what it is rather
    /// than to nag.
    private var footerForReason: String {
        guard model.household.role == .youngPerson else { return AgreementCopy.reasonHint }
        let now = existing.map { AgreementCopy.partiesLabel($0.agreedBy) } ?? "Nothing written down yet"
        return """
            \(AgreementCopy.reasonHint) \(now) at the moment. The \(Vocab.tagNoun) is what \
            records it as agreed together — it is the only way \(Vocab.appName) can tell that \
            both of you were here, rather than being told so.
            """
    }

    // MARK: - When it comes up again

    private var reviewSection: some View {
        Section {
            Toggle("Comes up again", isOn: $comesUpAgain)
            if comesUpAgain {
                Picker("In", selection: $days) {
                    ForEach(offered, id: \.self) { Text(label(days: $0)).tag($0) }
                }
            }
        } header: {
            Text("Talking about it again")
        } footer: {
            Text(existing.map { AgreementCopy.dueLine(daysUntil: $0.daysUntilRenegotiation()) }
                 ?? """
                    Restrictions are meant to shrink as trust grows. A rule with no date to \
                    come up again cannot shrink — it can only be argued about.
                    """)
        }
    }

    /// What the picker should start on: how long until this agreement is due,
    /// rounded to something the picker actually offers.
    ///
    /// Never the raw remaining days, and this is the bug it exists to prevent.
    /// An **overdue** agreement has a negative remaining count. Handing that to
    /// the picker selects nothing — no tag matches −5 — so a person who talks
    /// it over and saves without touching the row re-files it five days in the
    /// past, and it is still overdue the moment the conversation ends. Which
    /// is precisely the inversion `ModeAgreement.renegotiated` says it exists
    /// to prevent.
    ///
    /// The same blank-picker problem, less dramatically, for any live
    /// agreement with an unoffered number of days left — twelve, say.
    ///
    /// Rounding *up* to the nearest offered length is the right direction:
    /// talking about a rule buys it at least as long as was left, never less.
    private var nextReviewLength: Int {
        // Derived from `offered`, not written out beside it. The literals 30
        // and 180 were here for one commit, on the argument that a branch
        // guarding a fixed array is unreachable — which is true and beside the
        // point: an unreachable branch costs nothing, and a duplicated literal
        // goes stale the moment somebody edits the array. The failure it goes
        // stale into is a picker selection matching no tag, which is the exact
        // bug this function exists to prevent.
        guard let remaining = existing?.daysUntilRenegotiation(), remaining > 0 else {
            return offered.first { $0 >= 30 } ?? offered[0]
        }
        return offered.first { $0 >= remaining } ?? offered[offered.count - 1]
    }

    private func label(days: Int) -> String {
        switch days {
        case 14:  return "2 weeks"
        case 30:  return "A month"
        case 60:  return "2 months"
        case 90:  return "3 months"
        default:  return "6 months"
        }
    }

    // MARK: - What has been said before

    private func historySection(_ agreement: ModeAgreement) -> some View {
        Section("Talked about") {
            ForEach(Array(agreement.history.enumerated()), id: \.offset) { _, entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(AgreementCopy.outcomeLabel(entry.outcome))
                    Text("\(entry.date.formatted(.dateTime.day().month().year())) · \(AgreementCopy.partiesLabel(entry.agreedBy))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Saving

    /// A first agreement is `agree`; a later one on a Mode that already has one
    /// is a renegotiation, so the conversation is recorded rather than
    /// overwritten. The distinction is made here because only this screen
    /// knows whether somebody meant "write this down" or "we talked again".
    private func save() {
        let text = reason.trimmingCharacters(in: .whitespaces)
        let review = comesUpAgain ? days : nil
        let hadOne = existing != nil
        let changed = existing?.reason != text

        if hadOne {
            model.renegotiate(modeID: mode.id,
                              outcome: changed ? .changed : .keptAsIs,
                              reason: text, comingUpAgainIn: review, byTagUID: togetherTag)
        } else {
            model.agree(modeID: mode.id, reason: text,
                        comingUpAgainIn: review, byTagUID: togetherTag)
        }
        dismiss()
    }
}
