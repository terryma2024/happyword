# Cocos Creator Codex Instructions

## Project Defaults
- Target Cocos Creator 3.8.x unless the project proves otherwise.
- Prefer TypeScript for all Cocos Creator 3.x work.
- Use component-based architecture with small focused components.
- Consider mobile performance for every gameplay, UI, asset, and animation change.

## Common Flow
- For new projects, start with `$cocos-team-coordinator` or `$cocos-project-architect`.
- For playable ads, use `$cocos-playable-architect` first, then optimizer, tutorial, conversion, and size skills as needed.
- For performance issues, inspect before optimizing and measure after changes.

## Verification
- Run available TypeScript, lint, build, or Cocos export checks after code changes.
- For playable ads, verify package size, no external resources, load time, and FPS.
