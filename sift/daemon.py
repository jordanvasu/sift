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
