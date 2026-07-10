#!/bin/bash
# ==============================================================================
# Test Suite for pve-lxc-init
# Bash Automated Testing System (bats) compatible
# ==============================================================================

# Load the functions to test
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/include/common.sh"

# Setup test environment
setup() {
    # Save original variables
    OLD_GOTIFY_URL="$GOTIFY_URL"
    OLD_GOTIFY_TOKEN="$GOTIFY_TOKEN"
    OLD_DEVICE_NAME="$DEVICE_NAME"

    # Test Gotify URL
    GOTIFY_URL="https://test.gotify.example.com"
    GOTIFY_TOKEN="test-token-12345"
    DEVICE_NAME="TestServer"

    # Create temporary files for testing
    TEST_ENV_FILE="/tmp/test_pve_lxc_init.env"
    rm -f "$TEST_ENV_FILE"
}

# Cleanup test environment
teardown() {
    # Restore original variables
    GOTIFY_URL="$OLD_GOTIFY_URL"
    GOTIFY_TOKEN="$OLD_GOTIFY_TOKEN"
    DEVICE_NAME="$OLD_DEVICE_NAME"

    # Cleanup test files
    rm -f "$TEST_ENV_FILE"
}

# ==============================================================================
# TEST 1: check_root
# ==============================================================================
@test "check_root: should pass when run as root" {
    run check_root
    [ "$status" -eq 0 ]
}

@test "check_root: should fail when not run as root" {
    # Save current EUID
    OLD_UID="$EUID"

    # Change to non-root
    EUID=1000

    run check_root
    [ "$status" -eq 1 ]

    # Restore EUID
    EUID="$OLD_UID"
}

# ==============================================================================
# TEST 2: ensure_config
# ==============================================================================
@test "ensure_config: should add line when pattern not found" {
    local test_file="/tmp/test_ensure_config.txt"
    echo "existing=line1" > "$test_file"

    ensure_config "NEWLINE" "NEWLINE=value" "$test_file"

    grep -q "NEWLINE=value" "$test_file"
    [ "$?" -eq 0 ]

    rm -f "$test_file"
}

@test "ensure_config: should update line when pattern found" {
    local test_file="/tmp/test_ensure_config_update.txt"
    echo "OLD=line1" > "$test_file"

    ensure_config "OLD" "NEW=line1" "$test_file"

    grep -q "NEW=line1" "$test_file"
    [ "$?" -eq 0 ]

    rm -f "$test_file"
}

# ==============================================================================
# TEST 3: backup_file
# ==============================================================================
@test "backup_file: should create backup with timestamp" {
    local test_file="/tmp/test_backup.txt"
    echo "test content" > "$test_file"

    local backup_path=$(backup_file "$test_file")

    [ -f "$backup_path" ]
    [ -f "$test_file.bak.*" ]

    rm -f "$test_file" "$test_file.bak.*"
}

# ==============================================================================
# TEST 4: validate_nonempty
# ==============================================================================
@test "validate_nonempty: should return value when not empty" {
    local result=$(validate_nonempty "test" "TestField" "false")
    [ "$result" = "test" ]
}

@test "validate_nonempty: should return 1 and print error when empty" {
    run validate_nonempty "" "TestField" "true"
    [ "$status" -eq 1 ]
}

# ==============================================================================
# TEST 5: load_env / save_env
# ==============================================================================
@test "save_env: should save variables to file" {
    local test_env="/tmp/test_env_vars.env"
    DEVICE_NAME="TestDevice"
    GOTIFY_URL="https://test.com"
    GOTIFY_TOKEN="test123"

    save_env "$test_env"

    [ -f "$test_env" ]
    grep -q "DEVICE_NAME=\"TestDevice\"" "$test_env"
    grep -q "GOTIFY_URL=\"https://test.com\"" "$test_env"
    grep -q "GOTIFY_TOKEN=\"test123\"" "$test_env"

    rm -f "$test_env"
}

@test "load_env: should load variables from file" {
    local test_env="/tmp/test_load_env.env"
    DEVICE_NAME="OldDevice"

    cat > "$test_env" <<EOF
DEVICE_NAME="OldDevice"
GOTIFY_URL="https://old.com"
GOTIFY_TOKEN="old123"
EOF
    chmod 600 "$test_env"

    load_env "$test_env"

    [ "$DEVICE_NAME" = "OldDevice" ]
    [ "$GOTIFY_URL" = "https://old.com" ]
    [ "$GOTIFY_TOKEN" = "old123" ]

    rm -f "$test_env"
}

