# 🛠️ pve-lxc-init 

**专为 PVE LXC 容器 (Debian/Ubuntu) 设计的一键自动化初始化工具集。**

本仓库旨在解决新创建容器后的重复性配置工作，通过模块化脚本实现从“基础环境优化”到“监控预警”的全流程覆盖。

---

## ⚙️ 核心预设 (Preset Features)
- **🔥 全自动初始化**: 更新源、部署运维工具、同步全球时区、SSH 访问调优。
- **📜 审计强化**: 扩容 Shell 命令行历史记录 (`HISTSIZE=99999`)，确保持久化追踪。
- **📊 面板可选**: 交互式预设 CasaOS 或 1Panel 数据管理面板。
- **🔔 智能通知**: 完整的 Gotify 整合方案，支持上线、下线及每日系统心跳报告。
- **📦 幂等性设计**: 脚本多次运行仅更新差异，不会造成配置行冗余或系统冲突。

---

## 🚀 模块化脚本说明

### 1️⃣ 系统环境初始化 (`01_init_server.sh`)
这是项目的核心入口。脚本会在执行前先收集用户偏好（面板选择、时区、存储路径），并在展示确认摘要后一次性完成所有底层配置。

```bash
# 建议以 root 身份运行
apt update && apt install -y curl && \
curl -fsSL -o 01_init_server.sh https://github.com/emix1984/pve-lxc-init/raw/main/01_init_server.sh && \
bash 01_init_server.sh
```

### 2️⃣ SSH 密钥自动化部署 (`02_deploy_ssh_key.sh`)
在本地（如 macOS/Linux 终端）运行此脚本，交互式输入 IP 和端口，自动将公钥推送至容器。
*注：脚本会自动检测本地密钥对，若无则自动生成 4096 位 RSA 密钥。*

```bash
curl -fsSL -o 02_deploy_ssh_key.sh https://github.com/emix1984/pve-lxc-init/raw/main/02_deploy_ssh_key.sh && \
bash 02_deploy_ssh_key.sh
```

### 3️⃣ Gotify 综合通知服务 (`03_setup_gotify.sh`)
模块化部署通知系统，为您提供服务器的实时连接状态及昨日运行报告。
- **功能 A**: 开机联网自动上线通知。
- **功能 B**: 关机/重启触发的离线预警。
- **功能 C**: 每日凌晨 03:00 推送系统心跳（负载与时长报告）。

```bash
apt update && apt install -y curl && \
curl -fsSL -o 03_setup_gotify.sh https://github.com/emix1984/pve-lxc-init/raw/main/03_setup_gotify.sh && \
bash 03_setup_gotify.sh
```

### 4️⃣ 轻量级信息诊断 (`sys_info.sh`)
彩色输出系统画像，包含 CPU 拓扑、内存负载、存储分布、当前活跃用户及 Systemd 服务运行清单。

```bash
curl -fsSL -o sys_info.sh https://github.com/emix1984/pve-lxc-init/raw/main/sys_info.sh && \
bash sys_info.sh
```

---

## 📂 项目结构 (Structure)
```text
pve-lxc-init/
├── 01_init_server.sh       # 核心初始化：时区、SSH、面板安装、历史记录。
├── 02_deploy_ssh_key.sh     # 外围工具：交互式传送公钥、连通性验证。
├── 03_setup_gotify.sh       # 通知中枢：上线、下线、凌晨 3 点心跳报警。
├── sys_info.sh              # 诊断展示：可视化系统健康度报表。
└── README.md                # 部署手册。
```

## 🛡️ 安全与建议
- **SSH 加固**：脚本默认开启 `PermitRootLogin yes` 以方便 Lab 环境调试。在推送完 SSH Key 后，建议将 `sshd_config` 中的 `PasswordAuthentication` 改为 `no` 并开启强密码。
- **生效机制**：部分历史记录扩增需要 `source /etc/profile` 或重新登录才能生效。

---

## 🌐 兼容性报告
- **Ubuntu Server**: 22.04 LTS / 24.04 LTS / 24.10 / 25.04
- **Debian Server**: 12 (Bookworm) / 13 (Trixie)
- **Virtualization**: 特别针对 PVE LXC 容器环境进行了优化（减少了不必要的内核模块依赖检查）。

---
*Created by [emix1984](https://github.com/emix1984). Licensed under MIT.*
