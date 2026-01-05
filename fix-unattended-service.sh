#!/bin/bash

#
# Check and fix unattended-upgrades service/timer status
#

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: Please run as root or with sudo${NC}"
    exit 1
fi

echo -e "${CYAN}=== Unattended-Upgrades Service Status ===${NC}\n"

# Check service status
echo -e "${CYAN}Service Status:${NC}"
systemctl status unattended-upgrades.service --no-pager -l | head -n 15

echo ""

# Check timer status
echo -e "${CYAN}Timer Status:${NC}"
systemctl status unattended-upgrades.timer --no-pager -l | head -n 15

echo ""

# Check if service is active
SERVICE_ACTIVE=$(systemctl is-active unattended-upgrades.service 2>/dev/null || echo "inactive")
TIMER_ACTIVE=$(systemctl is-active unattended-upgrades.timer 2>/dev/null || echo "inactive")
TIMER_ENABLED=$(systemctl is-enabled unattended-upgrades.timer 2>/dev/null || echo "disabled")

echo -e "${CYAN}Current State:${NC}"
echo "  Service active: ${SERVICE_ACTIVE}"
echo "  Timer active: ${TIMER_ACTIVE}"
echo "  Timer enabled: ${TIMER_ENABLED}"

echo ""

# Note about service state
if [ "$SERVICE_ACTIVE" = "inactive" ] || [ "$SERVICE_ACTIVE" = "dead" ]; then
    echo -e "${YELLOW}Note: The service shows as inactive/dead - this is NORMAL!${NC}"
    echo -e "${CYAN}The unattended-upgrades service is designed to:${NC}"
    echo "  1. Run on-demand when triggered by the timer"
    echo "  2. Exit when finished (not stay running)"
    echo "  3. The TIMER is what keeps it scheduled"
    echo ""
    echo -e "${CYAN}What matters is the TIMER status, not the service status${NC}"
fi

echo ""

# Check if timer is enabled
if [ "$TIMER_ENABLED" != "enabled" ]; then
    echo -e "${YELLOW}⚠ Timer is NOT enabled (won't start on boot)${NC}"
    echo -e "${CYAN}To enable the timer:${NC}"
    echo "  sudo systemctl enable unattended-upgrades.timer"
    echo "  sudo systemctl start unattended-upgrades.timer"
else
    echo -e "${GREEN}✓ Timer is enabled${NC}"
fi

echo ""

# Show next scheduled run
echo -e "${CYAN}Next Scheduled Run:${NC}"
systemctl list-timers unattended-upgrades.timer --no-pager --all 2>/dev/null || echo -e "${YELLOW}No timer information available${NC}"

echo ""
echo -e "${CYAN}=== Summary ===${NC}"
echo "The service being 'inactive/dead' is normal - it runs on-demand."
echo "Check the TIMER status to see if updates are scheduled."
echo ""
echo "To manually test: sudo unattended-upgrade --dry-run --debug"

