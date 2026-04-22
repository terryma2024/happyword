import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry, Driver, ON } from '@kit.TestKit';
import { Want } from '@kit.AbilityKit';

const delegator: abilityDelegatorRegistry.AbilityDelegator = abilityDelegatorRegistry.getAbilityDelegator();

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => setTimeout(resolve, ms));
}

export default function indexPageUiTest(): void {
  describe('IndexPageUiTest', () => {
    it('clickHelloButton_shouldNotBlockUi', 0, async (done: Function) => {
      const bundleName = abilityDelegatorRegistry.getArguments().bundleName;
      const want: Want = {
        bundleName,
        abilityName: 'EntryAbility'
      };

      await delegator.startAbility(want);
      await sleep(1000);

      const driver = Driver.create();
      await driver.delayMs(500);

      await driver.assertComponentExist(ON.id('HelloWorld'));
      await driver.assertComponentExist(ON.id('HelloButton'));

      const button = await driver.findComponent(ON.id('HelloButton'));
      await button.click();
      await driver.delayMs(500);

      // If a blocking dialog appears, follow-up interactions commonly fail.
      const buttonAgain = await driver.findComponent(ON.id('HelloButton'));
      await buttonAgain.click();
      await driver.delayMs(500);

      await driver.assertComponentExist(ON.id('HelloWorld'));
      expect(true).assertTrue();
      done();
    });
  });
}

