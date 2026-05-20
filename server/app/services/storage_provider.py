"""Runtime storage-provider selection for backend-owned assets."""

import os
from typing import Literal

StorageProvider = Literal["vercel_blob", "tencent_cos", "cloudbase_storage"]


def current_provider() -> StorageProvider:
    raw = os.environ.get("ASSET_STORAGE_PROVIDER", "vercel_blob").strip().lower()
    if raw in {"vercel_blob", "tencent_cos", "cloudbase_storage"}:
        return raw  # type: ignore[return-value]
    raise RuntimeError(f"Unsupported ASSET_STORAGE_PROVIDER={raw!r}")
