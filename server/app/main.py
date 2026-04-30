import time

from fastapi import FastAPI

app = FastAPI(title="happyword-server", version="0.5.1")


@app.get("/api/v1/health")
async def health() -> dict[str, object]:
    return {"ok": True, "ts": int(time.time())}
