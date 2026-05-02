# V0.6.x — Scan Binding 从图库选择二维码 — 设计

- **Date:** 2026-05-02
- **Status:** Design-for-implementation; revision 1
- **Roadmap:** [WordMagicGame_roadmap.md §13 V0.6](../../WordMagicGame_roadmap.md)
- **Parent design:** [`2026-05-01-v0.6-parent-account-design.md`](2026-05-01-v0.6-parent-account-design.md) §3.2 设备绑定 / `ScanBindingPage`
- **Tech stack additions:** `@kit.ScanKit` 静态图解码 API（`scanBarcode.decode`，已在 SDK 中，无新增依赖）；`qrcode[pil]` 已在 server 侧用于家长 web QR 渲染，复用作为 ohosTest 固件生成器
- **Out-of-scope:** 修改 V0.5.8 lesson-import 路径上的 `LessonImagePicker` 行为契约；动态从孩子的相册读 QR（孩子设备上的相册一般没有 QR 截图，本特性的真实使用者是「家长把 QR 截图发给孩子」场景）；多张图批量解码

---

## 1. 背景与一句话设计

### 1.1 背景

V0.6.2 上线了 `ScanBindingPage`，提供两条绑定路径：

1. **打开扫码器** — 调 `@kit.ScanKit` 的 `scanBarcode.startScanForResult`，活摄像头扫家长 web 上显示的 QR。
2. **手动输入短码** — 在家长无法把 web 端 QR 物理出示到孩子设备摄像头前时，孩子手输 web 上同步显示的 6 位短码。

第二条路径是兜底，但**短码会过期**（默认 5 分钟），且要求家长能口播 6 位数字。实际使用中常见场景：

- 家长把 web 上的 QR 截图通过微信发到孩子的平板，让孩子在 ScanBindingPage 上扫这张截图。
- 家长用平板自己打开家长 web → 截图 → 想让孩子在同一台设备上完成绑定。

当前 ScanBindingPage 没有「从图库选 QR 图片」的入口，孩子只能用摄像头去扫平板自己的屏幕，体验极差。

### 1.2 一句话设计

> 在 `ScanBindingPage` 的 idle 状态新增「📷 从图库选择二维码」按钮；点击触发系统相册选图，对选中的图片调 `@kit.ScanKit` 的 `scanBarcode.decode` 静态解码 API 拿到 QR 字符串，进 `extractTokenFromQrPayload` → 已有的 `redeem(token, '')` 路径；解码失败或 payload 不是 `/p/<token>` 形态统一映射到 `TOKEN_INVALID`（与现有手动输入失败 UX 同色同文案）。配套提供 ohosTest 自动化，沿用 V0.5.8 lesson-fixture 的「ohosTest rawfile 预打包 → 运行时拷到 `appCtx.tempDir` → AppStorage override key 让 picker 直接返回该路径」方式，新建一张固定内容的 QR PNG 作为测试固件。

### 1.3 成功标准

- 真机上：家长把 QR 截图发到孩子平板，孩子点 ScanBindingPage 上的「📷 从图库选择二维码」→ 选中截图 → 设备进入 bound 状态，等价于摄像头扫码。
- ohosTest 上：`ParentBindingFlowV06.ui.test.ets` 新增 1 个用例 `pickQrFromGalleryRedeemsAndFlipsToBound`，端到端跑「拷固件 → 写 picker override → 写 decoder override → tap → 断言 ScanBindingSuccessLabel 可见」全链路。
- 旧路径（打开扫码器、手动输入短码）零回归；`LessonImagePicker` 在 V0.5.8 路径下行为契约不变（`LESSON_IMAGE_PICKER_OVERRIDE_URI_KEY` 仍生效，gallery 选图返回 `PickedImage` 的字段不变）。

---

## 2. 关键决策记录

