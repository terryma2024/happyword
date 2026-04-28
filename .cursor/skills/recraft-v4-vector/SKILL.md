---
name: recraft-v4-vector
description: Use when generating editable SVG/vector game art, icons, characters, props, UI assets, or marketing illustrations with Recraft V4 Vector from Cursor.
---

# recraft-v4-vector

Use the shared project tool:

```bash
node tools/recraft/generate-v4-vector.mjs --prompt "original cute magical slime monster, clean SVG vector game asset, simple readable silhouette, no text" --out generated/recraft/slime.svg --json generated/recraft/slime.json
```

## API Key

The tool reads the key from `--api-key`, then `RECRAFT_API_KEY`, then the local Codex MCP config at `~/.codex/config.toml`.

Do not write API keys into tracked files.

## Prompt Rules

- Keep prompts under 1024 characters.
- Generate original assets only; avoid copyrighted character likenesses.
- For game assets, include subject, role, silhouette, palette, mood, background, and `no text`.
- Use `--prompt-file` when the prompt is long or should be reused.

## Checks

```bash
file generated/recraft/asset.svg
wc -c generated/recraft/asset.svg
```
