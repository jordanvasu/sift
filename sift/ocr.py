"""OCR module — extracts text from images via Tesseract."""

from __future__ import annotations

from typing import Optional
from PIL import Image


def extract_text(image: Image.Image) -> Optional[str]:
    try:
        import pytesseract
        text = pytesseract.image_to_string(image).strip()
        return text if text else None
    except Exception:
        return None
