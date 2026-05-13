"""Android adapter — wraps am instrument + adb pull from internal storage.

The existing AndroidScreenScreenshotTest exposes three @Test methods that each
capture a sequence of PNGs into the app's internal storage at
`filesDir/screenshots/<filename>.png` (i.e.
`/data/data/cool.happyword.wordmagic/files/screenshots/...`). For per-page
granularity we let the registry name BOTH the @Test method to invoke AND the
filename to pull off the device.
"""

from __future__ import annotations

import os
import shlex
import subprocess
from pathlib import Path

from parity_scout.adapters import Adapter, AdapterResult


_PACKAGE = "cool.happyword.wordmagic"
_TEST_RUNNER = (
    "cool.happyword.wordmagic.test/androidx.test.runner.AndroidJUnitRunner"
)
_SCREENSHOT_CLASS = "cool.happyword.wordmagic.AndroidScreenScreenshotTest"


def _adb_path() -> str:
    sdk = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    if sdk:
        candidate = Path(sdk) / "platform-tools" / "adb"
        if candidate.is_file():
            return str(candidate)
    return "adb"  # fall back to PATH lookup


class AndroidAdapter(Adapter):
    name = "android"

    def capture(self, page_id, capture_spec, out_dir, timeout_s):
        # Accept either:
        #   { kind: android_screenshot_test, test_method: ..., filename: ... }
        #   { kind: android_screenshot_test, case: ... }  (legacy alias)
        test_method = capture_spec.get("test_method")
        filename = capture_spec.get("filename") or capture_spec.get("case")
        if filename and not filename.endswith(".png"):
            filename = f"{filename}.png"
        if not test_method or not filename:
            return AdapterResult(
                platform=self.name,
                page_id=page_id,
                out_dir=out_dir,
                success=False,
                stderr_tail=(
                    "capture spec missing test_method or filename "
                    "(android_screenshot_test)"
                ),
            )

        out_dir.mkdir(parents=True, exist_ok=True)
        adb = _adb_path()
        try:
            subprocess.run(
                [
                    adb, "shell", "am", "instrument", "-w",
                    "-e", "class", f"{_SCREENSHOT_CLASS}#{test_method}",
                    _TEST_RUNNER,
                ],
                capture_output=True,
                text=True,
                timeout=timeout_s,
                check=True,
            )
            out_png = out_dir / filename
            # `run-as` lets us cat the file out of internal storage without root.
            shell_cmd = (
                f"run-as {_PACKAGE} cat "
                f"{shlex.quote('files/screenshots/' + filename)}"
            )
            with open(out_png, "wb") as fh:
                proc = subprocess.run(
                    [adb, "exec-out", "sh", "-c", shell_cmd],
                    stdout=fh,
                    stderr=subprocess.PIPE,
                    timeout=30,
                    check=True,
                )
            if out_png.stat().st_size == 0:
                err = proc.stderr.decode(errors="replace") if proc.stderr else ""
                return AdapterResult(
                    platform=self.name,
                    page_id=page_id,
                    out_dir=out_dir,
                    success=False,
                    stderr_tail=(err or "empty PNG")[-2000:],
                )
        except subprocess.CalledProcessError as exc:
            err = exc.stderr
            if isinstance(err, bytes):
                err = err.decode(errors="replace")
            return AdapterResult(
                platform=self.name,
                page_id=page_id,
                out_dir=out_dir,
                success=False,
                stderr_tail=(err or str(exc))[-2000:],
            )
        except subprocess.TimeoutExpired as exc:
            return AdapterResult(
                platform=self.name,
                page_id=page_id,
                out_dir=out_dir,
                success=False,
                stderr_tail=f"timeout: {exc}",
            )
        return AdapterResult(
            platform=self.name,
            page_id=page_id,
            out_dir=out_dir,
            success=True,
        )
