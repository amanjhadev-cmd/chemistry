# How to import into n8n

Single workflow, two credentials, one activate toggle.

---

## 1. Credentials (one-time)

In **Credentials → New**:

| Credential | Type | Notes |
|---|---|---|
| `Anthropic` | Anthropic API | Paste your `sk-ant-...` key. The workflow uses Sonnet (generator) and Haiku (structurer + validator). |
| `Google Drive OAuth2` | Google Drive OAuth2 API | Sign in with the Google account that owns the destination Drive. Scope `drive` (or `drive.file`) is sufficient. |

Note each credential's **ID** from the URL when you open the credential (e.g. `rkE6lGy0ggcpc3F4`).

---

## 2. Import the workflow

**Workflows → ⋯ → Import from File** → pick `workflow/chemistry-question-generation.json`.

Open each red-dotted node and bind:

| Node | Credential |
|---|---|
| Structure Chapter Knowledge | Anthropic |
| AI: Generate Questions | Anthropic |
| AI: Validate Questions | Anthropic |
| Ensure Drive Folders | Google Drive OAuth2 |
| Load Existing Bank Stems | Google Drive OAuth2 |
| Upload to Google Drive | Google Drive OAuth2 |

### Or: find-and-replace in the JSON before import

| Placeholder | Replace with |
|---|---|
| `REPLACE_ANTHROPIC_CRED_ID` | your Anthropic credential id |
| `REPLACE_DRIVE_CRED_ID` | your Google Drive credential id |

---

## 3. Activate and test

1. Click the **Active** toggle (top right).
2. `On form submission` shows the form URL under **Webhook URLs**. Open it.
3. Submit a chapter PDF (try Class XII → Solutions → NCERT → MCQ → MEDIUM → 5 questions for a fast first run).
4. Open **Executions** to watch each node fire.
5. Check Drive — the file lands at `Question Bank/CBSE/Class XII/Solutions/MCQ/MEDIUM/Solutions_MCQ_MEDIUM_<batchId>.json`.

---

## 4. Editing prompts

All 18 templates + the 3 system prompts live as `hiddenField` entries on the form node. To tweak:

1. Open `On form submission`.
2. Scroll to e.g. `PROMPT_MCQ_HARD`.
3. Edit `fieldValue` in place.
4. Save the workflow. The change is live on the next submission.

This is exactly the MockGenie pattern: prompts versioned with the workflow, single source of truth, no env vars or external files.

---

## 5. Common first-run issues

| Symptom | Fix |
|---|---|
| `Could not find property 'Reference_PDF'` on Extract PDF | n8n sometimes converts the field label to `Reference_PDF` or `Reference PDF`. Open `Extract PDF Text` → set Binary Property to whichever appears in the form-trigger output. |
| `Missing hidden prompt field: PROMPT_AR_HARD` | A hidden field got deleted by accident. Re-import the workflow JSON or re-add the missing `hiddenField`. |
| Drive 403 on folder create | OAuth scope is too narrow. Re-auth with `drive.file` or `drive`. |
| `Generator returned non-JSON` | Model wrapped the output in a markdown fence. `Parse Generation` strips ```` ```json ```` and ```` ``` ```` already; if it still trips, re-prompt with `Return ONLY JSON, no markdown.` appended to the user message. |
| `IF` infinite loops | `Need Regeneration?` bounds attempts to 3. If you see >3 attempts, check that `Build Prompt` is incrementing `attempt`. |

---

## 6. Optional: swap LLM provider

Replace the three Anthropic nodes with OpenRouter / OpenAI / Gemini equivalents. Prompts are provider-neutral. You only need to map the response field in `Parse Generation` / `Filter Valid Questions` (currently reads `$json.content[0].text`).
