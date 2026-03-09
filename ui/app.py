"""Sift local web UI."""

from __future__ import annotations

from typing import Optional

from fastapi import FastAPI, Query
from fastapi.responses import FileResponse, JSONResponse

from sift.store import SiftStore
from sift.search import search as sift_search

app = FastAPI(title="Sift", version="0.1.0")
_store: Optional[SiftStore] = None


def get_store() -> SiftStore:
    global _store
    if _store is None:
        _store = SiftStore()
    return _store


@app.get("/api/search")
def search_endpoint(q: str = Query(...), n: int = Query(10, ge=1, le=50), images: bool = Query(True)):
    results = sift_search(q, store=get_store(), n=n, include_images=images)
    return JSONResponse(content={"results": results})


@app.get("/api/thumbnail/{item_id}")
def get_thumbnail(item_id: str):
    path = get_store()._thumbnail_dir / f"{item_id}.jpg"
    if path.exists():
        return FileResponse(path, media_type="image/jpeg")
    return JSONResponse(status_code=404, content={"error": "Not found"})


@app.get("/health")
def health():
    return {"status": "ok"}
