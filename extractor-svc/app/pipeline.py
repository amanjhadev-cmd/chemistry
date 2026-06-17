"""
Stages 1-12 orchestrator. Single sync entrypoint extract_pdf(path, hash).

Mirrors §13 of the blueprint:
  1. text + scan detection + cleaning
  2. (skipped — OCR fallback only when scanned)
  3. heading detection
  4. section tree
  5. tables (Camelot lattice → stream)
  6. formulas + chemical equations
  7. definitions
  8. examples / activities / theorems
  9. visuals (PyMuPDF images + nearby caption)
 10. final cleanup (header/footer dedup)
 11. quality score
 12. summary assembly (≤8000 chars for prompt injection)
"""
from __future__ import annotations

import time

from app.schemas import ChapterKnowledge
from app.stages import (
    definitions as defs_stage,
    examples as ex_stage,
    formulas as formula_stage,
    quality as q_stage,
    sections as sec_stage,
    tables as table_stage,
    text as text_stage,
    visuals as vis_stage,
)

EXTRACTOR_VERSION = "v1"


def extract_pdf(pdf_path: str, pdf_hash: str, assets_dir: str) -> ChapterKnowledge:
    timings: dict[str, int] = {}
    warnings: list[str] = []

    def stage(name: str, fn):
        t0 = time.perf_counter()
        result = fn()
        timings[name] = int((time.perf_counter() - t0) * 1000)
        return result

    raw_pages = stage("text", lambda: text_stage.extract_pages(pdf_path))
    raw_pages = stage("clean_headers", lambda: text_stage.strip_repeating_headers_footers(raw_pages))
    scanned = text_stage.is_scanned(raw_pages)
    if scanned:
        warnings.append("scan_detected: avg chars/page below threshold. OCR not yet wired in v1.")

    sections = stage("sections", lambda: sec_stage.build_sections(raw_pages))
    section_lookup = lambda p: sec_stage.find_section_id_for_page(sections, p)

    definitions = stage("definitions", lambda: defs_stage.extract_definitions(raw_pages, section_lookup))
    examples = stage("examples", lambda: ex_stage.extract_examples(raw_pages, section_lookup))
    formulas = stage("formulas", lambda: formula_stage.extract_formulas(raw_pages, section_lookup))

    tables, t_warn = stage("tables", lambda: table_stage.extract_tables(pdf_path))
    warnings.extend(t_warn)

    visuals, v_warn = stage("visuals", lambda: vis_stage.extract_visuals(pdf_path, assets_dir, pdf_hash))
    warnings.extend(v_warn)

    summary = build_summary(sections, definitions, examples, formulas)

    ck = ChapterKnowledge(
        pdf_hash=pdf_hash,
        extractor_version=EXTRACTOR_VERSION,
        pages=len(raw_pages),
        scanned=scanned,
        sections=sections,
        definitions=definitions,
        examples=examples,
        tables=tables,
        formulas=formulas,
        visuals=visuals,
        summary=summary,
        stage_warnings=warnings,
        timings_ms=timings,
        extraction_quality=0.0,  # filled below
    )

    total_chars = sum(len(p) for p in raw_pages)
    ck.extraction_quality = q_stage.score(ck, total_chars)
    return ck


def build_summary(sections, definitions, examples, formulas, max_chars: int = 6000) -> str:
    """Build a compact prompt-friendly summary. Order matters: definitions
    are the most prompt-critical, then formulas, then a section TOC, then
    a couple of example previews."""
    parts: list[str] = []

    if definitions:
        parts.append("# Key Definitions")
        for d in definitions[:30]:
            parts.append(f"- {d.term}: {d.text[:200]}".rstrip())

    if formulas:
        parts.append("\n# Formulas / Equations")
        for f in formulas[:25]:
            parts.append(f"- {f.latex}")

    if sections:
        parts.append("\n# Sections")
        for s in sections[:20]:
            pr = f"p{s.page_range[0]}-{s.page_range[-1]}" if s.page_range else ""
            parts.append(f"- ({pr}) {s.heading}")

    if examples:
        parts.append("\n# Example Previews")
        for e in examples[:10]:
            snippet = e.text.replace("\n", " ")[:200]
            parts.append(f"- [{e.kind} p{e.page}] {snippet}")

    out = "\n".join(parts).strip()
    if len(out) > max_chars:
        out = out[: max_chars - 3] + "..."
    return out
