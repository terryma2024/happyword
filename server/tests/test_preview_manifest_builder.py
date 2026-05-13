import json
import subprocess
from pathlib import Path


def _run_node_expression(expr: str) -> dict[str, object]:
    repo = Path(__file__).resolve().parents[2]
    script = f"""
      import {{
        makeManifestRow,
        requireBranchUrl,
      }} from {json.dumps(str(repo / "server/scripts/update_preview_manifest.mjs"))};
      const out = {expr};
      console.log(JSON.stringify(out));
    """
    result = subprocess.run(
        ["node", "--input-type=module", "-e", script],
        check=True,
        capture_output=True,
        text=True,
        cwd=repo,
    )
    return json.loads(result.stdout)


def test_manifest_row_prefers_stable_branch_url_and_keeps_deployment_url() -> None:
    row = _run_node_expression(
        """
        makeManifestRow({
          branch: "codex/preview-debug",
          deploy: {
            uid: "dpl_123",
            url: "happyword-abc123-terrymas-projects.vercel.app",
            alias: [
              "happyword-git-codex-preview-debug-terrymas-projects.vercel.app"
            ],
            meta: { githubCommitSha: "1234567890abcdef" }
          },
          pr: {
            number: 77,
            title: "Debug preview routing",
            user: { login: "tester" },
            head: { sha: "fedcba9876543210" }
          }
        })
        """,
    )

    assert row["url"] == "https://happyword-git-codex-preview-debug-terrymas-projects.vercel.app"
    assert row["branch_url"] == row["url"]
    assert row["deployment_url"] == "https://happyword-abc123-terrymas-projects.vercel.app"
    assert row["deployment_id"] == "dpl_123"
    assert row["head_sha"] == "1234567"


def test_manifest_builder_fails_when_branch_url_is_missing() -> None:
    row = _run_node_expression(
        """
        (() => {
          try {
            requireBranchUrl({
              branch: "codex/preview-debug",
              deploy: {
                url: "happyword-abc123-terrymas-projects.vercel.app",
                alias: []
              }
            });
          } catch (err) {
            return { message: err.message };
          }
          return { message: "" };
        })()
        """,
    )

    assert "branch URL" in row["message"]
    assert "Git metadata" in row["message"]
