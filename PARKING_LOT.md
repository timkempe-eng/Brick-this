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
- **What was decided and why** — the ADRs in [docs/adr/](docs/adr/). Six
  declines with the triggers that would reopen them, plus
  [ADR 007](docs/adr/007-what-the-research-says-not-to-build.md) for the things
  the market ships that this product will not.
- **What the work taught** — `CLAUDE.md`, under Testing posture. Every lesson
  that has cost this repo more than once is written down there.
- **Apple's state** — [docs/PROVISIONING.md](docs/PROVISIONING.md), where every
  ✅ cites evidence and a re-runnable check.
- **Everything else** — `git log`. The commit messages carry the reasoning.

---

## Blocked on Apple, or on a phone

Nothing here is code. The whole ranked feature backlog is finished; what is
left is calendar time and a browser.

- [ ] **Family Controls (Distribution) approved.** Requested 2026-09-02. A
      manual Apple review, and the one real long pole — nothing in the existing
      account helps, since the other two apps have no Screen Time surface.
      Apple sends no acknowledgement, so a Release run is the only signal; a
      Routine runs one every three days and reports.

- [ ] **App Store Connect record for `app.dad.Dad`.** Minutes in a browser, and
      confirmed missing as of 2026-09-03 by the capabilities lane. Registering
      the App ID on developer.apple.com is a **different site and a different
      action** — the two are easy to conflate, and only this one makes
      TestFlight possible. Nothing in the pipeline notices it is absent until
      `upload_to_testflight` fails at the very end of a signed build.

- [ ] **First TestFlight build on the iPhone.** Runbook in
      [docs/PROVISIONING.md](docs/PROVISIONING.md) — browser steps from an iPad,
      none needing a Mac. Everything that can be done from a session is done:
      the certificate is minted and stored, five profiles exist, the App Group
      is assigned, and the Family Controls capability is enabled on the four
      identifiers that need it.

      **Run Release once with `force_profiles: true`.** `match` matches
      profiles on expiry and certificate rather than on capability set, so it
      will reuse one minted before the capability was enabled — and that fails
      at export, after the build has already succeeded.

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

## Repository settings

- [ ] **Rename the default branch to `main`.** Settings → Branches. `main`
      carries everything and CI is green on its head; the default is still
      `claude/tim-phone-focus-device-tbu04b`. Nothing in a session can flip it —
      it is a repository setting, not a git operation. Delete the session
      branches afterwards.

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
