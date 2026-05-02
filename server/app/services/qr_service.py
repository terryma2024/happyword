"""V0.6.2 — server-side QR rendering for the parent /devices/add page.

We render to PNG bytes embedded as a data URL so the page is self-contained
(no extra HTTP round-trip, no CDN dependency, plays nicely with Vercel's
edge cache). The encoded payload is the parent web URL the client opens
when it scans (`{PARENT_WEB_BASE_URL}/p/<token-prefix>`).
"""

import base64
from io import BytesIO

import qrcode
from qrcode.constants import ERROR_CORRECT_M
from qrcode.image.pil import PilImage


def render_qr_data_url(payload: str) -> str:
    qr = qrcode.QRCode(
        version=None,
        error_correction=ERROR_CORRECT_M,
        box_size=8,
        border=2,
        image_factory=PilImage,
    )
    qr.add_data(payload)
    qr.make(fit=True)
    img = qr.make_image(fill_color="black", back_color="white")
    buf = BytesIO()
    img.save(buf, format="PNG")
    encoded = base64.b64encode(buf.getvalue()).decode("ascii")
    return f"data:image/png;base64,{encoded}"
