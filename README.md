# 🛠️ pve-lxc-init 

**专为 PVE LXC 容器 (Debian/Ubuntu) 设计的一键自动化初始化工具集。**

本仓库旨在解决新创建容器后的重复性配置工作，通过模块化脚本实现从"基础环境优化"到"监控预警"的全流程覆盖。

---

## ⚙️ 核心预设 (Preset Features)
- **🔥 全自动初始化**: 更新源、部署运维工具、同步全球时区、SSH 访问调优。
- **📜 审计强化**: 扩容 Shell 命令行历史记录 (`HISTSIZE=99999`)，确保持久化追踪。
- **📊 面板可选**: 交互式预设 CasaOS 或 1Panel 数据管理面板。
- **🔔 智能通知**: 完整的 Gotify 整合方案，支持上线、下线及每日系统心跳报告。
- **💻 笔记本优化**: 自动禁用合盖睡眠，适用于所有电源模式（电池/外接电源/扩展坞）。
- **💾 LVM 扩容**: 自动扩展根分区至卷组最大可用空间，支持 ext4/xfs 文件系统。
- **📦 幂等性设计**: 脚本多次运行仅更新差异，不会造成配置行冗余或系统冲突。

---

## 🚀 模块化脚本说明

### 1️⃣ 系统环境初始化 (`01_init_server.sh`)
这是项目的核心入口。脚本会在执行前先收集用户偏好（面板选择、时区、存储路径），并在展示确认摘要后一次性完成所有底层配置。

**功能清单：**
- ✅ 系统软件包更新与升级
- ✅ 安装基础运维工具（curl, wget, htop, tmux, nano 等）
- ✅ 时区同步（默认 Asia/Seoul，可自定义）
- ✅ SSH 客户端与服务端配置（开启 root 登录和密码认证）
- ✅ Root 密码设置（交互式，默认密码 1234）
- ✅ Shell 历史记录扩容（HISTSIZE=99999）
- ✅ 可选面板安装（CasaOS / 1Panel）
- ✅ 数据存储目录创建
- ✅ 系统缓存清理

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

### 4️⃣ 笔记本开关盖睡眠配置 (`04_setup_lid_sleep.sh`)
专为 Debian/Ubuntu Server 笔记本设计的睡眠行为配置工具，禁用所有合盖和按键睡眠触发。

**功能清单：**
- ✅ 自动检测设备类型（笔记本/台式机）
- ✅ 禁用合盖睡眠（电池模式）
- ✅ 禁用合盖睡眠（外接电源模式）
- ✅ 禁用合盖睡眠（扩展坞模式）
- ✅ 禁用挂起按键（Suspend Key）
- ✅ 禁用休眠按键（Hibernate Key）
- ✅ 自动备份原始配置文件
- ✅ 配置验证与错误提示

```bash
# 需要 root 权限运行
curl -fsSL -o 04_setup_lid_sleep.sh https://github.com/emix1984/pve-lxc-init/raw/main/04_setup_lid_sleep.sh && \
chmod +x 04_setup_lid_sleep.sh && \
sudo ./04_setup_lid_sleep.sh
```

### 5️⃣ LVM 根分区自动扩展 (`05_extend_lvm_root.sh`)
自动扩展 LVM 管理的根分区至卷组最大可用空间，支持 ext4 和 xfs 文件系统。

**功能清单：**
- ✅ 自动识别 LVM 根逻辑卷
- ✅ 检测卷组剩余空间
- ✅ 识别文件系统类型（ext4/xfs）
- ✅ 备份 LVM 配置（可回滚）
- ✅ 扩展逻辑卷至 100% 可用空间
- ✅ 自动调整文件系统大小
- ✅ 扩容结果验证与报告

```bash
# 需要 root 权限运行，仅适用于 LVM 根分区
curl -fsSL -o 05_extend_lvm_root.sh https://github.com/emix1984/pve-lxc-init/raw/main/05_extend_lvm_root.sh && \
chmod +x 05_extend_lvm_root.sh && \
sudo ./05_extend_lvm_root.sh
```

