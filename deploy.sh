#!/bin/bash
# ==============================================================================
# Project: pve-lxc-init
# Script: deploy.sh
# Description: Unified deployment & management tool for PVE LXC (Debian/Ubuntu).
#              Interactive menu (TTY) + CLI flags (non-interactive) + systemd mode.
# Usage:
#   ./deploy.sh              -> Interactive menu
#   ./deploy.sh --init       -> Server initialization (non-interactive)
#   ./deploy.sh --ssh-key    -> SSH key deployment
#   ./deploy.sh --sys-info   -> System info query
#   ./deploy.sh --gotify     -> Install boot/shutdown notifications
#   ./deploy.sh --lid-sleep  -> Disable laptop lid sleep
#   ./deploy.sh --extend-lvm -> Extend LVM root partition
#   ./deploy.sh --monitor    -> Run monitoring agent once
#   ./deploy.sh --monitor-install -> Register 2h monitoring timer
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
MONITOR_SCRIPT_PATH="/opt/gotify-monitor.sh"

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

# -------------------------------------------------------------------
#                         MODULE FUNCTIONS
# -------------------------------------------------------------------

# ====================== Module: Init Server ======================
module_init_server() {
    print_title "一键初始化服务器"

    local INSTALL_GOTIFY_NOTIFY=false
    local INSTALL_GOTIFY_MONITOR=false
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
        read -rp "设定时区 [默认: $TARGET_TIMEZONE]: " tz_input
        TARGET_TIMEZONE=${tz_input:-$TARGET_TIMEZONE}
        read -rp "设定 Root 工作目录 [默认: $TARGET_ROOT_HOME]: " dir_input
        TARGET_ROOT_HOME=${dir_input:-$TARGET_ROOT_HOME}

        # Root 密码
        echo ""
        read -sp "请输入 Root 新密码 [默认: 1234]: " pw1; echo
        local ROOT_PW_INPUT=${pw1:-1234}
        read -sp "请再次输入密码: " pw2; echo
        if [ "$ROOT_PW_INPUT" = "$pw2" ] && [ -n "$ROOT_PW_INPUT" ]; then
            ROOT_PW="$ROOT_PW_INPUT"
            PASSWORD_MATCH=true
        else
            print_error "两次密码不一致，跳过密码设置"
        fi

        # Gotify 配置
        echo ""
        print_separator
        echo "--- Gotify 推送配置 (可选，可跳过) ---"
        read -rp "是否配置 Gotify? (y/n, 默认 n): " gotify_yn
        if [[ "$gotify_yn" == [yY] ]]; then
            read -rp "请输入 Gotify URL (如 https://gotify.example.com): " GOTIFY_URL
            read -rp "请输入 Gotify Token: " GOTIFY_TOKEN
            if [ -n "$GOTIFY_URL" ] && [ -n "$GOTIFY_TOKEN" ]; then
                read -rp "安装开机/关机通知? (y/n, 默认 y): " yn_notify
                [[ "$yn_notify" != [nN] ]] && INSTALL_GOTIFY_NOTIFY=true
                read -rp "安装监控 Agent (每 2h 推送)? (y/n, 默认 y): " yn_mon
                if [[ "$yn_mon" != [nN] ]]; then
                    INSTALL_GOTIFY_MONITOR=true
                    read -rp "Tailscale Peer IP [默认: $TARGET_PEER_IP]: " peer_input
                    TARGET_PEER_IP=${peer_input:-$TARGET_PEER_IP}
                fi
                save_env
            fi
        fi

        # 确认摘要
        echo ""
        print_separator
        echo "========== 执行确认 =========="
        if [ "$INSTALL_PANEL" = "none" ]; then
            echo "  面板安装: 不安装"
        else
            echo "  面板安装: $INSTALL_PANEL"
        fi
        echo "  时区: $TARGET_TIMEZONE"
        echo "  工作目录: $TARGET_ROOT_HOME"
        if $PASSWORD_MATCH; then
            echo "  Root 密码: 已设置"
        else
            echo "  Root 密码: 跳过"
        fi
        if [ -n "$GOTIFY_URL" ]; then
            echo "  Gotify URL: $GOTIFY_URL"
            if $INSTALL_GOTIFY_NOTIFY; then
                echo "  开机/关机通知: 安装"
            else
                echo "  开机/关机通知: 跳过"
            fi
            if $INSTALL_GOTIFY_MONITOR; then
                echo "  监控 Agent (每 2h): 安装"
            else
                echo "  监控 Agent (每 2h): 跳过"
            fi
        fi
        echo "============================="
        read -rp "确认执行以上操作? (y/n, 默认 y): " confirm
        confirm=${confirm:-y}
        if [[ "$confirm" != [yY] ]]; then
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
    apt update && apt upgrade -y
    check_command "系统更新失败" "系统已更新至最新"

    print_info "正在安装基础工具包..."
    apt install -y curl wget nano tree screen tmux traceroute htop sshpass openssl jq iputils-ping lvm2 xfsprogs lsb-release
    check_command "工具安装失败" "基础工具包已就绪"

    print_info "正在同步时区: $TARGET_TIMEZONE..."
    timedatectl set-timezone "$TARGET_TIMEZONE"
    check_command "时区设置失败" "时区已设为 $TARGET_TIMEZONE"

    print_info "正在配置 SSH 服务..."
    apt install -y openssh-server openssh-client
    systemctl enable --now ssh
    local ssh_cfg="/etc/ssh/sshd_config"
    if [ -f "$ssh_cfg" ]; then
        backup_file "$ssh_cfg"
        ensure_config "PermitRootLogin" "PermitRootLogin yes" "$ssh_cfg"
        ensure_config "PasswordAuthentication" "PasswordAuthentication yes" "$ssh_cfg"
        systemctl restart ssh
        print_success "SSH 配置已更新 (root 登录 + 密码认证)"
    fi

    if $PASSWORD_MATCH; then
        echo "root:$ROOT_PW" | chpasswd
        check_command "密码设置失败" "Root 密码已更新"
    fi

    print_info "正在扩容历史记录..."
    local profile="/etc/profile"
    ensure_config "HISTSIZE=" "HISTSIZE=99999" "$profile"
    ensure_config "HISTFILESIZE=" "HISTFILESIZE=99999" "$profile"

    if [ "$INSTALL_PANEL" = "casaos" ]; then
        print_info "正在安装 CasaOS..."
        curl -fsSL https://get.casaos.io | bash
        check_command "CasaOS 安装失败" "CasaOS 安装完成"
    elif [ "$INSTALL_PANEL" = "1panel" ]; then
        print_info "正在安装 1Panel..."
        bash -c "$(curl -sSL https://resource.fit2cloud.com/1panel/package/v2/quick_start.sh)"
        check_command "1Panel 安装失败" "1Panel 安装完成"
    fi

    mkdir -p "$TARGET_ROOT_HOME"
    print_success "工作目录已就绪: $TARGET_ROOT_HOME"

    print_info "正在清理系统缓存..."
    apt clean && apt autoremove --purge -y
    rm -rf /var/cache/apt/archives/* /tmp/*

    print_success "系统初始化完成"

    # ========== Gotify 后置安装 ==========
    if [ -n "$GOTIFY_URL" ] && [ -n "$GOTIFY_TOKEN" ]; then
        if $INSTALL_GOTIFY_NOTIFY; then
            module_gotify_notify
        fi
        if $INSTALL_GOTIFY_MONITOR; then
            module_monitor_install
        fi
    fi

    print_info "建议重新登录或运行 'source /etc/profile' 启用历史记录扩容"
}

# ====================== Module: SSH Key Deploy ======================
module_ssh_key() {
    print_title "SSH 密钥免密部署"

    read -rp "请输入远程服务器 IP/域名 [默认: 127.0.0.1]: " REMOTE_HOST
    REMOTE_HOST=${REMOTE_HOST:-127.0.0.1}
    read -rp "请输入远程登录用户名 [默认: root]: " REMOTE_USER
    REMOTE_USER=${REMOTE_USER:-root}
    read -rp "请输入远程 SSH 端口 [默认: 22]: " REMOTE_PORT
    REMOTE_PORT=${REMOTE_PORT:-22}

    local key_file="$HOME/.ssh/id_rsa"
    if [ ! -f "$key_file" ]; then
        print_info "未检测到密钥对，正在生成 4096 位 RSA 密钥..."
        ssh-keygen -t rsa -b 4096 -f "$key_file" -N ""
        check_command "密钥生成失败" "密钥对已生成"
    else
        print_success "检测到现有密钥对，跳过生成"
    fi

    print_info "正在推送公钥至 ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PORT}..."
    ssh-copy-id -i "$key_file.pub" -p "$REMOTE_PORT" "${REMOTE_USER}@${REMOTE_HOST}"
    check_command "公钥推送失败，请检查网络或密码" "公钥已推送"

    # 验证
    print_info "正在验证免密登录..."
    if ssh -o BatchMode=yes -o ConnectTimeout=5 -p "$REMOTE_PORT" "${REMOTE_USER}@${REMOTE_HOST}" "id" > /dev/null 2>&1; then
        print_success "免密登录验证通过"
    else
        print_error "免密登录验证失败"
    fi
}

# ====================== Module: Gotify Notifications ======================
module_gotify_notify() {
    print_title "安装 Gotify 通知系统 (开机/关机通知)"

    if [ -z "$GOTIFY_URL" ] || [ -z "$GOTIFY_TOKEN" ]; then
        read -rp "请输入 Gotify API 端点 (如 https://gotify.example.com): " GOTIFY_URL
        read -rp "请输入 Gotify Token: " GOTIFY_TOKEN
    fi
    if [ -z "$GOTIFY_URL" ] || [ -z "$GOTIFY_TOKEN" ]; then
        print_error "Gotify URL 和 Token 为必填项"
        exit 1
    fi

    check_root

    # 1. 开机通知
    local startup_script="/opt/gotify_startup.sh"
    local startup_svc="/etc/systemd/system/gotify-startup.service"

    cat > "$startup_script" <<EOF
#!/bin/bash
curl -s -X POST "${GOTIFY_URL}/message?token=${GOTIFY_TOKEN}" \
    -F "title=服务器状态：已上线" \
    -F "message=服务器 [ ${DEVICE_NAME} ] 已成功启动并联网。" \
    -F "priority=5"
EOF
    chmod +x "$startup_script"

    cat > "$startup_svc" <<EOF
[Unit]
Description=Gotify Startup Notification for ${DEVICE_NAME}
After=network.target

[Service]
Type=oneshot
ExecStart=$startup_script
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable gotify-startup.service
    print_success "开机通知已激活"

    # 2. 关机通知
    local shutdown_script="/opt/gotify_shutdown.sh"
    local shutdown_svc="/etc/systemd/system/gotify-shutdown.service"

    cat > "$shutdown_script" <<EOF
#!/bin/bash
curl -s -X POST "${GOTIFY_URL}/message?token=${GOTIFY_TOKEN}" \
    -F "title=服务器状态：离线通知" \
    -F "message=警告：服务器 [ ${DEVICE_NAME} ] 正在执行关机/重启操作。" \
    -F "priority=7"
EOF
    chmod +x "$shutdown_script"

    cat > "$shutdown_svc" <<EOF
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

    systemctl daemon-reload
    systemctl enable gotify-shutdown.service
    print_success "关机通知已激活"

    print_success "Gotify 通知系统安装完成"
    print_info "已启用: 开机通知 (gotify-startup.service)"
    print_info "已启用: 关机预警 (gotify-shutdown.service)"
}

# ====================== Module: Lid Sleep Disable ======================
module_lid_sleep() {
    print_title "禁用笔记本合盖睡眠"

    check_root

    # 笔记本检测
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

    systemctl restart systemd-logind
    check_command "重启 systemd-logind 失败" "配置已生效"

    # 验证
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

    # 检测根分区
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

    # 检查剩余空间
    local free_space
    free_space=$(vgs --noheadings --units g -o vg_free "$vg_name" | awk '{gsub(/g/,""); print $1}')
    if awk "BEGIN {exit !($free_space <= 0.01)}"; then
        print_error "卷组无可用空间 (剩余: ${free_space}G)"
        exit 1
    fi
    print_success "卷组可用空间: ${free_space}G"

    # 检测文件系统
    local fs_type
    fs_type=$(df -T | grep "$root_device" | awk '{print $2}')
    case "$fs_type" in
        ext4|xfs) print_success "文件系统: $fs_type" ;;
        *) print_error "不支持的文件系统: $fs_type (仅 ext4/xfs)" ; exit 1 ;;
    esac

    # 备份
    local bk_dir="/root/lvm_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$bk_dir"
    vgcfgbackup -f "$bk_dir/vg_${vg_name}.cfg" "$vg_name" 2>/dev/null || true
    lvdisplay > "$bk_dir/lv_before.txt" 2>/dev/null || true
    vgs > "$bk_dir/vg_before.txt" 2>/dev/null || true
    print_success "LVM 配置已备份至: $bk_dir"

    # 扩展
    lvextend -l +100%FREE "$root_device"
    check_command "逻辑卷扩展失败" "逻辑卷已扩展"

    # 调整文件系统
    case "$fs_type" in
        ext4) resize2fs "$root_device" && print_success "文件系统已扩容" || print_error "resize2fs 失败" ;;
        xfs)  xfs_growfs / && print_success "文件系统已扩容" || print_error "xfs_growfs 失败" ;;
    esac

    # 验证
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

# --------------------------------------------------------
# Module: Monitor Agent (Tailscale + Resource + Gotify)
# --------------------------------------------------------
module_monitor_run() {
    print_title "运行 Gotify 监控 Agent"

    if [ -z "$GOTIFY_URL" ] || [ -z "$GOTIFY_TOKEN" ]; then
        print_error "请先设定 Gotify URL 和 Token"
        exit 1
    fi

    local report_log=""
    local reboot_triggered=false

    # ---------------------- Phase B: Tailscale Health ----------------------
    print_info "检查 Tailscale 状态..."

    # B1: 守护进程状态
    if ! command -v tailscale &>/dev/null; then
        print_info "Tailscale 未安装，跳过网络自愈模块"
    else
        if ! tailscale status &>/dev/null; then
            print_info "Tailscale 未运行，正在重启..."
            systemctl restart tailscaled
            sleep 5
            if tailscale status &>/dev/null; then
                print_success "Tailscaled 已恢复"
                report_log="${report_log}\n- Tailscale: 已自动恢复"
            else
                print_error "Tailscaled 无法重启"
                report_log="${report_log}\n- Tailscale: 恢复失败"
            fi
        else
            print_success "Tailscale 运行正常"
            report_log="${report_log}\n- Tailscale: 运行正常"
        fi

        # B2: 自动更新
        tailscale update --yes &>/dev/null || true

        # B3: Peer 连通性测试
        if [ -n "$TARGET_PEER_IP" ]; then
            print_info "正在检测 Peer $TARGET_PEER_IP..."
            if ping -c 3 -W 5 "$TARGET_PEER_IP" &>/dev/null; then
                print_success "Peer 连通正常"
                report_log="${report_log}\n- Peer ${TARGET_PEER_IP}: 连通正常"
            else
                print_error "Peer $TARGET_PEER_IP 不可达，触发紧急流程"
                report_log="${report_log}\n- Peer ${TARGET_PEER_IP}: 不可达"

                # 发送紧急通知
                local emergency_msg="**紧急：服务器 ${DEVICE_NAME} 即将重启**\n\n原因：Peer ${TARGET_PEER_IP} 不可达\n时间：$(date '+%Y-%m-%d %H:%M:%S')"
                send_gotify "紧急警报" "$emergency_msg" 10 "$GOTIFY_URL" "$GOTIFY_TOKEN"

                # 强制重启 (内核级，跳过所有进程)
                print_info "10 秒后强制重启 (内核级)..."
                sleep 10
                reboot --force --force 2>/dev/null || reboot -ff 2>/dev/null || echo b > /proc/sysrq-trigger
                reboot_triggered=true
            fi
        fi
    fi

    # ---------------------- Phase C: Metrics Collection ----------------------
    print_info "正在采集系统指标..."

    # C1: Uptime
    local days=0 hours=0 mins=0
    if [ -r /proc/uptime ]; then
        local uptime_seconds
        read -r uptime_seconds _ < /proc/uptime
        days=$((uptime_seconds / 86400))
        hours=$(((uptime_seconds % 86400) / 3600))
        mins=$(((uptime_seconds % 3600) / 60))
    fi

    # C2: CPU & Memory
    local load_1min total_mem used_mem
    load_1min=$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo "N/A")
    read -r total_mem used_mem _ < <(free -m | awk '/Mem:/ {print $2, $3, $4}') 2>/dev/null || { total_mem=0; used_mem=0; }

    # C3: Disk
    local disk_total disk_used disk_free
    read -r disk_total disk_used disk_free _ < <(df -BG / | awk 'NR==2 {print $2, $3, $4}') 2>/dev/null || { disk_total="N/A"; disk_used="N/A"; disk_free="N/A"; }

    # C4: Top 3 进程
    local top3="N/A"
    top3=$(ps -eo comm=,rss= --sort=-rss 2>/dev/null | awk '{size=$2/1024; if (size > 0) printf "%s (%.1fMB), ", $1, size}' | head -c -2)
    [ -z "$top3" ] && top3="N/A"

    # C5: Public IP (多源回退)
    local public_ip="N/A"
    for src in "https://api.ipify.org" "https://ifconfig.me" "https://icanhazip.com"; do
        public_ip=$(curl -s --max-time 5 "$src" 2>/dev/null | grep -Eo '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')
        [ -n "$public_ip" ] && break
    done
    [ -z "$public_ip" ] && public_ip="N/A"

    # Local IP
    local local_ip
    local_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    [ -z "$local_ip" ] && local_ip="N/A"

    # Tailscale IP
    local ts_ip="N/A"
    command -v tailscale &>/dev/null && ts_ip=$(tailscale ip -4 2>/dev/null || echo "N/A")

    # ---------------------- Phase D: JSON Format & Send ----------------------
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
${report_log}

_$(date '+%Y-%m-%d %H:%M:%S')_
MSGBODY
)

    # 使用 jq 构建 Markdown 格式 JSON
    local json_payload
    json_payload=$(jq -n \
        --arg title "伺服器 [ ${DEVICE_NAME} ] 运行报告" \
        --arg msg "$message" \
        '{title: $title, message: $msg, priority: 3,
          extras: {"client::display": {"contentType": "text/markdown"}}}' 2>/dev/null)

    if [ -z "$json_payload" ]; then
        # fallback: 传统 form-data 方式
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

module_monitor_install() {
    print_title "安装 Gotify 监控 Agent (每 2h)"

    if [ -z "$GOTIFY_URL" ] || [ -z "$GOTIFY_TOKEN" ]; then
        read -rp "请输入 Gotify API 端点 (如 https://gotify.example.com): " GOTIFY_URL
        read -rp "请输入 Gotify Token: " GOTIFY_TOKEN
    fi
    if [ -z "$GOTIFY_URL" ] || [ -z "$GOTIFY_TOKEN" ]; then
        print_error "Gotify URL 和 Token 为必填项"
        exit 1
    fi

    check_root

    local service_path="/etc/systemd/system/gotify-monitor.service"
    local timer_path="/etc/systemd/system/gotify-monitor.timer"

    # 生成 service unit (机器名称直接 embed)
    cat > "$service_path" <<UNIT
[Unit]
Description=Gotify Monitor Agent for ${DEVICE_NAME}
After=network.target tailscaled.service

[Service]
Type=oneshot
ExecStart=${SCRIPT_DIR}/deploy.sh --monitor \\
    --Device "${DEVICE_NAME}" \\
    --GotifyUrl "${GOTIFY_URL}" \\
    --GotifyToken "${GOTIFY_TOKEN}" \\
    --PeerIP "${TARGET_PEER_IP}"
UNIT

    # 生成 timer unit
    cat > "$timer_path" <<TIMER
[Unit]
Description=Run Gotify Monitor every 2 hours

[Timer]
OnBootSec=5min
OnUnitActiveSec=2h
Persistent=true

[Install]
WantedBy=timers.target
TIMER

    systemctl daemon-reload
    systemctl enable --now gotify-monitor.timer
    check_command "Timer 注册失败" "监控 Agent 已安装，每 2 小时执行一次"

    print_success "systemd timer 已激活"
    print_info "下次执行时间:"
    systemctl list-timers | grep gotify-monitor || true
}

# ====================== Module: Tailscale Install ======================
module_install_tailscale() {
    print_title "Tailscale 安装与配置"

    # 检查是否已安装
    if command -v tailscale &>/dev/null; then
        local ts_ver
        ts_ver=$(tailscale version 2>/dev/null | head -1)
        print_info "检测到 Tailscale 已安装 (版本: ${ts_ver:-unknown})"
        echo ""
        read -rp "是否重新安装/更新至最新版? (y/n, 默认 n): " reinstall
        if [[ "$reinstall" != [yY] ]]; then
            # 不重装，但确保服务运行和自动更新开启
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

    # 安装官方脚本
    print_info "正在安装 Tailscale (官方脚本)..."
    curl -fsSL https://tailscale.com/install.sh | sh
    check_command "Tailscale 安装失败" "Tailscale 安装完成"

    # 启用开机自启并启动服务
    systemctl enable tailscaled
    systemctl start tailscaled
    check_command "tailscaled 启动失败" "tailscaled 已开机自启并运行中"

    # 设置自动更新 (持久化，后台静默升级)
    print_info "正在启用自动更新..."
    tailscale set --auto-update=true 2>/dev/null || true
    print_success "自动更新已启用 (Tailscale 将在后台自动升级)"

    # 引导认证
    echo ""
    print_info "Tailscale 需要认证才能连接到您的 tailnet"
    print_info "执行以下命令完成认证:"
    echo ""
    echo "    tailscale up"
    echo ""
    echo "系统将打开一个登录链接，在浏览器中认证即可"
    echo ""
    read -rp "是否立即执行 tailscale up? (y/n, 默认 y): " do_up
    do_up=${do_up:-y}
    if [[ "$do_up" == [yY] ]]; then
        tailscale up
        print_success "Tailscale 认证流程已完成"
    else
        print_info "稍后可手动执行 'tailscale up' 完成认证"
    fi

    # 显示状态
    echo ""
    print_info "Tailscale 状态:"
    tailscale status 2>/dev/null || true

    # 可选：将本机 IP 设为 Peer IP
    local ts_ip
    ts_ip=$(tailscale ip -4 2>/dev/null || true)
    if [ -n "$ts_ip" ] && [ -z "$TARGET_PEER_IP" ]; then
        echo ""
        read -rp "是否将此 Tailscale IP ($ts_ip) 设为监控 Agent 的目标 Peer IP? (y/n): " set_peer
        if [[ "$set_peer" == [yY] ]]; then
            TARGET_PEER_IP="$ts_ip"
            save_env
            print_success "目标 Peer IP 已设为: $ts_ip"
        fi
    fi
}

# ====================== Module: Test Gotify Push ======================
module_test_gotify() {
    print_title "Gotify 推送测试"

    if [ -z "$GOTIFY_URL" ] || [ -z "$GOTIFY_TOKEN" ]; then
        print_error "请先设定 Gotify URL 和 Token（选单选项 [9]）"
        return
    fi

    print_info "正在向 $GOTIFY_URL 发送测试通知..."
    echo ""

    local test_msg
    test_msg="**Gotify 推送测试**\n\n\
- 服务器: \`$DEVICE_NAME\`\n\
- 时间: $(date '+%Y-%m-%d %H:%M:%S')\n\
- 状态: ✅ 推送正常\n\n\
*若收到本条消息，说明 Gotify 配置正确*"

    send_gotify "🧪 测试通知 - $DEVICE_NAME" "$test_msg" 5 "$GOTIFY_URL" "$GOTIFY_TOKEN"
}

# --------------------------------------------------------
#                        MENU
# --------------------------------------------------------
show_menu() {
    clear
    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "║        PVE-LXC-INIT  部 署 管 理 工 具       ║"
    echo "║       ═══════════════════════════════════    ║"
    echo "╠══════════════════════════════════════════════╣"
    echo "║                                              ║"
    printf "║   当前设定                                   ║\n"
    printf "║     机器名称 : %-30s ║\n" "$DEVICE_NAME"
    if [ -n "$GOTIFY_URL" ]; then
        printf "║     Gotify   : 已设定                         ║\n"
    else
        printf "║     Gotify   : 未设定                         ║\n"
    fi
    printf "║     Peer IP  : %-30s ║\n" "$TARGET_PEER_IP"
    echo "║                                              ║"
    echo "╠══════════════════════════════════════════════╣"
    echo "║                                              ║"
    echo "║   ┌── 系统初始化 ──────────────────────┐    ║"
    echo "║   │  [1] 一键初始化服务器              │    ║"
    echo "║   │  [2] SSH 密钥免密部署             │    ║"
    echo "║   │  [3] 系统信息查询                 │    ║"
    echo "║   └────────────────────────────────────┘    ║"
    echo "║                                              ║"
    echo "║   ┌── Gotify 推送系统 ────────────────┐    ║"
    echo "║   │  [4] 安装通知 (开机/关机)         │    ║"
    echo "║   │  [5] 安装监控 Agent (每 2h)      │    ║"
    echo "║   │ [12] 测试推送                    │    ║"
    echo "║   └────────────────────────────────────┘    ║"
    echo "║                                              ║"
    echo "║   ┌── 网络配置 ───────────────────────┐    ║"
    echo "║   │ [11] 安装 Tailscale (含自动更新)  │    ║"
    echo "║   └────────────────────────────────────┘    ║"
    echo "║                                              ║"
    echo "║   ┌── 进阶设定 ───────────────────────┐    ║"
    echo "║   │  [6] 禁用笔记本合盖睡眠           │    ║"
    echo "║   │  [7] LVM 根分区扩容              │    ║"
    echo "║   └────────────────────────────────────┘    ║"
    echo "║                                              ║"
    echo "║   ┌── 系统配置 ───────────────────────┐    ║"
    echo "║   │  [8] 修改机器名称                 │    ║"
    echo "║   │  [9] 修改 Gotify URL/Token       │    ║"
    echo "║   │ [10] 修改 Tailscale Peer IP      │    ║"
    echo "║   └────────────────────────────────────┘    ║"
    echo "║                                              ║"
    echo "║   ┌── ────────────────────────────────┐    ║"
    echo "║   │  [0] 退出                        │    ║"
    echo "║   └────────────────────────────────────┘    ║"
    echo "║                                              ║"
    echo "╚══════════════════════════════════════════════╝"
}

menu_loop() {
    while true; do
        show_menu
        read -rp "   请输入选项编号 [0-12]: " choice
        echo ""
        case "$choice" in
            1) module_init_server ;;
            2) module_ssh_key ;;
            3) module_sys_info ;;
            4) module_gotify_notify ;;
            5) module_monitor_install ;;
            6) module_lid_sleep ;;
            7) module_extend_lvm ;;
            8)
                read -rp "请输入新的机器名称: " DEVICE_NAME
                DEVICE_NAME=${DEVICE_NAME:-$(hostname)}
                save_env
                print_success "当前机器名称已设为: $DEVICE_NAME"
                if systemctl is-active gotify-monitor.timer &>/dev/null; then
                    echo ""
                    read -rp "检测到已安装监控 Agent，是否同时更新 systemd 中的名称？(y/n): " yn
                    if [[ "$yn" == [yY] ]]; then
                        module_monitor_install
                        print_success "监控 Agent 已更新为新名称: $DEVICE_NAME"
                    fi
                fi
                if systemctl is-enabled gotify-startup.service &>/dev/null; then
                    echo ""
                    read -rp "检测到已安装开机/关机通知，是否重新生成脚本？(y/n): " yn2
                    if [[ "$yn2" == [yY] ]]; then
                        module_gotify_notify
                    fi
                fi
                ;;
            9)
                read -rp "请输入 Gotify URL (如 https://gotify.example.com): " GOTIFY_URL
                read -rp "请输入 Gotify Token: " GOTIFY_TOKEN
                save_env
                print_success "Gotify 配置已更新"
                ;;
            10)
                read -rp "请输入 Tailscale Peer IP: " TARGET_PEER_IP
                save_env
                print_success "Peer IP 已更新为: $TARGET_PEER_IP"
                ;;
            11) module_install_tailscale ;;
            12) module_test_gotify ;;
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

# --------------------------------------------------------
#                   ARGUMENT PARSING
# --------------------------------------------------------
usage() {
    echo "用法: ./deploy.sh [选项]"
    echo ""
    echo "选项:"
    echo "  (无参数)        显示交互菜单"
    echo "  --init          一键初始化服务器"
    echo "  --ssh-key       SSH 密钥免密部署"
    echo "  --gotify        安装 Gotify 通知 (开机/关机)"
    echo "  --lid-sleep     禁用笔记本合盖睡眠"
    echo "  --extend-lvm    LVM 根分区扩容"
    echo "  --sys-info      系统信息查询"
    echo "  --monitor       运行监控 Agent (单次)"
    echo "  --monitor-install 安装监控 Agent 定时器 (每 2h)"
    echo "  --tailscale-install 安装 Tailscale (含自动更新)"
    echo ""
    echo "参数:"
    echo "  --Device <名称>      指定机器名称 (默认: hostname)"
    echo "  --GotifyUrl <URL>    Gotify 服务地址"
    echo "  --GotifyToken <KEY>  Gotify Token"
    echo "  --PeerIP <IP>        Tailscale Peer IP"
    echo "  --Timezone <时区>    时区 (如 Asia/Seoul)"
    echo ""
    echo "示例:"
    echo "  ./deploy.sh --monitor --Device MyServer --GotifyUrl https://gotify.example.com --GotifyToken abc --PeerIP 100.114.252.115"
    echo "  ./deploy.sh --monitor-install --Device MyServer --GotifyUrl https://gotify.example.com --GotifyToken abc"
    exit 0
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --init)             MODE="init"; shift ;;
            --ssh-key)          MODE="ssh-key"; shift ;;
            --gotify)           MODE="gotify"; shift ;;
            --lid-sleep)        MODE="lid-sleep"; shift ;;
            --extend-lvm)       MODE="extend-lvm"; shift ;;
            --sys-info)         MODE="sys-info"; shift ;;
            --monitor)          MODE="monitor"; shift ;;
            --monitor-install)  MODE="monitor-install"; shift ;;
            --tailscale-install) MODE="tailscale-install"; shift ;;
            --Device)           DEVICE_NAME="$2"; shift 2 ;;
            --GotifyUrl)        GOTIFY_URL="$2"; shift 2 ;;
            --GotifyToken)      GOTIFY_TOKEN="$2"; shift 2 ;;
            --PeerIP)           TARGET_PEER_IP="$2"; shift 2 ;;
            --Timezone)         TARGET_TIMEZONE="$2"; shift 2 ;;
            -h|--help)          usage ;;
            *)                  print_error "未知参数: $1"; usage ;;
        esac
    done
}

# --------------------------------------------------------
#                        MAIN
# --------------------------------------------------------
main() {
    # 无 TTY (piped / systemd) -> 只跑非交互模式
    if [ ! -t 0 ]; then
        if [ $# -eq 0 ]; then
            print_error "非交互模式需要指定 --flag 参数"
            usage
        fi
        parse_args "$@"
    elif [ $# -gt 0 ]; then
        # 有 TTY 但给了参数
        parse_args "$@"
    else
        # 有 TTY 且无参数 -> 显示菜单
        menu_loop
        return
    fi

    # 执行对应模块
    case "$MODE" in
        init)            module_init_server ;;
        ssh-key)         module_ssh_key ;;
        gotify)          module_gotify_notify ;;
        lid-sleep)       module_lid_sleep ;;
        extend-lvm)      module_extend_lvm ;;
        sys-info)        module_sys_info ;;
        monitor)         module_monitor_run ;;
        monitor-install) module_monitor_install ;;
        tailscale-install) module_install_tailscale ;;
        *)               print_error "未指定有效模块"; usage ;;
    esac
}

main "$@"
