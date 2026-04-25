---
name: cocos-scene-analyzer
description: Use when exploring scene structure, debugging node issues, or understanding component interactions in Cocos Creator projects.
---

# Cocos Scene Analyzer

## Overview
This Codex skill adapts the upstream Cocos Creator Claude agent guidance for use in Codex.

Expert in analyzing Cocos Creator scenes, node hierarchies, and component relationships. Use this skill when exploring scene structure, debugging node issues, or understanding component interactions in Cocos Creator projects.

## Expertise
- Scene hierarchy analysis and optimization
- Node tree traversal and manipulation
- Component dependency mapping
- Prefab structure analysis
- Scene loading and transition patterns
- Memory usage analysis for scenes
- Node pool optimization strategies

## Usage Examples

### Example 1: Scene Structure Analysis
```
Context: Cocos Creator project with complex scene
User: "Analyze the main game scene structure"
Assistant: "I will use $cocos-scene-analyzer"
Commentary: Analyzes nodes, components, and relationships
```

### Example 2: Performance Issues
```
Context: Scene with performance problems
User: "Find performance bottlenecks in the gameplay scene"
Assistant: "I will use $cocos-scene-analyzer"
Commentary: Checks node counts, component usage, draw calls
```

### Example 3: Prefab Dependencies
```
Context: Complex prefab structures
User: "Map out all prefab dependencies in the UI system"
Assistant: "I will use $cocos-scene-analyzer"
Commentary: Analyzes prefab references and nested structures
```

## Handoff Guidance

### To cocos-component-architect
Trigger: Component design needed
Handoff: "Scene analysis complete. Need component architecture for: [nodes]"

### To cocos-performance-optimizer
Trigger: Performance issues found
Handoff: "Scene bottlenecks identified. Optimization needed for: [areas]"

### To cocos-ui-builder
Trigger: UI structure analysis
Handoff: "UI hierarchy mapped. UI improvements needed for: [screens]"

## Codex Operating Notes
- Prefer inspecting the actual Cocos Creator project before proposing changes.
- Keep edits scoped to the requested game system, platform, or workflow.
- After implementation, run the available TypeScript, lint, build, export, or size checks for the project.
- When the task naturally crosses domains, recommend the next relevant Cocos skill instead of expanding scope silently.
