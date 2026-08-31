# ADR 001: Ports and adapters for the engine

**Status:** accepted
**Date:** 2026-08-31

## Context

`TimEngine` holds the entire product: tap toggles, mode selection, emergency
overrides, session archiving. It is also the code most likely to be subtly
wrong, because it is a state machine over time.

As first written it was a static `enum` that reached directly for
`TimStore.shared`, `Shielder`, `DeviceActivityCenter()` and `Date()`. Every one
of those is either a singleton, an iOS-only framework, or the system clock. The
result: **the most important code in the project could not be tested at all**,
and could only be compiled on a Mac.

That is backwards. The stats maths — much less critical — was fully tested,
while the toggle logic was not.

## Decision

Invert the dependencies. `TimEngine` moves into `Tim/Shared/Core` and depends
only on protocols it declares:

| Port | Hides | iOS adapter |
|---|---|---|
| `Clock` | the system clock | `SystemClock` |
| `ShieldControlling` | ManagedSettings | `ManagedSettingsShield` |
| `SessionScheduling` | DeviceActivity | `DeviceActivityScheduler` |
| `TimPersisting` | the App Group `UserDefaults` | `UserDefaultsStore` |

`TimEngine` becomes a struct holding those four, constructed once at a
composition root (`TimEngine.live`) that only the iOS targets compile.

### Keeping FamilyControls out of Core

`TimMode` held a `FamilyActivitySelection`, which is a FamilyControls type, so
`TimMode` could not move to Core with it. But Core does not care *which* apps a
mode blocks — only whether it blocks anything, and how to describe it. Only the
shield adapter needs the real tokens.

So `TimMode.blocked` is a `BlockedSelection`: an opaque `Data` payload plus
three counts. Core reads the counts; the iOS adapter encodes and decodes the
real `FamilyActivitySelection` into and out of the payload.

This is not a workaround — it is the privacy model made structural. The app is
supposed to never learn which apps you picked. Now the type system says so:
nothing outside one adapter file can interpret that blob.

## Consequences

**Good.** The whole state machine is testable on Linux with fakes, so the
behaviour that matters — allowance windowing, toggle ordering, what happens
when a scheduled release lands after a manual one — is verified rather than
asserted. CI runs it on every push. The iOS layer shrinks to thin adapters with
close to no logic worth testing.

**Cost.** One indirection between the engine and each framework, and a small
amount of encode/decode at the FamilyControls boundary. Two representations of
a mode's selection have to be kept in step, which is a real risk and is why
`TimMode+FamilyControls` keeps that conversion in one place, both directions
adjacent.

**Deliberately not done.** No DI container, no service locator. Four
dependencies passed to one initialiser is not a problem that needs a framework.