| 维度 | 选择 | 理由 |
| --- | --- | --- |
| 生产解码 API | `scanBarcode.decode({ inputType: ScanInputType.IMAGE_URI, uri })`（一次性静态解码） | 比 `enableAlbum: true`（在 ScanKit 自带相册按钮里）多一个 ArkUI 入口控件 — 给孩子明确视觉提示；且我们能在解码层注入 stub 适配器，给 ohosTest 提供干净 seam。`enableAlbum` 路径的相册 UI 在系统进程，Hypium 无法稳定驱动 |
| 解码失败 UX | 复用现有 `TOKEN_INVALID` reason + 红字 `二维码或短码无效。` | 孩子能做的下一步动作（重选图 / 让家长重发）与「手输短码错」时完全一致；新增独立 reason 仅为分流诊断而带来枚举膨胀，YAGNI |
| 与 `LessonImagePicker` 关系 | **抽离公共 `PhotoPickerService`**（仅 gallery 半边），让 `LessonImagePicker` 与新 ScanBinding 路径共用 picker 适配器，但**保留独立的 AppStorage override key**（lesson 用 `LESSON_IMAGE_PICKER_OVERRIDE_URI_KEY`，scan-binding 用 `SCAN_BINDING_PHOTO_PICKER_OVERRIDE_URI_KEY`） | 避免重复 ~50 行 picker 适配器；同时两个 override key 物理隔离，避免某次 ohosTest 写过 lesson key 后污染 scan-binding 测试。Camera 半边由 lesson 独占，不进 PhotoPickerService |
| ohosTest 解码层注入 | 新增 `SCAN_BINDING_BARCODE_DECODER_OVERRIDE_PAYLOAD_KEY` AppStorage 短路 — 测试时 `RealBarcodeImageDecoder.decodeFromUri` 命中 override 直接返回字符串，不调真实 `scanBarcode.decode` | `scanBarcode.decode` 在 OpenHarmony 模拟器上对任意应用沙箱下的图片 URI 鉴权不稳（与 V0.5.8 选 `LessonImagePicker` 加 picker override 同因），且我们已经持有 QR 的 raw 内容（在生成 fixture 时），把 raw 内容作为 override 字符串能让端到端测试只断言「上层调度正确 + redeem 链路通」而不绑死系统 ScanKit 的实现细节 |
| 测试固件 | 新增 `entry/src/ohosTest/resources/rawfile/scan_binding_qr_fixture.png`（PNG，内容编码 `https://happyword.vercel.app/p/uitestqr01`），由 `tools/generate_scan_binding_qr_fixture.py` 用 `qrcode` 库生成 | PNG 体积约 800B，可重新生成、可入 git，与 lesson_import_fixture.jpg 同栈位置；token 用 `uitestqr01` 是固定字符串，10 位长度满足 server `MIN_TOKEN_LEN=4 / MAX_TOKEN_LEN=64` 校验，mock server `/api/v1/pair/redeem` 已对任意非空 token 返回成功 |
| 是否同步打开 `enableAlbum:true` | **不打开** | C 选项（dedicated button + enableAlbum 双备）会让用户在「打开扫码器」点完后还能走系统相册路径，但那条路径不可测且 UI 重复；先用 dedicated button 单点上线，观察后再决定是否补 enableAlbum |
| 固件生成脚本入仓位置 | `tools/generate_scan_binding_qr_fixture.py` | `tools/` 下已经有 `recraft/` 等内容生成脚本，约定一致；固件由脚本可重生但 PNG 同时入仓（保证 ohosTest HAP 打包不依赖运行 Python） |

---

## 3. 用户路径

### 3.1 真机用户视角

ScanBindingPage idle 态从两按钮变三按钮：

```
┌─────────────────────────────────────────────────────┐
│ 扫码绑定家长账号                              [返回] │
├─────────────────────────────────────────────────────┤
│         请扫描家长网页 /parent/devices/add          │
│              显示的二维码                           │
│                                                     │
│              [ 打开扫码器 ]                         │
│                                                     │
│           [ 📷 从图库选择二维码 ]   ← NEW           │
│                                                     │
│        [ 无法扫码？手动输入短码 ]                   │
└─────────────────────────────────────────────────────┘
```

点 「📷 从图库选择二维码」 后：

1. `busy=true`，三按钮全 disabled。
2. 系统相册弹出（`@kit.CoreFileKit.picker.PhotoViewPicker`），用户选一张图片。
   - 用户取消：`busy=false`，回到 idle，无错误提示。
