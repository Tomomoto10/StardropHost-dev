#!/bin/bash
# ===========================================
# StardropHost | quick-start.sh
# ===========================================
# Fully automated setup — installs Docker if
# needed, downloads StardropHost, and launches
# the server. Just run this script and open
# the web panel when it's done.
#
# curl -fsSL https://raw.githubusercontent.com/Tomomoto10/StardropHost/main/quick-start.sh | bash
#
# Supports: Ubuntu, Debian, Raspberry Pi OS,
#           CentOS, RHEL, Fedora, Amazon Linux
# ===========================================

set +e

# -- Colors --
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

print_header() {
    echo ""
    echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}${BOLD}  🌟 StardropHost — Automated Setup${NC}"
    echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_error()   { echo -e "${RED}❌ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_info()    { echo -e "${BLUE}ℹ️  $1${NC}"; }
print_step()    { echo ""; echo -e "${BOLD}$1${NC}"; }

COMPOSE_CMD=""

# ===========================================
# Root check
# ===========================================
if [ "$(id -u)" != "0" ]; then
    # Re-run with sudo automatically
    if command -v sudo &>/dev/null; then
        print_info "Re-running with sudo for installation permissions..."
        exec sudo bash "$0" "$@"
    else
        print_error "This script must be run as root or with sudo."
        exit 1
    fi
fi

# Detect who actually invoked the script (for group membership)
REAL_USER="${SUDO_USER:-${USER:-root}}"

# ===========================================
# OS Detection
# ===========================================
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="$ID"
        OS_LIKE="${ID_LIKE:-}"
        OS_NAME="${PRETTY_NAME:-$ID}"
    else
        OS_ID="unknown"
        OS_LIKE=""
        OS_NAME="Unknown"
    fi
}

is_debian_based() {
    echo "$OS_ID $OS_LIKE" | grep -qiE "debian|ubuntu|raspbian|linuxmint|pop"
}

is_rhel_based() {
    echo "$OS_ID $OS_LIKE" | grep -qiE "rhel|centos|fedora|amzn|rocky|almalinux"
}

# ===========================================
# Step 1 — Install Docker
# ===========================================
install_docker() {
    print_step "Step 1: Installing Docker..."
    detect_os
    print_info "OS: $OS_NAME"

    if is_debian_based; then
        print_info "Using apt + official Docker repository..."

        apt-get update -qq
        apt-get install -y -qq \
            ca-certificates curl gnupg lsb-release apt-transport-https

        # Add Docker's official GPG key
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/${OS_ID}/gpg \
            | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null
        chmod a+r /etc/apt/keyrings/docker.gpg

        # Add the repository
        echo \
            "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
            https://download.docker.com/linux/${OS_ID} \
            $(lsb_release -cs 2>/dev/null || . /etc/os-release && echo "$VERSION_CODENAME") stable" \
            > /etc/apt/sources.list.d/docker.list

        apt-get update -qq
        apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin

    elif is_rhel_based && command -v dnf &>/dev/null; then
        print_info "Using dnf + official Docker repository..."

        dnf -y install dnf-plugins-core
        dnf config-manager --add-repo \
            https://download.docker.com/linux/centos/docker-ce.repo 2>/dev/null \
            || dnf config-manager --add-repo \
            https://download.docker.com/linux/fedora/docker-ce.repo
        dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    elif is_rhel_based && command -v yum &>/dev/null; then
        print_info "Using yum + official Docker repository..."

        yum install -y yum-utils
        yum-config-manager --add-repo \
            https://download.docker.com/linux/centos/docker-ce.repo
        yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    else
        # Universal fallback — get.docker.com covers most Linux distros
        print_info "Using get.docker.com universal install script..."
        curl -fsSL https://get.docker.com | sh

        # Also try to install Compose plugin separately if needed
        if ! docker compose version &>/dev/null 2>&1; then
            if command -v apt-get &>/dev/null; then
                apt-get install -y -qq docker-compose-plugin 2>/dev/null || true
            fi
        fi
    fi

    # Verify Docker installed
    if ! command -v docker &>/dev/null; then
        print_error "Docker installation failed!"
        echo ""
        echo "Please install Docker manually: https://docs.docker.com/get-docker/"
        exit 1
    fi

    print_success "Docker installed!"
}

