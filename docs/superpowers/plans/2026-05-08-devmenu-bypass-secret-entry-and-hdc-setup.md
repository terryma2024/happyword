# DevMenu BypassSecret Entry + HDC Setup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a top-level `BypassSecret` button in `DevMenuPage` that opens a dedicated BypassSecret entry page, and provide an `hdc` UI-automation script that fills the secret from host `~/.env` after install.

**Architecture:** Reuse existing persistence and header attachment (`BackendEnv.loadBypassSecret/saveBypassSecret` + AppStorage mirror + `x-vercel-protection-bypass`). Add one new page to edit the value, a small DevMenu header-row change to navigate to it, one minimal `ohosTest` UI suite to validate reachability, and one host script to drive the UI via `hdc shell uitest`.

**Tech Stack:** HarmonyOS NEXT, ArkTS, ArkUI `router`, `@ohos/hypium`, `@kit.TestKit`, `hdc`, bash.

---

## File map (create/modify)

**Create**
- `entry/src/main/ets/pages/BypassSecretPage.ets` — dedicated entry page (input + save/cancel).
- `scripts/setup_bypass_secret_on_device.sh` — host automation: open DevMenu → open BypassSecret page → fill & save.
- `entry/src/ohosTest/ets/test/BypassSecretEntry.ui.test.ets` — minimal UI test for navigation + save (device/emulator).

**Modify**
- `entry/src/main/ets/pages/DevMenuPage.ets` — header row adds `BypassSecret` button and navigation handler.
- `entry/src/main/resources/base/profile/main_pages.json` — register `pages/BypassSecretPage`.
- `AppScope/app.json5` — bump `versionName` patch.
- `entry/src/ohosTest/ets/test/List.test.ets` — optional: import/register new suite.

---

### Task 1: Version bump (patch)

**Files:**
- Modify: `AppScope/app.json5`

- [ ] **Step 1: Edit `versionName`**
  - Change `versionName` from `0.6.0` → `0.6.1`.
  - Leave `versionCode` unchanged.

- [ ] **Step 2: Commit**

```bash
git add AppScope/app.json5
git commit -m "$(cat <<'EOF'
chore: bump version to 0.6.1

EOF
)"
```

---

### Task 2: Add `BypassSecretPage`

**Files:**
- Create: `entry/src/main/ets/pages/BypassSecretPage.ets`
- Modify: `entry/src/main/resources/base/profile/main_pages.json`

- [ ] **Step 1: Create page skeleton with stable ids**

Create `entry/src/main/ets/pages/BypassSecretPage.ets`:

```ts
import { router } from '@kit.ArkUI';
import { BusinessError } from '@ohos.base';
import { loadBypassSecret, saveBypassSecret } from '../services/BackendEnv';

@Component
export struct BypassSecretPage {
  @State private secret: string = '';
  @State private errorMessage: string = '';

  aboutToAppear(): void {
    loadBypassSecret().then((s: string): void => {
      if (s.length > 0) {
        this.secret = s;
      }
    }).catch((err: BusinessError): void => {
      console.error(`BypassSecretPage.load failed: ${JSON.stringify(err)}`);
    });
  }

  build(): void {
    Column({ space: 12 }) {
      Text('Bypass secret')
        .id('BypassSecretPageTitle')
        .fontSize(20)
        .fontWeight(FontWeight.Bold);

      TextInput({ placeholder: 'paste from Vercel project settings', text: this.secret })
        .id('BypassSecretPageInput')
        .height(44)
        .type(InputType.Password)
        .onChange((v: string): void => {
          this.secret = v;
          this.errorMessage = '';
        });

      if (this.errorMessage.length > 0) {
        Text(this.errorMessage)
          .id('BypassSecretPageError')
          .fontSize(12)
          .fontColor('#E63946');
      }

      Row({ space: 12 }) {
        Button('Cancel')
          .id('BypassSecretPageCancelButton')
          .layoutWeight(1)
          .height(40)
          .onClick((): void => router.back());

        Button('Save')
          .id('BypassSecretPageSaveButton')
          .layoutWeight(1)
          .height(40)
          .onClick((): void => {
            const trimmed: string = this.secret.trim();
            if (trimmed.length === 0) {
              this.errorMessage = 'Secret cannot be empty';
              return;
            }
            saveBypassSecret(trimmed).then((): void => {
              router.back();
            }).catch((err: BusinessError): void => {
              console.error(`BypassSecretPage.save failed: ${JSON.stringify(err)}`);
              this.errorMessage = 'Failed to save';
            });
          });
      }
      .width('100%');
    }
    .padding(16)
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start);
  }
}
```

- [ ] **Step 2: Register the page in `main_pages.json`**
Add `pages/BypassSecretPage` to `entry/src/main/resources/base/profile/main_pages.json`.

- [ ] **Step 3: Build**

