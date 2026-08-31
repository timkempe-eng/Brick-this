#!/usr/bin/env python3
"""Inject manual code signing into project.yml before XcodeGen runs.

Called by the Fastfile with the team id and the profile names match actually
produced — never hardcoded names, because match auto-suffixes a timestamp when
the default is already taken by an earlier partial run.

    apply_signing.py TEAMID app.tim.Tim "Tim AppStore" app.tim.Tim.ShieldAction "..."

Sets signing per target. CODE_SIGN_ENTITLEMENTS is deliberately left alone: it
is already per-target in the spec, and a global value forces the app's
entitlements onto an extension whose profile doesn't authorize them.
"""
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent


def main(argv):
    if len(argv) < 4 or len(argv) % 2 != 0:
        sys.exit("usage: apply_signing.py TEAM_ID (BUNDLE_ID PROFILE_NAME)...")

    team_id = argv[1]
    profiles = dict(zip(argv[2::2], argv[3::2]))

    spec_path = ROOT / "project.yml"
    spec = yaml.safe_load(spec_path.read_text())

    spec.setdefault("settings", {}).setdefault("base", {})["DEVELOPMENT_TEAM"] = team_id

    unmatched = []
    for name, target in spec["targets"].items():
        base = target.setdefault("settings", {}).setdefault("base", {})
        bundle_id = base.get("PRODUCT_BUNDLE_IDENTIFIER")
        profile = profiles.get(bundle_id)
        if profile is None:
            unmatched.append(f"{name} ({bundle_id})")
            continue
        base["CODE_SIGN_STYLE"] = "Manual"
        base["CODE_SIGN_IDENTITY"] = "Apple Distribution"
        base["PROVISIONING_PROFILE_SPECIFIER"] = profile
        base["DEVELOPMENT_TEAM"] = team_id

    if unmatched:
        sys.exit("No profile supplied for: " + ", ".join(unmatched))

    # CI build numbers must be monotonic or TestFlight rejects the upload as a
    # duplicate. The Actions run number is monotonic and free.
    import os
    run_number = os.environ.get("GITHUB_RUN_NUMBER")
    if run_number:
        spec["settings"]["base"]["CURRENT_PROJECT_VERSION"] = run_number

    spec_path.write_text(yaml.safe_dump(spec, sort_keys=False))
    print(f"signing: manual, team {team_id}, {len(profiles)} profiles, build {run_number or 'unchanged'}")


if __name__ == "__main__":
    main(sys.argv)
