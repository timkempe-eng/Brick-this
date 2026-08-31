# What's not built yet

The engine, its ports, and the stats maths are covered by `swift test`. The
list below is roughly in the order the remaining work is worth doing.

The core loop is complete: pick a Mode, tap, apps disappear, tap, they come
back. These are the things Brick has that Tim doesn't, roughly in the order
they'd be worth adding.

~~**Stats and streaks.**~~ Built — `TimStats` plus `StatsView`. Streak, weekly
total, a seven-day chart, and the clean-finish ratio. The arithmetic is
Foundation-only and covered by `swift test`.

**A Lock Screen widget and Live Activity.** The status is currently only visible
inside the app, which is a little absurd for a product about not opening your
phone. A Live Activity showing the running timer is the natural home for it.

~~**Scheduled Modes.**~~ Built — `ModeSchedule`, registered declaratively with
DeviceActivity and driven from both edges of each window. The wall-clock maths
and the collision rules (a schedule never stomps a session you started by hand)
are covered by `swift test`.

**Allowance rather than blocking.** Screen Time can also throttle rather than
forbid. A Mode that grants fifteen minutes of a given app per day is a softer
tool than a hard shield, and sometimes the right one.

**Android.** Different mechanism entirely — an `AccessibilityService` watching
the foreground package rather than a system-enforced shield. The Mode model and
the tag format would carry over; nothing else would.

**A nicer tag.** A 3D-printed puck with a magnet and some ballast. Purely
cosmetic, entirely worth it.
