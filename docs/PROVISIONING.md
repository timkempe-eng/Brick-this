# Provisioning state

Apple's state — enrolment, app records, keys, capabilities — is invisible from
inside an agent session. This file is where it's written down, so the same
question isn't re-asked every month.

**Rule: every ✅ cites evidence and an exact re-runnable check. If you can't
re-run the check, it isn't ✅.**

| Item | State | Evidence | Re-runnable check |
|---|---|---|---|
| Repo builds the iOS app | ✅ | Actions run #10 and #11 green on `app` job | push, or re-run the Test workflow |
| Core test suite | ✅ | 98 tests, green in CI | `swift test` |
| Xcode wiring consistent | ✅ | 59 checks green | `python3 scripts/preflight.py` |
| Apple Developer Program | ❓ | — | developer.apple.com → Membership shows a Team ID |
| Family Controls (Distribution) | ❓ | — | Certificates, IDs & Profiles → the four App IDs show the capability |
| App Store Connect API key | ❓ | — | Users and Access → Integrations lists the key id |
| `ASC_*` / `APPLE_TEAM_ID` secrets | ❓ | — | run Release; the Fastfile names any missing one |
| Distribution certs below the cap | ❓ | — | run Apple account maintenance; expect fewer than 2 |
| `match` branch + certificate | ❓ | — | the `match` branch exists in this repo after the first Release run |
| App Store Connect record | ❓ | — | Connect → Apps shows `app.tim.Tim` |
| TestFlight build installed | ❓ | — | TestFlight app on the iPhone |
| A tap actually blocks an app | ❓ | — | on-device only; nothing before this proves it |

❓ means unverified, not false.

## The four bundle ids

Family Controls (Distribution) must be approved and the capability enabled for
every one, or the profile won't authorize it:

- `app.tim.Tim`
- `app.tim.Tim.ShieldConfiguration`
- `app.tim.Tim.ShieldAction`
- `app.tim.Tim.ActivityMonitor`

## Recurring, and easy to be surprised by

- Distribution certificates expire annually, and profiles with them.
- Apple's minimum SDK moves. The release workflow pins
  `xcode-version: latest-stable` for this reason; an old SDK is a rejection at
  upload, after the build already succeeded.
- API keys expire. When the email lands, the useful question isn't the date —
  it's what actually stands behind that key. Audit before treating it as an
  incident.
