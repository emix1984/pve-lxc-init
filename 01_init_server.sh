#!/bin/bash

# 打印信息函数
print_info() {
    echo "[INFO] $1"
}

# 打印错误函数
print_error() {
    echo "[ERROR] $1"
}

# 检查命令是否成功执行的函数
check_command() {
    if [ $? -ne 0 ]; then
        print_error "$1"
        exit 1
    else
        print_info "$2"
    fi
}

# 检查是否以 root 权限运行
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "请使用 root 权限运行此脚本 (sudo ./init_ubuntuserver.sh)"
        exit 1
    fi
}

# 通用函数：确保文件中存在某项配置（幂等性处理）
# 参数: $1=匹配正则表达式, $2=完整的配置行, $3=目标文件
ensure_config() {
    local pattern="$1"
    local line="$2"
    local file="$3"
    
    if grep -q "$pattern" "$file"; then
        # 如果匹配到，则替换（确保准确性）
        sed -i "s|^$pattern.*|$line|" "$file"
    else
        # 如果未匹配到，则追加
        echo "$line" >> "$file"
    fi
}

# 模块：更新和升级系统
module_update_upgrade_system() {
    print_info "正在更新和升级系统..."
    apt update && apt upgrade -y
    check_command "系统更新和升级失败" "系统更新和升级成功"
}

# 模块：安装通用工具
module_install_common_tools() {
    print_info "正在安装通用工具..."
    apt install -y curl wget nano tree net-tools screen tmux traceroute htop sshpass openssl
    check_command "安装通用工具失败" "通用工具安装成功"
}

# 全局变量，用于存储用户配置
INSTALL_PANEL="none"
TARGET_ROOT_HOME="/DATA/AppData"
TARGET_TIMEZONE="Asia/Seoul"

# 模块：交互式收集配置
module_collect_config() {
    print_info "================================================"
    print_info "          Ubuntu / Debian 服务器初始化配置收集           "
    print_info "================================================"

    # 1. 选择面板
    echo "1) 安装 CasaOS"
    echo "2) 安装 1Panel"
    echo "3) 暂不安装 (默认)"
    read -rp "请选择要安装的面板 (数字 1/2/3): " choice
    case "$choice" in
        1) INSTALL_PANEL="casaos" ;;
        2) INSTALL_PANEL="1panel" ;;
        *) INSTALL_PANEL="none" ;;
    esac

    # 2. 确认时区
    read -rp "请输入目标时区 [默认: $TARGET_TIMEZONE]: " tz_input
    TARGET_TIMEZONE=${tz_input:-$TARGET_TIMEZONE}

    # 3. 确认 root 工作目录
    read -rp "请输入 root 用户目标目录 [默认: $TARGET_ROOT_HOME]: " dir_input
    TARGET_ROOT_HOME=${dir_input:-$TARGET_ROOT_HOME}

    print_info "配置收集完成。"
}

# 模块：显示配置摘要并确认
module_confirm_config() {
    print_info "------------------------------------------------"
    print_info "请确认以下配置信息："
    echo "  - 目标时区: $TARGET_TIMEZONE"
    echo "  - 待安装面板: $INSTALL_PANEL"
    echo "  - Root 目标目录: $TARGET_ROOT_HOME"
    print_info "------------------------------------------------"
    
    read -rp "是否继续执行初始化？ (y/n, 默认 y): " confirm
    confirm=${confirm:-"y"}
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        print_info "用户取消，脚本退出。"
        exit 0
    fi
}

# 模块：同步时区
module_set_timezone() {
    print_info "正在将时区同步为 $TARGET_TIMEZONE..."
    timedatectl set-timezone "$TARGET_TIMEZONE"
    check_command "设置时区失败" "时区设置为 $TARGET_TIMEZONE 成功"
}

# 模块：安装 ssh-copy-id
module_install_ssh_copy_id() {
    print_info "正在安装 ssh-copy-id..."
    apt install -y openssh-client
    check_command "安装 ssh-copy_id 失败" "ssh-copy_id 安装成功"
}