3. 解码：调 `scanBarcode.decode({ inputType: IMAGE_URI, uri: pickedUri })`。
   - 解码不出 QR / payload 不是 `/p/<token>` 形态：`failureReason='TOKEN_INVALID'` → 红字「二维码或短码无效。」；`busy=false`。
4. 提取 token，进 `DeviceBindingService.redeem(token, '')` 既有路径。
   - 成功：state 翻 `bound`，渲染🎉 `绑定成功，<昵称>！`。
   - 失败（TOKEN_EXPIRED / TOKEN_REDEEMED / NETWORK / UNKNOWN）：与现有 redeem 失败 UX 完全一致。

### 3.2 失败矩阵

| 阶段 | 失败原因 | `failureReason` | 红字文案 |
| --- | --- | --- | --- |
| 选图 | 用户取消 picker | （不变） | （无） |
| 解码 | `scanBarcode.decode` 抛错（图片中无 QR） | `TOKEN_INVALID` | 二维码或短码无效。 |
| 解析 | QR 解出来但不含 `/p/` | `TOKEN_INVALID` | 二维码或短码无效。 |
| 解析 | QR 解出来 token 长度 <4 或 >64 | `TOKEN_INVALID` | 二维码或短码无效。 |
| Redeem | server 返回 410 TOKEN_EXPIRED | `TOKEN_EXPIRED` | 二维码已过期，请让家长在网页重新生成。 |
| Redeem | server 返回 409 TOKEN_REDEEMED | `TOKEN_REDEEMED` | 此二维码已被使用过。 |
| Redeem | 网络异常 | `NETWORK` | 网络异常，请检查后重试。 |

---

## 4. 模块切分与文件结构

### 4.1 新增 / 修改的文件

| 路径 | 角色 | 动作 |
| --- | --- | --- |
| `entry/src/main/ets/services/PhotoPickerService.ets` | 提取出来的 gallery picker 公共服务，定义 `IPhotoPickerAdapter` / `PickedFileRef` / `RealPhotoPickerAdapter` 与 picker override 读取助手 | **新增** |
| `entry/src/main/ets/services/LessonImagePicker.ets` | gallery 半边迁出，camera 半边保留；`LessonImagePicker` 持有 `IPhotoPickerAdapter` + camera 专用 adapter | **修改**（保契约不变） |
| `entry/src/main/ets/services/BarcodeImageDecoder.ets` | 新增 `BarcodeImageDecoderLike` 接口与 `RealBarcodeImageDecoder`（包 `scanBarcode.decode` 调用），含 ohosTest override key 短路 | **新增** |
| `entry/src/main/ets/services/DeviceBindingService.ets` | 新增 `BarcodeImageDecoderLike` 字段（构造注入）+ `startFromGalleryImage(uri)` 方法 | **修改** |
| `entry/src/main/ets/pages/ScanBindingPage.ets` | 新增 `ScanBindingGalleryButton`、`onPickQrTap()`，`bootstrapService()` 多构造一个 `RealPhotoPickerAdapter` + `RealBarcodeImageDecoder` | **修改** |
| `tools/generate_scan_binding_qr_fixture.py` | 用 `qrcode` 生成 `entry/src/ohosTest/resources/rawfile/scan_binding_qr_fixture.png`，幂等 | **新增** |
| `entry/src/ohosTest/resources/rawfile/scan_binding_qr_fixture.png` | 测试 QR 固件 PNG，~800B | **新增** |
| `entry/src/test/PhotoPickerService.test.ets` | 单元测试：override key 解析 / `RealPhotoPickerAdapter.selectGallery` 命中 override 时返回固定 `PickedFileRef` | **新增** |
| `entry/src/test/BarcodeImageDecoder.test.ets` | 单元测试：override key 命中时 `decodeFromUri` 返回 override 字符串 / 无 override 时调用真实 ScanKit（mock 后断言被调用一次） | **新增** |
| `entry/src/test/DeviceBindingService.test.ets` | 增量补 2 个用例：`startFromGalleryImage` 成功翻 bound；解码失败/parser 失败 → fail TOKEN_INVALID | **修改** |
| `entry/src/test/LessonImagePicker.test.ets` | 调整：构造 `LessonImagePicker` 改用注入式 picker（接受公共 `IPhotoPickerAdapter`），断言原 lesson key 行为不变 | **修改** |
| `entry/src/ohosTest/ets/test/ParentBindingFlowV06.ui.test.ets` | 新增 `pickQrFromGalleryRedeemsAndFlipsToBound` 用例 + `ensureScanBindingQrFixtureOnDevice()` 助手 | **修改** |
| `docs/WordMagicGame_roadmap.md` | V0.6 行追加「ScanBindingPage 从图库选择二维码」一句 | **修改** |
| `docs/WordMagicGame_overall_spec.md` | ohosTest 章节加新用例描述 | **修改** |
| `.cursor/dev-commands.md` | 把 lesson 固件段扩成「lesson + scan-binding QR」两个固件的统一描述 | **修改** |

