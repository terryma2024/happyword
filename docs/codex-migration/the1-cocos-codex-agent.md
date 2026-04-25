# The1 Cocos Claude Agents to Codex Migration

Source: https://github.com/The1Studio/the1-cocos-claude-agent

## Output
- Repo-local skills: `.agents/skills/cocos-*/SKILL.md`
- Distributable plugin: `plugins/the1-cocos-codex-agent`
- Custom subagents: `.codex/agents/*.toml`
- Cocos project instruction template: `plugins/the1-cocos-codex-agent/templates/AGENTS.md`

## Design
The upstream Claude agents are expert prompt documents. In Codex, they map best to Skills rather than one subagent per expert. Skills are lightweight, discoverable by name and description, and can be invoked with `$skill-name`. A small set of custom subagents handles read-only exploration, implementation, review, documentation research, and playable auditing.

## Skills
- `cocos-2d-gameplay-expert`: Cocos 2D Gameplay Expert
- `cocos-3d-gameplay-expert`: Cocos 3D Gameplay Expert
- `cocos-ai-specialist`: Cocos AI Specialist
- `cocos-analytics-specialist`: Cocos Analytics Specialist
- `cocos-animation-specialist`: Cocos Animation Specialist
- `cocos-asset-manager`: Cocos Asset Manager
- `cocos-backend-integrator`: Cocos Backend Integrator
- `cocos-build-engineer`: Cocos Build Engineer
- `cocos-casual-game-expert`: Cocos Casual Game Expert
- `cocos-component-architect`: Cocos Component Architect
- `cocos-conversion-optimizer`: Cocos Conversion Optimizer
- `cocos-level-designer`: Cocos Level Designer
- `cocos-mobile-optimizer`: Cocos Mobile Optimizer
- `cocos-multiplayer-architect`: Cocos Multiplayer Architect
- `cocos-performance-optimizer`: Cocos Performance Optimizer
- `cocos-platform-integrator`: Cocos Platform Integrator
- `cocos-playable-architect`: Cocos Playable Architect
- `cocos-playable-optimizer`: Cocos Playable Optimizer
- `cocos-progression-specialist`: Cocos Progression Specialist
- `cocos-project-architect`: Cocos Project Architect
- `cocos-puzzle-game-expert`: Cocos Puzzle Game Expert
- `cocos-rapid-prototyper`: Cocos Rapid Prototyper
- `cocos-scene-analyzer`: Cocos Scene Analyzer
- `cocos-security-expert`: Cocos Security Expert
- `cocos-team-coordinator`: Cocos Team Coordinator
- `cocos-tutorial-designer`: Cocos Tutorial Designer
- `cocos-typescript-expert`: Cocos TypeScript Expert
- `cocos-ui-builder`: Cocos UI Builder
- `cocos-ux-designer`: Cocos UX Designer

## Recommended Usage
```text
Use $cocos-team-coordinator to inspect this Cocos Creator project and recommend the skill stack.
Use $cocos-playable-architect to plan a match-3 playable ad.
Use $cocos-performance-optimizer to analyze frame drops and recommend measurable fixes.
Spawn cocos_explorer to inspect the project, then use $cocos-project-architect for the plan.
```

## Validation
Run:
```bash
node scripts/validate-codex-agent-port.mjs
```
