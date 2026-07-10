#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

# ==============================================================================
# Project: pve-lxc-init
# Script: deploy.sh
# Description: Unified deployment & management tool for PVE LXC (Debian/Ubuntu).
#              Interactive menu (TTY) + CLI flags (non-interactive) + systemd mode.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ---------------------------- Bootstrap ----------------------------
if [ -f "$SCRIPT_DIR/include/common.sh" ]; then
    source "$SCRIPT_DIR/include/common.sh"
else
    echo -e "\033[0;31m[FATAL]\033[0m 缺少 include/common.sh，请确认项目结构完整"
    exit 1
fi

# ---------------------------- Default Variables ----------------------------
ENV_FILE="/etc/default/pve-lxc-init"
DEVICE_NAME="${DEVICE_NAME:-$(hostname)}"
GOTIFY_URL="${GOTIFY_URL:-}"
GOTIFY_TOKEN="${GOTIFY_TOKEN:-}"
TARGET_PEER_IP="${TARGET_PEER_IP:-100.114.252.115}"
TARGET_TIMEZONE="${TARGET_TIMEZONE:-Asia/Seoul}"
TARGET_ROOT_HOME="${TARGET_ROOT_HOME:-/DATA/AppData}"
INSTALL_PANEL="${INSTALL_PANEL:-none}"

load_env() {
    if [ -f "$ENV_FILE" ]; then
        if source "$ENV_FILE" 2>/dev/null; then
            print_info "已加载配置: $ENV_FILE"
        else
            print_error "配置格式错误，将使用默认值: $ENV_FILE"
        fi
    fi
}

save_env() {
    cat > "$ENV_FILE" <<EOF
# pve-lxc-init 持久化配置 - 由 deploy.sh 自动管理
DEVICE_NAME="${DEVICE_NAME}"
GOTIFY_URL="${GOTIFY_URL}"
GOTIFY_TOKEN="${GOTIFY_TOKEN}"
TARGET_PEER_IP="${TARGET_PEER_IP}"
EOF
    chmod 600 "$ENV_FILE"
    print_success "配置已保存至: $ENV_FILE"
}

load_env

# ==============================================================================
#                          BOOTSTRAP FUNCTIONS
# ==============================================================================
validate_nonempty() {
    local value="$1" name="$2" required="$3"
    if [ -z "$value" ] && [ "$required" = "true" ]; then
        print_error "$name 不能为空"
        return 1
    fi
    echo "$value"
}

# ==============================================================================
#                         MODULE FUNCTIONS
# ==============================================================================

