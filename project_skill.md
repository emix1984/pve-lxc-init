# 项目技能文档

## 技术栈

| 技术 | 用途 |
|------|------|
| Bash | 全部脚本实现语言 |
| systemd (service/timer) | 开机/关机通知、定时系统报告、Peer 连通性监控 |
| systemd-logind | 笔记本合盖/睡眠行为控制 |
| LVM2 | 根分区逻辑卷管理 |
| Tailscale | 自愈网络与 Peer 连通性检测 |
| Gotify API | 消息推送 (支持 JSON/form-data) |
| jq | JSON 格式化构建 |

## 关键设计决策

### 1. TTY 检测实现交互/非交互双模式

```bash
if [ ! -t 0 ]; then
    # 非交互模式 (systemd / pipe)
else
    # 交互模式 (有 TTY)
fi
```

通过检查 stdin 是否为 TTY 来判断运行上下文，使单个脚本同时支持互动菜单和 systemd 后台执行，无需拆分两个文件。

### 2. 配置传递策略（env 文件）

变量通过 `/etc/default/pve-lxc-init` 持久化，systemd 服务通过 `EnvironmentFile` 读取：
- 互动模式：`load_env()` 加载，`save_env()` 保存
- systemd 模式：`EnvironmentFile=/etc/default/pve-lxc-init`（**Token 不嵌入 ExecStart**）
- 改名/改配置流程：菜单 [10]~[12] 修改 → `save_env()` → 自動生效（無需重新安裝服務）

### 3. JSON 推送降级处理

监控 Agent 优先使用 jq 构建 Markdown 格式 JSON 推送 Gotify，若 jq 不可用（常见于最小化安装），自动降级为 form-data 方式发送：

```bash
json_payload=$(jq -n ...)  # 优先
if [ -z "$json_payload" ]; then
    curl -F "title=..." -F "message=..."  # 降级
fi
```

### 4. Public IP 多源回退

```bash
for src in "https://api.ipify.org" "https://ifconfig.me" "https://icanhazip.com"; do
    public_ip=$(curl -s --max-time 5 "$src" | grep -Eo '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')
    [ -n "$public_ip" ] && break
done
```

三个源依次尝试，任一成功即跳出循环，避免单点故障。

### 5. 冪等配置处理

```bash
ensure_config() {
    local pattern="$1" line="$2" file="$3"
    if grep -q "$pattern" "$file"; then
        sed -i "s|^$pattern.*|$line|" "$file"  # 替换
    else
        echo "$line" >> "$file"  # 追加
    fi
}
```

确保 SSH、logind 等配置文件的修改是幂等的，重复执行不会产生重复行。

### 6. 配置持久化策略 (env 文件)

使用 `/etc/default/pve-lxc-init` 保存 DEVICE_NAME/GOTIFY_URL/GOTIFY_TOKEN/TARGET_PEER_IP：

```bash
load_env() {  if [ -f "$ENV_FILE" ]; then source "$ENV_FILE"; fi  }
save_env() { cat > "$ENV_FILE" <<EOF ...; chmod 600 "$ENV_FILE"; }
```

**关键设计**：systemd 服务通过 `EnvironmentFile=/etc/default/pve-lxc-init` 读取配置，Token 不嵌入 ExecStart。修改配置後自動生效，無需重裝服務。

### 7. Peer 断连三级强制重启

```bash
reboot --force --force 2>/dev/null || reboot -ff 2>/dev/null || echo b > /proc/sysrq-trigger
```

- 第一级：`reboot --force --force` — systemd 最大强制级别，直接调用 reboot syscall
- 第二级：`reboot -ff` — 短参数降级
- 第三级：`echo b > /proc/sysrq-trigger` — Magic SysRq 内核级重启，几乎不可阻挡

## 踩坑记录

