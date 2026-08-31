# What's not built yet

The core loop is complete: pick a Mode, tap, apps disappear, tap, they come
back. These are the things Brick has that Tim doesn't, roughly in the order
they'd be worth adding.

**Stats and streaks.** `TimStore.history` already records every session with its
mode, duration, and whether it ended by tag or by emergency override — the data
is there, there's just no screen showing it. A weekly total, a current streak,
and the ratio of clean finishes to bail-outs would cover most of it.

**A Lock Screen widget and Live Activity.** The status is currently only visible
inside the app, which is a little absurd for a product about not opening your
phone. A Live Activity showing the running timer is the natural home for it.

**Scheduled Modes.** `DeviceActivityMonitor` is already wired up for timed
release; the same extension can start a session on a recurring schedule — Tim
me every weeknight at 10pm without a tap.

**Allowance rather than blocking.** Screen Time can also throttle rather than
forbid. A Mode that grants fifteen minutes of a given app per day is a softer
tool than a hard shield, and sometimes the right one.

**Android.** Different mechanism entirely — an `AccessibilityService` watching
the foreground package rather than a system-enforced shield. The Mode model and
the tag format would carry over; nothing else would.

**A nicer tag.** A 3D-printed puck with a magnet and some ballast. Purely
cosmetic, entirely worth it.