# ===========================================
# Step 1 — Check or install Docker
# ===========================================
check_docker() {
    print_step "Step 1: Checking Docker..."

    if ! command -v docker &>/dev/null; then
        install_docker
    else
        DOCKER_VER=$(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',')
        print_info "Docker already installed: v${DOCKER_VER}"
    fi

    # Start daemon if not running
    if ! docker ps &>/dev/null 2>&1; then
        print_info "Starting Docker daemon..."
        if command -v systemctl &>/dev/null; then
            systemctl enable docker 2>/dev/null
            systemctl start docker 2>/dev/null
        elif command -v service &>/dev/null; then
            service docker start 2>/dev/null
        fi
        sleep 4

        if ! docker ps &>/dev/null 2>&1; then
            print_error "Docker daemon failed to start!"
            echo ""
            echo "Try: sudo systemctl start docker"
            exit 1
        fi
    fi

    # Resolve Compose command
    if docker compose version &>/dev/null 2>&1; then
        COMPOSE_CMD="docker compose"
        COMPOSE_VER=$(docker compose version --short 2>/dev/null)
        print_success "Docker is ready (Compose v${COMPOSE_VER})"
    elif command -v docker-compose &>/dev/null; then
        COMPOSE_CMD="docker-compose"
        print_success "Docker is ready (Compose v1 — consider upgrading)"
    else
        print_error "Docker Compose not found even after installation!"
        echo ""
        echo "Try: sudo apt-get install -y docker-compose-plugin"
        exit 1
    fi

    # Add real user to docker group so they don't need sudo next time
    if [ "$REAL_USER" != "root" ] && id "$REAL_USER" &>/dev/null; then
        usermod -aG docker "$REAL_USER" 2>/dev/null || true
    fi
}

