#!/bin/bash
# ==============================================================================
# wake-antigravity.sh - Wake Windows PC and ensure Antigravity app is running
# ==============================================================================
#
# Functionality:
#   1. Send WoL to wake Windows PC
#   2. Wait for system startup and service ready
#   3. Check if Antigravity app is running
#   4. Launch Antigravity if not running
#
# Usage:
#   ./wake-antigravity.sh              # Normal execution (wake + check/launch)
#   ./wake-antigravity.sh --skip-wake  # Skip wake (PC already on)
#   ./wake-antigravity.sh --dry-run    # Dry run, no actual execution
#
# ==============================================================================

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configuration
if [ -f "${SCRIPT_DIR}/config.sh" ]; then
    source "${SCRIPT_DIR}/config.sh"
else
    echo "Error: config.sh not found"
    exit 1
fi

# Build API URL
COMET_BASE_URL="http://${WINDOWS_IP}:${COMET_PORT}"

# Antigravity app configuration
ANTIGRAVITY_PROCESS_NAME="Antigravity"
ANTIGRAVITY_APP_PATH="C:\\Users\\$(whoami)\\AppData\\Local\\Antigravity\\Antigravity.exe"

# Run modes
SKIP_WAKE=false
DRY_RUN=false
FORCE_RUN=false

# Parse command line arguments
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
        --force|-f)
            FORCE_RUN=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --skip-wake, -s  Skip WoL wake"
            echo "  --dry-run, -d    Dry run mode"
            echo "  --force, -f      Force run (ignore daily lock)"
            echo "  --help, -h       Show help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# ==============================================================================
# Daily execution lock (prevent duplicate runs on timer restart)
# ==============================================================================
TODAY=$(date '+%Y-%m-%d')
LOCK_DIR="/tmp/satellite-y"
LOCK_FILE="${LOCK_DIR}/wake-antigravity-${TODAY}.lock"

# Ensure lock directory exists
mkdir -p "$LOCK_DIR"

if [[ "$FORCE_RUN" == "false" ]] && [[ -f "$LOCK_FILE" ]]; then
    LOCK_TIME=$(cat "$LOCK_FILE" 2>/dev/null || echo "unknown")
    echo "=============================================="
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Task already executed today, skipping"
    echo "  Lock file: $LOCK_FILE"
    echo "  Executed at: $LOCK_TIME"
    echo "  To force run: $0 --force"
    echo "=============================================="
    exit 0
fi

# Record execution time to lock file
echo "$(date '+%Y-%m-%d %H:%M:%S')" > "$LOCK_FILE"

# Ensure log directory exists
ANTIGRAVITY_LOG_DIR="${HOME}/logs/wake_antigravity"
ANTIGRAVITY_LOG_FILE="${ANTIGRAVITY_LOG_DIR}/$(date '+%Y-%m-%d').log"
mkdir -p "$ANTIGRAVITY_LOG_DIR"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo -e "${BLUE}${msg}${NC}"
    echo "$msg" >> "$ANTIGRAVITY_LOG_FILE"
}

log_success() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: $1"
    echo -e "${GREEN}${msg}${NC}"
    echo "$msg" >> "$ANTIGRAVITY_LOG_FILE"
}

log_error() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1"
    echo -e "${RED}${msg}${NC}"
    echo "$msg" >> "$ANTIGRAVITY_LOG_FILE"
}

log_warning() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1"
    echo -e "${YELLOW}${msg}${NC}"
    echo "$msg" >> "$ANTIGRAVITY_LOG_FILE"
}

# Countdown timer
countdown() {
    local seconds=$1
    local message="${2:-Waiting}"

    while [ $seconds -gt 0 ]; do
        local mins=$((seconds / 60))
        local secs=$((seconds % 60))
        printf "\r${BLUE}[%s]${NC} ${message}: %02d:%02d " "$(date '+%H:%M:%S')" $mins $secs
        sleep 1
        seconds=$((seconds - 1))
    done
    printf "\r${BLUE}[%s]${NC} ${message}: Done!          \n" "$(date '+%H:%M:%S')"
}

# Check service health
check_service() {
    curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "${COMET_BASE_URL}/health" 2>/dev/null
}

# Send WoL wake
wake_windows() {
    log "Sending Wake-on-LAN..."

    # Load user alias
    if [ -f "$HOME/.bashrc" ]; then
        shopt -s expand_aliases 2>/dev/null
        source "$HOME/.bashrc" 2>/dev/null
    fi

    if [ "$DRY_RUN" = true ]; then
        log "[DRY-RUN] Skipping actual WoL send"
        return 0
    fi

    if command -v wolwin &> /dev/null || type wolwin &> /dev/null; then
        wolwin
        log_success "WoL packet sent"
    elif [ -f "$HOME/.bashrc" ] && grep -q "alias wolwin" "$HOME/.bashrc"; then
        eval $(grep "alias wolwin" "$HOME/.bashrc" | sed "s/alias wolwin=//;s/'//g;s/\"//g")
        log_success "WoL packet sent (via alias)"
    else
        log_error "wolwin command not found"
        return 1
    fi
}

