"""The Windows build wrapper must fail closed when its SDK is unavailable."""
import os
from pathlib import Path
import subprocess
import unittest


@unittest.skipUnless(os.name == "nt", "Windows batch wrapper")
class WindowsBuildWrapperTest(unittest.TestCase):
    def run_wrapper(self, flutter_root):
        env = os.environ.copy()
        env.pop("FLUTTER_ROOT", None)
        if flutter_root is not None:
            env["FLUTTER_ROOT"] = flutter_root
        wrapper = Path(__file__).resolve().parents[1] / "rust_builder/cargokit/run_build_tool.cmd"
        return subprocess.run(["cmd.exe", "/d", "/c", str(wrapper)],
                              env=env, capture_output=True, timeout=15)

    def test_missing_sdk_is_not_a_successful_build(self):
        result = self.run_wrapper(None)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"FLUTTER_ROOT is required", result.stderr)

    def test_invalid_sdk_is_not_a_successful_build(self):
        result = self.run_wrapper("Z:/sitemark-no-such-flutter-sdk")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"Dart SDK executable was not found", result.stderr)


if __name__ == "__main__":
    unittest.main()
