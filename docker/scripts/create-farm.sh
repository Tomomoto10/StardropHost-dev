#!/bin/bash
# ===========================================
# StardropHost | scripts/create-farm.sh
# ===========================================
# Automates new co-op farm creation via the
# game UI using xdotool. Called from entrypoint.sh
# when NEW_FARM_CONFIG exists and no save is present.
#
# Uses display :99 (Xvfb or Xorg, already started).
# ===========================================

CONFIG_FILE="/home/steam/web-panel/data/new-farm.json"
SMAPI_LOG="/home/steam/.config/StardewValley/ErrorLogs/SMAPI-latest.txt"

export DISPLAY=:99

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'
log_info()  { echo -e "${GREEN}[CreateFarm]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[CreateFarm]${NC} $1"; }
log_error() { echo -e "${RED}[CreateFarm]${NC} $1"; }

# -- Read config --
if [ ! -f "$CONFIG_FILE" ]; then
    log_warn "No new-farm config found, skipping"
    exit 0
fi

FARM_NAME=$(python3 -c "import json,sys; d=json.load(open('$CONFIG_FILE')); print(d.get('farmName','My Farm'))" 2>/dev/null || echo "My Farm")
FARM_TYPE=$(python3 -c "import json,sys; d=json.load(open('$CONFIG_FILE')); print(d.get('farmType','0'))" 2>/dev/null || echo "0")
CABIN_COUNT=$(python3 -c "import json,sys; d=json.load(open('$CONFIG_FILE')); print(d.get('cabinCount','1'))" 2>/dev/null || echo "1")
PET_TYPE=$(python3 -c "import json,sys; d=json.load(open('$CONFIG_FILE')); print(d.get('petType','cat'))" 2>/dev/null || echo "cat")
FARMER_NAME=$(python3 -c "import json,sys; d=json.load(open('$CONFIG_FILE')); print(d.get('farmerName','Host'))" 2>/dev/null || echo "Host")

log_info "Creating new farm: '$FARM_NAME' (type=$FARM_TYPE, cabins=$CABIN_COUNT, pet=$PET_TYPE)"

# -- Wait for SMAPI to reach a state where xdotool can interact --
log_info "Waiting for SMAPI title screen..."
WAIT=0
while [ $WAIT -lt 120 ]; do
    if grep -q "SMAPI console ready\|title screen\|Performing core startup tasks" "$SMAPI_LOG" 2>/dev/null; then
        break
    fi
    sleep 3
    WAIT=$((WAIT + 3))
done

log_info "Waiting for game window..."
sleep 15

# -- Helper: click at coordinates --
click() {
    local x=$1 y=$2
    xdotool mousemove --sync "$x" "$y"
    sleep 0.3
    xdotool click 1
    sleep 0.5
}

# -- Helper: type text (clears first) --
type_text() {
    xdotool key ctrl+a
    sleep 0.1
    xdotool type --clearmodifiers --delay 50 "$1"
    sleep 0.3
}

# Resolution-based coordinate scaling (default 1280x720)
RES_W=${RESOLUTION_WIDTH:-1280}
RES_H=${RESOLUTION_HEIGHT:-720}
CX=$((RES_W / 2))   # center X
CY=$((RES_H / 2))   # center Y

log_info "Display: ${RES_W}x${RES_H}, center: ${CX}x${CY}"

# -- Step 1: Dismiss title screen --
log_info "Dismissing title screen..."
sleep 3
click $CX $CY
sleep 2
xdotool key Return
sleep 3

# -- Step 2: Navigate to Co-op --
# Co-op button is the 4th item in the main menu, below center
# Approximate Y positions (scaled from 720p reference):
# New Game: CY - 60, Co-op: CY - 10, Load: CY + 40
COOP_Y=$(( CY - 10 ))
log_info "Clicking Co-op at ${CX},${COOP_Y}..."
click $CX $COOP_Y
sleep 3

# -- Step 3: Click Host --
# "Host" is typically on the left side of the co-op screen
HOST_X=$(( CX - 160 ))
HOST_Y=$(( CY - 20 ))
log_info "Clicking Host at ${HOST_X},${HOST_Y}..."
click $HOST_X $HOST_Y
sleep 2

# -- Step 4: Click "New Farm" --
# The "New Farm" button is at the bottom of the farm list
NEW_FARM_Y=$(( CY + 180 ))
log_info "Clicking New Farm at ${CX},${NEW_FARM_Y}..."
click $CX $NEW_FARM_Y
sleep 3

# -- Step 5: Character creation screen --
# Farmer name field (top of screen)
FARMER_Y=$(( CY - 250 ))
log_info "Setting farmer name: '$FARMER_NAME'..."
click $CX $FARMER_Y
type_text "$FARMER_NAME"
xdotool key Return
sleep 1

# Farm name field (below farmer name)
FARM_NAME_Y=$(( CY - 180 ))
log_info "Setting farm name: '$FARM_NAME'..."
click $CX $FARM_NAME_Y
type_text "$FARM_NAME"
sleep 1

# -- Step 6: Farm type selection --
# Farm types are displayed as icons in a row
# Standard=0: leftmost, then Riverland=1, Forest=2, Hill-top=3, Wilderness=4, Four Corners=5, Beach=6
# At 1280x720 the farm type row is roughly at Y=280, X spanning 300-980
FARM_TYPE_Y=$(( CY - 50 ))
FARM_TYPE_START_X=300
FARM_TYPE_STEP=$(( (RES_W - 300) / 7 ))
FARM_TYPE_X=$(( FARM_TYPE_START_X + FARM_TYPE * FARM_TYPE_STEP ))
log_info "Selecting farm type $FARM_TYPE at ${FARM_TYPE_X},${FARM_TYPE_Y}..."
click $FARM_TYPE_X $FARM_TYPE_Y
sleep 1

# -- Step 7: Cabin count --
# +/- buttons for cabin count are typically in the lower portion
# We need to click + CABIN_COUNT times
CABIN_PLUS_X=$(( CX + 180 ))
CABIN_Y=$(( CY + 80 ))
log_info "Setting $CABIN_COUNT cabins..."
for i in $(seq 1 $CABIN_COUNT); do
    click $CABIN_PLUS_X $CABIN_Y
    sleep 0.3
done

# -- Step 8: Pet selection --
# Cat is left, dog is right. Click the appropriate one.
PET_Y=$(( CY + 150 ))
if [ "$PET_TYPE" = "dog" ]; then
    PET_X=$(( CX + 150 ))
else
    PET_X=$(( CX - 150 ))
fi
log_info "Selecting pet: $PET_TYPE at ${PET_X},${PET_Y}..."
click $PET_X $PET_Y
sleep 1

# -- Step 9: Confirm / Start --
# "OK" button is typically at the bottom center
OK_Y=$(( CY + 260 ))
log_info "Clicking OK to start..."
click $CX $OK_Y
sleep 3

# Wait for save to be created and loaded
log_info "Waiting for farm to load (up to 3 minutes)..."
WAIT=0
while [ $WAIT -lt 180 ]; do
    if grep -q "SAVE LOADED SUCCESSFULLY\|Context: loaded save\|type: save" "$SMAPI_LOG" 2>/dev/null; then
        log_info "✅ Farm created and loaded successfully!"
        # Remove the new-farm config so it doesn't run again
        rm -f "$CONFIG_FILE"
        exit 0
    fi
    sleep 5
    WAIT=$((WAIT + 5))
done

log_warn "⚠️  Farm creation may not have completed automatically."
log_warn "   Connect via VNC to complete setup if needed."
log_warn "   VNC port: 5900"
exit 1
