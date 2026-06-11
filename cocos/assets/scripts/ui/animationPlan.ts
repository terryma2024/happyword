// Declarative animation steps for a battle/animation message, mirroring
// BattleView.triggerAnimation (BattleView.swift:767-840). Pure TS.

import type { BattleAnimationPayload } from '../bridge/messages';

/// Native battleImpactDelayNs = 340ms: hits land after the projectile flight.
export const IMPACT_DELAY_MS = 340;

export interface AnimationStep {
    target: 'player' | 'monster' | 'projectile' | 'crit' | 'floaterPlayer' | 'floaterMonster';
    effect: string;
    delayMs: number;
    label?: string;
    intensity?: number;
}

export function planAnimation(payload: BattleAnimationPayload): AnimationStep[] {
    const steps: AnimationStep[] = [];
    const damage = Math.max(payload.projectileIntensity, 1);
    const floaterLabel = `-${damage}`;

    steps.push({
        target: 'projectile',
        effect: payload.projectileDirection,
        delayMs: 0,
        label: payload.projectileLabel,
        intensity: damage,
    });

    switch (payload.playerMotion) {
        case 'nudge':
            steps.push({ target: 'player', effect: 'nudge', delayMs: 0 });
            break;
        case 'cast':
            steps.push({ target: 'player', effect: 'cast', delayMs: 0 });
            break;
        case 'hurt':
            steps.push({ target: 'player', effect: 'hurt', delayMs: IMPACT_DELAY_MS });
            steps.push({ target: 'floaterPlayer', effect: 'show', delayMs: IMPACT_DELAY_MS, label: floaterLabel });
            break;
        default:
            break;
    }

    switch (payload.monsterMotion) {
        case 'hurt':
            steps.push({ target: 'monster', effect: 'hurt', delayMs: IMPACT_DELAY_MS });
            steps.push({ target: 'floaterMonster', effect: 'show', delayMs: IMPACT_DELAY_MS, label: floaterLabel });
            break;
        case 'zoom':
            steps.push({ target: 'monster', effect: 'zoom', delayMs: IMPACT_DELAY_MS });
            if (payload.showsCritOverlay) {
                steps.push({ target: 'crit', effect: 'show', delayMs: IMPACT_DELAY_MS, label: payload.damageLabel });
            }
            steps.push({ target: 'floaterMonster', effect: 'show', delayMs: IMPACT_DELAY_MS, label: floaterLabel });
            break;
        default:
            break;
    }

    return steps;
}
