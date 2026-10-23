#!/usr/bin/env bash

# ==============================================================================
# IP Monitor - 一键卸载脚本
# ==============================================================================

set -e

BIN_PATH="/usr/local/bin/ipmonitor.sh"
ALIAS_PATH="/usr/local/bin/ipmonitor"
SYSTEMD_SERVICE="/etc/systemd/system/ipmonitor.service"
SYSTEMD_TIMER="/etc/systemd/system/ipmonitor.timer"
CRON_FILE="/etc/cron.d/ipmonitor"
GLOBAL_CONF="/etc/ipmonitor.conf"

# 颜色输出定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info()   { echo -e "${BLUE}[INFO]${NC} $*"; }
success(){ echo -e "${GREEN}[SUCCESS]${NC} $*"; }
warn()   { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()  { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# 1. 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
    error "必须使用 root 权限运行此脚本。请尝试：sudo bash $0"
    exit 1
fi

# 2. 识别目标用户与日志文件路径
if [ -f "$GLOBAL_CONF" ]; then
    # shellcheck source=/dev/null
    source "$GLOBAL_CONF"
fi

if [ -z "$LOG_FILE" ]; then
    if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
        TARGET_USER="$SUDO_USER"
        TARGET_HOME="$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6)"
        [ -z "$TARGET_HOME" ] && TARGET_HOME="$(eval echo "~$SUDO_USER")"
    else
        TARGET_USER="$(id -un)"
        TARGET_HOME="${HOME:-/root}"
    fi
    LOG_FILE="${TARGET_HOME}/ip_history.txt"
fi

info "开始卸载 IP Monitor..."

# 3. 清理 Systemd 服务与定时器
if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active --quiet ipmonitor.timer 2>/dev/null || systemctl is-enabled --quiet ipmonitor.timer 2>/dev/null; then
        info "正在停止并禁用 systemd timer..."
        systemctl disable --now ipmonitor.timer >/dev/null 2>&1 || true
    fi
    if [ -f "$SYSTEMD_TIMER" ] || [ -f "$SYSTEMD_SERVICE" ]; then
        rm -f "$SYSTEMD_TIMER" "$SYSTEMD_SERVICE"
        systemctl daemon-reload >/dev/null 2>&1 || true
        info "已移除 systemd 配置文件"
    fi
fi

# 4. 清理 Cron 任务
if [ -f "$CRON_FILE" ]; then
    rm -f "$CRON_FILE"
    info "已移除 $CRON_FILE"
fi

if crontab -l 2>/dev/null | grep -q "ipmonitor.sh"; then
    (crontab -l 2>/dev/null | grep -v "/usr/local/bin/ipmonitor.sh" || true) | crontab -
    info "已从当前用户的 crontab 中移除相关任务"
fi

if [ -n "${TARGET_USER}" ] && id "${TARGET_USER}" >/dev/null 2>&1; then
    if crontab -u "${TARGET_USER}" -l 2>/dev/null | grep -q "ipmonitor.sh"; then
        (crontab -u "${TARGET_USER}" -l 2>/dev/null | grep -v "/usr/local/bin/ipmonitor.sh" || true) | crontab -u "${TARGET_USER}" -
        info "已从 ${TARGET_USER} 用户的 crontab 中移除相关任务"
    fi
fi

# 5. 删除二进制文件、快捷别名及全局配置文件
rm -f "$BIN_PATH" "$ALIAS_PATH" "$GLOBAL_CONF"
info "已删除可执行文件及全局配置文件"

# 6. 处理日志文件（支持 --purge 参数彻底删除，默认保留）
PURGE=false
for arg in "$@"; do
    if [ "$arg" == "--purge" ] || [ "$arg" == "-p" ]; then
        PURGE=true
    fi
done

if [ "$PURGE" = true ]; then
    if [ -f "$LOG_FILE" ]; then
        rm -f "$LOG_FILE"
        warn "已删除历史日志文件: $LOG_FILE"
    fi
else
    if [ -f "$LOG_FILE" ]; then
        echo -e "${YELLOW}[提示]${NC} 历史 IP 日志文件仍保留在: ${BLUE}${LOG_FILE}${NC}"
        echo -e "       若要彻底清除，请执行: ${YELLOW}rm -f ${LOG_FILE}${NC} (或在卸载时添加 --purge 参数)"
    fi
fi

echo ""
success "IP Monitor 卸载完成！"
