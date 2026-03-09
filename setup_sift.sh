#!/bin/bash
# Run this from your repo root (the folder containing .gitignore, README.md, pyproject.toml)
# It will delete incorrect folders and recreate the correct structure.

set -e

echo "Cleaning up incorrect folders..."
rm -rf embeddings platform ocr.py search.py store.py

echo "Creating correct directory structure..."
mkdir -p sift/platform
mkdir -p ui
mkdir -p tests

echo "Creating sift/__init__.py..."
cat > sift/__init__.py << 'EOF'
"""
Sift — local-first semantic clipboard manager.
"""

__version__ = "0.1.0"
EOF

echo "Creating sift/utils.py..."
cat > sift/utils.py << 'EOF'
"""
Shared utilities used across Sift modules.
"""

from __future__ import annotations

import re
from sift.platform.base import ContentType


_URL_PATTERN = re.compile(
    r"^https?://[^\s/$.?#].[^\s]*$", re.IGNORECASE
)

_CODE_PATTERNS = [
    re.compile(r"^\s*(def |class |import |from |#!|//|/\*|\{|\[)"),
    re.compile(r"[{};]\s*$", re.MULTILINE),
    re.compile(r"^\s*<[a-zA-Z][^>]*>"),
]


def classify_text(text: str) -> ContentType:
    stripped = text.strip()
    if not stripped:
        return ContentType.UNKNOWN
    if _URL_PATTERN.match(stripped):
        return ContentType.URL
    for pattern in _CODE_PATTERNS:
        if pattern.search(stripped):
            return ContentType.CODE
    return ContentType.TEXT
EOF

echo "Creating sift/platform/__init__.py..."
cat > sift/platform/__init__.py << 'EOF'
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
EOF

echo "Creating sift/platform/base.py..."
cat > sift/platform/base.py << 'EOF'
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
EOF

echo "Creating sift/platform/macos.py..."
cat > sift/platform/macos.py << 'EOF'
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
EOF

echo "Creating sift/platform/windows.py..."
cat > sift/platform/windows.py << 'EOF'
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
EOF

echo "Creating sift/platform/linux.py..."
cat > sift/platform/linux.py << 'EOF'
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
EOF

echo "Creating sift/embedder.py..."
cat > sift/embedder.py << 'EOF'
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
EOF

echo "Creating sift/ocr.py..."
cat > sift/ocr.py << 'EOF'
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
EOF

echo "Creating sift/store.py..."
cat > sift/store.py << 'EOF'
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
EOF

echo "Creating sift/search.py..."
cat > sift/search.py << 'EOF'
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
EOF

echo "Creating sift/daemon.py..."
cat > sift/daemon.py << 'EOF'
"""Sift background daemon."""

from __future__ import annotations

import argparse
import logging
import signal
import sys
from concurrent.futures import ThreadPoolExecutor

from sift.platform import get_monitor
from sift.platform.base import ClipboardItem, ContentType
from sift.embedder import embed_text, embed_image
from sift.ocr import extract_text
from sift.store import SiftStore

logger = logging.getLogger("sift.daemon")


def process_item(item: ClipboardItem, store: SiftStore) -> None:
    if store.hash_exists(item.content_hash):
        return
    if item.content_type == ContentType.IMAGE and item.image is not None:
        ocr_text = extract_text(item.image)
        embedding = embed_image(item.image)
        store.add_image_item(item, embedding, ocr_text=ocr_text)
    elif item.text:
        embedding = embed_text(item.text)
        store.add_text_item(item, embedding)


def main():
    parser = argparse.ArgumentParser(description="Sift clipboard daemon")
    parser.add_argument("--quiet", action="store_true")
    parser.add_argument("--data-dir", type=str, default=None)
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.WARNING if args.quiet else logging.INFO,
        format="%(asctime)s [siftd] %(levelname)s %(message)s",
    )

    store = SiftStore(data_dir=args.data_dir)
    monitor = get_monitor()
    executor = ThreadPoolExecutor(max_workers=2)

    def on_clipboard_change(item: ClipboardItem) -> None:
        executor.submit(process_item, item, store)

    monitor.on_change(on_clipboard_change)

    def shutdown(sig, frame):
        monitor.stop()
        executor.shutdown(wait=False)
        sys.exit(0)

    signal.signal(signal.SIGINT, shutdown)
    signal.signal(signal.SIGTERM, shutdown)

    logger.info("siftd started.")
    monitor.start()

    if sys.platform == "win32":
        import time
        while True:
            time.sleep(1)
    else:
        signal.pause()


if __name__ == "__main__":
    main()
EOF

echo "Creating sift/cli.py..."
cat > sift/cli.py << 'EOF'
"""Sift CLI — search clipboard history."""

