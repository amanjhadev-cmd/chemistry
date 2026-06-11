# Data contracts

## 1. Form submission

### Visible fields (user-facing)

| Field | Type | Required | Allowed values |
|---|---|---|---|
| Board | dropdown | yes | `CBSE`, `ICSE`, `ISC`, `MH` |
| Class | dropdown | yes | `CLASS IX`, `CLASS X`, `CLASS XI`, `CLASS XII` |
| Subject | dropdown | yes | `Chemistry` |
| Chapter Name | text | yes | |
| Chapter No (e.g. 1,2,3) | number | yes | |
| Concept Name | text | yes | |
| Concept No | number | yes | |
| Reference Document | file | yes | `.pdf` |
| Folder URL | text | yes | Drive folder URL `https://drive.google.com/drive/folders/<id>` |

### Hidden fields (prompts, set once)

18 fields, keyed `<LEVEL> <TYPE>`:

```
EASY MCQ, EASY VSA, EASY SA, EASY LA, EASY A&R, EASY CASE_STUDY,
MEDIUM MCQ, MEDIUM VSA, MEDIUM SA, MEDIUM LA, MEDIUM A&R, MEDIUM CASE_STUDY,
HARD MCQ, HARD VSA, HARD SA, HARD LA, HARD A&R, HARD CASE_STUDY
```

Each `fieldValue` is a full prompt instructing the LLM to produce 25 items.

## 2. Output of `Generate 18 Question Prompts`

```json
[
  { "level": "EASY",   "items": [
      { "type": "MCQ", "prompt": "ROLE: ..." },
      { "type": "VSA", "prompt": "ROLE: ..." },
      { "type": "SA",  "prompt": "ROLE: ..." },
      { "type": "LA",  "prompt": "ROLE: ..." },
      { "type": "A&R", "prompt": "ROLE: ..." },
      { "type": "CASE_STUDY", "prompt": "ROLE: ..." }
  ]},
  { "level": "MEDIUM", "items": [ ... 6 items ... ] },
  { "level": "HARD",   "items": [ ... 6 items ... ] }
]
```

## 3. Sub-workflow input (typed)

```json
{
  "Board": "CBSE",
  "Class": "CLASS XII",
  "Subject": "Chemistry",
  "Chapter Number": 1,
  "Chapter Name": "Solutions",
  "Concept Number": 2,
  "Concept Name": "Raoult's Law",
  "questionLevel": "MEDIUM",
  "questionType": "MCQ",
  "questionPrompt": "ROLE: ...full prompt for MEDIUM MCQ...",
  "driveid": "1aBcDeFgHiJ..."
}
```

## 4. LLM output contract

The agent is instructed to emit HTML, with every question prefixed by exactly:

```html
<p>QUESTION_START</p>
```

Per-type structure:

| Type | Structure after `QUESTION_START` |
|---|---|
| MCQ, A&R | `<p>question</p><ul><li>A] …</li>…<li>D] …</li></ul><p>Answer : B,D</p>` |
| VSA, SA, LA | `<p>question</p><p>Answer : …</p>` |
| CASE_STUDY | `<p>Passage: …</p><ol><li>(i) … Answer : C</li>… </ol>` |

## 5. Final per-question file (uploaded to Drive)

Filename: `Q<n>.json` inside the type folder.

```json
{
  "Metadata": {
    "board": "CBSE",
    "class": "CLASS XII",
    "subject": "Chemistry",
    "chapter_no": 1,
    "chapter_name": "Solutions",
    "concept_no": 2,
    "concept_name": "Raoult's Law",
    "question_level": "MEDIUM",
    "question_type": "MCQ"
  },
  "questionHtml": {
    "question_no": "Q1",
    "question_text": "<p>...</p>",
    "options": { "A": "...", "B": "...", "C": "...", "D": "..." },
    "final_answer": {
      "correct_option": "B,D",
      "model_answer": null
    }
  }
}
```

For written types (VSA / SA / LA): `options = {}`, `correct_option = ""`, `model_answer` holds the answer text.
For CASE_STUDY: `question_text` carries the parsed passage; `model_answer` carries the full original HTML cluster (4 sub-questions inline).

## 6. Drive layout

```
<Folder URL parent>/
  CBSE-CLASS XII-Chemistry-Ch-1-Solutions-Co-2-Raoult's Law/
    EASY/
      MCQ/  Q1.json … Q25.json
      VSA/  …
      SA/   …
      LA/   …
      AR/   …                           ← A&R is sanitised to AR for the folder name
      CASE_STUDY/  …
    MEDIUM/  …same six type folders
    HARD/    …same six type folders
```
