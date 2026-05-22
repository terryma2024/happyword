"""MongoDB inventory helper for the M7A Atlas -> TencentDB migration.

The script intentionally reports only schema/operational metadata: collection
names, counts, index definitions, TTL/unique flags, and collection size stats
when available. It never prints the MongoDB URI, credentials, or document
payloads.
"""

from __future__ import annotations

import argparse
import json
import os
from datetime import UTC, datetime
from typing import Any
from urllib.parse import urlsplit

from pymongo import MongoClient


def _env(name: str, *, default: str = "") -> str:
    return os.environ.get(name, default).strip()


def _connection_hosts(uri: str) -> list[str]:
    """Return redacted host labels from a MongoDB URI."""
    parsed = urlsplit(uri)
    netloc = parsed.netloc.rsplit("@", 1)[-1]
    if not netloc:
        return []
    return [host.strip() for host in netloc.split(",") if host.strip()]


def _json_default(value: Any) -> str:
    return str(value)


def _index_document(index: dict[str, Any]) -> dict[str, Any]:
    keys = index.get("key", [])
    if not isinstance(keys, list):
        keys = list(keys)
    item: dict[str, Any] = {
        "name": index.get("name", ""),
        "keys": keys,
    }
    if index.get("unique"):
        item["unique"] = True
    if "expireAfterSeconds" in index:
        item["expireAfterSeconds"] = index["expireAfterSeconds"]
    if "partialFilterExpression" in index:
        item["partialFilterExpression"] = index["partialFilterExpression"]
    if "sparse" in index:
        item["sparse"] = index["sparse"]
    return item


def _safe_collection_stats(db: Any, collection_name: str) -> dict[str, Any]:
    try:
        raw = db.command("collStats", collection_name)
    except Exception as exc:  # noqa: BLE001 - inventory should continue per collection
        return {"available": False, "error": type(exc).__name__}
    keep = ("count", "size", "storageSize", "totalIndexSize", "avgObjSize", "nindexes")
    return {"available": True, **{key: raw.get(key) for key in keep if key in raw}}


def build_inventory(
    client: MongoClient,
    *,
    db_name: str,
    uri: str,
    count_timeout_ms: int = 5000,
    include_stats: bool = True,
) -> dict[str, Any]:
    db = client[db_name]
    server_info = client.server_info()
    collections: list[dict[str, Any]] = []

    for name in sorted(db.list_collection_names()):
        if name.startswith("system."):
            continue
        collection = db[name]
        indexes = [_index_document(index) for index in collection.list_indexes()]
        stats = (
            _safe_collection_stats(db, name)
            if include_stats
            else {"available": False, "skipped": True}
        )
        try:
            count = collection.count_documents({}, maxTimeMS=count_timeout_ms)
        except Exception:  # noqa: BLE001 - fall back to collStats/estimated count
            count = (
                stats.get("count")
                if stats.get("available")
                else collection.estimated_document_count()
            )
        collections.append(
            {
                "name": name,
                "document_count": count,
                "indexes": indexes,
                "ttl_indexes": [
                    index for index in indexes if "expireAfterSeconds" in index
                ],
                "unique_indexes": [index for index in indexes if index.get("unique")],
                "stats": stats,
            }
        )

    largest = sorted(
        collections,
        key=lambda item: int(item["stats"].get("size") or 0)
        if isinstance(item.get("stats"), dict)
        else 0,
        reverse=True,
    )
    return {
        "generated_at": datetime.now(tz=UTC).isoformat(),
        "database": db_name,
        "connection_hosts": _connection_hosts(uri),
        "server": {
            "version": server_info.get("version"),
            "versionArray": server_info.get("versionArray"),
            "gitVersion": server_info.get("gitVersion"),
            "modules": server_info.get("modules", []),
        },
        "collections": collections,
        "collection_count": len(collections),
        "total_document_count": sum(
            int(item["document_count"] or 0) for item in collections
        ),
        "largest_collections": [
            {
                "name": item["name"],
                "document_count": item["document_count"],
                "size": item["stats"].get("size") if isinstance(item["stats"], dict) else None,
                "storageSize": item["stats"].get("storageSize")
                if isinstance(item["stats"], dict)
                else None,
                "totalIndexSize": item["stats"].get("totalIndexSize")
                if isinstance(item["stats"], dict)
                else None,
            }
            for item in largest[:10]
        ],
    }


def to_markdown(report: dict[str, Any]) -> str:
    lines = [
        f"# MongoDB Inventory: `{report['database']}`",
        "",
        f"- Generated at: `{report['generated_at']}`",
        f"- Server version: `{report['server'].get('version')}`",
        f"- Collections: `{report['collection_count']}`",
        f"- Total documents: `{report['total_document_count']}`",
        "",
        "## Collections",
        "",
        "| Collection | Documents | Indexes | TTL indexes | Unique indexes | Size bytes |",
        "| --- | ---: | ---: | ---: | ---: | ---: |",
    ]
    for collection in report["collections"]:
        stats = collection.get("stats", {})
        lines.append(
            "| {name} | {count} | {indexes} | {ttl} | {unique} | {size} |".format(
                name=collection["name"],
                count=collection["document_count"],
                indexes=len(collection["indexes"]),
                ttl=len(collection["ttl_indexes"]),
                unique=len(collection["unique_indexes"]),
                size=stats.get("size", "") if isinstance(stats, dict) else "",
            )
        )
    lines.extend(["", "## Indexes", ""])
    for collection in report["collections"]:
        lines.append(f"### `{collection['name']}`")
        for index in collection["indexes"]:
            flags: list[str] = []
            if index.get("unique"):
                flags.append("unique")
            if "expireAfterSeconds" in index:
                flags.append(f"ttl={index['expireAfterSeconds']}s")
            suffix = f" ({', '.join(flags)})" if flags else ""
            lines.append(f"- `{index['name']}`: `{index['keys']}`{suffix}")
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--format", choices=("json", "markdown"), default="json")
    parser.add_argument("--database", default=_env("MONGO_DB_NAME"))
    parser.add_argument("--uri-env", default="MONGODB_URI")
    parser.add_argument("--count-timeout-ms", type=int, default=5000)
    parser.add_argument("--skip-stats", action="store_true")
    args = parser.parse_args()

    uri = _env(args.uri_env)
    if not uri:
        raise SystemExit(f"{args.uri_env} is required")
    if not args.database:
        raise SystemExit("MONGO_DB_NAME or --database is required")

    with MongoClient(uri, serverSelectionTimeoutMS=15000) as client:
        report = build_inventory(
            client,
            db_name=args.database,
            uri=uri,
            count_timeout_ms=args.count_timeout_ms,
            include_stats=not args.skip_stats,
        )
    if args.format == "markdown":
        print(to_markdown(report), end="")
    else:
        print(json.dumps(report, ensure_ascii=False, indent=2, default=_json_default))


if __name__ == "__main__":
    main()
