#!/bin/bash
# ==============================================================================
# rollback.sh - SatelliteY 服务回滚脚本
# ==============================================================================
# 
# 功能:
#   1. 列出可用备份
#   2. 回滚到指定备份或最近的备份
#   3. 重启 systemd 服务
#   4. 验证回滚状态
#
# 用法:
#   sudo ./rollback.sh              # 回滚到最近的备份
#   sudo ./rollback.sh 20240103_021500  # 回滚到指定备份
#   ./rollback.sh --list            # 列出所有备份
#   ./rollback.sh --dry-run         # 只预览不实际回滚
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
DEPLOY_DIR="/opt/satellite-y"
BACKUP_DIR="/opt/satellite-y/backups"
SYSTEMD_DIR="/etc/systemd/system"
SERVICE_NAME="daily-checkin"

# 参数解析
TARGET_BACKUP=""
LIST_ONLY=false
DRY_RUN=false

for arg in "$@"; do
    case $arg in
        --list)
            LIST_ONLY=true
            ;;
        --dry-run)
            DRY_RUN=true
            ;;
        *)
            if [[ ! "$arg" =~ ^-- ]]; then
                TARGET_BACKUP="$arg"
            fi
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

# 提取 config.sh 中的 TASKS 数组
get_tasks_list() {
    local file="$1"
    if [[ -f "$file" ]]; then
        grep -A 20 "^TASKS=(" "$file" 2>/dev/null | grep '"/execute' | sed 's/.*|/  → /' | sed 's/".*//'
    fi
}

# ==============================================================================
# 主流程
# ==============================================================================

log_header "SatelliteY 服务回滚脚本"
echo -e "时间: $(date '+%Y-%m-%d %H:%M:%S')"

# 检查备份目录
if [[ ! -d "$BACKUP_DIR" ]]; then
    log_error "备份目录不存在: $BACKUP_DIR"
    echo ""
    echo "请先使用 deploy.sh 进行部署,它会自动创建备份"
    exit 1
fi

# 获取可用备份列表
BACKUPS=($(ls -1t "$BACKUP_DIR" 2>/dev/null))

