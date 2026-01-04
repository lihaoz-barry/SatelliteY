#!/bin/bash
# ==============================================================================
# deploy.sh - SatelliteY 服务部署脚本
# ==============================================================================
# 
# 功能:
#   1. 系统兼容性检查
#   2. 自动备份当前配置
#   3. 拉取最新代码
#   4. 显示配置对比 (before/after)
#   5. 复制文件到部署目录
#   6. 重启 systemd 服务
#   7. 验证部署状态
#
# 用法:
#   sudo ./deploy.sh              # 完整部署
#   sudo ./deploy.sh --dry-run    # 只显示对比,不实际部署
#   sudo ./deploy.sh --skip-pull  # 跳过 git pull
#   sudo ./deploy.sh --no-backup  # 跳过备份
#
# 兼容系统:
#   - DietPi (推荐)
#   - Raspberry Pi OS / Raspbian
#   - Ubuntu / Debian
#   - 任何使用 systemd 的 Linux
#
# ==============================================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 配置
REPO_DIR="${HOME}/SatelliteY"
SOURCE_DIR="${REPO_DIR}/linux-scheduler"
DEPLOY_DIR="/opt/satellite-y"
BACKUP_DIR="/opt/satellite-y/backups"
SYSTEMD_DIR="/etc/systemd/system"
SERVICE_NAME="daily-checkin"

# 参数解析
DRY_RUN=false
SKIP_PULL=false
NO_BACKUP=false
for arg in "$@"; do
    case $arg in
        --dry-run)
            DRY_RUN=true
            ;;
        --skip-pull)
            SKIP_PULL=true
            ;;
        --no-backup)
            NO_BACKUP=true
            ;;
    esac
done

# ==============================================================================
# 工具函数
# ==============================================================================

