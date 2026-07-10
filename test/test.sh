#!/bin/bash
# ==============================================================================
# Simple test runner for pve-lxc-init
# ==============================================================================

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$PROJECT_ROOT/include/common.sh"

TESTS_PASSED=0
TESTS_FAILED=0

# Helper functions
run_test() {
    local test_name="$1"
    local test_code="$2"

    echo "Testing: $test_name"

    if eval "$test_code"; then
        echo "  ✓ PASS"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "  ✗ FAIL"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    echo ""
}

# ==============================================================================
# TEST 1: check_root
# ==============================================================================
run_test "check_root should work as root" "check_root"

# ==============================================================================
# TEST 2: ensure_config
# ==============================================================================
TEST_FILE=$(mktemp)
echo "line1=value1" > "$TEST_FILE"

run_test "ensure_config should add line when pattern not found" "[ -f \"$TEST_FILE\" ] && ensure_config \"NEW\" \"NEW=value2\" \"$TEST_FILE\" && grep -q 'NEW=value2' \"$TEST_FILE\""

TEST_FILE=$(mktemp)
echo "line1=value1" > "$TEST_FILE"

run_test "ensure_config should update line when pattern found" "[ -f \"$TEST_FILE\" ] && ensure_config \"line1\" \"NEW=line1\" \"$TEST_FILE\" && grep -q 'NEW=line1' \"$TEST_FILE\""

rm -f "$TEST_FILE"

# ==============================================================================
# TEST 3: backup_file
# ==============================================================================
TEST_FILE=$(mktemp)
echo "content" > "$TEST_FILE"

run_test "backup_file should create backup" "backup_file \"$TEST_FILE\" | grep -q '.bak' && [ -f \"$TEST_FILE.bak.*\" ]"

rm -f "$TEST_FILE" "$TEST_FILE.bak.*"

# ==============================================================================
# TEST 4: validate_nonempty
# ==============================================================================
run_test "validate_nonempty should return value when not empty" "[ \"$(validate_nonempty 'value' 'Field' 'false')\" = 'value' ]"

if ! validate_nonempty "" "Field" "true" 2>/dev/null; then
    echo "  ✓ PASS"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "  ✗ FAIL"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi
echo ""

# ==============================================================================
# TEST 5: save_env / load_env
# ==============================================================================
TEST_ENV=$(mktemp)

run_test "save_env should save to file" "DEVICE_NAME='Test' GOTIFY_URL='http://test.com' GOTIFY_TOKEN='token' save_env \"$TEST_ENV\" && [ -f \"$TEST_ENV\" ]"

rm -f "$TEST_ENV"

# ==============================================================================
# TEST 6: Gotify URL validation
# ==============================================================================
GOTIFY_URL="invalid"
GOTIFY_TOKEN="test"

run_test "send_gotify should fail for invalid URL format" "send_gotify 'Test' 'Message' 5 'invalid-url' 'test' && [ $? -ne 0 ]"

# ==============================================================================
# TEST 7: load_env error handling
# ==============================================================================
TEST_ENV=$(mktemp)
echo "invalid" > "$TEST_ENV"

run_test "load_env should handle invalid format" "load_env \"$TEST_ENV\""

rm -f "$TEST_ENV"

# ==============================================================================
# TEST SUMMARY
# ==============================================================================
echo "=========================================="
echo "  Test Summary:"
echo "  Passed: $TESTS_PASSED"
echo "  Failed: $TESTS_FAILED"
echo "  Total:  $((TESTS_PASSED + TESTS_FAILED))"
echo "=========================================="

if [ $TESTS_FAILED -eq 0 ]; then
    echo "✅ All tests passed!"
    exit 0
else
    echo "❌ Some tests failed!"
    exit 1
fi
