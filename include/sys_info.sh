#!/bin/bash
# ==============================================================================
# [DEPRECATED] 此脚本已整合至 deploy.sh
# 建议使用: ./deploy.sh --sys-info (需 root 身份)
# 此文件保留以确保向后兼容，不再主动维护新功能。
# ==============================================================================

# ==============================================================================
# Project: pve-lxc-init
# Script: sys_info.sh
# Description: Lightweight system diagnostic tool for hardware and OS status.
# Usage: ./sys_info.sh
# ==============================================================================

# ---------------------------- 样式配置 ----------------------------
TITLE_COLOR="\e[1;34m"
END_COLOR="\e[0m"

echo -e "\n${TITLE_COLOR}===================== 核心硬件概况 =====================${END_COLOR}"

# 获取处理器架构与核心拓扑
echo "CPU 状态:"
lscpu | grep -E "Architecture|Model name|CPU MHz|Thread(s) per core|Core(s) per socket|Socket(s)|CPU(s)"

# 获取内存容量与负载情况 (Human Readable)
echo -e "\n内存负载 (Memory Usage):"
free -h | grep Mem

# 获取根分区与关键分区的存储占用情况 (以 /dev/ 开头的物理/逻辑卷)
echo -e "\n存储磁盘 (Disk Partition - /dev/):"
df -h | grep -E "^/dev/"

# 获取所有活跃网络接口及其 IP 绑定地址
echo -e "\n网络链路 (Network Interface & IP):"
ip addr show | grep -E "inet|ether"

echo -e "\n${TITLE_COLOR}===================== 操作系统环境 =====================${END_COLOR}"

# 获取系统版本信息 (支持 LSB 及通用 os-release)
echo "系统发行版 (Distribution):"
lsb_release -a 2>/dev/null || cat /etc/os-release | grep "PRETTY_NAME"

# 获取运行中的内核版本
echo -e "\n内核版本 (Kernel):"
uname -a

# 系统连续运行时间 (Pretty print)
echo -e "\n运行时长 (Uptime):"
uptime -p

# 获取系统负载平衡情况
echo -e "\n负载表现 (Load Avg):"
uptime

# 当前已登录的高级交互用户列表
echo -e "\n活跃会话 (Active Users):"
w

echo -e "\n${TITLE_COLOR}===================== 活跃服务监控 =====================${END_COLOR}"

# 打印当前正在运行的前 15 个 systemd 服务，过滤掉用户级服务 (@)
systemctl list-units --type=service --state=running | grep -v "@" | head -n 15

echo -e "\n${TITLE_COLOR}=======================================================${END_COLOR}"
