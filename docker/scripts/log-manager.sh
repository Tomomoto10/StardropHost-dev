#!/bin/bash
# ===========================================
# StardropHost | scripts/log-manager.sh
# ===========================================
# Handles log rotation, compression and
# retention policy.
#
# Policy:
#   - Rotate logs over 50MB
#   - Keep uncompressed for 7 days
#   - Keep compressed archives for 30 days
# ===========================================

set -e

# -- Config --
LOG_BASE_DIR="/home/steam/.config/StardewValley/ErrorLogs"
ARCHIVE_DIR="/home/steam/.local/share/stardrop/logs/archive"
KEEP_DAYS=7
ARCHIVE_DAYS=30
MAX_LOG_SIZE_MB=50

# -- Colors --
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
log_info() { echo -e "${GREEN}[Log-Manager]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[Log-Manager]${NC} $1"; }

mkdir -p "$ARCHIVE_DIR"

# -- Rotate a log file if over size limit --
rotate_log() {
    local log_file="$1"
    local log_name=$(basename "$log_file")
    local timestamp=$(date +%Y%m%d_%H%M%S)

    if [ ! -f "$log_file" ]; then return; fi

    local size_mb=$(du -m "$log_file" | cut -f1)

    if [ "$size_mb" -ge "$MAX_LOG_SIZE_MB" ]; then
        log_info "Rotating $log_name (${size_mb}MB)"
        gzip -c "$log_file" > "$ARCHIVE_DIR/${log_name%.txt}_${timestamp}.txt.gz"
        # Truncate in place to preserve file handles
        > "$log_file"
        log_info "Archived to ${log_name%.txt}_${timestamp}.txt.gz"
    fi
}

# -- Clean old logs and archives --
clean_old_logs() {
    log_info "Cleaning old log archives..."

    find "$LOG_BASE_DIR" -name "*.txt" -type f -mtime +$KEEP_DAYS \
        -delete 2>/dev/null || true

    find "$ARCHIVE_DIR" -name "*.gz" -type f -mtime +$ARCHIVE_DAYS \
        -delete 2>/dev/null || true

    find "$ARCHIVE_DIR" -type d -empty \
        -delete 2>/dev/null || true

    log_info "Cleanup complete"
}

# -- Generate daily summary --
generate_summary() {
    local log_file="$LOG_BASE_DIR/SMAPI-latest.txt"
    [ -f "$log_file" ] || return

    log_info "Generating log summary..."

    local error_count=$(grep -c "ERROR" "$log_file" 2>/dev/null || echo "0")
    local warn_count=$(grep -c "WARN" "$log_file" 2>/dev/null || echo "0")
    local recent_errors=$(grep "ERROR" "$log_file" 2>/dev/null | tail -5 || echo "")

    local summary_file="$ARCHIVE_DIR/summary_$(date +%Y%m%d).txt"
    {
        echo "=== StardropHost Log Summary ==="
        echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
        echo "Statistics:"
        echo "  Errors:   $error_count"
        echo "  Warnings: $warn_count"
        echo ""
        if [ -n "$recent_errors" ]; then
            echo "Recent Errors:"
            echo "$recent_errors"
        fi
        echo ""
        echo "Archives: $ARCHIVE_DIR"
    } > "$summary_file"

    log_info "Summary saved to $summary_file"
}

# -- Run --
log_info "Starting log management cycle..."

rotate_log "$LOG_BASE_DIR/SMAPI-latest.txt"
clean_old_logs
generate_summary

log_info "Disk usage:"
echo "  Logs:     $(du -sh "$LOG_BASE_DIR" 2>/dev/null | cut -f1 || echo "0K")"
echo "  Archives: $(du -sh "$ARCHIVE_DIR" 2>/dev/null | cut -f1 || echo "0K")"

log_info "Log management complete"