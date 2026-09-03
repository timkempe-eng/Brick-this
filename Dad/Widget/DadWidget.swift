import WidgetKit
import SwiftUI

/// The Lock Screen widget.
///
/// The point of the whole product is not opening your phone, so the status had
/// no business living only inside the app. This puts "Dadded, 1:24:07, Deep
/// Work" on the Lock Screen, where a glance settles it.
///
/// Deliberately thin. What it says is decided by `WidgetSnapshot` in Core,
/// where it is tested; this file is layout. It also carries no Family Controls
/// entitlement — it only reads the session out of the App Group, and an
/// entitlement it doesn't use would be a fifth bundle id needing Apple's
/// manual approval.

struct DadEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct DadProvider: TimelineProvider {

    func placeholder(in context: Context) -> DadEntry {
        DadEntry(date: Date(), snapshot: .dadded(modeName: "Deep Work",
                                                 since: Date().addingTimeInterval(-3600),
                                                 rationing: false))
    }

    func getSnapshot(in context: Context, completion: @escaping (DadEntry) -> Void) {
        completion(DadEntry(date: Date(), snapshot: current()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DadEntry>) -> Void) {
        let now = Date()
        let snapshot = current()
        let entry = DadEntry(date: now, snapshot: snapshot)

        // One entry either way. While Dadded the elapsed time is drawn by a
        // self-updating timer view, so there is nothing to reload for — the
        // engine announces the session ending through WidgetRefreshing. While
        // free, the streak can lapse at midnight with nothing to announce it.
        let policy: TimelineReloadPolicy = snapshot.nextRefresh(after: now)
            .map { .after($0) } ?? .never
        completion(Timeline(entries: [entry], policy: policy))
    }

    private func current() -> WidgetSnapshot {
        let store = UserDefaultsStore.shared
        let session = store.activeSession
        // The Mode, so the snapshot can tell rationing from blocking — the
        // difference between "my apps are gone" and "my apps are there, on a
        // budget", which is the whole question a glance is meant to settle.
        let mode = session.flatMap { s in store.modes.first(where: { $0.id == s.modeID }) }
        return .make(session: session,
                     mode: mode,
                     // The running session goes in, or the widget shows a
                     // streak without today in it while today is the thing it
                     // is showing a timer for.
                     stats: DadStats(sessions: store.history, activeSession: session),
                     pendingResume: store.pendingResume)
    }
}

// MARK: - Views

struct DadWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DadEntry

    var body: some View {
        content
            .widgetURL(IncomingLink.widgetURL)
            .containerBackground(.fill.tertiary, for: .widget)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline:      inline
        case .accessoryCircular:    circular
        case .accessoryRectangular: rectangular
        default:                    small
        }
    }

    // One line beside the clock — no room for a second.
    private var inline: some View {
        Label(entry.snapshot.inlineText, systemImage: entry.snapshot.symbolName)
    }

    private var circular: some View {
        VStack(spacing: 1) {
            Image(systemName: entry.snapshot.symbolName)
                .font(.title3)
            if case .free(let streak) = entry.snapshot, streak > 0 {
                Text("\(streak)")
                    .font(.caption2.weight(.semibold))
            }
        }
        .widgetAccentable()
        .accessibilityLabel(accessibilityLabel)
    }

    /// The main one: the rectangular Lock Screen slot.
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(entry.snapshot.headline, systemImage: entry.snapshot.symbolName)
                .font(.caption.weight(.semibold))
                .widgetAccentable()

            if case .dadded(_, let since, _) = entry.snapshot {
                // Ticks on its own, without the system rebuilding the timeline.
                Text(since, style: .timer)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            } else if case .onBreak(_, let until) = entry.snapshot {
                // The same self-updating view, counting the other way.
                Text(until, style: .timer)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }

            Text(entry.snapshot.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: entry.snapshot.symbolName)
                .font(.title2)
                .foregroundStyle(.tint)
            Spacer(minLength: 0)
            Text(entry.snapshot.headline)
                .font(.headline)
            if case .dadded(_, let since, _) = entry.snapshot {
                Text(since, style: .timer)
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
            }
            Text(entry.snapshot.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// VoiceOver reads the state, not the ticking clock — a timer that
    /// re-announces every second is unusable.
    private var accessibilityLabel: String {
        "\(entry.snapshot.headline). \(entry.snapshot.detail)"
    }
}

// MARK: - Configuration

struct DadStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DadStatus", provider: DadProvider()) { entry in
            DadWidgetView(entry: entry)
        }
        .configurationDisplayName(Vocab.appName)
        .description("Whether your phone is \(Vocab.verbPast), and for how long.")
        .supportedFamilies([
            .accessoryInline,
            .accessoryCircular,
            .accessoryRectangular,
            .systemSmall,
        ])
    }
}

@main
struct DadWidgetBundle: WidgetBundle {
    var body: some Widget {
        DadStatusWidget()
    }
}
