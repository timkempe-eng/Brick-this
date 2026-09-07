#!/usr/bin/env python3
"""Decides what a Release run *means*, so an email always carries news.

The Family Controls (Distribution) approval watch is `release.yml`'s own
schedule. While Apple is still deciding, every firing fails at signing in
under a minute with the same four rejections — and a red run every three
days that means "no news" is a red run nobody reads. Worse, the run that
finally succeeds sends nothing at all, so the one event worth an email is
the silent one.

This inverts that. A scheduled run is quiet only when the log is *exactly*
the known pending state: every error a Family Controls rejection, and all
of the entitled bundle ids still rejected. Anything else — an unrelated
failure, or one identifier approved ahead of the others — is news, fails
the job, and reaches you.

    python3 scripts/classify_signing_failure.py --build-status 65 \\
        --event schedule release.log

Exit 0: nothing to report. Exit 1: read this run. Exit 2: called wrong.

Being quiet about a real failure is the expensive mistake here, so every
uncertain case is loud: a missing log, an empty log, an error naming a
bundle id this repo does not entitle, or a manual dispatch, which has a
person waiting on it.

    python3 scripts/classify_signing_failure.py --self-test
"""
import argparse
import plistlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

ANSI = re.compile(r"\x1b\[[0-9;]*m")
BUNDLE_ID = re.compile(r"app\.dad\.Dad(?:\.[A-Za-z0-9]+)?")
FAMILY_CONTROLS = "com.apple.developer.family-controls"

QUIET, NEWS, MISUSE = 0, 1, 2


def entitled_bundle_ids():
    """The bundle ids whose entitlements ask for Family Controls.

    Read from the project rather than listed here, because a list of four
    identifiers in a fifth place is a list that goes stale. The plist is
    parsed rather than grepped: the widget's entitlements *mention*
    `family-controls` in a comment explaining that it deliberately carries
    none, and a text search reads that as the opposite of what it says.
    """
    import yaml  # only needed here, and only on a runner that has it

    spec = yaml.safe_load((ROOT / "project.yml").read_text())
    ids = set()
    for target in spec["targets"].values():
        settings = target.get("settings", {}).get("base", {})
        bundle_id = settings.get("PRODUCT_BUNDLE_IDENTIFIER")
        entitlements = settings.get("CODE_SIGN_ENTITLEMENTS")
        if not bundle_id or not entitlements:
            continue
        path = ROOT / entitlements
        if not path.exists():
            continue
        with path.open("rb") as handle:
            if FAMILY_CONTROLS in plistlib.load(handle):
                ids.add(bundle_id)
    return ids


def error_lines(log):
    """The compiler's error lines, de-duplicated, in order.

    xcodebuild prints each rejection twice — once as a `::error` annotation
    for the Actions UI and once plainly — so the same failure would
    otherwise be counted twice.
    """
    seen, out = set(), []
    for line in ANSI.sub("", log).splitlines():
        if "error:" not in line:
            continue
        text = line.split("error:", 1)[1].strip()
        if text not in seen:
            seen.add(text)
            out.append(text)
    return out


def is_family_controls_rejection(text):
    """A profile rejected for lacking Family Controls, in either wording.

    Xcode reports the same missing approval two ways and does not always
    print both: on the run this was written against, three targets got the
    entitlement wording *and* the capability wording, while ActivityMonitor
    got only the entitlement one. Requiring both would have called an
    ordinary pending run news.
    """
    if "doesn't include" not in text:
        return False
    return FAMILY_CONTROLS in text or "Family Controls" in text


def classify(log, build_status, event, expected):
    """Returns (exit code, headline, detail lines)."""
    if build_status == 0:
        return QUIET, "The build succeeded.", []

    if event != "schedule":
        return NEWS, f"Release failed (status {build_status}).", [
            "Dispatched by hand, so this is reported whatever the cause."
        ]

    errors = error_lines(log)
    if not errors:
        return NEWS, f"Release failed (status {build_status}) with no error line.", [
            "The failure is outside the build — read the log.",
        ]

    unrelated = [e for e in errors if not is_family_controls_rejection(e)]
    if unrelated:
        return NEWS, "Release failed for something other than the approval.", [
            f"- {e}" for e in unrelated
        ]

    rejected = set()
    for text in errors:
        found = BUNDLE_ID.search(text)
        if found:
            rejected.add(found.group(0))

    unknown = rejected - expected
    if unknown:
        return NEWS, "A bundle id this repo does not entitle was rejected.", [
            f"- {b}" for b in sorted(unknown)
        ]

    approved = expected - rejected
    if approved:
        return NEWS, "Family Controls has been approved — partly.", [
            "Apple grants this per bundle id and can land them days apart.",
            "",
            "Through: " + ", ".join(sorted(approved)),
            "Still waiting: " + ", ".join(sorted(rejected)),
        ]

    return QUIET, "Still waiting on Apple. Nothing has changed.", [
        "All " + str(len(rejected)) + " identifiers still rejected: "
        + ", ".join(sorted(rejected)),
    ]


