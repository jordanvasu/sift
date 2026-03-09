"""
Abstract base classes for platform-agnostic clipboard monitoring.
"""

from __future__ import annotations

import hashlib
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum, auto
from typing import Callable, Optional
from PIL import Image


class ContentType(Enum):
    TEXT = auto()
    IMAGE = auto()
    URL = auto()
    CODE = auto()
    UNKNOWN = auto()


@dataclass
class ClipboardItem:
    content_type: ContentType
    timestamp: datetime = field(default_factory=datetime.utcnow)
    text: Optional[str] = None
    image: Optional[Image.Image] = None
    source_app: Optional[str] = None
    content_hash: str = ""

    def __post_init__(self):
        if not self.content_hash:
            self.content_hash = self._compute_hash()

    def _compute_hash(self) -> str:
        if self.text is not None:
            return hashlib.sha256(self.text.encode()).hexdigest()
        if self.image is not None:
            return hashlib.sha256(self.image.tobytes()).hexdigest()
        return ""


ClipboardCallback = Callable[[ClipboardItem], None]


class ClipboardMonitor(ABC):

    def __init__(self):
        self._callback: Optional[ClipboardCallback] = None
        self._running: bool = False
        self._last_hash: str = ""

    def on_change(self, callback: ClipboardCallback) -> None:
        self._callback = callback

    @abstractmethod
    def start(self) -> None: ...

    @abstractmethod
    def stop(self) -> None: ...

    @abstractmethod
    def read(self) -> Optional[ClipboardItem]: ...

    def _emit(self, item: ClipboardItem) -> None:
        if item.content_hash == self._last_hash:
            return
        self._last_hash = item.content_hash
        if self._callback is not None:
            self._callback(item)
