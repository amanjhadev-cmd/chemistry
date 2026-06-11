# How to import this into n8n

The bundle is **two** workflow JSONs that talk to each other. Import the sub-workflow first so the main workflow can reference its id.

---

## 1. Create credentials (do this once)

In **n8n → Credentials → New**:

| Credential | Type | Notes |
|---|---|---|
| `Google Drive OAuth2` | Google Drive OAuth2 API | Sign in with the Google account that owns the destination folder. Scope `drive` (or `drive.file`) is fine. |
| `OpenRouter` | OpenRouter API | Paste your OpenRouter API key. (The sub-workflow uses `qwen/qwen3-235b-a22b-2507` — change if you prefer Claude / GPT-4o.) |
| `Gmail OAuth2` | Gmail OAuth2 | Used by the completion-email step. Skip if you don't want the email. |

Note the **credential IDs** (visible in the URL when you open each credential, e.g. `rkE6lGy0ggcpc3F4`). You'll paste them in step 4.

---

## 2. Import the **sub**-workflow first

1. **Workflows → ⋯ → Import from File** → pick `workflow/chemistry-question-generation-sub.json`.
2. Open each node with a red dot and pick the credential you created:
   - `Qwen3-Instruct` → OpenRouter
   - `Upload to Drive` → Google Drive OAuth2
3. **Save** the workflow (top right).
4. Copy its **workflow ID** from the URL (e.g. `/workflow/cm6PZRSEL2Q3PndE` → `cm6PZRSEL2Q3PndE`).

---

## 3. Import the **main** workflow

1. **Workflows → ⋯ → Import from File** → pick `workflow/chemistry-question-generation.json`.
2. Open the **`Call: QuestDrive Sub-Workflow`** node → in the Workflow dropdown, paste the sub-workflow id from step 2.4 (or pick it from the list).
3. Open every red-dotted node and pick the matching credential:
   - `Create Root Folder`, `Create Level Folder`, `Create Type Folder` → Google Drive OAuth2
   - `Send Completion Email` → Gmail OAuth2 (or delete this node if not needed)

---

## 4. Replace credential placeholders (optional shortcut)

If you'd rather edit the JSON before import, the two files contain placeholder strings you can find-and-replace:

| Placeholder | Replace with |
|---|---|
| `REPLACE_DRIVE_CRED_ID` | your Google Drive credential id |
| `REPLACE_OPENROUTER_CRED_ID` | your OpenRouter credential id |
| `REPLACE_GMAIL_CRED_ID` | your Gmail credential id |
| `REPLACE_SUB_WORKFLOW_ID` | sub-workflow id from step 2.4 |

---

## 5. Activate and test

1. **Activate** the main workflow (top right).
2. Open the form URL — `On form submission` node shows it under **Webhook URLs** after activation.
3. Fill the visible fields. The 18 hidden prompts are pre-filled, but if you ever want to tweak one, open the form node and edit `fieldValue` for that hidden field — no other change needed.
4. Submit. Watch **Executions** to see folders being created and the sub-workflow firing.
5. Check your Drive parent folder — the full tree should appear.

---

## 6. Common first-run issues

| Symptom | Fix |
|---|---|
| `Could not find workflow REPLACE_SUB_WORKFLOW_ID` | You forgot step 3.2. Re-open `Call: QuestDrive Sub-Workflow` and pick the sub-workflow. |
| `Folder URL` invalid | n8n expects a full Drive folder URL like `https://drive.google.com/drive/folders/<id>`. Don't paste just the id. |
| Sub-workflow errors with `questionPrompt is undefined` | The `Pack Prompt + Drive ID` node didn't pass through — re-check that the outer loop's Code node returns `prompt` not `Prompt` (case-sensitive). |
| LLM output has Markdown code-fences | The parser already strips them. If a question still shows leading whitespace, it's harmless — fix it in `Parse LLM HTML` if you want it cleaner. |
| 18-item outer loop stops at 3 | Open `Loop Over 18 Items (Outer)` → "Reset" → toggle on once if you re-run after a partial failure. |
| Drive folder `A&R` creates as `A_R` | Expected — the workflow already maps `A&R → AR` for the folder name; the JSON keeps `A&R` in metadata. |

---

## 7. Editing prompts

All 18 prompts live in the form-trigger node's `fieldValue` properties. To tweak (e.g. ask for 30 questions instead of 25):

1. Open `On form submission`.
2. Scroll to the hidden field (e.g. `EASY MCQ`).
3. Edit `fieldValue` in place.
4. Save the workflow. The change is live on the next submission — no other node needs to know.

This is the whole reason the prompts are stored as hidden form fields rather than in env vars or files: **one place to edit, versioned with the workflow**.
