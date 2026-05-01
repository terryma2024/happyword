# Server operations runbook (V0.5.x)

This is the operator-facing runbook for the FastAPI service at
`server/`. Every procedure below uses curl + the public API; the only
operator UI is the terminal until the admin web app lands in V0.6.

> Conventions used throughout
> - `${API}` — the deployed base URL (e.g. `https://happyword.vercel.app`).
> - `${ADMIN_USER}` / `${ADMIN_PASS}` — the admin credentials seeded via
>   `ADMIN_BOOTSTRAP_USER` / `ADMIN_BOOTSTRAP_PASS` env vars.
> - Replace `<…>` placeholders before pasting.

---

## 0. Bootstrap

The first time the service starts on a fresh Mongo, the lifespan hook
(`server/app/main.py`) does the following idempotent steps:

1. Connects to Mongo (`MONGODB_URI`, `MONGO_DB_NAME`).
2. Initialises Beanie with all document models (User, Word, WordPack,
   PackPointer, LlmDraft, Category, LessonImportDraft).
3. Inserts the admin user from `ADMIN_BOOTSTRAP_USER` /
   `ADMIN_BOOTSTRAP_PASS` if it does not yet exist.
4. Upserts the 5 manual category seeds (`fruit`, `place`, `home`,
   `animal`, `ocean`) — their `story_zh` defaults are baked into
   `app/services/category_service.py`.

No further manual setup is required.

## 1. Login → access token

```bash
ACCESS_TOKEN=$(curl -s -X POST "${API}/api/v1/auth/login" \
  -H 'content-type: application/json' \
  -d "{\"username\":\"${ADMIN_USER}\",\"password\":\"${ADMIN_PASS}\"}" \
  | jq -r .access_token)
```

All subsequent admin requests require `-H "Authorization: Bearer ${ACCESS_TOKEN}"`.

## 2. Stats glance

```bash
curl -s "${API}/api/v1/admin/stats" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | jq
```

Use `llm_draft_pending` / `lesson_import_draft_pending` as queue-depth
indicators. `latest_version` is `null` until the first publish.

## 3. Words — CRUD

```bash
# List (excludes soft-deleted by default)
curl -s "${API}/api/v1/admin/words?page=1&size=50" -H "Authorization: Bearer ${ACCESS_TOKEN}"

# Get one
curl -s "${API}/api/v1/admin/words/fruit-apple" -H "Authorization: Bearer ${ACCESS_TOKEN}"

# Create
curl -s -X POST "${API}/api/v1/admin/words" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H 'content-type: application/json' \
  -d '{"id":"fruit-banana","word":"banana","meaningZh":"香蕉","category":"fruit","difficulty":1}'

# Update (partial merge)
curl -s -X PUT "${API}/api/v1/admin/words/fruit-banana" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H 'content-type: application/json' \
  -d '{"difficulty":2}'

# Soft-delete (sets deleted_at; row stays for audit)
curl -s -X DELETE "${API}/api/v1/admin/words/fruit-banana" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}"
```

To seed the initial 50-word baseline from `client/.../rawfile/data/words_v1.json`:

```bash
cd server && uv run python scripts/seed_from_rawfile.py
```

The script is idempotent — admin-edited rows are never overwritten.

## 4. LLM word-level drafts

Generate a draft → review → approve. The draft sits in `llm_drafts`
until reviewed; only `approve` writes to the actual `Word` row.

```bash
# Generate
curl -s -X POST "${API}/api/v1/admin/words/fruit-apple/generate-distractors" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}"
curl -s -X POST "${API}/api/v1/admin/words/fruit-apple/generate-example" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}"

# Review queue
curl -s "${API}/api/v1/admin/drafts?status=pending" -H "Authorization: Bearer ${ACCESS_TOKEN}"

# Edit if needed (PATCH only allowed while pending)
curl -s -X PATCH "${API}/api/v1/admin/drafts/<DRAFT_ID>" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H 'content-type: application/json' \
  -d '{"content":{"distractors":["pear","plum","kiwi"]}}'

# Approve / reject
curl -s -X POST "${API}/api/v1/admin/drafts/<DRAFT_ID>/approve" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}"
curl -s -X POST "${API}/api/v1/admin/drafts/<DRAFT_ID>/reject" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}"
```

Approval merges `content` into the matching Word row and bumps the
pack snapshot to `schema_version=2` on next publish.

## 5. Categories — CRUD

```bash
# List
curl -s "${API}/api/v1/admin/categories" -H "Authorization: Bearer ${ACCESS_TOKEN}"

# Create
curl -s -X POST "${API}/api/v1/admin/categories" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H 'content-type: application/json' \
  -d '{"id":"weather","label_en":"Weather","label_zh":"天气","story_zh":"小精灵的天气日记…"}'

# Update / delete (DELETE is blocked if any Word references the category)
curl -s -X PUT "${API}/api/v1/admin/categories/weather" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H 'content-type: application/json' \
  -d '{"story_zh":"新的故事…"}'

curl -s -X DELETE "${API}/api/v1/admin/categories/weather" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}"
```

## 6. Lesson photo import

