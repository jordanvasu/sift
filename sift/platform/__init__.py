"""
Platform abstraction layer.
"""

import sys
from sift.platform.base import ClipboardMonitor, ClipboardItem, ContentType


def get_monitor() -> ClipboardMonitor:
    if sys.platform == "darwin":
        from sift.platform.macos import MacOSClipboardMonitor
        return MacOSClipboardMonitor()
    elif sys.platform == "win32":
        from sift.platform.windows import WindowsClipboardMonitor
        return WindowsClipboardMonitor()
    elif sys.platform.startswith("linux"):
        from sift.platform.linux import LinuxClipboardMonitor
        return LinuxClipboardMonitor()
    else:
        raise RuntimeError(f"Unsupported platform: {sys.platform}")


__all__ = ["get_monitor", "ClipboardMonitor", "ClipboardItem", "ContentType"]
