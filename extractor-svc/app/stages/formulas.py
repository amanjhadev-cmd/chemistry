"""
Stage 6: formula + chemical-equation extraction.

Pure regex — no symbolic parsing. We detect:
  - LaTeX-delimited:    $...$ or \[...\]
  - Plain equations:    "ΔT_b = K_b × m" or "M = n / V"
  - Chemical reactions: "2H2 + O2 → 2H2O", "AgNO3 + NaCl → AgCl + NaNO3"
  - Named formulas:     "Formula: ..." / "where ..."
"""
from __future__ import annotations

import re

from app.schemas import Formula


LATEX_INLINE = re.compile(r"\$([^$\n]{2,200})\$")
LATEX_BLOCK = re.compile(r"\\\[([^\]]{2,400})\\\]")

# An equation-like line: contains "=" or "→" and at least one math-y token.
PLAIN_EQ_LINE = re.compile(
    r"^[^\n]*?[A-Za-zΔΣπθρμ_][A-Za-z0-9_]*\s*(?:=|→|↔|⇌)\s*[^\n]{1,200}$"
)

# Chemical species token: 1-2 capital letters, optional lowercase, optional digit subscript.
CHEM_TOKEN = re.compile(r"\b[A-Z][a-z]?\d*\b")
CHEM_REACTION = re.compile(
    r"([A-Z][A-Za-z0-9_+\-\(\)\s]*?)(?:\s*[+]\s*[A-Z][A-Za-z0-9_+\-\(\)\s]*?)*\s*(?:→|↔|⇌|->)\s*([A-Z][A-Za-z0-9_+\-\(\)\s]*?)(?:\s*[+]\s*[A-Z][A-Za-z0-9_+\-\(\)\s]*?)*"
)

NAMED_FORMULA = re.compile(r"^\s*Formula\s*:\s*(.+)$", re.I | re.M)


def extract_formulas(pages_text: list[str], section_lookup) -> list[Formula]:
    out: list[Formula] = []
    seq = 0
    seen: set[str] = set()

    def add(latex: str, page_1based: int) -> None:
        nonlocal seq
        key = latex.lower().strip()
        if key in seen or len(key) < 3:
            return
        seen.add(key)
        seq += 1
        out.append(
            Formula(
                id=f"f_{seq}",
                latex=latex.strip()[:200],
                page=page_1based,
                section_id=section_lookup(page_1based),
            )
        )

    for page_idx, page in enumerate(pages_text):
        page_1based = page_idx + 1

        for m in LATEX_INLINE.finditer(page):
            add(m.group(1), page_1based)
        for m in LATEX_BLOCK.finditer(page):
            add(m.group(1), page_1based)
        for m in NAMED_FORMULA.finditer(page):
            add(m.group(1), page_1based)

        for line in page.splitlines():
            line = line.strip()
            if 5 < len(line) < 200 and PLAIN_EQ_LINE.match(line):
                add(line, page_1based)
            # Chemical reactions
            for m in CHEM_REACTION.finditer(line):
                snippet = m.group(0)
                # Sanity: must contain at least 2 chemical tokens to count.
                if len(CHEM_TOKEN.findall(snippet)) >= 2:
                    add(snippet, page_1based)

    return out