### 4.2 模块边界

```
ScanBindingPage
   ├─ PhotoPickerService.RealPhotoPickerAdapter (gallery only)
   │    └─ AppStorage[SCAN_BINDING_PHOTO_PICKER_OVERRIDE_URI_KEY] (test-only short circuit)
   ├─ BarcodeImageDecoder.RealBarcodeImageDecoder
   │    └─ AppStorage[SCAN_BINDING_BARCODE_DECODER_OVERRIDE_PAYLOAD_KEY] (test-only short circuit)
   └─ DeviceBindingService.startFromGalleryImage(uri)
         ├─ decoder.decodeFromUri(uri)               # may throw / return non-QR text
         ├─ extractTokenFromQrPayload(payload)       # existing parser
         └─ redeem(token, '')                        # existing redeem state machine
```

`PhotoPickerService` 与 `BarcodeImageDecoder` 互不依赖；`DeviceBindingService` 只依赖 `BarcodeImageDecoderLike`（不知道 picker 的存在，picker 由 page 调用后把 URI 喂进来）。

### 4.3 与 LessonImagePicker 的边界

`PhotoPickerService` 只承担 gallery 选图；它的 `IPhotoPickerAdapter` 接口只有 `selectGallery(): Promise<PickedFileRef | null>`。

V0.5.8 的 `LessonImagePicker` 重构为：

```typescript
class LessonImagePicker {
  constructor(
    galleryPicker: IPhotoPickerAdapter,   // 来自 PhotoPickerService
    cameraPicker: ILessonCameraAdapter,   // 留在 LessonImagePicker 内部
    reader: IPhotoFileReader,
  ) { ... }
}
```

外部构造点（`ParentAdminPage`）从「`new LessonImagePicker(new RealPhotoPickerAdapter(ctx), new RealPhotoFileReader())`」改为「`new LessonImagePicker(new RealPhotoPickerAdapter(ctx, LESSON_IMAGE_PICKER_OVERRIDE_URI_KEY), new RealLessonCameraAdapter(ctx), new RealPhotoFileReader())`」。

`RealPhotoPickerAdapter` 的构造参数加一个 `overrideKey: string`，让两个调用方各自传自己的 key（lesson 传 `LESSON_IMAGE_PICKER_OVERRIDE_URI_KEY`，scan binding 传 `SCAN_BINDING_PHOTO_PICKER_OVERRIDE_URI_KEY`）。这样：

- 生产路径：override key 为空，走系统 `picker.PhotoViewPicker`，行为与之前完全一致。
- ohosTest：写哪个 key 只影响哪个调用方，互不串扰。
- 现有 `LESSON_IMAGE_PICKER_OVERRIDE_URI_KEY` 常量名 / 值不变，V0.5.8 测试零改动。

---

## 5. 接口契约

### 5.1 `PhotoPickerService.ets`

```typescript
export class PickedFileRef {
  uri: string = '';
}

export interface IPhotoPickerAdapter {
  selectGallery(): Promise<PickedFileRef | null>;
}

/** Reads an AppStorage override key; returns '' when unset / non-string. */
export function readPickerOverrideUri(overrideKey: string): string;

export class RealPhotoPickerAdapter implements IPhotoPickerAdapter {
  constructor(ctx: common.UIAbilityContext, overrideKey: string);
  async selectGallery(): Promise<PickedFileRef | null>;
}
```

`overrideKey === ''` 时禁用 override（行为等价于 production-only）。`overrideKey` 非空时优先读 `AppStorage.get<string>(overrideKey)`，命中即直接返回 `PickedFileRef{uri: <override>}`。

