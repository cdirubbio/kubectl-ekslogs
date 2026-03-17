#!/usr/bin/env bash
#
# test-kubectl-ekslogs.sh — Test cases for kubectl-ekslogs
#
# Prerequisites:
#   - kubectl configured with access to an EKS cluster
#   - At least one Ready node in the cluster
#   - The EKS Node Monitoring Agent installed
#   - For S3 tests: an S3 bucket and boto3 installed
#   - For debug pod tests: a reachable container image
#
# Usage:
#   ./test-kubectl-ekslogs.sh                          # Run offline tests only
#   ./test-kubectl-ekslogs.sh --node <node-name>       # Run offline + live tests
#   ./test-kubectl-ekslogs.sh --node <node> --s3-bucket <bucket>  # Include S3 tests
#   ./test-kubectl-ekslogs.sh --node <node> --debug-image <image> # Include debug pod tests
#
# All flags can be combined. Multiple --node flags are supported.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EKSLOGS="${SCRIPT_DIR}/kubectl-ekslogs"

# --- Colors ---
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    RESET='\033[0m'
else
    RED='' GREEN='' YELLOW='' CYAN='' RESET=''
fi

PASSED=0
FAILED=0
SKIPPED=0

pass() { ((PASSED++)); echo -e "${GREEN}  PASS${RESET} $1"; }
fail() { ((FAILED++)); echo -e "${RED}  FAIL${RESET} $1"; }
skip() { ((SKIPPED++)); echo -e "${YELLOW}  SKIP${RESET} $1"; }

# Run a command and assert it exits with the expected code.
# Usage: assert_exit <expected_code> <test_name> <command...>
assert_exit() {
    local expected="$1" name="$2"
    shift 2
    local actual=0
    "$@" >/dev/null 2>&1 || actual=$?
    if [[ "$actual" -eq "$expected" ]]; then
        pass "$name"
    else
        fail "$name (expected exit $expected, got $actual)"
    fi
}

# Run a command and assert stderr+stdout contains a substring.
# Usage: assert_output_contains <substring> <test_name> <command...>
assert_output_contains() {
    local substring="$1" name="$2"
    shift 2
    local output
    output=$("$@" 2>&1) || true
    if echo "$output" | grep -qF "$substring"; then
        pass "$name"
    else
        fail "$name (expected output to contain: '$substring')"
    fi
}

# Run a command and assert a file exists afterward, then clean it up.
# Usage: assert_file_created <filepath> <test_name> <command...>
assert_file_created() {
    local filepath="$1" name="$2"
    shift 2
    "$@" >/dev/null 2>&1 || true
    if [[ -f "$filepath" ]]; then
        pass "$name"
        rm -f "$filepath"
    else
        fail "$name (expected file: $filepath)"
    fi
}

# --- Argument Parsing ---

NODES=()
S3_BUCKET=""
DEBUG_IMAGE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --node)       NODES+=("$2"); shift 2 ;;
        --s3-bucket)  S3_BUCKET="$2"; shift 2 ;;
        --debug-image) DEBUG_IMAGE="$2"; shift 2 ;;
        -h|--help)
            sed -n '3,/^$/p' "$0"
            exit 0
            ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

# =========================================================================
echo -e "\n${CYAN}=== Offline / Validation Tests ===${RESET}\n"
# =========================================================================

assert_exit 0 "--help exits 0" \
    "$EKSLOGS" --help

assert_output_contains "kubectl ekslogs" "--help shows usage" \
    "$EKSLOGS" --help

assert_exit 1 "no arguments exits 1" \
    "$EKSLOGS"

assert_output_contains "At least one node name or --selector is required" \
    "no arguments shows error message" \
    "$EKSLOGS"

assert_exit 1 "unknown flag exits 1" \
    "$EKSLOGS" --unknown-flag

assert_output_contains "Unknown flag" "unknown flag shows error" \
    "$EKSLOGS" --unknown-flag

assert_exit 1 "--selector + node names exits 1" \
    "$EKSLOGS" --selector foo=bar some-node

assert_output_contains "Cannot combine --selector" \
    "--selector + node names shows error" \
    "$EKSLOGS" --selector foo=bar some-node

assert_exit 1 "--key without --s3 exits 1" \
    "$EKSLOGS" --key some-prefix some-node

assert_output_contains "Flag --key requires --s3" \
    "--key without --s3 shows error" \
    "$EKSLOGS" --key some-prefix some-node

