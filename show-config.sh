#!/bin/bash

#
# Show current patching configuration
# Displays all active settings from config files, profiles, and systemd
#

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${CYAN}=== Patching Configuration Overview ===${NC}\n"

###############################################################################
# Helper Functions
###############################################################################

print_section() {
    echo -e "\n${BLUE}━━━ $1 ━━━${NC}"
}

print_setting() {
    local label="$1"
    local value="$2"
    local status="${3:-}"
    
    if [ -n "${status}" ]; then
        if [ "${status}" = "found" ]; then
            echo -e "  ${GREEN}✓${NC} ${CYAN}${label}:${NC} ${value}"
        elif [ "${status}" = "missing" ]; then
            echo -e "  ${YELLOW}⚠${NC} ${CYAN}${label}:${NC} ${RED}Not found${NC}"
        elif [ "${status}" = "enabled" ]; then
            echo -e "  ${GREEN}✓${NC} ${CYAN}${label}:${NC} ${GREEN}${value}${NC}"
        elif [ "${status}" = "disabled" ]; then
            echo -e "  ${YELLOW}○${NC} ${CYAN}${label}:${NC} ${value} (disabled)"
        fi
    else
        echo -e "  ${CYAN}${label}:${NC} ${value}"
    fi
}

print_array() {
    local label="$1"
    shift
    local arr=("$@")
    
    if [ ${#arr[@]} -eq 0 ]; then
        echo -e "  ${CYAN}${label}:${NC} ${YELLOW}(none)${NC}"
    else
        echo -e "  ${CYAN}${label}:${NC}"
        for item in "${arr[@]}"; do
            echo -e "    - ${item}"
        done
    fi
}

###############################################################################
# Find Config Files
###############################################################################

print_section "Configuration Files"

# Find main config
MAIN_CONFIG=""
if [ -f "${SCRIPT_DIR}/config.conf" ]; then
    MAIN_CONFIG="${SCRIPT_DIR}/config.conf"
    print_setting "Main Config" "${MAIN_CONFIG}" "found"
elif [ -f "/etc/security-updates/config.conf" ]; then
    MAIN_CONFIG="/etc/security-updates/config.conf"
    print_setting "Main Config" "${MAIN_CONFIG}" "found"
else
    print_setting "Main Config" "Using defaults" "missing"
fi

# Find scheduler config
SCHEDULER_CONFIG=""
if [ -f "${SCRIPT_DIR}/scheduler.conf" ]; then
    SCHEDULER_CONFIG="${SCRIPT_DIR}/scheduler.conf"
    print_setting "Scheduler Config" "${SCHEDULER_CONFIG}" "found"
elif [ -f "/etc/security-updates/scheduler.conf" ]; then
    SCHEDULER_CONFIG="/etc/security-updates/scheduler.conf"
    print_setting "Scheduler Config" "${SCHEDULER_CONFIG}" "found"
else
    print_setting "Scheduler Config" "Using defaults" "missing"
fi

# Find profiles directory
PROFILES_DIR=""
if [ -d "/etc/security-updates/profiles" ]; then
    PROFILES_DIR="/etc/security-updates/profiles"
elif [ -d "${SCRIPT_DIR}/profiles" ]; then
    PROFILES_DIR="${SCRIPT_DIR}/profiles"
fi

if [ -n "${PROFILES_DIR}" ]; then
    print_setting "Profiles Directory" "${PROFILES_DIR}" "found"
    PROFILE_COUNT=$(find "${PROFILES_DIR}" -maxdepth 1 -name "*.conf" 2>/dev/null | wc -l)
    print_setting "Available Profiles" "${PROFILE_COUNT}" ""
    if [ "${PROFILE_COUNT}" -gt 0 ]; then
        find "${PROFILES_DIR}" -maxdepth 1 -name "*.conf" 2>/dev/null | while read -r profile; do
            PROFILE_NAME=$(basename "${profile}" .conf)
            echo -e "    - ${PROFILE_NAME}"
        done
    fi
else
    print_setting "Profiles Directory" "Not found" "missing"
fi

###############################################################################
# Load Main Config
###############################################################################

if [ -n "${MAIN_CONFIG}" ] && [ -f "${MAIN_CONFIG}" ]; then
    # shellcheck source=/dev/null
    source "${MAIN_CONFIG}"
fi

# Set defaults if not set
LOG_FILE="${LOG_FILE:-/var/log/security-updates.log}"
LOG_FORMAT="${LOG_FORMAT:-standard}"
COLOR_OUTPUT="${COLOR_OUTPUT:-true}"
UPDATE_TYPE="${UPDATE_TYPE:-security}"
ALLOW_REBOOT_PACKAGES="${ALLOW_REBOOT_PACKAGES:-false}"
ALLOW_PACKAGES=("${ALLOW_PACKAGES[@]:-}")
SKIP_PACKAGES=("${SKIP_PACKAGES[@]:-}")
CHECK_REBOOT_REQUIRED="${CHECK_REBOOT_REQUIRED:-true}"
WARN_ON_REBOOT_REQUIRED="${WARN_ON_REBOOT_REQUIRED:-true}"
AUTO_REBOOT_IF_REQUIRED="${AUTO_REBOOT_IF_REQUIRED:-false}"
REBOOT_DELAY_MINUTES="${REBOOT_DELAY_MINUTES:-5}"
REBOOT_REQUIRES_CONFIRMATION="${REBOOT_REQUIRES_CONFIRMATION:-true}"

###############################################################################
# Load Scheduler Config
###############################################################################

if [ -n "${SCHEDULER_CONFIG}" ] && [ -f "${SCHEDULER_CONFIG}" ]; then
    # shellcheck source=/dev/null
    source "${SCHEDULER_CONFIG}"
fi

# Set scheduler defaults
SCHEDULER_ENABLED="${SCHEDULER_ENABLED:-false}"
CHECK_INTERVAL_MINUTES="${CHECK_INTERVAL_MINUTES:-60}"
RANDOM_DELAY_SECONDS="${RANDOM_DELAY_SECONDS:-300}"
DEFAULT_PROFILE="${DEFAULT_PROFILE:-security-no-reboot}"
SCHEDULER_PROFILES_DIR="${PROFILES_DIR:-/etc/security-updates/profiles}"
SCHEDULER_LOG_FILE="${SCHEDULER_LOG_FILE:-/var/log/security-updates-scheduler.log}"
LOG_SCHEDULER_DECISIONS="${LOG_SCHEDULER_DECISIONS:-true}"

# Maintenance window defaults
ENABLE_PATCH_TUESDAY_NONPROD="${ENABLE_PATCH_TUESDAY_NONPROD:-false}"
ENABLE_PATCH_TUESDAY_PROD="${ENABLE_PATCH_TUESDAY_PROD:-false}"
ENABLE_WEEKLY_SUNDAY="${ENABLE_WEEKLY_SUNDAY:-false}"
ENABLE_WEEKLY_SATURDAY="${ENABLE_WEEKLY_SATURDAY:-false}"
ENABLE_DAILY_EARLY="${ENABLE_DAILY_EARLY:-false}"
ENABLE_MONTHLY_FIRST_SUNDAY="${ENABLE_MONTHLY_FIRST_SUNDAY:-false}"

# Custom windows
if [ -z "${CUSTOM_WINDOWS:-}" ]; then
    CUSTOM_WINDOWS=()
fi

###############################################################################
# Main Configuration Settings
###############################################################################

print_section "Main Configuration (config.conf)"

print_setting "Update Type" "${UPDATE_TYPE}"
print_setting "Allow Reboot Packages" "${ALLOW_REBOOT_PACKAGES}"

if [ "${ALLOW_REBOOT_PACKAGES}" = "false" ]; then
    echo -e "    ${YELLOW}→ Packages requiring reboot will be SKIPPED${NC}"
else
    echo -e "    ${GREEN}→ Packages requiring reboot will be INSTALLED${NC}"
fi

print_setting "Check Reboot Required" "${CHECK_REBOOT_REQUIRED}"
print_setting "Warn on Reboot Required" "${WARN_ON_REBOOT_REQUIRED}"
print_setting "Auto Reboot if Required" "${AUTO_REBOOT_IF_REQUIRED}"

if [ "${AUTO_REBOOT_IF_REQUIRED}" = "true" ]; then
    print_setting "Reboot Delay (minutes)" "${REBOOT_DELAY_MINUTES}"
    print_setting "Reboot Requires Confirmation" "${REBOOT_REQUIRES_CONFIRMATION}"
fi

print_setting "Log File" "${LOG_FILE}"
print_setting "Log Format" "${LOG_FORMAT}"
print_setting "Color Output" "${COLOR_OUTPUT}"

if [ "${LOG_FORMAT}" = "datadog" ]; then
    print_setting "Datadog Service" "${DATADOG_SERVICE:-security-updates}"
    print_setting "Datadog Source" "${DATADOG_SOURCE:-linux-patching}"
    print_setting "Datadog Environment" "${DATADOG_ENV:-(none)}"
    print_setting "Datadog Host" "${DATADOG_HOST:-(auto)}"
fi

if [ ${#ALLOW_PACKAGES[@]} -gt 0 ]; then
    print_array "Allow Packages (whitelist)" "${ALLOW_PACKAGES[@]}"
    echo -e "    ${YELLOW}→ Only these packages will be updated${NC}"
else
    print_setting "Allow Packages (whitelist)" "(none - all available packages)"
fi

if [ ${#SKIP_PACKAGES[@]} -gt 0 ]; then
    print_array "Skip Packages" "${SKIP_PACKAGES[@]}"
else
    print_setting "Skip Packages" "(none - using defaults)"
fi

###############################################################################
# Scheduler Configuration
###############################################################################

print_section "Scheduler Configuration (scheduler.conf)"

if [ "${SCHEDULER_ENABLED}" = "true" ]; then
    print_setting "Scheduler Status" "Enabled" "enabled"
else
    print_setting "Scheduler Status" "Disabled" "disabled"
fi

print_setting "Check Interval (minutes)" "${CHECK_INTERVAL_MINUTES}"
print_setting "Random Delay (seconds)" "${RANDOM_DELAY_SECONDS}"

if [ -n "${MAINTENANCE_TIMEZONE:-}" ]; then
    print_setting "Maintenance Timezone" "${MAINTENANCE_TIMEZONE}"
else
    print_setting "Maintenance Timezone" "System default"
fi

print_setting "Default Profile" "${DEFAULT_PROFILE}"
print_setting "Log Scheduler Decisions" "${LOG_SCHEDULER_DECISIONS}"
print_setting "Scheduler Log File" "${SCHEDULER_LOG_FILE}"

###############################################################################
# Maintenance Windows
###############################################################################

print_section "Maintenance Windows"

WINDOWS_ENABLED=0

if [ "${ENABLE_PATCH_TUESDAY_NONPROD}" = "true" ]; then
    ((WINDOWS_ENABLED++))
    print_setting "Patch Tuesday (Non-Prod)" "Enabled" "enabled"
    print_setting "  Time" "${PATCH_TUESDAY_NONPROD_START_TIME:-20:00} - ${PATCH_TUESDAY_NONPROD_END_TIME:-23:00}"
    print_setting "  Profile" "${PATCH_TUESDAY_NONPROD_PROFILE:-security-with-reboot}"
else
    print_setting "Patch Tuesday (Non-Prod)" "Disabled" "disabled"
fi

if [ "${ENABLE_PATCH_TUESDAY_PROD}" = "true" ]; then
    ((WINDOWS_ENABLED++))
    print_setting "Patch Tuesday (Prod)" "Enabled" "enabled"
    print_setting "  Time" "${PATCH_TUESDAY_PROD_START_TIME:-02:00} - ${PATCH_TUESDAY_PROD_END_TIME:-05:00}"
    print_setting "  Profile" "${PATCH_TUESDAY_PROD_PROFILE:-security-with-reboot}"
else
    print_setting "Patch Tuesday (Prod)" "Disabled" "disabled"
fi

if [ "${ENABLE_WEEKLY_SUNDAY}" = "true" ]; then
    ((WINDOWS_ENABLED++))
    print_setting "Weekly Sunday" "Enabled" "enabled"
    print_setting "  Time" "${WEEKLY_SUNDAY_START_TIME:-02:00} - ${WEEKLY_SUNDAY_END_TIME:-04:00}"
    print_setting "  Profile" "${WEEKLY_SUNDAY_PROFILE:-security-no-reboot}"
else
    print_setting "Weekly Sunday" "Disabled" "disabled"
fi

if [ "${ENABLE_WEEKLY_SATURDAY}" = "true" ]; then
    ((WINDOWS_ENABLED++))
    print_setting "Weekly Saturday" "Enabled" "enabled"
    print_setting "  Time" "${WEEKLY_SATURDAY_START_TIME:-02:00} - ${WEEKLY_SATURDAY_END_TIME:-04:00}"
    print_setting "  Profile" "${WEEKLY_SATURDAY_PROFILE:-security-no-reboot}"
else
    print_setting "Weekly Saturday" "Disabled" "disabled"
fi

if [ "${ENABLE_DAILY_EARLY}" = "true" ]; then
    ((WINDOWS_ENABLED++))
    print_setting "Daily Early Morning" "Enabled" "enabled"
    print_setting "  Time" "${DAILY_EARLY_START_TIME:-02:00} - ${DAILY_EARLY_END_TIME:-04:00}"
    print_setting "  Profile" "${DAILY_EARLY_PROFILE:-security-no-reboot}"
else
    print_setting "Daily Early Morning" "Disabled" "disabled"
fi

if [ "${ENABLE_MONTHLY_FIRST_SUNDAY}" = "true" ]; then
    ((WINDOWS_ENABLED++))
    print_setting "Monthly First Sunday" "Enabled" "enabled"
    print_setting "  Time" "${MONTHLY_FIRST_SUNDAY_START_TIME:-01:00} - ${MONTHLY_FIRST_SUNDAY_END_TIME:-06:00}"
    print_setting "  Profile" "${MONTHLY_FIRST_SUNDAY_PROFILE:-all-with-reboot}"
else
    print_setting "Monthly First Sunday" "Disabled" "disabled"
fi

if [ -n "${CUSTOM_WINDOWS:-}" ] && [ ${#CUSTOM_WINDOWS[@]} -gt 0 ]; then
    ((WINDOWS_ENABLED++))
    echo -e "  ${GREEN}✓${NC} ${CYAN}Custom Windows:${NC} ${GREEN}${#CUSTOM_WINDOWS[@]} configured${NC}"
    for window in "${CUSTOM_WINDOWS[@]}"; do
        if [ -n "${window}" ]; then
            IFS='|' read -r type match start end profile <<< "${window}"
            if [ -n "${type}" ] && [ -n "${match}" ]; then
                echo -e "    - ${type}: ${match} ${start}-${end} → ${profile}"
            fi
        fi
    done
else
    echo -e "  ${CYAN}Custom Windows:${NC} ${YELLOW}(none)${NC}"
fi

echo ""
if [ "${WINDOWS_ENABLED}" -eq 0 ]; then
    echo -e "  ${YELLOW}⚠ No maintenance windows enabled${NC}"
    echo -e "  ${CYAN}→ Default profile will be used: ${DEFAULT_PROFILE}${NC}"
else
    echo -e "  ${GREEN}✓ ${WINDOWS_ENABLED} maintenance window(s) enabled${NC}"
fi

###############################################################################
# Determine Active Profile (if scheduler is running)
###############################################################################

print_section "Active Profile (Current Time)"

CURRENT_TIME=$(date '+%H:%M' 2>/dev/null || echo "unknown")
CURRENT_DOW=$(date '+%A' 2>/dev/null || echo "unknown")
CURRENT_DATE=$(date '+%Y-%m-%d' 2>/dev/null || echo "unknown")
CURRENT_DAY=$(date '+%d' 2>/dev/null || echo "unknown")

echo -e "  ${CYAN}Current Time:${NC} ${CURRENT_TIME}"
echo -e "  ${CYAN}Current Day:${NC} ${CURRENT_DOW} (${CURRENT_DATE})"

# Simple check if in any maintenance window (basic logic)
IN_WINDOW=false
ACTIVE_PROFILE="${DEFAULT_PROFILE}"
ACTIVE_REASON="default profile (no maintenance window active)"

if [ "${SCHEDULER_ENABLED}" = "true" ]; then
    # This is a simplified check - the actual scheduler has more complex logic
    echo -e "  ${CYAN}Status:${NC} ${YELLOW}(Simplified check - actual scheduler uses full window matching)${NC}"
    echo -e "  ${CYAN}Active Profile:${NC} ${GREEN}${ACTIVE_PROFILE}${NC}"
    echo -e "  ${CYAN}Reason:${NC} ${ACTIVE_REASON}"
else
    echo -e "  ${CYAN}Status:${NC} ${YELLOW}Scheduler disabled - profile only applies when scheduler runs${NC}"
fi

# Try to load the active profile to show its settings
if [ -n "${PROFILES_DIR}" ] && [ -d "${PROFILES_DIR}" ]; then
    PROFILE_FILE="${PROFILES_DIR}/${ACTIVE_PROFILE}.conf"
    if [ ! -f "${PROFILE_FILE}" ]; then
        PROFILE_FILE="${SCRIPT_DIR}/profiles/${ACTIVE_PROFILE}.conf"
    fi
    
    if [ -f "${PROFILE_FILE}" ]; then
        # Load profile temporarily to show settings
        PROFILE_UPDATE_TYPE="${UPDATE_TYPE}"
        PROFILE_ALLOW_REBOOT="${ALLOW_REBOOT_PACKAGES}"
        
        # shellcheck source=/dev/null
        source "${PROFILE_FILE}"
        
        echo -e "  ${CYAN}Profile Settings:${NC}"
        echo -e "    - Update Type: ${UPDATE_TYPE:-${PROFILE_UPDATE_TYPE}}"
        echo -e "    - Allow Reboot Packages: ${ALLOW_REBOOT_PACKAGES:-${PROFILE_ALLOW_REBOOT}}"
        
        # Restore
        UPDATE_TYPE="${PROFILE_UPDATE_TYPE}"
        ALLOW_REBOOT_PACKAGES="${PROFILE_ALLOW_REBOOT}"
    fi
fi

###############################################################################
# Systemd Timer Status
###############################################################################

print_section "Systemd Service Status"

if systemctl list-unit-files security-updates.timer 2>/dev/null | grep -q "security-updates.timer"; then
    TIMER_ENABLED=$(systemctl is-enabled security-updates.timer 2>/dev/null || echo "disabled")
    TIMER_ACTIVE=$(systemctl is-active security-updates.timer 2>/dev/null || echo "inactive")
    
    if [ "${TIMER_ENABLED}" = "enabled" ]; then
        print_setting "Timer Status" "Enabled" "enabled"
    else
        print_setting "Timer Status" "Disabled" "disabled"
    fi
    
    if [ "${TIMER_ACTIVE}" = "active" ]; then
        print_setting "Timer Active" "Running" "enabled"
        NEXT_RUN=$(systemctl list-timers security-updates.timer --no-pager --no-legend 2>/dev/null | awk '{print $1, $2, $3}' | head -1)
        if [ -n "${NEXT_RUN}" ]; then
            print_setting "Next Run" "${NEXT_RUN}"
        fi
    else
        print_setting "Timer Active" "Inactive" "disabled"
    fi
    
    SERVICE_ACTIVE=$(systemctl is-active security-updates.service 2>/dev/null || echo "inactive")
    if [ "${SERVICE_ACTIVE}" = "active" ] || [ "${SERVICE_ACTIVE}" = "running" ]; then
        print_setting "Service Status" "Currently running" "enabled"
    else
        print_setting "Service Status" "Idle (normal - runs on-demand)" ""
    fi
else
    print_setting "Timer Status" "Not installed" "missing"
    echo -e "    ${YELLOW}→ Install systemd timer: ${CYAN}sudo cp systemd/* /etc/systemd/system/ && sudo systemctl daemon-reload && sudo systemctl enable --now security-updates.timer${NC}"
fi

###############################################################################
# Notification Settings
###############################################################################

print_section "Notification Settings"

if [ -n "${NOTIFY_BEFORE_MAINTENANCE:-}" ]; then
    print_setting "Notify Before Maintenance" "${NOTIFY_BEFORE_MAINTENANCE}"
    if [ "${NOTIFY_BEFORE_MAINTENANCE}" = "true" ] && [ -n "${PRE_MAINTENANCE_NOTIFICATION_CMD:-}" ]; then
        print_setting "Pre-Maintenance Command" "${PRE_MAINTENANCE_NOTIFICATION_CMD}"
    fi
else
    print_setting "Notify Before Maintenance" "Not configured"
fi

if [ -n "${NOTIFY_AFTER_UPDATES:-}" ]; then
    print_setting "Notify After Updates" "${NOTIFY_AFTER_UPDATES}"
    if [ "${NOTIFY_AFTER_UPDATES}" = "true" ] && [ -n "${POST_UPDATE_NOTIFICATION_CMD:-}" ]; then
        print_setting "Post-Update Command" "${POST_UPDATE_NOTIFICATION_CMD}"
    fi
else
    print_setting "Notify After Updates" "Not configured"
fi

###############################################################################
# Summary
###############################################################################

print_section "Configuration Summary"

echo -e "  ${CYAN}Update Strategy:${NC}"
echo -e "    - Type: ${UPDATE_TYPE}"
if [ "${ALLOW_REBOOT_PACKAGES}" = "false" ]; then
    echo -e "    - Reboot packages: ${RED}SKIPPED${NC}"
else
    echo -e "    - Reboot packages: ${GREEN}ALLOWED${NC}"
fi

echo -e "  ${CYAN}Scheduling:${NC}"
if [ "${SCHEDULER_ENABLED}" = "true" ]; then
    echo -e "    - Scheduler: ${GREEN}ENABLED${NC}"
    echo -e "    - Maintenance windows: ${GREEN}${WINDOWS_ENABLED} enabled${NC}"
    echo -e "    - Default profile: ${DEFAULT_PROFILE}"
else
    echo -e "    - Scheduler: ${YELLOW}DISABLED${NC}"
    echo -e "    - Updates: ${YELLOW}Manual/cron only${NC}"
fi

echo -e "  ${CYAN}Logging:${NC}"
echo -e "    - Format: ${LOG_FORMAT}"
echo -e "    - Main log: ${LOG_FILE}"
if [ "${SCHEDULER_ENABLED}" = "true" ]; then
    echo -e "    - Scheduler log: ${SCHEDULER_LOG_FILE}"
fi

echo -e "\n${CYAN}=== End Configuration Overview ===${NC}\n"
