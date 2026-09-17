# What to ask Apple, and where

Two Feedback Assistant reports, written to be pasted. They are separate on
purpose: Apple's own guidance is **one issue per report** — "reports that
discuss multiple issues aren't actionable and may be returned for resubmission
as separate reports" — and these two land on different teams.

Neither is speculative. Each one cites Apple's documentation, an Apple
engineer, or a measurement taken on a phone, and each asks for a decision Apple
can actually make.

## Where to file

**[feedbackassistant.apple.com](https://feedbackassistant.apple.com)** in a
browser, or the Feedback Assistant app on the device. The app collects
diagnostics automatically and the website needs them attached by hand — which
matters for a crash and not for these, so the browser on an iPad is fine.

Sign in with the Apple Account that holds the developer membership, so the
reports are associated with a developer rather than a customer.

The form asks for a **starting topic**, a **title**, and a **description**.
Apple's guidance on titles: concise, and naming the technology, platform and
version. The description wants steps, actual result, expected result, and
context.

**Keep the FB numbers.** They are the currency: a WWDC lab engineer, a forum
reply and a developer-relations conversation all start with "do you have a
feedback number?", and a two-year-old report with a real use case carries more
weight than a fresh one.

---

## Report 1 — the contradiction

**File this one first.** It is not a feature request: it is Apple contradicting
itself in writing, which is the kind of thing a feedback report is best at
resolving. It also blocks shipping work today, which Report 2 does not.

**Starting topic:** Developer Technologies & SDKs
**Suggested area:** ManagedSettings / Screen Time / Family Controls
**Type:** the closest to "Incorrect/Unexpected Behavior" — this is a
documentation-and-review inconsistency rather than an enhancement. If the form
pushes you to "Suggestion", that is fine; the body is what matters.

**Title:**

> ManagedSettings blockedApplications is documented as hiding apps and
> recommended for it by an Apple engineer, but App Review rejects that use
> under guideline 2.5.1

**Description:**

> I am building an iOS app that helps a person remove distracting apps from
> their own phone for a set period, with their explicit consent, on their own
> device. I need to know whether `blockedApplications` is a sanctioned way to
> do that, because Apple currently says three different things.
>
> **1. The documentation says it hides apps.**
> `ManagedSettings.ApplicationSettings.blockedApplications` is documented as:
> "The system hides blocked applications and prevents the user from launching
> them."
>
> **2. An Apple Frameworks Engineer recommends it for exactly this.** In
> Developer Forums thread 716519 ("How to hide specific apps from home screen
> proactively?"), an Apple Frameworks Engineer answers that this is possible,
> posts sample code setting `store.application.blockedApplications`, and
> confirms it works under `.individual` authorization — not only under a
> parent-child Family Sharing arrangement.
>
> **3. App Review rejects it.** In Developer Forums thread 776058, a developer
> whose Family Controls & Personal Device Usage entitlement had already been
> approved was rejected under guideline 2.5.1: "your app uses ScreenTime API to
> hide apps." The developer appealed, quoting the documentation above
> verbatim, and received the same rejection text again. No Apple engineer
> responded in the thread, and it is still unresolved.
>
> **What I need is a decision, not a workaround.** Either:
>
> - `blockedApplications` is a supported way for an authorized app to hide apps
>   on a consenting user's own device — in which case App Review needs to know
>   that, because developers are currently being rejected for following both
>   the documentation and an Apple engineer's advice; or
> - it is not, and the documentation and the forum answer are both wrong — in
>   which case please say so in the documentation, so that the API's one
>   documented behaviour is not a trap.
>
> **Why it matters.** Shielding an app covers it when you open it. The icon,
> the badge and the folder all stay on the Home Screen, so the thing that
> actually pulls attention is untouched. Hiding is the behaviour that serves
> the user's stated intent, and the API that does it is the one that is
> ambiguous. I would rather build the sanctioned thing than discover the answer
> at review, after an entitlement request that already takes weeks.

---

## Report 2 — you need permission to make your phone *less* capable

**Starting topic:** iOS & iPadOS
**Suggested area:** Accessibility
**Type:** Suggestion (enhancement request)

The first draft of this report asked for a "self-commitment path", which is a
feature request and easy to decline. The argument below is not a feature
request. It is that one gate is pointed the wrong way, and iOS already agrees
everywhere else.

**Title:**

> Assistive Access: entering it requires the Screen Time passcode, so a person
> under someone else's Screen Time supervision cannot voluntarily restrict
> their own device further

**Description:**

> **My situation, which I do not think is rare.** I am an adult. I have
> deliberately given my spouse ownership of the Screen Time passcode on my own
> phone, as a guardrail I chose for myself. It works, and I do not want it
> changed.
>
> I now want to put my phone into a much more limited state for an hour —
> essentials only, a far quieter interface — so I can concentrate. Assistive
> Access does exactly this, and does it better than anything I could build. I
> cannot use it, because entering it asks for the Screen Time passcode, which I
> do not have and deliberately do not want.
>
> **The gate is pointed the wrong way.** A credential should be required to
> *reduce* a restriction, not to *add* one. Everything the Screen Time passcode
> protects is on the loosening side: more time, fewer limits, turning it off.
> Entering Assistive Access does none of those things. It is strictly
> subtractive — fewer apps, less interface, less capability. There is nothing
> there for a passcode to protect, and gating it means the one thing I cannot
> do to my own phone is make it less powerful.
>
> **iOS already agrees with me everywhere else.** With no passcode and no
> supervision, any user can:
>
> - Build a Focus that hides whole Home Screen pages and chooses which apps
>   appear while it is on.
> - Hide or lock individual apps behind Face ID (iOS 18).
> - Delete apps, turn on Do Not Disturb, and strip the Home Screen bare.
>
> Every one of those makes the phone less capable, and none of them asks
> anybody's permission. Assistive Access is the outlier, and the only apparent
> reason is that it was designed for a supporter administering somebody else's
> device. That audience should keep the passcode exactly as it is. It should
> not be the only door.
>
> **The obvious objection, and my answer.** Gating entry presumably stops
> somebody with brief physical access from trapping another person in a
> simplified phone they cannot leave. That is a real risk and I am not asking
> you to accept it. It is solved by the *exit* credential rather than the entry
> one:
>
> - For a **self-initiated** session, exiting takes the *device* passcode or
>   Face ID — the credential the owner already holds. Nobody can be trapped,
>   because whoever can enter can always leave.
> - Optionally, the person chooses a duration on the way in and it expires by
>   itself.
> - The supporter-administered mode is untouched: set up with the Assistive
>   Access passcode as it is today, and it still takes that passcode to leave.
>
> Entry needs no authorization because entry cannot harm anyone. Exit is where
> the authorization belongs, and which credential it takes should follow from
> who started the session.
>
> **The precedent for programmatic control already ships.**
> `UIAccessibility.requestGuidedAccessSession(enabled:completionHandler:)` has
> existed since iOS 7 and puts a device into Single App mode from code. Its
> documented requirement is that "entering Single App mode is supported only
> for devices that are supervised using Mobile Device Management (MDM), and the
> app itself must be enabled for this mode by MDM." So a programmatic lockdown
> capability is a decade old and gated to enterprise supervision rather than
> absent.
>
> **Any one of these would solve it, in order of preference:**
>
> 1. A self-initiated Assistive Access session: entered without the Assistive
>    Access passcode, left with the device passcode or Face ID, optionally
>    time-boxed. This needs no new API and no developer involvement at all.
> 2. A Shortcuts action to enter Assistive Access, so a person can attach it to
>    their own automation — an NFC tag, a time of day, arriving somewhere.
> 3. An API to request entry, gated by explicit user consent at the moment of
>    the call — the same shape as
>    `AuthorizationCenter.requestAuthorization(for: .individual)`, which already
>    puts Family Controls behind Face ID on the user's own device.
>
> **What I am actually trying to do**, in case it helps: tap an NFC sticker on
> my desk and have my phone become essentials-only for an hour, then tap it
> again to come back. The apps part I can already build with the Screen Time
> APIs. The interface part — the thing that makes a phone stop shouting — only
> Assistive Access does, and it is the one part I am locked out of.
>
> I am not trying to get around supervision. I am trying to add to it.

## What not to send yet

The featuring nomination in App Store Connect and a WWDC lab both want
something to look at. Both are better spent after a TestFlight build exists —
"here is the app, and here is the one API that would make it work" is a
different conversation from a description of an app that does not run yet.
