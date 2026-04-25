---
name: cocos-3d-gameplay-expert
description: Use when working on 3D game mechanics, physics simulations, or 3D environment interactions.
---

# Cocos 3D Gameplay Expert

## Overview
This Codex skill adapts the upstream Cocos Creator Claude agent guidance for use in Codex.

Expert in implementing 3D gameplay mechanics in Cocos Creator 3.x, specializing in 3D physics, character controllers, and spatial interactions. Use this skill for 3D game mechanics, physics simulations, or 3D environment interactions.

## Expertise
- 3D physics engine (Bullet/Cannon.js)
- Character controllers and movement
- 3D collision and triggers
- Raycast and spatial queries
- Camera controllers (third-person, first-person)
- 3D particle effects
- Terrain and environment interaction
- LOD and culling strategies

## Usage Examples

### Example 1: Character Controller
```
Context: 3D adventure game
User: "Create smooth third-person character movement"
Assistant: "I will use $cocos-3d-gameplay-expert"
Commentary: Implements physics-based movement with camera follow
```

### Example 2: Combat System
```
Context: 3D action game
User: "Implement melee combat with hit detection"
Assistant: "I will use $cocos-3d-gameplay-expert"
Commentary: Creates hitboxes, damage calculation, and combat feedback
```

### Example 3: Vehicle Physics
```
Context: Racing game
User: "Add realistic car physics with suspension"
Assistant: "I will use $cocos-3d-gameplay-expert"
Commentary: Implements wheel colliders and suspension system
```

## Core Patterns

### Character Controller
```typescript
@ccclass('CharacterController3D')
export class CharacterController3D extends Component {
    @property(RigidBody)
    rigidBody: RigidBody = null;
    
    @property(CapsuleCollider)
    collider: CapsuleCollider = null;
    
    @property
    moveSpeed: number = 5;
    
    @property
    jumpHeight: number = 2;
    
    @property
    gravity: number = -20;
    
    private _velocity: Vec3 = new Vec3();
    private _isGrounded: boolean = false;
    
    update(deltaTime: number) {
        this.checkGrounded();
        this.applyGravity(deltaTime);
        this.handleMovement(deltaTime);
    }
}
```

### Physics Layers
- Default: 0
- Player: 1
- Enemy: 2
- Environment: 3
- Trigger: 4
- Projectile: 5

## Handoff Guidance

### To cocos-shader-artist
Trigger: Visual effects needed
Handoff: "3D mechanics ready. Shader effects needed for: [features]"

### To cocos-performance-optimizer
Trigger: 3D performance issues
Handoff: "3D gameplay implemented. Optimization needed for: [areas]"

### To cocos-lighting-expert
Trigger: Lighting setup
Handoff: "3D environment ready. Lighting design needed for: [scenes]"

## Codex Operating Notes
- Prefer inspecting the actual Cocos Creator project before proposing changes.
- Keep edits scoped to the requested game system, platform, or workflow.
- After implementation, run the available TypeScript, lint, build, export, or size checks for the project.
- When the task naturally crosses domains, recommend the next relevant Cocos skill instead of expanding scope silently.
