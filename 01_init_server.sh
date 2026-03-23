#!/bin/bash

# ==============================================================================
# Project: pve-lxc-init
# Script: 01_init_server.sh
# Description: Automated server initialization for PVE LXC (Debian/Ubuntu).
# Features: Package updates, generic tools, timezone sync, SSH tuning, panel setup.
# Author: emix1984
# ==============================================================================

# ---------------------------- 日志与输出配置 ----------------------------

# 打印普通执行信息 (Standard Info)
print_info() {
    echo -e "\033[32m[INFO]\033[0m $1"
}

# 打印成功状态信息 (Success Info)
print_success() {
    echo -e "\033[36m[SUCCESS]\033[0m $1"
}

# 打印错误提示 (Error Info)
print_error() {
    echo -e "\033[31m[ERROR]\033[0m $1"
}

# ---------------------------- 通用校验工具 ----------------------------

# 检查上一条命令是否执行成功
# 参数: $1=错误信息, $2=成功信息
check_command() {
    if [ $? -ne 0 ]; then
        print_error "$1"
        exit 1
    else
        print_success "$2"
    fi
}

# 检查运行权限 (脚本大多数配置均需 root 身份)
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "权限不足：请使用 root 身份或 sudo 运行此脚本 (sudo ./01_init_server.sh)"
        exit 1
    fi
}

# 幂等配置处理函数：确保文件中配置行的唯一性与准确性
# 逻辑: 如果正则匹配到则替换整行，未匹配到则追加到文件末尾
# 参数: $1=匹配正则表达式, $2=完整的配置行, $3=目标文件
ensure_config() {
    local pattern="$1"
    local line="$2"
    local file="$3"
    
    if grep -q "$pattern" "$file"; then
        sed -i "s|^$pattern.*|$line|" "$file"
    else
        echo "$line" >> "$file"
    fi
}

# ---------------------------- 系统核心模块 ----------------------------

# 全局变量：存储交互阶段收集的用户偏好
INSTALL_PANEL="none"
TARGET_ROOT_HOME="/DATA/AppData"
TARGET_TIMEZONE="Asia/Seoul"

# 模块：配置收集 (互动阶段)
module_collect_config() {
    echo -e "\n\033[1;34m>>> 阶段 1/2: 正在收集初始配置参数\033[0m"
    echo "------------------------------------------------"

    # 1. 面板偏好
    echo "选择预装管理面板:"
    echo "  1) CasaOS (轻量级家庭云系统)"
    echo "  3) 1Panel (现代化开源通用面板)"
    echo "  0) 暂不安装 (默认选项)"
    read -rp "输入编号 [1/2/0]: " choice
    case "$choice" in
        1) INSTALL_PANEL="casaos" ;;
        2) INSTALL_PANEL="1panel" ;;
        *) INSTALL_PANEL="none" ;;
    esac

    # 2. 时区设定
    read -rp "设定服务器时区 [默认: $TARGET_TIMEZONE]: " tz_input
    TARGET_TIMEZONE=${tz_input:-$TARGET_TIMEZONE}

    # 3. 存储目录
    read -rp "设定 Root 用户工作基准目录 [默认: $TARGET_ROOT_HOME]: " dir_input
    TARGET_ROOT_HOME=${dir_input:-$TARGET_ROOT_HOME}

    print_info "配置参数收集已完成。"
}

# 模块：摘要验证 (确认阶段)
module_confirm_config() {
    echo -e "\n\033[1;33m>>> 阶段 2/2: 请确认即将执行的操作清单\033[0m"
    echo "------------------------------------------------"
    echo "  - 系统时区: $TARGET_TIMEZONE"
    echo "  - 面板安装: $INSTALL_PANEL"
    echo "  - 数据路径: $TARGET_ROOT_HOME"
    echo "  - 基础设置: 更新源、安装必备工具、SSH 登陆优化、历史记录扩容"
    echo "------------------------------------------------"
    
    read -rp "确认无误并执行初始化？(y/n, 默认 y): " confirm
    confirm=${confirm:-"y"}
    if [[ "$confirm" != [yY] ]]; then
        print_info "操作已取消，脚本退出。"
        exit 0
    fi
}

# 模块：系统更新
module_update_upgrade_system() {
    print_info "正在通过 apt 同步仓库索引并升级已安装软件包..."
    apt update && apt upgrade -y
    check_command "系统软件包升级失败，请检查网络或软件源配置" "系统镜像已更新至最新状态"
}

# 模块：基础工具箱
module_install_common_tools() {
    print_info "正在部署运维必备工具集 (curl, wget, htop, tmux, etc.)..."
    apt install -y curl wget nano tree net-tools screen tmux traceroute htop sshpass openssl
    check_command "工具包安装过程中出现异常" "全量基础运维工具包已就绪"
}

