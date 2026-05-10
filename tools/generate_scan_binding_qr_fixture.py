"""Generate the ohosTest QR fixture used by ParentBindingFlowV06.

Run from the `server/` directory so `qrcode` resolves via the server's
uv environment (the only place qrcode is declared as a dependency):

    cd server && uv run python ../tools/generate_scan_binding_qr_fixture.py

Output: harmonyos/entry/src/ohosTest/resources/rawfile/scan_binding_qr_fixture.png

The PNG is committed to the repo so the ohosTest HAP packaging does not
require Python to be installed; this script exists to make regenerating
the fixture deterministic (e.g. if we ever need to change PAYLOAD).
"""
from __future__ import annotations

from pathlib import Path

import qrcode
from qrcode.constants import ERROR_CORRECT_M
from qrcode.image.pil import PilImage

# Encoded QR payload. ParentBindingFlowV06.ui.test.ets writes this same
# string to the SCAN_BINDING_BARCODE_DECODER_OVERRIDE_PAYLOAD_KEY
# AppStorage key so the on-device test does not depend on whether
# ScanKit successfully decodes the bundled PNG. The token "uitestqr01"
# is 10 chars (within MIN_TOKEN_LEN=4 / MAX_TOKEN_LEN=64) and the mock
# UI server's /api/v1/pair/redeem accepts any non-empty token.
PAYLOAD: str = "https://happyword.cool/p/uitestqr01"

REPO_ROOT: Path = Path(__file__).resolve().parent.parent
OUT: Path = (
    REPO_ROOT
    / "harmonyos"
    / "entry"
    / "src"
    / "ohosTest"
    / "resources"
    / "rawfile"
    / "scan_binding_qr_fixture.png"
)


def main() -> None:
    qr = qrcode.QRCode(
        error_correction=ERROR_CORRECT_M,
        box_size=8,
        border=2,
    )
    qr.add_data(PAYLOAD)
    qr.make(fit=True)
    img = qr.make_image(
        image_factory=PilImage,
        fill_color="black",
        back_color="white",
    )
    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT)
    size = OUT.stat().st_size
    print(f"wrote {OUT} ({size} bytes) encoding {PAYLOAD}")


if __name__ == "__main__":
    main()
