#!/usr/bin/env python3
"""Merge ~/.env into server/.env.local using .env.local.example as skeleton.

Does not print secret values. Intended for local dev setup only."""

from __future__ import annotations

from pathlib import Path


def parse_env_file(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        key, _, rest = line.partition("=")
        key = key.strip()
        if not key:
            continue
        out[key] = rest.rstrip("\r")
    return out


def _lookup_value(
    home_vars: dict[str, str],
    key: str,
    used_sources: set[str],
) -> str | None:
    if key in home_vars:
        used_sources.add(key)
        return home_vars[key]
    # Match pydantic `AliasChoices` and common local aliases.
    aliases: dict[str, tuple[str, ...]] = {
        "MONGODB_URI": ("MONGO_URI", "DATABASE_URL"),
        "MONGO_DB_NAME": ("MONGODB_DB_NAME",),
    }
    for alt in aliases.get(key, ()):
        if alt in home_vars:
            used_sources.add(alt)
            return home_vars[alt]
    return None


def main() -> None:
    server_root = Path(__file__).resolve().parents[1]
    home_env = Path.home() / ".env"
    example = server_root / ".env.local.example"
    out_path = server_root / ".env.local"

    home_vars = parse_env_file(home_env)
    if not home_vars:
        raise SystemExit(f"No KEY=value entries found in {home_env}")

    example_text = example.read_text(encoding="utf-8")
    out_lines: list[str] = [
        "# Initialized from ~/.env (merged with .env.local.example). Do not commit.",
        "",
    ]

    emitted: set[str] = set()
    used_sources: set[str] = set()
    for raw in example_text.splitlines():
        stripped = raw.strip()
        if stripped.startswith("#") or not stripped:
            out_lines.append(raw)
            continue
        if "=" not in stripped:
            out_lines.append(raw)
            continue
        key, _, _rest = stripped.partition("=")
        key = key.strip()
        val = _lookup_value(home_vars, key, used_sources)
        if val is not None:
            out_lines.append(f"{key}={val}")
            emitted.add(key)
        else:
            out_lines.append(raw)

    extra_keys = sorted(k for k in home_vars if k not in used_sources)
    if extra_keys:
        out_lines.append("")
        out_lines.append("# Extra keys from ~/.env (not in .env.local.example)")
        for k in extra_keys:
            out_lines.append(f"{k}={home_vars[k]}")

    out_path.write_text("\n".join(out_lines) + "\n", encoding="utf-8")
    print(f"Wrote {out_path}")
    print(f"Overlaid {len(emitted)} keys from ~/.env; appended {len(extra_keys)} extra keys.")


if __name__ == "__main__":
    main()
