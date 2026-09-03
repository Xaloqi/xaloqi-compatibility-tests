#!/usr/bin/env bash
# run_compat.sh — Xaloqi Compatibility Test Runner
#
# Builds each ECU simulator target, launches it, runs the same TestLab campaign
# against it, and compares results between targets. Exits 0 only when all four
# campaigns pass and cross-target diffs are clean.
#
# Prerequisites:
#   pip install xaloqi-tester                  # free, public -- --virtual only
#   ..or the TestLab Pro package for the full build matrix (all four targets
#   use a real transport -- socketcan or DoIP -- both Pro-gated; see README
#   "Core vs. Pro")
#   west (Zephyr SDK) — for Zephyr targets
#   arm-none-eabi-gcc / qemu-system-arm       — for FreeRTOS / QEMU targets
#   sudo modprobe vcan && sudo ip link add dev vcan0 type vcan && sudo ip link set up vcan0
#
# Quick start (--virtual only, no builds, no hardware):
#   ./run_compat.sh --virtual
#
# Full run (builds all four ECUs):
#   EDS_ROOT=../EDS FREERTOS_DIR=/opt/freertos-kernel ./run_compat.sh
#
# MIT License — https://github.com/Xaloqi/xaloqi-compatibility-tests

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EDS_ROOT="${EDS_ROOT:-$(realpath "${SCRIPT_DIR}/../EDS" 2>/dev/null || echo "")}"
FREERTOS_DIR="${FREERTOS_DIR:-/opt/freertos-kernel}"
CAMPAIGN="${SCRIPT_DIR}/campaigns/core_validation.yaml"
JOB="core_validation"
REPORTS_DIR="${SCRIPT_DIR}/reports"
VIRTUAL_ONLY=false
SKIP_BUILD=false
VCAN_IF="${VCAN_IF:-vcan0}"
DOIP_HOST="${DOIP_HOST:-127.0.0.1}"
DOIP_PORT="${DOIP_PORT:-13400}"
LICENSE_ENV="${XALOQI_LICENSE_SKIP:-0}"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

usage() {
    echo "Usage: $0 [--virtual] [--skip-build] [--help]"
    echo ""
    echo "  --virtual      Run only the in-process --virtual test (no ECU builds needed)"
    echo "  --skip-build   Skip build step, use existing binaries in build/"
    echo "  --help         Show this message"
    echo ""
    echo "Environment variables:"
    echo "  EDS_ROOT        Path to Xaloqi EDS repo (default: ../EDS)"
    echo "  FREERTOS_DIR    Path to FreeRTOS-Kernel (default: /opt/freertos-kernel)"
    echo "  VCAN_IF         SocketCAN interface (default: vcan0)"
    echo "  DOIP_HOST       DoIP loopback host (default: 127.0.0.1)"
    echo "  DOIP_PORT       DoIP TCP port (default: 13400)"
    echo "  XALOQI_LICENSE_SKIP   Set to 1 to skip license check in CI"
}

for arg in "$@"; do
    case "$arg" in
        --virtual)    VIRTUAL_ONLY=true ;;
        --skip-build) SKIP_BUILD=true   ;;
        --help|-h)    usage; exit 0     ;;
        *) echo "Unknown option: $arg"; usage; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

PASS=0
FAIL=0
OVERALL=0
BG_PIDS=()

log()  { echo "  $*"; }
ok()   { echo "  ✔ $*"; }
fail() { echo "  ✗ $*" >&2; OVERALL=1; }

cleanup() {
    for pid in "${BG_PIDS[@]:-}"; do
        kill "$pid" 2>/dev/null || true
    done
}
trap cleanup EXIT

require_cmd() {
    if ! command -v "$1" &>/dev/null; then
        echo "ERROR: '$1' not found. $2" >&2
        return 1
    fi
}

require_testlab() {
    if ! command -v testlab-run &>/dev/null; then
        echo "ERROR: testlab-run not found." >&2
        echo "  Install with: pip install xaloqi-tester" >&2
        exit 1
    fi
}

wait_for_port() {
    local host="$1" port="$2" timeout="${3:-10}"
    local elapsed=0
    while ! nc -z "$host" "$port" 2>/dev/null; do
        sleep 0.5
        elapsed=$((elapsed + 1))
        if [ "$elapsed" -ge "$((timeout * 2))" ]; then
            echo "ERROR: timed out waiting for $host:$port" >&2
            return 1
        fi
    done
}

wait_for_vcan() {
    local elapsed=0 timeout=10
    while ! ip link show "$VCAN_IF" &>/dev/null; do
        sleep 0.5
        elapsed=$((elapsed + 1))
        if [ "$elapsed" -ge "$((timeout * 2))" ]; then
            echo "ERROR: $VCAN_IF not available. Run:" >&2
            echo "  sudo modprobe vcan && sudo ip link add dev $VCAN_IF type vcan && sudo ip link set up $VCAN_IF" >&2
            return 1
        fi
    done
}

