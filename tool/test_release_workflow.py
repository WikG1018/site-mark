import pathlib
import unittest


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[1]
RELEASE_WORKFLOW = REPOSITORY_ROOT / ".github" / "workflows" / "release.yml"
CI_WORKFLOW = REPOSITORY_ROOT / ".github" / "workflows" / "ci.yml"

FORBIDDEN_PERMISSIONS = (
    "android.permission.INTERNET",
    "android.permission.CAMERA",
    "android.permission.ACCESS_BACKGROUND_LOCATION",
    "android.permission.READ_MEDIA_IMAGES",
    "android.permission.ACCESS_NETWORK_STATE",
    "android.permission.WRITE_EXTERNAL_STORAGE",
    "android.permission.READ_EXTERNAL_STORAGE",
    "android.permission.MANAGE_EXTERNAL_STORAGE",
    "android.permission.READ_MEDIA_VIDEO",
    "android.permission.READ_MEDIA_AUDIO",
)


class ReleaseWorkflowTest(unittest.TestCase):
    def test_arm64_split_uses_flutter_version_code_offset(self) -> None:
        workflow = RELEASE_WORKFLOW.read_text(encoding="utf-8")

        self.assertIn('ARM64_VERSION_CODE="$((2000 + VERSION_CODE))"', workflow)
        self.assertIn('verify_badging "$ARM64" "$ARM64_VERSION_CODE"', workflow)
        self.assertIn('verify_badging "$UNIVERSAL" "$VERSION_CODE"', workflow)

    def test_metadata_failures_include_the_failed_assertion(self) -> None:
        workflow = RELEASE_WORKFLOW.read_text(encoding="utf-8")

        self.assertIn("APK metadata check failed:", workflow)

    def test_release_forbids_network_camera_and_broad_storage_permissions(self) -> None:
        workflow = RELEASE_WORKFLOW.read_text(encoding="utf-8")

        for permission in FORBIDDEN_PERMISSIONS:
            with self.subTest(permission=permission):
                self.assertIn(permission, workflow)

    def test_ci_checks_unsigned_release_apk_permissions(self) -> None:
        workflow = CI_WORKFLOW.read_text(encoding="utf-8")

        self.assertIn("Verify release APK has no forbidden permissions", workflow)
        self.assertIn("build/app/outputs/flutter-apk/app-release.apk", workflow)
        self.assertIn("build-tools/36.0.0/aapt2", workflow)
        for permission in FORBIDDEN_PERMISSIONS:
            with self.subTest(permission=permission):
                self.assertIn(permission, workflow)


if __name__ == "__main__":
    unittest.main()
