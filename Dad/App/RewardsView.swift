import SwiftUI

/// What the days buy, and who settles up.
///
/// The unit is a **day**, never a minute, and that is the whole design rather
/// than a formatting choice. `RewardLedger` makes screen time structurally
/// unreachable — there is no multiply, no `TimeInterval`, no duration member on
/// its unit type, and a test reads its own source to keep it that way. A
/// blocker that pays you in the thing it took away is one that has agreed the
/// thing was worth having.
///
/// So a grown-up who means five pounds writes "£5 pocket money" in the
/// reward's *name*, which Dad never parses, and prices it in days. Dad holds no
/// balance in money and makes no promise it could not honour.
///
/// One screen for both people, like every other screen here. What differs is
/// what each can do, and the difference is a tag tap rather than a login: three
/// of the five acts need a grown-up demonstrably in the room, and on a young
/// person's phone the proof is the paired tag they are holding.
struct RewardsView: View {
    @EnvironmentObject private var model: DadModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var scanner = TagScanner()

    @State private var isAdding = false
    @State private var newName = ""
    @State private var newPrice = 3

    private var ledger: RewardLedger { model.rewardLedger }

    var body: some View {
        NavigationStack {
            List {
                balanceSection
                pendingSection
                offersSection
                settledSection
            }
            .navigationTitle("Rewards")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $isAdding) { offerEditor }
            .nfcErrorAlert($scanner.lastError)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    Button { isAdding = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Offer a reward")
                }
            }
        }
    }

    // MARK: - What is in the pot

    private var balanceSection: some View {
        Section {
            LabeledContent("To spend", value: ledger.balance.description)
            LabeledContent("Earned in total", value: ledger.earned.description)
        } header: {
            Text("Days")
        } footer: {
            Text("""
                 A day is earned by finishing a session at the \(Vocab.tagNoun) — one \
                 counts however many times you \(Vocab.verb) that day, and a \
                 \(Vocab.modeNoun.lowercased()) a schedule opened and closed on its own \
                 earns nothing. The same days the ladder counts, so a rung and a reward \
                 quote against the same evidence.
                 """)
        }
    }

    // MARK: - Promised, not yet given

    @ViewBuilder
    private var pendingSection: some View {
        if !ledger.pending.isEmpty {
            Section {
                ForEach(ledger.pending) { claim in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(claim.rewardName)
                            Spacer()
                            Text(claim.price.description).foregroundStyle(.secondary)
                        }
                        Text("Claimed \(claim.claimedAt.formatted(.dateTime.weekday(.wide).day().month()))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Given") { settleUp(claim.id) }.tint(.green)
                        Button("Take back", role: .destructive) { model.withdraw(claim: claim.id) }
                    }
                }
            } header: {
                Text("Waiting to be given")
            } footer: {
                Text("""
                     Swipe to mark one given — on a young person's phone that needs the \
                     \(Vocab.tagNoun), because it is somebody saying a thing happened and \
                     it cannot be undone afterwards. Taking a claim back needs nobody and \
                     returns the days.
                     """)
            }
        }
    }

    // MARK: - On offer

    private var offersSection: some View {
        Section {
            if ledger.available.isEmpty {
                Text("Nothing on offer yet.").foregroundStyle(.secondary)
            }
            ForEach(ledger.available) { reward in
                Button {
                    model.claim(reward)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(reward.name).foregroundStyle(.primary)
                            if !ledger.canAfford(reward) {
                                Text("\(ledger.shortfall(for: reward).description) to go")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(reward.price.description)
                            .foregroundStyle(ledger.canAfford(reward) ? .primary : .secondary)
                    }
                }
                .disabled(!ledger.canAfford(reward))
                .swipeActions(edge: .trailing) {
                    Button("Retire") { retire(reward.id) }.tint(.orange)
                }
            }
        } header: {
            Text("On offer")
        } footer: {
            Text("""
                 Priced in days, never in minutes — a blocker that pays you in the thing \
                 it took away has agreed the thing was worth having. A grown-up who means \
                 five pounds writes it in the name; \(Vocab.appName) never reads it.
                 """)
        }
    }

    @ViewBuilder
    private var settledSection: some View {
        if !ledger.settled.isEmpty {
            Section("Given") {
                ForEach(ledger.settled.prefix(10)) { claim in
                    LabeledContent(claim.rewardName,
                                   value: claim.settledAt?
                                       .formatted(.dateTime.day().month()) ?? "")
                }
            }
        }
    }

    // MARK: - Offering something new

    private var offerEditor: some View {
        NavigationStack {
            Form {
                TextField("What it is", text: $newName)
                Picker("Days", selection: $newPrice) {
                    ForEach(1...30, id: \.self) { Text("\($0)").tag($0) }
                }
            }
            .navigationTitle("New reward")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { isAdding = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Offer") { offer() }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // MARK: - The three acts that need a grown-up

    /// Runs `act` straight away on a phone that is its owner's, and behind a
    /// tag tap on a young person's.
    ///
    /// The branch is here rather than in the engine's refusal because the
    /// engine's refusal is the enforcement and this is the affordance: asking
    /// for a tap nobody needs would be ceremony, and offering a button that
    /// silently does nothing would be worse.
    private func withAGrownUp(_ prompt: String, _ act: @escaping (String?) -> Void) {
        guard model.household.role == .youngPerson else { return act(nil) }
        scanner.scan(prompt: prompt) { uid in act(uid) }
    }

    private func offer() {
        let reward = RewardLedger.Reward(name: newName.trimmingCharacters(in: .whitespaces),
                                         price: RewardLedger.Days(newPrice))
        withAGrownUp("Hold your iPhone near your \(Vocab.tagNoun) to offer this.") { uid in
            model.offer(reward, byTagUID: uid)
            newName = ""
            isAdding = false
        }
    }

    private func retire(_ id: UUID) {
        withAGrownUp("Hold your iPhone near your \(Vocab.tagNoun) to take this offer back.") { uid in
            model.retire(rewardID: id, byTagUID: uid)
        }
    }

    private func settleUp(_ id: UUID) {
        withAGrownUp("Hold your iPhone near your \(Vocab.tagNoun) to mark this given.") { uid in
            model.settle(claim: id, byTagUID: uid)
        }
    }
}
