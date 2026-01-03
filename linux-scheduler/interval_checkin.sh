#!/bin/bash
# ==============================================================================
# interval_checkin.sh - 间隔循环执行脚本（测试用）
# ==============================================================================
#
# 功能：
#   每隔指定时间执行一次所有签到任务，直到手动终止 (Ctrl+C)
#
# 使用方法：
#   ./interval_checkin.sh              # 默认每 5 分钟执行一次
#   ./interval_checkin.sh 10           # 每 10 分钟执行一次
#   ./interval_checkin.sh 1            # 每 1 分钟执行一次（快速测试）
#
# ==============================================================================

# 获取脚本目录并加载配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "${SCRIPT_DIR}/config.sh" ]; then
    source "${SCRIPT_DIR}/config.sh"
else
    echo "❌ 错误: config.sh 未找到，使用默认配置"
    WINDOWS_IP="192.168.0.147"
    COMET_PORT="5000"
    COMET_API_KEY="${COMET_API_KEY:-my-secret-password-123}"
    WAKE_WAIT_SECONDS=20
    TASK_INTERVAL_SECONDS=30
    TASKS=(
        "/execute/ai|/1mu3|1688 每日签到"
        "/execute/ai|/iyf|IYF 每日任务"
    )
fi

# 配置覆盖
INTERVAL_MINUTES="${1:-5}"              # 默认 5 分钟，可通过参数覆盖
COMET_BASE_URL="http://${WINDOWS_IP}:${COMET_PORT}"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_task() {
    echo -e "${CYAN}[$(date '+%Y-%m-%d %H:%M:%S')] 🔹 $1${NC}"
}

# 实时倒计时显示
countdown() {
    local seconds=$1
    local message="${2:-等待中}"
    
    while [ $seconds -gt 0 ]; do
        local mins=$((seconds / 60))
        local secs=$((seconds % 60))
        printf "\r${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} ⏱️  ${message}: %02d:%02d 剩余 " $mins $secs
        sleep 1
        seconds=$((seconds - 1))
    done
    printf "\r${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} ⏱️  ${message}: 00:00 完成!      \n"
}

# 检查服务是否在线
check_service() {
    curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "${COMET_BASE_URL}/health" 2>/dev/null
}

# 执行单个任务
execute_task() {
    local endpoint=$1
    local instruction=$2
    local description=$3
    
    log_task "执行: ${description}"
    log "  端点: ${endpoint}"
    log "  指令: ${instruction}"
    
    local url="${COMET_BASE_URL}${endpoint}"
    local response
    
    if [[ "$endpoint" == "/execute/ai" ]]; then
        response=$(curl -s -X POST "$url" \
            -H "Content-Type: application/json" \
            -H "X-API-Key: ${COMET_API_KEY}" \
            -d "{\"instruction\": \"${instruction}\"}" 2>&1)
    elif [[ "$endpoint" == "/execute/url" ]]; then
        response=$(curl -s -X POST "$url" \
            -H "Content-Type: application/json" \
            -H "X-API-Key: ${COMET_API_KEY}" \
            -d "{\"url\": \"${instruction}\"}" 2>&1)
    else
        log_error "未知端点类型: ${endpoint}"
        return 1
    fi
    
    if echo "$response" | grep -q "task_id"; then
        local task_id=$(echo "$response" | grep -o '"task_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
        log_success "任务已提交 (ID: ${task_id})"
        return 0
    else
        log_error "任务提交失败: ${response}"
        return 1
    fi
}

# 执行一次完整的签到流程
run_checkin_cycle() {
    local cycle_num=$1
    
    echo ""
    log "=========================================="
    log "  执行周期 #${cycle_num}"
    log "=========================================="
    
    # Step 1: 发送 WoL 唤醒
    log "Step 1: 发送 Wake-on-LAN..."
    
    # 尝试加载用户的 alias 定义
    if [ -f "$HOME/.bashrc" ]; then
        shopt -s expand_aliases 2>/dev/null
        source "$HOME/.bashrc" 2>/dev/null
    fi
    
    if command -v wolwin &> /dev/null || type wolwin &> /dev/null; then
        wolwin
        log_success "WoL 包已发送"
    elif [ -f "$HOME/.bashrc" ] && grep -q "alias wolwin" "$HOME/.bashrc"; then
        eval $(grep "alias wolwin" "$HOME/.bashrc" | sed "s/alias wolwin=//;s/'//g;s/\"//g")
        log_success "WoL 包已发送 (通过 alias)"
    else
        log_warning "wolwin 命令未找到"
    fi
    
    # Step 2: 等待系统启动
    log "Step 2: 等待系统启动..."
    countdown $WAKE_WAIT_SECONDS "系统启动"
    
    # Step 3: 检查服务状态
    log "Step 3: 检查 Comet TaskRunner 服务..."
    local retries=5
    local connected=false
    
    for i in $(seq 1 $retries); do
        local status=$(check_service)
        if [ "$status" = "200" ]; then
            log_success "服务已就绪"
            connected=true
            break
        fi
        log "  服务未响应，重试 $i/$retries..."
        sleep 10
    done
    
    if [ "$connected" = false ]; then
        log_error "服务未能启动，跳过本次周期"
        return 1
    fi
    
    # Step 4: 执行所有任务
    log "Step 4: 执行任务列表 (共 ${#TASKS[@]} 个)..."
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
        
        # 任务间隔
        if [ $task_count -lt $total_tasks ]; then
            log ""
            countdown $TASK_INTERVAL_SECONDS "下一个任务"
        fi
    done
    
    log ""
    log_success "周期 #${cycle_num} 完成: ${success_count}/${total_tasks} 成功"
    return 0
}

# 主循环
main() {
    local cycle=0
    local interval_seconds=$((INTERVAL_MINUTES * 60))
    
    echo ""
    echo "=============================================="
    echo "  间隔循环签到脚本"
    echo "=============================================="
    echo ""
    echo "  目标: ${COMET_BASE_URL}"
    echo "  任务数量: ${#TASKS[@]}"
    for task_entry in "${TASKS[@]}"; do
        IFS='|' read -r _ instruction description <<< "$task_entry"
        echo "    - ${description} (${instruction})"
    done
    echo "  间隔: ${INTERVAL_MINUTES} 分钟"
    echo "  按 Ctrl+C 终止"
    echo ""
    echo "=============================================="
    
    # 捕获 Ctrl+C
    trap 'echo ""; log_warning "收到终止信号，正在退出..."; exit 0' SIGINT SIGTERM
    
    # 首次执行前等待
    log ""
    log "首次执行将在 ${INTERVAL_MINUTES} 分钟后开始..."
    countdown $interval_seconds "首次执行倒计时"
    
    while true; do
        cycle=$((cycle + 1))
        run_checkin_cycle $cycle
        
        log ""
        countdown $interval_seconds "下次执行倒计时"
    done
}

main
