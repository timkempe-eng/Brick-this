# ADR 003 — The code repo stays public; the certificates get their own private one

**Status:** accepted, 2026-09-02

## Context

`fastlane match` stores an encrypted distribution certificate and private key
in a git repo. The obvious place is this one, and that was the original wiring:
`MATCH_GIT_URL` defaulted to `GITHUB_REPOSITORY`.

This repo is public. So the first Release run would have committed the team's
signing key somewhere anyone could fetch it, with `MATCH_PASSWORD` the only
thing standing between a passer-by and the ability to sign as this team. That
is a bad default even if nobody is looking, because the failure is silent and
permanent — you cannot un-publish a key, only revoke it.

Noticing that raised the obvious question: make the repo private instead?

## Decision

**No. The repo stays public, and `match` gets its own private repo.**

Public is not incidental here — it is what pays for the build. GitHub's macOS
runners are free for public repositories and bill at a **10× multiplier** for
private ones. A Free account includes 2,000 minutes a month, Pro 3,000, so a
private repo gets roughly 200–300 macOS minutes.

This project ran **65 CI runs in its first two days**, each dominated by a
7–16 minute macOS job. Call it eight macOS minutes a run and that is ~520
minutes — over 5,000 billable. **Two days would have spent more than a month's
allowance.** There is no Mac here, so those runners are not a convenience;
they are the only machine that can compile the app at all. Making the repo
private does not tighten the budget, it ends the project.

Splitting the two is also just correct. Different things want different
visibility:

| | Wants | Why |
|---|---|---|
| Source, workflows, docs | public | free macOS runners, and nothing here is secret |
| `match` store | private | it is a signing key |
| Everything else Apple | Actions secrets | encrypted, never printed, invisible in a public repo |

## Consequences

- `MATCH_GIT_URL` is **required** and has no default. The `beta` lane calls the
  GitHub API and refuses outright if it names a public repo. A comment saying
  "use a private repo" would not have caught this; a check does.
- Dad mints its own certificate into its own store rather than sharing another
  project's. Sharing saves a slot against Apple's ceiling and costs isolation:
  one `match nuke` or one revoked certificate breaks releases in both projects,
  and the failure names neither.
- **Nothing secret may ever be committed here.** Not a `.p8`, not a
  `.mobileprovision`, not a `.p12`.
- The two workflows that hold secrets — Release and Apple account maintenance —
  are `workflow_dispatch` only. `test.yml` runs on `pull_request` and builds
  with `CODE_SIGNING_ALLOWED=NO`, so a fork's pull request gets no secrets. If
  a secret-bearing job is ever added, this is the property to preserve.
