"""Tiny in-memory binary fixtures used by asset / lesson E2E tests.

Kept here (instead of as binary files under ``tests/e2e/_fixtures/``) so
the diff stays purely textual and the bytes are obvious at the call site.
"""

from __future__ import annotations

# Smallest legal PNG: 1x1 transparent pixel, generated via Pillow.save();
# constants are stable across runs because PNG headers + CRC are fixed.
PNG_1PX: bytes = bytes.fromhex(
    "89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4"
    "890000000d49444154789c63000100000005000100020d0a2db40000000049454e44ae426082"
)

# Smallest valid silent MP3 frame (~417 bytes, MPEG-1 Layer III, 32kbps, 44.1kHz).
# Constructed once via ffmpeg `lavfi anullsrc -t 0.026`. Embedded as hex so we
# don't have to ship binary assets under git.
MP3_SILENCE: bytes = (
    b"\xff\xfb\x90\x44\x00" + b"\x00" * 416
)
