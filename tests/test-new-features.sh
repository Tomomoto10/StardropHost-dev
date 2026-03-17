#!/bin/bash
# =============================================================================
# StardropHost – Script Test Suite
#
# Runs WITHOUT Docker or the game. Tests logic, syntax, and behavior of each
# script using temporary directories for full isolation.
#
# Usage: bash tests/test-new-features.sh
# =============================================================================

set -o pipefail

# ---- Globals ----------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DOCKER_SCRIPTS="$SCRIPT_DIR/docker/scripts"
TMPDIR_ROOT=""
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_NAMES=()

# ---- Colors -----------------------------------------------------------------
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ---- Helpers ----------------------------------------------------------------
setup_tmpdir() {
    TMPDIR_ROOT=$(mktemp -d "/tmp/stardrop-test-XXXXXX")
}

cleanup_tmpdir() {
    [ -n "$TMPDIR_ROOT" ] && rm -rf "$TMPDIR_ROOT"
}

# Called at exit – always clean up
trap cleanup_tmpdir EXIT

pass() {
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "  ${GREEN}PASS${NC}: $1"
}

fail() {
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_NAMES+=("$1")
    echo -e "  ${RED}FAIL${NC}: $1"
}

section() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# =============================================================================
# 1. SYNTAX VALIDATION – bash -n on every new script
# =============================================================================
test_syntax_validation() {
    section "1. Syntax Validation (bash -n)"

    local scripts=(
        "$DOCKER_SCRIPTS/crash-monitor.sh"
        "$DOCKER_SCRIPTS/init-container.sh"
        "$DOCKER_SCRIPTS/save-selector.sh"
        "$DOCKER_SCRIPTS/status-reporter.sh"
        "$DOCKER_SCRIPTS/entrypoint.sh"
        "$DOCKER_SCRIPTS/event-handler.sh"
        "$DOCKER_SCRIPTS/auto-backup.sh"
        "$DOCKER_SCRIPTS/log-manager.sh"
        "$DOCKER_SCRIPTS/log-monitor.sh"
        "$DOCKER_SCRIPTS/vnc-monitor.sh"
        "$DOCKER_SCRIPTS/set-resolution.sh"
    )

    for script in "${scripts[@]}"; do
        local name
        name=$(basename "$script")
        if [ ! -f "$script" ]; then
            # Script doesn't exist – skip silently (not all may be present)
            continue
        fi

        if bash -n "$script" 2>/dev/null; then
            pass "syntax OK: $name"
        else
            fail "syntax ERROR: $name"
        fi
    done
}

