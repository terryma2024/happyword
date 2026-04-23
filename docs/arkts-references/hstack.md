# Stack Trace Analysis Tool (hstack)

hstack is a tool for resolving obfuscated crash stack traces from Release builds back to their original source code locations. It supports Windows, Mac, and Linux.

## Command Format

```bash
hstack [options]
```

## Command Parameters

| Parameter | Description |
|-----------|-------------|
| `-i, --input` | Specify the crash file archive directory |
| `-c, --crash` | Specify a single crash stack trace |
| `-o, --output` | Specify the output directory for parsed results (output file when using `-c`) |
| `-s, --sourcemapDir` | Specify the sourcemap file archive directory |
| `--so, --soDir` | Specify the shared object (.so) file archive directory |
| `-n, --nameObfuscation` | Specify the nameCache file archive directory |
| `-v, --version` | Show version |
| `-h, --help` | Show help |

## Parameter Constraints

- Crash file directory (`-i`) and crash stack trace (`-c`) **must provide exactly one**
- Sourcemap (`-s`) and shared object (`--so`) directories **must provide at least one**
- To restore obfuscated method names, **both** sourcemap and nameCache files must be provided
- Path parameters do not support special characters: `` `~!@#$^&*=|{};,\s\[\]<>? ``

## Environment Setup

1. Add the Command Line Tools `bin` directory to the PATH environment variable
2. Add Node.js to the environment variables
3. To parse C++ exceptions, add the SDK's `native\llvm\bin` directory to the `ADDR2LINE_PATH` environment variable

## Usage Examples

### Parse Crash File Directory

```bash
# Full parse command
hstack -i crashDir -o outputDir -s sourcemapDir --so soDir -n nameCacheDir

# Parse using sourcemap only (ArkTS)
hstack -i crashDir -o outputDir -s sourcemapDir

# Parse using .so files only (C++)
hstack -i crashDir -o outputDir --so soDir

# Include method name restoration
hstack -i crashDir -o outputDir -s sourcemapDir -n nameCacheDir
```

### Parse a Single Stack Trace

```bash
# Output to console
hstack -c "at har (entry|har|1.0.0|src/main/ets/pages/Index.ts:58:58)" -s sourcemapDir

# Output to file
hstack -c "at har (entry|har|1.0.0|src/main/ets/pages/Index.ts:58:58)" -s sourcemapDir -o result.txt
```

## Output

- Parsed results are written to the directory specified by `-o`, with filenames prefixed by `_` followed by the original crash filename
- When `-o` is not specified:
  - With `-i` input: output to the crashDir directory
  - With `-c` input: output directly to console

## File Sources

### Sourcemap Files

Sourcemap files from build artifacts, containing:
- Path information mapping
- Line/column number mapping (mappings field)
- package-info information

### NameCache Files

NameCache files from build artifacts, containing:
- `IdentifierCache`: Identifier obfuscation mapping
- `MemberMethodCache`: Member method obfuscation mapping, format: `"sourceMethodName:startLine:endLine": "obfuscatedMethodName"`

### Shared Object (.so) Files

When building Release applications, .so files do not include symbol tables by default. To generate .so files with symbol tables, configure in the module's `build-profile.json5`:

```json5
{
  "buildOption": {
    "externalNativeOptions": {
      "arguments": "-DCMAKE_BUILD_TYPE=RelWithDebInfo"
    }
  }
}
```

## Stack Trace Resolution Principles

### Crash Stack Format

```
at har (entry|har|1.0.0|src/main/ets/components/mainpage/MainPage.js:58:58)
at i (entry|entry|1.0.0|src/main/ets/pages/Index.ts:71:71)
```

Path format: `referrerPackageName|referredPackageName|version|sourceRelativePath`

### Resolution Steps

1. **Find the sourcemap based on path information**
   - From the path `entry|har|1.0.0|src/main/ets/...`, look up the corresponding field in the entry module's sourcemap

2. **Restore path and line/column numbers using sourcemap**
   - Parse using the `sources` and `mappings` fields
   - If `package-info` is included, perform a secondary parse for more accurate source locations

3. **Restore method names using nameCache**
   - Find all entries matching the obfuscated method name
   - Match the correct source method name based on the restored line number range

### Resolution Example

Original stack trace:
```
at i (entry|entry|1.0.0|src/main/ets/pages/Index.ts:71:71)
```

After resolution:
```
at callHarFunction (entry/src/main/ets/pages/Index.ets:25:3)
```

## CI/CD Integration

```bash
# Automated parsing script example
hstack \
  -i ./crash-logs \
  -o ./parsed-logs \
  -s ./build/sourcemap \
  --so ./build/libs \
  -n ./build/nameCache
```

## FAQ

1. **Method names not restored**: Ensure both `-s` and `-n` parameters are provided
2. **C++ stack traces not parsed**: Check the `ADDR2LINE_PATH` environment variable configuration
3. **No symbol table in .so files**: Configure the `RelWithDebInfo` build option