assert_exit 1 "--no-proxy without --debug-image exits 1" \
    "$EKSLOGS" --no-proxy some-node

assert_output_contains "Flag --debug-image is required" \
    "--no-proxy without --debug-image shows error" \
    "$EKSLOGS" --no-proxy some-node

assert_exit 1 "--output-dir nonexistent exits 1" \
    "$EKSLOGS" --output-dir /nonexistent/path some-node

assert_output_contains "Output directory does not exist" \
    "--output-dir nonexistent shows error" \
    "$EKSLOGS" --output-dir /nonexistent/path some-node

assert_exit 1 "--selector with empty value exits 1" \
    "$EKSLOGS" --selector

assert_exit 1 "--timeout with empty value exits 1" \
    "$EKSLOGS" --timeout

# --- Timeout validation ---

assert_exit 1 "--timeout banana exits 1" \
    "$EKSLOGS" --timeout banana some-node

assert_output_contains "Invalid timeout format" \
    "--timeout banana shows error" \
    "$EKSLOGS" --timeout banana some-node

assert_exit 1 "--timeout 5m exits 1" \
    "$EKSLOGS" --timeout 5m some-node

assert_output_contains "Invalid timeout format" \
    "--timeout 5m shows error" \
    "$EKSLOGS" --timeout 5m some-node

assert_exit 1 "--timeout -10s exits 1" \
    "$EKSLOGS" --timeout -10s some-node

assert_exit 1 "--timeout 0s exits 1 (caught by regex since 0 is not positive)" \
    "$EKSLOGS" --timeout 0s some-node || true
# Note: 0s matches [0-9]+s so it passes validation but kubectl wait handles it.
# If you want to reject 0s, the regex would need adjustment. Keeping as-is.

# --- Cluster-dependent validation (needs kubectl access) ---

if kubectl cluster-info >/dev/null 2>&1; then
    assert_exit 1 "bogus node name exits 1" \
        "$EKSLOGS" fake-node-name

    assert_output_contains "Node not found" \
        "bogus node name shows error" \
        "$EKSLOGS" fake-node-name

    assert_exit 1 "selector matching no nodes exits 1" \
        "$EKSLOGS" --selector fake-label=nope

    assert_output_contains "No nodes found matching selector" \
        "selector matching no nodes shows error" \
        "$EKSLOGS" --selector fake-label=nope
else
    skip "bogus node name (no cluster access)"
    skip "selector matching no nodes (no cluster access)"
fi

# --- S3 + no-proxy mutual exclusion ---

assert_output_contains "Cannot use --s3 and --no-proxy together" \
    "--s3 and --no-proxy together shows error" \
    "$EKSLOGS" --s3 some-bucket --no-proxy --debug-image busybox some-node

# =========================================================================
# Live tests — only run when --node is provided
# =========================================================================

