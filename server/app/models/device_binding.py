"""V0.6.2 — DeviceBinding ties one client device to one family + child profile.

Created atomically by `POST /api/v1/pair/redeem` together with a sibling
`ChildProfile` (1:1). When a device re-binds (same device_id), the previous
active binding for that device under the same family is revoked
(`revoked_at` set) but the same `child_profile_id` is reused so learning
state is preserved. Cross-family rebind always creates a fresh
ChildProfile (no leak).
"""

from datetime import datetime
from typing import Annotated

from beanie import Document, Indexed


class DeviceBinding(Document):
    binding_id: Annotated[str, Indexed(unique=True)]  # "bind-<8hex>"
    family_id: Annotated[str, Indexed()]
    device_id: Annotated[str, Indexed()]
    child_profile_id: Annotated[str, Indexed()]
    user_agent: str | None = None

    created_at: datetime
    last_seen_at: datetime | None = None
    revoked_at: datetime | None = None

    class Settings:
        name = "device_bindings"
        indexes = [
            [("family_id", 1), ("revoked_at", 1)],
            [("device_id", 1), ("revoked_at", 1)],
        ]
