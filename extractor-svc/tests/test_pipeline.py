"""
Pipeline smoke tests against samples/smoke_test/sample_chapter_solutions.pdf.

Run with:
    cd extractor-svc && python -m pytest tests/ -v
or, without pytest:
    cd extractor-svc && python -m tests.test_pipeline

Skips gracefully if the optional libs aren't installed.
"""
from __future__ import annotations

import hashlib
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SAMPLE_PDF = REPO_ROOT / "samples" / "smoke_test" / "sample_chapter_solutions.pdf"

sys.path.insert(0, str(REPO_ROOT / "extractor-svc"))


class TestPipeline(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if not SAMPLE_PDF.exists():
            raise unittest.SkipTest(f"sample PDF missing: {SAMPLE_PDF}")
        try:
            import pdfplumber  # noqa: F401
            import fitz  # noqa: F401
        except Exception as e:
            raise unittest.SkipTest(f"optional libs not installed: {e}")

        cls.pdf_bytes = SAMPLE_PDF.read_bytes()
        cls.pdf_hash = "sha256:" + hashlib.sha256(cls.pdf_bytes).hexdigest()
        cls.assets_dir = tempfile.mkdtemp(prefix="qgen_extractor_test_")

    def test_extract_pdf_contract(self) -> None:
        from app.pipeline import extract_pdf

        ck = extract_pdf(str(SAMPLE_PDF), self.pdf_hash, self.assets_dir)

        # Contract fields
        self.assertEqual(ck.pdf_hash, self.pdf_hash)
        self.assertEqual(ck.extractor_version, "v1")
        self.assertEqual(ck.pages, 4)
        self.assertFalse(ck.scanned, "sample PDF is text-based, not scanned")
        self.assertGreaterEqual(ck.extraction_quality, 0.4)

        # The sample chapter has explicit "Definition:" markers — we must find some.
        self.assertGreaterEqual(
            len(ck.definitions), 3,
            f"expected at least 3 definitions, got {len(ck.definitions)}",
        )

        # The sample chapter has "Example 1.1", "Example 1.2", "Example 1.3".
        self.assertGreaterEqual(
            len(ck.examples), 3,
            f"expected at least 3 examples, got {len(ck.examples)}",
        )

        # Summary must be non-empty and within prompt budget.
        self.assertTrue(ck.summary)
        self.assertLessEqual(len(ck.summary), 8000)

        # Sections: at least 1 (could be many depending on heading heuristics).
        self.assertGreaterEqual(len(ck.sections), 1)

        # Timings dictionary populated.
        self.assertIn("text", ck.timings_ms)
        self.assertIn("sections", ck.timings_ms)

    def test_definitions_have_expected_terms(self) -> None:
        from app.pipeline import extract_pdf

        ck = extract_pdf(str(SAMPLE_PDF), self.pdf_hash, self.assets_dir)
        terms = {d.term.lower() for d in ck.definitions}
        # The chapter mentions Molarity, Molality, Solubility, Mole fraction.
        # Heuristics are imperfect; require at least one canonical term.
        canonical = {"molality", "molarity", "solubility", "mole fraction", "saturated solution"}
        intersection = terms & canonical
        self.assertTrue(
            intersection,
            f"expected at least one canonical term in {terms!r}",
        )


def _main() -> int:
    suite = unittest.TestLoader().loadTestsFromTestCase(TestPipeline)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    sys.exit(_main())
