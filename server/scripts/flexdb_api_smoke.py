"""CloudBase FlexDB API smoke for the M7A database migration spike.

This script intentionally bypasses the local `tcb` CLI and talks to Tencent
Cloud API 3.0 directly. That makes the same probe usable from CloudBase Run
once the runtime has narrowly scoped API credentials.
"""

from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import os
import time
from datetime import UTC, datetime
from typing import Any

import httpx

TCB_ENDPOINT = "https://tcb.tencentcloudapi.com/"
TCB_HOST = "tcb.tencentcloudapi.com"
TCB_SERVICE = "tcb"
TCB_VERSION = "2018-06-08"


class CloudBaseApiError(RuntimeError):
    def __init__(self, *, code: str, message: str, request_id: str | None = None) -> None:
        super().__init__(f"{code}: {message}")
        self.code = code
        self.message = message
        self.request_id = request_id


def _env(*names: str, default: str = "") -> str:
    for name in names:
        value = os.environ.get(name, "").strip()
        if value:
            return value
    return default


def _json_dumps(payload: dict[str, Any]) -> str:
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":"))


def _sha256_hex(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _hmac_sha256(key: bytes, value: str) -> bytes:
    return hmac.new(key, value.encode("utf-8"), hashlib.sha256).digest()


class FlexDbApiClient:
    def __init__(
        self,
        *,
        env_id: str,
        tag: str,
        secret_id: str,
        secret_key: str,
        region: str = "ap-shanghai",
        http_client: httpx.Client | None = None,
        timestamp: int | None = None,
    ) -> None:
        self.env_id = env_id
        self.tag = tag
        self.secret_id = secret_id
        self.secret_key = secret_key
        self.region = region
        self._http_client = http_client
        self._timestamp = timestamp

    def _authorization(self, *, action: str, body: str, timestamp: int) -> str:
        date = datetime.fromtimestamp(timestamp, tz=UTC).strftime("%Y-%m-%d")
        canonical_headers = (
            "content-type:application/json; charset=utf-8\n"
            f"host:{TCB_HOST}\n"
            f"x-tc-action:{action.lower()}\n"
        )
        signed_headers = "content-type;host;x-tc-action"
        canonical_request = "\n".join(
            [
                "POST",
                "/",
                "",
                canonical_headers,
                signed_headers,
                _sha256_hex(body),
            ]
        )
        credential_scope = f"{date}/{TCB_SERVICE}/tc3_request"
        string_to_sign = "\n".join(
            [
                "TC3-HMAC-SHA256",
                str(timestamp),
                credential_scope,
                _sha256_hex(canonical_request),
            ]
        )
        secret_date = _hmac_sha256(("TC3" + self.secret_key).encode("utf-8"), date)
        secret_service = _hmac_sha256(secret_date, TCB_SERVICE)
        secret_signing = _hmac_sha256(secret_service, "tc3_request")
        signature = hmac.new(
            secret_signing,
            string_to_sign.encode("utf-8"),
            hashlib.sha256,
        ).hexdigest()
        return (
            "TC3-HMAC-SHA256 "
            f"Credential={self.secret_id}/{credential_scope}, "
            f"SignedHeaders={signed_headers}, "
            f"Signature={signature}"
        )

    def invoke(self, action: str, payload: dict[str, Any]) -> dict[str, Any]:
        body = _json_dumps(payload)
        timestamp = self._timestamp or int(time.time())
        headers = {
            "Authorization": self._authorization(
                action=action,
                body=body,
                timestamp=timestamp,
            ),
            "Content-Type": "application/json; charset=utf-8",
            "Host": TCB_HOST,
            "X-TC-Action": action,
            "X-TC-Region": self.region,
            "X-TC-Timestamp": str(timestamp),
            "X-TC-Version": TCB_VERSION,
        }
        client = self._http_client or httpx.Client(timeout=30.0)
        try:
            response = client.post(TCB_ENDPOINT, content=body, headers=headers)
            response.raise_for_status()
        finally:
            if self._http_client is None:
                client.close()
        envelope = response.json().get("Response", {})
        error = envelope.get("Error")
        if isinstance(error, dict):
            raise CloudBaseApiError(
                code=str(error.get("Code", "UnknownError")),
                message=str(error.get("Message", "")),
                request_id=envelope.get("RequestId"),
            )
        return envelope

    def list_tables(self) -> dict[str, Any]:
        return self.invoke(
            "ListTables",
            {
                "EnvId": self.env_id,
                "Tag": self.tag,
                "MgoLimit": 100,
                "MgoOffset": 0,
                "ShowHidden": True,
            },
        )

    def create_table(self, table_name: str) -> dict[str, Any]:
        return self.invoke(
            "CreateTable",
            {"EnvId": self.env_id, "Tag": self.tag, "TableName": table_name},
        )

    def delete_table(self, table_name: str) -> dict[str, Any]:
        return self.invoke(
            "DeleteTable",
            {"EnvId": self.env_id, "Tag": self.tag, "TableName": table_name},
        )

    def create_unique_index(self, table_name: str, *, index_name: str, field: str) -> None:
        self.invoke(
            "UpdateTable",
            {
                "EnvId": self.env_id,
                "Tag": self.tag,
                "TableName": table_name,
                "CreateIndexes": [
                    {
                        "IndexName": index_name,
                        "MgoKeySchema": {
                            "MgoIndexKeys": [{"Name": field, "Direction": "1"}],
                            "MgoIsUnique": True,
                        },
                    }
                ],
            },
        )

    def run_command(
        self,
        table_name: str,
        *,
        command_type: str,
        command: dict[str, Any],
    ) -> dict[str, Any]:
        return self.invoke(
            "RunCommands",
            {
                "EnvId": self.env_id,
                "Tag": self.tag,
                "MgoCommands": [
                    {
                        "TableName": table_name,
                        "CommandType": command_type,
                        "Command": _json_dumps(command),
                    }
                ],
            },
        )


def _contains_index(payload: dict[str, Any], index_name: str) -> bool:
    return index_name in json.dumps(payload.get("Data", []), ensure_ascii=False)


def run_smoke(
    client: FlexDbApiClient,
    *,
    table_name: str,
    cleanup: bool = True,
) -> dict[str, Any]:
    created = False
    cleanup_report: dict[str, Any] = {"enabled": cleanup, "deleted": False}
    duplicate_key_enforced = False

    try:
        initial_tables = client.list_tables()
        client.create_table(table_name)
        created = True
        client.run_command(
            table_name,
            command_type="INSERT",
            command={
                "insert": table_name,
                "documents": [
                    {
                        "_id": "probe-1",
                        "word": "apple",
                        "count": 1,
                        "nested": {"ok": True},
                    }
                ],
            },
        )
        client.run_command(
            table_name,
            command_type="QUERY",
            command={
                "find": table_name,
                "filter": {"_id": {"$eq": "probe-1"}},
                "limit": 1,
            },
        )
        client.run_command(
            table_name,
            command_type="UPDATE",
            command={
                "update": table_name,
                "updates": [
                    {
                        "q": {"_id": "probe-1"},
                        "u": {"$set": {"count": 2, "status": "updated"}},
                        "upsert": False,
                    }
                ],
            },
        )
        client.create_unique_index(table_name, index_name="word_1", field="word")
        index_payload = client.run_command(
            table_name,
            command_type="QUERY",
            command={"listIndexes": table_name},
        )
        if not _contains_index(index_payload, "word_1"):
            raise RuntimeError("word_1 index was not returned by listIndexes")
        try:
            client.run_command(
                table_name,
                command_type="INSERT",
                command={
                    "insert": table_name,
                    "documents": [{"_id": "probe-duplicate", "word": "apple"}],
                },
            )
        except CloudBaseApiError as exc:
            if "E11000" not in exc.message and "duplicate" not in exc.message.lower():
                raise
            duplicate_key_enforced = True
        if not duplicate_key_enforced:
            raise RuntimeError("unique index did not reject duplicate insert")
        return {
            "ok": True,
            "checked_at": datetime.now(tz=UTC).isoformat(),
            "env_id": client.env_id,
            "tag": client.tag,
            "probe_table": table_name,
            "initial_table_count": int((initial_tables.get("Pager") or {}).get("Total") or 0),
            "unique_index": "word_1",
            "duplicate_key_enforced": duplicate_key_enforced,
            "cleanup": cleanup_report,
        }
    finally:
        if cleanup and created:
            client.delete_table(table_name)
            cleanup_report["deleted"] = True
            cleanup_report["final_table_count"] = int(
                (client.list_tables().get("Pager") or {}).get("Total") or 0
            )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--env-id", default=_env("FLEXDB_ENV_ID", "TCB_ENV_ID"))
    parser.add_argument("--tag", default=_env("FLEXDB_TAG"))
    parser.add_argument("--region", default=_env("FLEXDB_REGION", default="ap-shanghai"))
    parser.add_argument(
        "--secret-id-env",
        default="FLEXDB_API_SECRET_ID",
        help=(
            "Env var for API secret id; falls back to TCB_SECRET_ID and "
            "TENCENTCLOUD_SECRET_ID when unset."
        ),
    )
    parser.add_argument(
        "--secret-key-env",
        default="FLEXDB_API_SECRET_KEY",
        help=(
            "Env var for API secret key; falls back to TCB_SECRET_KEY and "
            "TENCENTCLOUD_SECRET_KEY when unset."
        ),
    )
    parser.add_argument("--table-name", default=f"m7a_flexdb_probe_{int(time.time())}")
    parser.add_argument("--keep-table", action="store_true")
    args = parser.parse_args()

    secret_id = _env(args.secret_id_env, "TCB_SECRET_ID", "TENCENTCLOUD_SECRET_ID")
    secret_key = _env(args.secret_key_env, "TCB_SECRET_KEY", "TENCENTCLOUD_SECRET_KEY")
    if not args.env_id:
        raise SystemExit("FLEXDB_ENV_ID or TCB_ENV_ID is required")
    if not args.tag:
        raise SystemExit("FLEXDB_TAG is required")
    if not secret_id:
        raise SystemExit(
            f"{args.secret_id_env}, TCB_SECRET_ID, or TENCENTCLOUD_SECRET_ID is required"
        )
    if not secret_key:
        raise SystemExit(
            f"{args.secret_key_env}, TCB_SECRET_KEY, or TENCENTCLOUD_SECRET_KEY is required"
        )

    client = FlexDbApiClient(
        env_id=args.env_id,
        tag=args.tag,
        secret_id=secret_id,
        secret_key=secret_key,
        region=args.region,
    )
    report = run_smoke(client, table_name=args.table_name, cleanup=not args.keep_table)
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
