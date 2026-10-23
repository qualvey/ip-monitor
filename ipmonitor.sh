#!/usr/bin/env bash

# ==============================================================================
# IP Monitor - VPS 出口 IPv4 记录脚本
# ==============================================================================

# 配置日志输出路径（支持环境变量覆盖，默认 /root/ip_history.txt）
LOG_FILE="${LOG_FILE:-/root/ip_history.txt}"

# 确保日志所在目录存在
LOG_DIR="$(dirname "$LOG_FILE")"
[ -d "$LOG_DIR" ] || mkdir -p "$LOG_DIR" 2>/dev/null || true

# 获取当前时间（格式：YYYY-MM-DD HH:MM:SS）
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

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