### 5.2 `BarcodeImageDecoder.ets`

```typescript
export const SCAN_BINDING_BARCODE_DECODER_OVERRIDE_PAYLOAD_KEY: string =
  'scanBindingBarcodeDecoderOverridePayload';

export interface BarcodeImageDecoderLike {
  /** Returns the decoded barcode text. Throws on no-barcode / SDK error. */
  decodeFromUri(uri: string): Promise<string>;
}

export class RealBarcodeImageDecoder implements BarcodeImageDecoderLike {
  async decodeFromUri(uri: string): Promise<string>;  // override key short-circuit; otherwise scanBarcode.decode
}

export class NoBarcodeFoundError extends Error {}
```

`decodeFromUri` 不返回 token，只返回原始 payload；token 提取仍由现有 `extractTokenFromQrPayload` 完成（保证 production / test 共用同一 parser）。

### 5.3 `PhotoPickerService` override key 命名

```typescript
// 与 SCAN_BINDING_BARCODE_DECODER_OVERRIDE_PAYLOAD_KEY 一起在
// BarcodeImageDecoder.ets 中导出（同为 scan-binding 测试基础设施常量，
// 便于 ohosTest 一行 import 拿到两枚 key）。
export const SCAN_BINDING_PHOTO_PICKER_OVERRIDE_URI_KEY: string =
  'scanBindingPhotoPickerOverrideUri';
```

`PhotoPickerService.ets` 不依赖该常量；`ScanBindingPage` 在 `bootstrapService()` 里把这枚 key 字符串字面量传给 `RealPhotoPickerAdapter` 的 `overrideKey` 构造参数。这样 `PhotoPickerService` 只与「key 字符串」打交道，与具体调用方解耦；`LessonImagePicker.ets` 继续 `export const LESSON_IMAGE_PICKER_OVERRIDE_URI_KEY` 不变。

### 5.4 `DeviceBindingService.startFromGalleryImage`

```typescript
class DeviceBindingService {
  // existing constructor adds one parameter:
  constructor(
    scanner: BarcodeScannerLike,
    decoder: BarcodeImageDecoderLike,   // NEW
    http: BindingHttpClientLike,
    deviceIdProvider: DeviceIdProvider,
    credentials: CloudCredentials,
  );

  /** Pick → decode → token-extract → existing redeem path. */
  async startFromGalleryImage(uri: string): Promise<void>;
}
```

内部状态机扩展：

```
Idle
  start()                  → Scanning → Redeeming → Bound | Failed
  redeemShortCode(code)    → Scanning → Redeeming → Bound | Failed
  startFromGalleryImage(u) → Scanning → Redeeming → Bound | Failed   (NEW)
```

`startFromGalleryImage` 与 `start()` 共用 transition('scanning') / fail / transition('redeeming') / transition('bound') 既有路径；只在「scanner.scan() vs decoder.decodeFromUri」上分叉。

---

## 6. 测试策略

### 6.1 ArkTS 单元测试（host-side via `entry/src/test/`）

