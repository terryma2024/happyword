# CodeLinter Code Analysis Tool

codelinter is a code analysis and auto-fix tool for HarmonyOS, suitable for integration into gating checks or CI/CD pipelines.

## Command Format

```bash
codelinter [options] [dir]
```

- `options`: Optional configuration parameters
- `dir`: Project root directory to check (optional, defaults to current directory)

## Command Parameters

| Parameter | Description |
|-----------|-------------|
| `--config, -c <filepath>` | Specify rule configuration file (code-linter.json5) |
| `--fix` | Check and apply auto-fixes simultaneously |
| `--format, -f <format>` | Output format: `default`/`json`/`xml`/`html` |
| `--output, -o <filepath>` | Specify output file path (suppresses console output) |
| `--version, -v` | Show version |
| `--product, -p <productName>` | Specify the active product |
| `--incremental, -i` | Check only Git incremental files (added/modified/renamed) |
| `--help, -h` | Show help |
| `--exit-on, -e <levels>` | Specify warning levels that trigger a non-zero exit code |

## Basic Usage

### Run in the Project Root Directory

```bash
# Check current project with default rules
codelinter

# Specify a rule configuration file
codelinter -c ./code-linter.json5

# Check and apply auto-fixes
codelinter -c ./code-linter.json5 --fix
```

### Run Outside the Project Directory

```bash
# Check a specific project directory
codelinter /path/to/project

# Check multiple directories or files
codelinter dir1 dir2 file1.ets

# Specify rule file and project directory
codelinter -c /path/to/code-linter.json5 /path/to/project

# Check and fix a specific project
codelinter -c ./code-linter.json5 /path/to/project --fix
```

## Output Formats

```bash
# Default text format to console
codelinter /path/to/project

# JSON format output
codelinter /path/to/project -f json

# HTML format saved to file
codelinter /path/to/project -f html -o ./report.html

# XML format saved to file
codelinter /path/to/project -f xml -o ./report.xml
```

## Incremental Checking

Check only incremental files in a Git project (only added, modified, or renamed files):

```bash
codelinter -i
codelinter --incremental
```

## Specifying a Product

When the project has multiple products, specify the active product:

```bash
codelinter -p free /path/to/project
codelinter --product default
```

## Exit Codes (--exit-on)

Used in CI/CD to control the pipeline based on warning levels. Warning levels: `error`, `warn`, `suggestion`

Exit code calculation (3-bit binary number, from high to low representing error, warn, suggestion):

| Configuration | Check Results Include | Binary | Exit Code |
|---------------|---------------------|--------|-----------|
| `--exit-on error` | error, warn, suggestion | 100 | 4 |
| `--exit-on error` | warn, suggestion | 000 | 0 |
| `--exit-on error,warn` | error, warn | 110 | 6 |
| `--exit-on error,warn,suggestion` | error | 100 | 4 |
| `--exit-on error,warn,suggestion` | error, warn, suggestion | 111 | 7 |

```bash
# Non-zero exit code only for error level
codelinter --exit-on error

# Non-zero exit code for error and warn levels
codelinter --exit-on error,warn

# Non-zero exit code for all levels
codelinter --exit-on error,warn,suggestion
```

## CI/CD Integration Examples

```bash
# Full CI check pipeline
codelinter -c ./code-linter.json5 \
  -f json \
  -o ./codelinter-report.json \
  --exit-on error,warn

# Incremental check (changed files only)
codelinter -i -c ./code-linter.json5 --exit-on error

# Check with auto-fix, generate HTML report
codelinter -c ./code-linter.json5 \
  --fix \
  -f html \
  -o ./codelinter-report.html
```

## Rule Configuration File (code-linter.json5)

The default rule list can be viewed in the generated `code-linter.json5` file, as indicated by the console output after a check completes.

Example configuration:

```json5
{
  "files": [
    "**/*.ets",
    "**/*.ts"
  ],
  "ignore": [
    "**/node_modules/**",
    "**/oh_modules/**",
    "**/build/**"
  ],
  "ruleSet": ["plugin:@ohos/recommended"],
  "rules": {
    "@ohos/no-any": "error",
    "@ohos/no-console": "warn"
  }
}
```
