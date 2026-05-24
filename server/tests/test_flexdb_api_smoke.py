import json

import httpx
import pytest

from scripts import flexdb_api_smoke


def _response(payload: dict[str, object]) -> httpx.Response:
    return httpx.Response(200, json={"Response": payload})


def test_runtime_smoke_probes_flexdb_and_cleans_up_probe_table() -> None:
    actions: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        action = request.headers["x-tc-action"]
        actions.append(action)
        if action == "ListTables":
            return _response({"Tables": [], "Pager": {"Total": 0}, "RequestId": action})
        if action in {"CreateTable", "UpdateTable", "DeleteTable"}:
            return _response({"RequestId": action})
        body = json.loads(request.content.decode("utf-8"))
        command = body["MgoCommands"][0]["Command"]
        if '"listIndexes"' in command:
            return _response(
                {
                    "Data": [
                        json.dumps(
                            [
                                {"name": "_id_", "key": {"_id": {"$numberInt": "1"}}},
                                {
                                    "name": "word_1",
                                    "unique": True,
                                    "key": {"word": {"$numberInt": "1"}},
                                },
                            ]
                        )
                    ],
                    "RequestId": "RunCommands",
                }
            )
        if "probe-duplicate" in command:
            return _response(
                {
                    "Error": {
                        "Code": "FailedOperation",
                        "Message": "E11000 duplicate key error index: word_1",
                    },
                    "RequestId": "RunCommands",
                }
            )
        return _response({"Data": ['{"ok":1}'], "RequestId": "RunCommands"})

    http_client = httpx.Client(transport=httpx.MockTransport(handler))
    client = flexdb_api_smoke.FlexDbApiClient(
        env_id="happyword-d5g66zmq8ef2430b8",
        tag="tnt-jw1cesl68",
        secret_id="secret-id",
        secret_key="secret-key",
        http_client=http_client,
        timestamp=1_700_000_000,
    )

    report = flexdb_api_smoke.run_smoke(
        client,
        table_name="m7a_flexdb_probe_test",
        cleanup=True,
    )

    assert report["ok"] is True
    assert report["env_id"] == "happyword-d5g66zmq8ef2430b8"
    assert report["tag"] == "tnt-jw1cesl68"
    assert report["probe_table"] == "m7a_flexdb_probe_test"
    assert report["duplicate_key_enforced"] is True
    assert report["cleanup"]["deleted"] is True
    assert actions == [
        "ListTables",
        "CreateTable",
        "RunCommands",
        "RunCommands",
        "RunCommands",
        "UpdateTable",
        "RunCommands",
        "RunCommands",
        "DeleteTable",
        "ListTables",
    ]


def test_runtime_smoke_deletes_probe_table_when_late_probe_step_fails() -> None:
    actions: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        action = request.headers["x-tc-action"]
        actions.append(action)
        if action == "UpdateTable":
            return _response(
                {
                    "Error": {
                        "Code": "FailedOperation",
                        "Message": "index creation failed",
                    },
                    "RequestId": action,
                }
            )
        return _response({"Tables": [], "Pager": {"Total": 0}, "RequestId": action})

    http_client = httpx.Client(transport=httpx.MockTransport(handler))
    client = flexdb_api_smoke.FlexDbApiClient(
        env_id="happyword-d5g66zmq8ef2430b8",
        tag="tnt-jw1cesl68",
        secret_id="secret-id",
        secret_key="secret-key",
        http_client=http_client,
        timestamp=1_700_000_000,
    )

    with pytest.raises(flexdb_api_smoke.CloudBaseApiError, match="index creation failed"):
        flexdb_api_smoke.run_smoke(
            client,
            table_name="m7a_flexdb_probe_test",
            cleanup=True,
        )

    assert "DeleteTable" in actions


def test_client_signing_headers_do_not_include_secret_key() -> None:
    captured_headers: dict[str, str] = {}

    def handler(request: httpx.Request) -> httpx.Response:
        captured_headers.update(request.headers)
        return _response({"Tables": [], "Pager": {"Total": 0}, "RequestId": "ok"})

    http_client = httpx.Client(transport=httpx.MockTransport(handler))
    client = flexdb_api_smoke.FlexDbApiClient(
        env_id="env",
        tag="tag",
        secret_id="AKIDexample",
        secret_key="SECRETKEYexample",
        http_client=http_client,
        timestamp=1_700_000_000,
    )

    client.list_tables()

    authorization = captured_headers["authorization"]
    assert "AKIDexample" in authorization
    assert "SECRETKEYexample" not in authorization
    assert captured_headers["x-tc-action"] == "ListTables"