def main(argv):
    parser = argparse.ArgumentParser(add_help=True)
    parser.add_argument("log", nargs="?", help="the captured fastlane output")
    parser.add_argument("--build-status", type=int, default=0)
    parser.add_argument("--event", default="workflow_dispatch")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args(argv)

    if args.self_test:
        return self_test()

    if args.log is None:
        parser.error("a log path is required unless --self-test")

    path = Path(args.log)
    # A failure that produced no log at all is the shape most likely to be
    # something new, so it must never be the shape that goes quiet.
    log = path.read_text(errors="replace") if path.exists() else ""

    code, headline, detail = classify(
        log, args.build_status, args.event, entitled_bundle_ids()
    )
    print(f"## {headline}\n")
    for line in detail:
        print(line)
    return code


# --- self-test -------------------------------------------------------------
#
# This script's whole job is deciding when *not* to raise the alarm, so the
# thing it can get wrong is silence. Every case below that expects QUIET is
# a case where a wrong answer hides a real failure for three days.
#
# The pending log is the real one: run 34138328138, 2026-09-07, ANSI escapes
# and duplicate annotations included, so the parsing is exercised against
# what a runner actually emits rather than against a tidied copy.

PENDING = """
2026-09-07T15:27:26Z [15:27:26]: \x1b[35m::error file=/Users/runner/work/Brick-this/Brick-this/Dad.xcodeproj::Provisioning profile "match AppStore app.dad.Dad.ShieldConfiguration 1788794340" doesn't include the Family Controls (Development) capability. (in target 'DadShieldConfiguration' from project 'Dad')\x1b[0m
2026-09-07T15:27:26Z [15:27:26]: \x1b[35m/Users/runner/work/Brick-this/Brick-this/Dad.xcodeproj: error: Provisioning profile "match AppStore app.dad.Dad.ActivityMonitor 1788794342" doesn't include the com.apple.developer.family-controls entitlement. (in target 'DadActivityMonitor' from project 'Dad')\x1b[0m
2026-09-07T15:27:26Z [15:27:26]: \x1b[35m/Users/runner/work/Brick-this/Brick-this/Dad.xcodeproj: error: Provisioning profile "match AppStore app.dad.Dad 1788794339" doesn't include the Family Controls (Development) capability. (in target 'Dad' from project 'Dad')\x1b[0m
2026-09-07T15:27:26Z [15:27:26]: \x1b[35m/Users/runner/work/Brick-this/Brick-this/Dad.xcodeproj: error: Provisioning profile "match AppStore app.dad.Dad 1788794339" doesn't include the com.apple.developer.family-controls entitlement. (in target 'Dad' from project 'Dad')\x1b[0m
2026-09-07T15:27:26Z [15:27:26]: \x1b[35m/Users/runner/work/Brick-this/Brick-this/Dad.xcodeproj: error: Provisioning profile "match AppStore app.dad.Dad.ShieldAction 1788794341" doesn't include the com.apple.developer.family-controls entitlement. (in target 'DadShieldAction' from project 'Dad')\x1b[0m
2026-09-07T15:27:26Z [15:27:26]: \x1b[35m/Users/runner/work/Brick-this/Brick-this/Dad.xcodeproj: error: Provisioning profile "match AppStore app.dad.Dad.ShieldConfiguration 1788794340" doesn't include the com.apple.developer.family-controls entitlement. (in target 'DadShieldConfiguration' from project 'Dad')\x1b[0m
2026-09-07T15:27:26Z [15:27:26]: \x1b[31mExit status: 65\x1b[0m
2026-09-07T15:27:27Z ##[error]Process completed with exit code 1.
"""

