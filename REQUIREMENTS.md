# 需求文档

## 已完成需求

- [x] 服务器一键初始化（系统更新、工具安装、SSH调优、时区同步）
- [x] SSH 密钥免密部署
- [x] Gotify 开机/关机通知推送
- [x] 笔记本合盖睡眠禁用
- [x] LVM 根分区自动扩容
- [x] 系统信息诊断查询
- [x] 统一入口脚本 deploy.sh（互动菜单 + --flag 参数模式）
- [x] 机器名称自定义（非交互模式通过 --Device 参数传入）
- [x] Gotify 监控 Agent（Tailscale 自愈 + 资源采集 + 每 2h 推送）
- [x] systemd timer 自动注册（OnBootSec=5min, OnUnitActiveSec=2h, Persistent=true）
- [x] Peer 断连紧急重启流程（Priority 10 通知 → reboot --force）
- [x] jq/form-data 双模式 JSON 推送降级
- [x] Public IP 多源回退采集
- [x] LVM 配置备份与元数据记录

## 待优化/衍生需求

- [ ] 支持 Telegram / Slack 作为 Gotify 之外的备用通知渠道
- [ ] 监控 Agent 增加磁盘 I/O 和网络带宽统计
- [ ] deploy.sh 支持 `--uninstall` 移除所有 systemd 单元和脚本
- [ ] 支持配置文件外挂（允许用户通过外部文件覆写默认参数）
- [ ] 多语言支持（准备英文版输出）
