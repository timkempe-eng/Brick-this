import SwiftUI
import FamilyControls

struct ModesView: View {
    @EnvironmentObject private var model: DadModel
    @Environment(\.dismiss) private var dismiss
    @State private var editing: DadMode?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.modes) { mode in
                        Button { editing = mode } label: {
                            HStack {
                                Image(systemName: mode.symbol)
                                    .frame(width: 28)
                                    .foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mode.name).foregroundStyle(.primary)
                                    Text(mode.summary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        offsets.map { model.modes[$0] }.forEach(model.delete)
                    }
                } footer: {
                    Text("A \(Vocab.modeNoun.lowercased()) is a set of apps to take away. Pick one when you \(Vocab.verb) your phone.")
                }

                Button {
                    editing = DadMode(name: "New \(Vocab.modeNoun)", symbol: "circle.dashed")
                } label: {
                    Label("Add a \(Vocab.modeNoun.lowercased())", systemImage: "plus")
                }
            }
            .navigationTitle("\(Vocab.modeNoun)s")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .sheet(item: $editing) { mode in
                ModeEditorView(mode: mode) { model.save($0) }
            }
        }
    }

}

struct ModeEditorView: View {
    @State var mode: DadMode
    let onSave: (DadMode) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showingPicker = false

    /// The picker gets its own state rather than a binding into the Mode.
    ///
    /// It used to bind `$mode.selection`, a computed bridge whose getter
    /// JSON-decodes a fresh FamilyActivitySelection on every read and whose
    /// setter JSON-encodes back into `mode`. Anything the picker modifier
    /// wrote during a render therefore mutated the Mode, and every other
    /// edit on this screen was lost: the Simulator showed Strict and the
    /// schedule switch both reading back off immediately after a tap, while
    /// Cancel — the one control that does not touch `mode` — worked.
    @State private var selection = FamilyActivitySelection()

    /// Offered auto-release lengths. `DeviceActivitySchedule` won't monitor an
    /// interval under 15 minutes, so the shortest option is 15.
    private struct AutoRelease: Identifiable {
        let id: String
        let seconds: TimeInterval?
    }

