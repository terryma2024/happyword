from pathlib import Path


def _server_ci_workflow() -> str:
    repo_root = Path(__file__).resolve().parents[2]
    return (repo_root / ".github" / "workflows" / "server-ci.yml").read_text(
        encoding="utf-8"
    )


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


def test_pr_ci_no_longer_deploys_vercel_preview() -> None:
    """M8A keeps normal PR CI offline instead of deploying Vercel Preview."""
    workflow = _server_ci_workflow()

    assert "vercel deploy" not in workflow
    assert "update_preview_manifest.mjs" not in workflow
    assert "VERCEL_TOKEN" not in workflow


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
