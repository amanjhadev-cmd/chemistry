#!/usr/bin/env python3
"""
Generate samples/smoke_test/sample_chapter_solutions.pdf from
chapter_solutions_source.md without any external PDF libraries.

Outputs a valid PDF 1.4 with one page per ## section in the source markdown.
Text is plain ASCII, extractable by Tika / pdfplumber / pdftotext.

Usage:
    python3 generate_sample_pdf.py
"""

from pathlib import Path

HERE = Path(__file__).parent
SRC = HERE / "chapter_solutions_source.md"
OUT = HERE / "sample_chapter_solutions.pdf"


def parse_pages(md_text):
    """Split markdown into pages on '## Page N' headings."""
    pages = []
    current = []
    in_pages = False
    for line in md_text.splitlines():
        if line.startswith("## Page "):
            if current:
                pages.append("\n".join(current))
            current = []
            in_pages = True
            continue
        if in_pages:
            current.append(line)
    if current:
        pages.append("\n".join(current))
    # strip leading/trailing blank lines per page
    return [p.strip() for p in pages if p.strip()]


def escape_pdf_string(s):
    """Escape characters for PDF text string literals."""
    return s.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")


def wrap_lines(text, width=85):
    """Soft-wrap so long paragraphs don't overflow the page width."""
    out = []
    for raw_line in text.split("\n"):
        if not raw_line.strip():
            out.append("")
            continue
        words = raw_line.split(" ")
        line = ""
        for w in words:
            if len(line) + len(w) + 1 > width:
                out.append(line)
                line = w
            else:
                line = (line + " " + w).strip()
        if line:
            out.append(line)
    return out


def build_content_stream(page_text):
    """Build a PDF content stream that draws the page text."""
    lines = wrap_lines(page_text)
    # Limit to ~50 lines per page to stay within the MediaBox.
    lines = lines[:55]
    stream = "BT\n/F1 11 Tf\n50 760 Td\n14 TL\n"
    for i, line in enumerate(lines):
        esc = escape_pdf_string(line)
        if i == 0:
            stream += f"({esc}) Tj\n"
        else:
            stream += f"T*\n({esc}) Tj\n"
    stream += "ET\n"
    return stream.encode("latin-1")


def build_pdf(pages):
    """Assemble the full PDF byte string."""
    n_pages = len(pages)
    # Object numbering:
    #   1 = Catalog
    #   2 = Pages
    #   3..(2+n) = Page objects
    #   (3+n)..(2+2n) = Contents streams
    #   (3+2n) = Font
    contents_first = 3 + n_pages
    font_obj = 3 + 2 * n_pages

    objects = {}

    objects[1] = b"<< /Type /Catalog /Pages 2 0 R >>"

    kids = " ".join(f"{3+i} 0 R" for i in range(n_pages))
    objects[2] = (
        f"<< /Type /Pages /Kids [{kids}] /Count {n_pages} >>".encode("latin-1")
    )

    for i in range(n_pages):
        page_obj_num = 3 + i
        contents_num = contents_first + i
        objects[page_obj_num] = (
            f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
            f"/Contents {contents_num} 0 R "
            f"/Resources << /Font << /F1 {font_obj} 0 R >> >> >>"
        ).encode("latin-1")

    for i, page_text in enumerate(pages):
        contents_num = contents_first + i
        stream = build_content_stream(page_text)
        objects[contents_num] = (
            f"<< /Length {len(stream)} >>\nstream\n".encode("latin-1")
            + stream
            + b"\nendstream"
        )

    objects[font_obj] = (
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>"
    )

    # Serialize
    out = b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n"
    offsets = {}
    for num in sorted(objects):
        offsets[num] = len(out)
        out += f"{num} 0 obj\n".encode("latin-1")
        out += objects[num]
        out += b"\nendobj\n"

    xref_offset = len(out)
    max_obj = max(objects)
    out += f"xref\n0 {max_obj+1}\n".encode("latin-1")
    out += b"0000000000 65535 f \n"
    for num in range(1, max_obj + 1):
        off = offsets.get(num, 0)
        out += f"{off:010d} 00000 n \n".encode("latin-1")

    out += (
        f"trailer\n<< /Size {max_obj+1} /Root 1 0 R >>\n"
        f"startxref\n{xref_offset}\n%%EOF\n"
    ).encode("latin-1")
    return out


def main():
    if not SRC.exists():
        raise SystemExit(f"Source markdown not found: {SRC}")
    md = SRC.read_text(encoding="utf-8")
    pages = parse_pages(md)
    if not pages:
        raise SystemExit("No '## Page N' sections found in source markdown.")
    pdf_bytes = build_pdf(pages)
    OUT.write_bytes(pdf_bytes)
    print(f"Wrote {OUT} ({len(pdf_bytes)} bytes, {len(pages)} pages)")


if __name__ == "__main__":
    main()
