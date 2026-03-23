# CustomizeServerEnvironment
Ubuntu Server 22.04 LTS (Jammy Jellyfish) 自动化初始化工具集。

## ⚙️ 预设项 (Preset)
- **核心**: openssh-server, sudo
- **可选面板**: CasaOS, 1Panel
- **通知系统**: Gotify (自动生成 systemd 服务)
- **历史记录**: HISTSIZE=99999 (持久化保存命令行历史)

---

## 🚀 快速开始

### 1. 服务器初始化 (核心脚本)
集成交互式配置收集，支持一键更新、时区同步、SSH 优化及面板安装。

```bash
apt update && apt install -y curl && \
curl -fsSL -o 01_init_server.sh https://github.com/emix1984/CustomizeServerEnvironment/raw/main/01_init_server.sh && \
bash 01_init_server.sh
```

### 2. 免密登录部署 (SSH Key)
将本地公钥快速推送至远程服务器，支持交互式选择端口及主机。

```bash
apt update && apt install -y curl && \
curl -fsSL -o 02_deploy_ssh_key.sh https://github.com/emix1984/CustomizeServerEnvironment/raw/main/02_deploy_ssh_key.sh && \
bash 02_deploy_ssh_key.sh
```

### 3. Gotify 启动通知
为服务器配置开机自动发送 Gotify 消息提醒。

```bash
apt update && apt install -y curl && \
curl -fsSL -o 03_setup_gotify.sh https://github.com/emix1984/CustomizeServerEnvironment/raw/main/03_setup_gotify.sh && \
bash 03_setup_gotify.sh
```

### 4. 系统信息诊断
快速查看硬件、内核、网络分布及其它运行状态。

```bash
apt update && apt install -y curl && \
curl -fsSL -o sys_info.sh https://github.com/emix1984/CustomizeServerEnvironment/raw/main/sys_info.sh && \
bash sys_info.sh
```

---

## 🛡️ 安全提示 (Security)
- 脚本默认开启 `PermitRootLogin yes` 及 `PasswordAuthentication yes` (方便测试 lab)。
- 在完成 `02_deploy_ssh_key.sh` 部署后，强烈建议从安全性角度手动禁用密码登录。

## 📂 目录结构
- `01_init_server.sh`: 系统库更新、常用命令历史设置、SSH 服务优化、面板多选安装。
- `02_deploy_ssh_key.sh`: 本地公钥分发至远程主机。
- `03_setup_gotify.sh`: Gotify 开机自启通知服务配置。
- `sys_info.sh`: 轻量级硬件与系统状态查询脚本。
