import tempfile
import unittest
from pathlib import Path

from tool.verify_release_tag import ReleaseTagError, verify_release_tag


class VerifyReleaseTagTest(unittest.TestCase):
    def _pubspec(self, contents: str) -> Path:
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        path = Path(directory.name) / "pubspec.yaml"
        path.write_text(contents, encoding="utf-8")
        return path

    def test_matching_tag_uses_version_name_without_build_number(self) -> None:
        path = self._pubspec("name: sitemark\nversion: 0.8.1+12\n")
        self.assertEqual(verify_release_tag("v0.8.1", path), "0.8.1")

    def test_mismatching_tag_is_rejected(self) -> None:
        path = self._pubspec("name: sitemark\nversion: 0.8.1+12\n")
        with self.assertRaisesRegex(ReleaseTagError, "does not match"):
            verify_release_tag("v0.8.0", path)

    def test_missing_version_is_rejected(self) -> None:
        path = self._pubspec("name: sitemark\n")
        with self.assertRaisesRegex(ReleaseTagError, "version"):
            verify_release_tag("v0.8.1", path)

    def test_invalid_tag_is_rejected(self) -> None:
        path = self._pubspec("name: sitemark\nversion: 0.8.1+12\n")
        for tag in ("0.8.1", "release-v0.8.1", "v0.8", "v0.8.1+12"):
            with self.subTest(tag=tag), self.assertRaisesRegex(
                ReleaseTagError,
                "Invalid release tag",
            ):
                verify_release_tag(tag, path)


if __name__ == "__main__":
    unittest.main()
