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
