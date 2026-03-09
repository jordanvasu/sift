"""Linux clipboard monitor."""

from __future__ import annotations

import io
import os
import subprocess
import threading
import time
from typing import Optional

from PIL import Image

from sift.platform.base import ClipboardItem, ClipboardMonitor, ContentType
from sift.utils import classify_text

POLL_INTERVAL = 0.5


def _is_wayland() -> bool:
    return bool(os.environ.get("WAYLAND_DISPLAY"))


class LinuxClipboardMonitor(ClipboardMonitor):

    def __init__(self, poll_interval: float = POLL_INTERVAL):
        super().__init__()
        self._interval = poll_interval
        self._thread: Optional[threading.Thread] = None
        self._wayland = _is_wayland()

    def start(self) -> None:
        self._running = True
        self._thread = threading.Thread(target=self._poll, daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._running = False
        if self._thread:
            self._thread.join(timeout=2.0)

    def read(self) -> Optional[ClipboardItem]:
        image = self._read_image()
        if image:
            return ClipboardItem(content_type=ContentType.IMAGE, image=image)
        text = self._read_text()
        if text:
            return ClipboardItem(content_type=classify_text(text), text=text)
        return None

    def _read_text(self) -> Optional[str]:
        try:
            cmd = ["wl-paste", "--no-newline"] if self._wayland else ["xclip", "-selection", "clipboard", "-o"]
            result = subprocess.run(cmd, capture_output=True, timeout=1.0)
            if result.returncode == 0 and result.stdout:
                return result.stdout.decode("utf-8", errors="replace").strip() or None
        except (FileNotFoundError, subprocess.TimeoutExpired):
            try:
                import pyperclip
                return pyperclip.paste() or None
            except Exception:
                pass
        except Exception:
            pass
        return None

    def _read_image(self) -> Optional[Image.Image]:
        try:
            cmd = ["wl-paste", "--type", "image/png"] if self._wayland else ["xclip", "-selection", "clipboard", "-t", "image/png", "-o"]
            result = subprocess.run(cmd, capture_output=True, timeout=1.0)
            if result.returncode == 0 and result.stdout:
                return Image.open(io.BytesIO(result.stdout))
        except Exception:
            pass
        return None

    def _poll(self) -> None:
        while self._running:
            item = self.read()
            if item:
                self._emit(item)
            time.sleep(self._interval)
