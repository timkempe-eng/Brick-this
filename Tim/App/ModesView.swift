import SwiftUI
import FamilyControls

struct ModesView: View {
    @EnvironmentObject private var model: TimModel
    @Environment(\.dismiss) private var dismiss
    @State private var editing: TimMode?

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
                    Text("A \(Vocab.modeNoun.lowercased()) is a set of apps to take away. Pick one when you \(Vocab.verb.lowercased()) your phone.")
                }

                Button {
                    editing = TimMode(name: "New \(Vocab.modeNoun)", symbol: "circle.dashed")
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
    @State var mode: TimMode
    let onSave: (TimMode) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showingPicker = false

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
                    Text("Chosen with Apple's own picker. Tim receives anonymous tokens, not the names of your apps.")
                }

                ScheduleSection(mode: $mode)

                Section {
                    Picker("\(Vocab.unVerb) automatically", selection: $mode.autoUnTimAfter) {
                        ForEach(durations) { option in
                            Text(option.id).tag(option.seconds)
                        }
                    }
                    Toggle("Strict", isOn: $mode.isStrict)
                } footer: {
                    Text("Strict stops Tim being deleted while your phone is \(Vocab.verbPast.lowercased()) — the fastest way to cheat.")
                }
            }
            .navigationTitle(mode.name)
            .navigationBarTitleDisplayMode(.inline)
            .familyActivityPicker(isPresented: $showingPicker, selection: $mode.selection)
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


/// Lets a Mode run on its own — "Sleep, every night, 22:00–07:00".
///
/// The schedule is optional on `TimMode`, so the toggle creates and discards
/// it rather than binding to a field that might not be there.
private struct ScheduleSection: View {
    @Binding var mode: TimMode

    private var isOn: Binding<Bool> {
        Binding(
            get: { mode.schedule?.isEnabled ?? false },
            set: { on in
                if on {
                    // A sensible default that is already valid, so switching it
                    // on never leaves a schedule that silently can't fire.
                    mode.schedule = mode.schedule ?? ModeSchedule(
                        startHour: 22, startMinute: 0,
                        endHour: 7, endMinute: 0,
                        weekdays: ModeSchedule.everyDay
                    )
                    mode.schedule?.isEnabled = true
                } else {
                    mode.schedule?.isEnabled = false
                }
            }
        )
    }

    /// Bridges the stored hour/minute components to a `DatePicker`, which wants
    /// a `Date`. Components are what's stored, deliberately: 22:00 should mean
    /// 22:00 after a time-zone change, not the instant it once was.
    private func timeBinding(hour: WritableKeyPath<ModeSchedule, Int>,
                             minute: WritableKeyPath<ModeSchedule, Int>) -> Binding<Date> {
        Binding(
            get: {
                guard let s = mode.schedule else { return Date() }
                return Calendar.current.date(bySettingHour: s[keyPath: hour],
                                             minute: s[keyPath: minute],
                                             second: 0, of: Date()) ?? Date()
            },
            set: { newValue in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                mode.schedule?[keyPath: hour] = parts.hour ?? 0
                mode.schedule?[keyPath: minute] = parts.minute ?? 0
            }
        )
    }

    var body: some View {
        Section {
            Toggle("Run on a schedule", isOn: isOn)

            if let schedule = mode.schedule, schedule.isEnabled {
                DatePicker("Starts", selection: timeBinding(hour: \.startHour, minute: \.startMinute),
                           displayedComponents: .hourAndMinute)
                DatePicker("Ends", selection: timeBinding(hour: \.endHour, minute: \.endMinute),
                           displayedComponents: .hourAndMinute)
                WeekdayPicker(weekdays: Binding(
                    get: { mode.schedule?.weekdays ?? [] },
                    set: { mode.schedule?.weekdays = $0 }
                ))
            }
        } header: {
            Text("Schedule")
        } footer: {
            if let schedule = mode.schedule, schedule.isEnabled {
                if schedule.isValid {
                    Text("\(schedule.displayText()). Your phone \(Vocab.verbGerund.lowercased()) itself, and you can still tap out early.")
                } else {
                    Text("This schedule can't run: pick at least one day and a window of 15 minutes or more.")
                        .foregroundStyle(.orange)
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
