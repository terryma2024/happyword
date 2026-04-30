"""Off-site WordPack backup CLI (V0.5.7).

Snapshots the current PackPointer + every WordPack row to a single
timestamped JSON file under ``dist/`` (or any directory passed via
``--out-dir``). The file is human-readable and can be re-applied with a
sibling ``restore_pack.py`` (not yet shipped — V0.6+).

Usage::

    cd server
    uv run python scripts/backup_pack.py [--out-dir dist]

The function :func:`backup_to_disk` is the test-friendly entry point —
``test_backup_pack`` calls it directly with a ``tmp_path`` fixture.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from beanie import init_beanie
from motor.motor_asyncio import AsyncIOMotorClient

from app.config import get_settings
from app.models.pack_pointer import PackPointer
from app.models.user import User
from app.models.word import Word
from app.models.word_pack import WordPack


def _serialize_pointer(p: PackPointer) -> dict[str, Any]:
    return {
        "singleton_key": p.singleton_key,
        "current_version": p.current_version,
        "previous_version": p.previous_version,
    }


def _serialize_pack(p: WordPack) -> dict[str, Any]:
    return {
        "version": p.version,
        "schema_version": p.schema_version,
        "words": p.words,
        "categories": p.categories,
        "published_at": p.published_at.isoformat(),
        "published_by": p.published_by,
        "notes": p.notes,
    }


async def backup_to_disk(out_dir: Path) -> Path:
    """Write the current pointer + all WordPacks to ``out_dir``.

    Returns the resulting file path. The filename is timestamped to
    microsecond precision so back-to-back invocations produce distinct
    artifacts (operators often run a backup, change something, then
    re-run to confirm the diff).
    """
    out_dir.mkdir(parents=True, exist_ok=True)

    pointer = await PackPointer.find_one(PackPointer.singleton_key == "main")
    packs = await WordPack.find_all().to_list()

    payload: dict[str, Any] = {
        "schema": "happyword.pack-backup.v1",
        "exported_at": datetime.now(tz=UTC).isoformat(),
        "pointer": _serialize_pointer(pointer) if pointer is not None else None,
        "packs": [_serialize_pack(p) for p in packs],
    }

    ts = datetime.now(tz=UTC).strftime("%Y%m%dT%H%M%S%f")
    out_path = out_dir / f"pack-backup-{ts}.json"
    out_path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2, default=str),
        encoding="utf-8",
    )
    return out_path


async def _main(out_dir: Path) -> int:  # pragma: no cover - CLI shim
    settings = get_settings()
    client: AsyncIOMotorClient[dict[str, object]] = AsyncIOMotorClient(settings.mongo_uri)
    try:
        await init_beanie(
            database=client[settings.mongo_db_name],
            document_models=[User, Word, WordPack, PackPointer],
        )
        out_path = await backup_to_disk(out_dir)
    finally:
        client.close()
    print(f"backup-pack: OK -> {out_path}")
    return 0


if __name__ == "__main__":  # pragma: no cover
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--out-dir",
        default="dist",
        help="Directory to write the backup JSON into (default: dist)",
    )
    args = parser.parse_args()
    sys.exit(asyncio.run(_main(Path(args.out_dir))))
