import base64
import copy
import plistlib
import sys
import tempfile
import unittest
from pathlib import Path
import xml.etree.ElementTree as ET

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from prepare_mac_update import check_feed, SPARKLE
from validate_mac_update import validate


class ReleaseToolTests(unittest.TestCase):
    def setUp(self):
        with (Path(__file__).resolve().parents[1] / "Resources/Info.plist").open("rb") as source:
            self.info = plistlib.load(source)
        self.info["SUPublicEDKey"] = base64.b64encode(bytes(range(32))).decode()

    def test_release_configuration_and_missing_or_invalid_key(self):
        validate(self.info)
        for key in ("", "$(DCAMP_SPARKLE_PUBLIC_KEY)", "!!!", base64.b64encode(b"short").decode()):
            with self.subTest(key=key), self.assertRaises(ValueError):
                validate(dict(self.info, SUPublicEDKey=key))

    def test_release_security_settings_cannot_be_disabled(self):
        for key, value in (
            ("SUFeedURL", "https://example.com/appcast.xml"),
            ("SURequireSignedFeed", False),
            ("SUVerifyUpdateBeforeExtraction", False),
            ("SUScheduledCheckInterval", 3600),
            ("SUEnableAutomaticChecks", False),
            ("SUShowReleaseNotes", True),
        ):
            with self.subTest(key=key), self.assertRaises(ValueError):
                validate(dict(self.info, **{key: value}))

    def test_feed_pins_archive_build_signature_and_size(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / "dcamp-macos-latest.zip"
            archive.write_bytes(b"fixture")
            prefix = "https://github.com/johnbuckman/dcamp-ios/releases/download/v1.26/"
            root = ET.Element("rss")
            item = ET.SubElement(ET.SubElement(root, "channel"), "item")
            ET.SubElement(item, f"{{{SPARKLE}}}version").text = "27"
            enclosure = ET.SubElement(item, "enclosure", {
                "url": prefix + archive.name, "length": "7", f"{{{SPARKLE}}}edSignature": "fixture-signature"
            })
            feed = Path(directory) / "appcast.xml"
            info = {"CFBundleVersion": "27"}
            ET.ElementTree(root).write(feed)
            self.assertEqual(check_feed(feed, info, archive, prefix), "fixture-signature")
            for key, value in (
                ("url", "https://github.com/johnbuckman/dcamp-ios/releases/latest/download/dcamp-macos-latest.zip"),
                ("length", "8"), (f"{{{SPARKLE}}}edSignature", "")
            ):
                modified = copy.deepcopy(root)
                modified.find("./channel/item/enclosure").set(key, value)
                ET.ElementTree(modified).write(feed)
                with self.subTest(key=key), self.assertRaises(ValueError):
                    check_feed(feed, info, archive, prefix)
            ET.ElementTree(root).write(feed)
            with self.assertRaises(ValueError):
                check_feed(feed, {"CFBundleVersion": "28"}, archive, prefix)
            archive.write_bytes(b"changed archive")
            with self.assertRaises(ValueError):
                check_feed(feed, info, archive, prefix)


if __name__ == "__main__":
    unittest.main()
