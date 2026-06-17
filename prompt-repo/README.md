# Prompt Repository

Templates, schemas, and rubrics consumed by the n8n workflow
`Question Generation v1.0`. Loaded by `Agent 4 - Resolve Prompt + Inject Context`.

## Layout

```
prompt-repo/
  generators/   # Jinja2 templates rendered into the AI Call 1 user message
  validators/   # Jinja2 templates rendered into the AI Call 2 user message
  rubrics/      # Markdown snippets included by reference from templates
    difficulty/{easy,intermediate,hard}.vN.md
    visual/general.vN.md
    question_type/{mcq,la,...}.vN.md
  schemas/
    output/{question_type}.vN.json    # JSON Schema for AI Call 1 output
    contracts/*.schema.json           # Inter-agent boundary contracts
  manifest.json                       # Source of truth for active versions
```

## Hierarchical fallback (deterministic, no AI)

`Agent 4` walks these keys in order, takes the first hit in `manifest.json`:

1. `{board}_{class}_{subject}_{question_type}_{difficulty}`
2. `{board}_{class}_{subject}_{question_type}`
3. `{board}_{class}_{subject}`
4. `{board}_{subject}_{question_type}`
5. `{board}_{question_type}`
6. `global_{question_type}_{difficulty}`
7. `global_{question_type}`
8. `global_default`

Onboarding a new board/subject/qtype = add files + bump `manifest.json`. No
workflow change.

## Versioning

Templates are immutable per version (`.v1.j2`, `.v2.j2`, ...). To roll out a
new version, write `.vN+1.j2` and flip the `version` pointer in
`manifest.json`. Rollback = flip the pointer back.

## Template variables

Templates receive (all populated by Agent 4):

- `metadata` — full canonical metadata object
- `curriculum_constraints` — board/class/qtype/difficulty rules
- `chapter_knowledge` — extracted KB (truncated to ~8KB for token budget)
- `rubrics.difficulty` — markdown text from `rubrics/difficulty/{difficulty}.md`
- `rubrics.question_type` — markdown text from `rubrics/question_type/{qtype}.md`
- `rubrics.visual` — markdown text from `rubrics/visual/general.md` (if visuals enabled)
- `output_schema` — JSON Schema string for the validator to enforce
- `requested_count` / `draft_count` — overgenerated count for AI Call 1
- `duplicate_candidates` — only for validator templates
- `drafts` — only for validator templates

## Strict rules (apply to every template)

1. Output JSON only. No markdown, no code fences, no prose.
2. Use only facts from `chapter_knowledge`. No outside knowledge.
3. Cite `source_section_ids` + `source_pages` per question.
4. Respect `curriculum_constraints.forbidden_patterns` exactly.
5. Respect `curriculum_constraints.bloom_levels_allowed` exactly.
