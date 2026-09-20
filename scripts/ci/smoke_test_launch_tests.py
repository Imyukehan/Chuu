import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from smoke_test_launch import check_launch


class LaunchSmokeTests(unittest.TestCase):
    def test_rejects_crash_and_clean_early_exit(self):
        with tempfile.TemporaryDirectory() as folder:
            for status in [0, 6]:
                with self.subTest(status=status), self.assertRaisesRegex(RuntimeError, "exited during startup"):
                    check_launch([sys.executable, "-c", f"raise SystemExit({status})"], Path(folder) / "launch.log", 2)

    def test_surviving_process_is_terminated_and_startup_bypass_is_removed(self):
        with tempfile.TemporaryDirectory() as folder:
            log = Path(folder) / "launch.log"
            with patch.dict(os.environ, {"XCTestConfigurationFilePath": "inherited-test-config"}):
                check_launch([sys.executable, "-u", "-c",
                              "import os,time; print(os.getpid()); "
                              "assert not any(k.startswith('XCTest') for k in os.environ); time.sleep(30)"], log, 1)
            pid = int(log.read_text().splitlines()[0])
            with self.assertRaises(ProcessLookupError):
                os.kill(pid, 0)

    def test_refuses_full_app_launch_outside_ci(self):
        environment = dict(os.environ, GITHUB_ACTIONS="false")
        result = subprocess.run([sys.executable, str(Path(__file__).with_name("smoke_test_launch.py"))],
                                env=environment, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("only allowed on the disposable macOS CI runner", result.stderr)


if __name__ == "__main__":
    unittest.main()
