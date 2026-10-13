# ADR 009: rewards are priced in whole hours off the phone

**Status:** accepted
**Date:** 2026-10-13

## Context

The reward ledger paid one **day** for each calendar day on which someone ended
a session by hand. The household using it asked for something different: an
amount for each full hour the phone stays Dadded. A long evening off the phone
should be worth more than ten minutes, and a day-count could not show that.

`RewardLedger.swift` had turned this down already, for two reasons:

- **Points are tunable.** If a point is whatever the app says it is, someone
  sets its exchange rate. Raise the rate and balances inflate; lower it and
  rewards already promised quietly cost more.
- **A duration slides toward screen time.** `Days` existed partly so that the
  ledger's unit could not be multiplied into minutes. ADR 007 and the README
  both rule out paying in screen time.

Hours paid per session also bring three problems of their own:

1. **Sleep pays best.** An overnight session ended by a tap in the morning
   would earn about eight, more than any evening that took effort.
2. **Farming.** Dad the phone, leave it in a drawer during school, collect.
3. **Grown-ups lose.** An adult whose job needs a phone trails the teenagers
   every week. That cuts against the shared streak, which is built so that
   every phone counts the same.

## Decision

**Rewards are priced in `RewardLedger.Hours`: one for each whole hour of a
session a person ended themselves, up to four on any one day.**

- **Whole hours, per session.** Fifty-nine minutes earns nothing, and two
  half-hour sessions do not add up to an hour. Each session is measured on its
  own, so that "each full hour" means one unbroken hour.
- **Only sessions a person ended.** This is the same `wasEndedByAPerson` rule
  the ladder reads. A session a schedule opened and closed earns nothing, and
  so does a session ended with an emergency override. That shuts off the
  overnight Sleep schedule entirely.
- **A ceiling of four hours a day** (`hoursCountedPerDay`). Four is about an
  evening, from home-from-school to bed, and the evening is what the reward is
  for. A night or a school day still earns, but no more than an evening does.
  The ceiling eases problems 1 and 2. It does not remove them, and the
  household should know that.
- **A session's hours land on the day it started**, under that day's ceiling,
  the same day rule `DadStats` uses.

What did not change:

- **No points.** An hour is not a tunable unit. It happened or it did not. The
  one tunable is the ceiling, and changing it alters how much a day can earn,
  never what an hour already earned is worth.
- **No screen time.** `Hours` has `+`, a saturating `-` and `<`, and nothing
  else. The source-reading test still fails the build if `RewardLedger.swift`
  names `TimeInterval`, `Double`, `*` or `/`. That is why the measuring lives
  in `DadSession.wholeHoursEndedByAPerson` and not in the ledger.
- **The ladder still counts days.** A rung is evidence of a habit held over
  time, and a single long session is not that. The two ledgers read the same
  sessions, and `TwoLedgersAgreeTests` asserts that they credit the same days.

## Consequences

- Rewards stored before this change keep their number, which now reads as
  hours. A reward priced at 5 days becomes 5 hours and needs re-pricing. The
  JSON format is unchanged, so nothing is dropped.
- Balances are re-derived from the session history, so on the day the
  household updates, each balance moves from days to hours. Claims already
  made keep the price they were made at.
- Problem 3 is not solved. The reward ledger is per phone and compares nobody
  with anybody, so an adult earning fewer hours is not shown losing. Nobody
  should build a household hours leaderboard on top of this without reopening
  that question.
- `PromisedNumbersTests` pins the ceiling at four, because the Rewards screen
  prints it.

## Follow-up: where hours leaked (2026-10-13)

Going through how sessions end against the rule above found two ways for hours
to vanish with nobody doing anything wrong, and two improvements.

- **A granted break ended the session as `.system`**, which earns nothing, so
  three hours Dadded followed by a break a grown-up approved at their tag
  earned zero. It now ends `.granted`, which counts as a person ending it.
- **A Mode's timed release also ended `.system`.** It now ends `.timed`, which
  counts if a person started the session, because they chose the timer. It
  does not count on a session a schedule started, because nobody chose that
  timer at the moment it ran.
- Both new endings feed `wasEndedByAPerson`, so **they count toward a rung as
  well**. That is the one-definition rule working as intended. Sessions stored
  before this keep their `.system` ending, and nothing can tell them apart.
- The two new stored values bump `SchemaCoding.current` to 3. An older build
  would otherwise drop every session carrying one and then write the shorter
  history back.
- **Hours left with the history.** The history keeps the last
  `DadEngine.historyLimit` sessions, so once the oldest dropped off, the
  balance shrank. The engine now writes those sessions' hours to
  `archivedRewardHours` (per day, before the ceiling) as it trims them, and
  the ledger adds them back. It is the one stored earned quantity, for the
  same reason the ladder writes its rung down. Hours lost to trims before this
  change are not recovered.
- **A countdown while Dadded.** `HourProgress` shows "2 hours so far · next in
  18 min" on the home screen, under a note that the hours count only when you
  Un-Dad yourself. It is a forecast and never enters the balance.

## Follow-up: the night does not count (2026-10-13)

The household asked that time between 23:00 and 06:00 earn nothing. That
removes problem 1 at its source rather than capping it: an overnight session
now earns its evening and its morning, and the night between is unpaid.

- `RewardNight` measures a session's counted time: everything outside
  23:00–06:00, local wall-clock time through the injected calendar, so the
  night the clocks change is still 23:00 to 06:00 (pinned by a test on
  Europe/London's spring-forward night).
- One session's counted time is summed before rounding down, so 22:00 to
  07:00 earns two hours: one each side of the night, from one unbroken
  session.
- The ceiling stays at four. It now limits long daytime sessions, such as a
  school day, rather than sleep.
- The countdown skips the night: started at 22:30, the next hour lands at
  06:30, and between 23:00 and 06:00 the home screen says the night doesn't
  count rather than counting down hundreds of minutes.
- The ladder is unchanged. A session ended overnight still makes its day a
  clean day, at zero hours.