run_campaign() {
    local target="$1"; shift
    local extra_args=("$@")
    local json_out="${REPORTS_DIR}/${target}_run.json"

    log "Running campaign against $target..."
    if XALOQI_LICENSE_SKIP="${LICENSE_ENV}" testlab-run \
            --campaign "$CAMPAIGN" \
            --job      "$JOB"      \
            --json     "$json_out" \
            "${extra_args[@]}" 2>&1 | sed "s/^/    /"; then
        ok "$target → PASS  ($json_out)"
        PASS=$((PASS + 1))
    else
        fail "$target → FAIL  ($json_out)"
        FAIL=$((FAIL + 1))
    fi
}

# ---------------------------------------------------------------------------
# Step 0 — Sanity checks
# ---------------------------------------------------------------------------

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Xaloqi Compatibility Tests"
echo "═══════════════════════════════════════════════════════════════"
echo ""

require_testlab
mkdir -p "$REPORTS_DIR"

# ---------------------------------------------------------------------------
# Step 1 — In-process virtual run (always, proves campaign YAML is correct)
# ---------------------------------------------------------------------------

echo "── Step 1: Virtual validation (in-process VirtualBus + ECU sim) ──"
echo ""

run_campaign "virtual" \
    --config  "${SCRIPT_DIR}/configs/basic_ecu.yaml" \
    --virtual

echo ""

if $VIRTUAL_ONLY; then
    echo "─────────────────────────────────────────────────────────────────"
    echo "  --virtual flag set — skipping ECU builds and real transport tests."
    echo ""
    if [ "$OVERALL" -eq 0 ]; then
        echo "  RESULT: virtual validation PASSED  (campaign YAML is correct)"
        exit 0
    else
        echo "  RESULT: virtual validation FAILED"
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# Step 2 — Check prerequisites for full build+run
# ---------------------------------------------------------------------------

echo "── Step 2: Prerequisites ──────────────────────────────────────────"
echo ""

if [ -z "$EDS_ROOT" ] || [ ! -d "$EDS_ROOT" ]; then
    echo "ERROR: EDS_ROOT not found: '${EDS_ROOT}'" >&2
    echo "  Set EDS_ROOT to the path of the Xaloqi EDS repository." >&2
    echo "  Default: ../EDS (sibling directory)" >&2
    echo ""
    echo "  TIP: use --virtual to run without EDS:" >&2
    echo "    ./run_compat.sh --virtual" >&2
    exit 1
fi
ok "EDS_ROOT: $EDS_ROOT"

require_cmd west "Install: pip install west"
require_cmd ninja "Install: sudo apt install ninja-build"
ok "west and ninja found"

wait_for_vcan
ok "$VCAN_IF is up"

echo ""

# ---------------------------------------------------------------------------
# Step 3 — Build ECU simulator targets
# ---------------------------------------------------------------------------

BUILD_DIR="${SCRIPT_DIR}/build"

build_zephyr() {
    local target="$1" board="${2:-native_sim}"
    local src_dir="${EDS_ROOT}/examples/${target}"
    local out_dir="${BUILD_DIR}/${target}"

    if $SKIP_BUILD && [ -d "$out_dir" ]; then
        log "  Skipping build for $target (--skip-build)"
        return
    fi

    log "  Building $target (Zephyr $board)..."
    west build -p always -b "$board" \
        --build-dir "$out_dir" \
        "$src_dir" 2>&1 | tail -5 | sed "s/^/    /"
    ok "  Built: ${out_dir}/zephyr/zephyr.exe"
}

build_freertos() {
    local target="$1"
    local src_dir="${EDS_ROOT}/examples/${target}"
    local out_dir="${BUILD_DIR}/${target}"

    if $SKIP_BUILD && [ -d "$out_dir" ]; then
        log "  Skipping build for $target (--skip-build)"
        return
    fi

    if [ ! -d "$FREERTOS_DIR" ]; then
        echo "ERROR: FREERTOS_DIR not found: $FREERTOS_DIR" >&2
        echo "  Clone FreeRTOS-Kernel and set FREERTOS_DIR, or use --virtual." >&2
        exit 1
    fi

    log "  Building $target (FreeRTOS / QEMU Cortex-M4)..."
    cmake -S "$src_dir" -B "$out_dir" \
        -GNinja \
        -DEDS_PLATFORM=freertos \
        -DFREERTOS_DIR="$FREERTOS_DIR" \
        -DBOARD=qemu_cortex_m4 \
        -DCMAKE_BUILD_TYPE=Release \
        2>&1 | tail -3 | sed "s/^/    /"
    ninja -C "$out_dir" 2>&1 | tail -3 | sed "s/^/    /"
    ok "  Built: ${out_dir}/basic_ecu.elf"
}

echo "── Step 3: Build ──────────────────────────────────────────────────"
echo ""

build_zephyr basic_ecu        native_sim
build_zephyr basic_ecu_doip   native_sim

build_freertos basic_ecu_freertos
build_freertos basic_ecu_doip_freertos

echo ""

# ---------------------------------------------------------------------------
# Step 4 — Launch ECU simulators and run campaigns
# ---------------------------------------------------------------------------

echo "── Step 4: Run campaigns ──────────────────────────────────────────"
echo ""

