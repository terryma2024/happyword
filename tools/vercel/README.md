# Legacy Vercel deploy & ops scripts (server/ FastAPI)

CloudBase production now uses `https://happyword.com.cn`. These Vercel scripts
remain for the legacy `happyword.cool` HTTPS endpoint, which should return a
301 redirect to `https://happyword.com.cn`.

Distilled from the V0.5.1 Walking Skeleton deploy. Each one captures
something we hit and had to debug live; reading the script source is
intentionally a fast way to remember **why** we do it that way.

## Scripts

| Script | What it does | When to run |
| --- | --- | --- |
| [`api.sh`](api.sh) | Sourced helper library (token + REST helpers). Not run directly. | Sourced by `deploy-status.sh`. |
| [`deploy-prod.sh`](deploy-prod.sh) | Deploy `server/` to the legacy Vercel production slot. Sets repo-local `user.email = zjumty@gmail.com` (the Vercel team's recognized email) on first run, then verifies HEAD's author matches before deploying. | Only for maintaining the `happyword.cool` 301 redirect endpoint. Current application production deploys through CloudBase CD. |
| [`smoke-prod.sh`](smoke-prod.sh) | 4 curl probes: `/api/v1/public/health`, `/api/v1/admin/auth/login`, `/api/v1/admin/auth/me`, `/api/v1/public/packs/latest.json`. Exits non-zero on first failure. | For legacy Vercel rollback smoke, or ad hoc HTTP checks against an explicit base URL. |
| [`preview-health.sh`](preview-health.sh) | Fetch the live preview manifest from `https://happyword.com.cn/api/v1/public/preview-urls.json` and probe `/api/v1/public/health` on every legacy PR preview behind Vercel Deployment Protection. Reads `VERCEL_AUTOMATION_BYPASS_SECRET` from `~/.env`. Exits non-zero if any preview fails. | Only while legacy Vercel Preview rows remain in the manifest. |
| [`trigger-cron.sh`](trigger-cron.sh) | Trigger one or more cron HTTP endpoints declared in [`server/vercel.json`](../../server/vercel.json) (default: all). Adds `Authorization: Bearer $VERCEL_CRON_SECRET`. Reads `VERCEL_CRON_SECRET` from env or `~/.env`. Target defaults to `https://happyword.com.cn`; can target a preview by full `--url`, `--url-fragment`, or `--deployment-id`. | Legacy helper for Vercel-style cron endpoints or explicit URL ticks. Prefer CloudBase cron tooling for current production automation. |
| [`deploy-status.sh`](deploy-status.sh) | List recent Vercel deployments via REST API, **including the `errorMessage` the CLI hides**. Optional build event dump. | Anytime legacy `deploy-prod.sh` exits non-zero or you need to investigate previous Vercel state. |
| [`env-bootstrap.sh`](env-bootstrap.sh) | Idempotently push deterministic env vars (`MONGO_DB_NAME`, `JWT_SECRET`, `ADMIN_BOOTSTRAP_PASS`, …) to a Vercel target scope. Auto-generates JWT secret + admin password when missing. | Legacy Vercel setup only. |

## Quickstart

```bash
# one-time
brew install vercel-cli || npm i -g vercel@latest    # need >= 47.2.2
vercel login
cd server && vercel link                              # writes server/.vercel/project.json

# legacy rollback/archive only:
bash tools/vercel/deploy-prod.sh
bash tools/vercel/smoke-prod.sh
```

If a deploy ever fails, run `bash tools/vercel/deploy-status.sh` first
— the real reason almost always shows up in the `ERROR_MESSAGE` column
that the CLI's "deploy_failed" message buries.

## Project fact (do not guess)

The linked Vercel project uses **Project Settings → General → Root Directory =
`server`**. Only **`server/vercel.json`** is used for builds, `crons`, and
`git.deploymentEnabled`. A `vercel.json` at the Git repository root is **not**
read by this project. GitHub-triggered Vercel deployments are disabled and the
Vercel project is disconnected from its GitHub repository; use the manual CLI
deploy path only when maintaining the legacy `happyword.cool` 301 endpoint.
Details: [`.cursor/rules/vercel-root-directory.mdc`](../../.cursor/rules/vercel-root-directory.mdc).

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
Result: with `terry.ma@gmail.com` as `git config user.email` but
the team only registering `zjumty@gmail.com`, every deploy fails with:

```
Git author terry.ma@gmail.com must have access to the team
terrymas-projects on Vercel to create deployments.
```

Approach used by `deploy-prod.sh`: instead of hiding `.git/`, line
up the repo's git identity with the team-recognized email.

1. **Repo-local config** — on first run, the script writes
   `user.email = zjumty@gmail.com` and `user.name = zjumty` into
   this repo's `.git/config`. Repo-local; your global identity
   (e.g. `terry.ma@gmail.com`) is untouched. All future commits
   *in this repo* will be authored with the deploy email.

2. **HEAD verification** — the script then checks HEAD's author
   email and refuses to deploy if it doesn't match. We do **not**
   auto-rewrite history; the script prints two suggested commands
   so you can choose:

   ```bash
   # A) Amend HEAD (only if HEAD is unpushed, or you'll force-push):
   git -c user.email='zjumty@gmail.com' -c user.name='zjumty' \
       commit --amend --no-edit --reset-author

   # B) Add an empty marker commit (non-destructive):
   git -c user.email='zjumty@gmail.com' -c user.name='zjumty' \
       commit --allow-empty -m 'chore(deploy): production marker'
   ```

To use a different deploy identity:

```bash
DEPLOY_AUTHOR_EMAIL='you@example.com' \
DEPLOY_AUTHOR_NAME='You' \
    bash tools/vercel/deploy-prod.sh
```

### 3. `vercel.json` schema (modern Framework Preset, no `runtime` pin)

Modern CLI rejects the legacy `builds` + `functions` combo. The
**FastAPI Framework Preset** does the build for us as long as
`fastapi` is listed in `pyproject.toml` and a supported entrypoint
exists — the resulting deployment is a single Vercel Function that
catch-all-routes everything to the FastAPI app. We do **not** need
`rewrites` (the preset auto-installs them) and we must **not** set a
`runtime` value for the built-in Python runtime — `runtime:` in
`functions` is reserved for community runtimes
([docs](https://vercel.com/docs/functions/configuring-functions/runtime#other-runtimes)),
and `"@vercel/python@..."` there fails silently: the deployment goes
green but every URL returns Vercel's edge `404 NOT_FOUND` page.

Live config is in [`server/vercel.json`](../../server/vercel.json) (Vercel’s
deploy root is the **`server/`** subdirectory — see **Project fact** above). Do
**not** add a `functions` + `api/index.py` map for `maxDuration`: the FastAPI
preset does not match that pattern at build time. Set function max duration in
the Vercel dashboard instead.

Current shape (abbreviated):

```jsonc
{
  "$schema": "https://openapi.vercel.sh/vercel.json",
  "version": 2,
  "git": {
    "deploymentEnabled": false
  },
  "crons": [{ "path": "/api/v1/admin/cron/extract-pending", "schedule": "* * * * *" }]
}
```

`deploymentEnabled: false` is a defense-in-depth guard if the GitHub repository
is ever reconnected; commits or PRs still must not create new Vercel
deployments.

The companion knob is in [`server/pyproject.toml`](../../server/pyproject.toml):

```toml
[tool.vercel]
entrypoint = "api.index:app"
```

The preset's auto-discovery walks `app.py | index.py | server.py |
main.py` in `./`, `src/`, `app/`, `api/` looking for a top-level `app`
([docs](https://vercel.com/docs/functions/runtimes/python#python-entrypoints)).
Both `api/index.py` (re-export) and `app/main.py` (real definition)
match — without `tool.vercel.entrypoint` it is undefined which one
wins, and the loser's routes vanish. Pinning to the re-export
mirrors `uvicorn app.main:app` 1-for-1.

### 4. Root Directory is `server` (production setting)

This repo’s Vercel project keeps **Root Directory = `server`**. That matches
`deploy-prod.sh` (runs from `server/`) and makes **`server/vercel.json`** the
single source of truth.

If you ever see a CLI error about `.../server/server` not existing, it usually
means **Root Directory and working directory were both set to include
`server/` twice** — fix in the dashboard or align `vercel link` / CLI cwd with
[`vercel-root-directory.mdc`](../../.cursor/rules/vercel-root-directory.mdc). Do
not flip Root Directory to blank without **moving** `vercel.json` to the
repository root and updating this doc.

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
| `deploy-prod.sh` refuses with `HEAD commit ... is authored by ...` | — | Run one of the two `git -c user.email=...` commands the script just printed (amend or empty marker), then re-run. |
| `vercel deploy` exits non-zero, no helpful message | `bash tools/vercel/deploy-status.sh 1` | Read the `errorMessage` column — it has the real reason the CLI buries. |
| Smoke shows `[FAIL 500]` on `/health` | `bash tools/vercel/deploy-status.sh 1 events` | Look for `InvalidIndexSpecificationOption`, missing env var, or import error in the build events. |
| Smoke shows `[FAIL 401]` on `/auth/login` | — | Wrong admin password. Check `/tmp/admin_pass.txt` against what's in Vercel: `cd server && vercel env pull --environment=production .env.prod && grep ADMIN_BOOTSTRAP .env.prod && rm .env.prod`. |
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
