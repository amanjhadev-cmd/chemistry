# Phase 1 — Node-by-node architecture

12 nodes. Single linear path. One LLM call (the structurer). Two Drive interactions (folder creation + upload).

For every node below: **Purpose → Input → Config → Output → Errors.**

---

## 1. `On form submission`
- **Type:** `n8n-nodes-base.formTrigger` (v2.2)
- **Purpose:** Collects the 11 user fields plus one hidden field (`SYSTEM_STRUCTURER` prompt).
- **Input:** HTTP form post.
- **Config:** 11 visible fields (5 mandatory before PDF, 1 PDF, 5 follow-on incl. Question Type / Difficulty kept for Phase 2). One hidden field with the structurer prompt. `acceptFileTypes: ".pdf"`, `multipleFiles: false`.
- **Output (`$json`):**
  ```json
  {
    "Board": "CBSE", "Class": "Class XII", "Chapter Name": "Solutions",
    "Source Type": "NCERT", "Question Type": "MCQ", "Difficulty": "MEDIUM",
    "Number of Questions": "10", "Include Visual Questions": "NO",
    "Language": "English", "Generate Explanation": "YES",
    "SYSTEM_STRUCTURER": "You are a chemistry chapter structurer..."
  }
  ```
  Plus `$binary.Reference_PDF` (or similar — n8n normalises the label).
- **Errors:** Form-trigger validates `requiredField`. Bad MIME is rejected at upload.

---

## 2. `Normalize Input`
- **Type:** `n8n-nodes-base.code` (v2, JS)
- **Purpose:** Coerces types, builds `chapter_code` (e.g. `SOLUTIONS`), `batch_id`, `knowledge_file_name` (`SOLUTIONS_KNOWLEDGE.json`), and carries forward all 11 form values into a single typed envelope.
- **Input:** Form payload.
- **Config:** JS only — no node parameters.
- **Output (`$json`):**
  ```json
  {
    "board": "CBSE",
    "class_name": "Class XII",
    "chapter": "Solutions",
    "source_type": "NCERT",
    "question_type": "MCQ",
    "question_type_folder": "MCQ",
    "difficulty": "MEDIUM",
    "number_of_questions": 10,
    "include_visual_questions": false,
    "language": "English",
    "generate_explanation": true,
    "chapter_code": "SOLUTIONS",
    "batch_id": "lz9k2r-7f3a1c",
    "started_at": "2026-06-11T09:00:00Z",
    "knowledge_file_name": "SOLUTIONS_KNOWLEDGE.json",
    "system_structurer": "You are a chemistry chapter structurer..."
  }
  ```
  `$binary` is preserved untouched.
- **Errors:** None — defensive coercion. `number_of_questions` falls back to `10` on parse failure.

---

## 3. `Extract PDF Text & Metadata`
- **Type:** `n8n-nodes-base.extractFromFile` (v1)
- **Purpose:** Pulls the joined text of the PDF plus structural metadata (page count, PDF version, embedded info dictionary).
- **Input:** `$binary.Reference_PDF`.
- **Config:** `operation: pdf`, `binaryPropertyName: Reference_PDF`, `options: { joinPages: true, keepSource: binary }`.
- **Output (`$json`):** `text`, `numpages`, `info`, `version` (raw from `pdf-parse`).
- **Errors:** `retryOnFail: true`, `maxTries: 3`, `waitBetweenTries: 2000ms` — transient parser glitches self-heal. Hard failures (corrupt PDF) bubble up.

---

## 4. `Clean PDF Text`
- **Type:** `n8n-nodes-base.code` (v2, JS)
- **Purpose:** Removes page numbers, repeating headers/footers, watermark lines, OCR artefacts, URL/email lines; de-hyphenates line breaks; collapses duplicate adjacent paragraphs; repairs common chemistry-notation breakages (`H 2 O → H2O`, `o C → °C`, `-> → →`, `<-> → ⇌`).
- **Input:** `$('Normalize Input').first().json` (envelope) + `$json.text` from the extractor.
- **Config:** JS only.
- **Output:** Envelope + `pdf_metadata: {num_pages, info, version, raw_chars}` + `cleaned_text` (string).
- **Errors:** Throws `"Cleaned text is suspiciously short (<N> chars)..."` when post-clean length < 200 chars — usually means the PDF is image-only and needs OCR.