| 问题 | 原因 | 解决 |
|------|------|------|
| `lvextend` 后文件系统未识别 | LVM 扩展后需独立执行 `resize2fs` 或 `xfs_growfs` | 根据 `df -T` 检测文件系统类型后分别处理 |
| `tailscale status` 误判 | 首次安装后未启动 | 增加 `systemctl restart tailscaled` 自动恢复逻辑 |
| `hostname -I` 返回多个 IP | 容器有多个网络接口 | 用 `awk '{print $1}'` 取第一个 IPv4 |
| `/proc/uptime` 与 `uptime -p` 输出不一致 | `uptime -p` 在短运行时间时格式不同 | 改用 `/proc/uptime` 秒数自行计算天/时/分 |
| form-data 换行符显示问题 | 訊息中用 `\n` 字面字符串而非實際換行 | 改用 heredoc 構建純文字訊息，所有 Gotify 推送訊息統一更換 |
| systemd timer OnCalendar 格式 | `0:00/2:00` 全天偶數小時推送 | 鎖定 `OnCalendar=*-*-* 0:00/2:00`（00:00, 02:00, ... 22:00） |
| 测试监控推送功能 | 需要手动执行系统监控并推送到 Gotify | 菜单选项 [3] --test-monitor 自动执行并显示结果 |
| Token 明文嵌入 systemd ExecStart | `--GotifyToken "${GOTIFY_TOKEN}"` 任何能讀 service 文件的用戶都可看到 Token | 改為 `EnvironmentFile=/etc/default/pve-lxc-init`，修改配置無需重裝服務 |
| `_send_system_report` 共享函數 | `module_test_monitor` 和 `module_gotify_report_run` 重複 200+ 行指標採集代碼 | 提取 `_build_system_report_msg()` + `_send_system_report()`，兩模組各減至十餘行 |
| form-data 降级推送缺少 Markdown 格式 | jq 不可用時降級為 form-data，未傳 `extras::client::display::contentType=text/markdown` | form-data 路径补上 `-F "extras::client::display::contentType=text/markdown"` |
| CPU 計算顯示 `-inf%` | `awk` 輸出科學記號 `2.19e+09`，bash `$(( ))` 無法解析 | 全在 awk 內計算（`printf "%s\n%s\n"` 傳遞兩行，`NR==1/NR==2` 處理） |
| 記憶體顯示錯誤 (`5.5 / 1.6 GB`) | `read -r _ mem_total_mb mem_used_mb _` 多吞一個 `_`，`free -m` 的 `total/used/free` 錯位賦值 | 改為 `read -r mem_total_mb mem_used_mb _` |
| Top3 進程顯示全部進程 | `ps \| awk` 後缺少 `head -n 3` 限制 | 在 awk 前加 `head -n 3` |
| Markdown 單換行折疊 | Markdown 中單換行等於空格，同段落內多行被合併 | 相鄰項目間添加空行強制分段；同組指標用 ` ` 分隔保持同行 |
| Markdown `###` 標題渲染字體過大 | Gotify Markdown 渲染 `###` 為大號字體，推送訊息顯得很粗壯 | 改用 `**bold**` 替代 `###`，字體適中清爽；移除 `---` 和 emoji 精簡版面 |
| `save_env()` flag 模式下未調用 | `module_install_gotify` 中 `save_env` 在 `if [ -z "$GOTIFY_URL" ]` 內部，flag 模式變數已設跳過該分支 | 移出 `if` 塊，無條件調用 `save_env` |
| `ExecStart` 路徑指向 `/tmp/` 等臨時目錄 | `ABS_SCRIPT_DIR` 使用 `$(dirname "$0")`，下載到 `/tmp` 執行後 path 寫死到臨時位置 | 安裝時複製腳本至 `/opt/pve-lxc-init/`，`ExecStart` 指向固定路徑 |
| tailscale 模組引用未定義變量 `ABS_SCRIPT_DIR` | `module_tailscale_peer_monitor_install` 中 `ExecStart=${ABS_SCRIPT_DIR}/deploy.sh`，該變量僅在 gotify 模組定義為 local | 改為 `TS_SCRIPT_DIR` 並在函數內定義 |
| 無 systemd 環境（如部分 LXC）無法註冊 timer | 容器無 systemd 但可能有 cron | 新增 `_has_systemd()` / `_has_crond()` 檢測，自動降級到 `/etc/cron.d/` 寫入定時任務 |
