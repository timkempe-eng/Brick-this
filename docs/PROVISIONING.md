# Provisioning state

Apple's state — enrolment, app records, keys, capabilities — is invisible from
inside an agent session. This file is where it's written down, so the same
question isn't re-asked every month.

**Rule: every ✅ cites evidence and an exact re-runnable check. If you can't
re-run the check, it isn't ✅.**

| Item | State | Evidence | Re-runnable check |
|---|---|---|---|
| Repo builds the iOS app | ✅ | Actions run #10 and #11 green on `app` job | push, or re-run the Test workflow |
| Core test suite | ✅ | 145 tests, green in CI | `swift test` |
| Xcode wiring consistent | ✅ | 91 checks green | `python3 scripts/preflight.py` |
| Apple Developer Program | ✅ | Active membership already ships `app.hydive.lifeguard` and `app.hydive.member` to TestFlight | developer.apple.com → Membership shows a Team ID |
| App Group + five App IDs registered | ✅ | Account holder created them 2026-09-02 | Certificates, IDs & Profiles → Identifiers lists all five and `group.app.dad.shared` |
| Family Controls (Distribution) | ❓ | — | Certificates, IDs & Profiles → the four App IDs show the capability |
| App Store Connect API key | ✅ | The key hydive releases with. Keys are team-wide, so the same one signs Dad | Users and Access → Integrations lists the key id |
| `ASC_*` / `APPLE_TEAM_ID` secrets | ❓ | Values exist (hydive uses them); secrets are **per repo**, so they still have to be copied into this one | run Release; the Fastfile names any missing one |
| Distribution certs below the cap | ❓ | hydive holds at least one, so there is likely **one slot left** — reuse rather than mint | run Apple account maintenance; expect fewer than 2 |
| `match` branch + certificate | ❓ | hydive's match branch already holds a usable cert; point `MATCH_GIT_URL` there rather than minting a second | `git ls-remote <MATCH_GIT_URL> match` returns a ref |
| App Store Connect record | ❓ | — | Connect → Apps shows `app.dad.Dad` |
| TestFlight build installed | ❓ | — | TestFlight app on the iPhone |
| A tap actually blocks an app | ❓ | — | on-device only; nothing before this proves it |

❓ means unverified, not false.

## What is genuinely new for Dad

This account already ships two apps to TestFlight without a Mac, so most of
the pipeline is not a blocker — it is a copy. Sorted by how long it takes:

1. **Family Controls (Distribution) approval.** The long pole, and the only
   item measured in calendar time. It is a manual Apple review, requested per
   App ID, and nothing about hydive helps: those are Capacitor apps with no
   Screen Time surface. Request it early; everything else can be done while
   waiting.
2. **Five App IDs in the portal**, and the capability enabled on four of them
   once approved. `match` does not manage capabilities.
3. **Reuse the certificate, don't mint one.** hydive's match branch already
   holds a distribution certificate. Apple caps them at about two per account
   and hydive holds at least one, so minting a second spends the last slot for
   nothing. Set `MATCH_GIT_URL` to hydive's repo and `MATCH_GIT_TOKEN` to a PAT
   that can read it — Actions' own `GITHUB_TOKEN` is scoped to this repo and
   cannot.
4. **Copy the five secrets into this repo.** The values exist; repository
   secrets do not cross repositories.
5. **An App Store Connect record** for `app.dad.Dad`. Minutes.

## The four bundle ids

Family Controls (Distribution) must be approved and the capability enabled for
every one, or the profile won't authorize it:

- `app.dad.Dad`
- `app.dad.Dad.ShieldConfiguration`
- `app.dad.Dad.ShieldAction`
- `app.dad.Dad.ActivityMonitor`

`app.dad.Dad.Widget` is a fifth App ID for **signing** — it needs a `match`
profile and an App ID in the portal — but deliberately **not** for Family
Controls. It only reads the session out of the App Group, so it stays off the
approval list. Preflight fails if it ever acquires that entitlement.

## Runbook: getting the first build onto the phone

Every step below is browser work on the iPad. Nothing here needs a Mac, and
nothing here needs a session. Step 1 is the only one measured in days, so do
it first and do the rest while it is pending.

### 1. Register the App IDs and the App Group — before the request

