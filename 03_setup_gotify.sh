#!/bin/bash

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then
    echo "[ERROR] 请使用 root 权限运行此脚本 (sudo ./setup_gotify_notify.sh)"
    exit 1
fi

# 交互式输入
read -rp "请输入 Gotify 服务器地址 (如 https://gotify.example.com): " GOTIFY_URL
read -rp "请输入 Gotify Token: " GOTIFY_TOKEN
read -rp "请输入服务器名称 (server_name): " SERVER_NAME

# 检查输入是否为空
if [[ -z "$GOTIFY_URL" || -z "$GOTIFY_TOKEN" || -z "$SERVER_NAME" ]]; then
    echo "[ERROR] 所有输入项均不能为空，请重新运行脚本。"
    exit 1
fi

LOCAL_SCRIPT_PATH="/opt/gotify_startup_notify.sh"

echo "[INFO] 正在生成 $LOCAL_SCRIPT_PATH..."

# 直接生成脚本，变量在生成时替换
cat > "$LOCAL_SCRIPT_PATH" <<EOF
#!/bin/bash
# 自动生成的 Gotify 启动通知脚本
curl -X POST "${GOTIFY_URL}/message?token=${GOTIFY_TOKEN}" \
    -F "title=服务器启动通知" \
    -F "message=服务器 [ ${SERVER_NAME} ] 已启动" \
    -F "priority=5"
EOF

chmod +x "$LOCAL_SCRIPT_PATH"

# 配置 systemd 服务
SERVICE_FILE="/etc/systemd/system/gotify-notify.service"

echo "[INFO] 正在配置 systemd 服务 $SERVICE_FILE..."

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Gotify Startup Notification
After=network.target

[Service]
ExecStart=$LOCAL_SCRIPT_PATH
Type=oneshot
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable gotify-notify.service

echo "[INFO] 脚本已成功配置。Gotify 通知将在每次开机联网后自动发送。"