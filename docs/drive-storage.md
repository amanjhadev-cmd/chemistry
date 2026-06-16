# Google Drive Storage

## Per-batch folder hierarchy

Every batch's 6 artifacts land in a nested folder tree built deterministically
from the batch metadata:

```
<ROOT_FOLDER_ID>/
  QuestionBank/
    {board}/
      {class}/
        {subject}/
          {chapter_slug}/
            {question_type}/
              {difficulty}/
                {batch_id}/
                  GOOD_QUESTIONS.json
                  UPGRADE_QUESTIONS.json
                  BAD_QUESTIONS.json
                  REPORTS_BUNDLE.json
```

Example leaf:
`QuestionBank/cbse/12/chemistry/solutions/mcq/intermediate/BCH_M7QJX9YZ_ABCDEF12/`

## Drive Folder Resolver node

A Code node (`Drive Folder Resolver`) sits between `Agent 8 - Split Buckets +
Build 6 Artifacts` and the four Drive write nodes. On each run it:

1. Builds the 8-segment path array from `metadata`
   (`QuestionBank`, board, class, subject, chapter_slug, question_type,
   difficulty, batch_id).
2. Walks the tree from `ROOT_FOLDER_ID`, calling the Google Drive REST API via
   `this.helpers.httpRequestWithAuthentication(..., 'googleDriveOAuth2Api', ...)`:
   - **search** each segment: `GET /drive/v3/files?q=name='X' and 'PARENT' in parents and mimeType='application/vnd.google-apps.folder' and trashed=false`
   - **create** it only if not found: `POST /drive/v3/files` with `parents:[PARENT]`
   This is search-or-create, so re-running the same batch reuses every existing
   folder — only the genuinely-new `{batch_id}` leaf is created.
3. Returns the leaf folder id as `drive_leaf_folder_id`, plus everything Agent 8
   produced (spread through), so the four Drive nodes and four Postgres nodes
   downstream read from `$('Drive Folder Resolver')`.

The four Drive nodes set `folderId.value` to
`={{ $('Drive Folder Resolver').item.json.drive_leaf_folder_id }}`.

### Why downstream nodes reference the resolver explicitly

The Drive + Postgres nodes are chained linearly with `.to()`. After the first
Drive node runs, its output is `{ id: <fileId> }` — so a node that read `$json`
would no longer see Agent 8's `artifacts` / `good_questions` / etc. Every
downstream node therefore references `$('Drive Folder Resolver').item.json.X`
explicitly rather than `$json`. (This also fixed a latent bug where the
UPGRADE/BAD/Reports writes and all three PG inserts were reading the wrong
`$json`.)

## Configuration

| What | Where | Default |
|---|---|---|
| Root folder | `ROOT_FOLDER_ID` const inside the resolver's Code node | `PLACEHOLDER_DRIVE_ROOT_FOLDER_ID` |
| Drive credential | `googleDriveOAuth2Api` on the resolver Code node and the 4 Drive nodes | `Google Drive - QuestionBank` |

**One-time setup:** replace `PLACEHOLDER_DRIVE_ROOT_FOLDER_ID` with the Drive
folder id that should contain the `QuestionBank` tree (e.g. a dedicated project
folder, or `root` for My Drive). This is now the **only** place the root id is
configured — the four Drive write nodes no longer carry their own placeholder.

## Idempotency

Each Drive write carries `appProperties`:
- `batchId` — the batch id
- `bucket` — good / upgrade / bad / reports
- `folderPath` — the human-readable nested path
- `idempotencyKey` — `{batch_id}_{bucket}` (good/upgrade/bad)

A future enhancement can pre-search by `appProperties.idempotencyKey` and skip
the write if the file already exists, making re-runs fully idempotent on the
Drive side. (The Postgres side is already idempotent via
`ON CONFLICT (canonical_question_id) DO NOTHING`.)

## Degraded mode

If any Drive API call throws (auth expired, rate limit, network), the resolver
catches it, sets `drive_resolver_degraded = true` + `drive_resolver_degraded_reason`,
and falls back to `ROOT_FOLDER_ID` as the target. The audit log row records
`drive_resolver_degraded` so degraded runs are queryable:

```sql
SELECT batch_id, payload->>'drive_resolver_degraded' AS degraded,
       payload->>'folder_path' AS path
FROM generation_audit_log
WHERE stage = 'complete'
  AND (payload->>'drive_resolver_degraded')::boolean = true
ORDER BY created_at DESC;
```

If the root id itself is the unreplaced placeholder, the GOOD write (which has
no `onError` override) will hard-fail and trigger the error sub-workflow — a
loud, intentional failure rather than silently writing to the wrong place.

## The drive_folder_cache table (v2, not yet wired)

`db/migrations/0009_drive_folder_cache.sql` creates a `path → folder_id` cache.
The resolver does **not** use it yet — v1 walks the Drive API live every run.
Since intermediate folders (`QuestionBank/cbse/12/chemistry/...`) are reused
across thousands of batches, v2 will:

1. `SELECT folder_id FROM drive_folder_cache WHERE path = $1` for the longest
   known prefix.
2. Walk only the un-cached tail via the Drive API.
3. Insert newly-created segments back into the cache.
4. Bump `last_used_at` on hits (drives an LRU eviction policy if the cache ever
   needs trimming).

This turns the typical run from 8 Drive API round-trips into 1 (just the new
`{batch_id}` leaf).
