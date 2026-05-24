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


def test_server_ci_uses_single_cloudbase_staging_e2e_environment() -> None:
    """PR E2E uses the shared CloudBase staging environment, not per-PR deploys."""
    workflow = _server_ci_workflow()

    assert "  server_e2e:" not in workflow
    assert "Deploy Vercel preview (E2E-controlled)" not in workflow
    assert "happyword_pr_{pr}_e2e" not in workflow
    assert "  cloudbase_staging_e2e:" in workflow
    assert "E2E_BASE_URL: ${{ secrets.CLOUDBASE_STAGING_BASE_URL }}" in workflow
    assert "uv run --python 3.12 python scripts/e2e_reset_db.py" in workflow
    assert "uv run --python 3.12 pytest -v -m e2e" in workflow


def test_cursor_autofix_action_is_removed() -> None:
    """The Cursor autofix workflow was retired from server CI."""
    workflow = _server_ci_workflow()

    assert "cursor_autofix_e2e" not in workflow
    assert "CURSOR_API_KEY" not in workflow
    assert "trigger-cursor-fix-e2e.mjs" not in workflow


def test_server_ci_no_longer_deploys_legacy_vercel_preview_for_e2e() -> None:
    workflow = _server_ci_workflow()

    assert "VERCEL_TOKEN" not in workflow
    assert "VERCEL_CLI_VERSION" not in workflow
    assert "vercel_deploy" not in workflow
    assert "update_manifest" not in workflow


def test_cloudbase_staging_e2e_is_gated_by_manual_or_label() -> None:
    workflow = _server_ci_workflow()

    assert "workflow_dispatch:" in workflow
    assert "cloudbase-smoke" in workflow
    assert "github.event.action == 'labeled'" in workflow

    smoke_job_start = workflow.index("  cloudbase_staging_e2e:")
    smoke_job = workflow[smoke_job_start:]

    assert "github.event_name == 'workflow_dispatch'" in smoke_job
    assert "contains(github.event.pull_request.labels.*.name, 'cloudbase-smoke')" in smoke_job
    assert "CLOUDBASE_STAGING_BASE_URL" in smoke_job


def test_cloudbase_staging_e2e_uses_self_hosted_runner_and_global_lock() -> None:
    workflow = _server_ci_workflow()

    smoke_job_start = workflow.index("  cloudbase_staging_e2e:")
    smoke_job = workflow[smoke_job_start:]

    assert "runs-on: [self-hosted, linux, x64, happyword-e2e-db]" in smoke_job
    assert "concurrency:" in smoke_job
    assert "group: cloudbase-staging-e2e" in smoke_job
    assert "cancel-in-progress: false" in smoke_job

    reset_step = _step_named(workflow, "Reset shared staging E2E database")
    smoke_step = _step_named(workflow, "Run CloudBase staging E2E")
    assert "E2E_BASE_URL: ${{ secrets.CLOUDBASE_STAGING_BASE_URL }}" in smoke_step
    assert "E2E_MONGO_DB_NAME: ${{ secrets.E2E_STAGING_DB_NAME }}" in reset_step
    assert "uv run --python 3.12 pytest -v -m e2e" in smoke_step


def test_legacy_vercel_e2e_skips_unusable_local_mongo_uri() -> None:
    workflow = _server_ci_workflow()

    validate_step = _step_with_id(workflow, "e2e_mongo")
    assert "Validate E2E MongoDB URI" in validate_step
    assert "set_ready(False)" in validate_step
    assert "127.0.0.1" in validate_step
    assert "localhost" in validate_step
    assert "::1" in validate_step

    for step_name in [
        "Prune stale E2E PR databases",
        "Reset E2E database (truncate test collections)",
        "Run E2E pytest subset",
    ]:
        step = _step_named(workflow, step_name)
        assert "steps.e2e_mongo.outputs.ready == 'true'" in step


def test_main_cd_deploys_to_both_vercel_and_cloudbase_during_transition() -> None:
    vercel_cd = _workflow("server-cd.yml")
    cloudbase_cd = _workflow("server-cloudbase-cd.yml")

    assert "Wait for Vercel production deploy" in vercel_cd
    assert "Run staging smoke" in vercel_cd

    assert "name: server-cloudbase-cd" in cloudbase_cd
    assert "tcb login --apiKeyId" in cloudbase_cd
    assert "tcb cloudrun deploy" in cloudbase_cd
    assert "CLOUDBASE_PROD_BASE_URL" in cloudbase_cd


def test_cloudbase_cd_waits_for_a_real_new_deploy_before_smoke() -> None:
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
    assert "Number(latest.BuildId) > 0" in wait_step
    assert 'latest.Status === "normal"' in wait_step
    assert 'String(latest.FlowRatio) === "100"' in wait_step
    assert "latest.HasTraffic === true" in wait_step
    assert "curl -fsS" in health_step
