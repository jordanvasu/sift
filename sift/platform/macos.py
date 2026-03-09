"""macOS clipboard monitor."""

from __future__ import annotations

import subprocess
import threading
import time
from typing import Optional

import pyperclip
from PIL import ImageGrab

from sift.platform.base import ClipboardItem, ClipboardMonitor, ContentType
from sift.utils import classify_text

POLL_INTERVAL = 0.5


class MacOSClipboardMonitor(ClipboardMonitor):

    def __init__(self, poll_interval: float = POLL_INTERVAL):
        super().__init__()
        self._interval = poll_interval
        self._thread: Optional[threading.Thread] = None

    def start(self) -> None:
        self._running = True
        self._thread = threading.Thread(target=self._poll, daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._running = False
        if self._thread:
            self._thread.join(timeout=2.0)

    def read(self) -> Optional[ClipboardItem]:
        try:
            image = ImageGrab.grabclipboard()
            if image is not None:
                return ClipboardItem(
                    content_type=ContentType.IMAGE,
                    image=image,
                    source_app=self._get_source_app(),
                )
        except Exception:
            pass
        try:
            text = pyperclip.paste()
            if text:
                return ClipboardItem(
                    content_type=classify_text(text),
                    text=text,
                    source_app=self._get_source_app(),
                )
        except Exception:
            pass
        return None

    def _poll(self) -> None:
        while self._running:
            item = self.read()
            if item:
                self._emit(item)
            time.sleep(self._interval)

    def _get_source_app(self) -> Optional[str]:
        try:
            result = subprocess.run(
                ["osascript", "-e", 'tell application "System Events" to get name of first application process whose frontmost is true'],
                capture_output=True, text=True, timeout=1.0,
            )
            return result.stdout.strip() or None
        except Exception:
            return None