# 模块：时区同步
module_set_timezone() {
    print_info "正在将系统时间同步为: $TARGET_TIMEZONE..."
    timedatectl set-timezone "$TARGET_TIMEZONE"
    check_command "执行 timedatectl 命令失败" "时区已成功修正为 $TARGET_TIMEZONE"
}

# 模块：SSH 客户端工具
module_install_ssh_copy_id() {
    print_info "正在配置 SSH 客户端组件 (openssh-client)..."
    apt install -y openssh-client
    check_command "依赖包 openssh-client 安装失败" "SSH 客户端扩展工具安装成功"
}

# 模块：SSH 服务端调优
module_install_and_configure_ssh() {
    print_info "正在强化 SSH 服务配置 (开启 root 登陆与密码认证模式)..."
    apt update && apt install -y openssh-server sudo
    check_command "基础服务端环境安装失败" "SSH 服务端核心组件已安装"
    
    systemctl enable --now ssh
    check_command "启动 SSH 服务守护进程失败" "SSH daemon 已设为开机自启并实时运行"
    
    local ssh_config="/etc/ssh/sshd_config"
    if [ -f "$ssh_config" ]; then
        [ ! -f "${ssh_config}.bak" ] && cp "$ssh_config" "${ssh_config}.bak"
        
        ensure_config "PermitRootLogin" "PermitRootLogin yes" "$ssh_config"
        ensure_config "PasswordAuthentication" "PasswordAuthentication yes" "$ssh_config"
        
        systemctl restart ssh
        print_success "SSHD 配置已更新：PermitRootLogin 开启，密码认证开启。"
    else
        print_error "未识别到 $ssh_config 配置文件"
        exit 1
    fi
}

# 模块：增强历史消息审计能力
module_increase_history_size() {
    print_info "正在扩容 Shell 历史记录存储上限 (HISTSIZE=99999)..."
    local profile_file="/etc/profile"
    
    ensure_config "HISTSIZE=" "HISTSIZE=99999" "$profile_file"
    ensure_config "HISTFILESIZE=" "HISTFILESIZE=99999" "$profile_file"
    
    print_success "历史记录参数已注入 /etc/profile，将在下次会话加载时生效。"
}

# 模块：CasaOS 安装逻辑
module_install_casaos() {
    print_info "检测到面板需求：正在启动 CasaOS 云端安装程序..."
    curl -fsSL https://get.casaos.io | bash
    check_command "CasaOS 安装过程返回了非零状态码" "CasaOS 云平台安装完成"
}

# 模块：1Panel 安装逻辑
module_install_1panel() {
    print_info "检测到面板需求：正在启动 1Panel 官方安装脚本..."
    bash -c "$(curl -sSL https://resource.fit2cloud.com/1panel/package/v2/quick_start.sh)"
    check_command "1Panel 部署任务未确认完成" "1Panel 数据面板安装成功"
}

# 模块：Root 用户目录规范化
module_change_root_home() {
    print_info "建议性操作：正在创建/检查用户基准工作目录 $TARGET_ROOT_HOME..."
    if [ ! -d "$TARGET_ROOT_HOME" ]; then
        mkdir -p "$TARGET_ROOT_HOME"
        check_command "创建核心工作目录失败" "成功创建数据存储目录 $TARGET_ROOT_HOME"
    fi
}

# 模块：执行深度系统清理
module_clean_system() {
    print_info "最后阶段：正在回收残留的 apt 缓存并清理临时目录..."
    apt clean
    apt autoremove --purge -y
    rm -rf /var/cache/apt/archives/*
    rm -rf /tmp/*
    print_success "系统环境清理完毕，磁盘冗余已被移除。"
}

# ---------------------------- 主执行逻辑 (Main) ----------------------------

main() {
    # 执行前交互与环境预检
    module_collect_config
    module_confirm_config
    check_root
    
    # 核心系统配置序列
    module_update_upgrade_system
    module_install_common_tools
    module_set_timezone
    module_install_ssh_copy_id
    module_install_and_configure_ssh
    module_increase_history_size

    # 面板扩展安装
    if [[ "$INSTALL_PANEL" == "casaos" ]]; then
        module_install_casaos
    elif [[ "$INSTALL_PANEL" == "1panel" ]]; then
        module_install_1panel
    fi

    # 收尾工作
    module_change_root_home
    module_clean_system
    
    echo -e "\n\033[1;32m🎉 恭喜！服务器初始化任务已全部执行完毕。\033[0m"
    echo "------------------------------------------------"
    print_info "后续建议："
    echo "  1. 重新登录或运行 'source /etc/profile' 以启用新的历史记录扩充效果。"
    echo "  2. 建议重启服务器 (reboot) 以确保内核级变更和各项服务完全同步。"
    echo "------------------------------------------------"
}

# 脚本入口
main "$@"
