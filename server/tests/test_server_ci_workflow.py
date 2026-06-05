from pathlib import Path


def _server_ci_workflow() -> str:
    repo_root = Path(__file__).resolve().parents[2]
    return (repo_root / ".github" / "workflows" / "server-ci.yml").read_text(
        encoding="utf-8"
    )


def _workflow(name: str) -> str:
    repo_root = Path(__file__).resolve().parents[2]
    return (repo_root / ".github" / "workflows" / name).read_text(encoding="utf-8")


def _step_with_id(workflow: str, step_id: str) -> str:
    id_marker = f"        id: {step_id}"
    id_index = workflow.index(id_marker)
    start = workflow.rfind("\n      - name:", 0, id_index)
    end = workflow.find("\n      - name:", id_index)
    return workflow[start : end if end != -1 else len(workflow)]


def _step_named(workflow: str, name: str) -> str:
    start = workflow.index(f"      - name: {name}")
    end = workflow.find("\n      - name:", start + 1)
    return workflow[start : end if end != -1 else len(workflow)]


def test_server_ci_runs_cloudbase_staging_e2e_without_legacy_vercel_preview() -> None:
    """PR CI uses CloudBase staging E2E; legacy Vercel preview E2E is retired."""
    workflow = _server_ci_workflow()

    assert "  server_e2e:" not in workflow
    assert "Deploy Vercel preview (E2E-controlled)" not in workflow
    assert "VERCEL_TOKEN" not in workflow
    assert "VERCEL_CLI_VERSION" not in workflow
    assert "  update_manifest:" not in workflow
    assert "node server/scripts/update_preview_manifest.mjs" not in workflow
    assert "  cloudbase_staging_e2e:" in workflow
    assert "E2E_BASE_URL: ${{ secrets.CLOUDBASE_STAGING_BASE_URL }}" in workflow
    assert '"$UV_BIN" run --python 3.12 python scripts/e2e_reset_db.py' in workflow
    assert '"$UV_BIN" run --python 3.12 pytest -v -m e2e' in workflow


def test_cursor_autofix_action_is_removed() -> None:
    """The Cursor autofix workflow was retired from server CI."""
    workflow = _server_ci_workflow()

    assert "cursor_autofix_e2e" not in workflow
    assert "CURSOR_API_KEY" not in workflow
    assert "trigger-cursor-fix-e2e.mjs" not in workflow


def test_legacy_vercel_e2e_is_removed() -> None:
    workflow = _server_ci_workflow()
    assert "Validate E2E MongoDB URI" not in workflow
    assert "VERCEL_E2E_MONGODB_URI" not in workflow
    assert "Prune stale E2E PR databases" not in workflow
    assert "Reset E2E database (truncate test collections)" not in workflow
    assert "Run E2E pytest subset" not in workflow


def test_cloudbase_staging_e2e_runs_for_server_prs_without_label_gate() -> None:
    workflow = _server_ci_workflow()

    assert "workflow_dispatch:" in workflow
    assert "cloudbase-smoke" not in workflow
    assert "github.event.action == 'labeled'" not in workflow

    smoke_job_start = workflow.index("  cloudbase_staging_e2e:")
    smoke_job = workflow[smoke_job_start:]

    assert "github.event_name == 'workflow_dispatch'" in smoke_job
    assert "github.event_name == 'pull_request'" in smoke_job
    assert "contains(github.event.pull_request.labels.*.name" not in smoke_job
    assert "CLOUDBASE_STAGING_BASE_URL" in smoke_job


