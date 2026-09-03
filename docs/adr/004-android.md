# ADR 004: No Android app in the accessibility-service form

**Status:** accepted
**Date:** 2026-09-03

## Context

"Android" has sat in the parking lot's *Later* section since the beginning,
with one line of reasoning attached: `Dad/Shared/Core` would port nearly as-is,
every adapter is new, and blocking via `AccessibilityService` is meaningfully
weaker. Brick ships an Android app built exactly that way, so the shape is
proven to be buildable.

The item was never decided, only deferred. This settles it, because the two
things it turns on — how Android actually blocks an app, and what Google is
doing to that mechanism — have both moved, and in the same direction.

## What blocking an app on Android actually is

Android has no Screen Time. There is no third-party equivalent of
`ManagedSettings`: Digital Wellbeing is Google's own and exposes nothing.
There are three mechanisms and no fourth.

| Mechanism | How it blocks | What undoes it |
|---|---|---|
| `AccessibilityService` | Watch `TYPE_WINDOW_STATE_CHANGED`, read the foreground package, send the user home or paint an overlay | Settings → Accessibility → off. Three taps. |
| `UsageStatsManager` polling | A foreground service asks every second or so which app is in front | Kill the service, or revoke usage access. Also laggy and costs battery. |
| `DevicePolicyManager.setPackagesSuspended` | The system suspends the package. It cannot start activities, show notifications, play audio or vibrate. | Nothing the user can reach. Requires device-owner or profile-owner. |

Only the third is a *block* in the sense iOS means. The first two are a
program racing the user, and Brick's Android app is the first one — which is
why its own listing does not offer website blocking.

## Why the weak version is not worth building

The teardown's central finding is the reason this product exists at all:

> Software-only blockers fail because disabling them costs you three taps in a
> moment of weakness.

An `AccessibilityService` blocker *is* three taps in Settings. Shipping one
would mean shipping a product whose central claim — the block survives, and
getting your apps back means walking to the tag — is false on that platform.
On iOS the claim is structural: the restrictions are stored by the system and
outlive our process, and `denyAppRemoval` closes the delete-the-app hatch.
There is no Android equivalent of either at consumer permission levels.

Hard rule 7's logic applies to platforms as well as entitlements: no
capability without a feature that honestly ships. A second platform where the
one promise does not hold is worse than no second platform, because a user who
has been told Dad works cannot tell which version they have.

## And the mechanism is closing anyway

Google has spent five years narrowing `AccessibilityService`, and 2026 is the
year it stops being a grey area.

- Since November 2021, any app targeting API 31+ that ships an
  `AccessibilityService` must file a Play Console policy declaration
  justifying it. Review tightened again ahead of enforcement in January 2026.
- Android 16 introduced **Advanced Protection Mode**. In Android 17 that mode
  **blocks non-accessibility apps from the accessibility API entirely** —
  existing grants are revoked, new ones refused. Qualifying requires
  `isAccessibilityTool="true"`, and Google names the four categories that may
  claim it: screen readers, switch input, voice input, and Braille access. App
  blockers are not among them; monitoring and automation apps are called out
  as excluded.

Advanced Protection is opt-in, so this does not delete the mechanism today.
The direction is unambiguous, and building on it means building on a
foundation whose owner has said what it is for and that this is not it.
Declaring `isAccessibilityTool` to get past the check would be a lie told to
the platform on the user's behalf, which is not a thing this project does.

## The version that would actually work, and what it costs

`setPackagesSuspended` under **device-owner** is a real block: no accessibility
service, no polling, no foreground process, and nothing the phone's user can
switch off. It is genuinely stronger than the iOS shield.

The cost is provisioning. Device-owner can only be established during initial
setup or after a factory reset — the API's requirement is a device with no
accounts on it — via QR, zero-touch, NFC, or `adb shell dpm set-device-owner`
with the phone plugged into a computer. It cannot be granted later by a user
who has already set their phone up, however much they want to.

For one adult Dadding their own phone, that is an absurd price: factory-reset
your phone to install a focus app. So under the product as it stands, this
route is not merely expensive, it is unsellable.

## Decision

**Do not build an Android app on `AccessibilityService` or `UsageStatsManager`.
Not now, not as a stopgap.** The block would not hold, which makes it a
different product wearing the same name.

**Keep the device-owner route open, unbuilt, with a named trigger.** Build it
when there is a phone somebody is willing to provision from a factory reset —
and there is one obvious case: a phone being set up *for* someone else, at the
moment it is being set up. A parent handing over a first phone is already
holding a factory-fresh device with no accounts on it, which is precisely the
window device-owner requires and the only moment it is free.

That makes this decision a dependency of the family work rather than a
platform question: if Dad stays a tool one adult points at their own phone,
Android has no good answer and should not get a bad one. If it becomes
something a household sets up together, Android gets the *stronger* of the two
implementations, and the provisioning step lands on the one day it costs
nothing.

## Consequences

- Android stays unbuilt, and the roadmap says why rather than listing it as
  pending work.
- **The parking lot's claim that Core "would port nearly as-is" is corrected.**
  The *design* ports; the code does not. `Dad/Shared/Core` is Foundation-only
  Swift and Android has no Swift runtime worth shipping, so it is a retype into
  Kotlin — 1,700 lines, of which about 900 are code and the rest is the
  reasoning that makes them safe to change, plus 2,300 lines of tests, kept in
  step by hand forever.
  Kotlin Multiplatform would invert that by making Kotlin the source of truth
  for the iOS app too, which is a much larger decision than "add Android" and
  is not one to make as a side effect.
- The port boundary is still worth what it cost. It is what makes this ADR
  short: everything platform-specific is already named and behind a protocol,
  so the question is only ever "what implements `ShieldControlling` there", and
  the answer is now written down.

## Sources

- [Use of the AccessibilityService API — Play Console Help](https://support.google.com/googleplay/android-developer/answer/10964491)
- [Android 17 blocks non-accessibility apps from the accessibility API](https://thehackernews.com/2026/03/android-17-blocks-non-accessibility.html)
- [Advanced Protection Mode and accessibility misuse](https://securityaffairs.com/189497/security/advanced-protection-mode-in-android-17-prevents-apps-from-misusing-accessibility-services.html)
- [`DevicePolicyManager.setPackagesSuspended`](https://developer.android.com/work/dpc/security)
- [Provision for device management — AOSP](https://source.android.com/docs/devices/admin/provision)
- [Can I set Device Owner without a factory reset? — Jason Bayton](https://bayton.org/android/android-enterprise-faq/can-i-set-device-owner-without-factory-reset/)
- [docs/brick-teardown.md](../brick-teardown.md), on why the friction is the product