| 文件 | 用例 | 期望 |
| --- | --- | --- |
| `PhotoPickerService.test.ets` | `readPickerOverrideUri returns trimmed string when key is set` | 写 `'  /tmp/x.png\n'` → 读到 `/tmp/x.png` |
| `PhotoPickerService.test.ets` | `readPickerOverrideUri returns '' for empty / missing / non-string` | undefined / null / 数字 → '' |
| `PhotoPickerService.test.ets` | `RealPhotoPickerAdapter.selectGallery returns override path when key non-empty` | 写 override key → 不调系统 picker，返回 `PickedFileRef{uri: <override>}` |
| `BarcodeImageDecoder.test.ets` | `RealBarcodeImageDecoder.decodeFromUri returns override payload when key non-empty` | 写 override key → 不调 ScanKit，返回 override 字符串 |
| `BarcodeImageDecoder.test.ets` | `SCAN_BINDING_BARCODE_DECODER_OVERRIDE_PAYLOAD_KEY constant value pinned` | 常量 == `'scanBindingBarcodeDecoderOverridePayload'` |
| `DeviceBindingService.test.ets` | `startFromGalleryImage redeems on valid pair URL` | stub decoder 返回 `https://happyword.vercel.app/p/abc12345` → state 翻 bound，credentials.saveBinding 被调一次 |
| `DeviceBindingService.test.ets` | `startFromGalleryImage fails TOKEN_INVALID when decoder throws` | stub decoder throws `NoBarcodeFoundError` → fail reason TOKEN_INVALID |
| `DeviceBindingService.test.ets` | `startFromGalleryImage fails TOKEN_INVALID when payload has no /p/` | stub decoder 返回 `'hello world'` → fail reason TOKEN_INVALID |
| `DeviceBindingService.test.ets` | `startFromGalleryImage fails TOKEN_INVALID on token length out of range` | stub decoder 返回 `'.../p/x'`（长度 1）→ fail TOKEN_INVALID |
| `DeviceBindingService.test.ets` | `startFromGalleryImage maps server TOKEN_EXPIRED through` | stub http 抛 `BindingHttpError('TOKEN_EXPIRED', ...)` → fail TOKEN_EXPIRED |
| `LessonImagePicker.test.ets` | 现有用例全部保持绿（重构 picker 注入后行为不变） | 复跑无回归 |

### 6.2 ohosTest UI 测试（device-side）

新增一条 `it('pickQrFromGalleryRedeemsAndFlipsToBound', ...)`。骨架：

```typescript
it('pickQrFromGalleryRedeemsAndFlipsToBound', 0, async (done: Function) => {
  // 1. 把固件 PNG 拷到 appCtx.tempDir/scan_binding_qr_fixture.png
  const fixturePath: string = await ensureScanBindingQrFixtureOnDevice();
  expect(fs.accessSync(fixturePath)).assertTrue();

  // 2. 写两个 override key:
  //    - picker override → 让相册 picker 直接返回 fixturePath
  //    - decoder override → 让 ScanKit decode 直接返回 happyword URL
  AppStorage.setOrCreate<string>(
    SCAN_BINDING_PHOTO_PICKER_OVERRIDE_URI_KEY, fixturePath);
  AppStorage.setOrCreate<string>(
    SCAN_BINDING_BARCODE_DECODER_OVERRIDE_PAYLOAD_KEY,
    'https://happyword.vercel.app/p/uitestqr01');

  try {
    const driver: Driver = await launchApp();
    await returnToHome(driver);
    await ensureParentPin(driver, KNOWN_PIN);
    await openConfigPage(driver);
    await tapBindOpensScanBindingPage(driver);     // 已有 helper
    await driver.assertComponentExist(ON.id('ScanBindingGalleryButton'));
    await clickByIdShared(driver, 'ScanBindingGalleryButton');
    await driver.delayMs(3000);                    // picker stub + decode stub + redeem
    await driver.assertComponentExist(ON.id('ScanBindingSuccessLabel'));
  } finally {
    AppStorage.delete(SCAN_BINDING_PHOTO_PICKER_OVERRIDE_URI_KEY);
    AppStorage.delete(SCAN_BINDING_BARCODE_DECODER_OVERRIDE_PAYLOAD_KEY);
  }
  done();
});
```

`ensureScanBindingQrFixtureOnDevice()` 模仿 `ensureLessonImportFixtureOnDevice`：

```typescript
async function ensureScanBindingQrFixtureOnDevice(): Promise<string> {
  const appCtx = DELEGATOR.getAppContext();
  const dest = `${appCtx.tempDir}/scan_binding_qr_fixture.png`;
  if (fs.accessSync(dest)) return dest;
  const moduleCtx = appCtx.createModuleContext('entry_test');
  const bytes: Uint8Array = await moduleCtx.resourceManager.getRawFileContent(
    'scan_binding_qr_fixture.png');
  const file = await fs.open(dest, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  try { await fs.write(file.fd, bytes.buffer); } finally { await fs.close(file); }
  return dest;
}
```

### 6.3 Mock server

不新增 endpoint。`/api/v1/pair/redeem` 已经接受任意 token，对 `uitestqr01` 返回成功（`_short` 分支不命中，因为我们只填 token）。

### 6.4 Production smoke（人工）

