#!/bin/bash

#
# Check unattended-upgrades timer and service status
# READ-ONLY script - does NOT modify any configuration
# Only displays status and information about unattended-upgrades
#

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}=== Unattended-Upgrades Timer Status ===${NC}\n"

# Check if systemd is available
if ! command -v systemctl &> /dev/null; then
    echo -e "${RED}Error: systemctl not found. This script requires systemd.${NC}"
    exit 1
fi

# Check timer status
echo -e "${CYAN}Timer Status:${NC}"
systemctl status unattended-upgrades.timer 2>/dev/null || echo -e "${YELLOW}Timer not found or not active${NC}"

echo ""

# List all unattended-upgrades timers
echo -e "${CYAN}Timer Details:${NC}"
systemctl list-timers unattended-upgrades.timer --no-pager 2>/dev/null || echo -e "${YELLOW}No timer information available${NC}"

echo ""

# Show when timer will run next
echo -e "${CYAN}Next Scheduled Run:${NC}"
if systemctl list-timers unattended-upgrades.timer --no-pager 2>/dev/null | grep -q "unattended-upgrades"; then
    systemctl list-timers unattended-upgrades.timer --no-pager --all 2>/dev/null | tail -n +2 | head -n 1
else
    echo -e "${YELLOW}Timer not scheduled or not active${NC}"
fi

echo ""

# Check if timer is enabled
echo -e "${CYAN}Timer Enabled (starts on boot):${NC}"
if systemctl is-enabled unattended-upgrades.timer &>/dev/null; then
    ENABLED=$(systemctl is-enabled unattended-upgrades.timer)
    if [ "$ENABLED" = "enabled" ]; then
        echo -e "${GREEN}✓ Enabled${NC}"
    else
        echo -e "${YELLOW}⚠ $ENABLED${NC}"
    fi
else
    echo -e "${RED}✗ Timer not found${NC}"
fi

echo ""

# Check service status
echo -e "${CYAN}Service Status:${NC}"
systemctl status unattended-upgrades.service --no-pager -l 2>/dev/null | head -n 15 || echo -e "${YELLOW}Service not found${NC}"

echo ""

# Show timer configuration file location
echo -e "${CYAN}Timer Configuration File:${NC}"
if [ -f "/lib/systemd/system/unattended-upgrades.timer" ]; then
    echo "/lib/systemd/system/unattended-upgrades.timer"
    echo -e "${CYAN}Contents:${NC}"
    cat /lib/systemd/system/unattended-upgrades.timer
elif [ -f "/etc/systemd/system/unattended-upgrades.timer" ]; then
    echo "/etc/systemd/system/unattended-upgrades.timer"
    echo -e "${CYAN}Contents:${NC}"
    cat /etc/systemd/system/unattended-upgrades.timer
else
    echo -e "${YELLOW}Timer file not found in standard locations${NC}"
fi

echo ""
echo -e "${CYAN}=== Useful Commands ===${NC}"
echo "To see all timers:              systemctl list-timers --all"
echo "To enable timer:                sudo systemctl enable unattended-upgrades.timer"
echo "To start timer:                 sudo systemctl start unattended-upgrades.timer"
echo "To see timer logs:              journalctl -u unattended-upgrades.timer"
echo "To see service logs:            journalctl -u unattended-upgrades.service"
echo "To manually trigger update:     sudo unattended-upgrade --dry-run --debug"

