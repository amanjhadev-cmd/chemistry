"""
FastAPI app for the PDF extraction service.

Endpoints:
  GET  /healthz                  liveness
  GET  /readyz                   readiness (lib imports + write-perm on assets dir)
  POST /extract                  binary PDF in body (Content-Type: application/pdf) or
                                 multipart with field name "reference_pdf"
                                 Returns ChapterKnowledge JSON.

Auth (optional): set EXTRACTOR_BEARER_TOKEN env var. If set, requests must
present `Authorization: Bearer <token>`.

The n8n workflow's `Agent 3 - Non-AI PDF Extract` HTTP Request node already
sends:
  Content-Type: application/pdf  (binary body mode)
  X-Pdf-Hash: sha256:...
  X-Extractor-Version: v1
"""
from __future__ import annotations

import hashlib
import os
import tempfile
from pathlib import Path

from fastapi import FastAPI, HTTPException, Header, Request, status
from fastapi.responses import JSONResponse

from app.pipeline import EXTRACTOR_VERSION, extract_pdf
from app.schemas import ChapterKnowledge


MAX_PDF_BYTES = int(os.environ.get("EXTRACTOR_MAX_PDF_BYTES", str(50 * 1024 * 1024)))
ASSETS_DIR = os.environ.get("EXTRACTOR_ASSETS_DIR", "/data/assets")
BEARER_TOKEN = os.environ.get("EXTRACTOR_BEARER_TOKEN", "").strip()

app = FastAPI(
    title="Question Generation PDF Extractor",
    version=EXTRACTOR_VERSION,
    description="Non-AI PDF knowledge extraction. Used by n8n Agent 3.",
)


def _auth(authorization: str | None) -> None:
    if not BEARER_TOKEN:
        return
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing bearer token")
    if authorization.removeprefix("Bearer ").strip() != BEARER_TOKEN:
        raise HTTPException(status_code=403, detail="Invalid bearer token")


@app.get("/healthz")
def healthz() -> dict[str, str]:
    return {"status": "ok", "version": EXTRACTOR_VERSION}


@app.get("/readyz")
def readyz() -> dict[str, object]:
    checks: dict[str, object] = {}

    Path(ASSETS_DIR).mkdir(parents=True, exist_ok=True)
    probe = Path(ASSETS_DIR) / ".readyz"
    try:
        probe.write_text("ok")
        probe.unlink(missing_ok=True)
        checks["assets_dir_writable"] = True
    except Exception as e:
        checks["assets_dir_writable"] = f"FAIL: {e}"

    for mod in ("pdfplumber", "fitz"):
        try:
            __import__(mod)
            checks[f"import_{mod}"] = True
        except Exception as e:
            checks[f"import_{mod}"] = f"FAIL: {e}"

    # Camelot is optional — log but don't fail.
    try:
        __import__("camelot")
        checks["import_camelot"] = True
    except Exception:
        checks["import_camelot"] = "optional, not installed"

    failed = [k for k, v in checks.items() if v not in (True, "optional, not installed")]
    if failed:
        return JSONResponse(status_code=503, content={"ready": False, "checks": checks})
    return {"ready": True, "version": EXTRACTOR_VERSION, "checks": checks}


@app.post("/extract")
async def extract(
    request: Request,
    authorization: str | None = Header(default=None),
    x_pdf_hash: str | None = Header(default=None),
    x_extractor_version: str | None = Header(default=None),
) -> ChapterKnowledge:
    _auth(authorization)

    if x_extractor_version and x_extractor_version != EXTRACTOR_VERSION:
        raise HTTPException(
            status_code=400,
            detail=f"client requested extractor_version={x_extractor_version} but this service only serves {EXTRACTOR_VERSION}",
        )

    content_type = (request.headers.get("content-type") or "").lower()

    pdf_bytes: bytes
    if content_type.startswith("application/pdf"):
        pdf_bytes = await request.body()
    elif content_type.startswith("multipart/form-data"):
        form = await request.form()
        upload = form.get("reference_pdf") or form.get("file") or form.get("pdf")
        if upload is None or not hasattr(upload, "read"):
            raise HTTPException(status_code=400, detail="multipart body missing reference_pdf/file/pdf field")
        pdf_bytes = await upload.read()
    else:
        # Fallback: assume raw PDF bytes in body.
        pdf_bytes = await request.body()

    if not pdf_bytes:
        raise HTTPException(status_code=400, detail="empty body")
    if len(pdf_bytes) > MAX_PDF_BYTES:
        raise HTTPException(
            status_code=413,
            detail=f"pdf too large: {len(pdf_bytes)} bytes > limit {MAX_PDF_BYTES}",
        )
    if pdf_bytes[:5] != b"%PDF-":
        raise HTTPException(status_code=400, detail="body is not a valid PDF (missing %PDF- header)")

    # Encrypted-PDF guard. PyMuPDF can tell us cheaply before the pipeline runs.
    try:
        import fitz  # PyMuPDF
        with fitz.open(stream=pdf_bytes, filetype="pdf") as _probe:
            if _probe.is_encrypted:
                raise HTTPException(
                    status_code=400,
                    detail="encrypted PDFs are not supported; remove the password and resubmit",
                )
    except HTTPException:
        raise
    except Exception:
        # Probe failure shouldn't block extraction — the main pipeline will
        # surface a clearer error if the PDF is truly malformed.
        pass

    # Compute or verify hash.
    computed = "sha256:" + hashlib.sha256(pdf_bytes).hexdigest()
    if x_pdf_hash and x_pdf_hash != computed:
        raise HTTPException(
            status_code=400,
            detail=f"X-Pdf-Hash mismatch: client sent {x_pdf_hash}, computed {computed}",
        )
    pdf_hash = computed

    # Write to temp file for libs that need a path.
    with tempfile.NamedTemporaryFile(suffix=".pdf", delete=False) as f:
        f.write(pdf_bytes)
        tmp_path = f.name

    try:
        ck = extract_pdf(tmp_path, pdf_hash, ASSETS_DIR)
    finally:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass

    return ck


@app.exception_handler(Exception)
async def unhandled(request: Request, exc: Exception) -> JSONResponse:
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={"error": type(exc).__name__, "detail": str(exc)[:500]},
    )
