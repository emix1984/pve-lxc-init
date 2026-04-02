#!/bin/bash

# ==============================================================================
# Project: pve-lxc-init
# Script: 05_extend_lvm_root.sh
# Description: 自动扩展 LVM 根分区至卷组最大可用空间。
# Features: 自动识别根逻辑卷、检测卷组剩余空间、扩展 LV 并调整文件系统（支持 ext4/xfs）。
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
        print_error "权限不足：请使用 root 身份或 sudo 运行此脚本 (sudo ./05_extend_lvm_root.sh)"
        exit 1
    fi
}

# 检查依赖命令是否存在
check_dependencies() {
    local deps=("lvdisplay" "vgs" "lvextend" "resize2fs" "xfs_growfs")
    local missing=()
    
    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        print_error "缺少必要的 LVM 工具：${missing[*]}"
        print_info "请先安装 LVM2: apt install lvm2"
        exit 1
    fi
    
    print_success "LVM 工具链检查通过"
}

# ---------------------------- 系统检测模块 ----------------------------

# 检查是否为 LVM 根分区
check_lvm_root() {
    print_info "正在检测根分区类型..."
    
    # 获取根挂载点对应的设备
    local root_device
    root_device=$(df -hP | grep ' /$' | awk '{print $1}')
    
    if [[ -z "$root_device" ]]; then
        print_error "未找到根挂载点，请检查系统配置"
        exit 1
    fi
    
    # 检查是否为 LVM 逻辑卷（格式通常为 /dev/mapper/xxx 或 /dev/dm-xxx）
    if [[ "$root_device" =~ ^/dev/(mapper|dm)- ]]; then
        ROOT_LV_PATH="$root_device"
        print_success "检测到根分区为 LVM 逻辑卷：$ROOT_LV_PATH"
        return 0
    else
        print_info "根分区不是 LVM 逻辑卷（当前设备：$root_device）"
        print_error "此脚本仅适用于 LVM 管理的根分区"
        exit 1
    fi
}

# 获取卷组名称
get_vg_name() {
    print_info "正在获取卷组名称..."
    
    VG_NAME=$(lvdisplay "$ROOT_LV_PATH" | grep "VG Name" | awk '{print $3}')
    
    if [[ -z "$VG_NAME" ]]; then
        print_error "无法获取卷组名称"
        exit 1
    fi
    
    print_success "卷组名称：$VG_NAME"
}

# 检查卷组剩余空间
check_vg_free_space() {
    print_info "正在检查卷组剩余空间..."
    
    # 获取可用空间（单位：GB）
    FREE_SPACE=$(vgs --noheadings --units g -o vg_free "$VG_NAME" | awk '{gsub(/g/,""); print $1}')
    
    # 转换为浮点数比较
    if (( $(echo "$FREE_SPACE <= 0.01" | bc -l 2>/dev/null || echo "1") )); then
        print_error "卷组没有足够可用空间（当前可用：${FREE_SPACE}G）"
        print_info "请先扩展物理卷或添加新的 PV"
        exit 1
    fi
    
    print_success "卷组可用空间：${FREE_SPACE}G"
}

# 检测文件系统类型
detect_filesystem() {
    print_info "正在检测文件系统类型..."
    
    FS_TYPE=$(df -T | grep "$ROOT_LV_PATH" | awk '{print $2}')
    
    case "$FS_TYPE" in
        ext4)
            print_success "文件系统类型：ext4"
            ;;
        xfs)
            print_success "文件系统类型：xfs"
            ;;
        *)
            print_error "不支持的文件系统类型：$FS_TYPE"
            print_info "本脚本仅支持 ext4 和 xfs 文件系统"
            exit 1
            ;;
    esac
}

# ---------------------------- 核心配置模块 ----------------------------

# 模块：备份 LVM 配置
module_backup_lvm_config() {
    local backup_dir="/root/lvm_backup_$(date +%Y%m%d_%H%M%S)"
    
    print_info "正在备份 LVM 配置..."
    
    mkdir -p "$backup_dir"
    
    # 备份卷组元数据
    vgcfgbackup -f "$backup_dir/vg_${VG_NAME}.cfg" "$VG_NAME" 2>/dev/null || true
    
    # 记录当前逻辑卷信息
    lvdisplay > "$backup_dir/lv_before.txt" 2>/dev/null || true
    vgs > "$backup_dir/vg_before.txt" 2>/dev/null || true
    
    print_success "LVM 配置已备份至：$backup_dir"
}

# 模块：扩展逻辑卷
module_extend_logical_volume() {
    print_info "正在扩展逻辑卷 $ROOT_LV_PATH 至卷组最大空间..."
    
    # 扩展逻辑卷，使用 100% 的剩余空间
    lvextend -l +100%FREE "$ROOT_LV_PATH"
    check_command "逻辑卷扩展失败" "逻辑卷已成功扩展"
}

# 模块：调整文件系统大小
module_resize_filesystem() {
    print_info "正在调整文件系统大小以匹配新的逻辑卷容量..."
    
    case "$FS_TYPE" in
        ext4)
            print_info "检测到 ext4 文件系统，使用 resize2fs..."
            resize2fs "$ROOT_LV_PATH"
            check_command "ext4 文件系统扩容失败" "ext4 文件系统已成功扩容"
            ;;
        xfs)
            print_info "检测到 xfs 文件系统，使用 xfs_growfs..."
            xfs_growfs /
            check_command "xfs 文件系统扩容失败" "xfs 文件系统已成功扩容"
            ;;
    esac
}

# 模块：验证扩容结果
module_verify_expansion() {
    print_info "正在验证扩容结果..."
    echo "------------------------------------------------"
    
    # 显示扩容后的逻辑卷信息
    print_info "逻辑卷信息："
    lvdisplay "$ROOT_LV_PATH" | grep -E "LV Size|LV Name"
    
    echo ""
    print_info "卷组信息："
    vgs --noheadings -o vg_name,vg_size,vg_free "$VG_NAME"
    
    echo ""
    print_info "根分区使用情况："
    df -h /
    
    echo "------------------------------------------------"
    print_success "扩容完成！"
}

# ---------------------------- 主执行逻辑 (Main) ----------------------------

main() {
    print_info "=========================================="
    print_info "LVM 根分区自动扩展工具"
    print_info "=========================================="
    
    # 环境检查
    check_root
    check_dependencies
    check_lvm_root
    get_vg_name
    check_vg_free_space
    detect_filesystem
    
    # 执行扩容流程
    module_backup_lvm_config
    module_extend_logical_volume
    module_resize_filesystem
    module_verify_expansion
    
    echo -e "\n\033[1;32m🎉 恭喜！LVM 根分区扩展已完成。\033[0m"
    echo "------------------------------------------------"
    print_info "重要提示："
    echo "  - 备份文件保存在：/root/lvm_backup_*"
    echo "  - 如需回滚，可使用 vgcfgrestore 恢复配置"
    echo "  - 建议检查系统日志确保无异常"
    echo "------------------------------------------------"
}

# 脚本入口
main "$@"