- 真机 MatePad（5FFBB25926205346）：
  1. 在家长 web `/parent/devices/add` 上截屏 QR。
  2. 把截屏放到 MatePad 相册（hdc file send + 触发媒体扫描）。
  3. 在 MatePad 上点 ConfigPage → 绑定 → ScanBindingPage → 「📷 从图库选择二维码」。
  4. 选中刚保存的截屏 → 期待绑定成功。

---

## 7. 兼容性 / 回归面

| 表面 | 影响 | 兜底 |
| --- | --- | --- |
| `LessonImagePicker` 公共契约 | picker 适配器构造参数加 `overrideKey: string`；行为契约不变（empty key 等同旧版） | V0.5.8 ohosTest 用例 `tapPickGalleryUploadsAndShowsImported` 复跑必须绿 |
| `DeviceBindingService` 构造签名 | 多一个 `decoder: BarcodeImageDecoderLike` 参数 | V0.6.2 client 路径 `c20e9e4` 改 `bootstrapService()` 即可，所有现有测试用例补构造参数 |
| `ScanBindingPage` UI | idle 列表多一个按钮 | 现有 `ParentBindingFlowV06.ui.test.ets`（59 用例之一）的 `tapBindOpensScanBindingPage` 不依赖按钮顺序，无需修改 |
| `mock_ui_server.py` | 零修改 | — |
| Production 端 `scanBarcode.decode` 行为 | 仅在用户点新按钮时被调用，未点击零成本 | 失败映射统一到 `TOKEN_INVALID`，UI 文案与现有手输路径一致 |

---

## 8. 风险

| 风险 | 缓解 |
| --- | --- |
| `scanBarcode.decode` 在 OpenHarmony 模拟器上对应用沙箱外的 URI 鉴权失败 | 测试用 decoder override 短路；真机走真实 API |
| 用户选了一张不是 QR 的图（比如自拍） | 解码异常 → `TOKEN_INVALID` → 红字提示 |
| 用户连续选图触发并发 redeem | `busy=true` 早 gate；按钮 disabled |
| QR 指向其它 happyword 域名（例如 dev/staging） | `extractTokenFromQrPayload` 只看 `/p/<token>` 子串，与域名无关；下游 redeem 走客户端配置的 `effectiveServerBaseUrl` |
| Lesson 测试与 Scan-binding 测试串扰（同一 AppStorage 命名空间） | 物理隔离 override key；测试 `try/finally` 保证 delete；ohosTest 套件间默认重启 ability |

---

## 9. 实施切片

按 V0.5.8 的多 commit 节奏，分 4 段提交：

1. **Commit 1**: 抽 `PhotoPickerService` + 重构 `LessonImagePicker`（保契约不变），单元测试同步迁移。绿色基线。
2. **Commit 2**: `BarcodeImageDecoder` 模块 + override key + 单元测试。
3. **Commit 3**: `DeviceBindingService.startFromGalleryImage` + `ScanBindingPage` UI 按钮 + bootstrap wiring + 单元测试。
4. **Commit 4**: `tools/generate_scan_binding_qr_fixture.py` + 固件 PNG + ohosTest 用例 + 三处 docs 更新。

每段后跑 `hvigorw assembleHap` + 单元测试确保绿色，再进下一段。最后用 `scripts/run_ui_tests.sh --rebuild` 跑全套 ohosTest 验证零回归。

---

## 10. 附录：QR 固件生成脚本骨架

```python
"""Generate the ohosTest QR fixture used by ParentBindingFlowV06.

Run: uv run python tools/generate_scan_binding_qr_fixture.py
Output: entry/src/ohosTest/resources/rawfile/scan_binding_qr_fixture.png
"""
from pathlib import Path
import qrcode

PAYLOAD = "https://happyword.vercel.app/p/uitestqr01"
OUT = Path(__file__).resolve().parent.parent / (
    "entry/src/ohosTest/resources/rawfile/scan_binding_qr_fixture.png")

def main() -> None:
    qr = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_M, box_size=8, border=2)
    qr.add_data(PAYLOAD)
    qr.make(fit=True)
    img = qr.make_image(fill_color="black", back_color="white")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT)
    print(f"wrote {OUT} ({OUT.stat().st_size} bytes) encoding {PAYLOAD}")

if __name__ == "__main__":
    main()
```
