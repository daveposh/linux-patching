#!/bin/bash

#
# Install and enable unattended-upgrades timer
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

echo -e "${CYAN}=== Installing/Enabling Unattended-Upgrades Timer ===${NC}\n"

# Check if unattended-upgrades is installed
if ! command -v unattended-upgrade &> /dev/null; then
    echo -e "${YELLOW}unattended-upgrades package not found. Installing...${NC}"
    apt-get update -qq
    apt-get install -y unattended-upgrades
fi

# Check for timer file locations
TIMER_FILE=""
if [ -f "/lib/systemd/system/unattended-upgrades.timer" ]; then
    TIMER_FILE="/lib/systemd/system/unattended-upgrades.timer"
    echo -e "${GREEN}✓ Found timer file: ${TIMER_FILE}${NC}"
elif [ -f "/usr/lib/systemd/system/unattended-upgrades.timer" ]; then
    TIMER_FILE="/usr/lib/systemd/system/unattended-upgrades.timer"
    echo -e "${GREEN}✓ Found timer file: ${TIMER_FILE}${NC}"
elif [ -f "/etc/systemd/system/unattended-upgrades.timer" ]; then
    TIMER_FILE="/etc/systemd/system/unattended-upgrades.timer"
    echo -e "${GREEN}✓ Found timer file: ${TIMER_FILE}${NC}"
else
    echo -e "${YELLOW}⚠ Timer file not found in standard locations${NC}"
    echo -e "${CYAN}Searching for timer file...${NC}"
    TIMER_FILE=$(find /lib /usr/lib /etc -name "unattended-upgrades.timer" 2>/dev/null | head -1)
    
    if [ -z "$TIMER_FILE" ]; then
        echo -e "${RED}✗ Timer file not found. Checking if package needs reinstall...${NC}"
        
        # Check package files
        if command -v dpkg &> /dev/null; then
            echo -e "${CYAN}Checking unattended-upgrades package files...${NC}"
            dpkg -L unattended-upgrades | grep -i timer || echo "No timer files in package"
        fi
        
        echo -e "${YELLOW}The timer may be in a different package or needs to be created manually.${NC}"
        echo -e "${CYAN}Trying to enable it anyway...${NC}"
    else
        echo -e "${GREEN}✓ Found timer file: ${TIMER_FILE}${NC}"
    fi
fi

echo ""

# Try to enable and start the timer
echo -e "${CYAN}Enabling unattended-upgrades.timer...${NC}"
if systemctl enable unattended-upgrades.timer 2>&1; then
    echo -e "${GREEN}✓ Timer enabled${NC}"
else
    echo -e "${RED}✗ Failed to enable timer${NC}"
    echo -e "${YELLOW}This might mean the timer unit file doesn't exist on this system.${NC}"
fi

echo ""

echo -e "${CYAN}Starting unattended-upgrades.timer...${NC}"
if systemctl start unattended-upgrades.timer 2>&1; then
    echo -e "${GREEN}✓ Timer started${NC}"
else
    echo -e "${YELLOW}⚠ Could not start timer (might not exist)${NC}"
fi

echo ""

# Check status
echo -e "${CYAN}Checking timer status...${NC}"
systemctl status unattended-upgrades.timer --no-pager -l | head -n 20 || echo -e "${YELLOW}Timer not available${NC}"

echo ""

# Alternative: Check if updates are configured via cron
echo -e "${CYAN}Checking for alternative update methods...${NC}"
if [ -f "/etc/cron.daily/unattended-upgrades" ]; then
    echo -e "${GREEN}✓ Found cron.daily script: /etc/cron.daily/unattended-upgrades${NC}"
    echo -e "${CYAN}System may be using cron.daily instead of systemd timer${NC}"
fi

echo ""
echo -e "${CYAN}=== Summary ===${NC}"
echo "If the timer is not available, your system may use:"
echo "  - cron.daily (check /etc/cron.daily/unattended-upgrades)"
echo "  - Different package configuration"
echo ""
echo "To manually run updates: sudo unattended-upgrade --dry-run --debug"