```bash
# Upload a textbook page photo → creates a pending LessonImportDraft
curl -s -X POST "${API}/api/v1/admin/lessons/import" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -F image=@/path/to/page.jpg

# Review the queue
curl -s "${API}/api/v1/admin/lesson-drafts?status=pending" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}"

# Optionally edit the OpenAI Vision extraction (only while pending)
curl -s -X PATCH "${API}/api/v1/admin/lesson-drafts/<DRAFT_ID>" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H 'content-type: application/json' \
  -d '{"edited_extracted":{"category_id":"school-supplies","label_en":"School Supplies","label_zh":"学校用品","words":[{"word":"pencil","meaningZh":"铅笔","difficulty":1}]}}'

# Approve creates/updates the Category and inserts every word whose id
# does NOT already exist (admin edits are preserved). Reject leaves the
# DB untouched.
curl -s -X POST "${API}/api/v1/admin/lesson-drafts/<DRAFT_ID>/approve" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}"
curl -s -X POST "${API}/api/v1/admin/lesson-drafts/<DRAFT_ID>/reject" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}"
```

## 7. Word assets (illustration + audio)

```bash
# Upload illustration (PNG/JPEG/WebP, ≤ 2 MiB)
curl -s -X POST "${API}/api/v1/admin/words/fruit-apple/illustration" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -F image=@/path/to/apple.png

# Upload audio (MP3/M4A, ≤ 500 KiB)
curl -s -X POST "${API}/api/v1/admin/words/fruit-apple/audio" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -F audio=@/path/to/apple.mp3

# Delete (clears DB field + best-effort Blob delete)
curl -s -X DELETE "${API}/api/v1/admin/words/fruit-apple/illustration" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}"
curl -s -X DELETE "${API}/api/v1/admin/words/fruit-apple/audio" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}"
```

Re-upload deletes the previous Blob object first. The Blob is private
to Vercel until the URL is referenced from a published pack.

## 8. Publish / rollback / preview

```bash
# Snapshot the current Words + referenced Categories into a new WordPack
curl -s -X POST "${API}/api/v1/admin/packs/publish" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H 'content-type: application/json' \
  -d '{"notes":"weekly release"}'

# Pointer status (current + previous version, schema_version)
curl -s "${API}/api/v1/admin/packs/current" -H "Authorization: Bearer ${ACCESS_TOKEN}"

# Inspect a specific pack JSON
curl -s "${API}/api/v1/admin/packs/3" -H "Authorization: Bearer ${ACCESS_TOKEN}"

# Roll back one step (current ↔ previous swap)
curl -s -X POST "${API}/api/v1/admin/packs/rollback" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}"

# Public read path used by the HarmonyOS client (ETag/304 enabled)
curl -i "${API}/api/v1/packs/latest.json"
```

`schema_version` evolves with content shape:

| schema_version | Trigger                                                 |
|----------------|---------------------------------------------------------|
| 1              | Baseline (5-field word).                                |
| 2              | Any word has `distractors` or `example`.                |
| 4              | Any referenced category present.                        |
| 5              | Any word has `illustrationUrl` or `audioUrl`.           |

(`v3` is intentionally skipped — see V0.5 spec §6.7.)

## 9. Off-site backup

```bash
cd server && uv run python scripts/backup_pack.py            # writes dist/pack-backup-<ts>.json
cd server && uv run python scripts/backup_pack.py --out-dir /tmp/hwbackups
```

The JSON is human-readable: `{schema, exported_at, pointer, packs[]}`.
Restore is currently manual: `mongo` shell + the JSON. A
`scripts/restore_pack.py` is on the V0.6 backlog.

## 10. Routine ops checklist

Daily:

- `GET /admin/stats` — confirm `llm_draft_pending` and
  `lesson_import_draft_pending` are not stranded > 24 h.
- Review any backlog (`status=pending` queues) before approving the
  weekly publish.

Weekly:

1. `scripts/backup_pack.py` (off-site copy).
2. Approve any pending drafts you want shipped.
3. `POST /admin/packs/publish` with a release note.
4. Smoke-test `GET /api/v1/packs/latest.json` (status 200, ETag
   bumped). Verify on a dev device.

If something goes wrong:

- `POST /admin/packs/rollback` flips the pointer to the previous
  version. The bad pack stays in the collection for audit.
- A second rollback oscillates back to the broken version — re-publish
  a fix instead.

## 11. Environment variables

| Var                       | Purpose                                              |
|---------------------------|------------------------------------------------------|
| `MONGODB_URI`             | Connection string (Atlas / local).                   |
| `MONGO_DB_NAME`           | Database name (default `happyword`).                 |
| `JWT_SECRET`              | ≥ 32 byte secret for signing access tokens.          |
| `ADMIN_BOOTSTRAP_USER`    | Username seeded on first start.                      |
| `ADMIN_BOOTSTRAP_PASS`    | Plain password for that user (hashed at rest).       |
| `OPENAI_API_KEY`          | Required for `/admin/llm/*`, `/admin/lessons/*`.     |
| `OPENAI_MODEL_VISION`     | Default `gpt-4o`.                                    |
| `OPENAI_MODEL_TEXT`       | Default `gpt-4o-mini`.                               |
| `BLOB_READ_WRITE_TOKEN`   | Required for live Vercel Blob uploads (lessons + word assets). |
| `CORS_ALLOW_ORIGINS`      | Comma-separated origins (defaults to `*`).           |
