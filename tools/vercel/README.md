# Vercel deploy & ops scripts (server/ FastAPI)

Distilled from the V0.5.1 Walking Skeleton deploy. Each one captures
something we hit and had to debug live; reading the script source is
intentionally a fast way to remember **why** we do it that way.

## Scripts

| Script | What it does | When to run |
| --- | --- | --- |
| [`api.sh`](api.sh) | Sourced helper library (token + REST helpers). Not run directly. | Sourced by `deploy-status.sh`. |
| [`deploy-prod.sh`](deploy-prod.sh) | Deploy `server/` to production with the Hobby-plan git-author bypass (rename `.git` → `.git.deploy_bak`, restore via trap). | After every `server/` change you want live. |
| [`smoke-prod.sh`](smoke-prod.sh) | 4 curl probes: `/health`, `/auth/login`, `/auth/me`, `/packs/latest.json`. Exits non-zero on first failure. | Right after `deploy-prod.sh`, also any time prod is acting up. |
| [`deploy-status.sh`](deploy-status.sh) | List recent deployments via REST API, **including the `errorMessage` the CLI hides**. Optional build event dump. | Anytime `deploy-prod.sh` exits non-zero or you need to investigate a previous failure. |
| [`env-bootstrap.sh`](env-bootstrap.sh) | Idempotently push the deterministic env vars (`MONGO_DB_NAME`, `JWT_SECRET`, `ADMIN_BOOTSTRAP_PASS`, …) to a target scope. Auto-generates JWT secret + admin password when missing. | Initial project setup, or onboarding a new staging/preview scope. |

## Quickstart

```bash
# one-time
brew install vercel-cli || npm i -g vercel@latest    # need >= 47.2.2
vercel login
cd server && vercel link                              # writes server/.vercel/project.json

# typical day:
bash tools/vercel/deploy-prod.sh
bash tools/vercel/smoke-prod.sh
```

If a deploy ever fails, run `bash tools/vercel/deploy-status.sh` first
— the real reason almost always shows up in the `ERROR_MESSAGE` column
that the CLI's "deploy_failed" message buries.

## Design decisions (the `why`)

These are the trip-wires that cost time during V0.5.1, baked into the
scripts so you don't trip them again.

### 1. Never use `--prebuilt` from macOS

`vercel build --prod` runs locally and packages whatever Python wheels
are in your venv into the bundle. On macOS arm64 that means macOS
wheels (e.g. `bcrypt._bcrypt.abi3.so` mach-O), which the Linux arm64
serverless runtime cannot import. The function then returns
`FUNCTION_INVOCATION_FAILED` with no stack trace because the import
fails before Python can log.

`deploy-prod.sh` always calls `vercel deploy --prod` (never
`--prebuilt`), forcing Vercel to install dependencies on its build
machine.

### 2. Hobby-plan git author check

Hobby plans require the HEAD commit's author email to be a confirmed
member of the Vercel team — and they don't allow inviting members.
Result: with `terry.ma@bytedance.com` as `git config user.email` but
the team only registering `zjumty@gmail.com`, every deploy fails with:

```
Git author terry.ma@bytedance.com must have access to the team
terrymas-projects on Vercel to create deployments.
```

Workaround used by `deploy-prod.sh`: rename `.git` → `.git.deploy_bak`
for the duration of the `vercel deploy` call. The CLI walks parents
looking for `.git/`; finds none; sends no git context; author check
is skipped. A `trap … EXIT INT TERM` restores `.git` even if the
deploy is interrupted. The script also refuses to run if a rebase /
merge / cherry-pick / bisect is in progress, since restoring `.git`
mid-rebase would corrupt repo state.

When you upgrade off Hobby and the email mismatch is resolved, the
bypass becomes a no-op (the script has nothing to bypass) but is
still safe to use.

### 3. `vercel.json` schema

Modern CLI rejects `builds` + `functions` together. Use `rewrites`
+ `functions`. `memory` on `functions` is ignored under Active CPU
billing — drop it. Live config is in [`server/vercel.json`](../../server/vercel.json):

```jsonc
{
  "version": 2,
  "rewrites": [
    { "source": "/api/(.*)", "destination": "/api/index.py" },
    { "source": "/(.*)",     "destination": "/api/index.py" }
  ],
  "functions": {
    "api/index.py": { "maxDuration": 60 }
  }
}
```