**developer.apple.com** → Certificates, Identifiers & Profiles → Identifiers.
Not App Store Connect: they are separate sites and only one of them knows what
an App ID is. App Store Connect comes later, at step 5, and wants exactly one
of these five.

The entitlement request form asks for bundle ids, and approval is granted per
id, so these have to exist first.

**Register the App Group first.** Identifiers → + → **App Groups** →
`group.app.dad.shared`. The App Groups capability on an App ID is a picker over
groups that already exist, so doing this second means five trips back. All five
targets share it, and a mismatch shows up as the shield displaying the wrong
Mode while the app looks fine.

Then five App IDs (Identifiers → + → **App IDs** → **App**):

- **Explicit, never Wildcard.** A wildcard App ID cannot carry App Groups or
  Family Controls at all, and the radio button is easy to skim past.
- **The bundle id is case-sensitive.** `app.dad.Dad`, capital D — it must match
  `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml` character for character, and
  there is no rename afterwards.
- **Description takes letters, numbers and spaces only.** Apple rejects dots and
  hyphens, so "Dad Shield Configuration", not the bundle id.
- **App Groups is two clicks.** Ticking it is not enough — use Edit/Configure
  beside the row and actually select the group.

| App ID | Capabilities |
|---|---|
| `app.dad.Dad` | Family Controls, App Groups, **NFC Tag Reading** |
| `app.dad.Dad.ShieldConfiguration` | Family Controls, App Groups |
| `app.dad.Dad.ShieldAction` | Family Controls, App Groups |
| `app.dad.Dad.ActivityMonitor` | Family Controls, App Groups |
| `app.dad.Dad.Widget` | App Groups only |

**"Family Controls" is three rows now, and only one of them is ours.** Xcode 26
split the capability, so the Identifiers list shows:

| Row | Entitlement key | Tick it? |
|---|---|---|
| Family Controls (Development) | `com.apple.developer.family-controls` | **Yes** — self-service, works immediately |
| Family Controls (Distribution) | same key | Not a checkbox. Apple's approval flips it; a greyed row is expected |
| Family Controls App and Website Usage | `com.apple.developer.family-controls.app-and-website-usage` | **No** |

The third is a different, newer entitlement: reading which apps and sites were
used, on iOS 26.4+. Dad shields apps and never reads usage, so it fails hard
rule 7 — and on 26.4+ it changes the consent prompt to all-or-nothing. There is
also a live Xcode 26.4 bug where enabling all three produces a profile carrying
`…app-and-website-usage` with the base `com.apple.developer.family-controls`
key *missing*, which would break signing for every target we have.


### 2. Request Family Controls (Distribution) — the long pole

<https://developer.apple.com/contact/request/family-controls-distribution>,
signed in.

Three things that will bounce or delay a request:

- **The Account Holder must submit it.** Not a team member with developer
  access.
- **Each bundle id needs its own approval.** The app and every extension using
  Family Controls are approved separately, so name all four. Not the Widget:
  it carries no family-controls entitlement, which is the point of keeping its
  source set narrow.
- **Budget a month, not a week.** Apple says up to a week; developers commonly
  report 31–33 days. Nothing else in this runbook depends on it, so submit it
  and carry on.

The form's free-text field is where requests get bounced, because Apple is
screening for covert monitoring of other people. Dad is the opposite of that
and the answer should say so plainly:

> Dad is a single-user focus tool. The person installing it is the only person
> it applies to: they choose which of their own apps to hide, and they hide
> them from themselves. There is no second account, no parent or child role, no
> remote administration, and nothing to observe another person with.
>
> The release is triggered by a physical NFC sticker. Getting your apps back
> means walking to the tag and tapping it, which is the entire point — the
> friction is the feature.
>
> Everything stays on the device. There is no server, no account, no network
> call and no analytics. The app never learns which apps were selected: the
> FamilyActivitySelection is held as opaque tokens, persisted through an App
> Group, and passed straight back to ManagedSettings without being decoded.
>
> APIs used: FamilyControls for authorization and selection; ManagedSettings
> to apply and clear the shield; DeviceActivity to start and end scheduled
> sessions. Three extensions need the entitlement alongside the app —
> ShieldConfiguration draws the shield, ShieldAction handles its buttons, and
> ActivityMonitor (DeviceActivityMonitor) applies and lifts the schedule.

Bundle ids to list — four, not five:

