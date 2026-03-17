#!/bin/bash
# ===========================================
# StardropHost | scripts/set-resolution.sh
# ===========================================
# Sets display resolution for Xorg via xrandr.
# Usage: set-resolution.sh [WIDTH] [HEIGHT] [REFRESH_RATE]
# ===========================================

TARGET_W=${1:-1280}
TARGET_H=${2:-720}
TARGET_R=${3:-60}
TARGET_MODE="${TARGET_W}x${TARGET_H}_${TARGET_R}.00"
SIMPLE_MODE="${TARGET_W}x${TARGET_H}"

echo "[Set-Resolution] Target: ${SIMPLE_MODE} @ ${TARGET_R}Hz"

# Find first connected output
OUTPUT=$(xrandr | awk '/ connected/ { print $1; exit }' 2>/dev/null || true)

if [ -z "$OUTPUT" ]; then
    echo "[Set-Resolution] No connected output detected, skipping"
    exit 0
fi

echo "[Set-Resolution] Output detected: $OUTPUT"

# Try simple mode name first (e.g. 1280x720)
if xrandr --output "$OUTPUT" --mode "$SIMPLE_MODE" >/dev/null 2>&1; then
    echo "[Set-Resolution] ✅ Set $OUTPUT to ${SIMPLE_MODE}"
    exit 0
fi

# Try mode name with refresh suffix (e.g. 1280x720_60.00)
if xrandr --output "$OUTPUT" --mode "$TARGET_MODE" >/dev/null 2>&1; then
    echo "[Set-Resolution] ✅ Set $OUTPUT to ${TARGET_MODE}"
    exit 0
fi

# Fallback: use cvt to generate a custom modeline
if command -v cvt >/dev/null 2>&1 && command -v xrandr >/dev/null 2>&1; then
    echo "[Set-Resolution] Generating custom modeline via cvt..."

    MODELINE=$(cvt ${TARGET_W} ${TARGET_H} ${TARGET_R} 2>/dev/null | sed -n '2p' | sed 's/Modeline //')

    if [ -n "$MODELINE" ]; then
        MODE_NAME=$(echo "$MODELINE" | awk '{print $1}' | tr -d \")

        xrandr --newmode $MODELINE >/dev/null 2>&1 || true
        xrandr --addmode "$OUTPUT" "$MODE_NAME" >/dev/null 2>&1 || true

        if xrandr --output "$OUTPUT" --mode "$MODE_NAME" >/dev/null 2>&1; then
            echo "[Set-Resolution] ✅ Applied custom mode $MODE_NAME to $OUTPUT"
            exit 0
        else
            echo "[Set-Resolution] Failed to apply custom mode $MODE_NAME"
        fi
    else
        echo "[Set-Resolution] cvt failed to generate modeline"
    fi
else
    echo "[Set-Resolution] cvt or xrandr not available"
fi

echo "[Set-Resolution] Could not set resolution, keeping current"
exit 1