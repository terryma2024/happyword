---
name: cocos-ui-builder
description: Use when working on uI/UX implementation, menu systems, HUD design, or any user interface work in Cocos Creator projects.
---

# Cocos UI Builder

## Overview
This Codex skill adapts the upstream Cocos Creator Claude agent guidance for use in Codex.

Expert in creating responsive, accessible UI systems in Cocos Creator. Use this skill for UI/UX implementation, menu systems, HUD design, or any user interface work in Cocos Creator projects.

## Expertise
- Cocos Creator UI components (Button, Label, Sprite, etc.)
- Layout systems (Layout, Widget, ScrollView)
- Responsive design for multiple resolutions
- UI animations and transitions
- Touch event handling
- Localization integration
- Accessibility features
- Performance optimization for UI

## Usage Examples

### Example 1: Menu System
```
Context: Main menu implementation
User: "Create an animated main menu with settings"
Assistant: "I will use $cocos-ui-builder"
Commentary: Implements responsive menu with smooth transitions
```

### Example 2: In-Game HUD
```
Context: Game UI overlay
User: "Design HUD with health, score, and minimap"
Assistant: "I will use $cocos-ui-builder"
Commentary: Creates efficient HUD with proper anchoring
```

### Example 3: Dialog System
```
Context: RPG dialog interface
User: "Implement dialog boxes with character portraits"
Assistant: "I will use $cocos-ui-builder"
Commentary: Builds flexible dialog system with animation support
```

## UI Patterns

### Responsive Layout
```typescript
@ccclass('ResponsiveUI')
export class ResponsiveUI extends Component {
    @property(Widget)
    widget: Widget = null;
    
    onLoad() {
        this.setupResponsiveLayout();
        this.addResizeListener();
    }
    
    setupResponsiveLayout() {
        const canvas = find('Canvas');
        const designSize = canvas.getComponent(Canvas).designResolution;
        
        // Configure widget for responsive behavior
        this.widget.isAlignTop = true;
        this.widget.isAlignBottom = true;
        this.widget.isAlignLeft = true;
        this.widget.isAlignRight = true;
    }
}
```

### UI Component Structure
- Canvas
  - SafeArea
    - Header
    - Content
      - ScrollView
      - Panels
    - Footer
    - Popups
    - Loading

## Best Practices
1. Use prefabs for reusable UI elements
2. Implement object pooling for dynamic lists
3. Optimize draw calls with batch rendering
4. Use 9-slice sprites for scalable backgrounds
5. Implement proper touch zones for mobile

## Handoff Guidance

### To cocos-animation-specialist
Trigger: UI animations needed
Handoff: "UI layout complete. Animation sequences needed for: [elements]"

### To cocos-localization-expert
Trigger: Multi-language support
Handoff: "UI structure ready. Localization setup needed for: [texts]"

### To cocos-mobile-optimizer
Trigger: Mobile UI optimization
Handoff: "UI implemented. Mobile optimization needed for: [screens]"

## Codex Operating Notes
- Prefer inspecting the actual Cocos Creator project before proposing changes.
- Keep edits scoped to the requested game system, platform, or workflow.
- After implementation, run the available TypeScript, lint, build, export, or size checks for the project.
- When the task naturally crosses domains, recommend the next relevant Cocos skill instead of expanding scope silently.
