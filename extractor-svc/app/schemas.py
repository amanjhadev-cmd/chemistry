"""
Pydantic models for the chapter_knowledge contract.

Matches prompt-repo/schemas/contracts/chapter_knowledge.schema.json exactly so
the output slots into the n8n workflow's Agent 3 → KB Cache Write → Agent 4
chain with no transformation.
"""
from __future__ import annotations

from typing import Any
from pydantic import BaseModel, Field


class Section(BaseModel):
    id: str
    heading: str = ""
    page_range: list[int] = Field(default_factory=list)
    text: str = ""


class Definition(BaseModel):
    term: str
    text: str
    page: int
    section_id: str | None = None


class Example(BaseModel):
    id: str
    kind: str  # "example" | "activity" | "theorem" | "illustration"
    page: int
    text: str
    section_id: str | None = None


class Table(BaseModel):
    id: str
    page: int
    rows: list[list[str]]
    caption: str = ""


class Formula(BaseModel):
    id: str
    latex: str
    page: int
    section_id: str | None = None


class Visual(BaseModel):
    visual_id: str
    visual_type: str  # diagram | graph | table | flowchart | etc.
    page: int
    bbox: list[float] = Field(default_factory=list)  # [x0, y0, x1, y1]
    asset_path: str = ""
    caption: str = ""
    nearby_text: str = ""


class ChapterKnowledge(BaseModel):
    pdf_hash: str
    extractor_version: str = "v1"
    pages: int
    extraction_quality: float = Field(ge=0.0, le=1.0)
    scanned: bool = False
    sections: list[Section] = Field(default_factory=list)
    definitions: list[Definition] = Field(default_factory=list)
    examples: list[Example] = Field(default_factory=list)
    tables: list[Table] = Field(default_factory=list)
    formulas: list[Formula] = Field(default_factory=list)
    visuals: list[Visual] = Field(default_factory=list)
    summary: str = Field(default="", max_length=8000)
    stage_warnings: list[str] = Field(default_factory=list)
    timings_ms: dict[str, int] = Field(default_factory=dict)


class ExtractRequest(BaseModel):
    """Used only when the client POSTs JSON instead of multipart/binary."""
    pdf_url: str | None = None
    pdf_b64: str | None = None
