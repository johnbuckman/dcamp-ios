#!/usr/bin/env python3
"""Package a notarized Mac app and generate signed GitHub release assets.

Does not upload, publish, mutate the app, or export private keys.
"""
import argparse
import plistlib
import re
import subprocess
from pathlib import Path
from urllib.parse import quote
import xml.etree.ElementTree as ET

from validate_mac_update import validate

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"


def check_feed(feed, info, archive, prefix):
    items = ET.parse(feed).findall("./channel/item")
    if len(items) != 1:
        raise ValueError("Expected exactly one update in the appcast")
    enclosure = items[0].find("enclosure")
    if enclosure is None:
        raise ValueError("Missing update archive in appcast")
    if enclosure.get("url") != prefix + archive.name:
        raise ValueError("Appcast download must point to this exact GitHub release")
    version = items[0].findtext(f"{{{SPARKLE}}}version") or enclosure.get(f"{{{SPARKLE}}}version")
    if version != info["CFBundleVersion"]:
        raise ValueError("Appcast build number does not match the app")
    if not enclosure.get(f"{{{SPARKLE}}}edSignature"):
        raise ValueError("Update archive is not Ed25519 signed (check the signing account)")
    if enclosure.get("length") != str(archive.stat().st_size):
        raise ValueError("Appcast archive size does not match")
    return enclosure.get(f"{{{SPARKLE}}}edSignature")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, type=Path, help="Signed, notarized and stapled dcamp.app")
    parser.add_argument("--tag", required=True, help="Stable GitHub release tag, e.g. v1.26")
    parser.add_argument("--sparkle-bin", required=True, type=Path, help="Sparkle binary artifact's bin directory")
    parser.add_argument("--output", required=True, type=Path, help="New or empty output directory")
    parser.add_argument("--account", default="com.decentespresso.dcamp", help="Sparkle signing account in login Keychain")
    args = parser.parse_args()
    if not re.fullmatch(r"v[0-9]+(?:\.[0-9]+)*", args.tag):
        parser.error("Use a stable version tag, such as v1.26")
    app = args.app.resolve()
    with (app / "Contents/Info.plist").open("rb") as source:
        info = plistlib.load(source)
    validate(info)
    if info.get("CFBundleIdentifier") != "com.decentespresso.dcamp":
        parser.error("Expected the dcamp app")
    if args.tag != "v" + info["CFBundleShortVersionString"]:
        parser.error("Release tag must match CFBundleShortVersionString")
    output = args.output.resolve()
    if output.exists() and any(output.iterdir()):
        parser.error("Output directory must be empty (avoids stale archives or feeds)")
    tools = args.sparkle_bin.resolve()
    for name in ("generate_appcast", "generate_keys", "sign_update"):
        if not (tools / name).is_file():
            parser.error(f"Missing Sparkle tool: {name}")
    # This prints only the PUBLIC key. Never export the release owner's private key.
    public_key = subprocess.check_output([str(tools / "generate_keys"), "--account", args.account, "-p"], text=True).strip()
    if public_key != info["SUPublicEDKey"]:
        parser.error("App's public key does not match the signing account")
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    subprocess.run(["xcrun", "stapler", "validate", str(app)], check=True)
    subprocess.run(["spctl", "--assess", "--type", "execute", "--verbose=2", str(app)], check=True)
    output.mkdir(parents=True, exist_ok=True)
    archive = output / "dcamp-macos-latest.zip"
    subprocess.run(["ditto", "-c", "-k", "--keepParent", str(app), str(archive)], check=True)
    prefix = f"https://github.com/johnbuckman/dcamp-ios/releases/download/{quote(args.tag, safe='')}/"
    feed = output / "appcast.xml"
    subprocess.run([str(tools / "generate_appcast"), "--account", args.account,
                    "--download-url-prefix", prefix, "--maximum-deltas", "0",
                    "--maximum-versions", "1", "-o", str(feed), str(output)], check=True)
    signature = check_feed(feed, info, archive, prefix)
    subprocess.run([str(tools / "sign_update"), "--account", args.account, "--verify", str(feed)], check=True)
    subprocess.run([str(tools / "sign_update"), "--account", args.account, "--verify", str(archive), signature], check=True)
    print(f"Ready: {archive}\nReady: {feed}\nUpload BOTH assets to the stable {args.tag} GitHub release. Do not edit them after signing.")


if __name__ == "__main__":
    main()
