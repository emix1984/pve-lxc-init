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

# 交互式设定远程服务器信息 (增强灵活性)
read -rp "请输入远程服务器 IP/域名 [默认: 127.0.0.1]: " REMOTE_HOST
REMOTE_HOST=${REMOTE_HOST:-"127.0.0.1"}

read -rp "请输入远程用户名 [默认: root]: " REMOTE_USER
REMOTE_USER=${REMOTE_USER:-"root"}

read -rp "请输入远程 SSH 端口 [默认: 22]: " REMOTE_PORT
REMOTE_PORT=${REMOTE_PORT:-"22"}

# 模块：生成本地 SSH 密钥对
module_generate_ssh_key() {
    print_info "正在检查本地 SSH 密钥对..."
    local key_file="$HOME/.ssh/id_rsa"
    if [ ! -f "$key_file" ]; then
        print_info "生成新的 RSA 密钥对..."
        ssh-keygen -t rsa -b 4096 -f "$key_file" -N ""
        check_command "生成 SSH 密钥对失败" "SSH 密钥对生成成功"
    else
        print_info "本地 SSH 密钥对已存在，跳过生成步骤"
    fi
}

# 模块：将本地公钥复制到远程服务器
module_copy_public_key() {
    print_info "正在将公钥复制到远程服务器 ${REMOTE_USER}@${REMOTE_HOST}..."
    ssh-copy-id -i "$HOME/.ssh/id_rsa.pub" -p "${REMOTE_PORT}" "${REMOTE_USER}@${REMOTE_HOST}"
    check_command "复制公钥失败，请检查远程连接或密码" "公钥已成功复制到远程服务器"
}

# 模块：测试免密码登录
module_test_passwordless_login() {
    print_info "正在测试免密码登录..."
    # 尝试执行一个简单的远程命令
    ssh -o BatchMode=yes -o ConnectTimeout=5 -p "${REMOTE_PORT}" "${REMOTE_USER}@${REMOTE_HOST}" "id" > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        print_info "免密码登录测试成功！"
    else
        print_error "免密码登录测试失败，请检查之前步骤"
    fi
}

# 主函数
main() {
    module_generate_ssh_key
    module_copy_public_key
    module_test_passwordless_login
    print_info "配置完成。"
}

# 执行主函数
main
