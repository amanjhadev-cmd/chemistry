# Visual Question Rubric

Only applies when `metadata.include_visual_questions = true` and at least one
visual reference is present in `chapter_knowledge.visuals[]`.

**Rules**
- Reference a visual by its `visual_id` only. Do not paraphrase or redescribe what's in the image — the rendering layer will inline the asset.
- Place the reference using the placeholder syntax: `[VISUAL:{visual_id}]` in the question stem.
- Set `visual_required = true` and populate `visual_refs[]` with the visual_id(s) used.
- Do not invent visuals. Only use visual_ids present in `chapter_knowledge.visuals[]`.
- The question must be answerable from the visual + chapter knowledge. No outside diagrams.

**Visual types supported (from extractor)**
- `diagram` — labelled illustration
- `graph` — x/y plot or bar chart
- `table` — already extracted as text via Camelot; reference by `table_id` if present
- `data_interpretation` — combines numerical data + visual context
- `flowchart` — process / decision flow
- `chemical_structure` — molecular structure diagram
- `circuit_diagram` — electrical schematic
- `map_based` — labelled map

**Accessibility**
- The validator will reject questions where the visual is decorative (i.e. the stem makes sense without it). Visuals must be load-bearing.
