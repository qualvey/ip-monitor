#!/usr/bin/env bash

# ==============================================================================
# IP Monitor - 一键安装脚本
# 支持 Ubuntu, Debian, CentOS, AlmaLinux, RockyLinux, Fedora, Alpine, Arch 等
# ==============================================================================

set -e

# 默认 GitHub 仓库信息（可通过环境变量覆盖）
REPO_OWNER="${REPO_OWNER:-qualvey}"
REPO_NAME="${REPO_NAME:-ip-monitor}"
BRANCH="${BRANCH:-main}"
RAW_BASE="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}"

BIN_PATH="/usr/local/bin/ipmonitor.sh"
ALIAS_PATH="/usr/local/bin/ipmonitor"
SYSTEMD_DIR="/etc/systemd/system"
LOG_FILE="/root/ip_history.txt"

# 颜色输出定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
success(){ echo -e "${GREEN}[SUCCESS]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# 1. 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
    error "必须使用 root 权限运行此脚本。请尝试：sudo bash $0"
    exit 1
fi

info "开始安装 IP Monitor..."

# 2. 检查或安装基础依赖 (curl)
install_dependencies() {
    if command -v curl >/dev/null 2>&1; then
        return 0
    fi

    info "未检测到 curl，正在自动安装依赖..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -y && apt-get install -y curl
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y curl
    elif command -v yum >/dev/null 2>&1; then
        yum install -y curl
    elif command -v apk >/dev/null 2>&1; then
        apk add --no-cache curl bash
    elif command -v pacman >/dev/null 2>&1; then
        pacman -Sy --noconfirm curl
    else
        error "无法自动安装 curl，请手动安装 curl 后重试。"
        exit 1
    fi
}
install_dependencies

# 3. 判断是从本地目录安装还是通过网络下载
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"

download_or_copy() {
    local rel_path="$1"
    local dest_path="$2"

    if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/$rel_path" ]; then
        cp -f "$SCRIPT_DIR/$rel_path" "$dest_path"
    else
        curl -fsSL "${RAW_BASE}/${rel_path}" -o "$dest_path"
    fi
}

# 4. 安装核心主脚本
info "安装核心执行脚本到 ${BIN_PATH}..."
download_or_copy "ipmonitor.sh" "$BIN_PATH"
chmod +x "$BIN_PATH"
ln -sf "$BIN_PATH" "$ALIAS_PATH"

# 5. 配置定时任务（优先使用 systemd timer，非 systemd 环境回退到 cron）
HAS_SYSTEMD=false
if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    HAS_SYSTEMD=true
fi

if [ "$HAS_SYSTEMD" = true ]; then
    info "检测到 Systemd，正在配置 Systemd Timer 定时任务..."

    download_or_copy "systemd/ipmonitor.service" "${SYSTEMD_DIR}/ipmonitor.service"
    download_or_copy "systemd/ipmonitor.timer" "${SYSTEMD_DIR}/ipmonitor.timer"

    systemctl daemon-reload
    systemctl enable ipmonitor.timer >/dev/null 2>&1
    systemctl restart ipmonitor.timer

    success "Systemd 定时任务配置完成 (每日 00:00 自动触发)"
else
    info "未检测到活跃的 Systemd，正在回退配置 Cron 定时任务..."

    if [ -d /etc/cron.d ]; then
        cat << 'EOF' > /etc/cron.d/ipmonitor
# Daily Public IP Monitor (run once every day at 00:00)
0 0 * * * root /usr/local/bin/ipmonitor.sh >/dev/null 2>&1
EOF
        chmod 644 /etc/cron.d/ipmonitor
    else
        # 写入 root 用户 crontab
        (crontab -l 2>/dev/null | grep -v "/usr/local/bin/ipmonitor.sh" || true; echo "0 0 * * * /usr/local/bin/ipmonitor.sh >/dev/null 2>&1") | crontab -
    fi
    success "Cron 定时任务配置完成 (每日 00:00 自动触发)"
fi

# 6. 立即触发执行一次以测试并记录当前 IP
info "正在执行首次测试与记录..."
"$BIN_PATH"

# 7. 打印安装成功指引
echo ""
echo -e "${GREEN}=================================================================${NC}"
echo -e "${GREEN}             IP Monitor 一键部署成功！                           ${NC}"
echo -e "${GREEN}=================================================================${NC}"
echo -e "核心脚本:  ${BLUE}${BIN_PATH}${NC} (已创建别名快捷命令: ${YELLOW}ipmonitor${NC})"
echo -e "日志路径:  ${BLUE}${LOG_FILE}${NC}"

if [ "$HAS_SYSTEMD" = true ]; then
    echo -e "定时服务:  ${YELLOW}systemctl status ipmonitor.timer${NC}"
    echo -e "下一次执行: $(systemctl list-timers --no-legend ipmonitor.timer 2>/dev/null | awk '{print $1,$2,$3}' || echo '每日 00:00')"
else
    echo -e "定时服务:  Cron (每日 00:00 运行)"
fi

echo ""
echo -e "常用指令:"
echo -e "  查看历史日志:  ${YELLOW}cat ${LOG_FILE}${NC}  或  ${YELLOW}tail -f ${LOG_FILE}${NC}"
echo -e "  手动立即执行:  ${YELLOW}ipmonitor${NC}"
if [ "$HAS_SYSTEMD" = true ]; then
echo -e "  查看执行日志:  ${YELLOW}journalctl -u ipmonitor.service -n 20${NC}"
fi
echo -e "  一键卸载脚本:  ${YELLOW}curl -fsSL ${RAW_BASE}/uninstall.sh | bash${NC}"
echo -e "${GREEN}=================================================================${NC}"
