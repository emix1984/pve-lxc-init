#!/bin/bash
set +o errexit
set +o nounset
set +o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$PROJECT_ROOT/include/common.sh"

# 測試前臨時關閉 errexit，避免 send_gotify 的 return 1 直接炸掉腳本
set +o errexit
set +o nounset
set +o pipefail

TESTS_PASSED=0
TESTS_FAILED=0

check() {
    local name="$1"
    local expect_zero="$2"
    if [ "$expect_zero" -eq 1 ]; then
        echo "✓ PASS: $name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "✗ FAIL: $name"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

echo "=========================================="
echo "  Gotify send_gotify 测试"
echo "=========================================="
echo ""

# 测试 1: 无效 URL → 返回非 0（curl 连不上）
echo "Test 1: 无效 URL (invalid)"
send_gotify 'Test' 'Message' 5 'invalid' 'test123'
check "无效 URL 返回非 0" $(( $? != 0 ))
echo ""

# 测试 2: 有效 URL 格式 → 返回非 0（curl 连不上测试服务器）
echo "Test 2: 有效 URL (https://test.com)"
send_gotify 'Test' 'Message' 5 'https://test.com' 'test123'
check "有效 URL 返回非 0 (curl 不可达)" $(( $? != 0 ))
echo ""

# 测试 3: 尾部斜杠 URL → 正常处理，返回非 0（curl 连不上）
echo "Test 3: 尾部斜杠 (https://test.com/)"
send_gotify 'Test' 'Message' 5 'https://test.com/' 'test123'
check "尾部斜杠 URL 返回非 0 (curl 不可达)" $(( $? != 0 ))
echo ""

echo "=========================================="
echo "  Passed: $TESTS_PASSED"
echo "  Failed: $TESTS_FAILED"
echo "=========================================="

[ $TESTS_FAILED -eq 0 ]
exit $?
