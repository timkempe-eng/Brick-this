# ADR 005: No "what you missed while Dadded" digest

**Status:** declined
**Date:** 2026-09-03

## Context

The recurring complaint about every blocker, Brick included, is not the
blocking. It is the re-entry: you Un-Dad, and you have no idea what happened in
the hour you were gone. The obvious feature is a digest — "while you were
Dadded: 3 messages, 1 missed call, 12 things that could wait" — shown once, on
release.

The parking-lot entry attached a condition to it: *check feasibility first —
iOS may not expose enough to build this honestly, and a half-true digest is
worse than none.* This ADR is that check. It has two halves, and they turned out
to point the same way: **iOS does not expose it, and this project would refuse
it if iOS did.**

## What iOS actually exposes

Every candidate API, and whose data it can see. All of these are first-party
statements; the URLs are at the end.

| API | What it returns | Other apps' notifications? |
|---|---|---|
| `UNUserNotificationCenter.getDeliveredNotifications` | "all of **your app's** delivered notifications that are still present in Notification Center" | **No** |
| `UNNotificationServiceExtension` | modifies a remote notification before delivery; fires only when *your* payload sets `mutable-content: 1` | **No** |
| `UNNotificationContentExtension` | "displays a custom interface for **your app's** notifications", matched by a category your app declared | **No** |
| `DeviceActivityReport` | "the user's application, category, and web domain activity"; extension sandboxed against network and against "moving sensitive content outside the extension's address space" | **No** — it is usage minutes, not message content, and nothing leaves the extension |
| `INFocusStatus` | one property: `isFocused: Bool?` | **No** |
| Sensitive Content Analysis | nudity detection in media **your own app** is about to display | **No** |
| Apple Intelligence notification summaries | a system Settings feature | **No developer API** |

The Notification Service Extension is the one people assume is the way in,
because it is an extension and it sees a notification before the user does. It
sees exactly one notification: the one your own server sent, with your own
`mutable-content` flag on it. Dad has no server (ADR 002), so it has no remote
notifications, so it has nothing for the extension to look at.

Apple Developer Technical Support has answered the general question directly, in
a thread about forwarding notifications to a Bluetooth watch:

> "That is not something you can do in an app. The watch needs to implement The
> Apple Notification Center Service which will then receive the notifications
> directly from the system. **It is not possible for your app to intercept and
> read notifications from other apps.**"

## The one API that does forward other apps' notifications

There is now exactly one public route, and it is worth being precise about why
it is not ours. `AccessoryNotifications` (iOS 26.5) exists to satisfy the EU's
Digital Markets Act interoperability requirement: third-party watches must be
able to show iPhone notifications the way an Apple Watch does.

> "Receive forwarded iOS system notifications on **an accessory that you
> develop**."

Four things disqualify it, any one of which would be enough:

| Requirement | Dad |
|---|---|
| A physical accessory, receiving via an `AccessoryTransportExtension` data provider | An NFC sticker is not a Bluetooth peripheral; it has no processor |
| iOS 26.5 | The deployment target is iOS 17.0 |
| Customer use restricted to EU devices signed into an EU Apple Account | A household feature that works in one region is not a feature |
| Apple's licence terms on forwarded content | See below |

The fourth is the interesting one. Apple's Developer Program License Agreement
was amended in March 2026 to govern this data. As reported, third parties "may
not use Forwarding Information for advertising, profiling, training models, or
monitoring location", may not "disseminate the Forwarding Information to any
other Application, or any other device", and — decisively — **may not share the
data or the decryption keys with other devices including the user's own
iPhone**; decryption must happen on the accessory.

So even the maximal version of this feature — Dad ships hardware, requires iOS
26.5, and works only in the EU — produces a digest that is contractually
forbidden from reaching the phone app that would display it. The forwarding path
runs one way, off the phone, and terminates at the watch.

