"""iOS adapter — wraps xcrun simctl launch + io screenshot.

Reuses launch arguments already defined in WordMagicGameUITests
(-UITestResetState, -UITestRouteBattle, -UITestRouteConfig, etc.).
"""

from __future__ import annotations

import subprocess
import time

from parity_scout.adapters import Adapter, AdapterResult


_BUNDLE_ID = "com.terryma.wordmagicgame"


class IosAdapter(Adapter):
    name = "ios"

    def capture(self, page_id, capture_spec, out_dir, timeout_s):
        launch_args = list(capture_spec.get("launch_args") or [])
        basename = capture_spec.get("output_basename") or page_id
        out_dir.mkdir(parents=True, exist_ok=True)

        try:
            # Terminate any prior instance so reset launch-args take effect.
            subprocess.run(
                ["xcrun", "simctl", "terminate", "booted", _BUNDLE_ID],
                capture_output=True,
                text=True,
                timeout=20,
                check=False,
            )
            subprocess.run(
                ["xcrun", "simctl", "launch", "booted", _BUNDLE_ID, *launch_args],
                capture_output=True,
                text=True,
                timeout=timeout_s,
                check=True,
            )
            # Allow the landing screen to render.
            time.sleep(2.0)
            out_png = out_dir / f"{basename}.png"
            subprocess.run(
                [
                    "xcrun",
                    "simctl",
                    "io",
                    "booted",
                    "screenshot",
                    str(out_png),
                ],
                capture_output=True,
                text=True,
                timeout=20,
                check=True,
            )
        except subprocess.CalledProcessError as exc:
            return AdapterResult(
                platform=self.name,
                page_id=page_id,
                out_dir=out_dir,
                success=False,
                stderr_tail=(exc.stderr or "")[-2000:],
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
