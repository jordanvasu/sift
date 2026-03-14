# Sift

Local-first semantic clipboard manager with text and image search.

Search your clipboard history by meaning, not keywords. Works with text, code, URLs, and images — including screenshots. Runs entirely on your machine. No cloud. No account.

---

## Features

- Semantic search across all clipboard history using natural language
- Image search via CLIP embeddings -> find screenshots by describing what's in them
- OCR on copied images so text content is searchable too
- Cross-platform: macOS, Windows, Linux
- Fully local: No data leaves your machine

## Installation

```bash
pip install sift-clip
```

Tesseract is required for OCR (optional but recommended):

```bash
# macOS
brew install tesseract

# Ubuntu/Debian
sudo apt install tesseract-ocr

# Windows
# Download installer from https://github.com/UB-Mannheim/tesseract/wiki
```

## Usage

Start the background daemon:

```bash
siftd
```

Search your clipboard history:

```bash
sift "the API error from this morning"
sift "architecture diagram with blue boxes"
sift "that JSON I copied yesterday"
```

## Development

```bash
git clone https://github.com/yourusername/sift
cd sift
pip install -e ".[dev]"
pytest tests/
```

## License

Sift is licensed under the [Business Source License 1.1](LICENSE).

Free for personal, non-commercial use. Commercial use requires a separate license agreement. The license converts to MIT on March 9, 2030.
