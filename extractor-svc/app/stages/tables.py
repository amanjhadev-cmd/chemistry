"""
Stage 5: table extraction via Camelot (lattice + stream fallback).

Tries lattice first (works on tables with visible borders), falls back to
stream (works on whitespace-delimited tables). Skips silently if Camelot
isn't installed — the caller adds a stage_warning instead.
"""
from __future__ import annotations

from app.schemas import Table


def extract_tables(pdf_path: str) -> tuple[list[Table], list[str]]:
    """Returns (tables, warnings)."""
    warnings: list[str] = []
    try:
        import camelot  # type: ignore
    except Exception as e:
        warnings.append(f"tables: camelot unavailable ({type(e).__name__})")
        return [], warnings

    out: list[Table] = []
    seq = 0

    for flavor in ("lattice", "stream"):
        try:
            tables = camelot.read_pdf(pdf_path, pages="all", flavor=flavor, suppress_stdout=True)
        except Exception as e:
            warnings.append(f"tables: camelot {flavor} failed: {type(e).__name__}: {str(e)[:120]}")
            continue
        for t in tables:
            seq += 1
            try:
                rows = t.df.values.tolist()
            except Exception:
                continue
            page = int(getattr(t, "page", 0) or 0)
            out.append(
                Table(
                    id=f"tbl_{seq}",
                    page=page,
                    rows=[[str(c) for c in r] for r in rows],
                    caption="",
                )
            )
        if out:
            break  # don't double-extract via both flavors

    return out, warnings
