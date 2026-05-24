"""Redacted MongoDB connectivity smoke for Atlas/TencentDB cutovers.

The script verifies the URI can authenticate, ping the server, list the target
database collections, and optionally perform a tiny write/read/delete probe in a
dedicated migration collection. It intentionally reports only redacted hosts and
operational metadata; it never prints the URI, credentials, or document payloads.
"""

from __future__ import annotations

import argparse
import json
import os
from datetime import UTC, datetime
from typing import Any
from uuid import uuid4

from pymongo import MongoClient

from scripts.db_inventory import _connection_hosts


def _env(name: str, *, default: str = "") -> str:
    return os.environ.get(name, default).strip()


def run_smoke(
    client: MongoClient,
    *,
    db_name: str,
    uri: str,
    write_probe: bool = False,
    probe_collection: str = "_migration_probe",
) -> dict[str, Any]:
    client.admin.command("ping")
    server_info = client.server_info()
    db = client[db_name]
    collections = sorted(
        name for name in db.list_collection_names() if not name.startswith("system.")
    )

    write_probe_result: dict[str, Any] = {"enabled": False}
    if write_probe:
        probe_id = f"db-connectivity-smoke-{uuid4()}"
        collection = db[probe_collection]
        payload = {
            "_id": probe_id,
            "created_at": datetime.now(tz=UTC),
            "purpose": "m7a-connectivity-smoke",
        }
        insert_result = collection.insert_one(payload)
        found = collection.find_one({"_id": probe_id}, {"_id": 1})
        delete_result = collection.delete_one({"_id": probe_id})
        write_probe_result = {
            "enabled": True,
            "collection": probe_collection,
            "insert_acknowledged": bool(insert_result.acknowledged),
            "read_back": found is not None,
            "deleted_count": int(delete_result.deleted_count),
        }
        if not (
            write_probe_result["insert_acknowledged"]
            and write_probe_result["read_back"]
            and write_probe_result["deleted_count"] == 1
        ):
            raise RuntimeError("write probe did not complete cleanly")

    return {
        "ok": True,
        "checked_at": datetime.now(tz=UTC).isoformat(),
        "database": db_name,
        "connection_hosts": _connection_hosts(uri),
        "server": {
            "version": server_info.get("version"),
            "versionArray": server_info.get("versionArray"),
            "modules": server_info.get("modules", []),
        },
        "collection_count": len(collections),
        "collections": collections,
        "write_probe": write_probe_result,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database", default=_env("MONGO_DB_NAME"))
    parser.add_argument("--uri-env", default="MONGODB_URI")
    parser.add_argument("--server-selection-timeout-ms", type=int, default=15000)
    parser.add_argument("--write-probe", action="store_true")
    parser.add_argument("--probe-collection", default="_migration_probe")
    args = parser.parse_args()

    uri = _env(args.uri_env)
    if not uri:
        raise SystemExit(f"{args.uri_env} is required")
    if not args.database:
        raise SystemExit("MONGO_DB_NAME or --database is required")

    with MongoClient(uri, serverSelectionTimeoutMS=args.server_selection_timeout_ms) as client:
        report = run_smoke(
            client,
            db_name=args.database,
            uri=uri,
            write_probe=args.write_probe,
            probe_collection=args.probe_collection,
        )
    print(json.dumps(report, ensure_ascii=False, indent=2, default=str))


if __name__ == "__main__":
    main()
