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


def test_e2e_uses_cli_preview_deployment_with_pr_metadata() -> None:
    """The E2E suite must target a preview deployed with PR DB metadata."""
    workflow = _server_ci_workflow()

    deploy_step = _step_with_id(workflow, "vercel_deploy")
    assert "if: ${{ env.HAS_VERCEL_TOKEN == 'true' }}" in deploy_step
    assert "working-directory: server" in deploy_step
    assert "steps.detect_preview.outputs.preview_url == ''" not in deploy_step

    e2e_step = _step_named(workflow, "Run E2E pytest subset")
    assert (
        "E2E_BASE_URL: ${{ steps.vercel_deploy.outputs.preview-url || "
        "steps.detect_preview.outputs.preview_url }}"
        in e2e_step
    )