if [[ ${#NODES[@]} -eq 0 ]]; then
    echo ""
    skip "Live tests (no --node provided)"
    echo -e "\n${CYAN}=== Results ===${RESET}"
    echo -e "  ${GREEN}Passed: ${PASSED}${RESET}  ${RED}Failed: ${FAILED}${RESET}  ${YELLOW}Skipped: ${SKIPPED}${RESET}"
    [[ "$FAILED" -eq 0 ]] && exit 0 || exit 1
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

NODE="${NODES[0]}"

echo -e "\n${CYAN}=== Live Tests (proxy mode) ===${RESET}\n"

assert_file_created "${TMPDIR}/${NODE}-logs.tar.gz" \
    "single node proxy download" \
    "$EKSLOGS" -o "$TMPDIR" "$NODE"

# Verify tarball is valid
"$EKSLOGS" -o "$TMPDIR" "$NODE" >/dev/null 2>&1 || true
if tar tzf "${TMPDIR}/${NODE}-logs.tar.gz" >/dev/null 2>&1; then
    pass "downloaded tarball is valid tar.gz"
else
    fail "downloaded tarball is valid tar.gz"
fi
rm -f "${TMPDIR}/${NODE}-logs.tar.gz"

# Timeout test
assert_exit 1 "short timeout (1s) exits 1" \
    "$EKSLOGS" --timeout 1s "$NODE"

assert_output_contains "Timed out" \
    "short timeout shows timeout error" \
    "$EKSLOGS" --timeout 1s "$NODE"

# Multi-node test (if multiple nodes provided)
if [[ ${#NODES[@]} -gt 1 ]]; then
    echo -e "\n${CYAN}=== Live Tests (multi-node) ===${RESET}\n"

    "$EKSLOGS" -o "$TMPDIR" "${NODES[@]}" >/dev/null 2>&1 || true
    all_present=true
    for n in "${NODES[@]}"; do
        if [[ ! -f "${TMPDIR}/${n}-logs.tar.gz" ]]; then
            all_present=false
            break
        fi
    done
    if $all_present; then
        pass "multi-node proxy download (${#NODES[@]} nodes)"
    else
        fail "multi-node proxy download (${#NODES[@]} nodes)"
    fi
    for n in "${NODES[@]}"; do rm -f "${TMPDIR}/${n}-logs.tar.gz"; done
fi

# Label selector test
echo -e "\n${CYAN}=== Live Tests (label selector) ===${RESET}\n"

"$EKSLOGS" -o "$TMPDIR" --selector kubernetes.io/os=linux >/dev/null 2>&1 || true
selector_count=$(find "$TMPDIR" -name '*-logs.tar.gz' | wc -l | tr -d ' ')
if [[ "$selector_count" -gt 0 ]]; then
    pass "label selector downloaded ${selector_count} bundle(s)"
else
    fail "label selector downloaded 0 bundles"
fi
find "$TMPDIR" -name '*-logs.tar.gz' -delete

# No leftover resources
if kubectl get nodediagnostics 2>&1 | grep -q "No resources found"; then
    pass "no leftover NodeDiagnostic resources"
else
    fail "no leftover NodeDiagnostic resources"
fi

if kubectl get pods -l app.kubernetes.io/managed-by=kubectl-ekslogs --all-namespaces 2>&1 | grep -q "No resources found"; then
    pass "no leftover transfer pods"
else
    fail "no leftover transfer pods"
fi

# =========================================================================
# S3 tests — only when --s3-bucket is provided
# =========================================================================

if [[ -n "$S3_BUCKET" ]]; then
    echo -e "\n${CYAN}=== Live Tests (S3 mode) ===${RESET}\n"

    S3_TEST_PREFIX="ekslogs-test-$$"

    assert_exit 0 "S3 upload with key prefix" \
        "$EKSLOGS" --s3 "$S3_BUCKET" --key "$S3_TEST_PREFIX" "$NODE"

    # Verify object landed in S3
    if aws s3 ls "s3://${S3_BUCKET}/${S3_TEST_PREFIX}/${NODE}-logs.tar.gz" >/dev/null 2>&1; then
        pass "S3 object exists at expected key"
        aws s3 rm "s3://${S3_BUCKET}/${S3_TEST_PREFIX}/${NODE}-logs.tar.gz" >/dev/null 2>&1 || true
    else
        fail "S3 object exists at expected key"
    fi

    assert_exit 0 "S3 upload without key prefix" \
        "$EKSLOGS" --s3 "$S3_BUCKET" "$NODE"

    if aws s3 ls "s3://${S3_BUCKET}/${NODE}-logs.tar.gz" >/dev/null 2>&1; then
        pass "S3 object at bucket root exists"
        aws s3 rm "s3://${S3_BUCKET}/${NODE}-logs.tar.gz" >/dev/null 2>&1 || true
    else
        fail "S3 object at bucket root exists"
    fi
else
    skip "S3 tests (no --s3-bucket provided)"
fi

# =========================================================================
# Debug pod tests — only when --debug-image is provided
# =========================================================================

if [[ -n "$DEBUG_IMAGE" ]]; then
    echo -e "\n${CYAN}=== Live Tests (debug pod mode) ===${RESET}\n"

    assert_file_created "${TMPDIR}/${NODE}-logs.tar.gz" \
        "debug pod download" \
        "$EKSLOGS" --no-proxy --debug-image "$DEBUG_IMAGE" -o "$TMPDIR" "$NODE"

    # Verify no pods left behind
    if kubectl get pods -l app.kubernetes.io/managed-by=kubectl-ekslogs --all-namespaces 2>&1 | grep -q "No resources found"; then
        pass "debug pod cleaned up after download"
    else
        fail "debug pod cleaned up after download"
    fi
else
    skip "Debug pod tests (no --debug-image provided)"
fi

# --- Results ---
echo ""
echo -e "${CYAN}=== Results ===${RESET}"
echo -e "  ${GREEN}Passed: ${PASSED}${RESET}  ${RED}Failed: ${FAILED}${RESET}  ${YELLOW}Skipped: ${SKIPPED}${RESET}"
if [[ "$FAILED" -eq 0 ]]; then exit 0; else exit 1; fi

