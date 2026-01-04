#!/bin/bash
# ==============================================================================
# daily_tasks.sh - 每日定时任务主脚本
# ==============================================================================
#
# 功能：
#   1. 发送 WoL 唤醒 Windows PC
#   2. 等待系统启动和服务就绪
#   3. 按配置顺序执行多个 API 任务
#   4. 每个任务之间有间隔
#
# 使用方法：
#   ./daily_tasks.sh              # 正常执行（唤醒 + 所有任务）
#   ./daily_tasks.sh --skip-wake  # 跳过唤醒（PC 已开机）
#   ./daily_tasks.sh --dry-run    # 模拟运行，不实际执行
#
# 配置：
#   编辑 config.sh 添加/修改任务
#
# ==============================================================================

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载配置
if [ -f "${SCRIPT_DIR}/config.sh" ]; then
    source "${SCRIPT_DIR}/config.sh"
else
    echo "❌ 错误: config.sh 未找到"
    exit 1
fi

# 构建 API URL
COMET_BASE_URL="http://${WINDOWS_IP}:${COMET_PORT}"

# 运行模式
SKIP_WAKE=false
DRY_RUN=false

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-wake|-s)
            SKIP_WAKE=true
            shift
            ;;
        --dry-run|-d)
            DRY_RUN=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --skip-wake, -s  跳过 WoL 唤醒"
            echo "  --dry-run, -d    模拟运行"
            echo "  --help, -h       显示帮助"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# 确保日志目录存在
mkdir -p "$LOG_DIR"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo -e "${BLUE}${msg}${NC}"
    echo "$msg" >> "$LOG_FILE"
}

log_success() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $1"
    echo -e "${GREEN}${msg}${NC}"
    echo "$msg" >> "$LOG_FILE"
}

log_error() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] ❌ $1"
    echo -e "${RED}${msg}${NC}"
    echo "$msg" >> "$LOG_FILE"
}

log_warning() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  $1"
    echo -e "${YELLOW}${msg}${NC}"
    echo "$msg" >> "$LOG_FILE"
}

log_task() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] 🔹 $1"
    echo -e "${CYAN}${msg}${NC}"
    echo "$msg" >> "$LOG_FILE"
}

# 实时倒计时
countdown() {
    local seconds=$1
    local message="${2:-等待中}"
    
    while [ $seconds -gt 0 ]; do
        local mins=$((seconds / 60))
        local secs=$((seconds % 60))
        printf "\r${BLUE}[%s]${NC} ⏱️  ${message}: %02d:%02d " "$(date '+%H:%M:%S')" $mins $secs
        sleep 1
        seconds=$((seconds - 1))
    done
    printf "\r${BLUE}[%s]${NC} ⏱️  ${message}: 完成!          \n" "$(date '+%H:%M:%S')"
}

# 检查服务状态
check_service() {
    curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "${COMET_BASE_URL}/health" 2>/dev/null
}

# 发送 WoL 唤醒
wake_windows() {
    log "发送 Wake-on-LAN..."
    
    # 加载用户 alias
    if [ -f "$HOME/.bashrc" ]; then
        shopt -s expand_aliases 2>/dev/null
        source "$HOME/.bashrc" 2>/dev/null
    fi
    
    if [ "$DRY_RUN" = true ]; then
        log "[DRY-RUN] 跳过实际 WoL 发送"
        return 0
    fi
    
    if command -v wolwin &> /dev/null || type wolwin &> /dev/null; then
        wolwin
        log_success "WoL 包已发送"
    elif [ -f "$HOME/.bashrc" ] && grep -q "alias wolwin" "$HOME/.bashrc"; then
        eval $(grep "alias wolwin" "$HOME/.bashrc" | sed "s/alias wolwin=//;s/'//g;s/\"//g")
        log_success "WoL 包已发送 (通过 alias)"
    else
        log_error "wolwin 命令未找到"
        return 1
    fi
}