# ===========================================
# Step 2 — Download StardropHost
# ===========================================
download_files() {
    print_step "Step 2: Downloading StardropHost..."

    INSTALL_DIR="$HOME/stardrophost"

    # If already installed, just update
    if [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
        print_success "StardropHost already downloaded at $INSTALL_DIR"
        cd "$INSTALL_DIR"
        return
    fi

    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"

    BASE_URL="https://raw.githubusercontent.com/Tomomoto10/StardropHost/main"

    if command -v git &>/dev/null; then
        print_info "Cloning repository..."
        git clone https://github.com/Tomomoto10/StardropHost.git . 2>/dev/null \
            || { print_error "Git clone failed"; exit 1; }
    elif command -v curl &>/dev/null; then
        print_info "Downloading files via curl..."
        curl -fsSL "$BASE_URL/docker-compose.yml" -o docker-compose.yml \
            || { print_error "Failed to download docker-compose.yml"; exit 1; }
        curl -fsSL "$BASE_URL/.env" -o .env 2>/dev/null || true
    elif command -v wget &>/dev/null; then
        print_info "Downloading files via wget..."
        wget -q "$BASE_URL/docker-compose.yml" -O docker-compose.yml \
            || { print_error "Failed to download docker-compose.yml"; exit 1; }
        wget -q "$BASE_URL/.env" -O .env 2>/dev/null || true
    else
        # Install curl and retry
        print_info "No download tool found — installing curl..."
        if command -v apt-get &>/dev/null; then
            apt-get install -y -qq curl
        elif command -v yum &>/dev/null; then
            yum install -y curl
        elif command -v dnf &>/dev/null; then
            dnf install -y curl
        fi
        curl -fsSL "$BASE_URL/docker-compose.yml" -o docker-compose.yml \
            || { print_error "Failed to download docker-compose.yml"; exit 1; }
        curl -fsSL "$BASE_URL/.env" -o .env 2>/dev/null || true
    fi

    # Create .env if it doesn't exist
    if [ ! -f .env ]; then
        touch .env
    fi

    print_success "StardropHost downloaded to $INSTALL_DIR"
}

# ===========================================
# Step 3 — Set up data directories
# ===========================================
setup_directories() {
    print_step "Step 3: Setting up data directories..."

    mkdir -p data/{saves,game,logs,backups,custom-mods,panel}

    # Fix permissions for UID 1000 (the steam user inside the container)
    chown -R 1000:1000 data/ 2>/dev/null || true

    # Verify
    OWNER=$(stat -c '%u' data/game 2>/dev/null || stat -f '%u' data/game 2>/dev/null)
    if [ "$OWNER" != "1000" ]; then
        print_warning "Could not set permissions automatically."
        print_info "If you see 'Disk write failure' errors, run:"
        echo -e "  ${CYAN}sudo chown -R 1000:1000 data/${NC}"
    else
        print_success "Data directories ready!"
    fi

    # Fix ownership of the install directory itself for the real user
    if [ "$REAL_USER" != "root" ] && id "$REAL_USER" &>/dev/null; then
        chown -R "$REAL_USER":"$REAL_USER" . 2>/dev/null || true
        # But keep data/ at 1000:1000 for the container
        chown -R 1000:1000 data/ 2>/dev/null || true
    fi
}

# ===========================================
# Step 4 — Start server
# ===========================================
start_server() {
    print_step "Step 4: Starting StardropHost..."

    print_info "Pulling Docker images (this may take a few minutes on first run)..."
    $COMPOSE_CMD pull 2>&1 | grep -v "^$" | tail -5

    echo ""
    print_info "Starting containers..."
    $COMPOSE_CMD up -d

    # Wait for init container to complete
    print_info "Waiting for init container..."
    for i in $(seq 1 30); do
        STATUS=$(docker inspect --format='{{.State.Status}}' stardrop-init 2>/dev/null)
        EXIT=$(docker inspect --format='{{.State.ExitCode}}' stardrop-init 2>/dev/null)

        if [ "$STATUS" = "exited" ]; then
            if [ "$EXIT" = "0" ]; then
                print_success "Init complete!"
                break
            else
                print_warning "Init container exited with code $EXIT"
                print_info "Check: docker logs stardrop-init"
                break
            fi
        fi
        sleep 2
    done

    # Verify main container is running
    sleep 3
    if docker ps --format '{{.Names}}' | grep -q "^stardrop$"; then
        print_success "Server is running!"
    else
        print_warning "Container may still be starting — check logs if the web panel doesn't appear."
        print_info "  docker logs -f stardrop"
    fi
}

# ===========================================
# Done
# ===========================================
show_next_steps() {
    # Determine web panel URL
    SERVER_IP=""
    if command -v curl &>/dev/null; then
        SERVER_IP=$(curl -4 -s --max-time 5 ifconfig.me 2>/dev/null \
            || curl -4 -s --max-time 5 ip.sb 2>/dev/null || echo "")
    fi
    if [ -z "$SERVER_IP" ] && command -v hostname &>/dev/null; then
        SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    SERVER_IP="${SERVER_IP:-your-server-ip}"

    echo ""
    echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}${BOLD}  🌟 StardropHost is running!${NC}"
    echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  Open the web panel to finish setup:"
    echo ""
    echo -e "  ${CYAN}${BOLD}http://${SERVER_IP}:18642${NC}"
    echo ""
    echo -e "  The setup wizard will guide you through:"
    echo -e "    - Installing your game files"
    echo -e "    - Creating your admin password"
    echo -e "    - Configuring server resources"
    echo -e "    - Setting up Steam invite codes (optional)"
    echo ""
    echo -e "${BOLD}  Useful commands:${NC}"
    echo -e "    View logs:   ${CYAN}docker logs -f stardrop${NC}"
    echo -e "    Restart:     ${CYAN}$COMPOSE_CMD restart${NC}"
    echo -e "    Stop:        ${CYAN}$COMPOSE_CMD down${NC}"
    echo -e "    Directory:   ${CYAN}$(pwd)${NC}"
    echo ""
    echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# ===========================================
# Run
# ===========================================
main() {
    print_header
    check_docker
    download_files
    setup_directories
    start_server
    show_next_steps
}

main