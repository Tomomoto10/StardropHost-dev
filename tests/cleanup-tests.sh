#!/bin/bash
# StardropHost | tests/cleanup-tests.sh
# Cleans up test containers and temporary data

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Cleaning up test containers and data...${NC}"

# Stop and remove any test containers
docker stop stardrop-steam-auth-test 2>/dev/null || true
docker rm stardrop-steam-auth-test 2>/dev/null || true

# Remove temporary test directories
rm -rf /tmp/stardrop-test-* 2>/dev/null || true
rm -rf /tmp/steam-guard-test-* 2>/dev/null || true

# Remove dangling images
docker image prune -f >/dev/null 2>&1

echo -e "${GREEN}✓ Cleanup complete${NC}"
