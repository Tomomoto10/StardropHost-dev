#!/bin/bash
# ===========================================
# StardropHost | init.sh
# ===========================================
# Sets up data directories with correct
# permissions before first run.
#
# Note: This is a fallback CLI script.
# Normally this runs automatically via the
# stardrop-init container on startup.
#
# Only run this manually if you experience
# permission errors on first start.
# ===========================================

set -e

# -- Colors --
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# -- Output Helpers --
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_error()   { echo -e "${RED}❌ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_info()    { echo -e "${CYAN}ℹ️  $1${NC}"; }

echo ""
echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}${BOLD}  🌟 StardropHost - Initialisation${NC}"
echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# -- Check root --
if [ "$EUID" -eq 0 ]; then
    SUDO=""
    print_success "Running as root"
else
    SUDO="sudo"
    print_warning "Running as non-root, will use sudo for permission changes"
fi
echo ""

# -- Create directories --
print_info "Creating data directories..."

mkdir -p data/{saves,game,logs,backups,custom-mods,panel}

print_success "Directories created:"
echo "  data/saves"
echo "  data/game"
echo "  data/logs"
echo "  data/backups"
echo "  data/custom-mods"
echo "  data/panel"
echo ""

# -- Set permissions --
print_info "Setting permissions (UID 1000:1000)..."

$SUDO chown -R 1000:1000 data/

GAME_UID=$(stat -c '%u' data/game 2>/dev/null || stat -f '%u' data/game 2>/dev/null)
if [ "$GAME_UID" != "1000" ]; then
    print_error "Failed to set permissions!"
    echo ""
    echo "  This will cause disk write errors on first start."
    echo -e "  Try manually: ${CYAN}sudo chown -R 1000:1000 data/${NC}"
    echo ""
    exit 1
fi

print_success "Permissions set successfully"
echo ""

# -- Verify --
print_info "Directory listing:"
echo ""
ls -la data/
echo ""

echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}${BOLD}  🌟 Initialisation complete!${NC}"
echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  Next step:"
echo -e "    ${CYAN}docker compose up -d${NC}"
echo ""