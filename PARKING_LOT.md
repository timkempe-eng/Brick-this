# Parking lot

**Open work only.** A closed item is *removed*, not struck through — the commit
that closed it is the record, and a file that keeps its own history stops being
a list of what to do next. Swept every time something is built.

It ran to 914 lines before this rule, of which about 800 described work already
finished. Nobody reads a backlog that long, which means nobody notices when it
is wrong.

Where the rest went:

- **What is built and what isn't** — [docs/roadmap.md](docs/roadmap.md),
  including the honest limitations.
- **What was decided and why** — the ADRs in [docs/adr/](docs/adr/), each with
  the trigger that would reopen it, plus
  [ADR 007](docs/adr/007-what-the-research-says-not-to-build.md) for the things
  the market ships that this product will not. Counted here once and went stale
  the next time one was written, so it no longer carries a number.
- **What the work taught** — `CLAUDE.md`, under Testing posture. Every lesson
  that has cost this repo more than once is written down there.
- **Apple's state** — [docs/PROVISIONING.md](docs/PROVISIONING.md), where every
  ✅ cites evidence and a re-runnable check.
- **Everything else** — `git log`. The commit messages carry the reasoning.

---

## Blocked on Apple, or on a phone

Nothing here is code. The whole ranked feature backlog is finished; what is
left is calendar time, a browser and a phone.

- [ ] **First TestFlight build on the iPhone.** Build 1.0 (25) reached
      internal testers on 2026-10-12 (run 38284229412). What is left is the
      phone: install it from TestFlight and tap a tag.

      **On the device, write a tag as well as tapping one.** Writing uses
      `NFCNDEFReaderSession`, and the NFC entitlement lost its `NDEF` value on
      2026-10-12 because upload validation now rejects it. Current guidance
      is that `TAG` covers NDEF sessions too; nothing here has run it.

      **Replace the placeholder app icon.** It is the accent colour and the
      word "Dad", made only so upload validation would accept the build.

- [ ] **Prove child authorization on a real device.** The code is built and
      shipped: `requestAuthorization(for: .child)` when the role is a young
      person, with its own failure message, because a household not on Family
      Sharing gets an error that would otherwise read as "declined" and send
      somebody to the wrong Settings page.

      What cannot be proven from here is that it *works* — it needs a device
      signed into a child's iCloud account inside an iCloud Family, and not
      MDM-enrolled. Until then the family layer is an arrangement between two
      people who both want it to hold, rather than one that holds when a
      teenager would rather it didn't. That distinction is the difference
      between the product and a co-operative version of it.

- [ ] **See Dad on a phone in Assistive Access.** The scene and its copy are
      built and covered by `swift test`; two things about them can only be
      settled on a device that is actually running the mode, with Dad among the
      apps a trusted supporter chose.

      **That the streamlined scene is what appears** — that iOS picks the
      `AssistiveAccess` scene over `WindowGroup`, and that the app is listed as
      *Optimized for Assistive Access* in Settings. Needs iOS 26; below that the
      scene type does not exist and the standard UI renders in the reduced
      frame instead, which is the behaviour to expect on an older phone.

      **That the shields still hold inside the mode.** Apple's settings guide
      says Screen Time schedules and limits can be set while Assistive Access is
      active, which is good evidence and is not the same as watching a shielded
      app refuse to open. If it turns out they do not, the screen is still
      honest — it reports the stored session, which is what the shield is
      reconciled against — but the product would have a hole in it worth
      saying out loud.

      [ADR 008](docs/adr/008-assistive-access.md) has the API surface and why
      the tap cannot switch the mode itself.

- [ ] **Does a Shortcuts NFC automation fire while Assistive Access is on?**
      If it does, the tag keeps working inside the mode and the release is one
      tap. If it does not, the release is triple-click-then-tap, which is what
      every piece of copy already says — chosen because it is the one order
      that works under both answers.

      The other half of this question is answered and gone: entry is
      passcode-gated, measured 2026-09-17.

- [ ] **Find out whether `blockedApplications` would let Dad hide rather than
      shield — and whether shipping that survives review.** Found while writing
      [docs/apple-feedback.md](docs/apple-feedback.md), and it matters more than
      Assistive Access does: shielding covers an app when you open it, while the
      icon, the badge and the folder stay exactly where they were. Hiding is
      what somebody means when they say they want their phone to stop pulling
      at them.

      `ManagedSettings.ApplicationSettings.blockedApplications` is documented
      as "the system hides blocked applications and prevents the user from
      launching them", and an Apple Frameworks Engineer posted sample code for
      it under `.individual` authorization in Developer Forums thread 716519.
      `FamilyActivitySelection.applications` already yields the
      `Set<Application>` it wants, so on paper the selection Dad already has
      would drop straight in.

      **The catch is review, not code.** Developer Forums thread 776058 has an
      app rejected under guideline 2.5.1 — "your app uses ScreenTime API to
      hide apps" — after its Family Controls entitlement had already been
      approved, with the appeal quoting this documentation verbatim and getting
      the same rejection back. One report is not policy, but this repo has no
      build through App Review yet and cannot afford to complicate the first
      one, so the order is: get the first build onto TestFlight, file
      Report 1 in `docs/apple-feedback.md`, and only then try it.

## Deliberately deferred

- [ ] **Remote granting.** `GrantRequest` defines a `PINHashing` port and
      nothing conforms to it, on purpose. The first shape of granting is
      in-person: the grown-up already holds the tag, and a tag needs no
      account, no server and no cryptography anybody here has to get right. A
      PIN is what that becomes when they are not in the room.

      The trigger to build it is somebody actually wanting to grant from
      elsewhere. The fork below says what it costs.

## The architectural fork, when remote grant arrives

Two roles need shared state, and Dad has almost none — no accounts, no network,
no step of a tap that touches the internet. That property is a genuine
advantage over Brick, which every comparison notes "doesn't work without an
internet connection". **Do not spend it casually.**

The household streak spends the smallest possible amount of it: the tag itself
carries the shared ledger, so the feature costs no account and works on a
plane. That is the pattern to reach for first.

**Then CloudKit, only when remote grant proves necessary** — iCloud Family
Sharing is already a prerequisite of child authorization, so CloudKit is the
Apple-native answer and still needs no server of ours. Both beat inventing a
backend.
