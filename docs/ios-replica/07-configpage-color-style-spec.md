# iOS ConfigPage Color & Style Spec

> Status: Current implementation guardrail, captured 2026-06-02.
> Applies to: `ios/WordMagicGame/Features/Settings/ConfigView.swift`.
> Verification owner: `ios/WordMagicGameTests/AppThemeParityTests.swift`.

This document records the current iOS ConfigPage color and control-style rules.
When changing `ConfigView`, follow this spec first, then update the tests only
when the product owner intentionally changes the visual contract.

## Source Tokens

### AppTheme tokens

Defined in `ios/WordMagicGame/App/AppCoordinator.swift`:

| Token | Swift value | Use on ConfigPage |
| --- | --- | --- |
| `AppTheme.blue` | `Color(red: 0.08, green: 0.35, blue: 0.94)` | Numeric `+` / `-` circular controls. |
| `AppTheme.paleBlue` | `Color(red: 0.86, green: 0.93, blue: 0.98)` | Unselected timer chips and the `我的词包` entry background. |
| `AppTheme.page` | `Color(red: 0.98, green: 0.99, blue: 1.00)` | Config page background. |
| `AppTheme.pageHorizontalPadding` | `24` | Page horizontal gutter. |

### Config action button tokens

Defined by `ConfigActionButtonStyle` in `ConfigView.swift`:

| Token | Swift value |
| --- | --- |
| background | `Color(red: 0.88, green: 0.95, blue: 0.99)` |
| foreground | `Color(red: 0.01, green: 0.41, blue: 0.63)` |
| border | `Color(red: 0.05, green: 0.65, blue: 0.91)` |
| width | `220` |
| height | `40` |
| corner radius | `8` |
| border width | `2` |
| font | `.system(size: 15, weight: .semibold, design: .rounded)` |
| text behavior | `.lineLimit(1)` + `.minimumScaleFactor(0.78)` |

Use the `.configActionButtonStyle()` helper instead of duplicating these
modifiers on ConfigPage action buttons.

## Layout Rules

Defined by `ConfigLayoutRules`:

| Token | Value | Use |
| --- | --- | --- |
| `labelWidth` | `120` | Left label column width. |
| `controlGap` | `12` | Standard label-to-control gap. |
| `controlColumnWidth` | `220` | Main control column width. |
| `timerOptionsPerRow` | `3` | Timer chip row grouping. |
| `settingGroupSpacing` | `22` | Vertical spacing between setting rows/groups. |
| `settingOptionSpacing` | `8` | Vertical spacing inside option groups. |
| `settingSwitchLabelWidth` | `132` | Switch row label width. |

Config rows should stay centered with `maxWidth: 560` unless a specific
subscreen already owns a different layout rule.

## Control Style Rules

### 1. Unified action buttons

These ConfigPage buttons must use `.configActionButtonStyle()` and must match
the `投诉与举报` entry colors:

| Accessibility ID | User-facing role |
| --- | --- |
| `ConfigReportChannelButton` | `投诉与举报入口` |
| `ConfigParentPinButton` | Parent PIN setup/edit button. |
| `ConfigBoundDeviceInfoButton` | Bound child learning-profile button. |
| `ConfigBindParentButton` | Bind parent account button. |
| `ConfigCloudSyncButton` | Manual learning-record sync button. |
| `ConfigParentAdminButton` | Parent admin entry button. |

Do not give any of these buttons a separate yellow, orange, brown, or custom
semantic color unless the whole action-button system is intentionally redesigned.

### 2. Numeric stepper controls

The `+` and `-` controls are not action buttons. Keep the original circular
style:

| Property | Required style |
| --- | --- |
| Font | `.system(size: 24, weight: .bold)` |
| Foreground | `.white` |
| Size | `48 x 48` |
| Shape | `Circle()` |
| Background | `AppTheme.blue` |

Do not apply `.configActionButtonStyle()` to `roundControl`.

### 3. Timer chips

Countdown preset and custom-timer buttons are chips, not action buttons. Keep
the original selected/unselected chip palette:

| State | Background | Foreground | Shape |
| --- | --- | --- | --- |
| Selected preset | `Color(red: 0.71, green: 0.33, blue: 0.04)` | `.white` | `Capsule()` |
| Selected custom timer | `Color(red: 0.71, green: 0.33, blue: 0.04)` | `.white` | `Capsule()` |
| Unselected | `AppTheme.paleBlue` | `Color(red: 0.11, green: 0.3, blue: 0.85)` | `Capsule()` |

Timer-chip typography stays `.system(size: 16, weight: .bold, design: .rounded)`,
with horizontal padding `12`, fixed height `40`, `.lineLimit(1)`, and
`.minimumScaleFactor(0.75)`.

Do not use action-button colors for timer chips.

### 4. Pack manager entry

The `我的词包` entry is a status-and-management control, not a unified action
button. Keep its original pale-blue card-like button:

| Element | Required style |
| --- | --- |
| Background | `AppTheme.paleBlue` in `RoundedRectangle(cornerRadius: 8)` |
| Frame | `width: 220`, `height: 40` |
| Horizontal padding | `12` |
| Status text | `Color(red: 0.12, green: 0.16, blue: 0.23)` |
| `管理 ›` text | `Color(red: 0.27, green: 0.48, blue: 0.62)` |
| Font | `.system(size: 15, weight: .semibold, design: .rounded)` |

Do not apply `.configActionButtonStyle()` to `ConfigPackManagerEntry`.

### 5. Switches

Switch rows keep their existing ConfigPage switch pattern:

- Label column uses ConfigPage layout rules.
- Toggle controls remain native SwiftUI toggles unless a platform-wide switch
  redesign is approved.
- Question-type rows remain left-aligned according to
  `ConfigLayoutRules.questionTypesLeftAligned`.

## Change Guardrails

When editing `ConfigView`:

1. Use `ConfigActionButtonStyle` only for the unified action-button group.
2. Keep timer chips, numeric steppers, and `我的词包` visually separate.
3. If adding a new ConfigPage button, decide whether it is:
   - an action button: use `.configActionButtonStyle()`;
   - a chip: follow the timer chip pattern or add a new named chip pattern;
   - a status/control entry: document its local style and add a parity test.
4. Avoid introducing one-off inline colors for action buttons. Add a named token
   or helper first.
5. Do not update the style tests to match a regression. Update tests only after
   this spec is intentionally changed.

## Test Coverage

`AppThemeParityTests` currently protects these contracts:

| Test | Protects |
| --- | --- |
| `testConfigPageActionButtonsUseReportChannelColors` | Action buttons use `.configActionButtonStyle()`. |
| `testConfigPagePackManagerButtonKeepsOriginalPaleBlueStyle` | `我的词包` keeps its original pale-blue style. |
| `testConfigPageTimerButtonsKeepOriginalSelectedAndPaleBlueStyles` | Timer chips keep selected brown / unselected pale-blue styling. |
| `testConfigPageStepperButtonsKeepOriginalBlueCircleStyle` | `+` / `-` controls keep the original blue-circle style. |

Run the focused check after ConfigPage style edits:

```sh
xcodebuild test \
  -project ios/WordMagicGame.xcodeproj \
  -scheme WordMagicGame \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:WordMagicGameTests/AppThemeParityTests
```
