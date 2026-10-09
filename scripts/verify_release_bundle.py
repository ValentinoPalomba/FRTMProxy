#!/usr/bin/env python3
"""Read-only checks for exported FRTMProxy bundles; never sign or notarize."""
import argparse
import base64
import binascii
import plistlib
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import urlsplit


def command(args):
    try:
        return subprocess.run(args, capture_output=True, timeout=120, check=False)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise ValueError(f"Cannot run {args[0]}: {error}") from error


def text(result):
    return (result.stdout + result.stderr).decode("utf-8", errors="replace").strip()


def valid_public_key(value):
    try:
        return isinstance(value, str) and len(base64.b64decode(value, validate=True)) == 32
    except (ValueError, binascii.Error):
        return False


def inspect_bundle(app, expected_public_key=None, require_notarization=False):
    errors, distribution_errors = [], []
    app = app.resolve()
    try:
        with (app / "Contents/Info.plist").open("rb") as source:
            info = plistlib.load(source)
        for key in ("CFBundleIdentifier", "CFBundleExecutable", "CFBundleShortVersionString",
                    "CFBundleVersion", "LSMinimumSystemVersion"):
            value = info.get(key)
            if not isinstance(value, str) or not value.strip() or "$" in value:
                errors.append(f"{key} is missing or contains an unresolved build setting")
        if info.get("CFBundlePackageType") != "APPL":
            errors.append("CFBundlePackageType must be APPL")
        feed = info.get("SUFeedURL", "")
        parsed = urlsplit(feed) if isinstance(feed, str) else urlsplit("")
        if parsed.scheme != "https" or not parsed.hostname or parsed.username or "$" in feed:
            errors.append("SUFeedURL must be a resolved HTTPS URL without embedded credentials")
        public_key = info.get("SUPublicEDKey")
        if not valid_public_key(public_key):
            errors.append("SUPublicEDKey must resolve to a base64-encoded 32-byte Ed25519 public key")
        if expected_public_key is not None and public_key != expected_public_key:
            errors.append("Bundled SUPublicEDKey differs from the selected Sparkle signing account")

        executable = info.get("CFBundleExecutable", "")
        if not isinstance(executable, str) or Path(executable).name != executable:
            errors.append("CFBundleExecutable must be a filename inside Contents/MacOS")
            executable = "__invalid_executable__"
        engine_app = app / "Contents/Resources/mitmproxy.app"
        binaries = [app / "Contents/MacOS" / executable,
                    engine_app / "Contents/MacOS/mitmdump"]
        if not (app / "Contents/Resources/bridge.py").is_file():
            errors.append("Bundled bridge.py is missing")
        for binary in binaries:
            if not binary.is_file():
                errors.append(f"Required executable is missing: {binary.relative_to(app)}")
                continue
            if not binary.stat().st_mode & 0o111:
                errors.append(f"Executable permissions are missing: {binary.relative_to(app)}")
            if app not in binary.resolve().parents:
                errors.append(f"Executable resolves outside the bundle: {binary.relative_to(app)}")
            result = command(["/usr/bin/lipo", "-archs", str(binary)])
            if result.returncode or "arm64" not in result.stdout.decode().split():
                errors.append(f"Executable lacks the required arm64 architecture: {binary.relative_to(app)}")

        result = command(["/usr/bin/codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app)])
        if result.returncode:
            errors.append("Code signature/resource verification failed: " + text(result))

        # Inspect executable bundles, including Sparkle helpers; frameworks need no runtime flag.
        executable_bundles = {app, engine_app}
        executable_bundles.update(path.resolve() for path in app.rglob("*.app"))
        executable_bundles.update(path.resolve() for path in app.rglob("*.xpc"))
        for bundle in sorted(executable_bundles):
            if not bundle.is_dir():
                continue
            with (bundle / "Contents/Info.plist").open("rb") as source:
                bundle_info = plistlib.load(source)
            nested_executable = bundle / "Contents/MacOS" / bundle_info.get("CFBundleExecutable", "")
            # Upstream Python resources include .app templates without an executable.
            # Their bytes are sealed by the enclosing signature; they are not runnable code.
            if bundle not in {app, engine_app} and not nested_executable.is_file():
                continue
            result = command(["/usr/bin/codesign", "-d", "--verbose=4", str(bundle)])
            detail = text(result)
            label = "app" if bundle == app else str(bundle.relative_to(app))
            if result.returncode:
                distribution_errors.append(f"Cannot inspect signing for {label}: {detail}")
                continue
            authorities = re.findall(r"^Authority=(.+)$", detail, flags=re.MULTILINE)
            if not authorities or not authorities[0].startswith("Developer ID Application:"):
                identity = authorities[0] if authorities else "unsigned/ad hoc"
                distribution_errors.append(f"{label}: requires Developer ID Application; found {identity}")
            elif not any("Developer ID Certification Authority" in item for item in authorities[1:]):
                distribution_errors.append(f"{label}: Developer ID certificate authority chain is missing")
            flags = re.search(r"flags=0x([0-9a-fA-F]+)", detail)
            if not flags or not int(flags.group(1), 16) & 0x10000:
                distribution_errors.append(f"{label}: hardened runtime is not enabled")
            if not re.search(r"^Timestamp=.+$", detail, flags=re.MULTILINE):
                distribution_errors.append(f"{label}: secure signing timestamp is missing")
            result = command(["/usr/bin/codesign", "-d", "--entitlements", ":-", str(bundle)])
            if result.returncode:
                errors.append(f"Cannot inspect entitlements for {label}: {text(result)}")
            elif result.stdout.strip():
                try:
                    entitlements = plistlib.loads(result.stdout)
                except (ValueError, plistlib.InvalidFileException) as error:
                    errors.append(f"Unreadable entitlements for {label}: {error}")
                else:
                    if entitlements.get("com.apple.security.get-task-allow"):
                        distribution_errors.append(f"{label}: get-task-allow is enabled")

        if require_notarization:
            for args, label in [
                (["/usr/sbin/spctl", "--assess", "--type", "execute", "--verbose=4", str(app)], "Gatekeeper"),
                (["/usr/bin/xcrun", "stapler", "validate", str(app)], "Stapled notarization ticket"),
            ]:
                result = command(args)
                if result.returncode:
                    distribution_errors.append(f"{label} validation failed: {text(result)}")
    except (OSError, ValueError, TypeError, plistlib.InvalidFileException) as error:
        errors.append(f"Cannot validate bundle: {error}")
    return errors, distribution_errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--expected-public-key")
    parser.add_argument("--require-notarization", action="store_true")
    parser.add_argument("--diagnostic-local", action="store_true",
                        help="Allow development signatures for a local diagnostic archive, never an appcast")
    args = parser.parse_args()
    if args.diagnostic_local and args.require_notarization:
        parser.error("--diagnostic-local cannot be combined with --require-notarization")
    errors, distribution_errors = inspect_bundle(args.app, args.expected_public_key, args.require_notarization)
    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)
    for error in distribution_errors:
        print(f"{'DIAGNOSTIC ONLY' if args.diagnostic_local else 'ERROR'}: {error}", file=sys.stderr)
    if errors or (distribution_errors and not args.diagnostic_local):
        print("Bundle is NOT approved for distribution.", file=sys.stderr)
        return 1
    if args.diagnostic_local:
        print("Local diagnostic bundle verified; NOT approved for distribution or an appcast.")
    else:
        print("Distribution bundle checks passed" + (" (including notarization)." if args.require_notarization else "; notarization not checked."))
    return 0


if __name__ == "__main__":
    sys.exit(main())
