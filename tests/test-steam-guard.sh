#!/bin/bash
# =============================================================================
# StardropHost | tests/test-steam-guard.sh
# Tests the stardrop-steam-auth sidecar REST API
#
# Requires the stardrop-steam-auth container to be running.
# Usage: bash tests/test-steam-guard.sh [BASE_URL]
#   BASE_URL defaults to http://localhost:3000
# =============================================================================

set -o pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

BASE_URL="${1:-http://localhost:3000}"
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_NAMES=()

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
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Check that curl is available
if ! command -v curl &>/dev/null; then
    echo -e "${RED}ERROR: curl is required${NC}"
    exit 1
fi

echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  StardropHost – steam-auth sidecar API test                       ║${NC}"
echo -e "${CYAN}║  Target: ${BASE_URL}                                  ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# =============================================================================
# 1. Health / connectivity
# =============================================================================
section "1. Health check"

HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$BASE_URL/health" 2>/dev/null || echo "000")
if [ "$HTTP_STATUS" = "200" ]; then
    pass "GET /health returns 200"
else
    fail "GET /health – expected 200, got $HTTP_STATUS (is the container running?)"
fi

# =============================================================================
# 2. Status endpoint
# =============================================================================
section "2. GET /status"

BODY=$(curl -s --max-time 5 "$BASE_URL/status" 2>/dev/null)
if echo "$BODY" | grep -q '"status"'; then
    pass "GET /status returns JSON with 'status' field"
else
    fail "GET /status – missing 'status' field in response"
fi

# =============================================================================
# 3. Steam Guard code submission (invalid code – expected rejection)
# =============================================================================
section "3. POST /guard-code (invalid code)"

RESPONSE=$(curl -s --max-time 5 -X POST "$BASE_URL/guard-code" \
    -H "Content-Type: application/json" \
    -d '{"code":"XXXXX"}' 2>/dev/null)

# The server should respond with a JSON body regardless of success/failure
if echo "$RESPONSE" | grep -qE '"(error|status|message)"'; then
    pass "POST /guard-code returns structured JSON response"
else
    fail "POST /guard-code – response is not structured JSON (got: $RESPONSE)"
fi

# =============================================================================
# 4. Steam Guard code – missing body
# =============================================================================
section "4. POST /guard-code – validation"

HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 -X POST "$BASE_URL/guard-code" \
    -H "Content-Type: application/json" \
    -d '{}' 2>/dev/null || echo "000")
if [ "$HTTP_STATUS" = "400" ]; then
    pass "POST /guard-code with empty body returns 400"
else
    fail "POST /guard-code empty body – expected 400, got $HTTP_STATUS"
fi

# =============================================================================
# 5. Unknown route returns 404
# =============================================================================
section "5. 404 on unknown routes"

HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$BASE_URL/nonexistent" 2>/dev/null || echo "000")
if [ "$HTTP_STATUS" = "404" ]; then
    pass "GET /nonexistent returns 404"
else
    fail "Unknown route – expected 404, got $HTTP_STATUS"
fi

# =============================================================================
# Summary
# =============================================================================
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
    echo -e "  ${YELLOW}NOTE: failures may simply mean the container is not running.${NC}"
    echo -e "  Start it with: docker compose up stardrop-steam-auth"
    echo ""
    exit 1
else
    echo -e "  ${GREEN}╔═══════════════════╗${NC}"
    echo -e "  ${GREEN}║  ALL TESTS PASS   ║${NC}"
    echo -e "  ${GREEN}╚═══════════════════╝${NC}"
    exit 0
fi
