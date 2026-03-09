"""
Clipboard monitor: detects changes and emits ClipboardEntry objects.
Platform-agnostic. Delegates OS calls to the active backend.
"""

import hashlib
import time
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from typing import Callable

from PIL import Image

from .platform import get_backend


class ContentType(str, Enum):
    TEXT = "text"
    IMAGE = "image"
    CODE = "code"      # detected via heuristics
    URL = "url"        # detected via prefix match


@dataclass
class ClipboardEntry:
    id: str = field(default_factory=lambda: str(uuid.uuid4()))
    content_type: ContentType = ContentType.TEXT
    text: str | None = None
    image: Image.Image | None = None
    image_ocr_text: str | None = None   # populated later by OCR pipeline
    timestamp: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    hash: str = ""                      # dedup fingerprint
    source_app: str | None = None       # best-effort, platform-specific

    def __post_init__(self):
        if not self.hash:
            self.hash = _compute_hash(self)


def _compute_hash(entry: ClipboardEntry) -> str:
    h = hashlib.sha256()
    if entry.text:
        h.update(entry.text.encode())
    if entry.image:
        h.update(entry.image.tobytes())
    return h.hexdigest()


def _detect_content_type(text: str | None) -> ContentType:
    if text is None:
        return ContentType.IMAGE
    t = text.strip()
    if t.startswith(("http://", "https://", "ftp://")):
        return ContentType.URL
    # Rough code heuristic: multiple lines with indentation or brackets
    lines = t.splitlines()
    if len(lines) > 2 and any(
        l.startswith(("    ", "\t", "def ", "class ", "import ", "function ", "{", "}"))
        for l in lines
    ):
        return ContentType.CODE
    return ContentType.TEXT


class ClipboardMonitor:
    """
    Watches the clipboard and fires `on_entry` with a new ClipboardEntry
    each time the content changes. Skips duplicate entries by hash.
    """

    def __init__(
        self,
        on_entry: Callable[[ClipboardEntry], None],
        poll_interval: float = 0.5,
    ):
        self._on_entry = on_entry
        self._interval = poll_interval
        self._backend = get_backend()
        self._last_hash: str | None = None

    def start(self) -> None:
        self._backend.watch(self._handle_change, self._interval)

    def stop(self) -> None:
        self._backend.stop()

    def _handle_change(self) -> None:
        text = self._backend.get_text()
        image = self._backend.get_image() if text is None else None

        if text is None and image is None:
            return

        content_type = _detect_content_type(text)
        entry = ClipboardEntry(
            content_type=content_type,
            text=text,
            image=image,
        )

        # Skip if content hasn't actually changed (some platforms fire spuriously)
        if entry.hash == self._last_hash:
            return

        self._last_hash = entry.hash
        self._on_entry(entry)