# 等待服务就绪
wait_for_service() {
    log "等待 Comet TaskRunner 服务就绪..."
    
    for i in $(seq 1 $HEALTH_CHECK_RETRIES); do
        local status=$(check_service)
        if [ "$status" = "200" ]; then
            log_success "服务已就绪"
            return 0
        fi
        log "  检查 $i/$HEALTH_CHECK_RETRIES - 服务未响应..."
        sleep $HEALTH_CHECK_INTERVAL
    done
    
    log_error "服务等待超时"
    return 1
}

# 执行单个任务
execute_task() {
    local endpoint=$1
    local instruction=$2
    local description=$3
    
    log_task "执行: ${description}"
    log "  端点: ${endpoint}"
    log "  指令: ${instruction}"
    
    if [ "$DRY_RUN" = true ]; then
        log "[DRY-RUN] 跳过实际 API 调用"
        return 0
    fi
    
    local url="${COMET_BASE_URL}${endpoint}"
    local response
    local http_code
    
    # 直接发送请求到后端，不做端点验证
    # 后端自行处理请求的有效性
    response=$(curl -s -w "\n%{http_code}" -X POST "$url" \
        -H "Content-Type: application/json" \
        -H "X-API-Key: ${COMET_API_KEY}" \
        -d "{\"instruction\": \"${instruction}\"}" 2>&1)
    
    # 分离响应体和状态码
    http_code=$(echo "$response" | tail -n1)
    response=$(echo "$response" | sed '$d')
    
    # 记录响应
    log "  HTTP 状态: ${http_code}"
    log "  响应: ${response}"
    
    # 简单判断：2xx 状态码视为成功
    if [[ "$http_code" =~ ^2 ]]; then
        log_success "请求成功"
        return 0
    else
        log_error "请求失败 (HTTP ${http_code})"
        return 1
    fi
}

# 主函数
main() {
    echo ""
    log "=============================================="
    log "  每日定时任务开始"
    log "=============================================="
    log ""
    log "目标: ${COMET_BASE_URL}"
    log "任务数量: ${#TASKS[@]}"
    log "日志文件: ${LOG_FILE}"
    [ "$SKIP_WAKE" = true ] && log "模式: 跳过唤醒"
    [ "$DRY_RUN" = true ] && log "模式: 模拟运行"
    log ""
    
    # Step 1: 唤醒 Windows
    if [ "$SKIP_WAKE" = false ]; then
        wake_windows
        log ""
        countdown $WAKE_WAIT_SECONDS "等待系统启动"
    else
        log "跳过 WoL 唤醒步骤"
    fi
    
    # Step 2: 检查服务
    if ! wait_for_service; then
        log_error "服务不可用，终止任务"
        exit 1
    fi
    
    # Step 3: 执行所有任务
    log ""
    log "开始执行任务列表..."
    log ""
    
    local task_count=0
    local success_count=0
    local total_tasks=${#TASKS[@]}
    
    for task_entry in "${TASKS[@]}"; do
        task_count=$((task_count + 1))
        
        # 解析任务配置
        IFS='|' read -r endpoint instruction description <<< "$task_entry"
        
        log "[$task_count/$total_tasks] -------------------------"
        
        if execute_task "$endpoint" "$instruction" "$description"; then
            success_count=$((success_count + 1))
        fi
        
        # 任务间隔（最后一个任务不需要等待）
        if [ $task_count -lt $total_tasks ]; then
            log ""
            countdown $TASK_INTERVAL_SECONDS "下一个任务倒计时"
        fi
    done
    
    # 汇总
    log ""
    log "=============================================="
    log "  任务执行完成"
    log "=============================================="
    log "  成功: ${success_count}/${total_tasks}"
    log "  时间: $(date '+%Y-%m-%d %H:%M:%S')"
    log "=============================================="
    
    if [ $success_count -eq $total_tasks ]; then
        exit 0
    else
        exit 1
    fi
}

main
