# PDF Extractor Service

The non-AI PDF knowledge extraction microservice referenced by the n8n
workflow's **Agent 3 - Non-AI PDF Extract** HTTP node. Replaces the
placeholder URL `https://extract.internal.placeholder/extract`.

## What it does

Takes a PDF in the request body, runs 12 deterministic stages (no LLM
anywhere), returns a `ChapterKnowledge` JSON matching
`prompt-repo/schemas/contracts/chapter_knowledge.schema.json` exactly.

| Stage | Library | Output |
|---|---|---|
| 1 text + page split | `pdfplumber` | one cleaned string per page |
| 2 scan detection | regex + heuristic | `scanned: true/false` |
| 3 heading detection | regex | list of heading lines |
| 4 section tree | regex | `sections[]` with `page_range` |
| 5 tables (optional) | `camelot` (lattice→stream) | `tables[]` |
| 6 formulas + equations | regex | `formulas[]` |
| 7 definitions | regex | `definitions[]` |
| 8 examples / activities / theorems | regex | `examples[]` |
| 9 visuals | `PyMuPDF` | `visuals[]` with bbox + caption + asset file |
| 10 header/footer dedup | frequency | applied during text stage |
| 11 quality score | composite | `extraction_quality` 0.0..1.0 |
| 12 summary | template | `summary` (≤8000 chars, prompt-budgeted) |

OCR for scanned PDFs is **not in v1** — they're flagged with a warning so the
caller can decide. (Add `OCRmyPDF + Tesseract` later as `stages/ocr.py`.)

## Endpoints

- `GET  /healthz` — liveness
- `GET  /readyz` — readiness (lib imports + assets-dir writable)
- `POST /extract` — main endpoint. Accepts:
  - `Content-Type: application/pdf` with raw PDF bytes in body, OR
  - `Content-Type: multipart/form-data` with field `reference_pdf` (or `file` / `pdf`)
  - Optional headers: `X-Pdf-Hash` (sha256, verified against the body), `X-Extractor-Version` (must match service version)
  - Optional auth: `Authorization: Bearer <EXTRACTOR_BEARER_TOKEN env var>`

Returns `200` with the `ChapterKnowledge` JSON, `4xx` for client errors,
`413` for oversized PDFs, `500` for unhandled extraction failures.

## Run locally with Docker

```bash
cd extractor-svc
docker compose up --build
# service on http://localhost:8001
curl http://localhost:8001/readyz
curl -X POST http://localhost:8001/extract \
     -H "Content-Type: application/pdf" \
     --data-binary @../samples/smoke_test/sample_chapter_solutions.pdf \
     | jq '{pages, scanned, extraction_quality, sections: (.sections|length), definitions: (.definitions|length), examples: (.examples|length)}'
```

## Run tests

```bash
# In a venv with pdfplumber + PyMuPDF installed:
cd extractor-svc
python -m pip install -r requirements.txt
python -m tests.test_pipeline
# expects: 2 passing tests against samples/smoke_test/sample_chapter_solutions.pdf
```

## Configuration

| Env var | Default | Purpose |
|---|---|---|
| `EXTRACTOR_BEARER_TOKEN` | (unset → no auth) | If set, requests must present `Authorization: Bearer <value>` |
| `EXTRACTOR_MAX_PDF_BYTES` | `52428800` (50 MB) | Reject larger PDFs with HTTP 413 |
| `EXTRACTOR_ASSETS_DIR` | `/data/assets` | Where extracted images are written; should be a persistent volume |

## Wiring into the n8n workflow

The workflow's `Agent 3 - Non-AI PDF Extract` node already sends:
- `Content-Type: application/pdf` (binary body mode)
- `X-Pdf-Hash: sha256:...`
- `X-Extractor-Version: v1`

To wire this service in, edit the node and set:
- **URL**: `http://<host>:8001/extract` (or whatever you exposed in `docker-compose.yml`)
- **Authentication** (if token enabled): generic credential type → Header Auth with `Authorization: Bearer <token>`

That's the only n8n change needed — the response shape already matches what
Agent 4 expects via the `chapter_knowledge` field flowing through `Merge KB Paths`.

## Scaling

v1 is one Python process serving one PDF at a time per worker (uvicorn `--workers 2`
in the Dockerfile). Per the architecture doc, the 7-microservice split (Tika +
pdfplumber + PyMuPDF + Camelot + Tabula + OCR + Poppler each behind its own
HTTP service) is a v2 decision when a single stage becomes a bottleneck.
Don't split prematurely.
