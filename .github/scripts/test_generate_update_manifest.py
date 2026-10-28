import hashlib
from pathlib import Path
import tempfile
import unittest

from generate_update_manifest import generate, gradle_value, load_notes


class UpdateManifestGenerationTest(unittest.TestCase):
    def setUp(self):
        self.root = Path(__file__).resolve().parents[2]
        self.gradle = self.root / "app/build.gradle.kts"
        self.notes = self.root / ".github/release-notes.txt"
        self.version = gradle_value(self.gradle.read_text(encoding="utf-8"), "versionName")
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.apk = Path(self.temp.name) / ("MtForum-v" + self.version + "-release.apk")
        self.apk.write_bytes(b"test APK bytes; not a real APK")
        self.tag = "v" + self.version + "-build.123"

    def test_release_fields_match_compiled_artifact(self):
        manifest = generate(self.gradle, self.apk, self.notes,
                            "Rainy-C/Mtforum", self.tag, "2026-10-28")
        latest = manifest["latest"]
        self.assertEqual(1, manifest["schema_version"])
        self.assertEqual("me.rain.mtforum", manifest["app_id"])
        self.assertEqual(self.version, latest["version_name"])
        self.assertEqual(int(gradle_value(self.gradle.read_text(), "versionCode")),
                         latest["version_code"])
        self.assertEqual(len(self.apk.read_bytes()), latest["file_size_bytes"])
        self.assertEqual(hashlib.sha256(self.apk.read_bytes()).hexdigest(), latest["sha256"])
        self.assertEqual(
            "https://github.com/Rainy-C/Mtforum/releases/download/"
            + self.tag + "/" + self.apk.name, latest["download_url"]
        )
        self.assertEqual("2026-10-28", latest["release_date"])
        self.assertTrue(latest["changelog"])
        self.assertFalse(latest["force_update"])
        self.assertEqual(6, latest["min_supported_version_code"])
        self.assertEqual(24, manifest["check"]["interval_hours"])

    def test_rejects_a_tag_for_a_different_version(self):
        with self.assertRaises(ValueError):
            generate(self.gradle, self.apk, self.notes, "Rainy-C/Mtforum",
                     "v0.0.1-build.123", "2026-10-28")

    def test_rejects_stale_release_notes(self):
        stale = Path(self.temp.name) / "release-notes.txt"
        stale.write_text("version_name=0.0.1\n- old notes\n", encoding="utf-8")
        with self.assertRaises(ValueError):
            load_notes(stale, self.version)


if __name__ == "__main__":
    unittest.main()
