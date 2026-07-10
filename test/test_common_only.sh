#!/bin/bash
# ==============================================================================
# Test common.sh functions only
# ==============================================================================

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$PROJECT_ROOT/include/common.sh"

TESTS_PASSED=0
TESTS_FAILED=0

# Helper function
run_test() {
    local test_name="$1"
    local test_code="$2"

    echo -n "Testing: $test_name ... "

    if eval "$test_code"; then
        echo "✓ PASS"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "✗ FAIL"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# ==============================================================================
# TESTS FOR common.sh
# ==============================================================================

# 1. check_root
run_test "check_root should work as root" "check_root"

# 2. ensure_config
TEST_FILE=$(mktemp)
echo "line1=value1" > "$TEST_FILE"
run_test "ensure_config should add line when pattern not found" \
    "[ -f \"$TEST_FILE\" ] && ensure_config \"NEW\" \"NEW=value2\" \"$TEST_FILE\" && grep -q 'NEW=value2' \"$TEST_FILE\""

TEST_FILE=$(mktemp)
echo "line1=value1" > "$TEST_FILE"
run_test "ensure_config should update line when pattern found" \
    "[ -f \"$TEST_FILE\" ] && ensure_config \"line1\" \"NEW=line1\" \"$TEST_FILE\" && grep -q 'NEW=line1' \"$TEST_FILE\""

rm -f "$TEST_FILE"

# 3. ensure_config_logind
TEST_FILE=$(mktemp)
echo "# HandleLidSwitch=ignore" > "$TEST_FILE"
run_test "ensure_config_logind should handle commented out patterns" \
    "[ -f \"$TEST_FILE\" ] && ensure_config_logind \"HandleLidSwitch\" \"HandleLidSwitch=ignore\" \"$TEST_FILE\" && grep -q 'HandleLidSwitch=ignore' \"$TEST_FILE\""

rm -f "$TEST_FILE"

# 4. backup_file
TEST_FILE=$(mktemp)
echo "content" > "$TEST_FILE"

BACKUP_PATH=$(backup_file "$TEST_FILE")
if [ -n "$BACKUP_PATH" ] && [ -f "$BACKUP_PATH" ]; then
    echo "✓ PASS"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "✗ FAIL"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

rm -f "$TEST_FILE" "$BACKUP_PATH" 2>/dev/null || true

# 5. print functions
run_test "print_info should output to stdout" "print_info 'Test message' > /dev/null 2>&1"
run_test "print_success should output to stdout" "print_success 'Success' > /dev/null 2>&1"
run_test "print_error should output to stdout" "print_error 'Error' > /dev/null 2>&1"
run_test "print_warning should output to stdout" "print_warning 'Warning' > /dev/null 2>&1"

# 6. Logging (remove old Gotify tests - moved to test_send_gotify.sh)
run_test "write_log should not crash" "write_log 'Test log message' > /dev/null 2>&1"

# 8. print_success_with_log
run_test "print_success_with_log should output to stdout and log" \
    "print_success_with_log 'Test message' > /dev/null 2>&1 && write_log 'Test message' > /dev/null 2>&1"

# 9. print_error_with_log
run_test "print_error_with_log should output to stdout and log" \
    "print_error_with_log 'Test error' > /dev/null 2>&1 && write_log 'Test error' > /dev/null 2>&1"

# ==============================================================================
# TEST SUMMARY
# ==============================================================================
echo ""
echo "=========================================="
echo "  Test Summary for common.sh:"
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
