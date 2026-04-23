# ArkGuard Code Obfuscation Guide

ArkGuard is the officially recommended code obfuscation tool for HarmonyOS, designed to enhance application security and prevent reverse engineering.

## Requirements

- **DevEco Studio**: Version 5.0.3.600 or above
- **Project Model**: Stage model only
- **Effective Mode**: Only active in Release mode

## Enabling Obfuscation

Configure in the module's `build-profile.json5`:

```json
{
  "arkOptions": {
    "obfuscation": {
      "ruleOptions": {
        "enable": true,
        "files": ["./obfuscation-rules.txt"]
      },
      "consumerFiles": ["./consumer-rules.txt"]
    }
  }
}
```

## Obfuscation Rules Configuration

Create `obfuscation-rules.txt` in the project root directory:

```text
# Enable property obfuscation
-enable-property-obfuscation

# Enable top-level scope name obfuscation
-enable-toplevel-obfuscation

# Enable filename obfuscation
-enable-filename-obfuscation

# Enable import/export name obfuscation
-enable-export-obfuscation
```

## Whitelist Configuration

Certain names must not be obfuscated (e.g., dynamic property names, API fields, database fields):

```text
# Keep property names
-keep-property-name apiKey
-keep-property-name userId
-keep-property-name responseData

# Keep global names
-keep-global-name AppConfig

# Keep file names
-keep-file-name MainPage
-keep-file-name LoginPage
```

## Configuration Files

| Config File | Purpose | Editable | Scope |
|-------------|---------|:--------:|-------|
| `obfuscation-rules.txt` | Obfuscation rules applied when building this module | ✓ | Current module |
| `consumer-rules.txt` | Obfuscation rules applied when this module is used as a dependency (recommended: keep rules only) | ✓ | Modules depending on this module |
| `obfuscation.txt` | HAR/HSP build artifact, auto-generated | ✗ | Dependent modules |

## Common Obfuscation Options

| Option | Description |
|--------|-------------|
| `-enable-property-obfuscation` | Obfuscate object property names |
| `-enable-toplevel-obfuscation` | Obfuscate top-level scope variable and function names |
| `-enable-filename-obfuscation` | Obfuscate file names |
| `-enable-export-obfuscation` | Obfuscate import/export names |
| `-disable-obfuscation` | Temporarily disable obfuscation (for debugging) |

## Whitelist Options

| Option | Description |
|--------|-------------|
| `-keep-property-name <name>` | Preserve specified property name from obfuscation |
| `-keep-global-name <name>` | Preserve specified global name from obfuscation |
| `-keep-file-name <name>` | Preserve specified file name from obfuscation |

## Troubleshooting

### Diagnostic Steps

1. **Confirm obfuscation is the cause**: Temporarily add `-disable-obfuscation` and check if the issue disappears
2. **Locate the problematic field**: Identify the obfuscated field from crash logs
3. **Add to whitelist**: Add the problematic field to the `-keep-property-name` whitelist

### Common Scenarios Requiring Whitelisting

- **Network requests**: Request parameter field names, response data field names
- **Database operations**: Table field names
- **System APIs**: System callback parameters
- **Third-party library interfaces**: Field names required by third-party libraries

### Example: Preserving Network Request Fields

```text
# API request/response fields
-keep-property-name code
-keep-property-name message
-keep-property-name data
-keep-property-name token
-keep-property-name userId
```

## Verifying Obfuscation Results

1. Switch to **Release** mode and build
2. Inspect the build artifacts
3. Use decompilation tools to verify that class/method/property names are obfuscated
4. Test that the application functions correctly

## References

- [Huawei Official Documentation - ArkGuard](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-arkguard)
