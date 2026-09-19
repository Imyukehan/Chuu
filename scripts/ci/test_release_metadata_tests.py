import unittest
from test_release_metadata import validate


class ReleaseMetadataTests(unittest.TestCase):
    def setUp(self):
        self.app = {"CFBundleIdentifier": "moe.khan.MouseControl", "CFBundleShortVersionString": "0.1.1", "CFBundleVersion": "20260919.1"}
        self.widget = dict(self.app, CFBundleIdentifier="moe.khan.MouseControl.BatteryWidget")

    def test_matching_versions_are_explicitly_unnotarized(self):
        result = validate(self.app, self.widget, "v0.1.1")
        self.assertFalse(result["notarized"])
        self.assertEqual(result["signing"], "ad-hoc")

    def test_package_targets_only_apple_silicon(self):
        result = validate(self.app, self.widget, "v0.1.1")
        self.assertEqual(result["architectures"], ["arm64"])

    def test_rejects_bad_or_mismatched_tags(self):
        for tag in ["main", "v0.1.2", "v0.1.1\n", "v0.1.1;echo bad"]:
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                validate(self.app, self.widget, tag)

    def test_rejects_widget_version_or_identity_mismatch(self):
        for key, value in [("CFBundleVersion", "1"), ("CFBundleShortVersionString", "0.1.0"), ("CFBundleIdentifier", "example.other")]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                validate(self.app, dict(self.widget, **{key: value}), "v0.1.1")

    def test_rejects_update_feed(self):
        with self.assertRaises(ValueError):
            validate(dict(self.app, SUFeedURL="https://example.com/appcast.xml"), self.widget, "v0.1.1")

    def test_rejects_missing_build_number(self):
        del self.app["CFBundleVersion"]
        with self.assertRaises(ValueError):
            validate(self.app, self.widget, "v0.1.1")


if __name__ == "__main__":
    unittest.main()
