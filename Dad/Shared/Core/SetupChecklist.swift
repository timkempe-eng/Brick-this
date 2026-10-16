import Foundation

/// What stands between a fresh install and a tap that actually takes something
/// away.
///
/// Granting Screen Time access used to be the whole of onboarding, and it is
/// the smallest part of setup: the starter Modes arrive with no apps in them,
/// so the first tap after the permission prompt finds no Mode that hides
/// anything, and the engine — rightly refusing to start an empty session —
/// answers with a "which Mode?" question that has nothing to pick. A beta
/// tester called the result not intuitive.
///
/// Derived from what is really there rather than from a flag set when a screen
/// was passed, so a step skipped on the first day is still offered on the
/// tenth, and a step undone later (every app taken back out of every Mode) is
/// offered again.
struct SetupChecklist: Equatable {

    /// In the order they are offered. The order is the advice: apps before a
    /// tag, because a paired tag with nothing to hide is the same dead end the
    /// checklist exists to close.
    enum Step: CaseIterable, Equatable {
        /// At least one Mode takes something away.
        case chooseApps
        /// A tag is paired. Until one is, any NFC tag works — a transit card
        /// included — so it is a step and not a nicety.
        case pairTag
        /// A session has run at least once, so the shield has been seen.
        case tryIt
    }

    let done: Set<Step>

    init(modes: [DadMode], pairedTagCount: Int, hasEverStarted: Bool) {
        var done: Set<Step> = []
        if modes.contains(where: \.blocksAnything) { done.insert(.chooseApps) }
        if pairedTagCount > 0 { done.insert(.pairTag) }
        if hasEverStarted { done.insert(.tryIt) }
        self.done = done
    }

    /// The step to offer now, or `nil` once every one is done.
    var next: Step? { Step.allCases.first { !done.contains($0) } }

    var isComplete: Bool { next == nil }
}