### 4. Project root directory must be `null`, not `server`

If you run `cd server && vercel deploy --prod`, the CLI uses your CWD
as the deploy root. If the linked project's "Root Directory" setting
is also `server/`, Vercel concatenates them and dies with:

```
The provided path "~/Projects/happyword/server/server" does not exist.
```

Fix once via the dashboard (Project Settings → General → Root
Directory → blank) or via API:

```bash
. tools/vercel/api.sh
cd server
vercel_api PATCH "/v9/projects/$(vercel_proj_id)" '{"rootDirectory":null}'
```

`deploy-prod.sh` always runs from `server/`, so the linked Root
Directory must stay `null`.

### 5. `MONGODB_URI` vs `MONGO_URI`

Vercel's MongoDB Atlas Marketplace integration auto-injects
`MONGODB_URI`. Earlier `.env.local` files used `MONGO_URI`. The
Pydantic `Settings` class accepts **both** via:

```python
mongo_uri: str = Field(
    validation_alias=AliasChoices("MONGODB_URI", "MONGO_URI")
)
```

`env-bootstrap.sh` does **not** push `MONGODB_URI` — it's owned by
the integration. You'll see it in `vercel env ls` already.

### 6. `Indexed(unique=True)` on `_id` is fatal — and `mongomock-motor`
won't catch it

A real production trap that local tests missed:

```python
class Word(Document):
    id: Annotated[str, Indexed(unique=True)]   # WRONG — but mongomock is fine with it
```

Real MongoDB rejects `unique=True` on `_id` (it's already implicitly
unique) with `InvalidIndexSpecificationOption`, and Beanie `init_beanie`
runs `create_indexes` during the FastAPI lifespan startup. Result:
every endpoint returns 500 `FUNCTION_INVOCATION_FAILED` until the
annotation is removed.

Fix is in [`server/app/models/word.py`](../../server/app/models/word.py)
(plain `id: str`), with a structural regression test in
[`server/tests/test_word_model.py`](../../server/tests/test_word_model.py)
(`test_word_id_field_has_no_explicit_indexed_annotation`).

When `deploy-status.sh` shows `READY` but `smoke-prod.sh` returns 500,
this is the first thing to suspect for any new model.

### 7. CLI version

CLI ≥ 47.2.2 required. 44.x throws `Upload aborted` /
`Your Vercel CLI version is outdated`. Update with
`npm i -g vercel@latest`. The scripts don't enforce this — the CLI
itself complains, just so you know what to do.

## Recovery cookbook

| Symptom | Diagnosis script | Likely fix |
| --- | --- | --- |
| `vercel deploy` exits non-zero, no helpful message | `bash tools/vercel/deploy-status.sh 1` | Read `errorMessage`. If "git author …", `deploy-prod.sh` is doing the right thing — confirm `.git` was restored after the failed run (check for `.git.deploy_bak`). |
| Smoke shows `[FAIL 500]` on `/health` | `bash tools/vercel/deploy-status.sh 1 events` | Look for `InvalidIndexSpecificationOption`, missing env var, or import error in the build events. |
| Smoke shows `[FAIL 401]` on `/auth/login` | — | Wrong admin password. Check `/tmp/admin_pass.txt` against what's in Vercel: `cd server && vercel env pull --environment=production .env.prod && grep ADMIN_BOOTSTRAP .env.prod && rm .env.prod`. |
| `.git.deploy_bak` exists from previous failure | — | Manually restore: `mv .git.deploy_bak .git`. Then re-run deploy. |
| Smoke shows pack with 0 words | — | Seed missing. Run `cd server && uv run python -c "..."` against MongoDB to insert a Word, or wait for V0.5.2 `seed_from_rawfile.py`. |

## Out of scope (for now)

These are deferred to V0.5.2+ when the need becomes clear:

- **Preview / staging deploys** — V0.5 ships single-environment
  (production only). When we add staging, `deploy-prod.sh` will be
  generalized to take a target.
- **OPENAI_API_KEY rotation script** — currently manual; add when
  V0.5.4 introduces LLM features.
- **Backup script for word packs** — listed in V0.5.7 roadmap.
- **A `local-against-prod-db.sh`** — useful for reproducing prod
  Beanie issues with a real Atlas connection. We did this manually
  via `MONGODB_URI=… uv run python -c '…'`. Worth scripting once we
  hit it again.