if [[ ${#BACKUPS[@]} -eq 0 ]]; then
    log_error "没有可用的备份"
    exit 1
fi

# ------------------------------------------------------------------------------
# 列出备份模式
# ------------------------------------------------------------------------------
if [[ "$LIST_ONLY" == "true" ]]; then
    log_header "可用备份列表"
    echo ""
    
    for i in "${!BACKUPS[@]}"; do
        backup="${BACKUPS[$i]}"
        backup_path="${BACKUP_DIR}/${backup}"
        
        # 读取备份信息
        if [[ -f "${backup_path}/backup_info.txt" ]]; then
            commit_info=$(grep "Git commit" "${backup_path}/backup_info.txt" 2>/dev/null | cut -d: -f2 | tr -d ' ')
        else
            commit_info="unknown"
        fi
        
        # 计算文件数
        file_count=$(ls -1 "${backup_path}"/*.sh 2>/dev/null | wc -l)
        
        if [[ $i -eq 0 ]]; then
            echo -e "${GREEN}→ $backup${NC} (最新) - commit: $commit_info, $file_count 个脚本"
        else
            echo -e "  $backup - commit: $commit_info, $file_count 个脚本"
        fi
    done
    
    echo ""
    echo -e "${CYAN}回滚到指定备份: sudo ./rollback.sh [备份名称]${NC}"
    echo -e "${CYAN}回滚到最近备份: sudo ./rollback.sh${NC}"
    exit 0
fi

# ------------------------------------------------------------------------------
# 确定目标备份
# ------------------------------------------------------------------------------
log_header "Step 1: 选择备份"

if [[ -n "$TARGET_BACKUP" ]]; then
    # 验证指定的备份存在
    if [[ ! -d "${BACKUP_DIR}/${TARGET_BACKUP}" ]]; then
        log_error "指定的备份不存在: $TARGET_BACKUP"
        echo ""
        echo "可用备份:"
        printf '  %s\n' "${BACKUPS[@]}"
        exit 1
    fi
    SELECTED_BACKUP="$TARGET_BACKUP"
    log_info "使用指定备份: $SELECTED_BACKUP"
else
    # 使用最近的备份
    SELECTED_BACKUP="${BACKUPS[0]}"
    log_info "使用最近备份: $SELECTED_BACKUP"
fi

SELECTED_BACKUP_PATH="${BACKUP_DIR}/${SELECTED_BACKUP}"

# 显示备份信息
echo ""
echo -e "${BLUE}📦 备份信息:${NC}"
echo "  路径: $SELECTED_BACKUP_PATH"
if [[ -f "${SELECTED_BACKUP_PATH}/backup_info.txt" ]]; then
    cat "${SELECTED_BACKUP_PATH}/backup_info.txt" | sed 's/^/  /'
fi

echo ""
echo -e "${BLUE}📋 备份中的任务列表:${NC}"
get_tasks_list "${SELECTED_BACKUP_PATH}/config.sh" || echo "  (无)"

echo ""
echo -e "${BLUE}📁 备份中的文件:${NC}"
ls -la "${SELECTED_BACKUP_PATH}"/*.sh 2>/dev/null | awk '{print "  " $9 " (" $5 " bytes)"}' || echo "  (无脚本文件)"

# ------------------------------------------------------------------------------
# 对比当前配置
# ------------------------------------------------------------------------------
log_header "Step 2: 配置对比"

echo ""
echo -e "${YELLOW}当前部署 vs 备份:${NC}"
echo ""
echo -e "${RED}当前任务:${NC}"
get_tasks_list "${DEPLOY_DIR}/config.sh" || echo "  (无)"
echo ""
echo -e "${GREEN}回滚后任务:${NC}"
get_tasks_list "${SELECTED_BACKUP_PATH}/config.sh" || echo "  (无)"

# DRY-RUN 模式
if [[ "$DRY_RUN" == "true" ]]; then
    echo ""
    log_header "DRY-RUN 完成"
    log_warn "这是预览模式,运行 'sudo ./rollback.sh $SELECTED_BACKUP' 来实际回滚"
    exit 0
fi

# ------------------------------------------------------------------------------
# 确认回滚
# ------------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}⚠️  警告: 这将覆盖当前部署的配置!${NC}"
echo ""
read -p "确认回滚到备份 '$SELECTED_BACKUP'? (y/N): " confirm

if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    log_info "已取消回滚"
    exit 0
fi

# ------------------------------------------------------------------------------
# Step 3: 执行回滚
# ------------------------------------------------------------------------------
log_header "Step 3: 执行回滚"

# 复制脚本文件
log_info "恢复脚本文件..."
for file in "${SELECTED_BACKUP_PATH}"/*.sh; do
    if [[ -f "$file" ]]; then
        sudo cp "$file" "$DEPLOY_DIR/"
        sudo chmod +x "${DEPLOY_DIR}/$(basename "$file")"
        log_success "  恢复: $(basename "$file")"
    fi
done

# 复制 systemd 文件 (如果备份中有)
for file in "${SELECTED_BACKUP_PATH}"/*.service "${SELECTED_BACKUP_PATH}"/*.timer; do
    if [[ -f "$file" ]]; then
        sudo cp "$file" "$SYSTEMD_DIR/"
        log_success "  恢复: $(basename "$file")"
    fi
done

# ------------------------------------------------------------------------------
# Step 4: 重启服务
# ------------------------------------------------------------------------------
log_header "Step 4: 重启服务"

log_info "重载 systemd 配置..."
sudo systemctl daemon-reload
log_success "daemon-reload 完成"

log_info "重启定时器..."
sudo systemctl restart ${SERVICE_NAME}.timer
log_success "${SERVICE_NAME}.timer 已重启"

# ------------------------------------------------------------------------------
# Step 5: 验证回滚
# ------------------------------------------------------------------------------
log_header "Step 5: 验证回滚状态"

echo ""
echo -e "${BLUE}📊 定时器状态:${NC}"
systemctl status ${SERVICE_NAME}.timer --no-pager | head -10 || true

echo ""
echo -e "${BLUE}📅 下次执行时间:${NC}"
systemctl list-timers ${SERVICE_NAME}.timer --no-pager | head -5 || true

echo ""
echo -e "${BLUE}📋 当前任务列表:${NC}"
get_tasks_list "${DEPLOY_DIR}/config.sh"

# 最终状态
echo ""
log_header "回滚完成"

TIMER_STATUS=$(systemctl is-active ${SERVICE_NAME}.timer 2>/dev/null || echo "inactive")
if [[ "$TIMER_STATUS" == "active" ]]; then
    log_success "回滚成功! 定时器正在运行"
    echo ""
    echo -e "${GREEN}✓ 已回滚到备份: $SELECTED_BACKUP${NC}"
    echo -e "${GREEN}✓ 定时器状态: active${NC}"
    echo -e "${GREEN}✓ 下次执行时将使用回滚后的配置${NC}"
else
    log_error "回滚后定时器状态异常: $TIMER_STATUS"
    echo ""
    echo "请检查: sudo systemctl status ${SERVICE_NAME}.timer"
    exit 1
fi
