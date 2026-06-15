"""
Stage 9: visual (image/diagram) extraction via PyMuPDF.

Extracts every embedded image, writes it to assets_dir, records bbox + nearby
caption text. Visual type classification is intentionally coarse — refine
later if/when the workflow's visual question pipeline gets exercised.
"""
from __future__ import annotations

import os
from pathlib import Path

from app.schemas import Visual


CAPTION_PATTERNS = ("fig.", "figure", "diagram", "chart", "graph", "table")


def extract_visuals(pdf_path: str, assets_dir: str, pdf_hash: str) -> tuple[list[Visual], list[str]]:
    """Returns (visuals, warnings). assets_dir is created if missing."""
    warnings: list[str] = []
    try:
        import fitz  # PyMuPDF
    except Exception as e:
        warnings.append(f"visuals: pymupdf unavailable ({type(e).__name__})")
        return [], warnings

    out: list[Visual] = []
    out_dir = Path(assets_dir) / pdf_hash.replace(":", "_")
    out_dir.mkdir(parents=True, exist_ok=True)

    try:
        doc = fitz.open(pdf_path)
    except Exception as e:
        warnings.append(f"visuals: cannot open pdf: {type(e).__name__}: {e}")
        return [], warnings

    seq = 0
    for page_idx in range(len(doc)):
        page = doc[page_idx]
        page_1based = page_idx + 1

        # Collect text blocks for nearby-caption lookup.
        try:
            text_blocks = page.get_text("blocks") or []
        except Exception:
            text_blocks = []

        for img_index, img_info in enumerate(page.get_images(full=True)):
            xref = img_info[0]
            try:
                base_img = doc.extract_image(xref)
                ext = base_img.get("ext", "png")
                data = base_img.get("image", b"")
            except Exception as e:
                warnings.append(f"visuals: extract failed on p{page_1based} img{img_index}: {e}")
                continue

            seq += 1
            visual_id = f"v_{page_1based}_{seq}"
            asset_filename = f"{visual_id}.{ext}"
            asset_path = out_dir / asset_filename
            try:
                asset_path.write_bytes(data)
            except Exception as e:
                warnings.append(f"visuals: write failed for {asset_path}: {e}")
                continue

            # Find image bbox via page.get_image_rects (PyMuPDF 1.18+).
            bbox: list[float] = []
            try:
                rects = page.get_image_rects(xref)
                if rects:
                    r = rects[0]
                    bbox = [float(r.x0), float(r.y0), float(r.x1), float(r.y1)]
            except Exception:
                pass

            # Nearby caption: text block directly below the image bbox.
            caption = ""
            nearby = ""
            if bbox:
                for block in text_blocks:
                    # block = (x0, y0, x1, y1, "text", block_no, block_type)
                    x0, y0, x1, y1 = block[:4]
                    text = block[4] if len(block) > 4 else ""
                    if not text:
                        continue
                    is_below = y0 >= bbox[3] - 5 and (y0 - bbox[3]) < 80
                    overlap_x = min(x1, bbox[2]) - max(x0, bbox[0])
                    if is_below and overlap_x > 0:
                        nearby = text.strip()
                        first_line = nearby.splitlines()[0].strip()
                        if any(p in first_line.lower() for p in CAPTION_PATTERNS):
                            caption = first_line[:200]
                        break

            out.append(
                Visual(
                    visual_id=visual_id,
                    visual_type=_classify(caption),
                    page=page_1based,
                    bbox=bbox,
                    asset_path=str(asset_path),
                    caption=caption,
                    nearby_text=nearby[:400],
                )
            )

    doc.close()
    return out, warnings


def _classify(caption: str) -> str:
    c = caption.lower()
    if "graph" in c or "plot" in c or "chart" in c:
        return "graph"
    if "circuit" in c:
        return "circuit_diagram"
    if "flow" in c:
        return "flowchart"
    if "structure" in c or "molecule" in c:
        return "chemical_structure"
    return "diagram"
