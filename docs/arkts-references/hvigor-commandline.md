# Hvigor Command-Line Build Tool (hvigorw)

hvigorw is the Hvigor wrapper tool that supports automatic installation of the Hvigor build tool and its plugin dependencies, as well as executing Hvigor build commands.

## Command Format

```bash
hvigorw [taskNames...] <options>
```

## Build Tasks

| Task | Description |
|------|-------------|
| `clean` | Clean build artifacts in the build directory |
| `assembleHap` | Build HAP application |
| `assembleApp` | Build APP application |
| `assembleHsp` | Build HSP package |
| `assembleHar` | Build HAR package |
| `collectCoverage` | Generate coverage statistics report from instrumented data |

## Common Build Parameters

| Parameter | Description |
|-----------|-------------|
| `-p buildMode={debug\|release}` | Specify build mode. Default: debug for Hap/Hsp/Har, release for App |
| `-p debuggable=true/false` | Override the debuggable setting in buildOption |
| `-p product={ProductName}` | Specify product for compilation, defaults to default |
| `-p module={ModuleName}@{TargetName}` | Specify module and target for compilation (requires `--mode module`) |
| `-p ohos-test-coverage={true\|false}` | Enable test framework code coverage instrumentation |
| `-p parameterFile=param.json` | Set parameter configuration file for oh-package.json5 |

## Build Examples

```bash
# Clean build artifacts
hvigorw clean

# Build HAP in debug mode
hvigorw assembleHap -p buildMode=debug

# Build APP in release mode
hvigorw assembleApp -p buildMode=release

# Build a specific product
hvigorw assembleHap -p product=free

# Build a specific module
hvigorw assembleHap -p module=entry@default --mode module

# Build multiple modules
hvigorw assembleHar -p module=library1@default,library2@default --mode module
```

## Test Commands

### Instrument Test (On-Device Test)

```bash
hvigorw onDeviceTest -p module={moduleName} -p coverage={true|false} -p scope={suiteName}#{methodName}
```

- `module`: Module to test; omit to test all modules
- `coverage`: Whether to generate coverage report, defaults to true
- `scope`: Test scope, format `{suiteName}#{methodName}` or `{suiteName}`
- `ohos-debug-asan`: Whether to enable ASan detection, defaults to false (5.19.0+)

**Output paths:**
- Coverage report: `<module-path>/.test/default/outputs/ohosTest/reports`
- Test results: `<project>/<module>/.test/default/intermediates/ohosTest/coverage_data/test_result.txt`

### Local Test

```bash
hvigorw test -p module={moduleName} -p coverage={true|false} -p scope={suiteName}#{methodName}
```

**Output paths:**
- Coverage report: `<module-path>/.test/default/outputs/test/reports`
- Test results: `<project>/<module>/.test/default/intermediates/test/coverage_data/test_result.txt`

## Log Levels

| Parameter | Description |
|-----------|-------------|
| `-e, --error` | Set log level to error |
| `-w, --warn` | Set log level to warn |
| `-i, --info` | Set log level to info |
| `-d, --debug` | Set log level to debug |
| `--stacktrace` | Enable exception stack trace printing |

## Build Analyzer

| Parameter | Description |
|-----------|-------------|
| `--analyze=normal` | Normal mode analysis |
| `--analyze=advanced` | Advanced mode with detailed task timing data |
| `--analyze=ultrafine` | Ultra-fine mode with detailed ArkTS compilation instrumentation (6.0.0+) |
| `--analyze=false` | Disable build analysis |
| `--config properties.hvigor.analyzeHtml=true` | Generate HTML visual report to `.hvigor/report` |

## Daemon

| Parameter | Description |
|-----------|-------------|
| `--daemon` | Enable daemon process |
| `--no-daemon` | Disable daemon process (recommended for CLI mode) |
| `--stop-daemon` | Stop the daemon for the current project |
| `--stop-daemon-all` | Stop all project daemons |
| `--status-daemon` | Query all Hvigor daemon process information |
| `--max-old-space-size=12345` | Set old generation memory size (MB) |
| `--max-semi-space-size=32` | Set new generation semi-space size (MB, 5.18.4+) |

## Performance and Memory Optimization

| Parameter | Description |
|-----------|-------------|
| `--parallel` / `--no-parallel` | Enable/disable parallel builds (enabled by default) |
| `--incremental` / `--no-incremental` | Enable/disable incremental builds (enabled by default) |
| `--optimization-strategy=performance` | Performance-first mode, faster builds but higher memory usage (5.19.2+) |
| `--optimization-strategy=memory` | Memory-first mode (default) (5.19.2+) |

## Utility Commands

| Task | Description |
|------|-------------|
| `tasks` | Print task information for all project modules |
| `taskTree` | Print task dependency graph for all project modules |
| `prune` | Clean caches unused for 30 days and remove unreferenced pnpm packages |
| `buildInfo` | Print build-profile.json5 configuration information (5.18.4+) |

### buildInfo Extended Parameters

```bash
# Print project-level configuration
hvigorw buildInfo

# Print configuration for a specific module
hvigorw buildInfo -p module=entry

# Include buildOption configuration
hvigorw buildInfo -p buildOption

# JSON format output
hvigorw buildInfo -p json
```

## Other Parameters

| Parameter | Description |
|-----------|-------------|
| `-h, --help` | Print help information |
| `-v, --version` | Print version information |
| `-s, --sync` | Sync project information to `./hvigor/outputs/sync/output.json` |
| `-m, --mode` | Specify execution directory level (e.g., `-m project`) |
| `--type-check` | Enable type checking for hvigorfile.ts |
| `--watch` | Watch mode for preview and hot reload |
| `--node-home <string>` | Specify Node.js path |
| `--config, -c` | Specify hvigor-config.json5 parameters |

## CI/CD Common Command Combinations

```bash
# Full release build pipeline
hvigorw clean && hvigorw assembleApp -p buildMode=release --no-daemon

# Debug build with build analysis
hvigorw assembleHap -p buildMode=debug --analyze=advanced --no-daemon

# Run tests and generate coverage report
hvigorw onDeviceTest -p coverage=true --no-daemon

# Build in memory-constrained environment
hvigorw assembleHap --optimization-strategy=memory --no-daemon

# Clean caches
hvigorw prune
hvigorw --stop-daemon-all
```
