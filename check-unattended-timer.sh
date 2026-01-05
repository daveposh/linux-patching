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

# Check for unattended-upgrades timer (newer systems)
echo -e "${CYAN}Unattended-Upgrades Timer Status:${NC}"
if systemctl status unattended-upgrades.timer 2>/dev/null | head -n 10; then
    echo ""
else
    echo -e "${YELLOW}unattended-upgrades.timer not found${NC}"
    echo -e "${CYAN}Checking for apt-daily timers (alternative method)...${NC}"
    echo ""
fi

# Check for apt-daily timers (older systems use these)
echo -e "${CYAN}APT Daily Timers (alternative method):${NC}"
systemctl status apt-daily.timer --no-pager 2>/dev/null | head -n 10 || echo -e "${YELLOW}apt-daily.timer not found${NC}"
echo ""
systemctl status apt-daily-upgrade.timer --no-pager 2>/dev/null | head -n 10 || echo -e "${YELLOW}apt-daily-upgrade.timer not found${NC}"

echo ""

# List all unattended-upgrades timers
echo -e "${CYAN}Timer Details:${NC}"
if systemctl list-timers unattended-upgrades.timer --no-pager 2>/dev/null | grep -q "unattended-upgrades"; then
    systemctl list-timers unattended-upgrades.timer --no-pager 2>/dev/null
else
    echo -e "${YELLOW}No unattended-upgrades.timer found${NC}"
    echo -e "${CYAN}Checking apt-daily timers...${NC}"
    systemctl list-timers apt-daily.timer apt-daily-upgrade.timer --no-pager 2>/dev/null || echo -e "${YELLOW}No apt-daily timers found${NC}"
fi

echo ""

# Show when timer will run next
echo -e "${CYAN}Next Scheduled Run:${NC}"
if systemctl list-timers unattended-upgrades.timer --no-pager 2>/dev/null | grep -q "unattended-upgrades"; then
    systemctl list-timers unattended-upgrades.timer --no-pager --all 2>/dev/null | tail -n +2 | head -n 1
elif systemctl list-timers apt-daily.timer apt-daily-upgrade.timer --no-pager 2>/dev/null | grep -q "apt-daily"; then
    echo -e "${CYAN}Using apt-daily timers:${NC}"
    systemctl list-timers apt-daily.timer apt-daily-upgrade.timer --no-pager --all 2>/dev/null
else
    echo -e "${YELLOW}No timers found or scheduled${NC}"
    echo -e "${CYAN}Checking for cron.daily method...${NC}"
    if [ -f "/etc/cron.daily/unattended-upgrades" ]; then
        echo -e "${GREEN}✓ Found: /etc/cron.daily/unattended-upgrades${NC}"
        echo "System uses cron.daily instead of systemd timers"
    fi
fi

echo ""

# Check if timer is enabled
echo -e "${CYAN}Timer Enabled (starts on boot):${NC}"
if systemctl is-enabled unattended-upgrades.timer &>/dev/null; then
    ENABLED=$(systemctl is-enabled unattended-upgrades.timer)
    if [ "$ENABLED" = "enabled" ]; then
        echo -e "${GREEN}✓ unattended-upgrades.timer: enabled${NC}"
    else
        echo -e "${YELLOW}⚠ unattended-upgrades.timer: $ENABLED${NC}"
    fi
elif systemctl is-enabled apt-daily.timer &>/dev/null || systemctl is-enabled apt-daily-upgrade.timer &>/dev/null; then
    APT_DAILY=$(systemctl is-enabled apt-daily.timer 2>/dev/null || echo "not-found")
    APT_UPGRADE=$(systemctl is-enabled apt-daily-upgrade.timer 2>/dev/null || echo "not-found")
    echo "apt-daily.timer: $APT_DAILY"
    echo "apt-daily-upgrade.timer: $APT_UPGRADE"
else
    echo -e "${YELLOW}⚠ No systemd timers found${NC}"
    if [ -f "/etc/cron.daily/unattended-upgrades" ]; then
        echo -e "${CYAN}System uses cron.daily method instead${NC}"
    fi
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

