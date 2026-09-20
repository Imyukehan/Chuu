"""Exercise actual app startup on the disposable macOS CI runner, not a user's Mac."""

import os
from pathlib import Path
import subprocess
import sys


def check_launch(command, log_path, duration=10):
    # Do not accidentally inherit the app's XCTest startup bypass.
    environment = {key: value for key, value in os.environ.items()
                   if not key.startswith("XCTest") and key != "MOS_TEST_ENABLE_APP_STARTUP"}
    with Path(log_path).open("w") as log:
        process = subprocess.Popen(command, env=environment, stdout=log, stderr=subprocess.STDOUT)
        try:
            try:
                status = process.wait(timeout=duration)
            except subprocess.TimeoutExpired:
                return
            raise RuntimeError(f"App exited during startup (status {status}); see {log_path}")
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


def main():
    if os.environ.get("GITHUB_ACTIONS") != "true" or os.environ.get("RUNNER_OS") != "macOS":
        raise RuntimeError("Full app startup is only allowed on the disposable macOS CI runner")
    app, log = map(Path, sys.argv[1:])
    check_launch([str(app / "Contents/MacOS/MouseControl")], log)
    print("Extracted app survived 10 seconds of actual startup.")


if __name__ == "__main__":
    main()
