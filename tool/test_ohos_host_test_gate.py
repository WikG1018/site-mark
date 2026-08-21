import subprocess
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RUNNER = ROOT / "tool" / "ohos-native" / "run-host-tests.ps1"
BUILD = ROOT / "tool" / "ohos-native" / "build-hap.ps1"
CI = ROOT / ".github" / "workflows" / "ci.yml"
FAILURE_FIXTURE = (
    ROOT / "tool" / "ohos-native" / "test" / "fixtures" / "failing_unittest.py"
)
POWERSHELL_FAILURE_FIXTURE = (
    "tool/ohos-native/test/fixtures/failing_host_test.ps1"
)


class HarmonyHostTestGateTest(unittest.TestCase):
    def run_gate(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                "pwsh",
                "-NoLogo",
                "-NoProfile",
                "-File",
                str(RUNNER),
                *arguments,
            ],
            cwd=ROOT,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=False,
        )

    def test_shared_runner_owns_every_harmony_host_test(self) -> None:
        runner = RUNNER.read_text(encoding="utf-8")
        for test in (
            "tool.test_verify_ohos_native_manifest",
            "tool.test_seed_ohos_performance_db",
            "tool.test_ohos_capture_database_contract",
            "tool.test_ohos_back_wiring",
            "tool.test_ohos_host_test_gate",
            "verify-test-result.Tests.ps1",
        ):
            self.assertIn(test, runner)

        build = BUILD.read_text(encoding="utf-8")
        self.assertIn("run-host-tests.ps1", build)
        self.assertNotIn("tool.test_ohos_capture_database_contract", build)

        ci = CI.read_text(encoding="utf-8")
        self.assertIn("run-host-tests.ps1", ci)
        self.assertNotIn("tool.test_verify_ohos_native_manifest", ci)
        self.assertNotIn("tool.test_ohos_capture_database_contract", ci)

    def test_shared_runner_returns_nonzero_for_a_real_failing_fixture(self) -> None:
        result = self.run_gate("-PythonTestModules", str(FAILURE_FIXTURE))

        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("intentional host gate failure", result.stdout + result.stderr)

    def test_shared_runner_returns_nonzero_for_a_failing_powershell_fixture(self) -> None:
        result = self.run_gate(
            "-PythonTestModules",
            "tool.test_verify_ohos_native_manifest",
            "-PowerShellTestScripts",
            POWERSHELL_FAILURE_FIXTURE,
        )

        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("intentional PowerShell host gate failure", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