# 模块：安装和配置OpenSSH服务
module_install_and_configure_ssh() {
    print_info "正在安装 openssh-server 和 sudo..."
    apt update && apt install -y openssh-server sudo
    check_command "安装 openssh-server 和 sudo 失败" "openssh-server 和 sudo 安装成功"
    
    print_info "正在启动 openssh-server..."
    systemctl enable --now ssh
    check_command "启动 openssh-server 失败" "openssh-server 启动成功"
    
    print_info "正在配置 SSH (允许 root 登录及密码认证)..."
    local ssh_config="/etc/ssh/sshd_config"
    if [ -f "$ssh_config" ]; then
        # 备份原始配置文件
        [ ! -f "${ssh_config}.bak" ] && cp "$ssh_config" "${ssh_config}.bak"
        
        # 幂等性配置
        ensure_config "PermitRootLogin" "PermitRootLogin yes" "$ssh_config"
        ensure_config "PasswordAuthentication" "PasswordAuthentication yes" "$ssh_config"
        
        systemctl restart ssh
        check_command "重启 SSH 失败" "SSH 配置更新成功"
    else
        print_error "$ssh_config 文件未找到"
        exit 1
    fi
}

# 模块：增加命令历史记录的存储数量
module_increase_history_size() {
    print_info "正在配置命令历史记录数量..."
    local profile_file="/etc/profile"
    
    ensure_config "HISTSIZE=" "HISTSIZE=99999" "$profile_file"
    ensure_config "HISTFILESIZE=" "HISTFILESIZE=99999" "$profile_file"
    
    check_command "设置命令历史记录失败" "命令历史记录设置成功 (需重启或重新 source 生效)"
}

module_install_casaos() {
    print_info "正在安装 CasaOS..."
    curl -fsSL https://get.casaos.io | bash
    check_command "安装 CasaOS 失败" "CasaOS 安装成功"
}

module_install_1panel() {
    print_info "正在安装 1Panel..."
    bash -c "$(curl -sSL https://resource.fit2cloud.com/1panel/package/v2/quick_start.sh)"
    check_command "安装 1Panel 失败" "1Panel 安装成功"
}

# 模块：修改 root 用户的默认 workdir
module_change_root_home() {
    print_info "正在检查 root 用户的目标目录 $TARGET_ROOT_HOME..."
    if [ ! -d "$TARGET_ROOT_HOME" ]; then
        mkdir -p "$TARGET_ROOT_HOME"
        check_command "创建目录失败" "目标目录创建成功"
    fi
    print_info "目录 $TARGET_ROOT_HOME 已就绪。"
}

# 模块：清理系统
module_clean_system() {
    print_info "正在清理系统..."
    apt clean
    apt autoremove --purge -y
    rm -rf /var/cache/apt/archives/*
    rm -rf /tmp/*
    check_command "系统清理失败" "系统清理成功"
}

# 主函数，按顺序调用各个模块
main() {
    # 1. 先进行交互
    module_collect_config
    module_confirm_config

    # 2. 检查权限
    check_root
    
    # 3. 执行核心初始化
    module_update_upgrade_system
    module_install_common_tools
    module_set_timezone
    module_install_ssh_copy_id
    module_install_and_configure_ssh
    module_increase_history_size

    # 4. 根据之前的选择安装面板
    if [[ "$INSTALL_PANEL" == "casaos" ]]; then
        module_install_casaos
    elif [[ "$INSTALL_PANEL" == "1panel" ]]; then
        module_install_1panel
    fi

    # 5. 最后处理目录和清理
    module_change_root_home
    module_clean_system
    
    print_info "------------------------------------------------"
    print_info "初始化配置完成！"
    print_info "1. 请手动运行 'source /etc/profile' 或重新登录以应用历史记录设置。"
    print_info "2. 建议重启服务器以确保所有更改生效。"
    print_info "------------------------------------------------"
}

# 执行主函数
main "$@"
