#!/bin/bash
# ==============================================================================
# interval_checkin.sh - 间隔循环执行脚本（测试用）
# ==============================================================================
#
# 功能：
#   每隔指定时间执行一次签到任务，直到手动终止 (Ctrl+C)
#
# 使用方法：
#   ./interval_checkin.sh              # 默认每 5 分钟执行一次
#   ./interval_checkin.sh 10           # 每 10 分钟执行一次
#   ./interval_checkin.sh 1            # 每 1 分钟执行一次（快速测试）
#
# ==============================================================================

# 配置
INTERVAL_MINUTES="${1:-5}"              # 默认 5 分钟，可通过参数覆盖
WINDOWS_IP="192.168.0.147"
COMET_PORT="5000"
COMET_BASE_URL="http://${WINDOWS_IP}:${COMET_PORT}"
DAILY_CHECKIN_INSTRUCTION="/1mu3"
WAKE_WAIT_SECONDS=90                    # 唤醒后等待时间

# 从环境变量读取 API Key
COMET_API_KEY="${COMET_API_KEY:-my-secret-password-123}"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# 检查服务是否在线
check_service() {
    curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "${COMET_BASE_URL}/health" 2>/dev/null
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
    if command -v wolwin &> /dev/null; then
        wolwin
        log_success "WoL 包已发送"
    else
        log_warning "wolwin 命令未找到，跳过唤醒"
    fi
    
    # Step 2: 等待系统启动
    log "Step 2: 等待 ${WAKE_WAIT_SECONDS} 秒让系统启动..."
    sleep $WAKE_WAIT_SECONDS
    
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
        log_error "服务未能启动，跳过本次签到"
        return 1
    fi
    
    # Step 4: 执行签到
    log "Step 4: 执行签到任务 (${DAILY_CHECKIN_INSTRUCTION})..."
    local response
    response=$(curl -s -X POST "${COMET_BASE_URL}/execute/ai" \
        -H "Content-Type: application/json" \
        -H "X-API-Key: ${COMET_API_KEY}" \
        -d "{\"instruction\": \"${DAILY_CHECKIN_INSTRUCTION}\"}" 2>&1)
    
    if echo "$response" | grep -q "task_id"; then
        log_success "签到任务已提交"
        log "响应: $response"
        return 0
    else
        log_error "签到失败: $response"
        return 1
    fi
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
    echo "  指令: ${DAILY_CHECKIN_INSTRUCTION}"
    echo "  间隔: ${INTERVAL_MINUTES} 分钟"
    echo "  按 Ctrl+C 终止"
    echo ""
    echo "=============================================="
    
    # 捕获 Ctrl+C
    trap 'echo ""; log_warning "收到终止信号，正在退出..."; exit 0' SIGINT SIGTERM
    
    while true; do
        cycle=$((cycle + 1))
        run_checkin_cycle $cycle
        
        log ""
        log "下次执行: ${INTERVAL_MINUTES} 分钟后 ($(date -d "+${INTERVAL_MINUTES} minutes" '+%H:%M:%S' 2>/dev/null || date -v+${INTERVAL_MINUTES}M '+%H:%M:%S'))"
        log "按 Ctrl+C 终止..."
        log ""
        
        sleep $interval_seconds
    done
}

main