---

## 5. `AI: Structure Chapter Knowledge`
- **Type:** `n8n-nodes-base.anthropic` (v1)
- **Purpose:** Single LLM call that converts cleaned chapter text into the structured-knowledge object per the schema in `SYSTEM_STRUCTURER`.
- **Input:** `cleaned_text`, `chapter`, `class_name`, `board`, `source_type`.
- **Config:**
  - `modelId: claude-haiku-4-5-20251001`
  - `system: ={{ $json.system_structurer }}`
  - `temperature: 0`
  - `maxTokensToSample: 8000`
  - `retryOnFail: true`, `maxTries: 2`, `waitBetweenTries: 3000ms`
- **Output:** Anthropic message — text in `$json.content[0].text`.
- **Errors:** Anthropic 4xx surface immediately (auth / model / quota). 5xx and rate-limit retried twice with 3 s backoff.

---

## 6. `Parse Knowledge JSON`
- **Type:** `n8n-nodes-base.code` (v2, JS)
- **Purpose:** Strips any markdown fence, slices from first `{` to last `}` if the model added prose, and `JSON.parse`s the structurer output.
- **Input:** `$('Clean PDF Text').first().json` (envelope) + LLM message.
- **Config:** JS only.
- **Output:** Envelope + `structured_knowledge` (parsed object).
- **Errors:** Throws `"Structurer returned non-JSON: ..."` on parse failure or if no `{`/`}` boundary is found. Forces a visible failed execution rather than silently saving garbage.

---

## 7. `Validate Knowledge Schema`
- **Type:** `n8n-nodes-base.code` (v2, JS)
- **Purpose:** Pure-JS schema validation. No second LLM. Confirms `chapter_title` is a non-empty string, all 14 required arrays are arrays, total entries ≥ 8 (anti-empty floor).
- **Input:** Envelope with `structured_knowledge`.
- **Config:** JS only — required keys hard-coded:
  ```
  topics, subtopics, definitions, formulae, laws, principles,
  reactions, examples, tables, graph_references, diagram_references,
  important_facts, exceptions, ncert_activities
  ```
- **Output:** Envelope + `validation: { ok: true, total_entries: N }`.
- **Errors:** Throws a multi-line `"Knowledge object failed validation: …"` listing every missing/wrong-typed key. Halts the workflow before anything is written to Drive.

---

## 8. `Compose Final JSON`
- **Type:** `n8n-nodes-base.code` (v2, JS)
- **Purpose:** Assembles the spec-shaped output payload — required spec keys at the top level, then `form_inputs` and `meta`. Echoes all 11 form values inside `form_inputs` for Phase 2+ consumers.
- **Input:** Envelope with `structured_knowledge`, `cleaned_text`, `pdf_metadata`, `validation`.
- **Config:** JS only.
- **Output:** Envelope + `final_payload: { board, class, chapter, source_type, pdf_metadata, topics[], subtopics[], definitions[], formulae[], laws[], principles[], reactions[], examples[], tables[], graph_references[], diagram_references[], important_facts[], exceptions[], ncert_activities[], clean_text, form_inputs, meta }`.
- **Errors:** None — pure assembly over validated input.

---

## 9. `Ensure Drive Folders`
- **Type:** `n8n-nodes-base.code` (v2, JS) — uses `helpers.httpRequestWithAuthentication` against Drive REST.
- **Purpose:** Idempotent `findOrCreate` walk of `Question Bank / CBSE / <Class> / <Chapter> / Knowledge Base`. Returns the leaf folder id plus the full trail (handy for logs).
- **Input:** `board`, `class_name`, `chapter`.
- **Config:** Credential `googleDriveOAuth2Api`. No node parameters.
- **Output:** Envelope + `drive_folder_trail: [{name, id}, …]` + `target_folder_id`.
- **Errors:** 401 → re-auth the Drive credential. 403 → scope too narrow (use `drive.file` or `drive`). Network errors bubble up after one retry from the underlying helper.

