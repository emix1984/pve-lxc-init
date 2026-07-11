# 架构设计文档

## 项目概述

pve-lxc-init 是一套用于 PVE LXC 容器环境（Debian/Ubuntu）的服务器初始化与管理工具，提供从系统初始化到监控告警的完整运维能力。

## 架构图

```
┌─────────────────────────────────────────────────────────────────┐
│                        deploy.sh (入口)                          │
│  ┌────────── TTY 检测 ──────────┐                                │
│  │ 有 TTY + 无参数 → 互动菜单    │  无 TTY / 有参数 → --flag 模式  │
│  └──────────────────────────────┘                                │
├─────────────────────────────────────────────────────────────────┤
│                       模块层                                      │
│  ┌───────────┐ ┌─────────────────────────────────────────────┐   │
│  │  --init   │ │              --gotify                       │   │
│  │系统初始化  │ │  开机通知 + 关机预警 + 定时系统报告 (每2h)   │   │
│  └───────────┘ └─────────────────────────────────────────────┘   │
│  ┌──────────────────┐ ┌──────────────────────────────────────┐   │
│  │ --tailscale-install│ │    --tailscale-peer-monitor / --tailscale-peer-monitor-  │   │
│  │ 安装 + 自动更新   │ │    install                            │   │
│  └──────────────────┘ │  Tailscale 自愈 + Tailscale Peer 连通性 + 重启  │   │
│                        └──────────────────────────────────────┘   │
│  ┌───────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────────┐   │
│  │--ssh-key  │ │--sys-info│ │--extend-  │ │ --lid-sleep      │   │
│  │SSH密钥部署 │ │系统信息   │ │lvm       │ │ 合盖禁用          │   │
│  └───────────┘ └──────────┘ └──────────┘ └──────────────────┘   │
│  ┌──────────────────┐                                           │   │
│  │ --test-monitor   │ │  立即执行系统监控并推送测试报告        │   │
│  └──────────────────┘                                           │   │
├─────────────────────────────────────────────────────────────────┤
│                       共用层                                      │
│                    include/common.sh                             │
│  (print/check_root/check_command/ensure_config/backup_file/     │
│   send_gotify)                                                   │
└─────────────────────────────────────────────────────────────────┘
```

## 核心流程

### 1. 服务器初始化 (--init)
```
[交互模式] 面板选择 → 时区 → 工作目录 → Root密码 → Gotify配置
→ 确认摘要 → 系统更新 → 工具安装 → SSH 调优 → 密码设定
→ 历史记录扩容 → 面板安装 → 系统清理
→ 后置安装 Gotify (通知 + 定时监控)
```

```
非交互模式: 系统更新 → 安装工具包 → 时区同步 → SSH 调优
→ 历史记录扩容 → 建立工作目录 → 系统清理 (跳过密码/面板/Gotify)
```

### 2. Gotify 推送 (--gotify)
```
收集 URL/Token → 部署开机通知 (gotify-startup.service)
→ 部署关机预警 (gotify-shutdown.service)
→ 部署定时系统报告 (gotify-report.timer, 每 2h 整点)
```

### 3. Tailscale Peer 连通性监控 (--tailscale-peer-monitor / --tailscale-peer-monitor-install)
```
Phase A: 参数初始化 (URL/Token/Device/PeerIP)
Phase B: Tailscale 健康检查 → 自愈重启 → 自动更新
        → Peer 连通性测试 → 失联触发 Docker 安全停止 + 三级强制重启
Phase C: systemd timer 注册 (tailscale-peer-monitor.timer, 每 2h 整点)
```

### 4. Peer 断连强制重启
```
Peer 不可达 → Docker 容器安全停止
           → 发送紧急 Gotify (Priority 10)
           → 三级重启链:
             ① reboot --force --force (内核级重启syscall)
             ② reboot -ff (降级)
             ③ echo b > /proc/sysrq-trigger (Magic SysRq, 最终核弹)
```

### 5. Tailscale 安装 (--tailscale-install)
```
官方脚本安装 → systemctl enable+start tailscaled
→ tailscale set --auto-update=true
→ 引导 tailscale up 认证
→ 可选设定 Peer IP
```

## 数据流

```
deploy.sh 变量 (DEVICE_NAME/GOTIFY_URL/GOTIFY_TOKEN/TARGET_PEER_IP)
    │
    ├── → save_env: 写入 /etc/default/pve-lxc-init (持久化)
    ├── → load_env: 启动时读取 (仅互动菜单)
    ├── → module_install_gotify: embed 到 /opt/gotify_*.sh + gotify-report service
    ├── → module_gotify_report_run: systemd 定时执行 (纯指标)
    └── → module_tailscale_peer_monitor_run/install: embed 到 tailscale-peer-monitor service/timer
```

## 配置文件与路径

| 资源 | 路径 |
|------|------|
| 入口脚本 | `/opt/pve-lxc-init/deploy.sh` |
| 配置模板 | `.env.sample` (專案根目錄，可推送 GitHub) |
| 共用库 | `include/common.sh` |
| 持久化配置 (env) | `/etc/default/pve-lxc-init` (chmod 600) |
| 开机通知脚本 | `/opt/gotify_startup.sh` |
| 关机通知脚本 | `/opt/gotify_shutdown.sh` |
| 系统报告 service | `/etc/systemd/system/gotify-report.service` |
| 系统报告 timer | `/etc/systemd/system/gotify-report.timer` |
| 开机通知 service | `/etc/systemd/system/gotify-startup.service` |
| 关机通知 service | `/etc/systemd/system/gotify-shutdown.service` |
| Tailscale Peer 监控 service | `/etc/systemd/system/tailscale-peer-monitor.service` |
| Tailscale Peer 监控 timer | `/etc/systemd/system/tailscale-peer-monitor.timer` |
| 错误日志 | `report_error.log` (与 deploy.sh 同目录) |