def test_cloudbase_staging_e2e_uses_self_hosted_runner_and_global_lock() -> None:
    workflow = _server_ci_workflow()

    smoke_job_start = workflow.index("  cloudbase_staging_e2e:")
    smoke_job = workflow[smoke_job_start:]

    assert "runs-on: [self-hosted, linux, x64, happyword-e2e-db]" in smoke_job
    assert "concurrency:" in smoke_job
    assert "group: cloudbase-staging-e2e" in smoke_job
    assert "cancel-in-progress: false" in smoke_job
    assert "actions/upload-artifact@v7.0.1" in workflow
    assert "uses: actions/" not in smoke_job
    assert "actions/download-artifact" not in smoke_job
    assert "actions/upload-artifact" not in smoke_job
    assert "uses: astral-sh/setup-uv" not in smoke_job
    assert "UV_BIN: /usr/local/bin/uv" in smoke_job
    assert "NODE_VERSION: 24.11.1" in smoke_job
    assert "CLOUDBASE_CLI_VERSION: 3.5.5" in smoke_job
    assert "NPM_CONFIG_PREFIX: /tmp/happyword-npm-global" in smoke_job
    assert "HAS_TCB_E2E_MONGODB_URI" in smoke_job
    assert "secrets.TCB_E2E_MONGODB_URI" in smoke_job
    assert "secrets.E2E_MONGODB_URI" not in smoke_job
    assert "server-source-for-cloudbase-e2e" in workflow
    assert "/tarball/${GITHUB_SHA}" not in smoke_job
    assert "git fetch" not in smoke_job

    download_step = _step_named(workflow, "Download server source")
    bootstrap_node_step = _step_named(workflow, "Bootstrap Node.js")
    verify_step = _step_named(workflow, "Verify runner toolchain")
    reset_step = _step_named(workflow, "Reset shared staging E2E database")
    smoke_step = _step_named(workflow, "Run CloudBase staging E2E")
    assert "GITHUB_TOKEN" in download_step
    assert "archive_download_url" in download_step
    assert "--connect-timeout 20" in download_step
    assert "python3.12 -m zipfile -e" in download_step
    assert workflow.index("Bootstrap Node.js") < workflow.index(
        "Verify runner toolchain"
    )
    assert 'mkdir -p "$NPM_CONFIG_PREFIX/bin"' in bootstrap_node_step
    assert 'externals/node*/bin' in bootstrap_node_step
    assert 'https://nodejs.org/dist/v${NODE_VERSION}/${node_archive}' in bootstrap_node_step
    assert "node --version" in bootstrap_node_step
    assert "npm --version" in bootstrap_node_step
    assert "node --version" in verify_step
    assert "npm --version" in verify_step
    assert "E2E_BASE_URL: ${{ secrets.CLOUDBASE_STAGING_BASE_URL }}" in smoke_step
    assert "E2E_MONGO_DB_NAME: ${{ secrets.E2E_STAGING_DB_NAME }}" in reset_step
    assert "E2E_ADMIN_USER: ${{ secrets.E2E_ADMIN_USER }}" in reset_step
    assert "E2E_ADMIN_PASS: ${{ secrets.E2E_ADMIN_PASS }}" in reset_step
    assert '"$UV_BIN" run --python 3.12 pytest -v -m e2e' in smoke_step


def test_cloudbase_staging_e2e_deploys_pr_artifact_before_reset_and_tests() -> None:
    workflow = _server_ci_workflow()

    login_step = _step_named(workflow, "Login to CloudBase for staging deploy")
    capture_step = _step_named(workflow, "Capture CloudBase staging deploy marker")
    deploy_step = _step_named(workflow, "Deploy CloudBase staging Run")
    wait_step = _step_named(workflow, "Wait for CloudBase staging deployment")
    health_step = _step_named(workflow, "Health check CloudBase staging")
    reset_step = _step_named(workflow, "Reset shared staging E2E database")
    smoke_step = _step_named(workflow, "Run CloudBase staging E2E")

    assert workflow.index("Deploy CloudBase staging Run") < workflow.index(
        "Reset shared staging E2E database"
    )
    assert workflow.index("Health check CloudBase staging") < workflow.index(
        "Run CloudBase staging E2E"
    )

    assert "HAS_TCB_SECRET_ID" in workflow
    assert "HAS_TCB_SECRET_KEY" in workflow
    assert "HAS_TCB_ENV_ID" in workflow
    assert 'TCB_SECRET_ID: ${{ secrets.TCB_SECRET_ID }}' in login_step
    assert 'TCB_SECRET_KEY: ${{ secrets.TCB_SECRET_KEY }}' in login_step
    assert 'TCB_ENV_ID: ${{ secrets.TCB_ENV_ID }}' in capture_step
    assert "happyword-server-staging" in capture_step
    assert "happyword-server-staging" in deploy_step
    assert 'printf \'\\n\' | tcb cloudrun deploy' in deploy_step
    assert "--source . --force" in deploy_step
    assert "CLOUDBASE_PREVIOUS_STAGING_DEPLOY_ID" in wait_step
    assert "previousDeployId" in wait_step
    assert 'latest.Status === "normal"' in wait_step
    assert 'String(latest.FlowRatio) === "100"' in wait_step
    assert "latest.HasTraffic === true" in wait_step
    assert 'curl -fsS "$CLOUDBASE_STAGING_BASE_URL/api/v1/public/health"' in health_step
    assert "E2E_MONGO_DB_NAME: ${{ secrets.E2E_STAGING_DB_NAME }}" in reset_step
    assert "E2E_BASE_URL: ${{ secrets.CLOUDBASE_STAGING_BASE_URL }}" in smoke_step


