#!/bin/bash
# ==============================================================================
# Run test suite for pve-lxc-init
# ==============================================================================

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=========================================="
echo "   PVE-LXC-INIT Test Suite"
echo "=========================================="
echo ""

# Check if bats is available
if command -v bats &>/dev/null; then
    echo "✓ Found bats (Bash Automated Testing System)"
    echo ""
    echo "Running tests with bats..."
    echo ""

    # Run bats tests
    bats test/test_common.sh

    BATS_EXIT=$?
    echo ""
    if [ $BATS_EXIT -eq 0 ]; then
        echo "=========================================="
        echo "✅ All tests passed!"
        echo "=========================================="
    else
        echo "=========================================="
        echo "❌ Some tests failed!"
        echo "=========================================="
        exit $BATS_EXIT
    fi
else
    echo "⚠  bats not found, running simple bash tests instead..."
    echo ""

    # Run simple bash tests
    TEST_COUNT=0
    PASS_COUNT=0
    FAIL_COUNT=0

    for test_file in test/*.sh; do
        if [ -f "$test_file" ]; then
            echo "Running: $test_file"
            echo "----------------------------------------"
            bash "$test_file"
            TEST_EXIT=$?

            if [ $TEST_EXIT -eq 0 ]; then
                PASS_COUNT=$((PASS_COUNT + 1))
                echo "✓ PASS"
            else
                FAIL_COUNT=$((FAIL_COUNT + 1))
                echo "✗ FAIL"
            fi

            TEST_COUNT=$((TEST_COUNT + 1))
            echo ""
        fi
    done

    echo "=========================================="
    echo "  Test Summary:"
    echo "  Total:  $TEST_COUNT"
    echo "  Passed: $PASS_COUNT"
    echo "  Failed: $FAIL_COUNT"
    echo "=========================================="

    if [ $FAIL_COUNT -eq 0 ]; then
        echo "✅ All tests passed!"
        exit 0
    else
        echo "❌ Some tests failed!"
        exit 1
    fi
fi
