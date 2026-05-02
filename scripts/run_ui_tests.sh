#!/usr/bin/env bash
#
# Orchestrate the HarmonyOS ohosTest UI automation suite against a
# locally-hosted FastAPI mock so the device never has to touch
# happyword.vercel.app during automation.
#
# Pipeline:
#   1. Sanity-check that an emulator / device is reachable via hdc.
#   2. Wake and unlock the pinned USB device when it is on the lock screen.
#   3. Boot server/mock_ui_server.py on host port 8123.
#   4. Reverse-forward the device's 127.0.0.1:8123 to the host's
#      127.0.0.1:8123 via `hdc rport`.
#   5. (Optionally) build + reinstall the test HAP if --rebuild is set.
#   6. Run `hdc shell aa test ...` (the standard ohosTest entry).
#   7. Always tear down: kill the mock server, drop the rport mapping.
#
# Usage:
#   scripts/run_ui_tests.sh                  # run with already-built HAPs
#   scripts/run_ui_tests.sh --rebuild        # rebuild + reinstall first
#   scripts/run_ui_tests.sh --suite ParentAdminFlowV058  # run one suite
#
# Production (release) builds never see the override URL — only this
# script writes one (via the test harness in List.test.ets, which sets
# AppStorage `serverBaseUrlOverride` in beforeAll). When run by hand
# from DevEco "Run" without this script, ohosTest will still try to
# reach 127.0.0.1:8123 and fail fast — that is intentional, the suite
# is not designed to fall back to prod.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOCK_PORT="${MOCK_PORT:-8123}"
MOCK_HOST="127.0.0.1"
MOCK_LOG="${REPO_ROOT}/build-tmp/mock_ui_server.log"
MOCK_PID_FILE="${REPO_ROOT}/build-tmp/mock_ui_server.pid"
SUITE_FILTER=""
DO_REBUILD=0
# When more than one device is registered with hdc (e.g. the OpenHarmony
# emulator over TCP plus a USB phone), every hdc subcommand fails with
# "ExecuteCommand need connect-key?". Set HDC_TARGET in the environment
# (or rely on auto-detection in step 1) so we can pass `-t <key>`
# consistently.
HDC_TARGET="${HDC_TARGET:-}"
UNLOCK_DEVICE_TARGET="5FFBB25926205346"
UNLOCK_DEVICE_PASSWORD="${UI_TEST_UNLOCK_PASSWORD:-666888}"
UNLOCK_SWIPE_FROM_X="${UI_TEST_UNLOCK_SWIPE_FROM_X:-540}"
UNLOCK_SWIPE_FROM_Y="${UI_TEST_UNLOCK_SWIPE_FROM_Y:-1900}"
UNLOCK_SWIPE_TO_X="${UI_TEST_UNLOCK_SWIPE_TO_X:-540}"
UNLOCK_SWIPE_TO_Y="${UI_TEST_UNLOCK_SWIPE_TO_Y:-320}"
UNLOCK_SWIPE_VELOCITY="${UI_TEST_UNLOCK_SWIPE_VELOCITY:-1200}"

# Wrapper that injects `-t <key>` whenever HDC_TARGET is non-empty.
# Defined up here so the cleanup trap can use it too.
hdc_t() {
  if [[ -n "${HDC_TARGET}" ]]; then
    hdc -t "${HDC_TARGET}" "$@"
  else
    hdc "$@"
  fi
}

target_list_contains() {
  local target="$1"
  printf '%s\n' "${TARGETS}" | grep -Fxq "${target}"
}

should_unlock_target_device() {
  [[ "${HDC_TARGET}" == "${UNLOCK_DEVICE_TARGET}" ]]
}

device_layout_text() {
  hdc_t shell uitest dumpLayout 2>/dev/null | tr -d '\r' || true
}

layout_looks_locked() {
  local layout="$1"
  [[ "${layout}" =~ (锁屏|锁定|解锁|输入密码|密码|PIN|pin|Password|password) ]]
}

unlock_target_device_if_needed() {
  if ! should_unlock_target_device; then
    return 0
  fi

  echo "[run_ui_tests] preparing USB device ${UNLOCK_DEVICE_TARGET}: wake screen and prevent sleep"
  hdc_t shell power-shell wakeup >/dev/null 2>&1 || \
    hdc_t shell uitest uiInput keyEvent Power >/dev/null 2>&1 || true
  hdc_t shell power-shell setmode 602 >/dev/null 2>&1 || true
  sleep 0.8

  hdc_t shell uitest uiInput swipe \
    "${UNLOCK_SWIPE_FROM_X}" "${UNLOCK_SWIPE_FROM_Y}" \
    "${UNLOCK_SWIPE_TO_X}" "${UNLOCK_SWIPE_TO_Y}" \
    "${UNLOCK_SWIPE_VELOCITY}" >/dev/null 2>&1 || true
  sleep 0.8

  local layout
  layout="$(device_layout_text)"
  if layout_looks_locked "${layout}"; then
    echo "[run_ui_tests] lock screen detected on ${UNLOCK_DEVICE_TARGET}; unlocking before UI tests"
    hdc_t shell uitest uiInput text "${UNLOCK_DEVICE_PASSWORD}" >/dev/null 2>&1 || true
    hdc_t shell uitest uiInput keyEvent Enter >/dev/null 2>&1 || true
    sleep 1
  fi
}

