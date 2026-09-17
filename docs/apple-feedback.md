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

## Report 2 — Assistive Access has no self-service door

**Starting topic:** iOS & iPadOS
**Suggested area:** Accessibility
**Type:** Suggestion (enhancement request)

**Title:**

> Enhancement: allow a person to enter Assistive Access on their own device
> with their own consent — its passcode is designed for a separate supporter

**Description:**

> Assistive Access is the only place in iOS where a phone visibly *becomes*
> something simpler rather than merely losing apps, and it would be an
> excellent anti-distraction tool. It cannot be used as one, for a structural
> reason rather than a missing API detail.
>
> **The whole third-party surface is five symbols, and every one of them reads
> the mode or draws inside it:** the `AssistiveAccess` SwiftUI scene,
> `UISupportsAssistiveAccess`, `UISupportsFullScreenInAssistiveAccess`,
> `AccessibilitySettings.isAssistiveAccessEnabled` and the
> `accessibilityAssistiveAccessEnabled` environment value. Nothing enters,
> leaves or configures it. I also checked the MDM path:
> `com.apple.applicationaccess` has no Assistive Access key, and the iOS 26
> enterprise release notes do not mention it.
>
> **The passcode is the real barrier, and it is a design decision rather than
> an oversight.** Apple's setup guide says the Assistive Access passcode "is
> used to enter or exit Assistive Access and change Assistive Access settings."
> On my own phone, which already had a Screen Time passcode, the triple-click
> asked for that. This is correct for the audience the feature was built for: a
> trusted supporter sets it up on somebody else's behalf, and the person using
> the phone is not meant to be able to walk back out.
>
> **It also means there is no self-commitment path.** An adult who wants to put
> their *own* phone into a simpler state has to type a code that, by design, is
> meant to be held by somebody else. The feature can be administered *to* a
> person and cannot be chosen *by* one.
>
> **The precedent for what I am asking already ships.**
> `UIAccessibility.requestGuidedAccessSession(enabled:completionHandler:)` has
> existed since iOS 7 and lets an app put a device into Single App mode
> programmatically. Its documented requirement is that "entering Single App
> mode is supported only for devices that are supervised using Mobile Device
> Management (MDM), and the app itself must be enabled for this mode by MDM."
> So a programmatic lockdown capability is a decade old, and is gated to
> enterprise supervision rather than absent. I am asking for the consented,
> user-owned version of a mechanism Apple has already built and shipped.
>
> **Any one of these would be enough, in order of preference:**
>
> 1. An API to request entry into Assistive Access that requires explicit user
>    consent at the moment of the call — the same shape as
>    `AuthorizationCenter.requestAuthorization(for: .individual)`, which already
>    gates Family Controls behind Face ID on the user's own device.
> 2. A Shortcuts action to enter Assistive Access, so a person can build the
>    automation themselves without any app being trusted with it.
> 3. No API at all: an option during Assistive Access setup for a
>    self-administered session — entered without the supporter passcode, left
>    with the device passcode or a chosen delay. This needs nothing from
>    developers and would serve the use case entirely.
>
> **Why this is worth doing.** Apple already treats attention as a thing worth
> protecting — Downtime, App Limits and Focus all exist. Assistive Access is
> the most effective version of that idea Apple has ever shipped, and it is
> reachable only by people who have somebody else administering their phone.
> The audience it was built for should keep the passcode exactly as it is. The
> ask is only that a person be allowed to choose it for themselves.

---

## What not to send yet

The featuring nomination in App Store Connect and a WWDC lab both want
something to look at. Both are better spent after a TestFlight build exists —
"here is the app, and here is the one API that would make it work" is a
different conversation from a description of an app that does not run yet.
