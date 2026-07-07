#!/bin/bash
# ==============================================================================
# [DEPRECATED] 此脚本已整合至 deploy.sh
# 建议使用: ./deploy.sh --ssh-key (需 root 身份)
# 此文件保留以确保向后兼容，不再主动维护新功能。
# ==============================================================================

# ==============================================================================
# Project: pve-lxc-init
# Script: 02_deploy_ssh_key.sh
# Description: Distribute local SSH public key to remote server for passwordless login.
# Compatible Platforms: Locally executed on any Linux/macOS with OpenSSH Client.
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

# ---------------------------- 通用校验工具 ----------------------------

check_command() {
    if [ $? -ne 0 ]; then
        print_error "$1"
        exit 1
    else
        print_success "$2"
    fi
}

# ---------------------------- 交互式配置收集 ----------------------------

echo -e "\n\033[1;34m>>> 正在配置 SSH 公钥自动化部署\033[0m"
echo "------------------------------------------------"

read -rp "请输入远程服务器 IP/域名 [默认: 127.0.0.1]: " REMOTE_HOST
REMOTE_HOST=${REMOTE_HOST:-"127.0.0.1"}

read -rp "请输入远程登录用户名 [默认: root]: " REMOTE_USER
REMOTE_USER=${REMOTE_USER:-"root"}

read -rp "请输入远程 SSH 服务端口 [默认: 22]: " REMOTE_PORT
REMOTE_PORT=${REMOTE_PORT:-"22"}

# ---------------------------- 核心核心模块 ----------------------------

# 模块：密钥对生命周期管理
# 逻辑: 如果找不到 id_rsa，则静默生成一个 4096 位的 RSA 密钥对
module_generate_ssh_key() {
    print_info "步骤 1/3: 检查本地环境密钥对 (Local Keypair)..."
    local key_file="$HOME/.ssh/id_rsa"
    if [ ! -f "$key_file" ]; then
        print_info "未检测到现有密钥，正在生成新的 4096 位 RSA 密钥对..."
        ssh-keygen -t rsa -b 4096 -f "$key_file" -N ""
        check_command "密钥对生成失败，请检查 ~/.ssh 目录写入权限" "本地密钥对生成成功"
    else
        print_success "检测到现有本地密钥对，跳过生成步骤"
    fi
}

# 模块：公钥分发
# 逻辑: 使用 ssh-copy-id 工具将公钥追加到远程主机的 authorized_keys
module_copy_public_key() {
    print_info "步骤 2/3: 正在将公钥推送至远程目标 ${REMOTE_USER}@${REMOTE_HOST}..."
    ssh-copy-id -i "$HOME/.ssh/id_rsa.pub" -p "${REMOTE_PORT}" "${REMOTE_USER}@${REMOTE_HOST}"
    check_command "公钥同步失败，请确远程服务器在线且密码正确" "公钥已成功追加至远程授权列表"
}

# 模块：自动验证
# 逻辑: 使用 BatchMode 强制跳过交互，如果能成功执行命令则说明免密配置成功
module_test_passwordless_login() {
    print_info "步骤 3/3: 正在验证免密登录逻辑..."
    # 调用远程 'id' 命令测试连通性
    ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${REMOTE_PORT}" "${REMOTE_USER}@${REMOTE_HOST}" "id" > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        print_success "验证通过！下次登录将不再请求密码。"
    else
        print_error "连通性测试未响应。可能是由于公钥未被正确加载或端口限制。"
    fi
}

# ---------------------------- 主逻辑 ----------------------------

main() {
    module_generate_ssh_key
    module_copy_public_key
    module_test_passwordless_login
    
    echo "------------------------------------------------"
    print_info "SSH 公钥部署任务执行完毕！"
}

# 执行主程序
main
