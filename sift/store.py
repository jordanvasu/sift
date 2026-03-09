"""ChromaDB storage layer."""

from __future__ import annotations

from datetime import datetime
from pathlib import Path
from typing import List, Optional

import chromadb
from platformdirs import user_data_dir
from PIL import Image

from sift.platform.base import ClipboardItem, ContentType

_DEFAULT_DATA_DIR = Path(user_data_dir("sift", "sift"))
_THUMBNAIL_SIZE = (256, 256)


class SiftStore:

    def __init__(self, data_dir: Optional[Path] = None):
        self._dir = data_dir or _DEFAULT_DATA_DIR
        self._dir.mkdir(parents=True, exist_ok=True)
        self._thumbnail_dir = self._dir / "thumbnails"
        self._thumbnail_dir.mkdir(exist_ok=True)
        self._client = chromadb.PersistentClient(path=str(self._dir / "chroma"))
        self._text_col = self._client.get_or_create_collection("sift_text", metadata={"hnsw:space": "cosine"})
        self._image_col = self._client.get_or_create_collection("sift_images", metadata={"hnsw:space": "cosine"})

    def add_text_item(self, item: ClipboardItem, embedding: List[float]) -> None:
        assert item.text is not None
        self._text_col.add(
            ids=[item.content_hash],
            embeddings=[embedding],
            metadatas=[{"content_type": item.content_type.name, "timestamp": item.timestamp.isoformat(), "source_app": item.source_app or "", "text_preview": item.text[:200]}],
            documents=[item.text],
        )

    def add_image_item(self, item: ClipboardItem, embedding: List[float], ocr_text: Optional[str] = None) -> None:
        assert item.image is not None
        thumbnail_path = self._save_thumbnail(item.content_hash, item.image)
        self._image_col.add(
            ids=[item.content_hash],
            embeddings=[embedding],
            metadatas=[{"content_type": "IMAGE", "timestamp": item.timestamp.isoformat(), "source_app": item.source_app or "", "ocr_text": ocr_text or "", "thumbnail_path": str(thumbnail_path)}],
            documents=[ocr_text or ""],
        )

    def search_text(self, embedding: List[float], n: int = 10) -> List[dict]:
        count = self._text_col.count()
        if count == 0:
            return []
        results = self._text_col.query(query_embeddings=[embedding], n_results=min(n, count), include=["metadatas", "documents", "distances"])
        return self._format_results(results)

    def search_images(self, embedding: List[float], n: int = 10) -> List[dict]:
        count = self._image_col.count()
        if count == 0:
            return []
        results = self._image_col.query(query_embeddings=[embedding], n_results=min(n, count), include=["metadatas", "distances"])
        return self._format_results(results)

    def hash_exists(self, content_hash: str) -> bool:
        try:
            self._text_col.get(ids=[content_hash])
            return True
        except Exception:
            pass
        try:
            self._image_col.get(ids=[content_hash])
            return True
        except Exception:
            pass
        return False

    def _save_thumbnail(self, content_hash: str, image: Image.Image) -> Path:
        path = self._thumbnail_dir / f"{content_hash}.jpg"
        thumb = image.copy()
        thumb.thumbnail(_THUMBNAIL_SIZE)
        thumb.convert("RGB").save(path, "JPEG", quality=85)
        return path

    @staticmethod
    def _format_results(results: dict) -> List[dict]:
        out = []
        if not results or not results.get("ids"):
            return out
        for i, item_id in enumerate(results["ids"][0]):
            entry = {"id": item_id}
            if results.get("metadatas"):
                entry.update(results["metadatas"][0][i])
            if results.get("documents"):
                entry["document"] = results["documents"][0][i]
            if results.get("distances"):
                entry["score"] = 1 - results["distances"][0][i]
            out.append(entry)
        return out
