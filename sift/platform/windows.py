"""Windows clipboard monitor."""

from __future__ import annotations

import io
import threading
import time
from typing import Optional

from PIL import Image

from sift.platform.base import ClipboardItem, ClipboardMonitor, ContentType
from sift.utils import classify_text

POLL_INTERVAL = 0.5


class WindowsClipboardMonitor(ClipboardMonitor):

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
            import win32clipboard
            import win32con
            win32clipboard.OpenClipboard()
            try:
                if win32clipboard.IsClipboardFormatAvailable(win32con.CF_DIB):
                    data = win32clipboard.GetClipboardData(win32con.CF_DIB)
                    image = Image.open(io.BytesIO(data))
                    return ClipboardItem(content_type=ContentType.IMAGE, image=image)
                if win32clipboard.IsClipboardFormatAvailable(win32con.CF_UNICODETEXT):
                    text = win32clipboard.GetClipboardData(win32con.CF_UNICODETEXT)
                    if text:
                        return ClipboardItem(content_type=classify_text(text), text=text)
            finally:
                win32clipboard.CloseClipboard()
        except ImportError:
            import pyperclip
            text = pyperclip.paste()
            if text:
                return ClipboardItem(content_type=classify_text(text), text=text)
        except Exception:
            pass
        return None

    def _poll(self) -> None:
        while self._running:
            item = self.read()
            if item:
                self._emit(item)
            time.sleep(self._interval)
