# Entitlements and Apple approval

Two capabilities need explicit handling. One is a checkbox; the other is a
human at Apple reading your request. Start the second one early — it is the
single most common thing that blocks app blockers at submission time.

## Family Controls — the one that gates you

`com.apple.developer.family-controls` comes in two flavours:

**Development.** Enable the Family Controls capability in Xcode against your
team and you can build and run on your own device today. Nothing to wait for.

**Distribution.** Required for TestFlight *and* the App Store. You request it
from your Apple Developer account, per bundle ID — and **separately for every
Screen Time extension you ship**. For this project that's four requests:

- `app.tim.Tim`
- `app.tim.Tim.ShieldConfiguration`
- `app.tim.Tim.ShieldAction`
- `app.tim.Tim.ActivityMonitor`

A human reviews each one. Reported turnaround runs from about four business days
to a few weeks. You cannot upload a build to TestFlight until it's approved, so
file it the day you start building, not the week you want to ship.

What Apple is checking: that the app's core purpose genuinely needs Screen Time
— parental controls, family safety, or personal digital wellbeing — and that
you're not using the capability to harvest usage data for advertising or
profiling. A focus app that hides your own apps at your own request is squarely
inside that. Say so plainly in the request, describe the tap-to-block mechanic,
and note that the app never receives app identities, only opaque tokens.

If you're only building this for yourself, you can stop after the development
entitlement and just install to your own device from Xcode. A free Apple
Developer account gives you 7-day provisioning; a paid one gives you a year.

## NFC

`com.apple.developer.nfc.readersession.formats` — enable the **Near Field
Communication Tag Reading** capability in Xcode. No approval, no review. Needs
`NFCReaderUsageDescription` in `Info.plist` alongside it, which is already
there.

## App Groups

`group.app.tim.shared` — the app and all three extensions must share it. The
shield extension runs in its own process and reads the active session out of
this group; if it's missing or misspelled on any target, the shield will show
the wrong mode name or fail to launch. `TimStore` traps on a missing group
deliberately, so you find out at once rather than debugging a silently wrong
shield.

## Associated Domains

`applinks:tim.example.com` — only needed for background tag reading. Delete the
key if you're using the Shortcuts route. See [nfc-and-tags.md](nfc-and-tags.md).

## Changing the identifiers

The placeholders assume `app.tim.*`. To use your own:

1. `project.yml` — `bundleIdPrefix`, every `PRODUCT_BUNDLE_IDENTIFIER`, and
   `DEVELOPMENT_TEAM`
2. `Tim/Shared/TimStore.swift` — `appGroupID`
3. all four `.entitlements` files — the app group, and the domain if you use one

Then `xcodegen generate` again.
