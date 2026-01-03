#!/bin/bash
# ==============================================================================
# daily_checkin.sh - 每日签到自动化脚本
# ==============================================================================
# 
# 功能：
#   1. 使用 wolwin 命令唤醒 Windows PC
#   2. 等待 PC 启动并确认 Comet TaskRunner 服务可用
#   3. 调用 API 执行每日签到任务
#
# 兼容系统：
#   - DietPi (Raspberry Pi)
#   - macOS
#   - 任何支持 bash 的 Linux 系统
#
# 使用方法：
#   chmod +x daily_checkin.sh
#   ./daily_checkin.sh
#
# ==============================================================================

# =============================================================================
# 配置区域 - 根据你的环境修改这些值
# =============================================================================

# Windows PC 配置
WINDOWS_IP="192.168.0.147"
COMET_PORT="5000"
COMET_BASE_URL="http://${WINDOWS_IP}:${COMET_PORT}"

# API 配置
# 从环境变量读取，如果未设置则使用默认值（本地测试不需要 key）
COMET_API_KEY="${COMET_API_KEY:-}"

# 每日签到指令 - Comet 快捷命令
DAILY_CHECKIN_INSTRUCTION="/1mu3"

# 等待配置
WAKE_WAIT_SECONDS=90          # 唤醒后等待 PC 启动的时间
HEALTH_CHECK_RETRIES=10       # 健康检查重试次数
HEALTH_CHECK_INTERVAL=10      # 每次健康检查间隔（秒）

# 日志配置
LOG_FILE="${HOME}/daily_checkin.log"

# 运行模式
SKIP_WAKE=false               # 跳过唤醒步骤（用于 PC 已开机时测试）
TEST_MODE=false               # 测试模式（更详细的输出）

# =============================================================================
# 函数定义
# =============================================================================

log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" | tee -a "$LOG_FILE"
}

log_error() {
    log "❌ ERROR: $1"
}

log_success() {
    log "✅ $1"
}

log_info() {
    log "ℹ️  $1"
}

# 唤醒 Windows PC
wake_windows() {
    log_info "发送 Wake-on-LAN 唤醒请求..."
    
    # 使用用户已有的 wolwin 命令
    if command -v wolwin &> /dev/null; then
        wolwin
        log_success "已发送唤醒包 (使用 wolwin 命令)"
        return 0
    else
        log_error "wolwin 命令不存在，请确保已配置"
        return 1
    fi
}

# 检查 Comet TaskRunner 健康状态
check_health() {
    local url="${COMET_BASE_URL}/health"
    local response
    
    response=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$url" 2>/dev/null)
    
    if [ "$response" = "200" ]; then
        return 0
    else
        return 1
    fi
}

# 等待 Comet TaskRunner 服务启动
wait_for_service() {
    log_info "等待 Comet TaskRunner 服务启动..."
    log_info "目标地址: ${COMET_BASE_URL}"
    
    for i in $(seq 1 $HEALTH_CHECK_RETRIES); do
        log_info "健康检查 [$i/$HEALTH_CHECK_RETRIES]..."
        
        if check_health; then
            log_success "Comet TaskRunner 服务已就绪！"
            return 0
        fi
        
        if [ $i -lt $HEALTH_CHECK_RETRIES ]; then
            log_info "服务未就绪，${HEALTH_CHECK_INTERVAL} 秒后重试..."
            sleep $HEALTH_CHECK_INTERVAL
        fi
    done
    
    log_error "服务启动超时，放弃执行"
    return 1
}

# 执行每日签到
execute_checkin() {
    log_info "执行每日签到任务..."
    log_info "指令: ${DAILY_CHECKIN_INSTRUCTION}"
    
    local url="${COMET_BASE_URL}/execute/ai"
    local headers="-H 'Content-Type: application/json'"
    
    # 如果设置了 API Key，添加到请求头
    if [ -n "$COMET_API_KEY" ]; then
        headers="${headers} -H 'X-API-Key: ${COMET_API_KEY}'"
    fi
    
    local body="{\"instruction\": \"${DAILY_CHECKIN_INSTRUCTION}\"}"
    
    # 执行 API 调用
    local response
    if [ -n "$COMET_API_KEY" ]; then
        response=$(curl -s -X POST "$url" \
            -H "Content-Type: application/json" \
            -H "X-API-Key: ${COMET_API_KEY}" \
            -d "$body" 2>&1)
    else
        response=$(curl -s -X POST "$url" \
            -H "Content-Type: application/json" \
            -d "$body" 2>&1)
    fi
    
    # 检查响应
    if echo "$response" | grep -q "task_id"; then
        local task_id=$(echo "$response" | grep -o '"task_id"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)"$/\1/')
        log_success "签到任务已提交！Task ID: ${task_id}"
        log_info "响应: ${response}"
        return 0
    else
        log_error "签到任务提交失败"
        log_error "响应: ${response}"
        return 1
    fi
}

# =============================================================================
# 参数解析
# =============================================================================

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "每日签到自动化脚本 - 唤醒 Windows PC 并执行签到任务"
    echo ""
    echo "Options:"
    echo "  --test, -t       测试模式（详细输出，不等待唤醒）"
    echo "  --skip-wake, -s  跳过唤醒步骤（PC 已开机时使用）"
    echo "  --help, -h       显示此帮助信息"
    echo ""
    echo "Examples:"
    echo "  $0               # 正常运行（唤醒 + 签到）"
    echo "  $0 --test        # 测试模式（跳过唤醒等待）"
    echo "  $0 --skip-wake   # 仅执行签到（PC 已开机）"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --test|-t)
            TEST_MODE=true
            SKIP_WAKE=true
            WAKE_WAIT_SECONDS=5
            HEALTH_CHECK_RETRIES=3
            HEALTH_CHECK_INTERVAL=3
            shift
            ;;
        --skip-wake|-s)
            SKIP_WAKE=true
            WAKE_WAIT_SECONDS=5
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# =============================================================================
# 主程序
# =============================================================================

main() {
    log "=============================================="
    log "  每日签到自动化任务开始"
    if [ "$TEST_MODE" = true ]; then
        log "  [测试模式]"
    fi
    log "=============================================="
    
    # Step 1: 唤醒 Windows PC（除非跳过）
    if [ "$SKIP_WAKE" = true ]; then
        log_info "跳过唤醒步骤"
    else
        if ! wake_windows; then
            log_error "唤醒失败，终止任务"
            exit 1
        fi
        
        # Step 2: 等待 PC 启动
        log_info "等待 ${WAKE_WAIT_SECONDS} 秒让 Windows PC 启动..."
        sleep $WAKE_WAIT_SECONDS
    fi
    
    # Step 3: 检查服务是否启动
    if ! wait_for_service; then
        log_error "服务未启动，终止任务"
        exit 1
    fi
    
    # Step 4: 执行签到
    if ! execute_checkin; then
        log_error "签到执行失败"
        exit 1
    fi
    
    log "=============================================="
    log "  每日签到任务完成！"
    log "=============================================="
    
    exit 0
}

# 运行主程序
main "$@"