*(Unverified: the DPLA clause is cited here from press coverage naming Section
3.3.3(J), not from the agreement text itself. This repo has been burned once by
a second-hand account of an Apple document — see `docs/PROVISIONING.md` on the
Family Controls request form — so treat the exact wording as unconfirmed. It
does not change the outcome: the three preceding rows already disqualify it.)*

## The constraint that decides it regardless

Suppose Apple shipped `getEverybodysDeliveredNotifications()` tomorrow. Dad
still would not call it.

Hard rule 3 says only `DadMode+FamilyControls` may interpret a
`BlockedSelection`; everywhere else it is an opaque blob. That rule is not a
policy, it is a structure — the app cannot leak which apps you blocked because
the app never holds that fact in a readable form. `FamilyActivitySelection`
"holds opaque values" and Dad passes them straight back to `ManagedSettings`
without decoding them.

A digest inverts that exactly. To tell you that you missed four WhatsApp
messages, the app must learn that WhatsApp exists on your phone, that you use
it, and how much. That is strictly more knowledge than the selection Dad refuses
to decode — it is the same information plus content plus timing — and it would
have to live in the App Group, be read by a view, and survive on disk. The
structural guarantee would become a promise, which is exactly what hard rule 3
exists to avoid.

It also contradicts something already submitted to Apple. The Family Controls
(Distribution) justification in `docs/PROVISIONING.md`, filed 2026-09-02 and
still pending, says in Dad's own words:

> "Everything stays on the device. There is no server, no account, no network
> call and no analytics. The app never learns which apps were selected."

Family Controls approval is a human at Apple deciding whether a Screen Time app
is what it says it is. Shipping a notification-reading digest under an
entitlement granted on that description is the kind of thing that gets an
entitlement revoked, and this one has already cost the project weeks of calendar
time it cannot re-spend. Guideline 2.5.1 also requires that apps "use APIs and
frameworks for their intended purposes"; reading the household's messages under
a parental-controls entitlement is not that.

## Alternatives considered

**A digest of Dad's own notifications.** Legitimate, and useless: the only
notifications Dad sends are about Dad. `getDeliveredNotifications` would return
"your session ended". The user was there for that.

**Point at Notification Center instead of duplicating it.** iOS already keeps
undismissed notifications and stacks them by app; the honest version of this
feature is a sentence on the release screen saying so. That costs no API, no
entitlement and no storage — but it is a copy change, not a feature, and it does
not need an ADR to permit it.

There is a complication worth recording. One developer report (unanswered by
Apple, so **unverified**) says that shielding an app with `ManagedSettings` also
suppresses its notifications, rather than merely blocking launch. If that is
true, Notification Center will be *empty* for the shielded apps after a session,
and there is nothing for anyone — Dad or iOS — to summarise. Whether it holds is
answerable only on a device, which this project cannot reach until Family
Controls is approved. It does not change the decision; it may change what the
release screen should honestly say.

**Infer it from `DeviceActivityReport`.** The report knows usage, not messages,
and its extension is sandboxed against passing anything out. "You did not use
Instagram for two hours" is a statement Dad can already make from its own
session record, without Screen Time telling it — and `DadStats` makes it.

**Ask the user's other devices.** Covered by ADR 006, and it fails there for
different reasons.

## Decision

**Declined.** Not deferred: there is no version of this that iOS permits *and*
this project would ship.

The feasibility answer alone would be enough — no public API lets a
non-accessory app read another app's notifications, and the one framework that
forwards them is contractually barred from handing them back to the phone. But
the privacy answer is the load-bearing one, because it does not expire. If Apple
opened the API in iOS 28, Dad would still decline, for the same reason it does
not decode a `BlockedSelection`: a tool whose entire pitch is *the app does not
watch you* cannot ship a feature whose mechanism is watching you.

## Consequences

- Re-entry stays unassisted. Accepted. The user unlocks a phone and looks at
  Notification Center, which is where the information already is.
- `PARKING_LOT.md`'s "check feasibility first" item is closed by this ADR, the
  way the Live Activity item was closed by ADR 002.
