#!/bin/bash
# ===========================================
# StardropHost | update.sh
# ===========================================
# Usage:
#   ./update.sh          # Update to latest
#   ./update.sh v1.0.0   # Update to specific version
# ===========================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

IMAGE="tomomotto/stardrophost"
CONTAINER="stardrop"
VERSION="${1:-latest}"

print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_error()   { echo -e "${RED}❌ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_info()    { echo -e "${BLUE}ℹ️  $1${NC}"; }
print_step()    { echo ""; echo -e "${BOLD}$1${NC}"; }

echo ""
echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}${BOLD}  🌟 StardropHost Updater${NC}"
echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# -- Step 1: Check current version --
print_step "Step 1: Checking current version..."

CURRENT_IMAGE=$(docker inspect --format='{{.Config.Image}}' "$CONTAINER" 2>/dev/null)
if [ -n "$CURRENT_IMAGE" ]; then
    print_info "  Current: $CURRENT_IMAGE"
else
    print_warning "  Container not found"
fi
print_info "  Target:  $IMAGE:$VERSION"

# -- Step 2: Backup saves --
print_step "Step 2: Backing up saves..."

mkdir -p backups

if [ -d "data/saves" ]; then
    BACKUP_FILE="backups/saves-pre-update-$(date +%Y%m%d-%H%M%S).tar.gz"
    if tar -czf "$BACKUP_FILE" data/saves/ 2>/dev/null; then
        print_success "Backup saved to: $BACKUP_FILE"
    else
        print_warning "Backup failed, continuing anyway"
    fi
else
    print_warning "No saves directory found, skipping backup"
fi

# -- Step 3: Stop server --
print_step "Step 3: Stopping server..."

if docker ps -q -f name="$CONTAINER" | grep -q .; then
    docker compose down 2>/dev/null || docker stop "$CONTAINER" 2>/dev/null
    print_success "Server stopped"
else
    print_info "Server not running, skipping"
fi

# -- Step 4: Pull new image --
print_step "Step 4: Pulling new image ($VERSION)..."

if ! docker pull "$IMAGE:$VERSION"; then
    print_error "Failed to pull image"
    print_error "Check your network connection and try again"
    exit 1
fi
print_success "Image pulled successfully"

# -- Step 5: Update image tag if specific version --
print_step "Step 5: Updating configuration..."

if [ "$VERSION" != "latest" ]; then
    if [ -f "docker-compose.yml" ]; then
        sed -i "s|image: ${IMAGE}:.*|image: ${IMAGE}:${VERSION}|" docker-compose.yml
        print_success "Updated image tag to $VERSION"
    fi
else
    print_info "Using latest tag, no changes needed"
fi

# -- Step 6: Start server --
print_step "Step 6: Starting server..."

if ! docker compose up -d 2>/dev/null; then
    print_error "Failed to start server"
    echo ""
    echo "Check logs: docker logs $CONTAINER"
    exit 1
fi
print_success "Server started"

sleep 2
INIT_EXIT=$(docker inspect --format='{{.State.ExitCode}}' stardrop-init 2>/dev/null)
if [ "$INIT_EXIT" != "0" ] && [ -n "$INIT_EXIT" ]; then
    print_warning "Init container exit code: $INIT_EXIT"
    print_warning "Check: docker logs stardrop-init"
fi

# -- Step 7: Verify --
print_step "Step 7: Verifying update..."

sleep 3
NEW_IMAGE=$(docker inspect --format='{{.Config.Image}}' "$CONTAINER" 2>/dev/null)
print_info "  Running: $NEW_IMAGE"

# -- Cleanup --
print_step "Cleaning up old images..."
docker image prune -f 2>/dev/null
print_success "Cleanup complete"

echo ""
echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}${BOLD}  🌟 Update complete!${NC}"
echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
print_info "View logs:  docker logs -f $CONTAINER"
print_info "Backup at:  $BACKUP_FILE"
echo ""