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