# Wait for service ready
wait_for_service() {
    log "Waiting for Comet TaskRunner service..."

    for i in $(seq 1 $HEALTH_CHECK_RETRIES); do
        local status=$(check_service)
        if [ "$status" = "200" ]; then
            log_success "Service is ready"
            return 0
        fi
        log "  Check $i/$HEALTH_CHECK_RETRIES - Service not responding..."
        sleep $HEALTH_CHECK_INTERVAL
    done

    log_error "Service wait timeout"
    return 1
}

# Check if Antigravity is running using PowerShell via API
check_antigravity_running() {
    log "Checking if Antigravity is running..."

    if [ "$DRY_RUN" = true ]; then
        log "[DRY-RUN] Skipping process check"
        return 1  # Assume not running in dry-run mode
    fi

    local url="${COMET_BASE_URL}/execute/powershell"
    local check_script='Get-Process -Name \"Antigravity\" -ErrorAction SilentlyContinue | Select-Object -First 1 | ForEach-Object { \"RUNNING\" }'

    local response
    response=$(curl -s -X POST "$url" \
        -H "Content-Type: application/json" \
        -H "X-API-Key: ${COMET_API_KEY}" \
        -d "{\"script\": \"${check_script}\"}" 2>&1)

    log "  Process check response: ${response}"

    if echo "$response" | grep -q "RUNNING"; then
        return 0  # Process is running
    else
        return 1  # Process not running
    fi
}

# Launch Antigravity app
launch_antigravity() {
    log "Launching Antigravity app..."

    if [ "$DRY_RUN" = true ]; then
        log "[DRY-RUN] Skipping app launch"
        return 0
    fi

    local url="${COMET_BASE_URL}/execute/powershell"
    # Start Antigravity in a new process so it doesn't block
    local launch_script='Start-Process -FilePath \"$env:LOCALAPPDATA\\Antigravity\\Antigravity.exe\" -ErrorAction SilentlyContinue; Write-Output \"LAUNCHED\"'

    local response
    local http_code

    response=$(curl -s -w "\n%{http_code}" -X POST "$url" \
        -H "Content-Type: application/json" \
        -H "X-API-Key: ${COMET_API_KEY}" \
        -d "{\"script\": \"${launch_script}\"}" 2>&1)

    http_code=$(echo "$response" | tail -n1)
    response=$(echo "$response" | sed '$d')

    log "  HTTP Status: ${http_code}"
    log "  Response: ${response}"

    if [[ "$http_code" =~ ^2 ]]; then
        log_success "Antigravity launch command sent"
        return 0
    else
        log_error "Failed to launch Antigravity (HTTP ${http_code})"
        return 1
    fi
}

# Main function
main() {
    echo ""
    log "=============================================="
    log "  Wake & Antigravity Check Task"
    log "=============================================="
    log ""
    log "Target: ${COMET_BASE_URL}"
    log "Log file: ${ANTIGRAVITY_LOG_FILE}"
    [ "$SKIP_WAKE" = true ] && log "Mode: Skip wake"
    [ "$DRY_RUN" = true ] && log "Mode: Dry run"
    log ""

    # Step 1: Wake Windows
    if [ "$SKIP_WAKE" = false ]; then
        wake_windows
        log ""
        countdown $WAKE_WAIT_SECONDS "Waiting for system startup"
    else
        log "Skipping WoL wake step"
    fi

    # Step 2: Check service
    if ! wait_for_service; then
        log_error "Service not available, terminating"
        exit 1
    fi

    # Step 3: Check if Antigravity is running
    log ""
    log "Checking Antigravity status..."

    if check_antigravity_running; then
        log_success "Antigravity is already running"
    else
        log_warning "Antigravity is not running, launching..."

        # Step 4: Launch Antigravity
        if launch_antigravity; then
            # Wait a moment and verify
            sleep 5
            if check_antigravity_running; then
                log_success "Antigravity successfully started"
            else
                log_warning "Antigravity may have started but verification failed"
            fi
        else
            log_error "Failed to launch Antigravity"
            exit 1
        fi
    fi

    log ""
    log "=============================================="
    log "  Task completed"
    log "=============================================="
    log "  Time: $(date '+%Y-%m-%d %H:%M:%S')"
    log "=============================================="

    exit 0
}

main
