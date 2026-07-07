# 项目技能文档

## 技术栈

| 技术 | 用途 |
|------|------|
| Bash | 全部脚本实现语言 |
| systemd (service/timer) | 开机/关机通知、定时监控 Agent |
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

### 2. 名称传递策略（无 config 文件）

机器名称通过以下路径传递，避免维护额外配置文件：
- 互动模式：变量保存在 shell session 中
- systemd 模式：直接 embed 在 service unit 的 ExecStart 参数中
- 改名流程：`deploy.sh` 选项 8 → 重新产生 service unit → daemon-reload

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

## 踩坑记录

| 问题 | 原因 | 解决 |
|------|------|------|
| `lvextend` 后文件系统未识别 | LVM 扩展后需独立执行 `resize2fs` 或 `xfs_growfs` | 根据 `df -T` 检测文件系统类型后分别处理 |
| `tailscale status` 误判 | 首次安装后未启动 | 增加 `systemctl restart tailscaled` 自动恢复逻辑 |
| `hostname -I` 返回多个 IP | 容器有多个网络接口 | 用 `awk '{print $1}'` 取第一个 IPv4 |
| `/proc/uptime` 与 `uptime -p` 输出不一致 | `uptime -p` 在短运行时间时格式不同 | 改用 `/proc/uptime` 秒数自行计算天/时/分 |
