# Error Handling

## The error sub-workflow

A separate n8n workflow that catches **unhandled** failures from the main
Question Generation v1.0 workflow (`HKYbMEHdN2034xxM`).

| | |
|---|---|
| Workflow ID | `teW9SmrspnNlsNuT` |
| Name | `Question Generation v1.0 - Error Handler` |
| URL | https://devvrat.app.n8n.cloud/workflow/teW9SmrspnNlsNuT |
| Trigger | `Error Trigger` node — fires when any linked workflow throws |

### Pipeline (7 nodes)

```
Error Trigger
   → Extract Error Context           Code: parses error payload; best-effort batch_id from regex
   → Insert error_audit              Postgres: full forensic row (raw_error + execution_url + workflow ids)
   → Insert generation_audit_log     Postgres: stage='error', status='fail', joinable with the batch
   → Notify Operators (Slack)        HTTP: Slack incoming-webhook with formatted blocks (replace URL)
   → Summary                         Set: handled_at, batch_id, error_code, persisted_to flags
```

Failures of the persistence nodes themselves are tolerated:
`onError: continueRegularOutput` + `retryOnFail: 3 × 2s exp` so a Postgres
hiccup doesn't swallow the operator notification.

### What gets captured

Per row in `error_audit`:
| Column | Source |
|---|---|
| `batch_id` | Best-effort regex match on `BCH_[A-Z0-9_]+` anywhere in the error payload. Often present for late-pipeline failures; null for early ones |
| `error_code` | `execution.error.name` / `.type` / `.code`, falls back to `UNKNOWN_ERROR` |
| `error_message` | `execution.error.message`, truncated to 2000 chars |
| `node_name` | `execution.error.node.name` (the failing node) or `execution.lastNodeExecuted` |
| `payload` (jsonb) | Full execution context: `workflow_id`, `workflow_name`, `execution_id`, `execution_url`, `last_node_executed`, `retry_of`, `raw_error` |

## Linkage (manual one-time setup)

The n8n SDK `update_workflow` API doesn't expose the workflow-level
`errorWorkflow` setting, so this has to be done in the UI:

1. Open https://devvrat.app.n8n.cloud/workflow/HKYbMEHdN2034xxM
2. Click the **gear icon** (top right) → **Settings**
3. Find **Error Workflow**
4. Select **Question Generation v1.0 - Error Handler** from the dropdown
5. Click **Save**

Repeat for any other workflow you want covered by the same handler.

After linking, every unhandled error in the main workflow will trigger this
handler automatically — no further wiring needed.

## Configuration after import

Three manual changes after creating the workflow:

| Node | What to change |
|---|---|
| `Insert error_audit` | Attach `Postgres - Master DB` credential (auto-assigned if it already exists) |
| `Insert generation_audit_log (status=error)` | Same Postgres credential |
| `Notify Operators (Slack)` | Replace the placeholder URL `https://hooks.slack.placeholder/services/REPLACE_ME` with your real Slack incoming-webhook URL. To disable Slack entirely, set the node to disabled in the UI |

## What still doesn't get caught

The handler covers **unhandled** errors. The main workflow already absorbs
many failure modes via `onError: continueRegularOutput` (KB cache write,
Drive uploads, all 4 PG inserts, audit log) — those degrade silently and
don't fire this handler. That's intentional: a Drive upload failing
shouldn't block the rest of the batch.

To find these "silent degraded" runs:
```sql
SELECT batch_id, stage, status, payload->>'shortfall' AS shortfall
FROM generation_audit_log
WHERE created_at > now() - interval '24 hours'
  AND (status = 'success' AND (payload->>'shortfall')::boolean = true);
```

## Verifying the handler works

Temporarily make the main workflow fail intentionally (e.g. toggle the
Postgres credential off on `Knowledge Cache Lookup` and submit a batch),
then:

```sql
SELECT err_id, batch_id, error_code, node_name, created_at
FROM error_audit
ORDER BY err_id DESC
LIMIT 5;

SELECT log_id, batch_id, stage, status, payload->>'error_code' AS code
FROM generation_audit_log
WHERE status = 'fail'
ORDER BY log_id DESC
LIMIT 5;
```

Both should show a row for the synthetic failure. The Slack notification
should also have fired (check the channel).