from __future__ import annotations

import argparse
import sys

from rich.console import Console
from rich.table import Table

from sift.store import SiftStore
from sift.search import search

console = Console()


def main():
    parser = argparse.ArgumentParser(description="Search your clipboard history.")
    parser.add_argument("query", nargs="?")
    parser.add_argument("--n", type=int, default=10)
    parser.add_argument("--no-images", action="store_true")
    parser.add_argument("--data-dir", type=str, default=None)
    args = parser.parse_args()

    if not args.query:
        parser.print_help()
        sys.exit(0)

    store = SiftStore(data_dir=args.data_dir)
    results = search(args.query, store=store, n=args.n, include_images=not args.no_images)

    if not results:
        console.print("[yellow]No results found.[/yellow]")
        return

    table = Table(show_header=True, header_style="bold cyan")
    table.add_column("Score", width=6)
    table.add_column("Type", width=8)
    table.add_column("When", width=20)
    table.add_column("Preview")

    for r in results:
        score = f"{r.get('score', 0):.2f}"
        content_type = r.get("content_type", "?")
        timestamp = r.get("timestamp", "")[:19].replace("T", " ")
        if content_type == "IMAGE":
            preview = f"[dim][image] {r.get('ocr_text', '')[:80]}[/dim]"
        else:
            preview = (r.get("text_preview") or r.get("document", ""))[:80]
        table.add_row(score, content_type, timestamp, preview)

    console.print(table)


if __name__ == "__main__":
    main()
EOF

echo "Creating ui/app.py..."
cat > ui/__init__.py << 'EOF'
EOF
cat > ui/app.py << 'EOF'
"""Sift local web UI."""

from __future__ import annotations

from typing import Optional

from fastapi import FastAPI, Query
from fastapi.responses import FileResponse, JSONResponse

from sift.store import SiftStore
from sift.search import search as sift_search

app = FastAPI(title="Sift", version="0.1.0")
_store: Optional[SiftStore] = None


def get_store() -> SiftStore:
    global _store
    if _store is None:
        _store = SiftStore()
    return _store


@app.get("/api/search")
def search_endpoint(q: str = Query(...), n: int = Query(10, ge=1, le=50), images: bool = Query(True)):
    results = sift_search(q, store=get_store(), n=n, include_images=images)
    return JSONResponse(content={"results": results})


@app.get("/api/thumbnail/{item_id}")
def get_thumbnail(item_id: str):
    path = get_store()._thumbnail_dir / f"{item_id}.jpg"
    if path.exists():
        return FileResponse(path, media_type="image/jpeg")
    return JSONResponse(status_code=404, content={"error": "Not found"})


@app.get("/health")
def health():
    return {"status": "ok"}
EOF

echo "Creating tests/test_core.py..."
cat > tests/__init__.py << 'EOF'
EOF
cat > tests/test_core.py << 'EOF'
from sift.utils import classify_text
from sift.platform.base import ContentType


def test_classify_url():
    assert classify_text("https://github.com/sift") == ContentType.URL

def test_classify_code_python():
    assert classify_text("def hello():\n    return 'world'") == ContentType.CODE

def test_classify_plain_text():
    assert classify_text("This is a plain sentence.") == ContentType.TEXT

def test_classify_empty():
    assert classify_text("   ") == ContentType.UNKNOWN

def test_clipboard_item_hash():
    from sift.platform.base import ClipboardItem
    item1 = ClipboardItem(content_type=ContentType.TEXT, text="hello")
    item2 = ClipboardItem(content_type=ContentType.TEXT, text="hello")
    item3 = ClipboardItem(content_type=ContentType.TEXT, text="world")
    assert item1.content_hash == item2.content_hash
    assert item1.content_hash != item3.content_hash
EOF

echo ""
echo "Done. Your structure should now look like:"
echo ""
echo "sift/                  <- repo root"
echo "├── .gitignore"
echo "├── README.md"
echo "├── pyproject.toml"
echo "├── sift/"
echo "│   ├── __init__.py"
echo "│   ├── cli.py"
echo "│   ├── daemon.py"
echo "│   ├── embedder.py"
echo "│   ├── monitor.py     <- move from old location if present"
echo "│   ├── ocr.py"
echo "│   ├── search.py"
echo "│   ├── store.py"
echo "│   ├── utils.py"
echo "│   └── platform/"
echo "│       ├── __init__.py"
echo "│       ├── base.py"
echo "│       ├── linux.py"
echo "│       ├── macos.py"
echo "│       └── windows.py"
echo "├── ui/"
echo "│   ├── __init__.py"
echo "│   └── app.py"
echo "└── tests/"
echo "    ├── __init__.py"
echo "    └── test_core.py"