### 📊 轻量级信息诊断 (`sys_info.sh`)
彩色输出系统画像，包含 CPU 拓扑、内存负载、存储分布、当前活跃用户及 Systemd 服务运行清单。

```bash
curl -fsSL -o sys_info.sh https://github.com/emix1984/pve-lxc-init/raw/main/sys_info.sh && \
bash sys_info.sh
```

---

## 📂 项目结构 (Structure)
```text
pve-lxc-init/
├── 01_init_server.sh       # 核心初始化：系统更新、SSH 配置、Root 密码、面板安装、历史扩容
├── 02_deploy_ssh_key.sh     # SSH 工具：交互式传送公钥、连通性验证
├── 03_setup_gotify.sh       # 通知中枢：上线、下线、凌晨 3 点心跳报警
├── 04_setup_lid_sleep.sh    # 笔记本优化：禁用合盖睡眠、按键睡眠（全电源模式）
├── 05_extend_lvm_root.sh    # LVM 工具：自动扩展根分区至卷组最大空间
├── sys_info.sh              # 诊断展示：可视化系统健康度报表
└── README.md                # 部署手册
```

## 🎯 使用场景推荐

### 场景 1：新服务器初始化
```bash
# 1. 运行基础初始化（推荐首先执行）
sudo ./01_init_server.sh

# 2. 部署 SSH 密钥（从本地机器执行）
./02_deploy_ssh_key.sh

# 3. 配置通知服务（可选）
sudo ./03_setup_gotify.sh
```

### 场景 2：笔记本作为服务器使用
```bash
# 在基础初始化后，禁用合盖睡眠
sudo ./04_setup_lid_sleep.sh
```

### 场景 3：LVM 磁盘空间不足
```bash
# 当卷组有剩余空间但根分区已满时
sudo ./05_extend_lvm_root.sh
```

## 🛡️ 安全与建议
- **SSH 加固**：脚本默认开启 `PermitRootLogin yes` 以方便 Lab 环境调试。在推送完 SSH Key 后，建议将 `sshd_config` 中的 `PasswordAuthentication` 改为 `no` 并开启强密码。
- **生效机制**：部分历史记录扩增需要 `source /etc/profile` 或重新登录才能生效。
- **LVM 备份**：`05_extend_lvm_root.sh` 会自动备份 LVM 配置到 `/root/lvm_backup_*`，如需回滚可使用 `vgcfgrestore`。
- **笔记本配置**：`04_setup_lid_sleep.sh` 修改 `/etc/systemd/logind.conf`，原始配置会备份带时间戳的文件。

---

## 🌐 兼容性报告
- **Ubuntu Server**: 22.04 LTS / 24.04 LTS / 24.10 / 25.04
- **Debian Server**: 12 (Bookworm) / 13 (Trixie)
- **Virtualization**: 特别针对 PVE LXC 容器环境进行了优化（减少了不必要的内核模块依赖检查）。
- **Hardware**: `04_setup_lid_sleep.sh` 适用于物理笔记本设备，其他脚本同样适用于虚拟机和容器。

---

## 🔧 故障排查

### 如何查看脚本执行日志？
所有脚本都会实时输出彩色日志，关键操作会有 `[INFO]`、`[SUCCESS]`、`[ERROR]` 标记。

### 如何回滚配置？
- **SSH 配置**: 使用 `/etc/ssh/sshd_config.bak`
- **logind 配置**: 使用 `/etc/systemd/logind.conf.bak.*`
- **LVM 配置**: 使用 `/root/lvm_backup_*/vg_*.cfg`

### Root 默认密码是多少？
`01_init_server.sh` 中如果直接按回车，默认密码为 `1234`。建议首次登录后立即修改。

---
*Created by [emix1984](https://github.com/emix1984). Licensed under MIT.*
