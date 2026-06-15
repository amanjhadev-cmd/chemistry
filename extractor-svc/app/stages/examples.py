"""
Stage 8: example/activity/theorem/illustration extraction.

Recognizes the NCERT-style block markers and captures the body up to the next
similar marker or a heading-shaped line.
"""
from __future__ import annotations

import re

from app.schemas import Example


BLOCK_KINDS = {
    "Example": "example",
    "Illustration": "illustration",
    "Activity": "activity",
    "Theorem": "theorem",
    "Problem": "example",
}

# Matches "Example 1.2:" / "Activity 3" / "Theorem 5.1 -" at start of line.
BLOCK_HEAD = re.compile(
    r"^\s*(Example|Illustration|Activity|Theorem|Problem)\s*([\d\.]+)?\s*[:\-]?\s*(.*)$",
    re.I,
)


def extract_examples(pages_text: list[str], section_lookup) -> list[Example]:
    out: list[Example] = []
    seq = 0
    for page_idx, page in enumerate(pages_text):
        page_1based = page_idx + 1
        lines = page.splitlines()
        i = 0
        while i < len(lines):
            line = lines[i]
            m = BLOCK_HEAD.match(line)
            if not m:
                i += 1
                continue
            kind_word = m.group(1).capitalize()
            kind = BLOCK_KINDS.get(kind_word, "example")
            body_lines: list[str] = [line.strip()]
            j = i + 1
            # Collect until the next block marker or a blank-line cluster.
            blank_run = 0
            while j < len(lines):
                nxt = lines[j]
                if BLOCK_HEAD.match(nxt):
                    break
                if not nxt.strip():
                    blank_run += 1
                    if blank_run >= 2:
                        break
                else:
                    blank_run = 0
                body_lines.append(nxt)
                j += 1
            body = "\n".join(body_lines).strip()
            if len(body) >= 20:
                seq += 1
                out.append(
                    Example(
                        id=f"ex_{seq}",
                        kind=kind,
                        page=page_1based,
                        text=body[:2000],
                        section_id=section_lookup(page_1based),
                    )
                )
            i = j
    return out