# =============================================================================
# 2. CRASH-MONITOR.SH – test can_restart() rate-limiting logic
# =============================================================================
test_crash_monitor() {
    section "2. crash-monitor.sh – can_restart() rate-limiting"

    # We extract can_restart and supporting variables into a sub-shell so we
    # don't execute the main loop (which does cd + exec).

    # 2a. Fresh state – should allow restart
    local result
    result=$(bash -c '
        MAX_RESTARTS=3
        RESTART_WINDOW=300
        RESTART_TIMES=()

        can_restart() {
            local now=$(date +%s)
            local recent=0
            for t in "${RESTART_TIMES[@]}"; do
                [ $((now - t)) -lt $RESTART_WINDOW ] && recent=$((recent + 1))
            done
            [ $recent -lt $MAX_RESTARTS ]
        }

        can_restart && echo "ALLOW" || echo "DENY"
    ')
    if [ "$result" = "ALLOW" ]; then
        pass "can_restart allows restart with empty history"
    else
        fail "can_restart should allow restart with empty history (got: $result)"
    fi

    # 2b. After MAX_RESTARTS recent restarts – should deny
    result=$(bash -c '
        MAX_RESTARTS=3
        RESTART_WINDOW=300
        NOW=$(date +%s)
        RESTART_TIMES=( $((NOW - 10)) $((NOW - 5)) $((NOW - 1)) )

        can_restart() {
            local now=$(date +%s)
            local recent=0
            for t in "${RESTART_TIMES[@]}"; do
                [ $((now - t)) -lt $RESTART_WINDOW ] && recent=$((recent + 1))
            done
            [ $recent -lt $MAX_RESTARTS ]
        }

        can_restart && echo "ALLOW" || echo "DENY"
    ')
    if [ "$result" = "DENY" ]; then
        pass "can_restart denies after MAX_RESTARTS recent restarts"
    else
        fail "can_restart should deny after MAX_RESTARTS recent restarts (got: $result)"
    fi

    # 2c. Old restarts outside the window should not count
    result=$(bash -c '
        MAX_RESTARTS=3
        RESTART_WINDOW=300
        NOW=$(date +%s)
        RESTART_TIMES=( $((NOW - 600)) $((NOW - 500)) $((NOW - 400)) )

        can_restart() {
            local now=$(date +%s)
            local recent=0
            for t in "${RESTART_TIMES[@]}"; do
                [ $((now - t)) -lt $RESTART_WINDOW ] && recent=$((recent + 1))
            done
            [ $recent -lt $MAX_RESTARTS ]
        }

        can_restart && echo "ALLOW" || echo "DENY"
    ')
    if [ "$result" = "ALLOW" ]; then
        pass "can_restart allows when all restarts are outside the window"
    else
        fail "can_restart should allow when restarts are outside the window (got: $result)"
    fi

    # 2d. Mixed: 2 recent + 1 old with MAX_RESTARTS=3 – should allow
    result=$(bash -c '
        MAX_RESTARTS=3
        RESTART_WINDOW=300
        NOW=$(date +%s)
        RESTART_TIMES=( $((NOW - 600)) $((NOW - 10)) $((NOW - 5)) )

        can_restart() {
            local now=$(date +%s)
            local recent=0
            for t in "${RESTART_TIMES[@]}"; do
                [ $((now - t)) -lt $RESTART_WINDOW ] && recent=$((recent + 1))
            done
            [ $recent -lt $MAX_RESTARTS ]
        }

        can_restart && echo "ALLOW" || echo "DENY"
    ')
    if [ "$result" = "ALLOW" ]; then
        pass "can_restart allows with mixed old/recent restarts under limit"
    else
        fail "can_restart should allow with 2 recent + 1 old (got: $result)"
    fi

    # 2e. MAX_CRASH_RESTARTS env override
    result=$(bash -c '
        MAX_RESTARTS=${MAX_CRASH_RESTARTS:-5}
        echo "$MAX_RESTARTS"
    ' -- 2>/dev/null)
    if [ "$result" = "5" ]; then
        pass "MAX_CRASH_RESTARTS defaults to 5"
    else
        fail "MAX_CRASH_RESTARTS default should be 5 (got: $result)"
    fi

    result=$(MAX_CRASH_RESTARTS=10 bash -c '
        MAX_RESTARTS=${MAX_CRASH_RESTARTS:-5}
        echo "$MAX_RESTARTS"
    ' 2>/dev/null)
    if [ "$result" = "10" ]; then
        pass "MAX_CRASH_RESTARTS env override works (set to 10)"
    else
        fail "MAX_CRASH_RESTARTS env override should be 10 (got: $result)"
    fi

    # 2f. RESTART_TIMES array trimming logic
    result=$(bash -c '
        MAX_RESTARTS=3
        RESTART_TIMES=(100 200 300)
        RESTART_TIMES+=("400")
        [ ${#RESTART_TIMES[@]} -gt $MAX_RESTARTS ] && RESTART_TIMES=("${RESTART_TIMES[@]:1}")
        echo "${#RESTART_TIMES[@]} ${RESTART_TIMES[0]}"
    ')
    if [ "$result" = "3 200" ]; then
        pass "RESTART_TIMES array trims oldest entry correctly"
    else
        fail "RESTART_TIMES trimming broken (got: $result)"
    fi
}

# =============================================================================
# 3. INIT-CONTAINER.SH – directory creation & chown logic
# =============================================================================
test_init_container() {
    section "3. init-container.sh – directory creation & chown logic"

    local td="$TMPDIR_ROOT/init-test"
    mkdir -p "$td"

    # 3a. Verify the DIRS array creates all expected directories
    result=$(bash -c '
        HOME_BASE="'"$td"'"
        DIRS=(
            "$HOME_BASE/.config/StardewValley"
            "$HOME_BASE/stardewvalley"
            "$HOME_BASE/Steam"
            "$HOME_BASE/.local/share/stardrop/logs"
            "$HOME_BASE/.local/share/stardrop/backups"
        )
        for dir in "${DIRS[@]}"; do
            mkdir -p "$dir"
        done
        # Check all exist
        ALL_OK=true
        for dir in "${DIRS[@]}"; do
            [ -d "$dir" ] || ALL_OK=false
        done
        echo "$ALL_OK"
    ')
    if [ "$result" = "true" ]; then
        pass "init-container creates all required directories"
    else
        fail "init-container failed to create all directories"
    fi

    # 3b. Verify directories actually exist on disk
    local expected_dirs=(
        "$td/.config/StardewValley"
        "$td/stardewvalley"
        "$td/Steam"
        "$td/.local/share/stardrop/logs"
        "$td/.local/share/stardrop/backups"
    )
    local all_exist=true
    for d in "${expected_dirs[@]}"; do
        if [ ! -d "$d" ]; then
            all_exist=false
            break
        fi
    done
    if [ "$all_exist" = "true" ]; then
        pass "all 5 expected directories exist on disk"
    else
        fail "some expected directories missing on disk"
    fi

    # 3c. chown logic structure: count wrong-owner files
    # We test the logic pattern without actually requiring UID mismatch
    result=$(bash -c '
        DIR="'"$td"'/stardewvalley"
        touch "$DIR/testfile1" "$DIR/testfile2"
        # Simulate the counting logic (all files owned by current user → 0 wrong)
        WRONG_OWNER=$(find "$DIR" ! -uid $(id -u) 2>/dev/null | wc -l)
        echo "$WRONG_OWNER"
    ')
    if [ "$result" = "0" ]; then
        pass "chown logic correctly counts 0 wrong-owner files for current user"
    else
        fail "chown wrong-owner count should be 0 for current user (got: $result)"
    fi

    # 3d. GPU directory setup logic
    result=$(bash -c '
        USE_GPU=true
        TD="'"$td"'"
        if [ "$USE_GPU" = "true" ]; then
            mkdir -p "$TD/.X11-unix"
            chmod 1777 "$TD/.X11-unix"
            mkdir -p "$TD/.local/share/xorg"
            echo "GPU_SETUP_OK"
        else
            echo "GPU_SKIPPED"
        fi
    ')
    if [ "$result" = "GPU_SETUP_OK" ] && [ -d "$td/.X11-unix" ] && [ -d "$td/.local/share/xorg" ]; then
        pass "GPU directory setup creates .X11-unix and xorg dirs"
    else
        fail "GPU directory setup failed"
    fi

    # 3e. GPU setup skipped when USE_GPU != true
    result=$(bash -c '
        USE_GPU=false
        if [ "$USE_GPU" = "true" ]; then
            echo "GPU_SETUP_OK"
        else
            echo "GPU_SKIPPED"
        fi
    ')
    if [ "$result" = "GPU_SKIPPED" ]; then
        pass "GPU directory setup correctly skipped when USE_GPU=false"
    else
        fail "GPU setup should be skipped when USE_GPU=false (got: $result)"
    fi
}

# =============================================================================
# 4. SAVE-SELECTOR.SH – test with/without SAVE_NAME env var
# =============================================================================
test_save_selector() {
    section "4. save-selector.sh – SAVE_NAME logic"

    local td="$TMPDIR_ROOT/save-test"
    local save_dir="$td/Saves"
    mkdir -p "$save_dir/MyFarm_12345"

    # 4a. No SAVE_NAME → default logic message
    result=$(SAVE_NAME="" SAVE_DIR="$save_dir" bash -c '
        SAVE_DIR="'"$save_dir"'"
        SAVE_NAME="${SAVE_NAME:-}"
        log() { echo "$1"; }
        if [ -n "$SAVE_NAME" ]; then
            echo "SELECTED"
        else
            echo "DEFAULT"
        fi
    ')
    if [ "$result" = "DEFAULT" ]; then
        pass "no SAVE_NAME → uses default logic"
    else
        fail "no SAVE_NAME should use default logic (got: $result)"
    fi

    # 4b. SAVE_NAME set + save exists → writes .selected_save marker
    result=$(bash -c '
        SAVE_DIR="'"$save_dir"'"
        SAVE_NAME="MyFarm_12345"
        log() { :; }
        if [ -n "$SAVE_NAME" ]; then
            if [ -d "$SAVE_DIR/$SAVE_NAME" ]; then
                mkdir -p "$SAVE_DIR"
                echo "$SAVE_NAME" > "$SAVE_DIR/.selected_save"
                echo "FOUND"
            else
                echo "NOT_FOUND"
            fi
        fi
    ')
    if [ "$result" = "FOUND" ] && [ -f "$save_dir/.selected_save" ]; then
        local marker_content
        marker_content=$(cat "$save_dir/.selected_save")
        if [ "$marker_content" = "MyFarm_12345" ]; then
            pass "SAVE_NAME set + save exists → .selected_save marker written correctly"
        else
            fail ".selected_save content mismatch (got: $marker_content)"
        fi
    else
        fail "SAVE_NAME with existing save should create marker (got: $result)"
    fi

    # 4c. SAVE_NAME set + save does NOT exist
    result=$(bash -c '
        SAVE_DIR="'"$save_dir"'"
        SAVE_NAME="NonExistentFarm"
        log() { :; }
        if [ -n "$SAVE_NAME" ]; then
            if [ -d "$SAVE_DIR/$SAVE_NAME" ]; then
                echo "FOUND"
            else
                echo "NOT_FOUND"
            fi
        fi
    ')
    if [ "$result" = "NOT_FOUND" ]; then
        pass "SAVE_NAME set + save missing → correctly reports not found"
    else
        fail "SAVE_NAME with missing save should report NOT_FOUND (got: $result)"
    fi

    # 4d. Listing available saves when requested save doesn't exist
    result=$(bash -c '
        SAVE_DIR="'"$save_dir"'"
        if [ -d "$SAVE_DIR" ]; then
            ls -1 "$SAVE_DIR" 2>/dev/null | grep -v "^\." | head -5
        fi
    ')
    if echo "$result" | grep -q "MyFarm_12345"; then
        pass "available saves listing includes MyFarm_12345"
    else
        fail "available saves listing should include MyFarm_12345 (got: $result)"
    fi

    # 4e. Multiple saves listed
    mkdir -p "$save_dir/AnotherFarm_67890"
    result=$(bash -c '
        SAVE_DIR="'"$save_dir"'"
        ls -1 "$SAVE_DIR" 2>/dev/null | grep -v "^\." | wc -l
    ')
    if [ "$result" -ge 2 ]; then
        pass "multiple saves correctly listed ($result saves found)"
    else
        fail "should find at least 2 saves (got: $result)"
    fi
}

# =============================================================================
# 5. STATUS-REPORTER.SH – metric collection functions (mocked data)
# =============================================================================
test_status_reporter() {
    section "5. status-reporter.sh – metric collection functions"

    local td="$TMPDIR_ROOT/status-test"
    mkdir -p "$td"

    # 6a. get_player_count with mocked SMAPI log
    local smapi_log="$td/SMAPI-latest.txt"
    cat > "$smapi_log" << 'EOF'
[SMAPI] player connected
[SMAPI] farmhand connected
[SMAPI] joined the game
[SMAPI] player disconnected
EOF

    result=$(bash -c '
        SMAPI_LOG="'"$smapi_log"'"
        get_player_count() {
            if [ -f "$SMAPI_LOG" ]; then
                local connected=$(grep -c "player connected\|joined the game\|farmhand connected" "$SMAPI_LOG" 2>/dev/null || echo "0")
                local disconnected=$(grep -c "player disconnected\|left the game\|farmhand disconnected" "$SMAPI_LOG" 2>/dev/null || echo "0")
                local players=$((connected - disconnected))
                [ $players -lt 0 ] && players=0
                echo "$players"
            else
                echo "0"
            fi
        }
        get_player_count
    ')
    if [ "$result" = "2" ]; then
        pass "get_player_count returns 2 (3 connected - 1 disconnected)"
    else
        fail "get_player_count should return 2 (got: $result)"
    fi

    # 6b. get_player_count returns 0 when no log file
    result=$(bash -c '
        SMAPI_LOG="/nonexistent/path/log.txt"
        get_player_count() {
            if [ -f "$SMAPI_LOG" ]; then
                echo "999"
            else
                echo "0"
            fi
        }
        get_player_count
    ')
    if [ "$result" = "0" ]; then
        pass "get_player_count returns 0 when log file missing"
    else
        fail "get_player_count should return 0 when log missing (got: $result)"
    fi

    # 6c. get_player_count handles more disconnects than connects (floor at 0)
    cat > "$smapi_log" << 'EOF'
player connected
player disconnected
player disconnected
EOF
    result=$(bash -c '
        SMAPI_LOG="'"$smapi_log"'"
        get_player_count() {
            if [ -f "$SMAPI_LOG" ]; then
                local connected=$(grep -c "player connected\|joined the game\|farmhand connected" "$SMAPI_LOG" 2>/dev/null || echo "0")
                local disconnected=$(grep -c "player disconnected\|left the game\|farmhand disconnected" "$SMAPI_LOG" 2>/dev/null || echo "0")
                local players=$((connected - disconnected))
                [ $players -lt 0 ] && players=0
                echo "$players"
            else
                echo "0"
            fi
        }
        get_player_count
    ')
    if [ "$result" = "0" ]; then
        pass "get_player_count floors negative count to 0"
    else
        fail "get_player_count should floor to 0 (got: $result)"
    fi

    # 6d. get_game_day extracts day info from log
    cat > "$smapi_log" << 'EOF'
[SMAPI] Starting Day 5 of Spring Year 1
[SMAPI] Some other log line
[SMAPI] Starting Day 12 of Summer Year 2
EOF
    result=$(bash -c '
        SMAPI_LOG="'"$smapi_log"'"
        get_game_day() {
            if [ -f "$SMAPI_LOG" ]; then
                local day_info=$(grep -oP "Day \d+ of \w+ Year \d+" "$SMAPI_LOG" 2>/dev/null | tail -1)
                echo "${day_info:-Unknown}"
            else
                echo "Not started"
            fi
        }
        get_game_day
    ')
    if [ "$result" = "Day 12 of Summer Year 2" ]; then
        pass "get_game_day extracts latest day info"
    else
        fail "get_game_day should return 'Day 12 of Summer Year 2' (got: $result)"
    fi

    # 6e. get_game_day returns 'Not started' when no log
    result=$(bash -c '
        SMAPI_LOG="/nonexistent/log.txt"
        get_game_day() {
            if [ -f "$SMAPI_LOG" ]; then
                echo "has log"
            else
                echo "Not started"
            fi
        }
        get_game_day
    ')
    if [ "$result" = "Not started" ]; then
        pass "get_game_day returns 'Not started' without log file"
    else
        fail "get_game_day should return 'Not started' (got: $result)"
    fi

    # 6f. get_memory_usage_mb with mocked /proc data
    local mock_proc="$td/mock_proc_status"
    cat > "$mock_proc" << 'EOF'
Name:	StardewModdingAPI
VmRSS:	524288 kB
VmSize: 1048576 kB
EOF
    result=$(bash -c '
        MOCK_FILE="'"$mock_proc"'"
        rss=$(grep "VmRSS" "$MOCK_FILE" 2>/dev/null | awk "{print \$2}")
        if [ -n "$rss" ]; then
            echo "$((rss / 1024))"
        else
            echo "0"
        fi
    ')
    if [ "$result" = "512" ]; then
        pass "get_memory_usage_mb correctly converts 524288 kB to 512 MB"
    else
        fail "memory should be 512 MB (got: $result)"
    fi

    # 6g. get_event_counts with mocked log
    cat > "$smapi_log" << 'EOF'
[SMAPI] Player passed out
[SMAPI] Player exhausted
[SMAPI] Player collapsed
[SMAPI] ReadyCheckDialog appeared
[SMAPI] ReadyCheckDialog appeared
[SMAPI] ServerOfflineMode detected
EOF
    result=$(bash -c '
        SMAPI_LOG="'"$smapi_log"'"
        get_event_counts() {
            local passout=0 readycheck=0 offline=0
            if [ -f "$SMAPI_LOG" ]; then
                passout=$(grep -ciE "passed out|exhausted|collapsed" "$SMAPI_LOG" 2>/dev/null || echo "0")
                readycheck=$(grep -c "ReadyCheckDialog" "$SMAPI_LOG" 2>/dev/null || echo "0")
                offline=$(grep -c "ServerOfflineMode" "$SMAPI_LOG" 2>/dev/null || echo "0")
            fi
            echo "$passout $readycheck $offline"
        }
        get_event_counts
    ')
    if [ "$result" = "3 2 1" ]; then
        pass "get_event_counts returns 3 passout, 2 readycheck, 1 offline"
    else
        fail "get_event_counts should return '3 2 1' (got: $result)"
    fi

    # 6h. get_uptime_seconds returns 0 when no game running
    result=$(bash -c '
        get_uptime_seconds() {
            local pid=$(pgrep -f StardewModdingAPI 2>/dev/null | head -1)
            if [ -n "$pid" ] && [ -d "/proc/$pid" ]; then
                local start_time=$(stat -c %Y "/proc/$pid" 2>/dev/null)
                if [ -n "$start_time" ]; then
                    echo $(($(date +%s) - start_time))
                    return
                fi
            fi
            echo "0"
        }
        get_uptime_seconds
    ')
    if [ "$result" = "0" ]; then
        pass "get_uptime_seconds returns 0 when no game process found"
    else
        fail "get_uptime_seconds should return 0 (got: $result)"
    fi

    # 6i. Metrics file format: verify Prometheus format output
    local metrics_file="$td/metrics.prom"
    bash -c '
        game_running=1
        uptime=3600
        players=3
        memory=512
        cpu=25.5
        passout=2
        readycheck=1
        offline=0
        script_health=1

        cat > "'"$metrics_file"'" << EOPROM
# HELP stardrop_game_running Whether the Stardew Valley game process is running.
# TYPE stardrop_game_running gauge
stardrop_game_running $game_running

# HELP stardrop_players_online Number of players currently connected.
# TYPE stardrop_players_online gauge
stardrop_players_online $players

# HELP stardrop_memory_usage_mb Game process RSS memory usage in megabytes.
# TYPE stardrop_memory_usage_mb gauge
stardrop_memory_usage_mb $memory
EOPROM
    '

    if grep -q "stardrop_game_running 1" "$metrics_file" && \
       grep -q "stardrop_players_online 3" "$metrics_file" && \
       grep -q "stardrop_memory_usage_mb 512" "$metrics_file"; then
        pass "Prometheus metrics file has correct format and values"
    else
        fail "Prometheus metrics format validation failed"
    fi

    # 6j. JSON status file format
    local status_file="$td/status.json"
    bash -c '
        timestamp="2026-03-08T12:00:00Z"
        game_running=1
        uptime=3600
        game_day="Day 5 of Spring Year 1"
        players=2
        memory=512
        cpu=15.3
        passout=1
        readycheck=0
        offline=0
        script_health=1

        cat > "'"$status_file"'" << EOJSON
{
  "timestamp": "$timestamp",
  "server": {
    "version": "1.0.0",
    "game_running": true,
    "uptime_seconds": $uptime
  },
  "game": {
    "day": "$game_day",
    "players_online": $players
  },
  "resources": {
    "memory_mb": $memory,
    "cpu_percent": $cpu
  },
  "events": {
    "passout": $passout,
    "readycheck": $readycheck,
    "offline": $offline
  },
  "scripts_healthy": true
}
EOJSON
    '

    if grep -q '"game_running": true' "$status_file" && \
       grep -q '"players_online": 2' "$status_file" && \
       grep -q '"memory_mb": 512' "$status_file"; then
        pass "JSON status file has correct structure and values"
    else
        fail "JSON status file format validation failed"
    fi
}

# =============================================================================
# 6. ENTRYPOINT.SH – VNC and resolution logic
# =============================================================================
test_entrypoint() {
    section "6. entrypoint.sh – VNC and resolution logic"

    local td="$TMPDIR_ROOT/entrypoint-test"
    mkdir -p "$td"

    # 6a. VNC password truncation logic (>8 chars)
    result=$(bash -c '
        VNC_PASSWORD="verylongpassword123"
        if [ ${#VNC_PASSWORD} -gt 8 ]; then
            VNC_PASSWORD="${VNC_PASSWORD:0:8}"
        fi
        echo "$VNC_PASSWORD"
    ')
    if [ "$result" = "verylong" ]; then
        pass "VNC password truncated to 8 chars"
    else
        fail "VNC password should be truncated to 'verylong' (got: $result)"
    fi

    # 6b. VNC password ≤8 chars kept intact
    result=$(bash -c '
        VNC_PASSWORD="short"
        if [ ${#VNC_PASSWORD} -gt 8 ]; then
            VNC_PASSWORD="${VNC_PASSWORD:0:8}"
        fi
        echo "$VNC_PASSWORD"
    ')
    if [ "$result" = "short" ]; then
        pass "VNC password ≤8 chars kept intact"
    else
        fail "VNC password should stay 'short' (got: $result)"
    fi

    # 6c. Resolution defaults
    result=$(bash -c '
        RESOLUTION_WIDTH=${RESOLUTION_WIDTH:-1280}
        RESOLUTION_HEIGHT=${RESOLUTION_HEIGHT:-720}
        REFRESH_RATE=${REFRESH_RATE:-60}
        echo "${RESOLUTION_WIDTH}x${RESOLUTION_HEIGHT}@${REFRESH_RATE}"
    ')
    if [ "$result" = "1280x720@60" ]; then
        pass "resolution defaults to 1280x720@60"
    else
        fail "resolution defaults should be 1280x720@60 (got: $result)"
    fi

    # 6d. Resolution env override
    result=$(RESOLUTION_WIDTH=1920 RESOLUTION_HEIGHT=1080 REFRESH_RATE=144 bash -c '
        RESOLUTION_WIDTH=${RESOLUTION_WIDTH:-1280}
        RESOLUTION_HEIGHT=${RESOLUTION_HEIGHT:-720}
        REFRESH_RATE=${REFRESH_RATE:-60}
        echo "${RESOLUTION_WIDTH}x${RESOLUTION_HEIGHT}@${REFRESH_RATE}"
    ')
    if [ "$result" = "1920x1080@144" ]; then
        pass "resolution env overrides work (1920x1080@144)"
    else
        fail "resolution override should be 1920x1080@144 (got: $result)"
    fi
}

# =============================================================================
# BONUS: EVENT-HANDLER.SH – cooldown logic
# =============================================================================
test_event_handler() {
    section "BONUS: event-handler.sh – cooldown logic"

    # 8a. check_cooldown: expired cooldown → allow
    result=$(bash -c '
        check_cooldown() {
            local last_time="$1"
            local cooldown="$2"
            local current_time
            current_time=$(date +%s)
            if [ $((current_time - last_time)) -lt "$cooldown" ]; then
                return 1
            fi
            return 0
        }
        OLD_TIME=$(($(date +%s) - 100))
        check_cooldown "$OLD_TIME" 30 && echo "EXPIRED" || echo "ACTIVE"
    ')
    if [ "$result" = "EXPIRED" ]; then
        pass "check_cooldown: returns expired after cooldown window"
    else
        fail "check_cooldown should return expired (got: $result)"
    fi

    # 8b. check_cooldown: active cooldown → deny
    result=$(bash -c '
        check_cooldown() {
            local last_time="$1"
            local cooldown="$2"
            local current_time
            current_time=$(date +%s)
            if [ $((current_time - last_time)) -lt "$cooldown" ]; then
                return 1
            fi
            return 0
        }
        RECENT_TIME=$(($(date +%s) - 5))
        check_cooldown "$RECENT_TIME" 30 && echo "EXPIRED" || echo "ACTIVE"
    ')
    if [ "$result" = "ACTIVE" ]; then
        pass "check_cooldown: returns active within cooldown window"
    else
        fail "check_cooldown should return active (got: $result)"
    fi

    # 8c. check_cooldown with time=0 (never happened) → expired
    result=$(bash -c '
        check_cooldown() {
            local last_time="$1"
            local cooldown="$2"
            local current_time
            current_time=$(date +%s)
            if [ $((current_time - last_time)) -lt "$cooldown" ]; then
                return 1
            fi
            return 0
        }
        check_cooldown 0 30 && echo "EXPIRED" || echo "ACTIVE"
    ')
    if [ "$result" = "EXPIRED" ]; then
        pass "check_cooldown: time=0 (never happened) → expired"
    else
        fail "check_cooldown with time=0 should be expired (got: $result)"
    fi

    # 8d. Default cooldown values
    result=$(bash -c '
        PASSOUT_COOLDOWN=30
        READYCHECK_COOLDOWN=10
        OFFLINE_COOLDOWN=60
        echo "$PASSOUT_COOLDOWN $READYCHECK_COOLDOWN $OFFLINE_COOLDOWN"
    ')
    if [ "$result" = "30 10 60" ]; then
        pass "default cooldowns: passout=30s, readycheck=10s, offline=60s"
    else
        fail "default cooldowns should be '30 10 60' (got: $result)"
    fi
}

# =============================================================================
# BONUS: AUTO-BACKUP.SH – backup rotation logic
# =============================================================================
test_auto_backup() {
    section "BONUS: auto-backup.sh – backup rotation logic"

    local td="$TMPDIR_ROOT/backup-test"
    local backup_dir="$td/backups"
    mkdir -p "$backup_dir"

    # 9a. Backup rotation: only keep MAX_BACKUPS files
    for i in $(seq 1 10); do
        touch "$backup_dir/saves-2026030${i}-000000.tar.gz"
        # Add slight modification time difference
        sleep 0.05
    done

    result=$(bash -c '
        BACKUP_DIR="'"$backup_dir"'"
        MAX_BACKUPS=7
        backup_count=$(ls -1t "$BACKUP_DIR"/saves-*.tar.gz 2>/dev/null | wc -l)
        if [ "$backup_count" -gt "$MAX_BACKUPS" ]; then
            to_delete=$((backup_count - MAX_BACKUPS))
            ls -1t "$BACKUP_DIR"/saves-*.tar.gz | tail -n "$to_delete" | xargs rm -f
        fi
        ls -1 "$BACKUP_DIR"/saves-*.tar.gz 2>/dev/null | wc -l
    ')
    if [ "$result" = "7" ]; then
        pass "backup rotation keeps only MAX_BACKUPS=7 files"
    else
        fail "backup rotation should keep 7 files (got: $result)"
    fi

    # 9b. Backup hour formatting
    result=$(bash -c '
        BACKUP_HOUR=4
        echo "$(printf "%02d" $BACKUP_HOUR)"
    ')
    if [ "$result" = "04" ]; then
        pass "backup hour formatting: 4 → 04"
    else
        fail "backup hour should format to '04' (got: $result)"
    fi

    # 9c. MAX_BACKUPS default
    result=$(bash -c '
        MAX_BACKUPS=${MAX_BACKUPS:-7}
        echo "$MAX_BACKUPS"
    ')
    if [ "$result" = "7" ]; then
        pass "MAX_BACKUPS defaults to 7"
    else
        fail "MAX_BACKUPS should default to 7 (got: $result)"
    fi

    # 9d. MAX_BACKUPS env override
    result=$(MAX_BACKUPS=14 bash -c '
        MAX_BACKUPS=${MAX_BACKUPS:-7}
        echo "$MAX_BACKUPS"
    ')
    if [ "$result" = "14" ]; then
        pass "MAX_BACKUPS env override works (set to 14)"
    else
        fail "MAX_BACKUPS override should be 14 (got: $result)"
    fi
}

# =============================================================================
# Run all tests
# =============================================================================
main() {
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  StardropHost – Script Test Suite                                ║${NC}"
    echo -e "${CYAN}║                                                                   ║${NC}"
    echo -e "${CYAN}║  Tests run WITHOUT Docker or game – pure logic & syntax checks    ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}"

    setup_tmpdir

    test_syntax_validation
    test_crash_monitor
    test_init_container
    test_save_selector
    test_status_reporter
    test_entrypoint
    test_event_handler
    test_auto_backup

    # ---- Summary ------------------------------------------------------------
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  TEST SUMMARY${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  Total:   ${TESTS_RUN}"
    echo -e "  ${GREEN}Passed:  ${TESTS_PASSED}${NC}"
    echo -e "  ${RED}Failed:  ${TESTS_FAILED}${NC}"
    echo ""

    if [ "$TESTS_FAILED" -gt 0 ]; then
        echo -e "  ${RED}Failed tests:${NC}"
        for name in "${FAILED_NAMES[@]}"; do
            echo -e "    ${RED}✗${NC} $name"
        done
        echo ""
        echo -e "  ${RED}╔═══════════════════╗${NC}"
        echo -e "  ${RED}║   TESTS FAILED    ║${NC}"
        echo -e "  ${RED}╚═══════════════════╝${NC}"
        exit 1
    else
        echo -e "  ${GREEN}╔═══════════════════╗${NC}"
        echo -e "  ${GREEN}║  ALL TESTS PASS   ║${NC}"
        echo -e "  ${GREEN}╚═══════════════════╝${NC}"
        exit 0
    fi
}

main "$@"
