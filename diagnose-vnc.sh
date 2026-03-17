#!/bin/bash
# ===========================================
# StardropHost | diagnose-vnc.sh
# ===========================================
# Diagnoses VNC connection issues.
# Usage: ./diagnose-vnc.sh
# ===========================================

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
echo -e "${CYAN}${BOLD}  🌟 StardropHost - VNC Diagnostics${NC}"
echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# -- 1. Container status --
echo -e "${BOLD}[1/8] Checking container status...${NC}"
if ! docker ps | grep -q stardrop; then
    print_error "Container is not running"
    echo ""
    echo -e "  Start it: ${CYAN}docker compose up -d${NC}"
    exit 1
fi
print_success "Container is running"
echo ""

# -- 2. VNC environment variable --
echo -e "${BOLD}[2/8] Checking VNC setting...${NC}"
VNC_ENABLED=$(docker exec stardrop env | grep ENABLE_VNC)
echo "  $VNC_ENABLED"
if echo "$VNC_ENABLED" | grep -q "true"; then
    print_success "VNC is enabled"
else
    print_warning "VNC is not enabled"
    echo -e "  Enable via web UI or set ${CYAN}ENABLE_VNC=true${NC} in .env"
fi
echo ""

# -- 3. Xvfb process --
echo -e "${BOLD}[3/8] Checking Xvfb (virtual display)...${NC}"
if docker exec stardrop ps aux | grep -i xvfb | grep -v grep; then
    print_success "Xvfb is running"
else
    print_error "Xvfb is not running"
fi
echo ""

# -- 4. x11vnc process --
echo -e "${BOLD}[4/8] Checking x11vnc process...${NC}"
if docker exec stardrop ps aux | grep -i x11vnc | grep -v grep; then
    print_success "x11vnc is running"
else
    print_error "x11vnc is not running"
    echo ""
    echo "  Possible reasons:"
    echo "    1. VNC not enabled (toggle via web UI)"
    echo "    2. x11vnc failed to start"
    echo "    3. Xvfb not ready when x11vnc started"
fi
echo ""

# -- 5. Port 5900 listening --
echo -e "${BOLD}[5/8] Checking port 5900 inside container...${NC}"
if docker exec stardrop netstat -tuln 2>/dev/null | grep 5900; then
    print_success "Port 5900 is listening"
else
    print_error "Port 5900 is not listening"
fi
echo ""

# -- 6. Host port mapping --
echo -e "${BOLD}[6/8] Checking host port mapping...${NC}"
if docker port stardrop 5900 2>/dev/null; then
    print_success "Port 5900 is mapped"
else
    print_error "Port 5900 is not mapped"
    echo -e "  Check your ${CYAN}docker-compose.yml${NC} port bindings"
fi
echo ""

# -- 7. Firewall --
echo -e "${BOLD}[7/8] Checking firewall...${NC}"
if command -v ufw >/dev/null 2>&1; then
    if ufw status | grep 5900; then
        print_success "Firewall rule exists for port 5900"
    else
        print_warning "No firewall rule found for port 5900"
        echo -e "  Add with: ${CYAN}sudo ufw allow 5900/tcp${NC}"
    fi
else
    print_info "ufw not found, skipping firewall check"
fi
echo ""

# -- 8. Container logs --
echo -e "${BOLD}[8/8] Recent VNC log entries...${NC}"
docker logs stardrop 2>&1 | grep -i vnc | tail -5
echo ""

echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  Useful Commands${NC}"
echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  Manually start VNC in container:"
echo -e "    ${CYAN}docker exec stardrop x11vnc -display :99 -forever -shared -rfbport 5900${NC}"
echo ""
echo "  Test VNC connection from host:"
echo -e "    ${CYAN}nc -zv localhost 5900${NC}"
echo ""
echo "  View full container logs:"
echo -e "    ${CYAN}docker logs stardrop${NC}"
echo ""