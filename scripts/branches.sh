#!/usr/bin/env bash
# Branch hygiene. `list` runs anywhere, including the agent container. Every
# other mode deletes remote refs, which the container cannot do: its token
# creates and updates refs but is refused with a 403 on any deletion (measured
# 2026-09-03 — a scratch branch pushed fine and could not be removed). So the
# deleting modes run in .github/workflows/branches.yml, on a runner whose
# GITHUB_TOKEN can. docs/branches.md is the process.
#
#   scripts/branches.sh list                     classify every remote branch
#   scripts/branches.sh delete-merged [name…]    delete what main already carries
#   scripts/branches.sh archive name…            tag each tip archive/<name>, then delete
#   scripts/branches.sh delete name…             delete by name, merged or not
#
# Classification, against origin/main:
#   merged        every commit is an ancestor of main
#   patch-merged  no commit is an ancestor, but each one's diff is already on
#                 main (`git cherry`) — the same work landed under another hash
#   unmerged      N commits whose changes main does not have
#
# `delete-merged` takes the first two and never the third. `main`, the remote
# default branch and anything in $BRANCHES_KEEP (space-separated) are never
# touched by any mode; GitHub refuses to delete the default branch anyway.
set -euo pipefail
cd "$(dirname "$0")/.."

mode="${1:-list}"
shift || true
names=("$@")

git fetch --prune --quiet origin '+refs/heads/*:refs/remotes/origin/*'
git remote set-head origin --auto >/dev/null 2>&1 || true
default_branch="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' || true)"

protected=("main")
[ -n "$default_branch" ] && protected+=("$default_branch")
for k in ${BRANCHES_KEEP:-}; do protected+=("$k"); done

is_protected() {
  local b="$1" p
  for p in "${protected[@]}"; do [ "$b" = "$p" ] && return 0; done
  return 1
}

classify() {
  local b="$1" ahead plus
  ahead="$(git rev-list --count "origin/main..origin/$b")"
  if [ "$ahead" = 0 ]; then echo merged; return; fi
  plus="$(git cherry origin/main "origin/$b" | grep -c '^+' || true)"
  if [ "$plus" = 0 ]; then echo patch-merged; else echo "unmerged($plus)"; fi
}

all_branches() {
  git for-each-ref --format='%(refname)' refs/remotes/origin \
    | sed 's#^refs/remotes/origin/##' | grep -vx 'HEAD' | grep -vx 'main'
}

# Exact tip of each branch, before anything moves, so what was deleted can be
# recovered by sha until GitHub garbage-collects the unreachable ones.
report() {
  printf '%-14s %-8s %-10s %-9s %s\n' STATE AHEAD TIP DATE BRANCH
  local b
  for b in $(all_branches); do
    local state; state="$(classify "$b")"
    is_protected "$b" && state="$state,kept"
    printf '%-14s %-8s %-10s %-9s %s\n' "$state" \
      "$(git rev-list --count "origin/main..origin/$b")" \
      "$(git rev-parse --short=10 "origin/$b")" \
      "$(git log -1 --format=%cd --date=short "origin/$b")" "$b"
  done
}

delete_branches() {
  [ "$#" -gt 0 ] || { echo "Nothing to delete."; return; }
  echo "Deleting: $*"
  git push origin --delete "$@"
}

case "$mode" in
  list)
    report
    ;;

  delete-merged)
    report; echo
    targets=()
    if [ "${#names[@]}" -gt 0 ]; then candidates=("${names[@]}"); else read -ra candidates <<< "$(all_branches | tr '\n' ' ')"; fi
    for b in "${candidates[@]}"; do
      if is_protected "$b"; then echo "kept:      $b"; continue; fi
      state="$(classify "$b")"
      case "$state" in
        merged|patch-merged) targets+=("$b") ;;
        *) echo "not merged: $b ($state) — leave it, or use archive/delete by name"; [ "${#names[@]}" -gt 0 ] && exit 1 ;;
      esac
    done
    delete_branches "${targets[@]}"
    ;;

  archive)
    [ "${#names[@]}" -gt 0 ] || { echo "archive needs branch names"; exit 2; }
    for b in "${names[@]}"; do
      is_protected "$b" && { echo "refusing to archive protected branch $b"; exit 1; }
      git rev-parse --verify --quiet "origin/$b" >/dev/null || { echo "no such branch: $b"; exit 1; }
      tag="archive/$b"
      if git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null 2>&1; then
        echo "tag $tag already exists; refusing to move it"; exit 1
      fi
      git tag "$tag" "origin/$b"
      git push origin "refs/tags/$tag"
      echo "archived $b as $tag at $(git rev-parse --short=10 "origin/$b") ($(classify "$b"))"
    done
    delete_branches "${names[@]}"
    ;;

  delete)
    [ "${#names[@]}" -gt 0 ] || { echo "delete needs branch names"; exit 2; }
    for b in "${names[@]}"; do
      is_protected "$b" && { echo "refusing to delete protected branch $b"; exit 1; }
      echo "$b: $(classify "$b") at $(git rev-parse --short=10 "origin/$b")"
    done
    delete_branches "${names[@]}"
    ;;

  *)
    echo "unknown mode: $mode (list | delete-merged | archive | delete)"; exit 2
    ;;
esac
