# TODO — E2E preview job is blocked on a missing repo secret

**Status:** open. The `server / e2e (preview)` GitHub Actions job has now
failed identically on at least four consecutive runs (PR #33 → run
[`25476007013`](https://github.com/terryma2024/happyword/actions/runs/25476007013),
PR #35 → run
[`25476206872`](https://github.com/terryma2024/happyword/actions/runs/25476206872),
PR #36 → run
[`25476415304`](https://github.com/terryma2024/happyword/actions/runs/25476415304),
and PR #37 → run
[`25476569747`](https://github.com/terryma2024/happyword/actions/runs/25476569747))
for the same purely-environmental reason: the GitHub repository secret
`VERCEL_AUTOMATION_BYPASS_SECRET` is unset, the Vercel preview deployment
of the PR is protected by Vercel Authentication (SSO), and so every E2E
fixture is short-circuited by the session-scoped preflight in
[`server/tests/e2e/conftest.py`](tests/e2e/conftest.py) with the message:

> `Failed: E2E preflight: target https://… is protected by Vercel Authentication (the SSO HTML challenge was returned for /api/v1/health) and VERCEL_AUTOMATION_BYPASS_SECRET is not set.`

That preflight is the **diagnostic shim** added by commit `efa0f1b` —
it is intentionally loud so the failure annotation is one actionable
message instead of 50+ confusing JSONDecodeError stack traces. The
preflight, the bypass header plumbing in
[`tests/e2e/_utils/client.py`](tests/e2e/_utils/client.py) (commit
`2bf58cb`), and the workflow line in
[`.github/workflows/server-ci.yml`](../.github/workflows/server-ci.yml)
that forwards `VERCEL_AUTOMATION_BYPASS_SECRET: ${{ secrets.VERCEL_AUTOMATION_BYPASS_SECRET }}`
to pytest are all behaving exactly as designed. **No code change can make
these E2E cases pass; only a maintainer-side environment change can.**

## Maintainer action required

Pick **one**:

- [ ] **Recommended.** Generate a Protection Bypass token in
      **Vercel → Project (`happyword`) → Settings → Deployment
      Protection → Protection Bypass for Automation**, then add it to
      **GitHub → repo Settings → Secrets and variables → Actions** as
      `VERCEL_AUTOMATION_BYPASS_SECRET`. Re-run the failed
      `server / e2e (preview)` job on the affected PR(s). Docs:
      <https://vercel.com/docs/deployment-protection/methods-to-bypass-deployment-protection/protection-bypass-automation>.
- [ ] **Alternative.** Disable Vercel Authentication on Preview
      deployments under the same Deployment Protection screen. Less
      secure (anyone with the preview URL can hit the API) but
      requires no GitHub-side change.

After either of those, this file should be deleted in the same PR that
re-runs the E2E job and observes the suite back to green.

## Why this is tracked in the repo (not just in PR descriptions)

PR #35 already has this TODO in its description, but description
checklists do not survive PR merges, are easy to miss in the GitHub
notification firehose, and offer no way for a future contributor doing
`grep` on the repo to discover the blocker. A repo-tracked
`E2E_PREVIEW_TODO.md` is the smallest possible signal that survives
merges and is greppable.

## Don't bother retrying the autofix loop

The Cursor autofix workflow (`cursor / autofix e2e (preview)` in
`server-ci.yml`) is correctly gated on `needs.server_e2e.result ==
'failure'` and will keep firing on every run that lands here, but it
**cannot** resolve this class of failure — secrets cannot be set from
inside an Actions run. Leaving this file in place is also a signal to
the autofix agent that the next failure for the same reason should
just acknowledge the blocker instead of opening another doc-only PR.

Refs: PR #33, PR #35, PR #36, PR #37.
