#!/usr/bin/env bash

# ==============================================================================
# IP Monitor - VPS 出口 IPv4 记录脚本
# ==============================================================================

VERSION="1.1.0"
REPO_OWNER="${REPO_OWNER:-qualvey}"
REPO_NAME="${REPO_NAME:-ip-monitor}"
BRANCH="${BRANCH:-main}"

# 优先读取全局或用户配置文件（如果存在）
if [ -f "/etc/ipmonitor.conf" ]; then
    # shellcheck source=/dev/null
    source "/etc/ipmonitor.conf"
elif [ -n "$HOME" ] && [ -f "${HOME}/.config/ipmonitor/config" ]; then
    # shellcheck source=/dev/null
    source "${HOME}/.config/ipmonitor/config"
fi

# 配置日志输出路径（支持环境变量覆盖，默认当前用户家目录下的 ip_history.txt）
LOG_FILE="${LOG_FILE:-${HOME:-/root}/ip_history.txt}"
AUTO_UPDATE="${AUTO_UPDATE:-true}"

# 确保日志所在目录存在
LOG_DIR="$(dirname "$LOG_FILE")"
[ -d "$LOG_DIR" ] || mkdir -p "$LOG_DIR" 2>/dev/null || true

# 获取当前时间（格式：YYYY-MM-DD HH:MM:SS）
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# 自更新函数（支持静默检测与强制手动更新）
auto_update() {
    local force="${1:-false}"
    if [ "$force" != "true" ] && [ "$AUTO_UPDATE" != "true" ]; then
        return 0
    fi

    local current_script
    current_script="$(realpath "${BASH_SOURCE[0]}" 2>/dev/null || readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
    if [ ! -w "$current_script" ]; then
        if [ "$force" = "true" ]; then
            echo "错误: 对脚本 $current_script 没有写入权限，请尝试使用 sudo 运行更新。" >&2
            return 1
        fi
        return 0
    fi

    local remote_url="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}/ipmonitor.sh"
    local tmp_file
    tmp_file="$(mktemp 2>/dev/null || mktemp -t 'ipmonitor' 2>/dev/null || echo "/tmp/ipmonitor.tmp.$$")"

    # 请求远端最新脚本（设置短超时，更新失败绝不阻断常规记录流程）
    if curl -s -4 --connect-timeout 4 --max-time 8 "$remote_url" -o "$tmp_file" 2>/dev/null; then
        if [ -s "$tmp_file" ] && bash -n "$tmp_file" 2>/dev/null; then
            local current_hash remote_hash
            if command -v md5sum >/dev/null 2>&1; then
                current_hash=$(md5sum "$current_script" 2>/dev/null | awk '{print $1}')
                remote_hash=$(md5sum "$tmp_file" 2>/dev/null | awk '{print $1}')
            elif command -v sha256sum >/dev/null 2>&1; then
                current_hash=$(sha256sum "$current_script" 2>/dev/null | awk '{print $1}')
                remote_hash=$(sha256sum "$tmp_file" 2>/dev/null | awk '{print $1}')
            fi

            if [ -n "$current_hash" ] && [ -n "$remote_hash" ] && [ "$current_hash" != "$remote_hash" ]; then
                chmod +x "$tmp_file"
                mv -f "$tmp_file" "$current_script"
                if [ -t 1 ] || [ "$force" = "true" ]; then
                    echo "[$TIMESTAMP] 成功从仓库自动更新至最新版本！"
                fi
                if [ "$force" = "true" ]; then
                    exit 0
                fi
                # 防止循环重入，通过标记单次 exec
                if [ -z "$IPMONITOR_UPDATED" ]; then
                    export IPMONITOR_UPDATED=1
                    exec "$current_script" "$@"
                fi
            else
                if [ "$force" = "true" ]; then
                    echo "当前已是最新版本 (v${VERSION})，无需更新。"
                    rm -f "$tmp_file"
                    exit 0
                fi
            fi
        fi
    else
        if [ "$force" = "true" ]; then
            echo "错误: 无法连接至 GitHub 仓库更新脚本，请检查网络。" >&2
            rm -f "$tmp_file"
            exit 1
        fi
    fi
    rm -f "$tmp_file"
}

# 命令行参数解析
case "$1" in
    -u|--update)
        auto_update true
        exit 0
        ;;
    -v|--version)
        echo "ipmonitor v${VERSION}"
        exit 0
        ;;
    -h|--help)
        echo "IP Monitor v${VERSION} - VPS 出口 IPv4 每日监控记录工具"
        echo ""
        echo "用法: ipmonitor [选项]"
        echo ""
        echo "选项:"
        echo "  -u, --update   检查并立即从 GitHub 仓库更新至最新版本"
        echo "  -v, --version  显示当前版本号"
        echo "  -h, --help     显示此帮助信息"
        echo ""
        echo "日志路径: $LOG_FILE"
        exit 0
        ;;
esac

# 每日定时运行时，先尝试静默自更新
auto_update false

# 验证 IPv4 地址合法性
is_ipv4() {
    local ip="$1"
    local rx='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
    if [[ $ip =~ $rx ]]; then
        local IFS='.'
        local -a octets=($ip)
        for octet in "${octets[@]}"; do
            if (( octet < 0 || octet > 255 )); then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

# 依次尝试可信的公网 IP 查询接口（首选 ip.sb，备选 ipify / icanhazip / ifconfig.me）
ENDPOINTS=(
    "https://ip.sb"
    "https://api.ipify.org"
    "https://icanhazip.com"
    "https://ifconfig.me/ip"
)

IP=""
for url in "${ENDPOINTS[@]}"; do
    res=$(curl -s -4 --connect-timeout 5 --max-time 10 "$url" 2>/dev/null | tr -d '\r\n[:space:]')
    if is_ipv4 "$res"; then
        IP="$res"
        break
    fi
done

# 记录日志
if [ -n "$IP" ]; then
    echo "[$TIMESTAMP] $IP" >> "$LOG_FILE"
    if [ -t 1 ]; then
        echo "[$TIMESTAMP] 成功记录公网 IP: $IP -> $LOG_FILE"
    fi
else
    echo "[$TIMESTAMP] 获取 IP 失败" >> "$LOG_FILE"
    if [ -t 1 ]; then
        echo "[$TIMESTAMP] 获取 IP 失败，已记录到 $LOG_FILE" >&2
    fi
    exit 1
fi
