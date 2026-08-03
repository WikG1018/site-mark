import pathlib
import unittest


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[1]
RELEASE_WORKFLOW = REPOSITORY_ROOT / ".github" / "workflows" / "release.yml"


class ReleaseWorkflowTest(unittest.TestCase):
    def test_arm64_split_uses_flutter_version_code_offset(self) -> None:
        workflow = RELEASE_WORKFLOW.read_text(encoding="utf-8")

        self.assertIn('ARM64_VERSION_CODE="$((2000 + VERSION_CODE))"', workflow)
        self.assertIn('verify_badging "$ARM64" "$ARM64_VERSION_CODE"', workflow)
        self.assertIn('verify_badging "$UNIVERSAL" "$VERSION_CODE"', workflow)

    def test_metadata_failures_include_the_failed_assertion(self) -> None:
        workflow = RELEASE_WORKFLOW.read_text(encoding="utf-8")

        self.assertIn("APK metadata check failed:", workflow)


if __name__ == "__main__":
    unittest.main()
