# Extending Phase 1

Phase 1 only does Knowledge Extraction. Every extension below is a small, local change.

## Add a new chapter

1. `config/config.json#chapters.<class>` → append the chapter.
2. Open `On form submission` → add the chapter title to the `Chapter Name` dropdown.

`chapter_code` and the Drive folder name are derived from the dropdown value automatically.

## Add a new board (e.g. ICSE)

1. `config/config.json#supported.boards` → append `ICSE`.
2. Open `On form submission` → add `ICSE` to the `Board` dropdown.

If the structurer needs board-specific phrasing (rare for Phase 1 — extraction is largely board-agnostic), duplicate the `SYSTEM_STRUCTURER` hidden field as `SYSTEM_STRUCTURER_ICSE` and read the suffixed one in `Normalize Input` when `Board === 'ICSE'`.

## Add a new subject

Subjects differ enough that the cleanest path is to clone the Phase 1 workflow and swap:

- `Chapter Name` dropdown values.
- `SYSTEM_STRUCTURER` hidden field (subject-specific schema cues — e.g. for Biology you'd want `taxonomy[]` and `processes[]` arrays; for Physics you'd keep `formulae[]` and `laws[]` but lose `reactions[]`).
- `Validate Knowledge Schema` Code node — update the `REQUIRED_ARRAYS` list to match the new schema.

The PDF → extract → clean → structure → save pipeline is subject-agnostic.

## Add Hindi (or any new language)

1. `Language` dropdown on the form → add `Hindi`.
2. Add a hidden field `SYSTEM_STRUCTURER_HI` with Hindi structurer instructions emitting Devanagari output.
3. In `Normalize Input`, pick the right system prompt:
   ```js
   const langSuffix = (f['Language'] || 'English') === 'Hindi' ? '_HI' : '';
   const system_structurer = f[`SYSTEM_STRUCTURER${langSuffix}`] || f['SYSTEM_STRUCTURER'];
   ```

The output JSON shape stays the same — only the values are Devanagari.

## Use a different LLM provider

Replace `AI: Structure Chapter Knowledge` (`n8n-nodes-base.anthropic`) with the provider's chat node (OpenRouter, OpenAI, Gemini). The prompt is provider-neutral. You'll also need to adjust the response-path expression in `Parse Knowledge JSON` (currently reads `$json.content[0].text`).

## OCR support for scanned PDFs

When `Clean PDF Text` throws "Cleaned text is suspiciously short", insert an OCR step between `Extract PDF Text & Metadata` and `Clean PDF Text`:

1. Add a `Tesseract` (community node) or call an OCR API (Google Vision, Mathpix for chemistry).
2. Replace `$json.text` with the OCR-extracted text before `Clean PDF Text` runs.

The rest of the pipeline is unchanged.

## Pre-Phase 2 hand-off

When Phase 2 (prompt routing + question generation) is built, it will:

1. Read the form (same 11 fields again, OR a lighter form that only asks for question_type / difficulty / count).
2. Resolve the matching `<CHAPTER_CODE>_KNOWLEDGE.json` from `Question Bank/CBSE/<Class>/<Chapter>/Knowledge Base/`.
3. Use the structured arrays as ground truth for generation (no PDF re-extraction needed).

Phase 2 should never re-parse the PDF — it operates entirely off the Phase 1 JSON.
