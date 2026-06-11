# Phase 1 — How to import into n8n

Single workflow, two credentials, one activate toggle.

---

## 1. Credentials (one-time)

In **Credentials → New**:

| Credential | Type | Notes |
|---|---|---|
| `Anthropic` | Anthropic API | Paste your `sk-ant-...` key. Phase 1 uses `claude-haiku-4-5-20251001` (Haiku) at temperature 0. |
| `Google Drive OAuth2` | Google Drive OAuth2 API | Sign in with the Google account that owns the destination Drive. Scope `drive.file` is sufficient. |

Note each credential's **ID** from the URL when you open it (e.g. `rkE6lGy0ggcpc3F4`).

---

## 2. Import the workflow

**Workflows → ⋯ → Import from File** → pick `workflow/phase-1-knowledge-extraction.json`.

Open each red-dotted node and bind the credential:

| Node | Credential |
|---|---|
| AI: Structure Chapter Knowledge | Anthropic |
| Ensure Drive Folders | Google Drive OAuth2 |
| Upload Knowledge JSON to Drive | Google Drive OAuth2 |

### Or: find-and-replace before import

| Placeholder | Replace with |
|---|---|
| `REPLACE_ANTHROPIC_CRED_ID` | your Anthropic credential id |
| `REPLACE_DRIVE_CRED_ID` | your Google Drive credential id |

---

## 3. Activate and test

1. Click the **Active** toggle (top right).
2. `On form submission` shows the form URL under **Webhook URLs**. Open it.
3. Submit a chapter PDF (try **Class XII → Solutions → NCERT** for a known-good first run).
4. Open **Executions** to watch each of the 12 nodes fire.
5. Check Drive — the file lands at
   `Question Bank/CBSE/Class XII/Solutions/Knowledge Base/SOLUTIONS_KNOWLEDGE.json`.

The `Log Phase 1 Summary` node's output is your audit record.

---

## 4. Editing the structurer prompt

The structurer system prompt is stored as a hidden form field (`SYSTEM_STRUCTURER`).

1. Open `On form submission`.
2. Scroll to the `SYSTEM_STRUCTURER` hidden field.
3. Edit `fieldValue` in place.
4. Save the workflow. The change is live on the next submission.

---

## 5. Common first-run issues

| Symptom | Fix |
|---|---|
| `Could not find property 'Reference_PDF'` on Extract PDF | n8n sometimes labels the field `Reference PDF` (with space). Open `Extract PDF Text & Metadata` → set Binary Property to whichever appears in the form-trigger output. |
| `Cleaned text is suspiciously short (<200 chars)` | The PDF is image-only / scanned. OCR it first (Tesseract / Acrobat) and re-upload. |
| `Structurer returned non-JSON` | Re-run; usually a transient model hiccup at T=0. If it persists, open `AI: Structure Chapter Knowledge` and inspect the raw output — add `Return STRICT JSON only` reinforcement to the user-message prefix. |
| `Knowledge object failed validation: …` | The structurer skipped required arrays. Inspect the LLM output in the failed execution; usually a stricter system prompt or a bigger `maxTokensToSample` fixes it. |
| Drive 403 on folder creation | OAuth scope too narrow. Re-auth with `drive.file` (or `drive`). |

---

## 6. What's stored (and what isn't)

Phase 1 saves exactly one artefact per chapter:

```
Question Bank/CBSE/<Class>/<Chapter>/Knowledge Base/<CHAPTER_CODE>_KNOWLEDGE.json
```

The full JSON shape is documented in `docs/data-contracts.md`. Phase 2 (prompt routing + question generation) will read this file as input — you can rerun Phase 1 freely on the same chapter (Drive will keep revisions of the same filename).