mkdir -p "$(dirname "${MOCK_LOG}")"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rebuild)
      DO_REBUILD=1
      shift
      ;;
    --suite)
      SUITE_FILTER="$2"
      shift 2
      ;;
    --port)
      MOCK_PORT="$2"
      shift 2
      ;;
    -h|--help)
      grep -E '^# ' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "[run_ui_tests] unknown flag: $1" >&2
      exit 2
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Cleanup hook (runs on success and failure)
# ---------------------------------------------------------------------------

cleanup() {
  local rc=$?
  set +e
  if [[ -f "${MOCK_PID_FILE}" ]]; then
    local pid
    pid="$(cat "${MOCK_PID_FILE}")"
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
      kill "${pid}" 2>/dev/null || true
      # Give uvicorn a beat to release the port; force-kill if it lingers.
      sleep 1
      kill -9 "${pid}" 2>/dev/null || true
    fi
    rm -f "${MOCK_PID_FILE}"
  fi
  # Drop ALL rport mappings we created. `hdc fport ls` prints both
  # forward and reverse tasks in one list; we filter for our port and
  # strip out the "tcp:8123 tcp:8123" tail which `hdc fport rm` wants.
  if command -v hdc >/dev/null 2>&1; then
    hdc_t fport ls 2>/dev/null \
      | awk -v p=":${MOCK_PORT}" '$0 ~ p {print $0}' \
      | while read -r line; do
          taskstr="$(echo "${line}" | sed -nE 's/.*(tcp:[0-9]+ tcp:[0-9]+).*/\1/p')"
          if [[ -n "${taskstr}" ]]; then
            hdc_t fport rm "${taskstr}" >/dev/null 2>&1 || true
          fi
        done
  fi
  return "${rc}"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# 1. hdc reachability
# ---------------------------------------------------------------------------

if ! command -v hdc >/dev/null 2>&1; then
  echo "[run_ui_tests] hdc not on PATH — load DevEco's command-line tools." >&2
  exit 1
fi

# `hdc list targets` prints "[Empty]" when no device is connected.
TARGETS="$(hdc list targets 2>&1 | tr -d '\r' | sed '/^[[:space:]]*$/d' || true)"
if [[ -z "${TARGETS}" || "${TARGETS}" == *"[Empty]"* ]]; then
  echo "[run_ui_tests] no hdc target. Start the emulator (or plug a device) and retry." >&2
  exit 1
fi
echo "[run_ui_tests] hdc target(s): ${TARGETS}"

# If multiple targets are present and HDC_TARGET wasn't pinned by the
# caller, prefer the known USB device for these UI tests; otherwise keep
# the historical emulator preference.
TARGET_COUNT="$(printf '%s\n' "${TARGETS}" | wc -l | tr -d ' ')"
if [[ -z "${HDC_TARGET}" ]] && target_list_contains "${UNLOCK_DEVICE_TARGET}"; then
  HDC_TARGET="${UNLOCK_DEVICE_TARGET}"
  echo "[run_ui_tests] auto-selecting USB target ${HDC_TARGET}"
elif [[ -z "${HDC_TARGET}" && "${TARGET_COUNT}" -gt 1 ]]; then
  TCP_TARGET="$(printf '%s\n' "${TARGETS}" | grep -E '^127\.0\.0\.1:' | head -n1 || true)"
  if [[ -n "${TCP_TARGET}" ]]; then
    HDC_TARGET="${TCP_TARGET}"
    echo "[run_ui_tests] multiple targets visible, auto-selecting ${HDC_TARGET}"
  fi
fi

unlock_target_device_if_needed

# ---------------------------------------------------------------------------
# 3. Boot mock server
# ---------------------------------------------------------------------------

# If the port is busy, fail loudly — we never want to "fall through" to a
# stale mock from a previous run that might have inconsistent state.
if lsof -i ":${MOCK_PORT}" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "[run_ui_tests] port ${MOCK_PORT} is already in use; free it (lsof -i :${MOCK_PORT}) and retry." >&2
  exit 1
fi

echo "[run_ui_tests] starting mock UI server on ${MOCK_HOST}:${MOCK_PORT}"
(
  cd "${REPO_ROOT}/server"
  exec uv run python mock_ui_server.py --host "${MOCK_HOST}" --port "${MOCK_PORT}"
) >"${MOCK_LOG}" 2>&1 &
echo $! >"${MOCK_PID_FILE}"

# Wait up to ~10s for the health endpoint to come up.
for _ in $(seq 1 50); do
  if curl -fsS "http://${MOCK_HOST}:${MOCK_PORT}/api/v1/health" >/dev/null 2>&1; then
    echo "[run_ui_tests] mock UI server is healthy"
    break
  fi
  sleep 0.2
done

if ! curl -fsS "http://${MOCK_HOST}:${MOCK_PORT}/api/v1/health" >/dev/null 2>&1; then
  echo "[run_ui_tests] mock server failed to come up — log tail:" >&2
  tail -n 50 "${MOCK_LOG}" >&2 || true
  exit 1
fi

# ---------------------------------------------------------------------------
# 3. Reverse-forward device:127.0.0.1:8123 -> host:127.0.0.1:8123
# ---------------------------------------------------------------------------

# `rport` syntax: `hdc rport <remotenode> <localnode>` — connection
# initiated on the device targets the host. After this, the device
# resolves http://127.0.0.1:8123 to the mock running on the developer's
# Mac.
echo "[run_ui_tests] hdc rport tcp:${MOCK_PORT} tcp:${MOCK_PORT}"
hdc_t rport "tcp:${MOCK_PORT}" "tcp:${MOCK_PORT}"

# Note on lesson-import fixture: HarmonyOS NEXT's selinux blocks the
# bundle UID from reading every shell-writable path on disk
# (`/data/local/tmp/*` -> data_local_tmp:s0; the app's own debug
# sandbox -> debug_hap_data_file:s0 from sh:s0 is also denied), so we
# CANNOT use `hdc file send` to drop the fixture image where the
# gallery-upload UI test can fs.open it. The fixture is bundled into
# the ohosTest HAP at
# `entry/src/ohosTest/resources/rawfile/lesson_import_fixture.jpg`
# and `tapPickGalleryUploadsAndShowsImported` copies it from the
# rawfile resource into the app sandbox at runtime via
# `Context.resourceManager.getRawFileContent` + `fs.write`. See
# `ParentAdminFlow.ui.test.ets::ensureLessonImportFixtureOnDevice`.

# ---------------------------------------------------------------------------
# 4. (optional) rebuild + reinstall HAPs
# ---------------------------------------------------------------------------

if [[ "${DO_REBUILD}" -eq 1 ]]; then
  echo "[run_ui_tests] rebuilding HAPs"
  (cd "${REPO_ROOT}" && hvigorw assembleHap --no-daemon)
  (cd "${REPO_ROOT}" && hvigorw assembleOhosTest --no-daemon || \
    hvigorw --mode module -p module=entry@ohosTest assembleHap --no-daemon)

  HAP_DEFAULT="$(find "${REPO_ROOT}/entry/build" -name 'entry-default-signed.hap' | head -1 || true)"
  HAP_TEST="$(find "${REPO_ROOT}/entry/build" -name 'entry-ohosTest-signed.hap' | head -1 || true)"
  if [[ -z "${HAP_DEFAULT}" || -z "${HAP_TEST}" ]]; then
    echo "[run_ui_tests] expected HAPs not found under entry/build" >&2
    exit 1
  fi
  echo "[run_ui_tests] installing ${HAP_DEFAULT}"
  hdc_t install -r "${HAP_DEFAULT}"
  echo "[run_ui_tests] installing ${HAP_TEST}"
  hdc_t install -r "${HAP_TEST}"
fi

# ---------------------------------------------------------------------------
# 5. Run ohosTest
# ---------------------------------------------------------------------------

# Standard ohosTest entry point for this project — see .cursor/dev-commands.md
# section 4. The "-s class <suite>" filter is appended only when --suite
# is supplied; without it, the runner executes everything registered in
# entry/src/ohosTest/ets/test/List.test.ets.
# Per-test timeout is intentionally larger than dev-commands.md's
# 30000ms reference: parentAdminInteractionsStayStable in
# entry/src/ohosTest/ets/test/ParentAdminFlow.ui.test.ets walks
# launchApp → returnToHome → ensureParentPin → navigateToParentAdmin →
# refresh → pending probe → scroll → typeIntoAdmin → exit, which can
# take 35-45s in cold start, even though every individual step is fast
# (the test is wide, not slow). 60000ms buys a safe margin without
# masking real hangs.
TEST_CMD=(hdc)
if [[ -n "${HDC_TARGET}" ]]; then
  TEST_CMD+=(-t "${HDC_TARGET}")
fi
TEST_CMD+=(shell aa test
  -b com.terryma.wordmagicgame
  -m entry_test
  -s unittest OpenHarmonyTestRunner
  -s timeout 60000
  -w 1800
)
if [[ -n "${SUITE_FILTER}" ]]; then
  TEST_CMD+=(-s class "${SUITE_FILTER}")
fi

echo "[run_ui_tests] ${TEST_CMD[*]}"
"${TEST_CMD[@]}"

echo "[run_ui_tests] done."
