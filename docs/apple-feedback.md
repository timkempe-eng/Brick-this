# What to ask Apple, and where

Two Feedback Assistant reports. The text of each is a separate file, stripped
of formatting and ready to select-all and paste:

| | Body to paste | What it asks |
|---|---|---|
| **Report 1** | [feedback/1-blockedapplications.md](feedback/1-blockedapplications.md) | Resolve a contradiction between the docs, an Apple engineer and App Review |
| **Report 2** | [feedback/2-assistive-access.md](feedback/2-assistive-access.md) | Let a person restrict their own device without the supervisor's passcode |

They are separate on purpose: Apple's guidance is **one issue per report** —
"reports that discuss multiple issues aren't actionable and may be returned for
resubmission as separate reports" — and these land on different teams.

**File Report 1 first.** It is not a feature request, which is what makes it
the stronger filing: it is Apple contradicting itself in writing, and it blocks
shipping work today. Report 2 asks for something new.

## This cannot be automated, and should not be

Feedback Assistant is sign-in only and has no public submission API. The
`applefeedback://` URL scheme opens the app but prefills nothing. Anything that
did submit on your behalf would need your Apple Account credentials driven
through a form Apple has not published an interface for — against a developer
account with an app mid-review, which is not a trade worth making to save five
minutes. So the automation here is the boring kind: the text is written, the
formatting is stripped, and the click path is below.

## Filing, step by step

1. **[feedbackassistant.apple.com](https://feedbackassistant.apple.com)** in
   Safari. Sign in with the Apple Account that holds the developer membership,
   so it is filed as a developer rather than a customer.
2. **New feedback**, then pick the starting topic named under each report
   below.
3. **Title** — copy the one line under that report here.
4. **Description** — open the body file, select all, paste.
5. **Attach** the screenshots named under each report. Apple's guidance: "if an
   issue appears in a user interface, make sure to include visuals."
6. **Submit**, then write the FB number into the table at the bottom of this
   file.

The Feedback Assistant *app* collects diagnostics automatically where the
website makes you attach them by hand. That matters for a crash and not for
either of these, so Safari on the iPad is the right tool.

---

## Report 1 — the contradiction

**Starting topic:** Developer Technologies & SDKs
**Area:** ManagedSettings / Screen Time / Family Controls
**Type:** the closest to "Incorrect/Unexpected Behavior". If the form pushes you
to "Suggestion", take it — the body is what matters.

**Title** (copy this line):

```
ManagedSettings blockedApplications is documented as hiding apps and recommended for it by an Apple engineer, but App Review rejects that use under guideline 2.5.1
```

**Body:** [feedback/1-blockedapplications.md](feedback/1-blockedapplications.md)

**Attach:** nothing needed. The evidence is three links, and they are in the
body.

---

## Report 2 — you need permission to make your phone less capable

**Starting topic:** iOS & iPadOS
**Area:** Accessibility
**Type:** Suggestion (enhancement request)

**Title** (copy this line):

```
Assistive Access: entering it requires the Screen Time passcode, so a person under someone else's Screen Time supervision cannot voluntarily restrict their own device further
```

**Body:** [feedback/2-assistive-access.md](feedback/2-assistive-access.md)

**Attach:** a screenshot of the triple-click asking for the passcode. It is the
whole report in one image — the moment a person is refused permission to limit
their own phone.

---

## After filing

**Keep the FB numbers here.** They are the currency: a WWDC lab engineer, a
forum reply and a developer-relations conversation all open with "do you have a
feedback number?", and an aged report with a real use case carries more weight
than a fresh one.

| Report | FB number | Filed | State |
|---|---|---|---|
| 1 — blockedApplications | | | |
| 2 — Assistive Access | | | |

Expect no reply to either. Feedback is a filing cabinet, not a conversation;
the number is what makes the next conversation possible.

## What not to send yet

The featuring nomination in App Store Connect and a WWDC lab both want
something to look at. Both are better spent after a TestFlight build exists —
"here is the app, and here is the one API that would make it work" is a
different conversation from a description of an app that does not run yet.
