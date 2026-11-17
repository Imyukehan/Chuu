import importlib.util
import pathlib
import unittest
import xml.etree.ElementTree as ET

SPEC = importlib.util.spec_from_file_location("appcast", pathlib.Path(__file__).with_name("make_appcast.py"))
appcast = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(appcast)


class AppcastTests(unittest.TestCase):
    info = {"CFBundleIdentifier": "moe.khan.MouseControl", "CFBundleShortVersionString": "0.1.6", "CFBundleVersion": "20261117.1"}
    url = "https://github.com/Imyukehan/Chuu/releases/download/v0.1.6/Chuu-0.1.6-20261117.1-arm64.zip"

    def test_feed_uses_public_release_and_sparkle_build(self):
        feed = appcast.make_feed(self.info, self.url, 100, "signed", "<h2>Update & fixes</h2>", "date")
        parsed = ET.fromstring(ET.tostring(feed.getroot()))
        item = parsed.find("channel/item")
        enclosure = item.find("enclosure")
        self.assertEqual(enclosure.attrib["url"], self.url)
        self.assertEqual(enclosure.attrib[f"{{{appcast.NAMESPACE}}}version"], "20261117.1")
        self.assertEqual(item.findtext("description"), "<h2>Update & fixes</h2>")
        self.assertIsNone(item.find(f"{{{appcast.NAMESPACE}}}releaseNotesLink"))

    def test_rejects_unrelated_bundle_stale_build_and_bad_download_url(self):
        for info, asset in [
            (dict(self.info, CFBundleIdentifier="another.app"), self.url),
            (dict(self.info, CFBundleVersion="1"), self.url),
            (self.info, self.url + "?token=secret"),
            (self.info, self.url.replace("github.com/", "github.com.evil.test/")),
            (self.info, self.url.replace("v0.1.6", "v0.1.7")),
            (self.info, "https://api.github.com/repos/Imyukehan/Chuu/releases/assets/12345"),
        ]:
            with self.assertRaises(ValueError):
                appcast.make_feed(info, asset, 100, "signature", "notes", "date")


if __name__ == "__main__":
    unittest.main()