FOUR = {
    "app.dad.Dad",
    "app.dad.Dad.ShieldConfiguration",
    "app.dad.Dad.ShieldAction",
    "app.dad.Dad.ActivityMonitor",
}

COMPILE_ERROR = (
    "2026-09-07T15:27:26Z /Users/runner/Dad/Core/DadMode.swift:12: "
    "error: cannot find 'Clock' in scope\n"
)

# Names the entitlement but is not a pending-approval rejection. Every guard
# in `is_family_controls_rejection` except the wording check would wave this
# through, and waving it through means three days of silence about a profile
# that has actually gone wrong.
OTHER_FAMILY_CONTROLS_ERROR = (
    "2026-09-07T15:27:26Z /Users/runner/Dad.xcodeproj: error: The entitlement "
    "com.apple.developer.family-controls is disallowed for this profile. "
    "(in target 'Dad' from project 'Dad')\n"
)

# xcodebuild colours whole lines today, so stripping the escapes only shows
# its worth if one lands mid-message: an escape inside a profile name cuts
# the bundle id short, and `app.dad.Dad.ShieldAction` read as `app.dad.Dad`
# is an identifier reported approved that has not been.
PENDING_COLOURED_MIDLINE = PENDING.replace(
    "app.dad.Dad.ShieldAction", "app.dad.Dad\x1b[0m\x1b[35m.ShieldAction"
)


def self_test():
    def without(bundle_id):
        keep = [l for l in PENDING.splitlines() if bundle_id + " " not in l]
        return "\n".join(keep)

    cases = [
        # (name, log, status, event, expected code, a phrase the output must carry)
        ("pending, scheduled, is quiet",
         PENDING, 65, "schedule", QUIET, "Nothing has changed"),
        ("pending, dispatched by hand, is loud",
         PENDING, 65, "workflow_dispatch", NEWS, "Dispatched by hand"),
        ("a green build is quiet",
         "", 0, "schedule", QUIET, "succeeded"),
        ("a green build dispatched by hand is quiet",
         "", 0, "workflow_dispatch", QUIET, "succeeded"),
        ("one identifier approved is news",
         without("app.dad.Dad.ActivityMonitor"), 65, "schedule", NEWS,
         "app.dad.Dad.ActivityMonitor"),
        ("an unrelated error alongside the rejections is news",
         PENDING + COMPILE_ERROR, 65, "schedule", NEWS, "cannot find 'Clock'"),
        ("an unrelated error alone is news",
         COMPILE_ERROR, 65, "schedule", NEWS, "cannot find 'Clock'"),
        ("a failure with no log is news",
         "", 65, "schedule", NEWS, "no error line"),
        ("a rejection naming an unentitled bundle id is news",
         PENDING.replace("app.dad.Dad.ActivityMonitor", "app.dad.Dad.Widget"),
         65, "schedule", NEWS, "does not entitle"),
        ("an entitlement error that is not a rejection is news",
         OTHER_FAMILY_CONTROLS_ERROR, 65, "schedule", NEWS, "disallowed"),
        ("a colour escape inside a bundle id does not fake an approval",
         PENDING_COLOURED_MIDLINE, 65, "schedule", QUIET, "Nothing has changed"),
    ]

    failures = 0
    for name, log, status, event, want_code, want_text in cases:
        code, headline, detail = classify(log, status, event, FOUR)
        printed = "\n".join([headline] + detail)
        if code != want_code:
            print(f"FAIL {name}: exit {code}, wanted {want_code}")
            failures += 1
        elif want_text not in printed:
            print(f"FAIL {name}: {want_text!r} missing from {printed!r}")
            failures += 1
        else:
            print(f"ok   {name}")

    # The set the script derives from the project must be the set the cases
    # above assume. Without this the whole suite could be passing against a
    # shape the real repository no longer has.
    try:
        derived = entitled_bundle_ids()
    except ImportError:
        print("SKIP project.yml check: pyyaml not installed")
    else:
        if derived == FOUR:
            print("ok   project.yml entitles exactly the four expected ids")
        else:
            print(f"FAIL project.yml entitles {sorted(derived)}")
            failures += 1

    print(f"\n{len(cases) + 1} checks, {failures} failed")
    return NEWS if failures else QUIET


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
