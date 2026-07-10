#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$PROJECT_ROOT/include/common.sh"

# Test 1: Invalid URL should fail
echo "Test 1: Invalid URL"
if send_gotify 'Test' 'Message' 5 'invalid' 'token'; then
    echo "✗ FAIL (should have failed)"
    exit 1
else
    echo "✓ PASS"
fi

# Test 2: Valid URL should not fail validation
echo ""
echo "Test 2: Valid URL (https://test.com)"
gotify_url="https://test.com"
gotify_token="test"
echo "Gotify URL: '$gotify_url'"
echo "Gotify Token: '$gotify_token'"

# 直接在测试中验证
echo ""
echo "Direct regex test:"
pattern='^(https?://)?([a-zA-Z0-9][a-zA-Z0-9\-\.]+)(:[0-9]+)?(\/.*)?$'
if [[ "$gotify_url" =~ $pattern ]]; then
    echo "✓ Pattern matches"
else
    echo "✗ Pattern does not match"
    echo "Testing individual parts:"
    echo "  Starts with https://: $([[ "$gotify_url" =~ ^https:// ]] && echo 'yes' || echo 'no')"
    echo "  Characters: ${gotify_url:0:1} = '${gotify_url:0:1}'"
fi

if send_gotify 'Test' 'Message' 5 "$gotify_url" "$gotify_token"; then
    echo "✓ PASS (send_gotify returned 0)"
else
    echo "✗ FAIL (send_gotify returned non-zero)"
    exit 1
fi

echo ""
echo "All tests passed!"
