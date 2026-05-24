from scripts import db_connectivity_smoke


class FakeInsertResult:
    acknowledged = True


class FakeDeleteResult:
    deleted_count = 1


class FakeCollection:
    def __init__(self) -> None:
        self.documents: dict[str, dict[str, object]] = {}

    def insert_one(self, document: dict[str, object]) -> FakeInsertResult:
        self.documents[str(document["_id"])] = document
        return FakeInsertResult()

    def find_one(
        self, query: dict[str, object], projection: dict[str, int]
    ) -> dict[str, object] | None:
        _ = projection
        document = self.documents.get(str(query["_id"]))
        return {"_id": document["_id"]} if document else None

    def delete_one(self, query: dict[str, object]) -> FakeDeleteResult:
        self.documents.pop(str(query["_id"]))
        return FakeDeleteResult()


class FakeDatabase:
    def __init__(self) -> None:
        self.probe = FakeCollection()

    def list_collection_names(self) -> list[str]:
        return ["words", "system.profile", "users"]

    def __getitem__(self, name: str) -> FakeCollection:
        assert name == "_migration_probe"
        return self.probe


class FakeAdmin:
    def __init__(self) -> None:
        self.commands: list[str] = []

    def command(self, name: str) -> dict[str, int]:
        self.commands.append(name)
        return {"ok": 1}


class FakeClient:
    def __init__(self) -> None:
        self.admin = FakeAdmin()
        self.db = FakeDatabase()

    def server_info(self) -> dict[str, object]:
        return {"version": "8.0.23", "versionArray": [8, 0, 23], "modules": []}

    def __getitem__(self, name: str) -> FakeDatabase:
        assert name == "happyword"
        return self.db


def test_read_only_smoke_redacts_host_and_filters_system_collections() -> None:
    client = FakeClient()

    report = db_connectivity_smoke.run_smoke(
        client,
        db_name="happyword",
        uri="mongodb+srv://user:secret@example.mongodb.net/?retryWrites=true",
    )

    assert report["ok"] is True
    assert report["connection_hosts"] == ["example.mongodb.net"]
    assert report["server"]["version"] == "8.0.23"
    assert report["collections"] == ["users", "words"]
    assert report["collection_count"] == 2
    assert report["write_probe"] == {"enabled": False}
    assert client.admin.commands == ["ping"]


def test_write_probe_inserts_reads_and_deletes_probe_document() -> None:
    client = FakeClient()

    report = db_connectivity_smoke.run_smoke(
        client,
        db_name="happyword",
        uri="mongodb://localhost:27017",
        write_probe=True,
    )

    assert report["write_probe"]["enabled"] is True
    assert report["write_probe"]["collection"] == "_migration_probe"
    assert report["write_probe"]["insert_acknowledged"] is True
    assert report["write_probe"]["read_back"] is True
    assert report["write_probe"]["deleted_count"] == 1
    assert client.db.probe.documents == {}
