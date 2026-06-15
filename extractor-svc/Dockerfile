FROM python:3.12-slim AS base

# System deps: PyMuPDF wheel ships without system libs, but Camelot (if
# enabled) needs ghostscript + tk. Keep both for parity with the optional
# Camelot path; remove if you've commented out camelot in requirements.txt.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ghostscript \
        tk \
        libgl1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /srv

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app

ENV PYTHONUNBUFFERED=1 \
    EXTRACTOR_ASSETS_DIR=/data/assets \
    PORT=8000

RUN mkdir -p /data/assets

EXPOSE 8000

# Healthcheck hits the readiness endpoint.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
    CMD python -c "import urllib.request, sys; \
sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/healthz', timeout=3).status==200 else 1)"

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "2"]
