"""Unified search across text and image collections."""

from __future__ import annotations

from typing import List

from sift.embedder import embed_text, embed_text_for_image_search
from sift.store import SiftStore


def search(query: str, store: SiftStore, n: int = 10, include_images: bool = True) -> List[dict]:
    text_embedding = embed_text(query)
    text_results = store.search_text(text_embedding, n=n)
    image_results = []
    if include_images:
        clip_embedding = embed_text_for_image_search(query)
        image_results = store.search_images(clip_embedding, n=n)
    combined = text_results + image_results
    combined.sort(key=lambda r: r.get("score", 0), reverse=True)
    return combined[:n]
