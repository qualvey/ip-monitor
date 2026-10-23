# 🌐 VPS IP Monitor

轻量、可靠的 VPS 出口 IPv4 每日监控与历史记录工具。适用于新开 VPS 一键初始化部署，零额外环境依赖，支持开机自动补跑与多接口冗余容灾。

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![ShellCheck](https://img.shields.io/badge/ShellCheck-Passed-brightgreen.svg)]()

---

## ✨ 特性

- 🚀 **一键极速部署**：单行命令自动化安装，自动安装 `curl` 依赖与配置定时任务。
- 🛡️ **多源冗余容灾**：依次通过 `ip.sb`、`ipify.org`、`icanhazip.com`、`ifconfig.me` 探测出口 IP，严格校验 IPv4 合法性，防止因单点网络抖动导致漏记。
- ⏰ **双定时机制兼容**：
  - **优先使用 Systemd Timer**：支持错峰随机延时（RandomizedDelaySec）与漏跑自动补测（Persistent=true）；
  - **自适应降级 Cron**：在无 Systemd 的精简容器/系统上自动配置系统 Cron 任务。
- 📝 **开箱即用格式**：日志追加记录为 `[YYYY-MM-DD HH:MM:SS] IP`，格式直观，方便审查与审计。
- 🔧 **快捷命令行**：内置软链接全局快捷命令 `ipmonitor`，随手即测。

---

## ⚡ 快速开始（一键安装）

在你的新 VPS 上（支持 Debian / Ubuntu / CentOS / AlmaLinux / RockyLinux / Alpine / Arch 等），直接以 `root` 或 `sudo` 运行：

```bash
curl -fsSL https://raw.githubusercontent.com/qualvey/ip-monitor/main/install.sh | sudo bash
```

> **提示**：如果 VPS 尚未安装 `curl`，也可以使用 `wget`：
> ```bash
> wget -qO- https://raw.githubusercontent.com/qualvey/ip-monitor/main/install.sh | sudo bash
> ```

安装完成后，程序会自动执行一次测试并将当前出口 IP 记录至 `/root/ip_history.txt`。

---

## 📖 常用管理命令

### 1. 查看历史 IP 记录
```bash
cat /root/ip_history.txt
# 或者持续追踪新记录
tail -f /root/ip_history.txt
```

**日志记录示例：**
```text
[2026-10-23 00:00:15] 198.51.100.23
[2026-10-24 00:00:42] 198.51.100.23
[2026-10-25 00:00:08] 203.0.113.88
```

### 2. 手动立即测试/记录一次
任何时候都可以直接执行全局命令：
```bash
ipmonitor
```

### 3. 查看定时器运行状态与下次触发时间
对于 Systemd 系统：
```bash
# 查看定时器状态
systemctl status ipmonitor.timer

# 查看距离下一次执行的倒计时
systemctl list-timers | grep ipmonitor

# 查看最近的执行日志输出
journalctl -u ipmonitor.service -n 20 --no-pager
```

对于使用 Cron 的系统：
```bash
cat /etc/cron.d/ipmonitor
# 或
crontab -l
```

---

## ⚙️ 进阶配置

### 修改日志路径
默认日志保存在 `/root/ip_history.txt`。如需自定义，可修改 `/etc/systemd/system/ipmonitor.service` 中的 `Environment`：
```ini
[Service]
Environment="LOG_FILE=/var/log/my_ip.log"
ExecStart=/usr/local/bin/ipmonitor.sh
```
修改后执行 `systemctl daemon-reload` 即可。

### 修改每日执行时间 / 执行频率
默认在每日 `00:00:00` 运行。如需更改为每 6 小时记录一次，编辑 `/etc/systemd/system/ipmonitor.timer`：
```ini
[Timer]
# 改为每 6 小时执行一次
OnCalendar=*-*-* 00/6:00:00
```
保存后执行 `systemctl daemon-reload && systemctl restart ipmonitor.timer`。

---

## 🗑️ 一键卸载

如果不再需要该监控工具，可以执行一键卸载脚本清理所有组件：

```bash
curl -fsSL https://raw.githubusercontent.com/qualvey/ip-monitor/main/uninstall.sh | sudo bash
```

> **注意**：卸载脚本默认会**保留**你的 `/root/ip_history.txt` 历史记录文件。
> 若要连同历史记录彻底删除，请传入 `--purge` 参数：
> ```bash
> curl -fsSL https://raw.githubusercontent.com/qualvey/ip-monitor/main/uninstall.sh | sudo bash -s -- --purge
> ```

---

## 📄 开源许可证

本项目基于 [MIT](LICENSE) 协议开源。
