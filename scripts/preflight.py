#!/usr/bin/env python3
"""Checks the Xcode project wiring before you ever open Xcode.

Every failure here is one that does *not* announce itself on a device: a
mismatched App Group makes the shield show the wrong Mode name while the app
works perfectly; a principal class typo makes an extension silently never
launch. They cost an afternoon each to find by hand, and all of them are
checkable without a Mac.

    python3 scripts/preflight.py
"""
import plistlib
import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    print("needs pyyaml: pip install pyyaml")
    sys.exit(2)

ROOT = Path(__file__).resolve().parent.parent
problems, checks = [], 0


def check(ok, message):
    global checks
    checks += 1
    if not ok:
        problems.append(message)


spec = yaml.safe_load((ROOT / "project.yml").read_text())
targets = spec["targets"]

# --- App Group must match everywhere, including the string the code uses.
store_src = (ROOT / "Tim/Shared/Adapters/UserDefaultsStore.swift").read_text()
m = re.search(r'appGroupID\s*=\s*"([^"]+)"', store_src)
check(m is not None, "UserDefaultsStore has no appGroupID literal")
group = m.group(1) if m else None

for name, target in targets.items():
    ent_path = target["settings"]["base"].get("CODE_SIGN_ENTITLEMENTS")
    check(ent_path is not None, f"{name}: no CODE_SIGN_ENTITLEMENTS")
    if not ent_path:
        continue
    ent = plistlib.loads((ROOT / ent_path).read_bytes())
    groups = ent.get("com.apple.security.application-groups", [])
    check(group in groups,
          f"{name}: entitlements list {groups}, but the code uses '{group}' "
          f"— the shield would silently disagree with the app")
    check(ent.get("com.apple.developer.family-controls") is True,
          f"{name}: missing the family-controls entitlement")

# --- Extension bundle IDs must nest under the app's, or they won't install.
app_id = targets["Tim"]["settings"]["base"]["PRODUCT_BUNDLE_IDENTIFIER"]
for name, target in targets.items():
    if name == "Tim":
        continue
    bid = target["settings"]["base"]["PRODUCT_BUNDLE_IDENTIFIER"]
    check(bid.startswith(app_id + "."),
          f"{name}: bundle id '{bid}' must nest under the app's '{app_id}'")

# --- An extension's principal class must actually exist, spelled that way.
for name, target in targets.items():
    info_path = target["settings"]["base"].get("INFOPLIST_FILE")
    if not info_path:
        continue
    info = plistlib.loads((ROOT / info_path).read_bytes())
    ext = info.get("NSExtension")
    if not ext:
        continue
    principal = ext["NSExtensionPrincipalClass"].split(".")[-1]
    sources = [ROOT / s if isinstance(s, str) else ROOT / s["path"]
               for s in target["sources"]]
    found = any(
        re.search(rf"class\s+{re.escape(principal)}\b", f.read_text())
        for d in sources if d.is_dir()
        for f in d.rglob("*.swift")
    )
    check(found, f"{name}: principal class '{principal}' is not defined in its sources "
                 f"— the extension would never launch")
    check(ext.get("NSExtensionPointIdentifier", "").startswith("com.apple."),
          f"{name}: suspicious NSExtensionPointIdentifier")

# --- Every target compiles the whole shared tree, so each needs the frameworks
#     the adapters import.
adapter_imports = set()
for f in (ROOT / "Tim/Shared/Adapters").glob("*.swift"):
    adapter_imports |= set(re.findall(r"^import (\w+)", f.read_text(), re.M))
adapter_imports -= {"Foundation", "SwiftUI"}

for name, target in targets.items():
    linked = {d["sdk"].replace(".framework", "")
              for d in target.get("dependencies", []) if "sdk" in d}
    missing = adapter_imports - linked
    check(not missing,
          f"{name}: compiles the adapters but does not link {sorted(missing)}")

# --- Core must never reach for an iOS framework, or `swift test` stops working.
for f in (ROOT / "Tim/Shared/Core").glob("*.swift"):
    bad = set(re.findall(r"^import (\w+)", f.read_text(), re.M)) - {"Foundation"}
    check(not bad, f"Core/{f.name} imports {sorted(bad)} — Core must stay Foundation-only")

# --- The standard bundle keys. Xcode's own template supplies these; a
#     hand-written Info.plist that omits CFBundleName still builds, but the
#     App Intents Siri-training step then fails with "Unable to parse
#     Info.plist" — naming neither the key nor the file.
REQUIRED_BUNDLE_KEYS = [
    "CFBundleDevelopmentRegion", "CFBundleExecutable", "CFBundleIdentifier",
    "CFBundleInfoDictionaryVersion", "CFBundleName", "CFBundlePackageType",
]
for name, target in targets.items():
    info_path = target["settings"]["base"].get("INFOPLIST_FILE")
    if not info_path:
        continue
    info = plistlib.loads((ROOT / info_path).read_bytes())
    missing = [k for k in REQUIRED_BUNDLE_KEYS if k not in info]
    check(not missing, f"{name}: Info.plist is missing {missing}")

# --- NFC needs both the entitlement and the usage string.
app_ent = plistlib.loads((ROOT / targets["Tim"]["settings"]["base"]["CODE_SIGN_ENTITLEMENTS"]).read_bytes())
app_info = plistlib.loads((ROOT / targets["Tim"]["settings"]["base"]["INFOPLIST_FILE"]).read_bytes())
check("com.apple.developer.nfc.readersession.formats" in app_ent,
      "app: missing the NFC reader-session entitlement")
check("NFCReaderUsageDescription" in app_info,
      "app: missing NFCReaderUsageDescription — the scan sheet would crash")

print(f"preflight: {checks} checks")
if problems:
    print("\nFAILED:")
    for p in problems:
        print(f"  - {p}")
    sys.exit(1)
print("all good — the wiring Xcode won't warn you about is consistent")
