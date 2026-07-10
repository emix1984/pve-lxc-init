#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

# ==============================================================================
# Project: pve-lxc-init
# Module: include/common.sh
# Description: Shared utility library for deploy.sh and sub-modules.
# ==============================================================================

# ---------------------------- Color Output ----------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; BLUE='\033[1;34m'; NC='\033[0m'

print_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
print_success() { echo -e "${CYAN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
print_title()   { echo -e "\n${BLUE}>>> $1${NC}"; }
print_separator() { echo "------------------------------------------------"; }

# ---------------------------- Validation ----------------------------
check_command() {
    local rc=$?
    if [ $rc -ne 0 ]; then
        print_error "$1"
        exit $rc
    else
        print_success "$2"
    fi
}

# ---------------------------- Logging ----------------------------
LOG_FILE="${SCRIPT_DIR:-$(dirname "$0")}/report_error.log"
write_log() {
    if command -v logger &>/dev/null; then
        logger -t "pve-lxc-init" "$1"
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

print_success_with_log() {
    print_success "$1"
    write_log "SUCCESS: $1"
}

print_error_with_log() {
    print_error "$1"
    write_log "ERROR: $1"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "权限不足：请使用 root 身份运行此脚本"
        exit 1
    fi
}

# ---------------------------- Config Helpers ----------------------------
ensure_config() {
    local pattern="$1" line="$2" file="$3"
    if grep -q "$pattern" "$file" 2>/dev/null; then
        sed -i "s|^$pattern.*|$line|" "$file"
    else
        echo "$line" >> "$file"
    fi
}

ensure_config_logind() {
    local pattern="$1" line="$2" file="$3"
    if grep -qE "^#?\s*$pattern" "$file" 2>/dev/null; then
        sed -i "s|^#\s*$pattern.*|$line|" "$file"
        sed -i "s|^$pattern.*|$line|" "$file"
    else
        echo "$line" >> "$file"
    fi
}

backup_file() {
    local source="$1"
    local backup_path="${source}.bak.$(date +%Y%m%d_%H%M%S)"
    if [ -f "$source" ]; then
        cp "$source" "$backup_path"
        print_success "已备份: $backup_path" >&2
    fi
    echo "$backup_path"
}

# ---------------------------- Gotify Sender (JSON或form-data) ----------------------------
send_gotify() {
    local title="$1" message="$2" priority="$3"
    local gotify_url="$4" gotify_token="$5"
    local payload

    gotify_url="${gotify_url%/}"

    payload=$(jq -n \
        --arg title "$title" \
        --arg msg "$message" \
        --argjson priority "$priority" \
        '{title: $title, message: $msg, priority: $priority,
          extras: {"client::display": {"contentType": "text/markdown"}}}' 2>/dev/null)

    if [ -n "$payload" ]; then
        if curl -s -m 10 -X POST "${gotify_url}/message?token=${gotify_token}" \
            -H "Content-Type: application/json" \
            -d "$payload" > /dev/null 2>&1; then
            print_success "Gotify 推送成功: $title"
            return 0
        else
            print_error "Gotify JSON 推送失敗，回退到 form-data"
        fi
    fi

    if ! curl -s -m 10 -X POST "${gotify_url}/message?token=${gotify_token}" \
        -F "title=${title}" \
        -F "message=${message}" \
        -F "priority=${priority}" > /dev/null 2>&1; then
        print_error "Gotify 推送失敗 (JSON/form-data 皆失敗)"
        return 1
    fi
    print_success "Gotify 推送成功 (form-data): $title"
    return 0
}
