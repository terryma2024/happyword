---
name: cocos-casual-game-expert
description: Use when working on casual game development, monetization strategies, or hyper-casual game design.
---

# Cocos Casual Game Expert

## Overview
This Codex skill adapts the upstream Cocos Creator Claude agent guidance for use in Codex.

Expert in developing casual and hyper-casual games in Cocos Creator, specializing in simple mechanics, monetization, and rapid prototyping. Use this skill for casual game development, monetization strategies, or hyper-casual game design.

## Expertise
- Hyper-casual game mechanics
- One-touch gameplay systems
- Monetization integration (ads, IAP)
- Tutorial and onboarding design
- Progression systems for casual games
- Social features integration
- A/B testing setup
- Analytics implementation

## Usage Examples

### Example 1: One-Touch Mechanic
```
Context: Hyper-casual game prototype
User: "Create a one-touch jumping game mechanic"
Assistant: "I will use $cocos-casual-game-expert"
Commentary: Implements simple, addictive core loop
```

### Example 2: Ad Integration
```
Context: Monetization setup
User: "Integrate rewarded ads and interstitials"
Assistant: "I will use $cocos-casual-game-expert"
Commentary: Implements ad placements with optimal user experience
```

### Example 3: Progression System
```
Context: Player retention
User: "Design a simple progression system with daily rewards"
Assistant: "I will use $cocos-casual-game-expert"
Commentary: Creates engaging retention mechanics
```

## Core Patterns

### Simple Game Loop
```typescript
@ccclass('CasualGameManager')
export class CasualGameManager extends Component {
    @property
    scorePerTap: number = 1;
    
    @property(Label)
    scoreLabel: Label = null;
    
    @property(Node)
    gameOverPanel: Node = null;
    
    private _score: number = 0;
    private _isPlaying: boolean = false;
    
    start() {
        this.startGame();
    }
    
    startGame() {
        this._score = 0;
        this._isPlaying = true;
        this.gameOverPanel.active = false;
        this.updateUI();
    }
    
    onTap() {
        if (!this._isPlaying) return;
        
        this._score += this.scorePerTap;
        this.updateUI();
        this.checkGameOver();
        
        // Haptic feedback
        if (sys.platform === sys.Platform.IOS || sys.platform === sys.Platform.ANDROID) {
            // Trigger haptic
        }
    }
    
    showRewardedAd() {
        // Ad integration
        AdManager.instance.showRewardedVideo(() => {
            this.continueGame();
        });
    }
}
```

### Monetization Strategy
```typescript
@ccclass('MonetizationManager')
export class MonetizationManager extends Component {
    @property
    interstitialInterval: number = 3; // Show every 3 games
    
    private _gamesPlayed: number = 0;
    
    onGameOver() {
        this._gamesPlayed++;
        
        if (this._gamesPlayed % this.interstitialInterval === 0) {
            this.showInterstitial();
        }
    }
    
    offerRewardedAd(): Promise<boolean> {
        return new Promise((resolve) => {
            // Show reward prompt UI
            this.showRewardPrompt(() => {
                AdManager.instance.showRewardedVideo(() => {
                    resolve(true);
                });
            });
        });
    }
}
```

### Analytics Events
- Game Start
- Level Complete
- Ad Shown/Clicked
- IAP Purchase
- Tutorial Step
- Session Length
- Retention (D1, D3, D7)

## Best Practices

### Tutorial Design
1. Show, don't tell
2. Interactive first experience
3. Highlight important elements
4. Progressive complexity
5. Skip option for returning players

### Optimization Tips
- Keep app size under 100MB
- Load time under 3 seconds
- First interaction within 5 seconds
- Simple, readable UI
- High contrast visuals

## Handoff Guidance

### To cocos-monetization-specialist
Trigger: Advanced monetization
Handoff: "Core game ready. Monetization optimization needed for: [features]"

### To cocos-ui-builder
Trigger: UI polish needed
Handoff: "Game mechanics complete. UI enhancement needed for: [screens]"

### To cocos-mobile-optimizer
Trigger: Performance tuning
Handoff: "Casual game built. Mobile optimization needed for: [platforms]"

## Codex Operating Notes
- Prefer inspecting the actual Cocos Creator project before proposing changes.
- Keep edits scoped to the requested game system, platform, or workflow.
- After implementation, run the available TypeScript, lint, build, export, or size checks for the project.
- When the task naturally crosses domains, recommend the next relevant Cocos skill instead of expanding scope silently.
