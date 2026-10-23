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

# 1. 检查 root 权限（配置全局命令和 systemd/cron 需要）
if [ "$(id -u)" -ne 0 ]; then
    error "必须使用 root 权限运行此脚本。请尝试：sudo bash $0"
    exit 1
fi

# 2. 确定当前执行安装的用户与用户家目录（避免默认写入 /root）
if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
    TARGET_USER="$SUDO_USER"
    TARGET_HOME="$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6)"
    [ -z "$TARGET_HOME" ] && TARGET_HOME="$(eval echo "~$SUDO_USER")"
else
    TARGET_USER="$(id -un)"
    TARGET_HOME="${HOME:-/root}"
fi

# 默认日志保存路径为当前安装用户的家目录下的 ip_history.txt
LOG_FILE="${LOG_FILE:-${TARGET_HOME}/ip_history.txt}"

info "开始安装 IP Monitor..."
info "当前安装用户: ${TARGET_USER} (家目录: ${TARGET_HOME})"
info "日志保存路径: ${LOG_FILE}"

# 3. 检查或安装基础依赖 (curl)
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

# 4. 判断是从本地目录安装还是通过网络下载
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

# 5. 安装核心主脚本
info "安装核心执行脚本到 ${BIN_PATH}..."
download_or_copy "ipmonitor.sh" "$BIN_PATH"
chmod +x "$BIN_PATH"
# 将脚本所有者赋予目标用户，以便普通用户身份每天定时运行时具备自更新写权限
chown "${TARGET_USER}:" "$BIN_PATH" 2>/dev/null || true
ln -sf "$BIN_PATH" "$ALIAS_PATH"

# 6. 生成全局配置文件，记录目标日志路径与自动更新设置
cat << EOF > "$GLOBAL_CONF"
# IP Monitor Global Configuration
LOG_FILE="${LOG_FILE}"
AUTO_UPDATE="true"
REPO_OWNER="${REPO_OWNER}"
REPO_NAME="${REPO_NAME}"
BRANCH="${BRANCH}"
EOF
chmod 644 "$GLOBAL_CONF"
chown "${TARGET_USER}:" "$GLOBAL_CONF" 2>/dev/null || true

# 7. 配置定时任务（优先使用 systemd timer，非 systemd 环境回退到 cron）
HAS_SYSTEMD=false
if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    HAS_SYSTEMD=true
fi

if [ "$HAS_SYSTEMD" = true ]; then
    info "检测到 Systemd，正在配置 Systemd Timer 定时任务..."

    TMP_SERVICE="$(mktemp)"
    download_or_copy "systemd/ipmonitor.service" "$TMP_SERVICE"
    sed -e "s|__TARGET_USER__|${TARGET_USER}|g" \
        -e "s|__LOG_FILE__|${LOG_FILE}|g" \
        -e "s|__BIN_PATH__|${BIN_PATH}|g" \
        "$TMP_SERVICE" > "${SYSTEMD_DIR}/ipmonitor.service"
    rm -f "$TMP_SERVICE"

    download_or_copy "systemd/ipmonitor.timer" "${SYSTEMD_DIR}/ipmonitor.timer"

    systemctl daemon-reload
    systemctl enable ipmonitor.timer >/dev/null 2>&1
    systemctl restart ipmonitor.timer

    success "Systemd 定时任务配置完成 (每日 00:00 自动以 ${TARGET_USER} 身份运行)"
else
    info "未检测到活跃的 Systemd，正在回退配置 Cron 定时任务..."

    if [ -d /etc/cron.d ]; then
        TMP_CRON="$(mktemp)"
        download_or_copy "cron/ipmonitor.cron" "$TMP_CRON"
        sed -e "s|__TARGET_USER__|${TARGET_USER}|g" \
            -e "s|__LOG_FILE__|${LOG_FILE}|g" \
            -e "s|__BIN_PATH__|${BIN_PATH}|g" \
            "$TMP_CRON" > /etc/cron.d/ipmonitor
        rm -f "$TMP_CRON"
        chmod 644 /etc/cron.d/ipmonitor
    else
        # 写入对应用户的 crontab
        (crontab -u "$TARGET_USER" -l 2>/dev/null | grep -v "${BIN_PATH}" || true; echo "0 0 * * * LOG_FILE=\"${LOG_FILE}\" ${BIN_PATH} >/dev/null 2>&1") | crontab -u "$TARGET_USER" -
    fi
    success "Cron 定时任务配置完成 (每日 00:00 自动以 ${TARGET_USER} 身份运行)"
fi

# 8. 以目标用户身份执行首次测试，并确保日志文件属主归属于该用户
info "正在执行首次测试与记录..."
if [ "$TARGET_USER" != "$(id -un)" ] && command -v sudo >/dev/null 2>&1; then
    sudo -u "$TARGET_USER" LOG_FILE="$LOG_FILE" "$BIN_PATH"
elif [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
    su - "$TARGET_USER" -c "LOG_FILE='$LOG_FILE' '$BIN_PATH'"
else
    LOG_FILE="$LOG_FILE" "$BIN_PATH"
fi

if [ -f "$LOG_FILE" ]; then
    chown "${TARGET_USER}:" "$LOG_FILE" 2>/dev/null || true
fi

# 9. 打印安装成功指引
echo ""
echo -e "${GREEN}=================================================================${NC}"
echo -e "${GREEN}             IP Monitor 一键部署成功！                           ${NC}"
echo -e "${GREEN}=================================================================${NC}"
echo -e "执行用户:  ${YELLOW}${TARGET_USER}${NC}"
echo -e "核心脚本:  ${BLUE}${BIN_PATH}${NC} (快捷命令: ${YELLOW}ipmonitor${NC})"
echo -e "日志路径:  ${BLUE}${LOG_FILE}${NC}"

if [ "$HAS_SYSTEMD" = true ]; then
    echo -e "定时服务:  ${YELLOW}systemctl status ipmonitor.timer${NC}"
    echo -e "下一次执行: $(systemctl list-timers --no-legend ipmonitor.timer 2>/dev/null | awk '{print $1,$2,$3}' || echo '每日 00:00')"
else
    echo -e "定时服务:  Cron (每日 00:00 以 ${TARGET_USER} 运行)"
fi

echo ""
echo -e "常用指令:"
echo -e "  查看历史日志:  ${YELLOW}cat ${LOG_FILE}${NC}  或  ${YELLOW}tail -f ${LOG_FILE}${NC}"
echo -e "  手动立即执行:  ${YELLOW}ipmonitor${NC}"
echo -e "  手动更新版本:  ${YELLOW}ipmonitor -u${NC}"
echo -e "  查看当前版本:  ${YELLOW}ipmonitor -v${NC}"
if [ "$HAS_SYSTEMD" = true ]; then
echo -e "  查看执行日志:  ${YELLOW}journalctl -u ipmonitor.service -n 20${NC}"
fi
echo -e "  一键卸载脚本:  ${YELLOW}curl -fsSL ${RAW_BASE}/uninstall.sh | bash${NC}"
echo -e "${GREEN}=================================================================${NC}"
