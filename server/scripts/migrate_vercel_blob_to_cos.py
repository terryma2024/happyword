"""Backfill historical Vercel Blob asset URLs to Tencent COS.

Default mode is read-only. Use ``--apply`` to download each Vercel Blob object,
upload it through the active ``blob_service`` provider, and update the MongoDB
URL field in place.
"""

from __future__ import annotations

import argparse
import asyncio
import mimetypes
import os
from collections.abc import AsyncIterator, Iterable, Sequence
from dataclasses import dataclass
from typing import Any
from urllib.parse import unquote, urlparse

import httpx
from motor.motor_asyncio import AsyncIOMotorClient

from app.services import blob_service

DEFAULT_COLLECTION_PATHS: dict[str, tuple[str, ...]] = {
    "words": ("illustration_url", "audio_url"),
    "categories": ("source_image_url",),
    "lesson_import_drafts": ("source_image_url",),
    "word_packs": (
        "words.*.illustrationUrl",
        "words.*.audioUrl",
        "categories.*.source_image_url",
    ),
    "family_pack_drafts": (
        "words.*.illustration_url",
        "words.*.audio_url",
        "words.*.illustrationUrl",
        "words.*.audioUrl",
    ),
    "family_word_packs": (
        "words.*.illustration_url",
        "words.*.audio_url",
        "words.*.illustrationUrl",
        "words.*.audioUrl",
    ),
    "family_pack_definitions": ("scene.spellbookCoverUrl",),
}

KNOWN_ASSET_PREFIXES = (
    "illustrations/",
    "audio/",
    "lessons/",
    "spellbook-covers/",
)


@dataclass(frozen=True)
class UrlRef:
    collection: str
    document_id: Any
    path: str
    url: str


def is_vercel_blob_url(url: str) -> bool:
    host = urlparse(url).netloc.lower()
    return host == "blob.vercel-storage.com" or host.endswith(".blob.vercel-storage.com")


def cos_path_from_blob_url(url: str) -> str:
    parsed = urlparse(url)
    path = unquote(parsed.path.lstrip("/"))
    if any(path.startswith(prefix) for prefix in KNOWN_ASSET_PREFIXES):
        return path
    return f"migrated-vercel-blob/{path}"


def _values_at_path(value: Any, parts: Sequence[str], prefix: list[str]) -> Iterable[tuple[str, str]]:
    if not parts:
        if isinstance(value, str) and is_vercel_blob_url(value):
            yield ".".join(prefix), value
        return

    head, *tail = parts
    if head == "*":
        if not isinstance(value, list):
            return
        for idx, item in enumerate(value):
            yield from _values_at_path(item, tail, [*prefix, str(idx)])
        return

    if isinstance(value, dict) and head in value:
        yield from _values_at_path(value[head], tail, [*prefix, head])


def find_url_refs(
    collection: str,
    document: dict[str, Any],
    *,
    candidate_paths: Sequence[str],
) -> list[UrlRef]:
    refs: list[UrlRef] = []
    for path in candidate_paths:
        refs.extend(
            UrlRef(collection, document.get("_id"), concrete_path, url)
            for concrete_path, url in _values_at_path(document, path.split("."), [])
        )
    return refs


def _mongo_uri() -> str:
    uri = os.environ.get("MONGODB_URI") or os.environ.get("MONGO_URI")
    if not uri:
        raise SystemExit("MONGODB_URI or MONGO_URI is required")
    return uri


def _mongo_db_name() -> str:
    name = os.environ.get("MONGO_DB_NAME")
    if not name:
        raise SystemExit("MONGO_DB_NAME is required")
    return name


def _guess_mime(path: str, response: httpx.Response) -> str:
    content_type = response.headers.get("content-type", "").split(";", 1)[0].strip()
    if content_type:
        return content_type
    return mimetypes.guess_type(path)[0] or "application/octet-stream"


async def _download(client: httpx.AsyncClient, url: str) -> tuple[bytes, str]:
    response = await client.get(url)
    response.raise_for_status()
    path = cos_path_from_blob_url(url)
    return response.content, _guess_mime(path, response)


async def _verify_public_url(client: httpx.AsyncClient, url: str) -> None:
    response = await client.head(url)
    if response.status_code == 405:
        response = await client.get(url)
    response.raise_for_status()


async def collect_refs(db: Any) -> list[UrlRef]:
    refs: list[UrlRef] = []
    for collection, paths in DEFAULT_COLLECTION_PATHS.items():
        cursor = db[collection].find({}, {"_id": 1, **{path.split(".", 1)[0]: 1 for path in paths}})
        async for document in cursor:
            refs.extend(find_url_refs(collection, document, candidate_paths=paths))
    return refs


async def migrate_refs(refs: Sequence[UrlRef], *, verify: bool) -> AsyncIterator[tuple[UrlRef, str]]:
    async with httpx.AsyncClient(timeout=60.0, follow_redirects=True, trust_env=False) as client:
        for ref in refs:
            cos_path = cos_path_from_blob_url(ref.url)
            payload, mime = await _download(client, ref.url)
            new_url = await blob_service.upload_object(cos_path, payload, mime)

            yield ref, new_url

            if verify:
                await _verify_public_url(client, new_url)


async def run(args: argparse.Namespace) -> int:
    client = AsyncIOMotorClient(_mongo_uri(), serverSelectionTimeoutMS=10_000)
    db = client[_mongo_db_name()]
    try:
        refs = await collect_refs(db)
        by_collection: dict[str, int] = {}
        for ref in refs:
            by_collection[ref.collection] = by_collection.get(ref.collection, 0) + 1

        print(f"Vercel Blob URL refs: {len(refs)}")
        for collection, count in sorted(by_collection.items()):
            print(f"- {collection}: {count}")

        if not args.apply:
            print("Dry run only. Re-run with --apply to copy to COS and update MongoDB.")
            return 0

        if not blob_service.is_blob_configured():
            raise SystemExit("Active asset provider is not configured; set ASSET_STORAGE_PROVIDER=tencent_cos and COS_* env vars")

        uploaded = 0
        updated = 0
        verified = 0
        async for ref, new_url in migrate_refs(refs, verify=args.verify):
            uploaded += 1
            result = await db[ref.collection].update_one(
                {"_id": ref.document_id, ref.path: ref.url},
                {"$set": {ref.path: new_url}},
            )
            if result.modified_count != 1:
                raise RuntimeError(
                    f"Failed to update {ref.collection} _id={ref.document_id!r} path={ref.path}"
                )
            updated += 1
            if args.verify:
                verified += 1

        print(f"Backfill complete. uploaded={uploaded} updated={updated} verified={verified}")
        return 0
    finally:
        client.close()


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="copy assets and update MongoDB")
    parser.add_argument("--verify", action="store_true", help="HEAD/GET each new COS URL after upload")
    return parser.parse_args(argv)


def main() -> None:
    raise SystemExit(asyncio.run(run(parse_args())))


if __name__ == "__main__":  # pragma: no cover
    main()
