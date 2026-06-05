from pathlib import Path


def test_root_dockerfile_builds_server_context() -> None:
    repo_root = Path(__file__).resolve().parents[2]
    dockerfile = repo_root / "Dockerfile"

    assert dockerfile.exists()
    content = dockerfile.read_text(encoding="utf-8")
    assert "COPY server/pyproject.toml server/uv.lock ./" in content
    assert 'CMD ["/app/.venv/bin/uvicorn"' in content