def test_main_cd_deploys_to_cloudbase_with_vercel_manual_rollback_only() -> None:
    vercel_cd = _workflow("server-cd.yml")
    cloudbase_cd = _workflow("server-cloudbase-cd.yml")

    assert "name: server-cd-legacy-vercel" in vercel_cd
    assert "workflow_dispatch:" in vercel_cd
    assert "push:" not in vercel_cd
    assert "Wait for Vercel production deploy" in vercel_cd
    assert "Run staging smoke" in vercel_cd

    assert "name: server-cloudbase-cd" in cloudbase_cd
    assert "push:" in cloudbase_cd
    assert "CLOUDBASE_CLI_VERSION: 3.5.5" in cloudbase_cd
    assert "npm install -g \"@cloudbase/cli@${CLOUDBASE_CLI_VERSION}\"" in cloudbase_cd
    assert "tcb login --apiKeyId" in cloudbase_cd
    assert "tcb cloudrun deploy" in cloudbase_cd
    assert "CLOUDBASE_PROD_BASE_URL" in cloudbase_cd


def test_cd_smoke_jobs_are_http_only_on_github_hosted_runners() -> None:
    vercel_cd = _workflow("server-cd.yml")
    cloudbase_cd = _workflow("server-cloudbase-cd.yml")

    vercel_smoke_step = _step_named(vercel_cd, "Run staging smoke")
    cloudbase_smoke_step = _step_named(cloudbase_cd, "Smoke test")

    assert "runs-on: ubuntu-latest" in vercel_cd
    assert "runs-on: ubuntu-latest" in cloudbase_cd
    assert "E2E_BASE_URL:" in vercel_smoke_step
    assert "E2E_BASE_URL:" in cloudbase_smoke_step
    assert "E2E_MONGODB_URI" not in vercel_smoke_step
    assert "E2E_MONGODB_URI" not in cloudbase_smoke_step
    assert "E2E_MONGO_DB_NAME" not in vercel_smoke_step
    assert "E2E_MONGO_DB_NAME" not in cloudbase_smoke_step
    assert "uv run pytest -v -m smoke" in vercel_smoke_step
    assert "uv run pytest -v -m smoke" in cloudbase_smoke_step


def test_cloudbase_cd_waits_for_a_real_new_deploy_before_health_and_smoke() -> None:
    cloudbase_cd = _workflow("server-cloudbase-cd.yml")

    capture_step = _step_named(cloudbase_cd, "Capture CloudBase deploy marker")
    deploy_step = _step_named(cloudbase_cd, "Deploy CloudBase Run")
    wait_step = _step_named(cloudbase_cd, "Wait for CloudBase deployment")
    health_step = _step_named(cloudbase_cd, "Health check")

    assert cloudbase_cd.index("Capture CloudBase deploy marker") < cloudbase_cd.index(
        "Deploy CloudBase Run"
    )
    assert cloudbase_cd.index("Wait for CloudBase deployment") < cloudbase_cd.index(
        "Health check"
    )

    assert "CLOUDBASE_PREVIOUS_DEPLOY_ID" in capture_step
    assert "DescribeCloudRunDeployRecord" in capture_step
    assert "printf '\\n' | tcb cloudrun deploy" in deploy_step
    assert "previousDeployId" in wait_step
    assert "latest.DeployId === previousDeployId && latest.Status === \"deploy_failed\"" in wait_step
    assert "Number(latest.BuildId) === 0" in wait_step
    assert "CloudBase deploy process log" in wait_step
    assert "Number(latest.BuildId) > 0" in wait_step
    assert 'latest.Status === "normal"' in wait_step
    assert 'String(latest.FlowRatio) === "100"' in wait_step
    assert "latest.HasTraffic === true" in wait_step
    assert "curl -fsS" in health_step


def test_cloudbase_cd_prunes_local_test_artifacts_before_source_deploy() -> None:
    cloudbase_cd = _workflow("server-cloudbase-cd.yml")

    deploy_step = _step_named(cloudbase_cd, "Deploy CloudBase Run")

    assert "timeout-minutes: 20" in deploy_step
    assert "rm -rf .venv .pytest_cache .ruff_cache .mypy_cache" in deploy_step
    assert deploy_step.index("rm -rf .venv") < deploy_step.index(
        "tcb cloudrun deploy"
    )


def test_cloudbase_cd_retries_transient_submit_failures() -> None:
    cloudbase_cd = _workflow("server-cloudbase-cd.yml")

    deploy_step = _step_named(cloudbase_cd, "Deploy CloudBase Run")

    assert "for attempt in 1 2 3" in deploy_step
    assert "CloudBase Run submit attempt ${attempt}/3 failed" in deploy_step
    assert "deploy_output=\"$(mktemp)\"" in deploy_step
    assert "deploy_status=${PIPESTATUS[1]}" in deploy_step
    assert "HTTP ERROR|Error:" in deploy_step
    assert "submission completed" in deploy_step
    assert "DescribeCloudRunDeployRecord" in deploy_step
    assert "CLOUDBASE_PREVIOUS_DEPLOY_ID" in deploy_step
    assert "latest.DeployId !== previousDeployId" in deploy_step
    assert "Number(latest.BuildId) > 0" in deploy_step
    assert 'latest.Status === "deploy_failed"' in deploy_step
    assert "CloudBase created a new deploy record despite the CLI failure" in deploy_step
