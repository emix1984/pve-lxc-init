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
│  ┌───────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────────┐   │
│  │  --init   │ │--ssh-key │ │--gotify  │ │ --lid-sleep      │   │
│  │系统初始化  │ │SSH密钥部署│ │通知安装   │ │ 合盖禁用          │   │
│  └───────────┘ └──────────┘ └──────────┘ └──────────────────┘   │
│  ┌───────────┐ ┌──────────┐ ┌──────────────────────────────┐   │
│  │--extend-lvm│ │--sys-info│ │ --monitor / --monitor-install│   │
│  │LVM根分区扩容│ │系统信息   │ │ 监控 Agent + Tailscale 自愈  │   │
│  └───────────┘ └──────────┘ └──────────────────────────────┘   │
├─────────────────────────────────────────────────────────────────┤
│                       共用层                                      │
│                    include/common.sh                             │
│  (print/check_root/check_command/ensure_config/backup_file/     │
│   send_gotify)                                                   │
├─────────────────────────────────────────────────────────────────┤
│                       原有脚本 (deprecated)                       │
│  include/01_init_server.sh  include/02_deploy_ssh_key.sh        │
│  include/03_setup_gotify.sh  include/04_setup_lid_sleep.sh      │
│  include/05_extend_lvm_root.sh  include/sys_info.sh             │
└─────────────────────────────────────────────────────────────────┘
```

## 核心流程

### 1. 服务器初始化 (--init)
```
[交互模式] 面板选择 → 时区 → 工作目录 → Root密码 → Gotify配置询问
→ 确认摘要 → 执行系统初始化 → 后置安装 Gotify 通知/监控 (可选)
```

```
非交互模式: 系统更新 → 安装工具包 → 时区同步 → SSH 调优
→ 历史记录扩容 → 建立工作目录 → 系统清理 (跳过密码/面板/Gotify)
```

### 2. SSH 密钥部署 (--ssh-key)
```
检查密钥对 → 生成(如无) → ssh-copy-id → 免密验证
```

### 3. Gotify 通知系统 (--gotify)
```
收集 URL/Token → 部署开机通知 (gotify-startup.service)
→ 部署关机预警 (gotify-shutdown.service)
```

### 4. 监控 Agent (--monitor / --monitor-install)
```
Phase A: 参数初始化 (URL/Token/Device/PeerIP)
Phase B: Tailscale 健康检查 → 自愈重启 → 自动更新
        → Peer 连通性测试 → 失联触发三级强制重启
Phase C: 指标采集 (Uptime/RAM/CPU/Disk/Top3/Public IP/Local IP/Tailscale IP)
Phase D: JSON 封装 → Gotify 推送 (jq优先, form-data降级)
Phase E: systemd timer 注册 (每 2h)
```

### 5. Peer 断连强制重启
```
Peer 不可达 → 发送紧急 Gotify (Priority 10)
           → 三级重启链:
             ① reboot --force --force (内核级重启syscall)
             ② reboot -ff (降级)
             ③ echo b > /proc/sysrq-trigger (Magic SysRq, 最终核弹)
```

## 数据流

```
deploy.sh 变量 (DEVICE_NAME/GOTIFY_URL/GOTIFY_TOKEN/TARGET_PEER_IP)
    │
    ├── → save_env: 写入 /etc/default/pve-lxc-init (持久化)
    ├── → load_env: 启动时读取 (仅互动菜单)
    ├── → module_gotify_notify: embed 到 /opt/gotify_*.sh
    ├── → module_monitor_run:   运行时引用参数 (systemd走ExecArgs)
    └── → module_monitor_install: embed 到 systemd service unit
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
| 监控 Agent service | `/etc/systemd/system/gotify-monitor.service` |
| 监控 Agent timer | `/etc/systemd/system/gotify-monitor.timer` |
| 开机通知 service | `/etc/systemd/system/gotify-startup.service` |
| 关机通知 service | `/etc/systemd/system/gotify-shutdown.service` |
| 错误日志 | `report_error.log` (与 deploy.sh 同目录) |
