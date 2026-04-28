import { describe, it, expect } from '@ohos/hypium';
import { Driver, ON } from '@kit.TestKit';
import {
  launchAppShared,
  clickByIdShared,
} from './RoutingFlow.ui.test';

/**
 * SpeakerButton UI test (spec §15 V0.2 Track B). Covers the
 * `BattleSpeakerButton` that sits next to the Chinese prompt:
 *
 *  - The button must render whenever BattlePage is on-screen, even
 *    when CoreSpeechKit is unavailable on the emulator (the tap
 *    path is a silent no-op inside PronunciationService).
 *  - Tapping it must NOT route away from BattlePage — it should stay
 *    mounted so the player can keep answering.
 *  - Tapping it MUST NOT change the combo counter, the visible
 *    prompt, or the option buttons: it's a side-channel to the TTS
 *    engine, not a game action.
 *
 * Runner: the same 30 s per-test timeout as RoutingFlow.ui.test.
 */
export default function speakerButtonUiTest(): void {
  describe('SpeakerButtonUiTest', () => {
    it('speakerButtonIsIdempotentOnTap', 0, async (done: Function) => {
      const driver: Driver = await launchAppShared();

      await driver.assertComponentExist(ON.id('HomeStartButton'));
      // v0.3.6: HomeStartButton routes to today's adventure. Today-mode
      // ignores cfg.playerHp / monsterHp / monstersTotal so the legacy
      // resetToDefaultConfigShared() guard is no longer needed; the
      // speaker tap path is mode-agnostic.
      await clickByIdShared(driver, 'HomeStartButton');
      // Today-mode loads WordRepository + LearningRecorder
      // asynchronously before pushing BattlePage; bumped from 1000ms
      // to 1500ms so BattlePage is mounted before the assertions.
      await driver.delayMs(1500);
      await driver.assertComponentExist(ON.id('BattleTitle'));
      await driver.assertComponentExist(ON.id('BattlePrompt'));
      // Speaker button rendered unconditionally — even when TTS init
      // fails the layout is stable so the id must exist.
      await driver.assertComponentExist(ON.id('BattleSpeakerButton'));

      // Snapshot pre-tap state so we can assert the tap was a no-op
      // on the game loop (only the TTS engine is poked).
      const promptBefore = await driver.findComponent(ON.id('BattlePrompt'));
      const promptTextBefore: string = await promptBefore.getText();
      await driver.assertComponentExist(ON.text('Combo: 0'));

      // Tap the speaker twice to ensure a repeat-click doesn't fire
      // duplicate routes or break the page. PronunciationService
      // cancels the in-flight utterance on every call so this is the
      // most common real-world sequence ("oh, I missed it — replay").
      await clickByIdShared(driver, 'BattleSpeakerButton');
      await driver.delayMs(200);
      await clickByIdShared(driver, 'BattleSpeakerButton');
      await driver.delayMs(200);

      await driver.assertComponentExist(ON.id('BattleTitle'));
      await driver.assertComponentExist(ON.id('BattleSpeakerButton'));
      const promptAfter = await driver.findComponent(ON.id('BattlePrompt'));
      const promptTextAfter: string = await promptAfter.getText();
      expect(promptTextAfter).assertEqual(promptTextBefore);
      // Still pre-tap combo — speaker taps never touch the engine.
      await driver.assertComponentExist(ON.text('Combo: 0'));

      // Leave the suite in a clean state for the next test.
      await clickByIdShared(driver, 'BattleFinishButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('ResultTitle'));
      await clickByIdShared(driver, 'ResultHomeButton');
      await driver.delayMs(800);
      await driver.assertComponentExist(ON.id('HomeStartButton'));

      expect(true).assertTrue();
      done();
    });
  });
}