log_header() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC} ${BLUE}$1${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

log_diff() {
    echo -e "${YELLOW}[DIFF]${NC} $1"
}

# 获取文件内容摘要
get_file_summary() {
    local file="$1"
    if [[ -f "$file" ]]; then
        echo "$(md5sum "$file" 2>/dev/null | cut -d' ' -f1) ($(wc -l < "$file") lines)"
    else
        echo "(不存在)"
    fi
}

# 提取 config.sh 中的 TASKS 数组
get_tasks_list() {
    local file="$1"
    if [[ -f "$file" ]]; then
        grep -A 20 "^TASKS=(" "$file" 2>/dev/null | grep '"/execute' | sed 's/.*|/  → /' | sed 's/".*//'
    fi
}

# ==============================================================================
# Step 0: 系统兼容性检查
# ==============================================================================

log_header "Step 0: 系统兼容性检查"

COMPAT_ERRORS=0

# 检查操作系统
echo ""
echo -e "${BLUE}📋 系统信息:${NC}"
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    echo "  操作系统: ${PRETTY_NAME:-$NAME}"
    echo "  版本 ID: ${VERSION_ID:-unknown}"
else
    echo "  操作系统: $(uname -s)"
fi
echo "  内核版本: $(uname -r)"
echo "  架构: $(uname -m)"

# 检查是否是 Linux
if [[ "$(uname -s)" != "Linux" ]]; then
    log_error "此脚本仅支持 Linux 系统"
    echo "  当前系统: $(uname -s)"
    echo "  如需在 macOS 测试,请使用 --dry-run 模式"
    if [[ "$DRY_RUN" == "false" ]]; then
        exit 1
    fi
    COMPAT_ERRORS=$((COMPAT_ERRORS + 1))
fi

# 检查 systemd
echo ""
echo -e "${BLUE}🔧 依赖检查:${NC}"
if command -v systemctl &> /dev/null; then
    log_success "systemctl 可用"
    
    # 检查 systemd 是否在运行
    if systemctl is-system-running &> /dev/null || [[ $? -eq 1 ]]; then
        log_success "systemd 正在运行"
    else
        log_warn "systemd 可能未运行 (在容器中?)"
    fi
else
    log_error "systemctl 不可用 - 此脚本需要 systemd"
    COMPAT_ERRORS=$((COMPAT_ERRORS + 1))
fi

# 检查必要命令
REQUIRED_CMDS=("git" "md5sum" "diff" "cp" "mkdir")
for cmd in "${REQUIRED_CMDS[@]}"; do
    if command -v "$cmd" &> /dev/null; then
        log_success "$cmd 可用"
    else
        log_error "$cmd 不可用"
        COMPAT_ERRORS=$((COMPAT_ERRORS + 1))
    fi
done

# 检查仓库目录
echo ""
echo -e "${BLUE}📁 目录检查:${NC}"
if [[ -d "$REPO_DIR" ]]; then
    log_success "仓库目录存在: $REPO_DIR"
else
    log_error "仓库目录不存在: $REPO_DIR"
    COMPAT_ERRORS=$((COMPAT_ERRORS + 1))
fi

if [[ -d "$SOURCE_DIR" ]]; then
    log_success "源文件目录存在: $SOURCE_DIR"
else
    log_error "源文件目录不存在: $SOURCE_DIR"
    COMPAT_ERRORS=$((COMPAT_ERRORS + 1))
fi

# 检查是否已有服务运行
echo ""
echo -e "${BLUE}🔄 服务状态:${NC}"
if [[ -f "${SYSTEMD_DIR}/${SERVICE_NAME}.timer" ]]; then
    TIMER_STATUS=$(systemctl is-active ${SERVICE_NAME}.timer 2>/dev/null || echo "inactive")
    if [[ "$TIMER_STATUS" == "active" ]]; then
        log_success "定时器正在运行 (将更新现有服务)"
    else
        log_info "定时器未运行 (状态: $TIMER_STATUS)"
    fi
else
    log_info "首次部署 (定时器尚未安装)"
fi

# 检查是否有任务正在执行
SERVICE_STATUS=$(systemctl is-active ${SERVICE_NAME}.service 2>/dev/null || echo "inactive")
if [[ "$SERVICE_STATUS" == "active" ]]; then
    log_warn "任务正在执行中!部署将在任务完成后生效"
fi

# 兼容性检查结果
echo ""
if [[ $COMPAT_ERRORS -gt 0 ]]; then
    log_error "兼容性检查失败: $COMPAT_ERRORS 个问题"
    if [[ "$DRY_RUN" == "false" ]]; then
        exit 1
    fi
else
    log_success "兼容性检查通过 ✓"
fi

# ==============================================================================
# 主流程
# ==============================================================================

log_header "SatelliteY 服务部署脚本"
echo -e "模式: $(if [[ "$DRY_RUN" == "true" ]]; then echo "${YELLOW}DRY-RUN (仅预览)${NC}"; else echo "${GREEN}正式部署${NC}"; fi)"
echo -e "时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# ------------------------------------------------------------------------------
# Step 1: 创建备份
# ------------------------------------------------------------------------------
log_header "Step 1: 备份当前配置"

BACKUP_TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
CURRENT_BACKUP_DIR="${BACKUP_DIR}/${BACKUP_TIMESTAMP}"

if [[ "$NO_BACKUP" == "true" ]]; then
    log_warn "跳过备份 (--no-backup)"
elif [[ "$DRY_RUN" == "true" ]]; then
    log_warn "DRY-RUN: 跳过备份"
elif [[ -d "$DEPLOY_DIR" ]] && [[ -f "${DEPLOY_DIR}/config.sh" ]]; then
    log_info "创建备份目录: $CURRENT_BACKUP_DIR"
    sudo mkdir -p "$CURRENT_BACKUP_DIR"
    
    # 备份脚本文件
    for file in "${DEPLOY_DIR}"/*.sh; do
        if [[ -f "$file" ]]; then
            sudo cp "$file" "$CURRENT_BACKUP_DIR/"
            log_success "  备份: $(basename "$file")"
        fi
    done
    
    # 备份 systemd 文件
    for file in "${SYSTEMD_DIR}/${SERVICE_NAME}".*; do
        if [[ -f "$file" ]]; then
            sudo cp "$file" "$CURRENT_BACKUP_DIR/"
            log_success "  备份: $(basename "$file")"
        fi
    done
    
    # 记录备份信息
    echo "Backup created: $BACKUP_TIMESTAMP" | sudo tee "${CURRENT_BACKUP_DIR}/backup_info.txt" > /dev/null
    echo "Git commit: $(cd "$REPO_DIR" && git rev-parse --short HEAD 2>/dev/null || echo 'unknown')" | sudo tee -a "${CURRENT_BACKUP_DIR}/backup_info.txt" > /dev/null
    
    log_success "备份完成: $CURRENT_BACKUP_DIR"
    
    # 保留最近 5 个备份,删除旧的
    BACKUP_COUNT=$(ls -1 "$BACKUP_DIR" 2>/dev/null | wc -l)
    if [[ $BACKUP_COUNT -gt 5 ]]; then
        log_info "清理旧备份 (保留最近 5 个)..."
        ls -1t "$BACKUP_DIR" | tail -n +6 | while read old_backup; do
            sudo rm -rf "${BACKUP_DIR}/${old_backup}"
            log_info "  删除: $old_backup"
        done
    fi
else
    log_info "首次部署,无需备份"
fi

# 显示可用备份
echo ""
echo -e "${BLUE}📦 可用备份:${NC}"
if [[ -d "$BACKUP_DIR" ]]; then
    ls -1t "$BACKUP_DIR" 2>/dev/null | head -5 | while read backup; do
        echo "  • $backup"
    done
    echo ""
    echo -e "${CYAN}回滚命令: sudo ./rollback.sh [备份名称]${NC}"
else
    echo "  (无备份)"
fi

# ------------------------------------------------------------------------------
# Step 2: Git Pull
# ------------------------------------------------------------------------------
log_header "Step 2: 拉取最新代码"

cd "$REPO_DIR"
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
CURRENT_COMMIT=$(git rev-parse --short HEAD)

log_info "当前分支: $CURRENT_BRANCH"
log_info "当前提交: $CURRENT_COMMIT"

if [[ "$SKIP_PULL" == "true" ]]; then
    log_warn "跳过 git pull (--skip-pull)"
else
    if [[ "$DRY_RUN" == "false" ]]; then
        git fetch origin
        git pull
        NEW_COMMIT=$(git rev-parse --short HEAD)
        if [[ "$CURRENT_COMMIT" != "$NEW_COMMIT" ]]; then
            log_success "代码已更新: $CURRENT_COMMIT → $NEW_COMMIT"
        else
            log_info "代码已是最新"
        fi
    else
        log_warn "DRY-RUN: 跳过 git pull"
    fi
fi

# ------------------------------------------------------------------------------
# Step 3: 显示配置对比
# ------------------------------------------------------------------------------
log_header "Step 3: 配置文件对比"

echo ""
echo -e "${YELLOW}┌─────────────────────────────────────────────────────────────────┐${NC}"
echo -e "${YELLOW}│ 文件对比: 源文件 vs 已部署文件                                   │${NC}"
echo -e "${YELLOW}└─────────────────────────────────────────────────────────────────┘${NC}"

FILES_TO_COMPARE=("config.sh" "daily_tasks.sh" "daily_checkin.sh" "interval_checkin.sh")
CHANGES_DETECTED=false

for file in "${FILES_TO_COMPARE[@]}"; do
    SOURCE_FILE="${SOURCE_DIR}/${file}"
    DEPLOYED_FILE="${DEPLOY_DIR}/${file}"
    
    echo ""
    echo -e "${BLUE}📄 ${file}${NC}"
    
    if [[ ! -f "$SOURCE_FILE" ]]; then
        log_warn "  源文件不存在"
        continue
    fi
    
    if [[ ! -f "$DEPLOYED_FILE" ]]; then
        log_info "  已部署: (新文件 - 首次部署)"
        CHANGES_DETECTED=true
    else
        SOURCE_HASH=$(md5sum "$SOURCE_FILE" | cut -d' ' -f1)
        DEPLOYED_HASH=$(md5sum "$DEPLOYED_FILE" | cut -d' ' -f1)
        
        if [[ "$SOURCE_HASH" == "$DEPLOYED_HASH" ]]; then
            log_success "  无变化 ✓"
        else
            CHANGES_DETECTED=true
            log_diff "  检测到变化!"
            echo -e "    源文件:   $(get_file_summary "$SOURCE_FILE")"
            echo -e "    已部署:   $(get_file_summary "$DEPLOYED_FILE")"
            
            # 显示具体差异
            echo -e "    ${YELLOW}差异内容:${NC}"
            diff --color=always -u "$DEPLOYED_FILE" "$SOURCE_FILE" 2>/dev/null | head -30 | sed 's/^/    /' || true
        fi
    fi
done

# 显示 TASKS 对比
echo ""
echo -e "${YELLOW}┌─────────────────────────────────────────────────────────────────┐${NC}"
echo -e "${YELLOW}│ 任务列表对比                                                     │${NC}"
echo -e "${YELLOW}└─────────────────────────────────────────────────────────────────┘${NC}"
echo ""
echo -e "${BLUE}已部署的任务:${NC}"
get_tasks_list "${DEPLOY_DIR}/config.sh" || echo "  (无)"
echo ""
echo -e "${GREEN}新版本的任务:${NC}"
get_tasks_list "${SOURCE_DIR}/config.sh" || echo "  (无)"

# Systemd 文件对比
echo ""
echo -e "${YELLOW}┌─────────────────────────────────────────────────────────────────┐${NC}"
echo -e "${YELLOW}│ Systemd 配置对比                                                 │${NC}"
echo -e "${YELLOW}└─────────────────────────────────────────────────────────────────┘${NC}"

SYSTEMD_FILES=("daily-checkin.service" "daily-checkin.timer")
for file in "${SYSTEMD_FILES[@]}"; do
    SOURCE_FILE="${SOURCE_DIR}/${file}"
    DEPLOYED_FILE="${SYSTEMD_DIR}/${file}"
    
    echo ""
    echo -e "${BLUE}⚙️  ${file}${NC}"
    
    if [[ -f "$SOURCE_FILE" ]] && [[ -f "$DEPLOYED_FILE" ]]; then
        if diff -q "$SOURCE_FILE" "$DEPLOYED_FILE" > /dev/null 2>&1; then
            log_success "  无变化 ✓"
        else
            CHANGES_DETECTED=true
            log_diff "  检测到变化!"
        fi
    elif [[ -f "$SOURCE_FILE" ]]; then
        log_info "  新文件 (首次部署)"
        CHANGES_DETECTED=true
    fi
done

# DRY-RUN 模式结束
if [[ "$DRY_RUN" == "true" ]]; then
    echo ""
    log_header "DRY-RUN 完成"
    if [[ "$CHANGES_DETECTED" == "true" ]]; then
        log_warn "检测到变化,运行 'sudo ./deploy.sh' 来应用更改"
    else
        log_success "没有检测到变化"
    fi
    exit 0
fi

# ------------------------------------------------------------------------------
# Step 4: 复制文件
# ------------------------------------------------------------------------------
log_header "Step 4: 复制文件到部署目录"

# 创建部署目录
sudo mkdir -p "$DEPLOY_DIR"

# 复制脚本文件
log_info "复制脚本文件..."
for file in "${SOURCE_DIR}"/*.sh; do
    if [[ -f "$file" ]]; then
        sudo cp "$file" "$DEPLOY_DIR/"
        sudo chmod +x "${DEPLOY_DIR}/$(basename "$file")"
        log_success "  $(basename "$file")"
    fi
done

# 复制 systemd 配置
log_info "复制 systemd 配置..."
for file in "${SOURCE_DIR}"/*.service "${SOURCE_DIR}"/*.timer; do
    if [[ -f "$file" ]]; then
        sudo cp "$file" "$SYSTEMD_DIR/"
        log_success "  $(basename "$file")"
    fi
done

# ------------------------------------------------------------------------------
# Step 5: 重启服务
# ------------------------------------------------------------------------------
log_header "Step 5: 重启 Systemd 服务"

log_info "停止现有定时器..."
sudo systemctl stop ${SERVICE_NAME}.timer 2>/dev/null || true
log_success "定时器已停止"

log_info "重载 systemd 配置..."
sudo systemctl daemon-reload
log_success "daemon-reload 完成"

log_info "启动定时器（全新状态，无补执行）..."
sudo systemctl start ${SERVICE_NAME}.timer
log_success "${SERVICE_NAME}.timer 已启动"

# ------------------------------------------------------------------------------
# Step 6: 验证部署
# ------------------------------------------------------------------------------
log_header "Step 6: 验证部署状态"

echo ""
echo -e "${BLUE}📊 定时器状态:${NC}"
systemctl status ${SERVICE_NAME}.timer --no-pager | head -10 || true

echo ""
echo -e "${BLUE}📅 下次执行时间:${NC}"
systemctl list-timers ${SERVICE_NAME}.timer --no-pager | head -5 || true

echo ""
echo -e "${BLUE}📋 已部署的任务列表:${NC}"
get_tasks_list "${DEPLOY_DIR}/config.sh"

echo ""
echo -e "${BLUE}📁 已部署的文件:${NC}"
ls -la "$DEPLOY_DIR"/*.sh 2>/dev/null | awk '{print "  " $9 " (" $5 " bytes)"}'

# 最终状态
echo ""
log_header "部署完成"

TIMER_STATUS=$(systemctl is-active ${SERVICE_NAME}.timer 2>/dev/null || echo "inactive")
if [[ "$TIMER_STATUS" == "active" ]]; then
    log_success "部署成功! 定时器正在运行"
    echo ""
    echo -e "${GREEN}✓ 所有更改已应用${NC}"
    echo -e "${GREEN}✓ 定时器状态: active${NC}"
    echo -e "${GREEN}✓ 下次执行时将使用新配置${NC}"
    echo -e "${GREEN}✓ 备份位置: ${CURRENT_BACKUP_DIR:-无}${NC}"
    echo ""
    echo -e "${CYAN}如需回滚: sudo ./linux-scheduler/rollback.sh${NC}"
else
    log_error "部署可能存在问题,定时器状态: $TIMER_STATUS"
    echo ""
    echo "请检查: sudo systemctl status ${SERVICE_NAME}.timer"
    echo ""
    echo -e "${YELLOW}如需回滚到上一版本:${NC}"
    echo "  sudo ./linux-scheduler/rollback.sh"
    exit 1
fi
