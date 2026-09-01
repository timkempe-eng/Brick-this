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


def source_paths(target):
    """The target's own compiled source paths, resources excluded."""
    out = []
    for entry in target.get("sources", []):
        if isinstance(entry, str):
            out.append(entry)
        elif entry.get("buildPhase") != "resources" and entry.get("path"):
            out.append(entry["path"])
    return out


def source_dirs(target):
    return [ROOT / p for p in source_paths(target) if (ROOT / p).is_dir()]


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
    # Symmetrical, and it encodes rule 7: a target that links FamilyControls
    # needs the entitlement, and a target that doesn't must not carry it —
    # every extra copy is another bundle id needing Apple's manual approval.
    links_family_controls = any(
        d.get("sdk") == "FamilyControls.framework"
        for d in target.get("dependencies", []) if "sdk" in d
    )
    has_entitlement = ent.get("com.apple.developer.family-controls") is True
    check(has_entitlement == links_family_controls,
          f"{name}: links FamilyControls={links_family_controls} but "
          f"declares the entitlement={has_entitlement} — these must agree")

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
    if "NSExtensionPrincipalClass" not in ext:
        # A WidgetKit extension has no principal class; it is entered through
        # @main on a WidgetBundle. Check that instead, since a bundle with no
        # entry point builds fine and then simply never appears in the gallery.
        check(ext.get("NSExtensionPointIdentifier") == "com.apple.widgetkit-extension",
              f"{name}: extension declares no NSExtensionPrincipalClass")
        has_main = any(
            "@main" in f.read_text() and "WidgetBundle" in f.read_text()
            for d in source_dirs(target) for f in d.rglob("*.swift")
        )
        check(has_main, f"{name}: no @main WidgetBundle — the widget would never appear")
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

# --- A target must link the frameworks that the adapters IT COMPILES import.
#
#     Not every target takes the whole shared tree: the widget deliberately
#     compiles Core plus one adapter, so that it never pulls in FamilyControls
#     and never needs an entitlement it has no use for. So the check resolves
#     each target's own source paths rather than assuming.
def compiles(target, file_path):
    rel = str(file_path.relative_to(ROOT))
    for path in source_paths(target):
        if rel == path or rel.startswith(path.rstrip("/") + "/"):
            return True
    return False


adapters = sorted((ROOT / "Tim/Shared/Adapters").glob("*.swift"))

for name, target in targets.items():
    needed = set()
    compiled_any = False
    for adapter in adapters:
        if not compiles(target, adapter):
            continue
        compiled_any = True
        needed |= set(re.findall(r"^import (\w+)", adapter.read_text(), re.M))
    needed -= {"Foundation", "SwiftUI"}

    linked = {d["sdk"].replace(".framework", "")
              for d in target.get("dependencies", []) if "sdk" in d}
    missing = needed - linked
    check(not missing,
          f"{name}: compiles adapters importing {sorted(missing)} but does not link them")
    check(compiled_any or not source_paths(target),
          f"{name}: compiles no adapter at all — is its source list right?")

# --- The widget reads; it must never acquire Screen Time powers. An
#     entitlement it doesn't use is a fifth bundle id needing Apple's manual
#     Family Controls approval, which is already the long pole.
widget = targets.get("TimWidget")
if widget:
    ent = plistlib.loads((ROOT / widget["settings"]["base"]["CODE_SIGN_ENTITLEMENTS"]).read_bytes())
    check("com.apple.developer.family-controls" not in ent,
          "TimWidget declares family-controls; it only reads the session")
    check(not any(compiles(widget, a) and "FamilyControls" in a.read_text()
                  for a in adapters),
          "TimWidget compiles a FamilyControls adapter; keep its sources narrow")

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

# --- Entitlements must not name placeholder infrastructure. An entitlement
#     you don't ship a feature for is a capability the App ID has to carry, a
#     review surface, and one more thing that can break signing.
for name, target in targets.items():
    ent_path = target["settings"]["base"].get("CODE_SIGN_ENTITLEMENTS")
    if not ent_path:
        continue
    raw = (ROOT / ent_path).read_text()
    for placeholder in ("example.com", "TEAMID", "CHANGEME"):
        check(placeholder not in raw,
              f"{name}: entitlements still reference the placeholder '{placeholder}'")

# --- Declare export compliance in the build, or answer the question on every
#     single upload, forever.
check(app_info.get("ITSAppUsesNonExemptEncryption") is not None,
      "app: Info.plist doesn't declare ITSAppUsesNonExemptEncryption")

# --- Signing must never be automatic. Xcode's automatic signing resolves the
#     whole lifecycle — development profile included — the moment it has valid
#     credentials, which a from-scratch CI account cannot satisfy.
release = (ROOT / ".github/workflows/release.yml")
if release.exists():
    text = release.read_text()
    check("-allowProvisioningUpdates" not in text,
          "release.yml uses -allowProvisioningUpdates; use fastlane match (docs/signing.md)")
    check("signingStyle: automatic" not in text and '"automatic"' not in text,
          "release.yml requests automatic signing; match requires manual")

# --- Every target's bundle id must be in the Fastfile's signing list. A target
#     match never mints a profile for fails at export — after the build has
#     already succeeded.
fastfile = ROOT / "fastlane/Fastfile"
if fastfile.exists():
    signed = set(re.findall(r'"(app\.tim\.[\w.]+)"', fastfile.read_text()))
    for name, target in targets.items():
        bid = target["settings"]["base"]["PRODUCT_BUNDLE_IDENTIFIER"]
        check(bid in signed,
              f"{name}: '{bid}' is not in the Fastfile's signing list")

print(f"preflight: {checks} checks")
if problems:
    print("\nFAILED:")
    for p in problems:
        print(f"  - {p}")
    sys.exit(1)
print("all good — the wiring Xcode won't warn you about is consistent")