- Dad gains no notification entitlement, no `UNUserNotificationCenter`
  authorization prompt, and no reason to raise its deployment target. Hard rule
  7 holds without having to be invoked.
- The Family Controls justification already filed with Apple stays true. That is
  worth more than the feature.

## What would change my mind

All three, not any one:

1. Apple ships a public, non-accessory API for reading system-wide notification
   *metadata* — counts and app identity, never content — behind an explicit user
   authorization prompt.
2. That API is available outside the EU and without shipping hardware.
3. Someone writes down how it coexists with hard rule 3. The only shape that
   plausibly does is a system-drawn summary Dad never reads — the equivalent of
   `DeviceActivityReport`'s sandboxed view, where the app hosts a report it
   cannot inspect. If Apple ever extends that pattern from usage to
   notifications, reopen this.

Absent 3, the first two do not matter.

## Sources

- `getDeliveredNotifications(completionHandler:)` — "Fetches all of **your
  app's** delivered notifications that are still present in Notification
  Center":
  <https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/getdeliverednotifications(completionhandler:)>
- `UNNotificationServiceExtension` — modifies a remote notification; fires only
  when the `aps` dictionary includes `mutable-content` set to `1`:
  <https://developer.apple.com/documentation/usernotifications/unnotificationserviceextension>
- `UNNotificationContentExtension` — "displays a custom interface for your app's
  notifications", keyed to a category the app itself declared:
  <https://developer.apple.com/documentation/usernotificationsui/unnotificationcontentextension>
- Apple DTS, "How can I access data from the iOS Notification Center?" — "It is
  not possible for your app to intercept and read notifications from other
  apps": <https://developer.apple.com/forums/thread/758584>
- `DeviceActivityReport` — "reports the user's application, category, and web
  domain activity in a privacy-preserving way"; the extension sandbox "prevents
  your extension from making network requests or moving sensitive content
  outside the extension's address space":
  <https://developer.apple.com/documentation/deviceactivity/deviceactivityreport>
- `INFocusStatus` — sole property `isFocused: Bool?`:
  <https://developer.apple.com/documentation/intents/infocusstatus>, with
  authorization via
  <https://developer.apple.com/documentation/intents/infocusstatuscenter>
- Sensitive Content Analysis — checks media the app itself is about to display:
  <https://developer.apple.com/documentation/sensitivecontentanalysis>
- `AccessoryNotifications` — "Receive forwarded iOS system notifications on an
  accessory that you develop"; accessory data-provider extension model:
  <https://developer.apple.com/documentation/accessorynotifications>
- `NotificationsForwarding` — iOS 26.5+, "A class for handling notification
  forwarding in your accessory's data provider extension":
  <https://developer.apple.com/documentation/accessorynotifications/notificationsforwarding>
- EU-only availability of notification forwarding, and its DMA origin:
  <https://www.macrumors.com/2025/12/15/ios-26-3-notification-forwarding/>
- Apple's licence rules on Forwarding Information (reported as DPLA §3.3.3(J);
  **wording unverified against the agreement itself**):
  <https://9to5mac.com/2026/03/30/apple-introduces-privacy-rules-for-third-party-access-to-notifications-and-live-activities/>,
  primary document at
  <https://developer.apple.com/support/terms/apple-developer-program-license-agreement/>
- `FamilyActivitySelection` — "holds opaque values that represent categories,
  applications, and web domains selected by the user":
  <https://developer.apple.com/documentation/familycontrols/familyactivityselection>
- App Review Guideline 2.5.1 — "Apps should use APIs and frameworks for their
  intended purposes"; 5.1.2(i) on data use and sharing:
  <https://developer.apple.com/app-store/review/guidelines/>
- Notification summaries are a system Settings feature; Apple publishes no
  developer API for them:
  <https://support.apple.com/guide/iphone/summarize-notifications-reduce-interruptions-iph1fbe7d2b9/ios>
- **Unverified, single unanswered report** that shielding an app also suppresses
  its notifications: <https://developer.apple.com/forums/thread/818841>
