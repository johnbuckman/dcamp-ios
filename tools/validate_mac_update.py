#!/usr/bin/env python3
"""Fail a Mac Release build before shipping an unconfigured updater."""
import base64
import binascii
import plistlib
import sys

FEED_URL = "https://github.com/johnbuckman/dcamp-ios/releases/latest/download/appcast.xml"


def validate(info):
    try:
        key = base64.b64decode(info.get("SUPublicEDKey", ""), validate=True)
    except (ValueError, binascii.Error):
        key = b""
    if len(key) != 32:
        raise ValueError("Set DCAMP_SPARKLE_PUBLIC_KEY to the release owner's Ed25519 public key. See MAC_UPDATES.md.")
    expected = {
        "SUFeedURL": FEED_URL,
        "SUScheduledCheckInterval": 86400,
        "SUEnableAutomaticChecks": True,
        "SUVerifyUpdateBeforeExtraction": True,
        "SURequireSignedFeed": True,
        "SUShowReleaseNotes": False,
    }
    for name, value in expected.items():
        if info.get(name) != value:
            raise ValueError(f"Invalid Mac updater setting: {name}")


if __name__ == "__main__":
    try:
        with open(sys.argv[1], "rb") as source:
            validate(plistlib.load(source))
    except (OSError, ValueError) as error:
        sys.exit(f"error: {error}")
