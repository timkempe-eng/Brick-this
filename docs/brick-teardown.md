# How Brick actually works

Research notes from before building Dad. Everything here is from Brick's own
materials, published reviews, and Apple's developer documentation.

## The product

Brick is a $59 NFC puck — a small magnetic plastic square with no battery and
nothing to charge — plus a free companion app for iOS and Android. You choose
which apps to block, tap your phone to the puck to start, and put the puck
somewhere out of reach. The apps stay gone until you physically go back and tap
it again.

Requirements are iOS 17+ or Android 12+, on a phone with NFC.

## The insight

**The puck does almost nothing.** It contains a read-only NFC chip. It has no
radio beyond that, no battery, no logic, no connection to the app. All it
supplies is a unique identifier that shows up when the phone gets close.

**The app does almost nothing either.** On iOS it configures Apple's Screen
Time — the same system behind Apple's own app limits — and Screen Time does the
blocking. The app's job is to decide *when* to turn those restrictions on.

So the entire product is: *a physical token that toggles a Screen Time
restriction set.* Everything else is packaging.

**The value is the friction, not the technology.** Software-only blockers fail
because disabling them costs you three taps in a moment of weakness. Brick makes
the off switch a physical object in another room. That's the whole idea, and it's
why a $0.30 sticker works as well as a $59 puck.

## The iOS stack

| Layer | Framework | What it does |
|---|---|---|
| Permission | `FamilyControls` | `AuthorizationCenter.requestAuthorization(for: .individual)` — one system prompt, once. |
| App selection | `FamilyControls` | `FamilyActivityPicker` returns a `FamilyActivitySelection` of opaque tokens. The app never learns which apps you picked; iOS keeps the mapping. |
| Blocking | `ManagedSettings` | `ManagedSettingsStore.shield.applications = tokens`. The restriction lives in the system, not the app — which is why it survives a force-quit. |
| The block screen | `ManagedSettingsUI` | A `ShieldConfigurationDataSource` extension supplies the title, subtitle, icon and buttons. |
| Block-screen buttons | `ManagedSettings` | A `ShieldActionDelegate` extension handles the two buttons. |
| Timed sessions | `DeviceActivity` | A `DeviceActivityMonitor` extension wakes at the end of a scheduled interval to lift the block. 15-minute minimum interval. |
| The tap | `CoreNFC` | Foreground scanning, plus iOS's background tag reading for taps with the app closed. |

The security model is worth noticing: the restrictions outlive the app's process
because they're stored by the system. Killing the app does not unblock anything.
`ManagedSettings` also offers `application.denyAppRemoval`, which is how a
"strict mode" stops you deleting the blocker to escape it.

## The tap, in detail

This is the part that most DIY attempts get wrong, because there are three
different mechanisms and only one of them feels like Brick.

1. **Foreground scan.** Open the app, press a button, tap the tag. Always works,
   needs nothing special — but you had to open the app, which is exactly the
   moment you get distracted.

2. **Shortcuts NFC automation.** iOS Shortcuts has an NFC personal-automation
   trigger (iPhone XS and later). It keys off the tag's UID, works with a
   completely blank tag, and since iOS 15 can run with "Ask Before Running"
   turned off. Point it at an App Intent and a tap runs your code in the
   background with the app closed. **This is the practical path for a personal
   build**: no server, no domain, nothing written to the tag.

3. **Background tag reading.** iOS reads NDEF tags with the screen on and no app
   open, and shows a banner. To route that into *your* app rather than Safari,
   the tag must hold a URI record whose domain is in your Associated Domains
   entitlement — i.e. you need a website you control and an
   `apple-app-site-association` file on it. This is what a shipping product
   does. It costs you a domain.

Dad implements all three. See [nfc-and-tags.md](nfc-and-tags.md).

## Feature inventory

What Brick ships, and where Dad stands:

| Brick | Dad |
|---|---|
| Modes / packs (Work, Sleep, Gym…) | ✅ `DadMode`, with starter set |
| App + category + website blocking | ✅ (websites are iOS-only in Brick too) |
| Tap to toggle | ✅ all three tap paths |
| Session timer on the home screen | ✅ live counter |
| Strict mode (can't delete the app) | ✅ `denyAppRemoval` |
| 5 emergency unbricks, then email support | ✅ 5 per rolling 30 days, self-restoring |
| Timed / scheduled sessions | ✅ via `DeviceActivityMonitor` |
| Streaks, stats, social features | ➖ session history is stored; no UI yet |
| Android app | ➖ not built; see below |

## Android, for reference

Android has no Screen Time equivalent. Blockers there run an
`AccessibilityService`, watch the foreground package name, and bounce you to the
home screen when you open something blocked. It works, but it's a running
service the user can disable in Settings, so it's meaningfully weaker than the
iOS approach. Brick's Android version does this, and doesn't support website
blocking. NFC is easier on Android — foreground dispatch and background intent
filters both work without Apple's associated-domain requirement.

## Sources

- [Brick — official site](https://getbrick.com/)
- [Brick on the App Store](https://apps.apple.com/us/app/brick-ditch-distractions/id6448794069)
- [Brick on Google Play](https://play.google.com/store/apps/details?id=com.brickllc.brick)
- [Brick Phone Blocker Review 2026 — Cybernews](https://cybernews.com/reviews/brick-phone-blocker-review/)
- [I Used the Brick Phone Blocker for a Year](https://whatifididnt.com/blog/brick-phone-app/)
- [The Brick: Tested review — CNN Underscored](https://www.cnn.com/cnn-underscored/reviews/the-brick)
- [Broke: An Open Source Alternative to Brick](https://posts.oztamir.com/broke-an-open-source-alternative-to-brick/)
- [Making My Own NFC "Focus Brick"](https://jacobdesforges.com/nfc-focus-brick/)
- [Requesting the Family Controls entitlement — Apple](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement)
- [iOS Background NFC Tag Reading — GoToTags](https://gototags.com/help/ios/nfc/reading/background)
