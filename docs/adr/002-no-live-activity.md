# ADR 002: No Live Activity

**Status:** accepted
**Date:** 2026-09-01

## Context

The Lock Screen widget shipped, and the parking lot's next item was a Live
Activity: the Dynamic Island, and a richer running presentation while a session
is open. It looked like a natural extension — `WidgetRefreshing` already
generalises to it, and the UI would live in the widget extension that now
exists.

## The constraint

**ActivityKit can only start a Live Activity while the app is in the
foreground.** `Activity.request()` fails otherwise, and no App Intent,
background task or extension changes that. Apps may *update* and *end* an
activity from the background; only the start is gated.

## Why that is fatal here, specifically

Dad's whole point is not opening the app. Sessions begin on three paths:

| Path | Process | Can start a Live Activity |
|---|---|---|
| Shortcuts NFC automation → `ToggleDadIntent` | background | **No** |
| A scheduled Mode's window | DeviceActivity extension | **No** |
| The in-app button | foreground | Yes |

The primary path — the one the product is built around, tap the tag and pocket
the phone — is the one that cannot start it. A Live Activity would therefore
appear only when you Dadded your phone by *opening the app*, which is the
behaviour Dad exists to make unnecessary.

That is worse than not having it. A status presentation that shows up on the
rare path and is absent on the common one teaches the user it cannot be
trusted, and "was I Dadded?" becomes a question again — the exact question the
widget was built to answer.

## Alternatives considered

**ActivityKit push notifications** can start an activity while the app isn't
running. That needs APNs, a push token, and a server to send from. This project
has no backend by design — "nothing leaves the device; there is no server and
no network code" — and standing one up so a Lock Screen animation can start is
a bad trade against the privacy posture.

**Start it late, on next foreground.** The activity would then begin whenever
you next opened the app, minutes or hours into a session, and be absent for the
period that matters. It also duplicates the widget, which already works from
every process.

## Decision

Don't build it. The Lock Screen widget is the correct answer for this product:
it renders from any process, needs no foreground, and answers the same question.

Revisit only if Apple lifts the foreground requirement for locally-started
activities.

## Consequences

The Dynamic Island stays empty. Accepted — it is a presentation surface, not a
capability, and the capability is already covered.
