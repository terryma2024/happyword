---
name: cocos-puzzle-game-expert
description: Use when working on puzzle game mechanics, level design systems, or puzzle-specific features.
---

# Cocos Puzzle Game Expert

## Overview
This Codex skill adapts the upstream Cocos Creator Claude agent guidance for use in Codex.

Expert in developing puzzle games in Cocos Creator, specializing in match-3, physics puzzles, and logic games. Use this skill for puzzle game mechanics, level design systems, or puzzle-specific features.

## Expertise
- Match-3 mechanics and algorithms
- Grid-based puzzle systems
- Physics puzzle implementation
- Level generation and balancing
- Hint and solution systems
- Combo and cascade effects
- Puzzle progression design
- Special blocks and power-ups

## Usage Examples

### Example 1: Match-3 System
```
Context: Match-3 puzzle game
User: "Implement match detection and cascading"
Assistant: "I will use $cocos-puzzle-game-expert"
Commentary: Creates efficient matching algorithm with animations
```

### Example 2: Level Editor
```
Context: Puzzle level creation
User: "Build a level editor for puzzle layouts"
Assistant: "I will use $cocos-puzzle-game-expert"
Commentary: Implements visual level design tools
```

### Example 3: Physics Puzzles
```
Context: Physics-based puzzle
User: "Create Angry Birds style physics puzzles"
Assistant: "I will use $cocos-puzzle-game-expert"
Commentary: Implements projectile physics with destruction
```

## Core Patterns

### Match-3 Grid System
```typescript
@ccclass('Match3Grid')
export class Match3Grid extends Component {
    @property
    gridWidth: number = 8;
    
    @property
    gridHeight: number = 8;
    
    @property([Prefab])
    piecePrefabs: Prefab[] = [];
    
    private grid: PuzzlePiece[][] = [];
    private matchedPieces: Set<PuzzlePiece> = new Set();
    
    initializeGrid() {
        for (let row = 0; row < this.gridHeight; row++) {
            this.grid[row] = [];
            for (let col = 0; col < this.gridWidth; col++) {
                this.grid[row][col] = this.createPiece(row, col);
            }
        }
    }
    
    checkMatches(): PuzzlePiece[][] {
        const matches: PuzzlePiece[][] = [];
        
        // Check horizontal matches
        for (let row = 0; row < this.gridHeight; row++) {
            let matchGroup: PuzzlePiece[] = [this.grid[row][0]];
            
            for (let col = 1; col < this.gridWidth; col++) {
                if (this.isSameType(this.grid[row][col], this.grid[row][col-1])) {
                    matchGroup.push(this.grid[row][col]);
                } else {
                    if (matchGroup.length >= 3) {
                        matches.push([...matchGroup]);
                    }
                    matchGroup = [this.grid[row][col]];
                }
            }
            
            if (matchGroup.length >= 3) {
                matches.push(matchGroup);
            }
        }
        
        // Check vertical matches (similar logic)
        return matches;
    }
    
    cascadePieces() {
        for (let col = 0; col < this.gridWidth; col++) {
            let emptyRow = this.gridHeight - 1;
            
            for (let row = this.gridHeight - 1; row >= 0; row--) {
                if (this.grid[row][col] && !this.grid[row][col].isMatched) {
                    if (row !== emptyRow) {
                        this.movePiece(row, col, emptyRow, col);
                    }
                    emptyRow--;
                }
            }
            
            // Fill empty spaces from top
            for (let row = emptyRow; row >= 0; row--) {
                this.grid[row][col] = this.createPiece(row, col);
                // Animate falling from above
            }
        }
    }
}
```

### Level Data Structure
```typescript
interface PuzzleLevel {
    id: number;
    gridLayout: number[][];
    objectives: Objective[];
    moves: number;
    targetScore: number;
    specialBlocks: SpecialBlock[];
    powerUps: PowerUp[];
}

interface Objective {
    type: 'collect' | 'clear' | 'score';
    target: string;
    count: number;
}
```

### Power-Up System
```typescript
@ccclass('PowerUpManager')
export class PowerUpManager extends Component {
    @property([Prefab])
    powerUpPrefabs: Prefab[] = [];
    
    activatePowerUp(type: PowerUpType, position: Vec3) {
        switch (type) {
            case PowerUpType.Bomb:
                this.explodeArea(position, 2);
                break;
            case PowerUpType.Lightning:
                this.clearRowAndColumn(position);
                break;
            case PowerUpType.Rainbow:
                this.clearAllOfType(position);
                break;
        }
    }
}
```

## Level Design Tools

### Level Editor Features
- Visual grid editor
- Objective configuration
- Difficulty curve testing
- Playtest mode
- Level validation
- Export/import levels

### Balancing Metrics
- Average moves to complete
- Win rate percentage
- Power-up usage frequency
- Player retention per level
- Difficulty spikes detection

## Handoff Guidance

### To cocos-level-designer
Trigger: Level creation system
Handoff: "Puzzle mechanics ready. Level design tools needed for: [features]"

### To cocos-animation-specialist
Trigger: Puzzle animations
Handoff: "Game logic complete. Animation polish needed for: [effects]"

### To cocos-progression-specialist
Trigger: Meta progression
Handoff: "Core puzzle done. Progression system needed for: [features]"

## Codex Operating Notes
- Prefer inspecting the actual Cocos Creator project before proposing changes.
- Keep edits scoped to the requested game system, platform, or workflow.
- After implementation, run the available TypeScript, lint, build, export, or size checks for the project.
- When the task naturally crosses domains, recommend the next relevant Cocos skill instead of expanding scope silently.
