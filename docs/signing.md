# Signing: use match, not automatic

Adapted from `docs/DEV_SETUP.md` in `timkempe-eng/hydive`, which reached
TestFlight twice with no Mac involved. This project's first release pipeline
got this wrong; the correction is below.

## The rule

**fastlane `match`. Never Xcode automatic signing in CI.**

Automatic signing tries to resolve the *entire* signing lifecycle — a
development profile as well as a distribution profile — the moment `xcodebuild`
has any valid Apple credentials, regardless of which configuration you're
actually archiving. A from-scratch CI account can't satisfy the development
side (no registered test devices) and can't persist a keychain across ephemeral
runners.

In hydive that produced three consecutive red runs — "No Accounts", "no
registered devices", "certificate with no local private key" — all the same
root cause wearing different hats. `-allowProvisioningUpdates` looks like it
avoids needing a Mac. It does; it just fails a week later instead.

`match` sidesteps the class: one App Store distribution certificate and
profile, created once, encrypted, stored on a branch, reused forever.

## What that means here

- **Storage is a `match` branch of a repo**, not a second private repo. It needs
  `permissions: contents: write`, and `match` clones that branch *outside* the
  checkout tree — so it doesn't inherit the checkout's credentials and has to be
  handed `git_basic_authorization` built from the workflow's own `GITHUB_TOKEN`.
- **Auth is an App Store Connect API key**, never an Apple ID. No 2FA prompt can
  appear in CI. Create it with the **App Manager** role.
- **`ASC_KEY_P8` is base64**, not the raw file. There's no local `base64` on an
  iPad — do it in an agent session. The Fastfile rejects a raw paste up front
  rather than failing opaquely at signing time.
- **`match` does not manage capabilities.** Automatic signing enabled them as a
  side effect; `match` doesn't. Every App ID must carry Family Controls before
  the profile is minted, or the profile won't authorize it and the export fails.
- **`match` judges a profile valid by expiry and certificate, not capability
  set.** It will happily reuse one that predates a capability you just added.
  Run with `force_profiles: true` **only** on the run that changed capabilities;
  steady-state runs stay force-free and reuse everything.
- **Never hardcode a profile name.** If an earlier partial run took the default,
  `match` silently auto-suffixes a timestamp. The Fastfile reads back the name
  from `sigh_<bundle-id>_appstore_profile-name`.
- **`CODE_SIGN_ENTITLEMENTS` stays per target.** A global value forces the app's
  entitlements onto an extension whose profile doesn't authorize them, and the
  export fails. `scripts/apply_signing.py` writes signing per target and leaves
  entitlements alone; preflight checks all four.

## The certificate ceiling

**Apple allows roughly two distribution certificates per account.** A run that
creates one and dies before storing it strands that slot permanently, and two
stranded slots lock you out of distribution entirely.

`.github/workflows/apple-maintenance.yml` lists them and revokes one by id. It
only makes HTTP calls, so it runs on Ubuntu — don't pay for a macOS runner to
call an API.

**The store must be a private repo, and it is not this one.** `match` commits
an encrypted certificate and private key; this repo is public, because that is
what makes the macOS runners free. `MATCH_GIT_URL` is therefore required — it
has no default — and the lane refuses if it names a public repo. Both checks
exist because the earlier default was *this repo*, which would have published
the key on the first release.

**Dad mints its own certificate into its own store.** Sharing another project's
`match` branch would save a slot against the ceiling, and is not worth it: a
`match nuke` or a revoked certificate on either side breaks releases in both,
and the failure gives no hint that the other project caused it. The release
workflow counts distribution certificates before `match` runs and refuses to
proceed if the account is at the ceiling with nothing stored to reuse.

Run **Apple account maintenance** before the first release. It lists the
certificates, and revokes a stranded one by id.

## Build numbers

`CURRENT_PROJECT_VERSION` is set from `GITHUB_RUN_NUMBER` at build time:
monotonic, free, and no `agvtool` dependency. TestFlight rejects a duplicate
build number, so the committed `"1"` would have shipped exactly once.
