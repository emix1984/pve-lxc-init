#!/bin/bash
# ==============================================================================
# [DEPRECATED] 此脚本已整合至 deploy.sh
# 建议使用: ./deploy.sh --lid-sleep (需 root 身份)
# 此文件保留以确保向后兼容，不再主动维护新功能。
# ==============================================================================

# ==============================================================================
# Project: pve-lxc-init
# Script: 04_setup_lid_sleep.sh
# Description: 为 Debian/Ubuntu Server 配置笔记本电脑开关盖和睡眠按键行为。
# Features: 禁用合盖睡眠、挂起按键、休眠按键，适用于所有电源模式（电池/外接电源/扩展坞）。
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
# 参数: $1=错误信息，$2=成功信息
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
        print_error "权限不足：请使用 root 身份运行此脚本 (./04_setup_lid_sleep.sh)"
        exit 1
    fi
}

# 幂等配置处理函数：确保文件中配置行的唯一性与准确性
# 逻辑：如果正则匹配到则替换整行，未匹配到则追加到文件末尾
# 参数: $1=匹配正则表达式，$2=完整的配置行，$3=目标文件
ensure_config() {
    local pattern="$1"
    local line="$2"
    local file="$3"
    
    if grep -qE "^#?\s*$pattern" "$file"; then
        # 如果存在（包括注释的），则替换
        sed -i "s|^#\s*$pattern.*|$line|" "$file"
        sed -i "s|^$pattern.*|$line|" "$file"
    else
        # 不存在则追加
        echo "$line" >> "$file"
    fi
}

# ---------------------------- 系统检测模块 ----------------------------

# 检查是否为笔记本电脑
check_laptop() {
    print_info "正在检测设备类型..."
    
    # 检查是否存在电池类设备（笔记本通常有 BAT0 或 BAT1）
    if ls /sys/class/power_supply/BAT* >/dev/null 2>&1; then
        print_success "检测到笔记本电脑环境"
        return 0
    else
        print_info "未检测到电池设备，可能是台式机或服务器"
        read -rp "是否继续配置？(y/n, 默认 n): " confirm
        confirm=${confirm:-"n"}
        if [[ "$confirm" != [yY] ]]; then
            print_info "操作已取消，脚本退出。"
            exit 0
        fi
        return 0
    fi
}

# ---------------------------- 核心配置模块 ----------------------------

# 模块：备份原始配置文件
module_backup_logind_config() {
    local config_file="/etc/systemd/logind.conf"
    local backup_file="${config_file}.bak.$(date +%Y%m%d_%H%M%S)"
    
    print_info "正在备份原始配置文件..."
    
    if [ ! -f "$config_file" ]; then
        print_error "配置文件 $config_file 不存在"
        exit 1
    fi
    
    cp "$config_file" "$backup_file"
    check_command "配置文件备份失败" "配置文件已备份至：$backup_file"
}

# 模块：配置睡眠和开关盖行为
module_configure_lid_sleep() {
    local config_file="/etc/systemd/logind.conf"
    
    print_info "正在配置 systemd-logind 睡眠和开关盖行为..."
    echo "------------------------------------------------"
    echo "目标配置："
    echo "  - HandleSuspendKey=ignore         (禁用挂起按键)"
    echo "  - HandleHibernateKey=ignore       (禁用休眠按键)"
    echo "  - HandleLidSwitch=ignore          (电池供电时合盖不操作)"
    echo "  - HandleLidSwitchExternalPower=ignore (外接电源时合盖不操作)"
    echo "  - HandleLidSwitchDocked=ignore    (连接扩展坞时合盖不操作)"
    echo "------------------------------------------------"
    
    # 配置各项参数
    ensure_config "HandleSuspendKey" "HandleSuspendKey=ignore" "$config_file"
    ensure_config "HandleHibernateKey" "HandleHibernateKey=ignore" "$config_file"
    ensure_config "HandleLidSwitch" "HandleLidSwitch=ignore" "$config_file"
    ensure_config "HandleLidSwitchExternalPower" "HandleLidSwitchExternalPower=ignore" "$config_file"
    ensure_config "HandleLidSwitchDocked" "HandleLidSwitchDocked=ignore" "$config_file"
    
    print_success "logind.conf 配置文件已更新"
}

# 模块：重启 systemd-logind 服务
module_restart_logind() {
    print_info "正在重启 systemd-logind 服务以应用配置..."
    
    systemctl restart systemd-logind
    check_command "重启 systemd-logind 服务失败" "systemd-logind 服务已成功重启"
    
    print_success "所有配置已生效，无需重启系统"
}

# 模块：验证配置结果
module_verify_config() {
    local config_file="/etc/systemd/logind.conf"
    
    print_info "正在验证配置结果..."
    echo "------------------------------------------------"
    
    local success=true
    
    # 逐项检查配置
    if grep -q "^HandleSuspendKey=ignore" "$config_file"; then
        print_success "✓ HandleSuspendKey=ignore"
    else
        print_error "✗ HandleSuspendKey 配置失败"
        success=false
    fi
    
    if grep -q "^HandleHibernateKey=ignore" "$config_file"; then
        print_success "✓ HandleHibernateKey=ignore"
    else
        print_error "✗ HandleHibernateKey 配置失败"
        success=false
    fi
    
    if grep -q "^HandleLidSwitch=ignore" "$config_file"; then
        print_success "✓ HandleLidSwitch=ignore"
    else
        print_error "✗ HandleLidSwitch 配置失败"
        success=false
    fi
    
    if grep -q "^HandleLidSwitchExternalPower=ignore" "$config_file"; then
        print_success "✓ HandleLidSwitchExternalPower=ignore"
    else
        print_error "✗ HandleLidSwitchExternalPower 配置失败"
        success=false
    fi
    
    if grep -q "^HandleLidSwitchDocked=ignore" "$config_file"; then
        print_success "✓ HandleLidSwitchDocked=ignore"
    else
        print_error "✗ HandleLidSwitchDocked 配置失败"
        success=false
    fi
    
    echo "------------------------------------------------"
    
    if [ "$success" = true ]; then
        print_success "所有配置项验证通过！"
    else
        print_error "部分配置项验证失败，请手动检查 $config_file"
        exit 1
    fi
}

# ---------------------------- 主执行逻辑 (Main) ----------------------------

main() {
    print_info "=========================================="
    print_info "笔记本开关盖睡眠配置工具"
    print_info "=========================================="
    
    # 环境检查
    check_root
    check_laptop
    
    # 执行配置流程
    module_backup_logind_config
    module_configure_lid_sleep
    module_restart_logind
    module_verify_config
    
    echo -e "\n\033[1;32m🎉 恭喜！笔记本开关盖配置已完成。\033[0m"
    echo "------------------------------------------------"
    print_info "配置说明："
    echo "  - 合上笔记本盖子不会触发睡眠"
    echo "  - 睡眠键和休眠键将被忽略"
    echo "  - 适用于所有电源模式（电池/外接电源/扩展坞）"
    echo "  - 如需恢复默认设置，可从备份文件还原"
    echo "------------------------------------------------"
}

# 脚本入口
main "$@"
