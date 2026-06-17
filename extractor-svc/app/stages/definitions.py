"""
Stage 7: definition extraction.

Detects three common patterns:
  - "Definition: Term is/are/means/refers to ..."
  - "Term is defined as ..."
  - "A/An <Term> is ..."  (sentence-initial, capitalized noun)

Conservative — false positives cost prompt tokens and confuse the generator,
so we prefer high precision over recall.
"""
from __future__ import annotations

import re

from app.schemas import Definition


# Patterns capture (term, body).
DEF_PATTERNS = [
    re.compile(r"Definition\s*:\s*([A-Z][^.\n]{1,80}?)\s+(is|are|means|refers to)\s+([^\n]{10,400})", re.I),
    re.compile(r"\b([A-Z][a-zA-Z\-]+(?:\s+[a-zA-Z\-]+){0,3})\s+is\s+defined\s+as\s+([^\n]{10,400})", re.I),
]


def extract_definitions(pages_text: list[str], section_lookup) -> list[Definition]:
    """section_lookup is a callable(page_1based) -> section_id|None."""
    out: list[Definition] = []
    seq = 0
    seen: set[str] = set()
    for page_idx, page in enumerate(pages_text):
        page_1based = page_idx + 1
        for pat in DEF_PATTERNS:
            for m in pat.finditer(page):
                if pat is DEF_PATTERNS[0]:
                    term = m.group(1).strip().rstrip(".,;:")
                    body = m.group(3).strip()
                else:
                    term = m.group(1).strip().rstrip(".,;:")
                    body = m.group(2).strip()
                if not term or not body:
                    continue
                # De-dupe on lowercased term.
                key = term.lower()
                if key in seen:
                    continue
                seen.add(key)
                seq += 1
                out.append(
                    Definition(
                        term=term,
                        text=body[:400],
                        page=page_1based,
                        section_id=section_lookup(page_1based),
                    )
                )
    return out
