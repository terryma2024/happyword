---
name: recraft-v4-vector
description: Use when generating editable SVG/vector game art, icons, characters, props, UI assets, or marketing illustrations with Recraft V4 Vector from Codex.
---

# Recraft V4 Vector

Use the project tool instead of hand-writing API calls:

```bash
node tools/recraft/generate-v4-vector.mjs --prompt "original cute magical slime monster, clean SVG vector game asset, simple readable silhouette, no text" --out generated/recraft/slime.svg --json generated/recraft/slime.json
```

## Key Handling

The tool reads the Recraft API key in this order:

1. `--api-key`
2. `RECRAFT_API_KEY`
3. `~/.codex/config.toml` under `[mcp_servers.recraft.env]`

Do not commit API keys or paste them into tracked skill files.

## Prompt Rules

- Keep prompts under 1024 characters.
- Ask for `original` assets and avoid copyrighted character likenesses.
- For game assets, specify: subject, gameplay role, silhouette, palette, mood, background, and `no text`.
- Use `--prompt-file` for long prompts that should be reviewed or reused.

## Outputs

- Default model: `recraftv4_vector`
- Default size: `1:1`
- Default output directory: `generated/recraft/`
- Use `--json` to preserve the Recraft response URL and metadata.

Validate output with:

```bash
file generated/recraft/asset.svg
wc -c generated/recraft/asset.svg
```