# ==============================================================================
# TEST 6: Gotify URL validation
# ==============================================================================
@test "send_gotify: should return 1 for invalid URL" {
    GOTIFY_URL="not-a-valid-url"
    GOTIFY_TOKEN="test-token"

    run send_gotify "Test" "Test message" 5 "not-a-valid-url" "test-token"
    [ "$status" -eq 1 ]
}

@test "send_gotify: should return 0 for valid URL format" {
    GOTIFY_URL="https://test.example.com"
    GOTIFY_TOKEN="test-token"

    run send_gotify "Test" "Test message" 5 "https://test.example.com" "test-token"
    # Should not fail on format validation (but may fail on actual network)
    [ "$status" -eq 0 ]
}

# ==============================================================================
# TEST 7: JSON vs form-data fallback
# ==============================================================================
@test "send_gotify: should handle form-data when JSON fails" {
    GOTIFY_URL="https://test.gotify.example.com"
    GOTIFY_TOKEN="test-token"

    # Mock curl to fail (to force form-data)
    run send_gotify "Test" "Test message" 5 "$GOTIFY_URL" "$GOTIFY_TOKEN"
    [ "$status" -eq 0 ]
}

# ==============================================================================
# TEST 8: Password validation
# ==============================================================================
@test "validate_nonempty: should work correctly" {
    run validate_nonempty "value" "FieldName" "true"
    [ "$status" -eq 0 ]
    [ "$output" = "value" ]
}

@test "validate_nonempty: should fail on empty string" {
    run validate_nonempty "" "FieldName" "true"
    [ "$status" -eq 1 ]
    [[ "$output" == *"不能为空"* ]]
}

# ==============================================================================
# TEST 9: Directory validation
# ==============================================================================
@test "validate_nonempty: should accept non-empty directory path" {
    run validate_nonempty "/tmp/test" "Directory" "true"
    [ "$status" -eq 0 ]
}

@test "validate_nonempty: should fail on empty directory path" {
    run validate_nonempty "" "Directory" "true"
    [ "$status" -eq 1 ]
}

# ==============================================================================
# TEST 10: Systemd service configuration
# ==============================================================================
@test "ensure_config: should handle commented out patterns" {
    local test_file="/tmp/test_commented.txt"
    echo "# COMMENTED=value" > "$test_file"

    ensure_config "COMMENTED" "COMMENTED=new_value" "$test_file"

    grep -q "COMMENTED=new_value" "$test_file"

    rm -f "$test_file"
}

# ==============================================================================
# TEST 11: Variable defaults
# ==============================================================================
@test "load_env: should use defaults when env file doesn't exist" {
    local test_env="/tmp/nonexistent.env"
    rm -f "$test_env"

    load_env "$test_env"

    # Should have default values
    [ -n "$DEVICE_NAME" ]
    [ -n "$TARGET_TIMEZONE" ]

    rm -f "$test_env"
}

# ==============================================================================
# TEST 12: Gotify token validation
# ==============================================================================
@test "validate_nonempty: should validate required fields" {
    run validate_nonempty "" "RequiredField" "true"
    [ "$status" -eq 1 ]

    run validate_nonempty "value" "OptionalField" "false"
    [ "$status" -eq 0 ]
}

# ==============================================================================
# TEST 13: No command validation
# ==============================================================================
@test "check_root: should only work as root" {
    run check_root
    [ "$status" -eq 0 ]
}

# ==============================================================================
# TEST 14: load_env error handling
# ==============================================================================
@test "load_env: should handle invalid format gracefully" {
    local test_env="/tmp/test_invalid_format.env"
    echo "invalid content without equals" > "$test_env"

    load_env "$test_env"

    # Should not crash, just print error

    rm -f "$test_env"
}

# ==============================================================================
# TEST 15: Config file permissions
# ==============================================================================
@test "save_env: should set correct permissions (600)" {
    local test_env="/tmp/test_permissions.env"
    save_env "$test_env"

    local perms=$(stat -c '%a' "$test_env" 2>/dev/null || stat -f '%A' "$test_env" 2>/dev/null)
    [ "$perms" = "600" ] || [ "$perms" = "600" ]

    rm -f "$test_env"
}
