#!/bin/bash

#
# Check patch status - Simple way to verify if server was patched
#

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m' # No Color

LOG_FILE="/var/log/security-updates.log"

echo -e "${CYAN}=== Server Patch Status ===${NC}\n"

# Check last patch time from log file
if [ -f "${LOG_FILE}" ]; then
    LAST_PATCH=$(grep "Security Update Script Completed" "${LOG_FILE}" | tail -1 | sed 's/.*at \(.*\) ===.*/\1/' || echo "")
    LAST_START=$(grep "Security Update Script Started" "${LOG_FILE}" | tail -1 | sed 's/.*at \(.*\) ===.*/\1/' || echo "")
    
    if [ -n "${LAST_PATCH}" ]; then
        echo -e "${GREEN}✓ Last successful patch:${NC} ${LAST_PATCH}"
        
        # Calculate if it's the same calendar day
        if command -v date &> /dev/null; then
            # Extract date part (YYYY-MM-DD) from timestamp
            LAST_DATE=$(echo "${LAST_PATCH}" | awk '{print $1}' || echo "")
            TODAY_DATE=$(date '+%Y-%m-%d' 2>/dev/null || echo "")
            
            if [ -n "${LAST_DATE}" ] && [ -n "${TODAY_DATE}" ]; then
                if [ "${LAST_DATE}" = "${TODAY_DATE}" ]; then
                    echo -e "  ${GREEN}  (Today)${NC}"
                else
                    # Calculate days ago using epoch for accuracy
                    LAST_EPOCH=$(date -d "${LAST_PATCH}" +%s 2>/dev/null || echo "")
                    NOW_EPOCH=$(date +%s 2>/dev/null || echo "")
                    if [ -n "${LAST_EPOCH}" ] && [ -n "${NOW_EPOCH}" ] && [ "${NOW_EPOCH}" -gt "${LAST_EPOCH}" ]; then
                        DAYS_AGO=$(( (NOW_EPOCH - LAST_EPOCH) / 86400 ))
                        if [ "${DAYS_AGO}" -eq 1 ]; then
                            echo -e "  ${YELLOW}  (1 day ago)${NC}"
                        elif [ "${DAYS_AGO}" -lt 7 ]; then
                            echo -e "  ${YELLOW}  (${DAYS_AGO} days ago)${NC}"
                        else
                            echo -e "  ${RED}  (${DAYS_AGO} days ago - OLD)${NC}"
                        fi
                    fi
                fi
            fi
        fi
        
        # Extract packages from the last successful update
        # Find the last successful run by looking for completed entries
        LAST_COMPLETED_LINE=$(grep -n "Security Update Script Completed" "${LOG_FILE}" | tail -1 | cut -d: -f1)
        if [ -n "${LAST_COMPLETED_LINE}" ]; then
            # Find the section between last "Started" and "Completed" for this run
            LAST_STARTED_LINE=$(sed -n "1,${LAST_COMPLETED_LINE}p" "${LOG_FILE}" | grep -n "Security Update Script Started" | tail -1 | cut -d: -f1)
            
            if [ -n "${LAST_STARTED_LINE}" ] && [ "${LAST_STARTED_LINE}" -lt "${LAST_COMPLETED_LINE}" ]; then
                # Extract lines in this section that contain package names (pattern: "  - package-name")
                # Strip ANSI color codes first, then extract package names
                UPDATED_PACKAGES=$(sed -n "${LAST_STARTED_LINE},${LAST_COMPLETED_LINE}p" "${LOG_FILE}" | \
                    sed 's/\x1b\[[0-9;]*m//g' | \
                    sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' | \
                    grep -E "\s+-\s+[a-zA-Z0-9]" | \
                    sed -E 's/.*-\s+([a-zA-Z0-9][a-zA-Z0-9._-]+).*/\1/' | \
                    grep -v "^Found" | \
                    grep -v "^Security" | \
                    sort -u || echo "")
                
                if [ -n "${UPDATED_PACKAGES}" ]; then
                    PACKAGE_COUNT=$(echo "${UPDATED_PACKAGES}" | grep -v "^$" | wc -l | tr -d ' ')
                    if [ "${PACKAGE_COUNT}" -gt 0 ] && [ "${PACKAGE_COUNT}" -lt 100 ]; then  # Sanity check
                        echo -e "  ${CYAN}Packages updated:${NC} ${PACKAGE_COUNT}"
                        echo "${UPDATED_PACKAGES}" | grep -v "^$" | sed 's/^/    - /'
                    fi
                fi
            fi
        fi
    elif [ -n "${LAST_START}" ]; then
        echo -e "${YELLOW}⚠ Last patch attempt:${NC} ${LAST_START} (may have failed - check log)"
    else
        echo -e "${YELLOW}⚠ No patch history found in log${NC}"
    fi
else
    echo -e "${YELLOW}⚠ No patch log file found at ${LOG_FILE}${NC}"
fi

echo ""

# Check last package update time (from dpkg log)
if [ -f "/var/log/dpkg.log" ]; then
    LAST_DPKG_UPDATE=$(grep "status installed" /var/log/dpkg.log 2>/dev/null | tail -1 | awk '{print $1, $2}' || echo "")
    if [ -n "${LAST_DPKG_UPDATE}" ]; then
        echo -e "${CYAN}Last package update (system-wide):${NC} ${LAST_DPKG_UPDATE}"
    fi
fi

echo ""

# Check for pending security updates (requires apt access)
if command -v apt &> /dev/null; then
    # Update package lists if user has permission
    if [ -w "/var/cache/apt" ] 2>/dev/null || [ "$EUID" -eq 0 ]; then
        apt update -qq > /dev/null 2>&1
    fi
    
    PENDING_SECURITY_LIST=$(apt list --upgradable 2>/dev/null | grep -i security | awk -F'/' '{print $1}' || echo "")
    PENDING_SECURITY=$(echo "${PENDING_SECURITY_LIST}" | grep -v "^$" | wc -l || echo "0")
    PENDING_TOTAL=$(apt list --upgradable 2>/dev/null | grep -c "upgradable" || echo "0")
    
    if [ "${PENDING_SECURITY}" -gt 0 ]; then
        echo -e "${YELLOW}⚠ Pending security updates:${NC} ${PENDING_SECURITY}"
        echo -e "  ${YELLOW}Packages:${NC}"
        echo "${PENDING_SECURITY_LIST}" | grep -v "^$" | sed 's/^/    - /'
        if [ "${PENDING_TOTAL}" -gt "${PENDING_SECURITY}" ]; then
            echo -e "  ${CYAN}  (Total upgradable packages: ${PENDING_TOTAL})${NC}"
        fi
    else
        echo -e "${GREEN}✓ No pending security updates${NC}"
        if [ "${PENDING_TOTAL}" -gt 0 ]; then
            echo -e "  ${CYAN}  (Non-security updates available: ${PENDING_TOTAL})${NC}"
        fi
    fi
else
    echo -e "${YELLOW}⚠ Cannot check pending updates (apt not available)${NC}"
fi

echo ""

# Check reboot status
if [ -f "/var/run/reboot-required" ]; then
    echo -e "${RED}⚠ REBOOT REQUIRED${NC}"
    if [ -f "/var/run/reboot-required.pkgs" ]; then
        echo -e "  ${YELLOW}Packages requiring reboot:${NC}"
        cat /var/run/reboot-required.pkgs | sed 's/^/    - /'
    fi
else
    echo -e "${GREEN}✓ No reboot required${NC}"
fi

echo ""

# System uptime
if command -v uptime &> /dev/null; then
    UPTIME_INFO=$(uptime -p 2>/dev/null || uptime | awk -F'up ' '{print $2}' | awk -F',' '{print $1}')
    if [ -n "${UPTIME_INFO}" ]; then
        echo -e "${CYAN}System uptime:${NC} ${UPTIME_INFO}"
    fi
fi

echo ""
echo -e "${CYAN}=== End Status ===${NC}"

