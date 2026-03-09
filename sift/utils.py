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