---

## 10. `JSON → Binary`
- **Type:** `n8n-nodes-base.code` (v2, JS)
- **Purpose:** Wraps `final_payload` as a binary file ready for upload.
- **Input:** Envelope with `final_payload` and `knowledge_file_name`.
- **Config:** JS only.
- **Output:** `$json` unchanged + `$binary.data` (base64) with `mimeType: application/json` and `fileName: <CHAPTER_CODE>_KNOWLEDGE.json`.
- **Errors:** None — serialisation only.

---

## 11. `Upload Knowledge JSON to Drive`
- **Type:** `n8n-nodes-base.googleDrive` (v3)
- **Purpose:** Uploads the JSON into the leaf Knowledge Base folder.
- **Input:** `$binary.data` + `target_folder_id` + `knowledge_file_name`.
- **Config:** `operation: upload`, `name: ={{ $json.knowledge_file_name }}`, `folderId: ={{ $json.target_folder_id }}`, `binaryPropertyName: data`, `options.fields: id,name,webViewLink,parents`. `retryOnFail: true`, `maxTries: 3`, `waitBetweenTries: 2000ms`.
- **Output:** Drive file object — `id`, `name`, `webViewLink`, `parents` — merged onto `$json`.
- **Errors:** 5xx retried with backoff. 403 → scope. 404 on folder id → `Ensure Drive Folders` upstream bug; check the trail in the previous node's output.

---

## 12. `Log Phase 1 Summary`
- **Type:** `n8n-nodes-base.code` (v2, JS)
- **Purpose:** Emits a single audit record for downstream telemetry.
- **Input:** Envelope.
- **Output:** `{ status: "OK", phase: 1, batch_id, chapter, chapter_code, saved_file, drive_file_id, drive_web_view_link, drive_folder_trail, pdf_pages, total_structured_entries, finished_at }`.
- **Errors:** None.

---

## Connections (graph)

```
On form submission
  → Normalize Input
    → Extract PDF Text & Metadata
      → Clean PDF Text
        → AI: Structure Chapter Knowledge
          → Parse Knowledge JSON
            → Validate Knowledge Schema
              → Compose Final JSON
                → Ensure Drive Folders
                  → JSON → Binary
                    → Upload Knowledge JSON to Drive
                      → Log Phase 1 Summary
```

No branches. No back-edges. No dangling nodes.

## Error-handling strategy (summary)

| Failure mode | Where caught | Behaviour |
|---|---|---|
| Required form field missing | Form trigger | 400 to submitter |
| PDF unreadable / corrupt | Extract PDF Text & Metadata | Retry 3× with 2 s backoff; hard fail surfaces in Executions |
| Scanned (image-only) PDF | Clean PDF Text | Throws "Cleaned text is suspiciously short" — operator action: OCR the PDF first |
| Anthropic 5xx / rate limit | AI: Structure | Retry 2× with 3 s backoff |
| Malformed LLM JSON | Parse Knowledge JSON | Throws — no garbage to Drive |
| Schema gaps in knowledge object | Validate Knowledge Schema | Throws with full list of issues |
| Drive auth / scope error | Ensure Drive Folders, Upload | Surfaces immediately; nothing partial uploaded |
| Drive 5xx on upload | Upload | Retry 3× with 2 s backoff |

The pipeline never silently downgrades — if any check fails, the file is **not** written to Drive.

## Why this shape

- **One LLM call.** Phase 1 has a single AI step (the structurer). Cheap, deterministic, T=0.
- **Hidden-field system prompt.** Prompt versioned with the workflow, no env vars / external files.
- **Schema validation before Drive.** Saves operator time; you never end up debugging a malformed file already in production.
- **Folder creation as Code, not Drive node chains.** Five segments × `findOrCreate` in 25 lines, one credential, no extra nodes per level.
- **Filename = `<CHAPTER_CODE>_KNOWLEDGE.json`.** Stable, predictable, the only file Phase 2 will look for.
