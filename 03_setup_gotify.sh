#!/bin/bash
# ==============================================================================
# [DEPRECATED] 此脚本已整合至 deploy.sh
# 建议使用: ./deploy.sh --gotify (需 root 身份)
# 此文件保留以确保向后兼容，不再主动维护新功能。
# ==============================================================================

# ==============================================================================
# Project: pve-lxc-init
# Script: 03_setup_gotify.sh
# Description: Modular setup for multiple Gotify notification services:
#              1. Startup notification
#              2. Shutdown notification
#              3. Daily heartbeat @ 03:00 (Uptime & Load info)
# Compatible Platforms: Debian/Ubuntu (Systemd based)
# ==============================================================================

# ---------------------------- 日志与输出配置 ----------------------------

print_info() {
    echo -e "\033[32m[INFO]\033[0m $1"
}

print_success() {
    echo -e "\033[36m[SUCCESS]\033[0m $1"
}

print_error() {
    echo -e "\033[31m[ERROR]\033[0m $1"
}

check_command() {
    if [ $? -ne 0 ]; then
        print_error "$1"
        exit 1
    else
        print_success "$2"
    fi
}

# ---------------------------- 环境校验 ----------------------------

check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "权限不足：请使用 root 身份运行此脚本 (./03_setup_gotify.sh)"
        exit 1
    fi
}

# ---------------------------- 配置收集 ----------------------------

GOTIFY_URL=""
GOTIFY_TOKEN=""
SERVER_NAME=""

module_collect_config() {
    echo -e "\n\033[1;34m>>> 正在收集 Gotify 推送服务参数\033[0m"
    echo "------------------------------------------------"
    read -rp "请输入 Gotify API 端点 (如 https://gotify.example.com): " GOTIFY_URL
    read -rp "请输入 Gotify 访问 Token: " GOTIFY_TOKEN
    read -rp "请输入本机的服务器标识名称 (SERVER_NAME): " SERVER_NAME

    if [[ -z "$GOTIFY_URL" || -z "$GOTIFY_TOKEN" || -z "$SERVER_NAME" ]]; then
        print_error "参数缺失，所有项均为必填。"
        exit 1
    fi
}

# ---------------------------- 核心核心模块 ----------------------------

# 1. 设置开机通知
module_setup_startup_notify() {
    local script_path="/opt/gotify_startup.sh"
    local service_path="/etc/systemd/system/gotify-startup.service"

    print_info "正在部署：开机自启通知模块..."

    # 生成执行脚本
    cat > "$script_path" <<EOF
#!/bin/bash
curl -X POST "${GOTIFY_URL}/message?token=${GOTIFY_TOKEN}" \\
    -F "title=服务器状态：已上线" \\
    -F "message=服务器 [ ${SERVER_NAME} ] 已成功启动并联网。" \\
    -F "priority=5"
EOF
    chmod +x "$script_path"

    # 生成 systemd service
    cat > "$service_path" <<EOF
[Unit]
Description=Gotify Startup Notification
After=network.target

[Service]
ExecStart=$script_path
Type=oneshot
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable gotify-startup.service
    print_success "开机通知已激活。"
}

# 2. 设置关机通知
module_setup_shutdown_notify() {
    local script_path="/opt/gotify_shutdown.sh"
    local service_path="/etc/systemd/system/gotify-shutdown.service"

    print_info "正在部署：关机前置通知模块..."

    # 生成执行脚本
    cat > "$script_path" <<EOF
#!/bin/bash
curl -X POST "${GOTIFY_URL}/message?token=${GOTIFY_TOKEN}" \\
    -F "title=服务器状态：离线通知" \\
    -F "message=警告：服务器 [ ${SERVER_NAME} ] 正在执行关机/重启操作。" \\
    -F "priority=7"
EOF
    chmod +x "$script_path"

    # 生成 systemd service (利用 ExecStop 在服务停止时触发)
    cat > "$service_path" <<EOF
[Unit]
Description=Gotify Shutdown Notification
DefaultDependencies=no
Before=shutdown.target reboot.target halt.target

[Service]
Type=oneshot
ExecStart=/bin/true
ExecStop=$script_path
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable gotify-shutdown.service
    print_success "关机通知已激活。"
}

# 3. 设置每日心跳 (凌晨 03:00)
module_setup_daily_heartbeat() {
    local script_path="/opt/gotify_heartbeat.sh"
    local service_path="/etc/systemd/system/gotify-heartbeat.service"
    local timer_path="/etc/systemd/system/gotify-heartbeat.timer"

    print_info "正在部署：每日凌晨 3 点心跳推送模块..."

    # 生成执行脚本 (包含 Uptime 和 Load)
    cat > "$script_path" <<EOF
#!/bin/bash
UPTIME_INFO=\$(uptime -p)
LOAD_INFO=\$(uptime | awk -F'load average:' '{ print \$2 }')

# 组合推送到 Gotify
curl -X POST "${GOTIFY_URL}/message?token=${GOTIFY_TOKEN}" \\
    -F "title=服务器心跳：日常体检" \\
    -F "message=服务器 [ ${SERVER_NAME} ] 运行正常。
运行时长: \$UPTIME_INFO
系统负载: \$LOAD_INFO" \\
    -F "priority=1"
EOF
    chmod +x "$script_path"

    # 生成 systemd service
    cat > "$service_path" <<EOF
[Unit]
Description=Gotify Daily Heartbeat Notification

[Service]
Type=oneshot
ExecStart=$script_path
EOF

    # 生成 systemd timer
    cat > "$timer_path" <<EOF
[Unit]
Description=Run Gotify Heartbeat Daily at 3 AM

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable --now gotify-heartbeat.timer
    print_success "每日心跳定时器已启动 (03:00 AM)。"
}

# ---------------------------- 主执行逻辑 (Main) ----------------------------

main() {
    check_root
    module_collect_config

    echo "------------------------------------------------"
    module_setup_startup_notify
    module_setup_shutdown_notify
    module_setup_daily_heartbeat
    echo "------------------------------------------------"

    print_info "Gotify 综合通知系统配置完毕。"
    print_success "您的服务器现在具备了：[开机通知]、[关机预警] 以及 [每日凌晨心跳汇总] 功能。"
    print_info "您可以通过以下命令查看心跳定时器的下次执行时间："
    echo "  systemctl list-timers | grep heartbeat"
}

# 脚本入口
main