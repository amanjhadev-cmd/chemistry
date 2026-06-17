"""
Stage 11: extraction quality score.

Composite 0.0..1.0 of:
  - 0.30 text coverage     (chars/page above SCAN_THRESHOLD)
  - 0.20 section count     (at least 3 sections detected)
  - 0.15 definitions found
  - 0.15 examples found
  - 0.10 formulas found
  - 0.10 stage_warnings count (penalty)

A score >= 0.6 means the extraction is probably useful. < 0.4 means the
caller should treat results with suspicion or rerun with OCR.
"""
from __future__ import annotations

from app.schemas import ChapterKnowledge


def score(ck: ChapterKnowledge, total_text_chars: int) -> float:
    if ck.pages == 0:
        return 0.0

    coverage = min(1.0, (total_text_chars / max(1, ck.pages)) / 400.0)
    section_factor = min(1.0, len(ck.sections) / 3.0)
    def_factor = 1.0 if ck.definitions else 0.0
    ex_factor = 1.0 if ck.examples else 0.0
    formula_factor = 1.0 if ck.formulas else 0.0
    warn_penalty = max(0.0, 1.0 - 0.1 * len(ck.stage_warnings))

    raw = (
        0.30 * coverage
        + 0.20 * section_factor
        + 0.15 * def_factor
        + 0.15 * ex_factor
        + 0.10 * formula_factor
        + 0.10 * warn_penalty
    )
    return round(max(0.0, min(1.0, raw)), 3)