# ── 4a: basic_ecu (Zephyr native_sim, CAN/vcan0) ──────────────────────────

log "Launching basic_ecu (native_sim, CAN)..."
"${BUILD_DIR}/basic_ecu/zephyr/zephyr.exe" &
BG_PIDS+=($!)
sleep 1   # brief settle for native_sim CAN init

run_campaign "basic_ecu" \
    --config    "${SCRIPT_DIR}/configs/basic_ecu.yaml" \
    --interface "$VCAN_IF"

kill "${BG_PIDS[-1]}" 2>/dev/null || true
BG_PIDS=("${BG_PIDS[@]::${#BG_PIDS[@]}-1}")
sleep 0.5

# ── 4b: basic_ecu_doip (Zephyr native_sim, DoIP loopback) ────────────────

log "Launching basic_ecu_doip (native_sim, DoIP)..."
"${BUILD_DIR}/basic_ecu_doip/zephyr/zephyr.exe" &
BG_PIDS+=($!)
wait_for_port "$DOIP_HOST" "$DOIP_PORT"

run_campaign "basic_ecu_doip" \
    --workspace "${SCRIPT_DIR}/configs/basic_ecu_doip.yaml"

kill "${BG_PIDS[-1]}" 2>/dev/null || true
BG_PIDS=("${BG_PIDS[@]::${#BG_PIDS[@]}-1}")
sleep 0.5

# ── 4c: basic_ecu_freertos (QEMU Cortex-M4, CAN/vcan0) ────────────────────

log "Launching basic_ecu_freertos (QEMU, CAN)..."
qemu-system-arm \
    -machine lm3s6965evb \
    -kernel "${BUILD_DIR}/basic_ecu_freertos/basic_ecu.elf" \
    -net nic -net socket,connect=localhost:4321 \
    -nographic -serial /dev/null &
BG_PIDS+=($!)
sleep 2   # QEMU takes longer to boot

run_campaign "basic_ecu_freertos" \
    --config    "${SCRIPT_DIR}/configs/basic_ecu_freertos.yaml" \
    --interface "$VCAN_IF"

kill "${BG_PIDS[-1]}" 2>/dev/null || true
BG_PIDS=("${BG_PIDS[@]::${#BG_PIDS[@]}-1}")
sleep 0.5

# ── 4d: basic_ecu_doip_freertos (QEMU + LwIP, DoIP loopback) ──────────────

log "Launching basic_ecu_doip_freertos (QEMU + LwIP, DoIP)..."
qemu-system-arm \
    -machine lm3s6965evb \
    -kernel "${BUILD_DIR}/basic_ecu_doip_freertos/basic_ecu.elf" \
    -net nic,model=stellaris \
    -net user,hostfwd=tcp::${DOIP_PORT}-:${DOIP_PORT} \
    -nographic -serial /dev/null &
BG_PIDS+=($!)
wait_for_port "$DOIP_HOST" "$DOIP_PORT"

run_campaign "basic_ecu_doip_freertos" \
    --workspace "${SCRIPT_DIR}/configs/basic_ecu_doip_freertos.yaml"

kill "${BG_PIDS[-1]}" 2>/dev/null || true
BG_PIDS=()
sleep 0.5

echo ""

# ---------------------------------------------------------------------------
# Step 5 — Compare results between targets
# ---------------------------------------------------------------------------

echo "── Step 5: Cross-target comparison ───────────────────────────────"
echo ""

compare_pair() {
    local a="$1" b="$2" label="$3"
    local fa="${REPORTS_DIR}/${a}_run.json"
    local fb="${REPORTS_DIR}/${b}_run.json"

    if [ ! -f "$fa" ] || [ ! -f "$fb" ]; then
        log "  SKIP $label — one or both result files missing"
        return
    fi

    log "  Comparing $a vs $b..."
    if XALOQI_LICENSE_SKIP="${LICENSE_ENV}" testlab compare \
            --before "$fa" --after "$fb" 2>&1 | sed "s/^/    /"; then
        ok "  $label → no regressions"
    else
        fail "  $label → regressions detected"
    fi
}

compare_pair basic_ecu        basic_ecu_doip         "Zephyr CAN vs DoIP"
compare_pair basic_ecu        basic_ecu_freertos      "Zephyr vs FreeRTOS (CAN)"
compare_pair basic_ecu_doip   basic_ecu_doip_freertos "Zephyr vs FreeRTOS (DoIP)"
compare_pair basic_ecu        basic_ecu_doip_freertos "CAN/Zephyr vs DoIP/FreeRTOS"

echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo "═══════════════════════════════════════════════════════════════"
TOTAL=$((PASS + FAIL))
if [ "$OVERALL" -eq 0 ]; then
    echo "  RESULT: ALL PASS  ($PASS/$TOTAL campaigns passed, 0 regressions)"
else
    echo "  RESULT: FAILED    ($PASS/$TOTAL campaigns passed, $FAIL failed)"
fi
echo ""
echo "  Reports: $REPORTS_DIR/"
echo "═══════════════════════════════════════════════════════════════"
echo ""

exit "$OVERALL"
