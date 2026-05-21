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


def test_transition_keeps_legacy_vercel_preview_deploy() -> None:
    """During migration, PR CI still deploys Vercel Preview as a fallback path."""
    workflow = _server_ci_workflow()

    assert "  server_e2e:" in workflow
    assert "Deploy Vercel preview (E2E-controlled)" in workflow
    assert "npx --yes" in workflow
    assert "deploy --yes" in workflow
    assert "VERCEL_TOKEN" in workflow
    assert "  update_manifest:" in workflow
    assert "node server/scripts/update_preview_manifest.mjs" in workflow
    assert "  cursor_autofix_e2e:" in workflow


def test_cloudbase_staging_smoke_is_gated_by_manual_or_label() -> None:
    workflow = _server_ci_workflow()

    assert "workflow_dispatch:" in workflow
    assert "cloudbase-smoke" in workflow
    assert "github.event.action == 'labeled'" in workflow

    smoke_job_start = workflow.index("  cloudbase_staging_smoke:")
    smoke_job_end = workflow.find("\n  cursor_autofix", smoke_job_start)
    smoke_job = workflow[smoke_job_start : smoke_job_end if smoke_job_end != -1 else len(workflow)]

    assert "github.event_name == 'workflow_dispatch'" in smoke_job
    assert "contains(github.event.pull_request.labels.*.name, 'cloudbase-smoke')" in smoke_job
    assert "CLOUDBASE_STAGING_BASE_URL" in smoke_job


def test_cloudbase_staging_smoke_uses_shared_staging_url() -> None:
    workflow = _server_ci_workflow()

    smoke_step = _step_named(workflow, "Run CloudBase staging smoke")
    assert "E2E_BASE_URL: ${{ secrets.CLOUDBASE_STAGING_BASE_URL }}" in smoke_step
    assert "uv run pytest -v -m smoke" in smoke_step


def test_main_cd_deploys_to_both_vercel_and_cloudbase_during_transition() -> None:
    vercel_cd = _workflow("server-cd.yml")
    cloudbase_cd = _workflow("server-cloudbase-cd.yml")

    assert "Wait for Vercel production deploy" in vercel_cd
    assert "Run staging smoke" in vercel_cd

    assert "name: server-cloudbase-cd" in cloudbase_cd
    assert "tcb login --apiKeyId" in cloudbase_cd
    assert "tcb cloudrun deploy" in cloudbase_cd
    assert "CLOUDBASE_PROD_BASE_URL" in cloudbase_cd
