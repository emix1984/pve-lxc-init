#!/bin/bash

# 显示硬件信息
echo "===================== 硬件信息 ====================="
echo "CPU 信息:"
lscpu | grep -E "Architecture|Model name|CPU MHz|Thread(s) per core|Core(s) per socket|Socket(s)|CPU(s)"

echo -e "\n内存信息:"
free -h | grep Mem

echo -e "\n磁盘信息:"
df -h | grep -E "^/dev/"

echo -e "\n网络接口信息:"
ip addr show | grep -E "inet|ether"

# 显示系统信息
echo -e "\n===================== 系统信息 ====================="
echo "系统版本:"
lsb_release -a 2>/dev/null || cat /etc/os-release

echo -e "\n内核版本:"
uname -a

echo -e "\n系统运行时间:"
uptime -p

echo -e "\n系统负载:"
uptime

echo -e "\n已登录用户:"
w

echo -e "\n===================== 服务状态 ====================="
systemctl list-units --type=service --state=running | grep -v "@" | head -n 15
