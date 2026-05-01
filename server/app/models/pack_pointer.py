"""PackPointer — single-row pointer to the currently published WordPack.

A separate `pack_pointer` collection (with one document keyed by
`singleton_key="main"`) is used instead of an attribute on WordPack so
that `POST /admin/packs/rollback` is a single-document atomic write
rather than a two-document update. We keep `previous_version` so that
rollback is reversible without scanning the WordPack history.
"""

from typing import Annotated, Literal

from beanie import Document, Indexed


class PackPointer(Document):
    # The pointer is a singleton — there's exactly one row at any time
    # with `singleton_key == "main"`. Indexed(unique=True) on a non-`_id`
    # field is safe (V0.5.1's bug was specifically on `_id`).
    singleton_key: Annotated[Literal["main"], Indexed(unique=True)] = "main"
    current_version: int
    previous_version: int | None = None

    class Settings:
        name = "pack_pointer"
