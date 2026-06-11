import { describe, expect, it } from 'vitest';
import { planAnimation } from '../assets/scripts/ui/animationPlan';
import type { BattleAnimationPayload } from '../assets/scripts/bridge/messages';

function payload(overrides: Partial<BattleAnimationPayload>): BattleAnimationPayload {
    return {
        projectileDirection: 'forward', projectileIntensity: 1, projectileLabel: 'apple',
        playerMotion: 'nudge', monsterMotion: 'hurt', feedbackText: 'Correct!',
        showsCritOverlay: false, damageLabel: '-1!', playsMonsterDefeatCue: false,
        correct: true, comboTriggered: false, battleEnded: false,
        ...overrides,
    };
}

describe('planAnimation', () => {
    it('correct answer: projectile forward, player nudge, monster hurt + floater after impact delay', () => {
        const steps = planAnimation(payload({}));
        expect(steps).toContainEqual({ target: 'projectile', effect: 'forward', delayMs: 0, label: 'apple', intensity: 1 });
        expect(steps).toContainEqual({ target: 'player', effect: 'nudge', delayMs: 0 });
        expect(steps).toContainEqual({ target: 'monster', effect: 'hurt', delayMs: 340 });
        expect(steps).toContainEqual({ target: 'floaterMonster', effect: 'show', delayMs: 340, label: '-1' });
    });

    it('wrong answer: projectile backward, player hurt + floater after impact delay', () => {
        const steps = planAnimation(payload({
            projectileDirection: 'backward', playerMotion: 'hurt', monsterMotion: 'idle', correct: false,
        }));
        expect(steps).toContainEqual({ target: 'player', effect: 'hurt', delayMs: 340 });
        expect(steps).toContainEqual({ target: 'floaterPlayer', effect: 'show', delayMs: 340, label: '-1' });
        expect(steps.find(s => s.target === 'monster')).toBeUndefined();
    });

    it('combo: player cast immediately, monster zoom + crit overlay after impact delay', () => {
        const steps = planAnimation(payload({
            projectileIntensity: 2, playerMotion: 'cast', monsterMotion: 'zoom',
            showsCritOverlay: true, damageLabel: '-2!', comboTriggered: true,
        }));
        expect(steps).toContainEqual({ target: 'player', effect: 'cast', delayMs: 0 });
        expect(steps).toContainEqual({ target: 'monster', effect: 'zoom', delayMs: 340 });
        expect(steps).toContainEqual({ target: 'crit', effect: 'show', delayMs: 340, label: '-2!' });
        expect(steps).toContainEqual({ target: 'floaterMonster', effect: 'show', delayMs: 340, label: '-2' });
    });
});
