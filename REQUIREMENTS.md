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
- [x] systemd timer 自动注册（OnCalendar=*-*-* 10:00/2:00）
- [x] 菜单选项 [3] 测试监控推送（立即验证推送功能）
- [x] Peer 断连紧急重启流程（Priority 10 通知 → 三级内核级重启链）
- [x] jq/form-data 双模式 JSON 推送降级
- [x] Public IP 多源回退采集
- [x] LVM 配置备份与元数据记录
- [x] 持久化 env 配置 `/etc/default/pve-lxc-init`（chmod 600 保护 token）
- [x] 选项 1 整合 Gotify 安装 + 确认摘要
- [x] 脚本全量移除 sudo 依赖，仅以 root 身份运行
- [x] 监控 Agent 强制重启升级为三级内核级：`--force --force` → `-ff` → `Magic SysRq`
- [x] 全面支援 Ubuntu 24.04 / 26.04、Debian 12 / 13
- [x] 新增 .env.sample 配置模板（可安全推送 GitHub）
- [x] 新增 xfsprogs 套件（XFS 根目錄擴容支援）
- [x] 移除已棄用 net-tools 套件
- [x] 新增 lsb-release 套件（系統資訊輸出更完整）
- [x] 獨立 Tailscale 安裝選單 (選項 4)，含自動更新與認證引導
- [x] 提取共享函數 _build_system_report_msg() / _send_system_report()，消除 ~200 行重複代碼
- [x] systemd 服務改用 EnvironmentFile=/etc/default/pve-lxc-init，Token 不再嵌入 ExecStart
- [x] 全面清除 $? race condition，統一使用 if ! 模式
- [x] 移除未使用的 check_command() 函數
- [x] 診斷功能增加直接 curl 測試（顯示 HTTP 狀態碼和伺服器響應）

## 待优化/衍生需求

- [ ] 支持 Telegram / Slack 作为 Gotify 之外的备用通知渠道
- [ ] 监控 Agent 增加磁盘 I/O 和网络带宽统计
- [ ] deploy.sh 支持 `--uninstall` 移除所有 systemd 单元和脚本
- [ ] 多语言支持（准备英文版输出）
- [x] 修复 systemd timer OnCalendar 格式（`*-*-* 0:00/2:00` → `10:00/2:00`，从 10:00 开始推送）
- [x] 修复 form-data 换行符显示问题（引號包裹导致 `"\n"` 而非实际换行）
