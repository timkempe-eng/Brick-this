# Branches

`main` is the trunk. A session branch is a scratch vehicle: it exists so a
container with no persistent disk has somewhere to push, and it is finished
the moment its work is on `main`. Left alone, they accumulate — six were
sitting on the remote on 2026-09-03, every one already carried by `main` —
and a branch list nobody trusts is a branch list nobody reads, which is how
real unmerged work goes missing.

## What a session can and cannot do

A session's git token creates and updates refs but is refused on deletion:
`git push origin --delete <branch>` returns HTTP 403, measured on 2026-09-03
with a scratch branch that had pushed fine seconds earlier. The GitHub
connector in a session has no branch-deletion tool either. So, as the contract
says: **an operation that needs a machine is a workflow.** Deletion runs in
[`.github/workflows/branches.yml`](../.github/workflows/branches.yml) on a
runner whose `GITHUB_TOKEN` can do it. Auditing needs nothing special and
runs anywhere.

| Step | Where | How |
|---|---|---|
| Audit | any session, or the workflow | `scripts/branches.sh list` |
| Land work | any session | merge to `main`, push |
| Delete merged branches | the workflow | *Branch cleanup* → `delete-merged` |
| Keep unmerged work without its branch | the workflow | *Branch cleanup* → `archive` |
| Change the default branch | Settings → Branches, in a browser | nothing in a session can |

## The audit

```
scripts/branches.sh list
```

classifies every remote branch against `origin/main`:

- **merged** — every commit is an ancestor of `main`. Deleting it loses
  nothing; the commits stay reachable from `main`.
- **patch-merged** — no commit is an ancestor, but `git cherry` finds each
  one's diff already on `main`. This is the same work landed twice under
  different hashes: `agent/tags` was one commit whose two files were
  byte-identical to a commit already on `main`. Also loses nothing.
- **unmerged(N)** — N commits whose changes `main` does not have. The only
  kind that needs a decision: land it, archive it, or delete it on purpose.

The listing also prints each tip's sha and date. Keep the run's output; a
deleted branch can be recreated from its sha until GitHub garbage-collects
the unreachable commits (weeks, typically), and an archived one indefinitely.

## Deleting

From the Actions tab, *Branch cleanup*, mode `delete-merged`. It removes the
merged and patch-merged branches and refuses the unmerged ones, and it never
touches `main`, the repository's default branch, or the branch the run was
dispatched from. Naming branches in the second input narrows it to those,
and fails the run if any of them is unmerged — so a session that wants
exactly one branch gone can say so and be told if it was wrong.

From a session, the same thing is the GitHub connector's *actions run
trigger* on `branches.yml` with `mode: delete-merged` and `ref` set to a
branch that carries the workflow file. Then `scripts/branches.sh list` to
confirm.

A `workflow_dispatch` workflow can only be dispatched once its file is on
the **default branch**; until then the API answers 404 and the Actions tab
has no *Run workflow* button, whatever other branches carry it. Measured on
2026-09-03: dispatching this workflow from the session branch that
introduced it returned 404 while the four workflows on the default branch
listed fine. So a new or changed workflow lands on the default branch
before it can be tried — one more reason the default branch should be
`main`.

Deleting a merged branch under an active session is safe. Its next push
recreates the ref; nothing on the container's disk is affected.

## Archiving

For unmerged work worth keeping but not worth a branch — an experiment
declined in an ADR, a direction abandoned halfway — mode `archive` with the
branch names tags each tip as `archive/<branch>` and then deletes the branch.
Tags are not listed with branches, so the clutter goes away and the commits
stay reachable forever. It refuses to move an existing archive tag. Mode
`delete` with names deletes regardless of state and is for work that should
not survive.

## Default branch

The repository's default branch is still `claude/tim-phone-focus-device-tbu04b`
(PARKING_LOT.md tracks the rename). GitHub refuses to delete the default
branch, and the script marks it `kept`, so it will survive `delete-merged`
until the rename is done in Settings → Branches. After the rename, one more
`delete-merged` run from `main` removes it and the branch this workflow first
shipped on.