# ====================== Module: Init Server ======================
module_init_server() {
    print_title "一键初始化服务器"

    local INSTALL_GOTIFY=false
    local PASSWORD_MATCH=false

    # ========== 交互收集阶段 ==========
    if [ -t 0 ]; then
        echo "选择预装管理面板:"
        echo "  1) CasaOS (轻量级家庭云系统)"
        echo "  2) 1Panel (现代化开源通用面板)"
        echo "  0) 暂不安装 (默认)"
        read -rp "输入编号 [1/2/0]: " choice
        case "$choice" in
            1) INSTALL_PANEL="casaos" ;;
            2) INSTALL_PANEL="1panel" ;;
            *) INSTALL_PANEL="none" ;;
        esac

        while true; do
            read -rp "设定时区 [默认: $TARGET_TIMEZONE]: " tz_input
            TARGET_TIMEZONE=${tz_input:-$TARGET_TIMEZONE}
            if timedatectl list-timezones | grep -q "^${TARGET_TIMEZONE}$"; then
                break
            else
                print_warning "$TARGET_TIMEZONE 不是有效时区，请重新输入"
            fi
        done

        while true; do
            read -rp "设定 Root 工作目录 [默认: $TARGET_ROOT_HOME]: " dir_input
            TARGET_ROOT_HOME=${dir_input:-$TARGET_ROOT_HOME}
            if [[ "$TARGET_ROOT_HOME" =~ ^/ ]]; then
                break
            else
                print_warning "目录必须以斜线开头，请重新输入"
            fi
        done

        echo ""
        while true; do
            read -sp "请输入 Root 新密码 [默认: 1234]: " pw1; echo
            local ROOT_PW_INPUT=${pw1:-1234}
            if [ -z "$ROOT_PW_INPUT" ]; then
                print_warning "密码不能为空"
                continue
            fi
            read -sp "请再次输入密码: " pw2; echo
            if [ "$ROOT_PW_INPUT" = "$pw2" ]; then
                ROOT_PW="$ROOT_PW_INPUT"
                PASSWORD_MATCH=true
                break
            else
                print_error "两次密码不一致，请重新输入"
            fi
        done

        # Gotify 配置（一次问完，一次装完）
        echo ""
        print_separator
        echo "--- Gotify 推送配置 (可选，可跳过) ---"
        while true; do
            read -rp "是否配置 Gotify? (y/n, 默认 n): " gotify_yn
            gotify_yn=${gotify_yn:-n}
            if [[ "$gotify_yn" == [yY] ]]; then
                while true; do
                    read -rp "请输入 Gotify API 端点 (如 https://gotify.example.com): " gotify_url_input
                    read -rp "请输入 Gotify Token: " gotify_token_input
                    if [ -n "$gotify_url_input" ] && [ -n "$gotify_token_input" ]; then
                        GOTIFY_URL="$gotify_url_input"
                        GOTIFY_TOKEN="$gotify_token_input"
                        INSTALL_GOTIFY=true
                        save_env
                        break
                    else
                        print_error "Gotify URL 和 Token 都不能为空，请重新输入"
                    fi
                done
                break
            elif [[ "$gotify_yn" == [nN] ]]; then
                break
            else
                print_error "请输入 y 或 n"
            fi
        done

        # 确认摘要
        echo ""
        print_separator
        echo "========== 执行确认 =========="
        if [ "$INSTALL_PANEL" = "none" ]; then echo "  面板安装: 不安装"
        else echo "  面板安装: $INSTALL_PANEL"; fi
        echo "  时区: $TARGET_TIMEZONE"
        echo "  工作目录: $TARGET_ROOT_HOME"
        echo "  Root 密码: $($PASSWORD_MATCH && echo "已设置" || echo "跳过")"
        echo "  Gotify 推送: $($INSTALL_GOTIFY && echo "已配置 (通知 + 定时监控)" || echo "跳过")"
        echo "============================="
        while true; do
            read -rp "确认执行以上操作? (y/n, 默认 y): " confirm
            confirm=${confirm:-y}
            if [[ "$confirm" == [yY] ]] || [[ "$confirm" == [nN] ]]; then
                break
            else
                print_error "请输入 y 或 n"
            fi
        done
        if [[ "$confirm" == [nN] ]]; then
            print_info "已取消"
            exit 0
        fi
    else
        INSTALL_PANEL="none"
        print_info "非交互模式，仅执行系统初始化，跳过面板/Gotify/密码设置"
    fi

    # ========== 执行阶段 ==========
    check_root

    print_info "正在更新系统软件包..."
    if ! apt update && ! apt upgrade -y; then
        print_error "系统更新失败"
        exit 1
    fi
    print_success "系统已更新至最新"

    print_info "正在安装基础工具包..."
    if ! apt install -y curl wget nano tree screen tmux traceroute htop sshpass openssl jq iputils-ping lvm2 xfsprogs lsb-release; then
        print_error "工具安装失败"
        exit 1
    fi
    print_success "基础工具包已就绪"

    print_info "正在同步时区: $TARGET_TIMEZONE..."
    if ! timedatectl set-timezone "$TARGET_TIMEZONE"; then
        print_error "时区设置失败"
        exit 1
    fi
    print_success "时区已设为 $TARGET_TIMEZONE"

    print_info "正在配置 SSH 服务..."
    if ! apt install -y openssh-server openssh-client; then
        print_error "SSH 服务安装失败"
        exit 1
    fi
    if ! systemctl enable --now ssh; then
        print_error "SSH 服务启动失败"
        exit 1
    fi
    local ssh_cfg="/etc/ssh/sshd_config"
    if [ -f "$ssh_cfg" ]; then
        backup_file "$ssh_cfg"
        if ! ensure_config "PermitRootLogin" "PermitRootLogin yes" "$ssh_cfg" || ! ensure_config "PasswordAuthentication" "PasswordAuthentication yes" "$ssh_cfg"; then
            print_error "SSH 配置更新失败"
            exit 1
        fi
        if ! systemctl restart ssh; then
            print_error "SSH 服务重启失败"
            exit 1
        fi
        print_success "SSH 配置已更新 (root 登录 + 密码认证)"
    fi

    if $PASSWORD_MATCH; then
        echo "root:$ROOT_PW" | chpasswd
        print_success "Root 密码已更新"
    fi

    print_info "正在扩容历史记录..."
    local profile="/etc/profile"
    ensure_config "HISTSIZE=" "HISTSIZE=99999" "$profile"
    ensure_config "HISTFILESIZE=" "HISTFILESIZE=99999" "$profile"

    if [ "$INSTALL_PANEL" = "casaos" ]; then
        print_info "正在安装 CasaOS..."
        if ! curl -fsSL https://get.casaos.io | bash; then
            print_error "CasaOS 安装失败"
            exit 1
        fi
        print_success "CasaOS 安装完成"
    elif [ "$INSTALL_PANEL" = "1panel" ]; then
        print_info "正在安装 1Panel..."
        if ! bash -c "$(curl -sSL https://resource.fit2cloud.com/1panel/package/v2/quick_start.sh)"; then
            print_error "1Panel 安装失败"
            exit 1
        fi
        print_success "1Panel 安装完成"
    fi

    mkdir -p "$TARGET_ROOT_HOME"
    print_success "工作目录已就绪: $TARGET_ROOT_HOME"

    print_info "正在清理系统缓存..."
    if ! apt clean || ! apt autoremove --purge -y; then
        print_warning "清理系统缓存失败，继续"
    fi
    rm -rf /var/cache/apt/archives/* /tmp/*

    print_success "系统初始化完成"

    # ========== Gotify 后置安装（合并通知 + 定时监控）==========
    local gotify_was_installed=false
    if [ -n "$GOTIFY_URL" ] && [ -n "$GOTIFY_TOKEN" ] && $INSTALL_GOTIFY; then
        module_install_gotify
        gotify_was_installed=true
    fi

    # ========== 执行报告 ==========
    echo ""
    print_separator
    echo "========================== 执行报告 =========================="
    echo "  系统初始化:         ✅ 完成"
    echo "  面板安装:           $([ "$INSTALL_PANEL" = "none" ] && echo "跳过" || echo "$INSTALL_PANEL ✅")"
    echo "  Root 密码:          $($PASSWORD_MATCH && echo "已设置 ✅" || echo "跳过")"
    echo "  Gotify 推送:        $($gotify_was_installed && echo "已安装 (通知 + 定时监控) ✅" || echo "跳过")"
    echo "=============================================================="

    if $gotify_was_installed; then
        echo ""
        print_info "验证 Gotify 推送..."
        local test_report_msg
        test_report_msg="**✅ 服务器初始化完成**\n\n\
- 服务器: \`$DEVICE_NAME\`\n\
- 时间: $(date '+%Y-%m-%d %H:%M:%S')\n\
- 状态: 初始化成功，通知与监控系统运行正常"
        if ! send_gotify "✅ 初始化完成 - $DEVICE_NAME" "$test_report_msg" 5 "$GOTIFY_URL" "$GOTIFY_TOKEN"; then
            print_error "Gotify 验证推送失败"
        fi
        echo ""
        print_info "首次监控已执行，之后每 2 小时整点自动推送"
    fi

    print_info "建议重新登录或运行 'source /etc/profile' 启用历史记录扩容"
}

# ====================== Module: SSH Key Deploy ======================
module_ssh_key() {
    print_title "SSH 密钥免密部署"

    # 远程服务器 IP/域名验证
    while true; do
        read -rp "请输入远程服务器 IP/域名 [默认: 127.0.0.1]: " REMOTE_HOST
        REMOTE_HOST=${REMOTE_HOST:-127.0.0.1}
        # 简单验证格式
        local re='^[a-zA-Z0-9.-]+$'
        if [[ "$REMOTE_HOST" =~ $re ]]; then
            break
        else
            print_error "IP/域名格式不正确，请重新输入"
        fi
    done

    # 远程用户名验证
    while true; do
        read -rp "请输入远程登录用户名 [默认: root]: " REMOTE_USER
        REMOTE_USER=${REMOTE_USER:-root}
        if [[ "$REMOTE_USER" =~ ^[a-zA-Z0-9_]+$ ]]; then
            break
        else
            print_error "用户名只能包含字母、数字或下划线"
        fi
    done

    # 端口验证
    while true; do
        read -rp "请输入远程 SSH 端口 [默认: 22]: " REMOTE_PORT
        REMOTE_PORT=${REMOTE_PORT:-22}
        if [[ "$REMOTE_PORT" =~ ^[0-9]+$ ]] && ((REMOTE_PORT >= 1 && REMOTE_PORT <= 65535)); then
            break
        else
            print_error "端口必须是 1-65535 之间的数字"
        fi
    done

    local key_file="$HOME/.ssh/id_rsa"
    if [ ! -f "$key_file" ]; then
        print_info "未检测到密钥对，正在生成 4096 位 RSA 密钥..."
        if ! ssh-keygen -t rsa -b 4096 -f "$key_file" -N ""; then
            print_error "密钥生成失败"
            exit 1
        fi
        print_success "密钥对已生成"
    else
        print_success "检测到现有密钥对，跳过生成"
    fi

    print_info "正在推送公钥至 ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PORT}..."
    if ! ssh-copy-id -i "$key_file.pub" -p "$REMOTE_PORT" "${REMOTE_USER}@${REMOTE_HOST}"; then
        print_error "公钥推送失败，请检查网络或密码"
        exit 1
    fi
    print_success "公钥已推送"

    print_info "正在验证免密登录..."
    if ssh -o BatchMode=yes -o ConnectTimeout=5 -p "$REMOTE_PORT" "${REMOTE_USER}@${REMOTE_HOST}" "id" > /dev/null 2>&1; then
        print_success "免密登录验证通过"
    else
        print_error "免密登录验证失败"
        exit 1
    fi
}

# ====================== Module: Install Gotify (通知 + 定时监控) ======================
module_install_gotify() {
    print_title "安装 Gotify 推送 (通知 + 定时监控)"

    if [ -z "$GOTIFY_URL" ] || [ -z "$GOTIFY_TOKEN" ]; then
        while true; do
            read -rp "请输入 Gotify API 端点 (如 https://gotify.example.com): " INPUT_URL
            read -rp "请输入 Gotify Token: " INPUT_TOKEN
            if [ -n "$INPUT_URL" ] && [ -n "$INPUT_TOKEN" ]; then
                GOTIFY_URL="$INPUT_URL"
                GOTIFY_TOKEN="$INPUT_TOKEN"
                break
            else
                print_error "Gotify URL 和 Token 都不能为空"
            fi
        done
        save_env
    fi

    # URL/Token 格式验证
    local re='^(https?://)?([a-zA-Z0-9.-]+)(:[0-9]+)?(/.*)?$'
    if [[ ! "$GOTIFY_URL" =~ $re ]]; then
        print_error "无效的 Gotify URL 格式: $GOTIFY_URL"
        exit 1
    fi

    check_root

    # -------- 1. 开机通知 --------
    local startup_script="/opt/gotify_startup.sh"
    local startup_svc="/etc/systemd/system/gotify-startup.service"
    local ABS_STARTUP_SCRIPT
    ABS_STARTUP_SCRIPT="$(cd "$(dirname "$startup_script")" && pwd)/$(basename "$startup_script")"
    if ! cat > "$startup_script" <<EOF
#!/bin/bash
curl -s -m 10 -X POST "${GOTIFY_URL}/message?token=${GOTIFY_TOKEN}" \
    -F "title=服务器状态：已上线" \
    -F "message=服务器 [ ${DEVICE_NAME} ] 已成功启动并联网。" \
    -F "priority=5"
EOF
    then
        print_error "启动通知脚本创建失败"
        exit 1
    fi
    if ! chmod +x "$startup_script"; then
        print_error "启动通知脚本权限设置失败"
        exit 1
    fi
    if ! cat > "$startup_svc" <<EOF
[Unit]
Description=Gotify Startup Notification for ${DEVICE_NAME}
After=network.target

[Service]
Type=oneshot
ExecStart=${ABS_STARTUP_SCRIPT}
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    then
        print_error "启动通知 systemd 服务创建失败"
        exit 1
    fi
    if ! systemctl daemon-reload; then
        print_error "系统服务缓存更新失败"
        exit 1
    fi
    if ! systemctl enable gotify-startup.service; then
        print_error "启动通知服务启用失败"
        exit 1
    fi
    print_success "开机通知已激活"

    # -------- 2. 关机通知 --------
    local shutdown_script="/opt/gotify_shutdown.sh"
    local shutdown_svc="/etc/systemd/system/gotify-shutdown.service"
    if ! cat > "$shutdown_script" <<EOF
#!/bin/bash
curl -s -m 10 -X POST "${GOTIFY_URL}/message?token=${GOTIFY_TOKEN}" \
    -F "title=服务器状态：离线通知" \
    -F "message=警告：服务器 [ ${DEVICE_NAME} ] 正在执行关机/重启操作。" \
    -F "priority=7"
EOF
    then
        print_error "关机通知脚本创建失败"
        exit 1
    fi
    if ! chmod +x "$shutdown_script"; then
        print_error "关机通知脚本权限设置失败"
        exit 1
    fi
    if ! cat > "$shutdown_svc" <<EOF
[Unit]
Description=Gotify Shutdown Notification for ${DEVICE_NAME}
DefaultDependencies=no
Before=shutdown.target reboot.target halt.target

[Service]
Type=oneshot
ExecStart=/bin/true
ExecStop=$shutdown_script
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    then
        print_error "关机通知 systemd 服务创建失败"
        exit 1
    fi
    if ! systemctl daemon-reload; then
        print_error "系统服务缓存更新失败"
        exit 1
    fi
    if ! systemctl enable gotify-shutdown.service; then
        print_error "关机通知服务启用失败"
        exit 1
    fi
    print_success "关机通知已激活"

    # -------- 3. 定时监控 (纯系统指标，不含 Tailscale/Peer) --------
    local ABS_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    local service_path="/etc/systemd/system/gotify-report.service"
    local timer_path="/etc/systemd/system/gotify-report.timer"
    if ! cat > "$service_path" <<SERVICE
[Unit]
Description=Gotify System Report for ${DEVICE_NAME}
After=network.target

[Service]
Type=oneshot
ExecStart=${ABS_SCRIPT_DIR}/deploy.sh --gotify-report \\
    --Device "${DEVICE_NAME}" \\
    --GotifyUrl "${GOTIFY_URL}" \\
    --GotifyToken "${GOTIFY_TOKEN}"
SERVICE
    then
        print_error "系统报告服务创建失败"
        exit 1
    fi

    if ! cat > "$timer_path" <<TIMER
[Unit]
Description=Run Gotify System Report every 2 hours (on the hour)

[Timer]
OnCalendar=*-*-* 0:00/2:00
Persistent=true

[Install]
WantedBy=timers.target
TIMER
    then
        print_error "系统报告定时器创建失败"
        exit 1
    fi

    if ! systemctl daemon-reload; then
        print_error "系统服务缓存更新失败"
        exit 1
    fi

    if ! systemctl enable --now gotify-report.timer; then
        print_error "系统报告定时器注册失败"
        exit 1
    fi
    print_success_with_log "定时监控已注册，每 2 小时执行一次"

    # 立即执行首轮
    print_info "首次运行系统监控..."
    if ! systemctl start gotify-report.service; then
        print_error "首次运行系统监控服务启动失败"
        exit 1
    fi
    sleep 2
    print_success "首次监控已触发，下次将在整点推送"
    echo ""
    print_info "定时器排程:"
    systemctl list-timers | grep gotify-report || print_info "无计时器信息"

    print_success "Gotify 推送安装完成"
    print_success_with_log "已启用: 开机通知 (gotify-startup.service)"
    print_success_with_log "已启用: 关机预警 (gotify-shutdown.service)"
    print_success_with_log "已启用: 定时监控 (gotify-report.timer, 每 2h 整点)"
}

# ====================== Module: Gotify System Report (纯指标，无 Peer) ======================
module_gotify_report_run() {
    print_title "Gotify 系统报告"

    if [ -z "$GOTIFY_URL" ] || [ -z "$GOTIFY_TOKEN" ]; then
        print_error "请先设定 Gotify URL 和 Token"
        exit 1
    fi

    print_info "正在采集系统指标..."

    # Uptime
    local days=0 hours=0 mins=0
    if [ -r /proc/uptime ]; then
        local uptime_seconds
        read -r uptime_seconds _ < /proc/uptime
        days=$(awk "BEGIN {print int($uptime_seconds / 86400)}")
        hours=$(awk "BEGIN {print int(($uptime_seconds % 86400) / 3600)}")
        mins=$(awk "BEGIN {print int(($uptime_seconds % 3600) / 60)}")
    fi

    # CPU & Memory
    local load_1min total_mem used_mem
    load_1min=$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo "N/A")
    read -r total_mem used_mem _ < <(free -m | awk '/Mem:/ {print $2, $3, $4}') 2>/dev/null || { total_mem=0; used_mem=0; }

    # Disk
    local disk_total disk_used disk_free
    read -r disk_total disk_used disk_free _ < <(df -BG / | awk 'NR==2 {print $2, $3, $4}') 2>/dev/null || { disk_total="N/A"; disk_used="N/A"; disk_free="N/A"; }

    # Top 3 进程
    local top3="N/A"
    top3=$(ps -eo comm=,rss= --sort=-rss 2>/dev/null | awk '{size=$2/1024; if (size > 0) printf "%s (%.1fMB), ", $1, size}' | head -c -2)
    [ -z "$top3" ] && top3="N/A"

    # Public IP
    local public_ip="N/A"
    for src in "https://api.ipify.org" "https://ifconfig.me" "https://icanhazip.com"; do
        public_ip=$(curl -s --max-time 5 "$src" 2>/dev/null | grep -Eo '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')
        [ -n "$public_ip" ] && break
    done
    [ -z "$public_ip" ] && public_ip="N/A"

    local local_ip
    local_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    [ -z "$local_ip" ] && local_ip="N/A"

    local ts_ip="N/A"
    command -v tailscale &>/dev/null && ts_ip=$(tailscale ip -4 2>/dev/null || echo "N/A")

    local message
    message=$(cat <<MSGBODY
**伺服器 [ ${DEVICE_NAME} ] 监控报告**
===================================

**运行时间:** ${days}天 ${hours}时 ${mins}分
**系统负载:** ${load_1min}
**内存:** ${used_mem}MB / ${total_mem}MB
**磁盘 (/):** ${disk_used} / ${disk_total} (剩余: ${disk_free})
**Top 3 进程:** ${top3}

**Public IP:** ${public_ip}
**Local IP:** ${local_ip}
**Tailscale IP:** ${ts_ip}

_$(date '+%Y-%m-%d %H:%M:%S')_
MSGBODY
)

    local json_payload
    json_payload=$(jq -n \
        --arg title "伺服器 [ ${DEVICE_NAME} ] 运行报告" \
        --arg msg "$message" \
        '{title: $title, message: $msg, priority: 3,
          extras: {"client::display": {"contentType": "text/markdown"}}}' 2>/dev/null)

    if [ -z "$json_payload" ]; then
        print_info "jq 不可用，使用 form-data 方式发送..."
        curl -s -X POST "${GOTIFY_URL}/message?token=${GOTIFY_TOKEN}" \
            -F "title=伺服器 [ ${DEVICE_NAME} ] 运行报告" \
            -F "message=$message" \
            -F "priority=3" > /dev/null 2>&1
    else
        curl -s -X POST "${GOTIFY_URL}/message?token=${GOTIFY_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "$json_payload" > /dev/null 2>&1
    fi

    if [ $? -eq 0 ]; then
        print_success "监控报告已推送到 Gotify"
    else
        print_error "Gotify 推送失败"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Error: Failed to send Gotify notification" >> "$SCRIPT_DIR/report_error.log"
    fi
}

# ====================== Module: Lid Sleep Disable ======================
module_lid_sleep() {
    print_title "禁用笔记本合盖睡眠"
    check_root

    if ! ls /sys/class/power_supply/BAT* > /dev/null 2>&1; then
        print_info "未检测到电池设备，可能是台式机或服务器"
        if [ -t 0 ]; then
            read -rp "是否继续配置？(y/n, 默认 n): " confirm
            confirm=${confirm:-n}
            if [[ "$confirm" != [yY] ]]; then
                print_info "已取消"
                exit 0
            fi
        else
            print_info "非交互模式，跳过合盖配置"
            return
        fi
    fi

    local config_file="/etc/systemd/logind.conf"
    if [ ! -f "$config_file" ]; then
        print_error "$config_file 不存在"
        exit 1
    fi

    backup_file "$config_file"
    ensure_config_logind "HandleSuspendKey" "HandleSuspendKey=ignore" "$config_file"
    ensure_config_logind "HandleHibernateKey" "HandleHibernateKey=ignore" "$config_file"
    ensure_config_logind "HandleLidSwitch" "HandleLidSwitch=ignore" "$config_file"
    ensure_config_logind "HandleLidSwitchExternalPower" "HandleLidSwitchExternalPower=ignore" "$config_file"
    ensure_config_logind "HandleLidSwitchDocked" "HandleLidSwitchDocked=ignore" "$config_file"

    if ! systemctl restart systemd-logind; then
        print_error "重启 systemd-logind 失败"
        exit 1
    fi
    print_success "配置已生效"

    local failed=false
    for key in HandleSuspendKey HandleHibernateKey HandleLidSwitch HandleLidSwitchExternalPower HandleLidSwitchDocked; do
        if grep -q "^${key}=ignore" "$config_file"; then
            print_success "  ${key}=ignore"
        else
            print_error "  ${key} 配置失败"
            failed=true
        fi
    done
    $failed && exit 1 || print_success "合盖配置全部通过"
}

# ====================== Module: Extend LVM Root ======================
module_extend_lvm() {
    print_title "LVM 根分区自动扩容"
    check_root

    local deps=(lvdisplay vgs lvextend resize2fs xfs_growfs)
    local missing=()
    for cmd in "${deps[@]}"; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        print_error "缺少 LVM 工具: ${missing[*]}，请先安装 lvm2"
        exit 1
    fi
    print_success "LVM 工具链检查通过"

    local root_device
    root_device=$(df -hP | grep ' /$' | awk '{print $1}')
    if [ -z "$root_device" ]; then
        print_error "未找到根挂载点"
        exit 1
    fi

    if ! lvdisplay "$root_device" &>/dev/null; then
        print_error "根分区不是 LVM 逻辑卷 (当前: $root_device)，此脚本仅支持 LVM"
        exit 1
    fi
    print_success "检测到 LVM 根分区: $root_device"

    local vg_name
    vg_name=$(lvdisplay "$root_device" | grep "VG Name" | awk '{print $3}')
    print_success "卷组名称: $vg_name"

    local free_space
    free_space=$(vgs --noheadings --units g -o vg_free "$vg_name" | awk '{gsub(/g/,""); print $1}')
    if awk "BEGIN {exit !($free_space <= 0.01)}"; then
        print_error "卷组无可用空间 (剩余: ${free_space}G)"
        exit 1
    fi
    print_success "卷组可用空间: ${free_space}G"

    local fs_type
    fs_type=$(df -T | grep "$root_device" | awk '{print $2}')
    case "$fs_type" in
        ext4|xfs) print_success "文件系统: $fs_type" ;;
        *) print_error "不支持的文件系统: $fs_type (仅 ext4/xfs)" ; exit 1 ;;
    esac

    local bk_dir="/root/lvm_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$bk_dir"
    vgcfgbackup -f "$bk_dir/vg_${vg_name}.cfg" "$vg_name" 2>/dev/null || true
    lvdisplay > "$bk_dir/lv_before.txt" 2>/dev/null || true
    vgs > "$bk_dir/vg_before.txt" 2>/dev/null || true
    print_success "LVM 配置已备份至: $bk_dir"

    if ! lvextend -l +100%FREE "$root_device"; then
        print_error "逻辑卷扩展失败"
        exit 1
    fi
    print_success "逻辑卷已扩展"

    case "$fs_type" in
        ext4) resize2fs "$root_device" && print_success "文件系统已扩容" || print_error "resize2fs 失败" ;;
        xfs)  xfs_growfs / && print_success "文件系统已扩容" || print_error "xfs_growfs 失败" ;;
    esac

    print_info "扩容后信息:"
    lvdisplay "$root_device" | grep -E "LV Size|LV Name"
    echo ""
    df -h /
    print_success "LVM 扩容完成"
}

# ====================== Module: System Info ======================
module_sys_info() {
    print_title "系统信息诊断"

    echo -e "\n${BLUE}===================== 核心硬件概况 =====================${NC}"
    echo "CPU 状态:"
    lscpu | grep -E "Architecture|Model name|CPU MHz|Thread\(s\) per core|Core\(s\) per socket|Socket\(s\)|CPU\(s\)"
    echo -e "\n内存负载:"
    free -h | grep Mem
    echo -e "\n磁盘分区:"
    df -h | grep -E "^/dev/"
    echo -e "\n网络链路:"
    ip addr show | grep -E "inet|ether"

    echo -e "\n${BLUE}===================== 操作系统环境 =====================${NC}"
    echo "系统发行版:"
    lsb_release -a 2>/dev/null || cat /etc/os-release | grep "PRETTY_NAME"
    echo -e "\n内核版本:"
    uname -a
    echo -e "\n运行时长:"
    uptime -p
    echo -e "\n负载表现:"
    uptime
    echo -e "\n活跃会话:"
    w

    echo -e "\n${BLUE}===================== 活跃服务监控 =====================${NC}"
    systemctl list-units --type=service --state=running | grep -v "@" | head -n 15
    echo ""
}

# ====================== Module: Tailscale Install ======================
module_install_tailscale() {
    print_title "Tailscale 安装与配置"

    if command -v tailscale &>/dev/null; then
        local ts_ver
        ts_ver=$(tailscale version 2>/dev/null | head -1)
        print_info "检测到 Tailscale 已安装 (版本: ${ts_ver:-unknown})"
        echo ""
        read -rp "是否重新安装/更新至最新版? (y/n, 默认 n): " reinstall
        if [[ "$reinstall" != [yY] ]]; then
            if ! systemctl is-active tailscaled &>/dev/null; then
                systemctl enable tailscaled
                systemctl start tailscaled
            else
                systemctl enable tailscaled 2>/dev/null || true
            fi
            tailscale set --auto-update=true 2>/dev/null || true
            print_success "自动更新已确保开启"
            echo ""
            print_info "当前 Tailscale 状态:"
            tailscale status 2>/dev/null || print_info "尚未认证，请执行: tailscale up"
            return
        fi
    fi

    print_info "正在安装 Tailscale (官方脚本)..."
    if ! curl -fsSL https://tailscale.com/install.sh | sh; then
        print_error "Tailscale 安装失败"
        exit 1
    fi
    print_success "Tailscale 安装完成"

    if ! systemctl enable tailscaled; then
        print_error "tailscaled 启动失败"
        exit 1
    fi
    if ! systemctl start tailscaled; then
        print_error "tailscaled 启动失败"
        exit 1
    fi
    print_success "tailscaled 已开机自启并运行中"

    print_info "正在启用自动更新..."
    tailscale set --auto-update=true 2>/dev/null || true
    print_success "自动更新已启用 (Tailscale 将在后台自动升级)"

    echo ""
    print_info "Tailscale 需要认证才能连接到您的 tailnet"
    print_info "执行以下命令完成认证:"
    echo ""
    echo "    tailscale up"
    echo ""
    read -rp "是否立即执行 tailscale up? (y/n, 默认 y): " do_up
    do_up=${do_up:-y}
    if [[ "$do_up" == [yY] ]]; then
        tailscale up
        print_success "Tailscale 认证流程已完成"
    else
        print_info "稍后可手动执行 'tailscale up' 完成认证"
    fi

    echo ""
    print_info "Tailscale 状态:"
    tailscale status 2>/dev/null || true

    local ts_ip
    ts_ip=$(tailscale ip -4 2>/dev/null || true)
    if [ -n "$ts_ip" ] && [ -z "$TARGET_PEER_IP" ]; then
        echo ""
        read -rp "是否将此 Tailscale IP ($ts_ip) 设为 Tailscale Peer 连通性监控的目标 IP? (y/n): " set_peer
        if [[ "$set_peer" == [yY] ]]; then
            TARGET_PEER_IP="$ts_ip"
            save_env
            print_success "目标 Tailscale Peer IP 已设为: $ts_ip"
        fi
    fi
}

# ====================== Module: Tailscale Peer Monitor (连通性 + 紧急重启) ======================

# 安全停止所有 Docker 容器（重啟前呼叫）
safe_stop_docker() {
    if ! command -v docker &>/dev/null; then
        return
    fi
    local running
    running=$(docker ps -q 2>/dev/null)
    if [ -z "$running" ]; then
        print_info "Docker: 无运行中的容器"
        return
    fi
    local count
    count=$(echo "$running" | wc -l)
    print_info "检测到 $count 个运行中的 Docker 容器，正在安全停止..."
    docker stop $running > /dev/null 2>&1
    print_success "Docker 容器已全部停止"
}

module_tailscale_peer_monitor_run() {
    print_title "Tailscale Peer 连通性监控"

    if [ -z "$GOTIFY_URL" ] || [ -z "$GOTIFY_TOKEN" ]; then
        print_error "请先设定 Gotify URL 和 Token"
        exit 1
    fi

    print_info "检查 Tailscale 状态..."

    if ! command -v tailscale &>/dev/null; then
        print_error "Tailscale 未安装，无法执行 Peer 监控"
        print_error "Tailscale 未安装，无法执行 Tailscale Peer 监控"
        exit 1
    fi

    # 守护进程检查
    local ts_ok=false
    if ! tailscale status &>/dev/null; then
        print_info "Tailscale 未运行，正在重启..."
        systemctl restart tailscaled
        sleep 5
        if tailscale status &>/dev/null; then
            print_success "Tailscaled 已恢复"
            ts_ok=true
        else
            print_error "Tailscaled 无法重启"
        fi
    else
        print_success "Tailscale 运行正常"
        ts_ok=true
    fi

    # 自动更新
    tailscale update --yes &>/dev/null || true

    # Tailscale Peer 连通性测试
    if [ -n "$TARGET_PEER_IP" ]; then
        print_info "正在检测 Tailscale Peer $TARGET_PEER_IP..."
        if ping -c 3 -W 5 "$TARGET_PEER_IP" &>/dev/null; then
        print_success "Tailscale Peer 连通正常"
        else
        print_error "Tailscale Peer $TARGET_PEER_IP 不可达，触发紧急流程"

            local emergency_msg="**紧急：服务器 ${DEVICE_NAME} 即将重启**\n\n原因：Tailscale Peer ${TARGET_PEER_IP} 不可达\n时间：$(date '+%Y-%m-%d %H:%M:%S')"
            send_gotify "紧急警报" "$emergency_msg" 10 "$GOTIFY_URL" "$GOTIFY_TOKEN"

            safe_stop_docker

            print_info "10 秒后强制重启 (内核级)..."
            sleep 10
            reboot --force --force 2>/dev/null || reboot -ff 2>/dev/null || echo b > /proc/sysrq-trigger
        fi
    else
        print_info "未设定 Tailscale Peer IP，跳过连通性测试"
    fi
}

module_tailscale_peer_monitor_install() {
    print_title "安装 Tailscale Peer 连通性监控 (定时)"

    if [ -z "$GOTIFY_URL" ] || [ -z "$GOTIFY_TOKEN" ]; then
        read -rp "请输入 Gotify API 端点 (如 https://gotify.example.com): " GOTIFY_URL
        read -rp "请输入 Gotify Token: " GOTIFY_TOKEN
    fi
    if [ -z "$GOTIFY_URL" ] || [ -z "$GOTIFY_TOKEN" ]; then
        print_error "Gotify URL 和 Token 为必填项"
        exit 1
    fi
    if [ -z "$TARGET_PEER_IP" ]; then
        read -rp "请输入要监控的 Tailscale Peer IP: " TARGET_PEER_IP
    fi
    if [ -z "$TARGET_PEER_IP" ]; then
        print_error "Tailscale Peer IP 为必填项"
        exit 1
    fi

    check_root

    local service_path="/etc/systemd/system/tailscale-peer-monitor.service"
    local timer_path="/etc/systemd/system/tailscale-peer-monitor.timer"

    cat > "$service_path" <<UNIT
[Unit]
    Description=Tailscale Peer Monitor for ${DEVICE_NAME}
After=network.target tailscaled.service

[Service]
Type=oneshot
    ExecStart=${ABS_SCRIPT_DIR}/deploy.sh --tailscale-peer-monitor \
    --Device "${DEVICE_NAME}" \\
    --GotifyUrl "${GOTIFY_URL}" \\
    --GotifyToken "${GOTIFY_TOKEN}" \\
    --PeerIP "${TARGET_PEER_IP}"
UNIT

    cat > "$timer_path" <<TIMER
[Unit]
Description=Run Tailscale Peer Monitor every 2 hours (on the hour)

[Timer]
OnCalendar=*-*-* 0:00/2:00
Persistent=true

[Install]
WantedBy=timers.target
TIMER

    if ! systemctl daemon-reload; then
        print_error "系统服务缓存更新失败"
        exit 1
    fi

    if ! systemctl enable --now tailscale-peer-monitor.timer; then
        print_error "定时器注册失败"
        exit 1
    fi
    print_success "Tailscale Peer 监控已注册，每 2 小时执行一次"
    print_info "首次运行 Tailscale Peer 监控..."
    systemctl start tailscale-peer-monitor.service
    sleep 2
    print_success "首次 Tailscale Peer 监控已触发"
    echo ""
    print_info "定时器排程:"
    systemctl list-timers | grep tailscale-peer-monitor || true
}

# ====================== Module: System Diagnostic ======================
module_diagnostic() {
    print_title "系统诊断"

    # -------- 1. Gotify 推送测试 --------
    if [ -n "$GOTIFY_URL" ] && [ -n "$GOTIFY_TOKEN" ]; then
        print_info "测试 Gotify 推送..."
        local test_msg
        test_msg="**系统诊断 - Gotify 推送测试**\n\n\
- 服务器: \`$DEVICE_NAME\`\n\
- 时间: $(date '+%Y-%m-%d %H:%M:%S')\n\
- 状态: ✅ 推送正常\n\n\
*若收到本条消息，说明 Gotify 配置正确*"
        send_gotify "🧪 诊断测试 - $DEVICE_NAME" "$test_msg" 5 "$GOTIFY_URL" "$GOTIFY_TOKEN"
    else
        print_error "Gotify 未配置，跳过推送测试（选单选项 [10] 配置）"
    fi

    # -------- 2. Tailscale + Peer 状态 --------
    echo ""
    print_separator
    echo "--- Tailscale 状态 ---"
    if command -v tailscale &>/dev/null; then
        local ts_ver
        ts_ver=$(tailscale version 2>/dev/null | head -1)
        print_info "版本: ${ts_ver:-unknown}"
        if tailscale status &>/dev/null; then
            print_success "守护进程运行正常"
            tailscale status 2>/dev/null | head -5
        else
            print_error "守护进程未运行"
            print_info "执行 'systemctl start tailscaled' 启动"
        fi
    else
        print_info "Tailscale 未安装"
    fi

    # -------- 3. Tailscale Peer 连通性测试 + 重启模拟 --------
    echo ""
    print_separator
    echo "--- Tailscale Peer 连通性测试 ---"
    if [ -z "$TARGET_PEER_IP" ]; then
        print_info "未设定 Peer IP，跳过连通性测试（选单选项 [11] 配置）"
    elif ! command -v tailscale &>/dev/null; then
        print_info "Tailscale 未安装，跳过连通性测试"
    elif ! command -v ping &>/dev/null; then
        print_error "ping 不可用，跳过连通性测试"
    else
        print_info "正在检测 Peer $TARGET_PEER_IP..."
        if ping -c 3 -W 5 "$TARGET_PEER_IP" &>/dev/null; then
            print_success "Peer $TARGET_PEER_IP 连通正常"
        else
            print_error "Peer $TARGET_PEER_IP 不可达"
            echo ""
            print_info "Peer 监控检测到不可达时会执行以下流程:"
            echo "  ① 发送 Priority 10 紧急通知至 Gotify"
            echo "  ② 安全停止所有 Docker 容器"
            echo "  ③ 执行三级内核重启链"

            if [ -n "$GOTIFY_URL" ] && [ -n "$GOTIFY_TOKEN" ]; then
                print_info "正在发送测试紧急通知..."
                local emergency_msg
                emergency_msg="**⚠️ 连通性测试 - 模拟紧急警报**\n\n\
- 服务器: \`$DEVICE_NAME\`\n\
- Peer: \`$TARGET_PEER_IP\`\n\
- 状态: 🔴 不可达\n\
- 时间: $(date '+%Y-%m-%d %H:%M:%S')\n\n\
*此为模拟测试，非真实紧急情况*"
                send_gotify "⚠️ 模拟紧急警报" "$emergency_msg" 10 "$GOTIFY_URL" "$GOTIFY_TOKEN"
            fi

            echo ""
            print_info "是否执行重启效果模拟？"
            echo "  [1] 仅显示命令（不重启）"
            echo "  [2] 确认后真实重启"
            echo "  [其他] 取消"
            read -rp "  请选择 [1/2]: " sim_choice
            case "$sim_choice" in
                1)
                    echo ""
                    print_info "模拟重启流程:"
                    echo "  ① 紧急通知已发送 (Priority 10)"
                    echo "  ② Docker 容器已安全停止"
                    echo "  ③ 执行: reboot --force --force"
                    echo "  ④ 降级: reboot -ff"
                    echo "  ⑤ 最终: echo b > /proc/sysrq-trigger"
                    print_success "模拟完成（未实际重启）"
                    ;;
                2)
                    echo ""
                    print_warning "即将执行真实重启！"
                    read -rp "确认强制重启? (y/n): " confirm
                    if [[ "$confirm" == [yY] ]]; then
                        print_info "安全停止 Docker 容器..."
                        safe_stop_docker
                        print_info "10 秒后强制重启..."
                        sleep 10
                        reboot --force --force 2>/dev/null || reboot -ff 2>/dev/null || echo b > /proc/sysrq-trigger
                    else
                        print_info "已取消重启"
                    fi
                    ;;
                *)
                    print_info "已取消"
                    ;;
            esac
        fi
    fi

    echo ""
    print_success "系统诊断完成"
}

# ====================================================================
#                            MENU
# ====================================================================
show_menu() {
    clear
    echo ""
    echo "============================================"
    echo "     PVE-LXC-INIT  部 署 管 理 工 具"
    echo "============================================"
    echo "  机器名称 : $DEVICE_NAME"
    echo "  Gotify   : $([ -n "$GOTIFY_URL" ] && echo "已设定" || echo "未设定")"
    echo "  Tailscale Peer: ${TARGET_PEER_IP:-(未配置)}"
    echo "============================================"
    echo ""
    echo "-- 常用部署 --"
    echo "  [1] 一键初始化服务器"
    echo "  [2] 安装 Gotify (通知 + 定时监控)"
    echo ""
    echo "-- Tailscale --"
    echo "  [3] 安装 Tailscale"
    echo "  [4] 配置 Tailscale Peer 连通性监控"
    echo ""
    echo "-- 辅助工具 --"
    echo "  [5] SSH 密钥免密部署"
    echo "  [6] 系统信息查询"
    echo "  [7] LVM 根分区扩容"
    echo "  [8] 禁用笔记本合盖睡眠"
    echo ""
    echo "-- 系统设置 --"
    echo "  [9] 修改机器名称"
    echo " [10] 修改 Gotify URL/Token"
    echo " [11] 修改 Tailscale Peer IP"
    echo " [12] 系统诊断"
    echo ""
    echo "  [0] 退出"
    echo "--------------------------------------------"
}

validate_menu_input() {
    local max_choice=$1
    local choice="$2"

    if [[ "$choice" =~ ^[0-9]+$ ]]; then
        if (( choice > max_choice )) || (( choice < 0 )); then
            print_error "无效选项，请输入 0-$max_choice"
            return 1
        fi
        echo "$choice"
        return 0
    else
        print_error "请输入数字"
        return 1
    fi
}

menu_loop() {
    while true; do
        show_menu
        read -rp "   请输入选项编号 [0-12]: " choice
        echo ""

        if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
            print_error "请输入数字"
            sleep 1
            continue
        fi

        case "$choice" in
            1)  module_init_server ;;
            2)  module_install_gotify ;;
            3)  module_install_tailscale ;;
            4)  module_peer_monitor_install ;;
            5)  module_ssh_key ;;
            6)  module_sys_info ;;
            7)  module_extend_lvm ;;
            8)  module_lid_sleep ;;
            9)
                read -rp "请输入新的机器名称: " DEVICE_NAME
                DEVICE_NAME=${DEVICE_NAME:-$(hostname)}
                save_env
                print_success "当前机器名称已设为: $DEVICE_NAME"
                if systemctl is-active gotify-report.timer &>/dev/null; then
                    echo ""
                    read -rp "检测到已安装 Gotify 定时监控，是否重新生成脚本? (y/n): " yn
                    if [[ "$yn" == [yY] ]]; then
                        module_install_gotify
                        print_success "Gotify 推送已更新为新名称: $DEVICE_NAME"
                    fi
                fi
                if systemctl is-active tailscale-peer-monitor.timer &>/dev/null; then
                    echo ""
                    read -rp "检测到已安装 Tailscale Peer 监控，是否重新生成脚本? (y/n): " yn2
                    if [[ "$yn2" == [yY] ]]; then
                        module_tailscale_peer_monitor_install
                        print_success "Tailscale Peer 监控已更新为新名称: $DEVICE_NAME"
                    fi
                fi
                ;;
            10)
                read -rp "请输入 Gotify URL (如 https://gotify.example.com): " GOTIFY_URL
                read -rp "请输入 Gotify Token: " GOTIFY_TOKEN
                if [ -n "$GOTIFY_URL" ]; then
                    save_env
                    print_success "Gotify 配置已更新"
                fi
                ;;
            11)
                read -rp "请输入 Peer IP: " TARGET_PEER_IP
                if [ -n "$TARGET_PEER_IP" ]; then
                    save_env
                    print_success "Peer IP 已更新为: $TARGET_PEER_IP"
                fi
                ;;
            12) module_diagnostic ;;
            0)
                print_info "感谢使用，再见"
                exit 0
                ;;
            *)
                print_error "无效选项，请重新输入"
                sleep 1
                ;;
        esac
        echo ""
        print_info "按 Enter 键返回菜单..."
        read -r
    done
}

# ====================================================================
#                      ARGUMENT PARSING
# ====================================================================
usage() {
    echo "用法: ./deploy.sh [选项]"
    echo ""
    echo "选项:"
    echo "  (无参数)              显示交互菜单"
    echo "  --init                一键初始化服务器"
    echo "  --ssh-key             SSH 密钥免密部署"
    echo "  --gotify              安装 Gotify (通知 + 定时监控)"
    echo "  --gotify-report       运行一次系统监控报告"
    echo "  --tailscale-install   安装 Tailscale (含自动更新)"
    echo "  --tailscale-peer-monitor        运行一次 Tailscale Peer 连通性监控"
    echo "  --tailscale-peer-monitor-install 安装 Tailscale Peer 连通性定时监控"
    echo "  --lid-sleep           禁用笔记本合盖睡眠"
    echo "  --extend-lvm          LVM 根分区扩容"
    echo "  --sys-info            系统信息查询"
    echo ""
    echo "参数:"
    echo "  --Device <名称>      指定机器名称 (默认: hostname)"
    echo "  --GotifyUrl <URL>    Gotify 服务地址"
    echo "  --GotifyToken <KEY>  Gotify Token"
    echo "  --PeerIP <IP>        Peer IP"
    echo "  --Timezone <时区>    时区 (如 Asia/Seoul)"
    echo ""
    echo "示例:"
    echo "  ./deploy.sh --gotify --Device MyServer --GotifyUrl https://gotify.example.com --GotifyToken abc"
    echo "  ./deploy.sh --tailscale-peer-monitor-install --Device MyServer --GotifyUrl https://gotify.example.com --GotifyToken abc --PeerIP 100.114.252.115"
    exit 0
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --init)                 MODE="init"; shift ;;
            --ssh-key)              MODE="ssh-key"; shift ;;
            --gotify)               MODE="gotify"; shift ;;
            --gotify-report)        MODE="gotify-report"; shift ;;
            --tailscale-install)    MODE="tailscale-install"; shift ;;
            --tailscale-peer-monitor)         MODE="tailscale-peer-monitor"; shift ;;
            --tailscale-peer-monitor-install) MODE="tailscale-peer-monitor-install"; shift ;;
            --lid-sleep)            MODE="lid-sleep"; shift ;;
            --extend-lvm)           MODE="extend-lvm"; shift ;;
            --sys-info)             MODE="sys-info"; shift ;;
            --Device)               DEVICE_NAME="$2"; shift 2 ;;
            --GotifyUrl)            GOTIFY_URL="$2"; shift 2 ;;
            --GotifyToken)          GOTIFY_TOKEN="$2"; shift 2 ;;
            --PeerIP)               TARGET_PEER_IP="$2"; shift 2 ;;
            --Timezone)             TARGET_TIMEZONE="$2"; shift 2 ;;
            -h|--help)              usage ;;
            *)                      print_error "未知参数: $1"; usage ;;
        esac
    done
}

# ====================================================================
#                   VERSION CHECK (STARTUP)
# ====================================================================
check_update() {
    # 僅互動模式執行
    if [ ! -t 0 ]; then return; fi

    command -v git &>/dev/null || return
    git rev-parse --git-dir &>/dev/null || return

    local remote_url
    remote_url=$(git config --get remote.origin.url 2>/dev/null || true)
    if [ -z "$remote_url" ]; then return; fi

    local local_commit remote_commit
    local_commit=$(git rev-parse HEAD 2>/dev/null || echo "")
    [ -z "$local_commit" ] && return

    print_info "正在检查更新..."
    remote_commit=$(git ls-remote origin HEAD 2>/dev/null | awk '{print $1}')
    if [ -z "$remote_commit" ]; then
        print_info "无法连接远程仓库，跳过更新检查"
        return
    fi

    if [ "$local_commit" = "$remote_commit" ]; then
        print_success "已是最新版本 (${local_commit:0:8})"
        return
    fi

    echo ""
    print_warning "发现新版本！"
    echo "  本地: ${local_commit:0:8}"
    echo "  远程: ${remote_commit:0:8}"
    echo ""
    read -rp "是否强制拉取 GitHub 最新代码? (y/n, 默认 n): " do_update
    if [[ "$do_update" == [yY] ]]; then
        print_info "正在强制同步远程代码..."
        git fetch origin --force
        git reset --hard origin/main
        print_success "已更新至最新版本: ${remote_commit:0:8}"
        print_info "请重新运行脚本以应用更新"
        exit 0
    fi
    echo ""
}

# ====================================================================
#                           MAIN
# ====================================================================
main() {
    if [ ! -t 0 ]; then
        if [ $# -eq 0 ]; then
            print_error "非交互模式需要指定 --flag 参数"
            usage
        fi
        parse_args "$@"
    elif [ $# -gt 0 ]; then
        parse_args "$@"
    else
        check_update
        menu_loop
        return
    fi

    case "$MODE" in
        init)                 module_init_server ;;
        ssh-key)              module_ssh_key ;;
        gotify)               module_install_gotify ;;
        gotify-report)        module_gotify_report_run ;;
        tailscale-install)    module_install_tailscale ;;
        tailscale-peer-monitor)         module_tailscale_peer_monitor_run ;;
        tailscale-peer-monitor-install) module_tailscale_peer_monitor_install ;;
        lid-sleep)            module_lid_sleep ;;
        extend-lvm)           module_extend_lvm ;;
        sys-info)             module_sys_info ;;
        *)                    print_error "未指定有效模块"; usage ;;
    esac
}

main "$@"
