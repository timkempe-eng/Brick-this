# Day one: from a bag of stickers to a Timmed phone

Your NTAG215s are the right chip. Here's the order to do things in, and where
it's most likely to go wrong.

## Before the tags arrive

You can do all of this now — none of it needs the stickers.

1. **Run the checks.** `swift test` covers the engine; `python3
   scripts/preflight.py` checks the Xcode wiring that nothing else will warn
   you about — App Groups matching across all four targets, extension
   principal classes actually existing, every target linking what its adapters
   import. Both run without a Mac.
2. **Request the Family Controls entitlement.** Development access is instant,
   but if you ever want this on TestFlight the distribution request is a manual
   review at Apple that takes days to weeks, per bundle ID.
   [Details](entitlements.md). File it first; everything else is faster.
3. **Generate the project.** `brew install xcodegen && xcodegen generate`
4. **Set your Team ID** in `project.yml`, then `xcodegen generate` again.
5. **Add the Family Controls capability** to all four targets in Xcode, and
   **App Groups** (`group.app.tim.shared`) to all four. A mismatch here doesn't
   fail loudly — the shield just shows the wrong mode name — which is why
   preflight checks it.
6. **Build to your iPhone.** Screen Time and NFC both no-op in the Simulator,
   so a real device is the only way to see anything work.

At this point you can already Tim your phone from the in-app button; only the
tap is missing.

## When the tags arrive

1. **Open Tim, grant Screen Time access.** One system prompt.
2. **Build a Mode.** Start with one — "Deep Work" — and pick three or four apps
   you actually lose time to. Blocking thirty apps on day one is how people
   quit this after a week.
3. **Pair a tag.** Settings → Pair a Tim tag → hold the phone to the sticker.
   Until you pair one, any tag works; after that only yours do.
4. **Test it in-app.** Press "Tim my phone", then try to open a blocked app. You
   should get the "Timmed." shield. Press "Un-Tim" to release.
5. **Optionally give a Mode a schedule.** Sleep, every night, 22:00–07:00, and
   the phone Tims itself. A schedule never overrides a session you started by
   hand, and you can always tap out early.
6. **Set up the Shortcuts automation** so the tap works with Tim closed:
   Shortcuts → Automation → NFC → Scan → add the "Tim my phone" action → turn
   **Ask Before Running** off. [Full steps](nfc-and-tags.md#2-shortcuts-automation--the-one-to-use).
7. **Stick the tag somewhere inconvenient.** This is the actual product. A
   sticker on your desk gives you nothing; one in a drawer in another room is
   the whole mechanism.

## If something doesn't work

**The tap does nothing.** Check the Shortcuts automation has Ask Before Running
off. NFC personal automations need iPhone XS or later.

**"Tag not found" / nothing reads.** Is it on metal? Even a laptop lid detunes
the antenna enough to kill the read.

**Apps aren't blocked but the app says Timmed.** The Mode has nothing selected,
or Screen Time authorization was declined. Check Settings → Screen Time.

**The shield shows the wrong Mode name.** The App Group isn't set on the shield
extension target. It's the most common mismatch, because the app itself works
fine without it — run `python3 scripts/preflight.py`, which checks exactly this.

**A scheduled Mode never fires.** Check the schedule is enabled, has at least
one day, and spans 15 minutes or more; anything shorter is below what
DeviceActivity will monitor. The editor says so under the section when the
schedule can't run.

**You can still delete Tim while Timmed.** That Mode doesn't have Strict on.

## A note on the escape hatches

You get five emergency overrides per rolling 30 days, and they come back on
their own. That's deliberate — Brick makes you email support, which is friction
for its own sake. The point of the limit is to make you notice you're using
them, not to lock you out of your own phone.

If you find yourself burning all five, the Mode is wrong. Block less.
