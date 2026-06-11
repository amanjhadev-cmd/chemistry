# Architecture (post-refactor — MockGenie/QuestDrive pattern)

Two workflows, one form, 18 hidden prompts.

## Main workflow nodes

| # | Node | Type | Role |
|---|---|---|---|
| 1 | On form submission | formTrigger | 9 visible fields + 18 hidden prompt fields |
| 2 | Create Root Folder | googleDrive (folder) | Creates `{Board}-{Class}-{Subject}-Ch-{n}-{Chapter}-Co-{n}-{Concept}` under the user-supplied Folder URL |
| 3 | Generate 18 Question Prompts | code | Reshapes the 18 hidden fields into `[{level, items:[{type, prompt}, …]}]` |
| 4 | Create Level Folder | googleDrive (folder) | EASY / MEDIUM / HARD folders under the root |
| 5 | Loop Over 18 Items (Outer) | splitInBatches | Iterates per level; the "done" branch flows to Aggregate → Email, the "loop" branch flows into the next step |
| 6 | Expand Level → Types | code | For the current level expands its 6 (type, prompt) pairs and attaches the matching level-folder id |
| 7 | Create Type Folder | googleDrive (folder) | MCQ / VSA / SA / LA / AR / CASE_STUDY under the level folder |
| 8 | Pack Prompt + Drive ID | set | Carries `questionPrompt` and the new folder's `driveid` |
| 9 | Call: QuestDrive Sub-Workflow | executeWorkflow | Invokes the sub-workflow with 11 typed inputs |
| 10 | Aggregate | aggregate | Pools all completed iterations |
| 11 | Send Completion Email | gmail | Sends the operator a "done" mail |

Connections form a strict DAG; nothing is left dangling. The outer loop's "done" output feeds Aggregate, the "loop" output feeds the expansion, and Call Sub-Workflow loops back into the outer loop so all 3 levels are processed in turn.

## Sub-workflow nodes (QuestDrive)

| # | Node | Type | Role |
|---|---|---|---|
| 1 | When Executed by Another Workflow | executeWorkflowTrigger | Receives 11 typed inputs |
| 2 | Loop Over Items | splitInBatches | One iteration per (level × type) call |
| 3 | Extract QuestionType | code | Normalises `questionType` from `questionPrompt` if missing |
| 4 | AI Agent (Chemistry) | langchain.agent | System instructions + injects the (level × type) prompt and the chapter context |
| 5 | Qwen3-Instruct | lmChatOpenRouter | LLM credential for the agent (swap to Anthropic / OpenAI here) |
| 6 | Parse LLM HTML | code | Splits on `<p>QUESTION_START</p>` and parses each block. Branches by `QuestionType`: MCQ/A&R → options + correct letter(s); VSA/SA/LA → text answer; CASE_STUDY → whole cluster preserved |
| 7 | Convert to JSON File | convertToFile | One binary per question |
| 8 | Upload to Drive | googleDrive (file) | Drops `Q1.json … Q25.json` into the target type folder |

## Why two workflows

| Concern | Outcome |
|---|---|
| Execution-graph readability | 11 nodes per workflow vs 22+ jammed together |
| Independent retry | A failed (level × type) can be re-run by calling the sub-workflow alone, with the same 11 inputs |
| LLM provider swap | Touches only the sub-workflow (one model node) |
| Folder-tree replay | The main workflow's `Create Folder*` nodes are idempotent — re-running over an existing tree reuses the folders |

## Prompt routing

There is **no Switch** node. Routing is implicit in the form structure:

- 18 hidden fields are emitted under keys like `"EASY MCQ"`, `"MEDIUM VSA"`, …
- `Generate 18 Question Prompts` walks `levels × formats` and emits one record per level with a 6-item `items` array.
- `Expand Level → Types` (Code) reads `$runIndex` to know which level the outer loop is on and emits 6 items for that level.
- `Pack Prompt + Drive ID` ferries the right prompt and folder id into the sub-workflow call.

Adding a 19th prompt (or a new question type) is a 3-line change:
1. Add a hidden field to the form.
2. Append the type name to the `formats` array in `Generate 18 Question Prompts`.
3. Done — the loops widen automatically.

## Error / retry behaviour

- `On form submission`, `Create Root Folder`, `Generate 18 Question Prompts`, `Create Level Folder`, `Loop Over 18 Items (Outer)`, `Send Completion Email` all have `retryOnFail: true`. Transient Drive 5xx and OAuth refreshes self-heal.
- Sub-workflow inherits per-call retry from the main workflow's `executeWorkflow` call.
- If the LLM returns malformed HTML, `Parse LLM HTML` will simply produce 0 questions for that call — visible in Executions; the rest of the batch continues.

## What's intentionally not here

- **No structurer pre-pass.** The reference workflow passes the PDF directly to the agent and relies on prompt rigor; we follow that pattern. If hallucination rate is too high in your dataset, add a structurer call in the sub-workflow between Trigger and Agent.
- **No dedupe pass.** Reference assumes 25 questions per (level × type) is the unit and that human review is the next step. If you want dedupe, add a Code node between Parse LLM HTML and Convert to JSON File doing trigram Jaccard against prior runs.
- **No validator LLM pass.** Same logic — easy to add as another agent node after parsing.