```
app.dad.Dad
app.dad.Dad.ShieldConfiguration
app.dad.Dad.ShieldAction
app.dad.Dad.ActivityMonitor
```

The usual advice for the wait is to use the *development* entitlement, which
works immediately, and test on a device from Xcode. **That does not apply to
this project**, and the reason is worth writing down because the obvious
workaround is a dead end too:

| Profile | Family Controls without approval | Installs without a Mac |
|---|---|---|
| Development | yes, the development variant | **no** — OTA install is not supported for development-signed builds |
| Ad-hoc | **no** — profiles come back without the entitlement, development variant included | yes, over the air |
| App Store | no | yes, via TestFlight |

The two halves never meet: the profile that carries the entitlement cannot be
installed without a Mac, and the one that can be installed does not carry it.
So approval gates the app reaching a phone **at all**, not just shipping, and
with it every question a Simulator cannot answer.

What this does leave open: a build carrying **no** Family Controls entitlement
is not gated by any of this, and ad-hoc plus an over-the-air install needs no
Apple review whatsoever — a distribution certificate, the phone's UDID
registered, and the `.ipa` and a `manifest.plist` served over HTTPS, which
public GitHub Release assets are. That is the only route to a real device
before approval, and it costs the three Screen Time extensions, since they
exist for nothing else.

Approval is not the same as *enabled*. Afterwards, go to each App ID's
**Additional Capabilities** tab and switch on Family Controls (Distribution),
then run Release once with `force_profiles: true` — `match` judges a profile
by expiry and certificate, not by capability set, so it will happily reuse one
minted before the capability existed.

### 3. Reuse the existing certificate — do not mint a new one

Apple caps distribution certificates at about two per account and the other
apps already hold at least one. A second app needs no new certificate.

Set the repository **variable** `MATCH_GIT_URL` to the repo whose `match`
branch already holds it, and the **secret** `MATCH_GIT_TOKEN` to a personal
access token with `contents:read` on that repo — Actions' own `GITHUB_TOKEN`
is scoped to this repository and cannot read another one's branch. Set
`MATCH_GIT_BRANCH` too if that branch is not called `match`.

Before the first run, run the **Apple account maintenance** workflow to see
the real certificate count. The `beta` lane also refuses to start if the
account is at the ceiling with no stored branch to reuse.

### 4. Copy the secrets into this repository

The values already exist; repository secrets do not cross repositories.

| Secret | Where it comes from |
|---|---|
| `APPLE_TEAM_ID` | Developer account → Membership, 10 characters |
| `ASC_KEY_ID` | App Store Connect → Users and Access → Integrations |
| `ASC_ISSUER_ID` | Same page, above the key list |
| `ASC_KEY_P8` | **base64** of `AuthKey_XXXX.p8`, not the raw file |
| `MATCH_PASSWORD` | The passphrase the stored certificates use |

`ASC_KEY_P8` must be base64: the lane rejects anything not starting `LS0t`
rather than failing twenty minutes later as an opaque signing error.

### 5. Create the App Store Connect record

**appstoreconnect.apple.com** → My Apps → new app, bundle id `app.dad.Dad`.
Minutes.

Only the app. The four extensions never get their own record — they ship
inside the app bundle. Five App IDs, one app record.

### 6. Run Release to TestFlight

Actions → *Release to TestFlight* → Run workflow. Pick the branch, set
`force_profiles: true` for the first run after enabling capabilities.

**Run it from `claude/dad-phone-focus-device-tbu04b`**, not `main`: the
certificate-reuse support (`MATCH_GIT_TOKEN`) only exists there. `main` would
try to mint a certificate.

### What the first build will and will not show

It answers the question no Simulator can: whether tapping a tag actually
hides an app.

It will also settle the open editor bug above. If Modes cannot be configured
on the device either, that bug is real and blocking. If they configure
normally, it was a Simulator artifact and the two failing UI tests should be
deleted rather than fixed.

## Recurring, and easy to be surprised by

- Distribution certificates expire annually, and profiles with them.
- Apple's minimum SDK moves. The release workflow pins
  `xcode-version: latest-stable` for this reason; an old SDK is a rejection at
  upload, after the build already succeeded.
- API keys expire. When the email lands, the useful question isn't the date —
  it's what actually stands behind that key. Audit before treating it as an
  incident.
