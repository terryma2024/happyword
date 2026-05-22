from scripts import db_inventory


def test_connection_hosts_redacts_credentials() -> None:
    hosts = db_inventory._connection_hosts(
        "mongodb+srv://user:secret@example.mongodb.net/?retryWrites=true"
    )

    assert hosts == ["example.mongodb.net"]


def test_markdown_marks_ttl_and_unique_indexes() -> None:
    report = {
        "generated_at": "2026-05-23T00:00:00+00:00",
        "database": "happyword",
        "server": {"version": "8.0.0"},
        "collection_count": 1,
        "total_document_count": 2,
        "collections": [
            {
                "name": "sessions",
                "document_count": 2,
                "indexes": [
                    {"name": "_id_", "keys": [("_id", 1)]},
                    {"name": "token_1", "keys": [("token", 1)], "unique": True},
                    {
                        "name": "expires_at_1",
                        "keys": [("expires_at", 1)],
                        "expireAfterSeconds": 0,
                    },
                ],
                "ttl_indexes": [
                    {
                        "name": "expires_at_1",
                        "keys": [("expires_at", 1)],
                        "expireAfterSeconds": 0,
                    }
                ],
                "unique_indexes": [
                    {"name": "token_1", "keys": [("token", 1)], "unique": True}
                ],
                "stats": {"size": 128},
            }
        ],
    }

    markdown = db_inventory.to_markdown(report)

    assert "| sessions | 2 | 3 | 1 | 1 | 128 |" in markdown
    assert "`token_1`: `[('token', 1)]` (unique)" in markdown
    assert "`expires_at_1`: `[('expires_at', 1)]` (ttl=0s)" in markdown
