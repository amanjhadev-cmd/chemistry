"""
Stage 3+4: heading detection + section tree builder.

Pure-regex heuristic — no font-size analysis (would need PyMuPDF
per-character traversal which is expensive). Recognizes:

  - "1.2 Heading Text"      (numbered, decimal)
  - "Chapter 5: Title"
  - "## Title"              (markdown-ish if present)
  - ALL CAPS LINES (short)  (last-resort heuristic)
"""
from __future__ import annotations

import re
import uuid

from app.schemas import Section


HEADING_PATTERNS = [
    re.compile(r"^\s*(\d+(?:\.\d+)+)\s+([A-Z][^\n]{2,80})\s*$"),
    re.compile(r"^\s*(Chapter\s+\d+)\s*[:\-]\s*([^\n]{2,100})\s*$", re.I),
    re.compile(r"^\s*##\s+([^\n]{2,100})\s*$"),
    re.compile(r"^\s*([A-Z][A-Z\s]{4,60})\s*$"),  # ALL CAPS short lines
]


def detect_headings(pages_text: list[str]) -> list[tuple[int, str]]:
    """Return list of (page_index_0based, heading_text)."""
    out: list[tuple[int, str]] = []
    for page_idx, page in enumerate(pages_text):
        for raw_line in page.splitlines():
            line = raw_line.strip()
            if not line or len(line) > 120:
                continue
            for pat in HEADING_PATTERNS:
                m = pat.match(line)
                if m:
                    # Use the last capture group as the heading text.
                    heading = m.group(m.lastindex) if m.lastindex else line
                    # Skip false positives that are really just sentences.
                    if heading.endswith(".") or heading.endswith(","):
                        break
                    out.append((page_idx, line))
                    break
    return out


def build_sections(pages_text: list[str]) -> list[Section]:
    """Build a flat list of sections (one Section per detected heading).
    Section.text contains all body text between this heading and the next."""
    headings = detect_headings(pages_text)
    if not headings:
        # No headings: emit one big section covering all pages.
        return [
            Section(
                id="sec_1",
                heading="(no heading detected)",
                page_range=[1, len(pages_text)],
                text="\n\n".join(pages_text).strip(),
            )
        ]

    # Materialize the full doc as a single string with page markers so we can
    # slice on heading positions without losing page numbers.
    doc_pieces: list[tuple[int, str]] = []  # (page_1based, page_text)
    for i, p in enumerate(pages_text, start=1):
        doc_pieces.append((i, p))

    sections: list[Section] = []
    heading_set = {(pi, line) for pi, line in headings}

    # Walk page-by-page; whenever we hit a heading, close the previous section
    # and start a new one.
    current_heading: str | None = None
    current_start_page: int = 1
    current_buf: list[str] = []
    seq = 0

    def flush(end_page: int) -> None:
        nonlocal seq
        seq += 1
        text = "\n".join(current_buf).strip()
        if not text and not current_heading:
            return
        sections.append(
            Section(
                id=f"sec_{seq}",
                heading=current_heading or "(preamble)",
                page_range=[current_start_page, end_page],
                text=text,
            )
        )

    for page_idx, page_text in enumerate(pages_text):
        page_1based = page_idx + 1
        for line in page_text.splitlines():
            if (page_idx, line) in heading_set:
                # Close previous section.
                flush(page_1based)
                current_heading = line.strip()
                current_start_page = page_1based
                current_buf = []
            else:
                current_buf.append(line)

    flush(len(pages_text))
    # Filter empty preambles
    return [s for s in sections if s.text or s.heading != "(preamble)"]


def find_section_id_for_page(sections: list[Section], page_1based: int) -> str | None:
    """Return the id of the section that contains the given page, if any."""
    for s in sections:
        if not s.page_range:
            continue
        lo, hi = s.page_range[0], s.page_range[-1]
        if lo <= page_1based <= hi:
            return s.id
    return None
