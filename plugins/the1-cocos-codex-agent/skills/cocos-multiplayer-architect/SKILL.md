---
name: cocos-multiplayer-architect
description: Use when working on any multiplayer functionality, networking architecture, or online features.
---

# Cocos Multiplayer Architect

## Overview
This Codex skill adapts the upstream Cocos Creator Claude agent guidance for use in Codex.

Expert in implementing multiplayer systems for Cocos Creator games, including real-time networking, matchmaking, and synchronization. Use this skill for any multiplayer functionality, networking architecture, or online features.

## Expertise
- WebSocket and Socket.io integration
- Client-server architecture
- State synchronization strategies
- Lag compensation techniques
- Matchmaking systems
- Room/lobby management
- Client prediction and reconciliation
- Network optimization

## Usage Examples

### Example 1: Real-time Multiplayer
```
Context: Real-time PvP game
User: "Implement synchronized player movement"
Assistant: "I will use $cocos-multiplayer-architect"
Commentary: Creates authoritative server with client prediction
```

### Example 2: Turn-based System
```
Context: Card game multiplayer
User: "Create turn-based game logic with rooms"
Assistant: "I will use $cocos-multiplayer-architect"
Commentary: Implements room management and turn synchronization
```

### Example 3: Leaderboards
```
Context: Global leaderboard system
User: "Add real-time leaderboards with friend filtering"
Assistant: "I will use $cocos-multiplayer-architect"
Commentary: Designs efficient leaderboard with caching
```

## Architecture Patterns

### Network Manager
```typescript
@ccclass('NetworkManager')
export class NetworkManager extends Component {
    private socket: any = null;
    private localPlayer: Player = null;
    private remotePlayers: Map<string, Player> = new Map();
    
    @property
    serverUrl: string = 'ws://localhost:3000';
    
    onLoad() {
        this.connectToServer();
        this.setupEventHandlers();
    }
    
    connectToServer() {
        // Socket.io or native WebSocket
        this.socket = io(this.serverUrl);
    }
    
    setupEventHandlers() {
        this.socket.on('connect', this.onConnected.bind(this));
        this.socket.on('player-update', this.onPlayerUpdate.bind(this));
        this.socket.on('player-disconnected', this.onPlayerDisconnected.bind(this));
    }
    
    sendPlayerUpdate(position: Vec3, rotation: Quat) {
        this.socket.emit('player-move', {
            position: { x: position.x, y: position.y, z: position.z },
            rotation: { x: rotation.x, y: rotation.y, z: rotation.z, w: rotation.w },
            timestamp: Date.now()
        });
    }
}
```

### Common Protocols
- Movement sync: 10-30 Hz
- State updates: 5-10 Hz
- Critical events: Immediate
- Heartbeat: 1 Hz

## Server Integration
- Node.js + Socket.io
- Colyseus framework
- Photon Engine
- Unity Netcode (with adapter)
- Custom WebSocket server

## Handoff Guidance

### To cocos-backend-integrator
Trigger: Server implementation needed
Handoff: "Client networking ready. Server implementation needed for: [features]"

### To cocos-security-expert
Trigger: Anti-cheat required
Handoff: "Multiplayer system ready. Security measures needed for: [vulnerabilities]"

### To cocos-performance-optimizer
Trigger: Network optimization
Handoff: "Networking implemented. Performance tuning needed for: [bandwidth]"

## References
Read `references/multiplayer-game-development.md` when the task needs the full workflow.

## Codex Operating Notes
- Prefer inspecting the actual Cocos Creator project before proposing changes.
- Keep edits scoped to the requested game system, platform, or workflow.
- After implementation, run the available TypeScript, lint, build, export, or size checks for the project.
- When the task naturally crosses domains, recommend the next relevant Cocos skill instead of expanding scope silently.