```bash
hvigorw assembleHap --no-daemon
```

- [ ] **Step 4: Commit**

```bash
git add entry/src/main/ets/pages/BypassSecretPage.ets entry/src/main/resources/base/profile/main_pages.json
git commit -m "$(cat <<'EOF'
feat(client): add BypassSecretPage

EOF
)"
```

---

### Task 3: DevMenu header button → navigate to page (TDD)

**Files:**
- Modify: `entry/src/main/ets/pages/DevMenuPage.ets`
- Create: `entry/src/ohosTest/ets/test/BypassSecretEntry.ui.test.ets`

- [ ] **Step 1: Write failing ohosTest (button exists + opens page)**

Create `entry/src/ohosTest/ets/test/BypassSecretEntry.ui.test.ets`:

```ts
import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry, Driver, ON, Component } from '@kit.TestKit';
import { Want } from '@kit.AbilityKit';

const BUNDLE: string = 'com.terryma.wordmagicgame';
const DELEGATOR: abilityDelegatorRegistry.AbilityDelegator =
  abilityDelegatorRegistry.getAbilityDelegator();

async function launchApp(): Promise<Driver> {
  const want: Want = { bundleName: BUNDLE, abilityName: 'EntryAbility' };
  await DELEGATOR.startAbility(want);
  const driver: Driver = Driver.create();
  await driver.delayMs(1200);
  return driver;
}

export default function bypassSecretEntryUiTest(): void {
  describe('BypassSecretEntryUiTest', () => {
    it('devMenuBypassSecretButtonOpensEntryPage', 0, async (done: Function) => {
      const driver: Driver = await launchApp();
      await driver.assertComponentExist(ON.text('Developer options'));
      const btn: Component | null = await driver.findComponent(ON.id('DevMenuBypassSecretButton'));
      expect(btn !== null).assertTrue();
      if (btn !== null) {
        await btn.click();
        await driver.delayMs(600);
      }
      const title: Component | null = await driver.findComponent(ON.id('BypassSecretPageTitle'));
      expect(title !== null).assertTrue();
      done();
    });
  });
}
```

- [ ] **Step 2: Run suite to verify RED**

```bash
hvigorw --mode module -p module=entry@ohosTest assembleHap --no-daemon
hdc -t 127.0.0.1:5555 install -r entry/build/default/outputs/default/entry-default-signed.hap
hdc -t 127.0.0.1:5555 install -r entry/build/default/outputs/ohosTest/entry-ohosTest-signed.hap
hdc -t 127.0.0.1:5555 shell aa test -b com.terryma.wordmagicgame -m entry_test \
  -s unittest OpenHarmonyTestRunner -s class BypassSecretEntryUiTest -s timeout 60000 -w 1800
```

- [ ] **Step 3: Implement DevMenu button + navigation (GREEN)**
In `DevMenuPage.ets` header row before `Refresh manifest` button:

```ts
Button('BypassSecret')
  .id('DevMenuBypassSecretButton')
  .fontSize(13)
  .height(36)
  .enabled(!this.applying)
  .onClick((): void => {
    router.pushUrl({ url: 'pages/BypassSecretPage' });
  });
```

- [ ] **Step 4: Re-run suite to verify GREEN**

- [ ] **Step 5: Commit**

```bash
git add entry/src/main/ets/pages/DevMenuPage.ets entry/src/ohosTest/ets/test/BypassSecretEntry.ui.test.ets
git commit -m "$(cat <<'EOF'
feat(client): add DevMenu BypassSecret entry

EOF
)"
```

---

### Task 4: Host automation script (hdc uitest)

**Files:**
- Create: `scripts/setup_bypass_secret_on_device.sh`

- [ ] **Step 1: Read secret from `~/.env` (no echo)**

```bash
ENV_FILE="${HOME}/.env"
secret="$(/bin/bash -c "set -a; [ -f \"$ENV_FILE\" ] && source \"$ENV_FILE\"; printf '%s' \"\${VERCEL_AUTOMATION_BYPASS_SECRET:-}\"")"
if [[ -z \"$secret\" ]]; then
  echo \"[setup_bypass_secret] missing VERCEL_AUTOMATION_BYPASS_SECRET in ~/.env\" >&2
  exit 2
fi
```

- [ ] **Step 2: UI automation via `hdc shell uitest`**
Drive:
- open app
- go to DevMenu (triple-tap version label)
- tap `DevMenuBypassSecretButton`
- fill `BypassSecretPageInput`
- tap `BypassSecretPageSaveButton`

- [ ] **Step 3: Smoke run**

```bash
scripts/setup_bypass_secret_on_device.sh --target 127.0.0.1:5555
```

- [ ] **Step 4: Commit**

```bash
git add scripts/setup_bypass_secret_on_device.sh
git commit -m "$(cat <<'EOF'
chore(dev): add hdc bypass secret setup script

EOF
)"
```

