"""
Stage 1+2+10: per-page raw text extraction + scan detection + cleaning.

Uses pdfplumber for layout-aware extraction. Falls back to PyMuPDF if a page
is unparseable. OCR is a separate optional stage in stages/ocr.py.
"""
from __future__ import annotations

import re
import unicodedata


SCAN_THRESHOLD_CHARS_PER_PAGE = 50


def extract_pages(pdf_path: str) -> list[str]:
    """Return one cleaned-text string per page. Empty string for unparseable pages."""
    import pdfplumber

    out: list[str] = []
    with pdfplumber.open(pdf_path) as pdf:
        for page in pdf.pages:
            try:
                raw = page.extract_text() or ""
            except Exception:
                raw = ""
            out.append(clean_page_text(raw))
    return out


def is_scanned(pages_text: list[str]) -> bool:
    """Heuristic: if average chars-per-page is tiny, the PDF is scanned."""
    if not pages_text:
        return True
    total = sum(len(p) for p in pages_text)
    return (total / len(pages_text)) < SCAN_THRESHOLD_CHARS_PER_PAGE


def clean_page_text(raw: str) -> str:
    """Normalize unicode, fix hyphenation, strip control chars, collapse whitespace."""
    if not raw:
        return ""
    s = unicodedata.normalize("NFKC", raw)
    # Strip control chars except \n and \t.
    s = "".join(ch for ch in s if ch in ("\n", "\t") or ord(ch) >= 0x20)
    # Repair end-of-line hyphenation: "molal-\nity" → "molality".
    s = re.sub(r"-\n(\w)", r"\1", s)
    # Collapse runs of 3+ blank lines.
    s = re.sub(r"\n{3,}", "\n\n", s)
    # Collapse repeated spaces (preserve newlines).
    s = re.sub(r"[ \t]{2,}", " ", s)
    return s.strip()


def strip_repeating_headers_footers(pages_text: list[str]) -> list[str]:
    """If the same short line appears on >=60% of pages, treat as header/footer
    and remove it. Only removes lines shorter than 80 chars to avoid eating
    real content."""
    if len(pages_text) < 3:
        return pages_text

    line_counts: dict[str, int] = {}
    for p in pages_text:
        seen_on_this_page = set()
        for line in p.splitlines():
            stripped = line.strip()
            if 0 < len(stripped) < 80 and stripped not in seen_on_this_page:
                seen_on_this_page.add(stripped)
                line_counts[stripped] = line_counts.get(stripped, 0) + 1

    threshold = max(2, int(0.6 * len(pages_text)))
    headers_footers = {line for line, n in line_counts.items() if n >= threshold}

    if not headers_footers:
        return pages_text

    cleaned: list[str] = []
    for p in pages_text:
        kept = [ln for ln in p.splitlines() if ln.strip() not in headers_footers]
        cleaned.append("\n".join(kept).strip())
    return cleaned
