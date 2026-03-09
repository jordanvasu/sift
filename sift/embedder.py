"""Embedding module — text via sentence-transformers, image via CLIP."""

from __future__ import annotations

import threading
from typing import List

from PIL import Image

_text_model = None
_clip_model = None
_clip_preprocess = None
_clip_tokenizer = None
_lock = threading.Lock()


def _load_text_model():
    global _text_model
    if _text_model is None:
        from sentence_transformers import SentenceTransformer
        _text_model = SentenceTransformer("all-MiniLM-L6-v2")
    return _text_model


def _load_clip_model():
    global _clip_model, _clip_preprocess, _clip_tokenizer
    if _clip_model is None:
        import open_clip
        _clip_model, _, _clip_preprocess = open_clip.create_model_and_transforms("ViT-B-32", pretrained="openai")
        _clip_tokenizer = open_clip.get_tokenizer("ViT-B-32")
        _clip_model.eval()
    return _clip_model, _clip_preprocess, _clip_tokenizer


def embed_text(text: str) -> List[float]:
    with _lock:
        model = _load_text_model()
    return model.encode(text, normalize_embeddings=True).tolist()


def embed_image(image: Image.Image) -> List[float]:
    import torch
    with _lock:
        model, preprocess, _ = _load_clip_model()
    tensor = preprocess(image).unsqueeze(0)
    with torch.no_grad():
        features = model.encode_image(tensor)
        features = features / features.norm(dim=-1, keepdim=True)
    return features.squeeze().tolist()


def embed_text_for_image_search(query: str) -> List[float]:
    import torch
    with _lock:
        model, _, tokenizer = _load_clip_model()
    tokens = tokenizer([query])
    with torch.no_grad():
        features = model.encode_text(tokens)
        features = features / features.norm(dim=-1, keepdim=True)
    return features.squeeze().tolist()
