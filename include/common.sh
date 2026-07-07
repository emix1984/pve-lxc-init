#!/bin/bash
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
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
print_title()   { echo -e "\n${BLUE}>>> $1${NC}"; }
print_separator() { echo "------------------------------------------------"; }

# ---------------------------- Validation ----------------------------
check_command() {
    if [ $? -ne 0 ]; then print_error "$1"; exit 1
    else print_success "$2"; fi
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "权限不足：请使用 root 身份或 sudo 运行此脚本"
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
        print_success "已备份: $backup_path"
    fi
    echo "$backup_path"
}

# ---------------------------- Gotify Sender (JSON) ----------------------------
send_gotify() {
    local title="$1" message="$2" priority="$3"
    local gotify_url="$4" gotify_token="$5"
    local payload

    payload=$(jq -n \
        --arg title "$title" \
        --arg msg "$message" \
        --argjson priority "$priority" \
        '{title: $title, message: $msg, priority: $priority,
          extras: {"client::display": {"contentType": "text/markdown"}}}' 2>/dev/null)

    if [ -z "$payload" ]; then
        print_error "JSON 封裝失敗，請確認 jq 是否已安裝"
        return 1
    fi

    curl -s -X POST "${gotify_url}/message?token=${gotify_token}" \
        -H "Content-Type: application/json" \
        -d "$payload" > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        print_success "Gotify 推送成功: $title"
    else
        print_error "Gotify 推送失敗"
        return 1
    fi
}
