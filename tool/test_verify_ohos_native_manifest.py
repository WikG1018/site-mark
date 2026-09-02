import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class HarmonyNativeManifestTest(unittest.TestCase):
    def test_manifest_requests_only_network_location_and_vibrate(self) -> None:
        module = (ROOT / "ohos-native/entry/src/main/module.json5").read_text(
            encoding="utf-8"
        )
        permissions = set(re.findall(r'"name"\s*:\s*"(ohos\.permission\.[A-Z_]+)"', module))
        # VIBRATE is a system-grant permission backing the selection haptics.
        # INTERNET + GET_NETWORK_INFO serve the opt-in NAS sync (D-023
        # revision, 2026-09-02): uploads go only to the server the user
        # configures. The camera/media surface must stay empty — captures
        # go through the system camera app.
        self.assertEqual(
            permissions,
            {
                "ohos.permission.INTERNET",
                "ohos.permission.GET_NETWORK_INFO",
                "ohos.permission.LOCATION",
                "ohos.permission.APPROXIMATELY_LOCATION",
                "ohos.permission.VIBRATE",
            },
        )
        for forbidden in (
            "ohos.permission.CAMERA",
            "ohos.permission.READ_IMAGEVIDEO",
            "ohos.permission.WRITE_IMAGEVIDEO",
        ):
            self.assertNotIn(forbidden, module)

    def test_package_identity_and_dual_abi_are_stable(self) -> None:
        app = (ROOT / "ohos-native/AppScope/app.json5").read_text(encoding="utf-8")
        profile = (ROOT / "ohos-native/entry/build-profile.json5").read_text(
            encoding="utf-8"
        )
        self.assertIn('"bundleName": "io.github.wikg1018.sitemark.native"', app)
        self.assertIn('"arm64-v8a"', profile)
        self.assertIn('"x86_64"', profile)

    def test_debug_capture_sample_is_guarded_by_build_metadata(self) -> None:
        services = (
            ROOT
            / "ohos-native/entry/src/main/ets/core/system/SystemServices.ets"
        ).read_text(encoding="utf-8")
        guarded_calls = re.findall(
            r"if \(this\.context\.applicationInfo\.debug\) \{[^}]*writeDebugSample",
            services,
            flags=re.DOTALL,
        )
        self.assertGreaterEqual(len(guarded_calls), 2)


if __name__ == "__main__":
    unittest.main()
