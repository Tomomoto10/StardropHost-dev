#!/bin/bash
# ===========================================
# StardropHost | scripts/init-container.sh
# ===========================================
# Runs as root in the init container before
# the main server starts. Handles:
#   1. Create required data directories
#   2. Fix file ownership (UID 1000 = steam)
#   3. GPU Xorg prep if enabled
#
# Replaces the manual init.sh step entirely.
# Users never need to run this manually.
# ===========================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
log_info() { echo -e "${GREEN}[Init]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[Init]${NC} $1"; }

log_info "================================================"
log_info "  StardropHost - Init Container"
log_info "================================================"

# -- 1. Create data directories --
log_info "Creating data directories..."

DIRS=(
    "/home/steam/.config/StardewValley"
    "/home/steam/.config/StardewValley/ErrorLogs"
    "/home/steam/stardewvalley"
    "/home/steam/web-panel/data"
    "/home/steam/.local/share/stardrop"
    "/home/steam/.local/share/stardrop/logs"
    "/home/steam/.local/share/stardrop/backups"

    # Host-side bind mount targets
    # Created here so Docker doesn't create them as root
    "/home/steam/.config/StardewValley/Saves"
    "/home/steam/custom-mods"
)

for dir in "${DIRS[@]}"; do
    mkdir -p "$dir"
done

log_info "✅ Directories created"

# -- 2. Fix ownership to steam user (UID 1000) --
log_info "Fixing file ownership..."

FIXED_COUNT=0
for dir in "${DIRS[@]}"; do
    if [ -d "$dir" ]; then
        WRONG_OWNER=$(find "$dir" ! -uid 1000 2>/dev/null | wc -l)
        if [ "$WRONG_OWNER" -gt 0 ]; then
            log_warn "Fixing $WRONG_OWNER file(s) in $dir"
            chown -R 1000:1000 "$dir" 2>/dev/null || true
            FIXED_COUNT=$((FIXED_COUNT + WRONG_OWNER))
        fi
    fi
done

# Also fix the game directory if it exists (user may have mounted files)
if [ -d "/home/steam/stardewvalley" ] && \
   [ "$(find /home/steam/stardewvalley ! -uid 1000 2>/dev/null | wc -l)" -gt 0 ]; then
    log_warn "Fixing ownership on game directory..."
    chown -R 1000:1000 /home/steam/stardewvalley 2>/dev/null || true
fi

if [ "$FIXED_COUNT" -gt 0 ]; then
    log_info "✅ Fixed permissions for $FIXED_COUNT file(s)"
else
    log_info "✅ All permissions correct"
fi

# -- 3. GPU Xorg prep --
if [ "$USE_GPU" = "true" ]; then
    log_info "GPU mode enabled, preparing Xorg directories..."
    mkdir -p /tmp/.X11-unix
    chmod 1777 /tmp/.X11-unix
    mkdir -p /home/steam/.local/share/xorg
    chown 1000:1000 /home/steam/.local/share/xorg 2>/dev/null || true
    log_info "✅ GPU directories prepared"
fi

log_info "================================================"
log_info "  Init complete! Main container starting..."
log_info "================================================"