    private let durations: [AutoRelease] = [
        AutoRelease(id: "Until I tap again", seconds: nil),
        AutoRelease(id: "15 minutes", seconds: 15 * 60),
        AutoRelease(id: "30 minutes", seconds: 30 * 60),
        AutoRelease(id: "1 hour", seconds: 60 * 60),
        AutoRelease(id: "2 hours", seconds: 2 * 60 * 60),
        AutoRelease(id: "4 hours", seconds: 4 * 60 * 60),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $mode.name)
                }

                Section {
                    Button {
                        showingPicker = true
                    } label: {
                        HStack {
                            Text("Apps and sites to hide")
                            Spacer()
                            Text("\(mode.blocked.totalCount)")
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("Chosen with Apple's own picker. Dad receives anonymous tokens, not the names of your apps.")
                }

                AllowanceSection(mode: $mode)

                ScheduleSection(mode: $mode)

                Section {
                    Picker("\(Vocab.unVerb) automatically", selection: $mode.autoUnDadAfter) {
                        ForEach(durations) { option in
                            Text(option.id).tag(option.seconds)
                        }
                    }
                    Toggle("Strict", isOn: $mode.isStrict)
                } footer: {
                    Text("Strict stops Dad being deleted while your phone is \(Vocab.verbPast) — the fastest way to cheat.")
                }
            }
            .navigationTitle(mode.name)
            .navigationBarTitleDisplayMode(.inline)
            .familyActivityPicker(isPresented: $showingPicker, selection: $selection)
            .onAppear { selection = mode.selection }
            // Take what was chosen when the picker closes. Keyed on the Bool
            // rather than on the selection itself, which need not be Equatable.
            .onChange(of: showingPicker) { _, isShowing in
                if !isShowing { mode.selection = selection }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { onSave(mode); dismiss() }
                        .disabled(mode.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}


/// Lets a Mode ration instead of forbid — "fifteen minutes of these a day".
///
/// Every control binds directly to a property of the Mode, for the reason
/// written out at length on `ScheduleSection` below: the one decision the
/// switch carries lives on `DadMode`, where a test can call it.
private struct AllowanceSection: View {
    @Binding var mode: DadMode

    var body: some View {
        Section {
            Toggle("Ration instead of hiding", isOn: $mode.isRationed)

            if mode.isRationed {
                Picker("Allowance", selection: $mode.editableAllowance.minutesPerDay) {
                    ForEach(ModeAllowance.offered, id: \.self) { minutes in
                        Text(ModeAllowance(minutesPerDay: minutes).displayText).tag(minutes)
                    }
                }
            }
        } header: {
            Text("Allowance")
        } footer: {
            if mode.isRationed {
                if !mode.blocksAnything {
                    // Same rule as the schedule below: an allowance over an
                    // empty selection counts nothing and would never run out.
                    Text("An allowance needs apps to count — pick some above.")
                        .foregroundStyle(.orange)
                } else {
                    Text("These apps stay usable until the allowance runs out, then they go until midnight. Strict still applies the whole time. Changing the allowance while your phone is \(Vocab.verbPast) starts today's count again.")
                }
            } else {
                Text("Off. This \(Vocab.modeNoun.lowercased()) takes its apps away for as long as it runs.")
            }
        }
    }
}

/// Lets a Mode run on its own — "Sleep, every night, 22:00–07:00".
///
/// Every control binds DIRECTLY to a property of the Mode. There used to be a
/// `Binding(get:set:)` built here for each one; the switch bound that way did
/// not stick — the Simulator showed it reading off immediately after a tap,
/// with the footer still saying the Mode only runs when you tap. The decision
/// those closures carried now lives on `DadMode`, where it is tested.
private struct ScheduleSection: View {
    @Binding var mode: DadMode

    /// Bridges stored hour/minute components to a `DatePicker`, which wants a
    /// `Date`. Components are what's stored, deliberately: 22:00 should mean
    /// 22:00 after a time-zone change, not the instant it once was.
    private func time(_ hour: WritableKeyPath<ModeSchedule, Int>,
                      _ minute: WritableKeyPath<ModeSchedule, Int>) -> Binding<Date> {
        Binding(
            get: {
                let s = mode.editableSchedule
                return Calendar.current.date(bySettingHour: s[keyPath: hour],
                                             minute: s[keyPath: minute],
                                             second: 0, of: Date()) ?? Date()
            },
            set: { newValue in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                var updated = mode.editableSchedule
                updated[keyPath: hour] = parts.hour ?? 0
                updated[keyPath: minute] = parts.minute ?? 0
                mode.editableSchedule = updated
            }
        )
    }

    var body: some View {
        Section {
            Toggle("Run on a schedule", isOn: $mode.isScheduled)

            if mode.isScheduled {
                DatePicker("Starts", selection: time(\.startHour, \.startMinute),
                           displayedComponents: .hourAndMinute)
                DatePicker("Ends", selection: time(\.endHour, \.endMinute),
                           displayedComponents: .hourAndMinute)
                WeekdayPicker(weekdays: $mode.editableSchedule.weekdays)
            }
        } header: {
            Text("Schedule")
        } footer: {
            if mode.isScheduled {
                let schedule = mode.editableSchedule
                if !schedule.isValid {
                    Text("This schedule can't run: pick at least one day and a window of 15 minutes or more.")
                        .foregroundStyle(.orange)
                } else if !mode.blocksAnything {
                    // A valid schedule on a Mode that blocks nothing is never
                    // registered — promising "Dads itself" here would be the
                    // looks-configured-does-nothing failure.
                    Text("This schedule won't run until the \(Vocab.modeNoun.lowercased()) blocks something — pick apps above.")
                        .foregroundStyle(.orange)
                } else if let next = schedule.nextStart(after: Date()) {
                    Text("\(schedule.displayText()). Next: \(next.formatted(.dateTime.weekday(.wide).hour().minute())). Your phone \(Vocab.verbThirdPerson) itself, and you can still tap out early.")
                } else {
                    Text("\(schedule.displayText()). Your phone \(Vocab.verbThirdPerson) itself, and you can still tap out early.")
                }
            } else {
                Text("Off. This \(Vocab.modeNoun.lowercased()) only runs when you tap.")
            }
        }
    }
}

private struct WeekdayPicker: View {
    @Binding var weekdays: Set<Int>

    /// `Calendar` numbers weekdays from 1 = Sunday, and `veryShortWeekdaySymbols`
    /// is indexed the same way, offset by one.
    private let symbols = Calendar.current.veryShortWeekdaySymbols

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { day in
                let on = weekdays.contains(day)
                Button {
                    if on { weekdays.remove(day) } else { weekdays.insert(day) }
                } label: {
                    Text(symbols.indices.contains(day - 1) ? symbols[day - 1] : "?")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(on ? Color.accentColor : Color.secondary.opacity(0.15),
                                    in: Capsule())
                        .foregroundStyle(on ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
        .padding(.vertical, 4)
    }
}
