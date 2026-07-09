# pve-lxc-init

**专为 PVE LXC 容器 (Debian/Ubuntu) 设计的一键自动化初始化工具集。**

本仓库旨在解决新创建容器后的重复性配置工作，通过模块化脚本实现从"基础环境优化"到"监控预警"的全流程覆盖。

---

## 快速开始

### 一键部署（推荐）

```bash
# 下载入口脚本
curl -fsSL -o deploy.sh https://github.com/emix1984/pve-lxc-init/raw/main/deploy.sh && \
chmod +x deploy.sh && ./deploy.sh
```

互动菜单中可选择所有功能模块并自定义机器名称。

### 单次命令模式

```bash
# 全自动初始化 (需 root)
./deploy.sh --init

# 安装 Gotify (通知 + 定时监控) (需 root)
./deploy.sh --gotify --Device MyServer --GotifyUrl https://gotify.example.com --GotifyToken xxxx

# 安装 Peer 连通性监控 (需 root)
./deploy.sh --peer-monitor-install --Device MyServer --GotifyUrl https://gotify.example.com --GotifyToken xxxx --PeerIP 100.114.252.115

# 系统信息查询
./deploy.sh --sys-info
```

---

## 功能清单

### 系统初始化 (`deploy.sh --init`)
- 系统软件包更新与升级
- 安装运维工具（curl, wget, htop, tmux, nano, jq, lvm2, xfsprogs, iputils-ping, lsb-release 等）
- 时区同步（默认 Asia/Seoul，可自定义）
- SSH 配置（开启 root 登录和密码认证）
- Root 密码设置（交互式，默认密码 1234）
- Shell 历史记录扩容 (HISTSIZE=99999)
- 可选面板安装（CasaOS / 1Panel）
- 数据存储目录创建与系统缓存清理

### SSH 密钥部署 (`deploy.sh --ssh-key`)
自动检测/生成 4096 位 RSA 密钥对，通过 ssh-copy-id 推送至远程服务器并验证免密登录。

### Gotify 推送 (`deploy.sh --gotify`)
- **开机通知**: 服务器联网后自动推送上线消息
- **关机预警**: 关机/重启前触发离线通知
- **系统监控报告**: 同时安装定时监控（每 2h 整点推送）

### 笔记本合盖禁用 (`deploy.sh --lid-sleep`)
禁用所有电源模式下的合盖睡眠、挂起键和休眠键，自动备份原始配置文件并验证。

### LVM 根分区扩容 (`deploy.sh --extend-lvm`)
自动识别 LVM 逻辑卷、检测卷组剩余空间、扩展 LV 至 100%FREE、调整文件系统（ext4/xfs），含备份与验证。

### 系统监控报告 (`deploy.sh --gotify-report`)
- **资源采集**: Uptime、RAM/CPU、磁盘、Top3 内存进程
- **网络发现**: Public IP（三源回退）、Local IP、Tailscale IP
- **纯系统指标**，不含 Tailscale/Peer 检测
- **推送频率**: 每 2 小时整点（`OnCalendar=*:0/2`）

### Tailscale 安装 (`deploy.sh --tailscale-install`)
- 官方脚本一键安装 (`curl -fsSL https://tailscale.com/install.sh | sh`)
- 自动启动并启用 tailscaled 服务
- 默认开启自动更新 (`tailscale set --auto-update=true`)
- 引导 `tailscale up` 认证流程
- 自动将 Tailscale IP 设为 Peer IP（可选）

### Peer 连通性监控 (`deploy.sh --peer-monitor / --peer-monitor-install`)
- **Tailscale 自愈**: 守护进程状态检查、自动重启、自动更新
- **Peer 连通性**: 连接检测失败时发送紧急通知（Priority 10）并触发强制重启
- **Docker 保护**: 重启前安全停止所有运行中的容器
- **推送频率**: 每 2 小时整点（`OnCalendar=*:0/2`）

### 系统信息 (`deploy.sh --sys-info`)
彩色输出 CPU 拓扑、内存负载、磁盘分布、网络 IP、系统版本、运行中服务等诊断信息。

---

## 使用场景

### 场景 1：新容器初始化

```bash
./deploy.sh
# 选单: 1 → 初始化, 需要 Gotify 再加 [2]
```

### 一键全自动

```bash
./deploy.sh --init
./deploy.sh --tailscale-install
./deploy.sh --peer-monitor-install --Device "MyServer" --GotifyUrl "https://..." --GotifyToken "..." --PeerIP "100.x.x.x"
```

### 场景 3：改名后同步 systemd

```bash
# 选单选项 8: 输入新名称 → 自动询问是否更新已安装的 timer/通知
```

---

## 项目结构

```text
pve-lxc-init/
├── deploy.sh                  # 统一入口 (互动菜单 + --flag 模式 + systemd 背景)
├── .env.sample                # 配置模板 (cp 至 /etc/default/pve-lxc-init)
├── include/
│   └── common.sh              # 共用工厂函数库
├── docs/
│   └── architecture.md        # 架构设计文档
├── project_skill.md           # 技术栈与踩坑记录
├── REQUIREMENTS.md            # 需求文档
├── agent.md                   # 全局环境配置
└── README.md
```

---

## 安装后生成的 systemd 单元

| 服务名称 | 触发方式 | 功能 |
|---------|---------|------|
| `gotify-startup.service` | 开机 | 推送上线通知 |
| `gotify-shutdown.service` | 关机 | 推送关机预警 |
| `gotify-report.service` | `gotify-report.timer` | 执行系统监控报告 |
| `gotify-report.timer` | 每 2h 整点 | 触发系统监控 |
| `peer-monitor.service` | `peer-monitor.timer` | 执行 Peer 连通性检测 |
| `peer-monitor.timer` | 每 2h 整点 | 触发 Peer 监控 |

---

## 菜单导航

```
============================================
     PVE-LXC-INIT  部 署 管 理 工 具
============================================

-- 常用部署 --
  [1] 一键初始化服务器
  [2] 安装 Gotify (通知 + 定时监控)

-- Tailscale --
  [3] 安装 Tailscale
  [4] 配置 Peer 连通性监控

-- 辅助工具 --
  [5] SSH 密钥免密部署
  [6] 系统信息查询
  [7] LVM 根分区扩容
  [8] 禁用笔记本合盖睡眠

-- 系统设置 --
  [9] 修改机器名称
 [10] 修改 Gotify URL/Token
 [11] 修改 Peer IP
 [12] 系统诊断

  [0] 退出
```

---

## 兼容性

- **Ubuntu Server**: 24.04 LTS / 26.04 LTS
- **Debian Server**: 12 (Bookworm) / 13 (Trixie)
- **Virtualization**: 针对 PVE LXC 容器环境优化
- **Hardware**: 合盖脚本适用于物理笔记本，其余脚本通用

## 安全与建议

- SSH 加固：脚本默认开启 `PermitRootLogin yes`。推送 SSH Key 后建议关闭密码认证。
- LVM 备份：扩容前自动备份至 `/root/lvm_backup_*`，回滚可用 `vgcfgrestore`。
- 日志：监控 Agent 的推送失败记录在 `report_error.log`。

---

*Created by [emix1984](https://github.com/emix1984). Licensed under MIT.*
