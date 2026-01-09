#!/bin/bash

#
# Scheduler wrapper for apply-security-updates.sh
# Handles maintenance windows, profile selection, and automated scheduling
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

###############################################################################
# Load Scheduler Configuration
###############################################################################

# Default scheduler values
SCHEDULER_ENABLED=true
SCHEDULER_LOG_FILE="/var/log/security-updates-scheduler.log"
LOG_SCHEDULER_DECISIONS=true
DEFAULT_PROFILE="security-no-reboot"
PROFILES_DIR="/etc/security-updates/profiles"
MAINTENANCE_TIMEZONE=""

# All preconfigured window settings (defaults)
ENABLE_PATCH_TUESDAY_NONPROD=false
ENABLE_PATCH_TUESDAY_PROD=false
ENABLE_WEEKLY_SUNDAY=false
ENABLE_WEEKLY_SATURDAY=false
ENABLE_DAILY_EARLY=false
ENABLE_MONTHLY_FIRST_SUNDAY=false

# Reboot behavior
AUTO_REBOOT_IF_REQUIRED=false
REBOOT_DELAY_MINUTES=5
REBOOT_REQUIRES_CONFIRMATION=true

# Custom windows (initialize if not set)
if [ -z "${CUSTOM_WINDOWS:-}" ]; then
    CUSTOM_WINDOWS=()
fi

# Load scheduler config
SCHEDULER_CONFIG="${SCHEDULER_CONFIG:-}"
if [ -z "${SCHEDULER_CONFIG}" ]; then
    if [ -f "${SCRIPT_DIR}/scheduler.conf" ]; then
        SCHEDULER_CONFIG="${SCRIPT_DIR}/scheduler.conf"
    elif [ -f "/etc/security-updates/scheduler.conf" ]; then
        SCHEDULER_CONFIG="/etc/security-updates/scheduler.conf"
    fi
fi

if [ -n "${SCHEDULER_CONFIG}" ] && [ -f "${SCHEDULER_CONFIG}" ]; then
    # shellcheck source=/dev/null
    source "${SCHEDULER_CONFIG}"
fi

###############################################################################
# Logging Functions
###############################################################################

scheduler_log() {
    local message="$1"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] ${message}" >> "${SCHEDULER_LOG_FILE}"
    echo -e "${message}"
}

scheduler_log_info() {
    scheduler_log "${GREEN}[INFO]${NC} ${1}"
}

scheduler_log_warn() {
    scheduler_log "${YELLOW}[WARN]${NC} ${1}"
}

scheduler_log_error() {
    scheduler_log "${RED}[ERROR]${NC} ${1}"
}

###############################################################################
# Check if Scheduler is Enabled
###############################################################################

if [ "${SCHEDULER_ENABLED}" != "true" ]; then
    scheduler_log_info "Scheduler is disabled. Exiting."
    exit 0
fi

###############################################################################
# Date/Time Helper Functions
###############################################################################

# Get current date/time in specified timezone (or system default)
get_current_datetime() {
    if [ -n "${MAINTENANCE_TIMEZONE}" ]; then
        TZ="${MAINTENANCE_TIMEZONE}" date '+%Y-%m-%d %H:%M:%S'
    else
        date '+%Y-%m-%d %H:%M:%S'
    fi
}

# Get current day of week (Mon, Tue, Wed, etc.)
get_day_of_week() {
    if [ -n "${MAINTENANCE_TIMEZONE}" ]; then
        TZ="${MAINTENANCE_TIMEZONE}" date '+%a'
    else
        date '+%a'
    fi
}

# Get current time in HH:MM format
get_current_time() {
    if [ -n "${MAINTENANCE_TIMEZONE}" ]; then
        TZ="${MAINTENANCE_TIMEZONE}" date '+%H:%M'
    else
        date '+%H:%M'
    fi
}

# Get current date (YYYY-MM-DD)
get_current_date() {
    if [ -n "${MAINTENANCE_TIMEZONE}" ]; then
        TZ="${MAINTENANCE_TIMEZONE}" date '+%Y-%m-%d'
    else
        date '+%Y-%m-%d'
    fi
}

# Check if time is within range (HH:MM format)
time_in_range() {
    local check_time="$1"
    local start_time="$2"
    local end_time="$3"
    
    # Convert to minutes since midnight for comparison
    local check_minutes=$(echo "${check_time}" | awk -F: '{print $1*60 + $2}')
    local start_minutes=$(echo "${start_time}" | awk -F: '{print $1*60 + $2}')
    local end_minutes=$(echo "${end_time}" | awk -F: '{print $1*60 + $2}')
    
    # Handle wrap-around (e.g., 22:00-02:00)
    if [ "${end_minutes}" -lt "${start_minutes}" ]; then
        # Window spans midnight
        if [ "${check_minutes}" -ge "${start_minutes}" ] || [ "${check_minutes}" -le "${end_minutes}" ]; then
            return 0
        fi
    else
        # Normal window
        if [ "${check_minutes}" -ge "${start_minutes}" ] && [ "${check_minutes}" -le "${end_minutes}" ]; then
            return 0
        fi
    fi
    return 1
}

# Get nth occurrence of day in month (e.g., 2nd Tuesday)
get_nth_weekday_in_month() {
    local day_name="$1"  # Mon, Tue, Wed, etc.
    local nth="$2"       # 1 for first, 2 for second, etc.
    
    local current_year
    local current_month
    current_year=$(date '+%Y')
    current_month=$(date '+%m')
    
    # Get day number (1-7, where 1=Monday)
    local day_num
    case "${day_name}" in
        Mon) day_num=1 ;;
        Tue) day_num=2 ;;
        Wed) day_num=3 ;;
        Thu) day_num=4 ;;
        Fri) day_num=5 ;;
        Sat) day_num=6 ;;
        Sun) day_num=7 ;;
        *) return 1 ;;
    esac
    
    # Find nth occurrence using Python or date math
    if command -v python3 &> /dev/null; then
        local target_date
        target_date=$(python3 -c "
import calendar
from datetime import date
year = int('${current_year}')
month = int('${current_month}')
day_num = ${day_num} - 1  # Python: Monday=0
nth = ${nth}

# Find first occurrence
first = calendar.monthcalendar(year, month)[0][day_num]
if first == 0:
    first = calendar.monthcalendar(year, month)[1][day_num]
else:
    first = calendar.monthcalendar(year, month)[0][day_num]

# Calculate nth occurrence
target_day = first + (nth - 1) * 7
print(f'{year}-{month:02d}-{target_day:02d}')
")
        echo "${target_date}"
        return 0
    fi
    
    # Fallback: use simple calculation
    return 1
}

# Check if today matches a specific date pattern
is_date_today() {
    local target_date="$1"
    local current_date
    current_date=$(get_current_date)
    [ "${current_date}" = "${target_date}" ]
}

# Check if day matches pattern (Mon, Tue, daily, weekdays, weekend)
day_matches() {
    local pattern="$1"
    local current_day
    current_day=$(get_day_of_week)
    
    case "${pattern}" in
        daily) return 0 ;;
        weekdays)
            case "${current_day}" in
                Mon|Tue|Wed|Thu|Fri) return 0 ;;
                *) return 1 ;;
            esac
            ;;
        weekend)
            case "${current_day}" in
                Sat|Sun) return 0 ;;
                *) return 1 ;;
            esac
            ;;
        Mon|Tue|Wed|Thu|Fri|Sat|Sun)
            [ "${current_day}" = "${pattern}" ] && return 0 || return 1
            ;;
        *) return 1 ;;
    esac
}

###############################################################################
# Window Matching Functions
###############################################################################

# Parse time window format "HH:MM-HH:MM"
parse_time_window() {
    local time_window="$1"
    local start_time
    local end_time
    start_time=$(echo "${time_window}" | cut -d'-' -f1)
    end_time=$(echo "${time_window}" | cut -d'-' -f2)
    echo "${start_time}|${end_time}"
}

# Check preconfigured maintenance windows
check_preconfigured_windows() {
    local current_time
    local current_day
    current_time=$(get_current_time)
    current_day=$(get_day_of_week)
    
    # Patch Tuesday Non-Prod (2nd Thursday)
    if [ "${ENABLE_PATCH_TUESDAY_NONPROD}" = "true" ] && [ "${current_day}" = "Thu" ]; then
        local second_tuesday
        second_tuesday=$(get_nth_weekday_in_month "Tue" 2)
        local thursday_after
        if [ -n "${second_tuesday}" ]; then
            # Calculate Thursday (2 days after Tuesday)
            local thursday_after
            if command -v python3 &> /dev/null; then
                thursday_after=$(python3 -c "
from datetime import datetime, timedelta
target = datetime.strptime('${second_tuesday}', '%Y-%m-%d')
thursday = target + timedelta(days=2)
print(thursday.strftime('%Y-%m-%d'))
")
                if is_date_today "${thursday_after}"; then
                    local times
                    times=$(parse_time_window "${PATCH_TUESDAY_NONPROD_TIME}")
                    local start_time
                    local end_time
                    start_time=$(echo "${times}" | cut -d'|' -f1)
                    end_time=$(echo "${times}" | cut -d'|' -f2)
                    if time_in_range "${current_time}" "${start_time}" "${end_time}"; then
                        echo "${PATCH_TUESDAY_NONPROD_PROFILE}"
                        return 0
                    fi
                fi
            fi
        fi
    fi
    
    # Patch Tuesday Prod (Thursday after non-prod)
    if [ "${ENABLE_PATCH_TUESDAY_PROD}" = "true" ] && [ "${current_day}" = "Thu" ]; then
        local second_tuesday
        second_tuesday=$(get_nth_weekday_in_month "Tue" 2)
        if [ -n "${second_tuesday}" ]; then
            # Calculate Thursday after non-prod (4 days after 2nd Tuesday)
            local thursday_after
            if command -v python3 &> /dev/null; then
                thursday_after=$(python3 -c "
from datetime import datetime, timedelta
target = datetime.strptime('${second_tuesday}', '%Y-%m-%d')
thursday = target + timedelta(days=4)
print(thursday.strftime('%Y-%m-%d'))
")
                if is_date_today "${thursday_after}"; then
                    local times
                    times=$(parse_time_window "${PATCH_TUESDAY_PROD_TIME}")
                    local start_time
                    local end_time
                    start_time=$(echo "${times}" | cut -d'|' -f1)
                    end_time=$(echo "${times}" | cut -d'|' -f2)
                    if time_in_range "${current_time}" "${start_time}" "${end_time}"; then
                        echo "${PATCH_TUESDAY_PROD_PROFILE}"
                        return 0
                    fi
                fi
            fi
        fi
    fi
    
    # Weekly Sunday
    if [ "${ENABLE_WEEKLY_SUNDAY}" = "true" ] && [ "${current_day}" = "Sun" ]; then
        local times
        times=$(parse_time_window "${WEEKLY_SUNDAY_TIME}")
        local start_time
        local end_time
        start_time=$(echo "${times}" | cut -d'|' -f1)
        end_time=$(echo "${times}" | cut -d'|' -f2)
        if time_in_range "${current_time}" "${start_time}" "${end_time}"; then
            echo "${WEEKLY_SUNDAY_PROFILE}"
            return 0
        fi
    fi
    
    # Weekly Saturday
    if [ "${ENABLE_WEEKLY_SATURDAY}" = "true" ] && [ "${current_day}" = "Sat" ]; then
        local times
        times=$(parse_time_window "${WEEKLY_SATURDAY_TIME}")
        local start_time
        local end_time
        start_time=$(echo "${times}" | cut -d'|' -f1)
        end_time=$(echo "${times}" | cut -d'|' -f2)
        if time_in_range "${current_time}" "${start_time}" "${end_time}"; then
            echo "${WEEKLY_SATURDAY_PROFILE}"
            return 0
        fi
    fi
    
    # Daily Early
    if [ "${ENABLE_DAILY_EARLY}" = "true" ]; then
        local times
        times=$(parse_time_window "${DAILY_EARLY_TIME}")
        local start_time
        local end_time
        start_time=$(echo "${times}" | cut -d'|' -f1)
        end_time=$(echo "${times}" | cut -d'|' -f2)
        if time_in_range "${current_time}" "${start_time}" "${end_time}"; then
            echo "${DAILY_EARLY_PROFILE}"
            return 0
        fi
    fi
    
    # Monthly First Sunday
    if [ "${ENABLE_MONTHLY_FIRST_SUNDAY}" = "true" ] && [ "${current_day}" = "Sun" ]; then
        local first_sunday
        first_sunday=$(get_nth_weekday_in_month "Sun" 1)
        if [ -n "${first_sunday}" ] && is_date_today "${first_sunday}"; then
            local times
            times=$(parse_time_window "${MONTHLY_FIRST_SUNDAY_TIME}")
            local start_time
            local end_time
            start_time=$(echo "${times}" | cut -d'|' -f1)
            end_time=$(echo "${times}" | cut -d'|' -f2)
            if time_in_range "${current_time}" "${start_time}" "${end_time}"; then
                echo "${MONTHLY_FIRST_SUNDAY_PROFILE}"
                return 0
            fi
        fi
    fi
    
    return 1
}

# Check custom maintenance windows
check_custom_windows() {
    local current_time
    local current_day
    current_time=$(get_current_time)
    current_day=$(get_day_of_week)
    
    # Skip if no custom windows defined
    [ ${#CUSTOM_WINDOWS[@]} -eq 0 ] && return 1
    
    for window in "${CUSTOM_WINDOWS[@]}"; do
        # Parse window: "DAY START_TIME END_TIME PROFILE_NAME"
        local window_day
        local start_time
        local end_time
        local profile_name
        window_day=$(echo "${window}" | awk '{print $1}')
        start_time=$(echo "${window}" | awk '{print $2}')
        end_time=$(echo "${window}" | awk '{print $3}')
        profile_name=$(echo "${window}" | awk '{print $4}')
        
        if day_matches "${window_day}" && time_in_range "${current_time}" "${start_time}" "${end_time}"; then
            echo "${profile_name}"
            return 0
        fi
    done
    
    return 1
}

###############################################################################
# Profile Loading
###############################################################################

# Load profile configuration
load_profile() {
    local profile_name="$1"
    
    # Determine profile path
    local profile_path=""
    if [ -f "${PROFILES_DIR}/${profile_name}.conf" ]; then
        profile_path="${PROFILES_DIR}/${profile_name}.conf"
    elif [ -f "${SCRIPT_DIR}/profiles/${profile_name}.conf" ]; then
        profile_path="${SCRIPT_DIR}/profiles/${profile_name}.conf"
    elif [ -f "${profile_name}.conf" ]; then
        profile_path="${profile_name}.conf"
    fi
    
    if [ -z "${profile_path}" ] || [ ! -f "${profile_path}" ]; then
        scheduler_log_error "Profile '${profile_name}' not found. Using default profile."
        return 1
    fi
    
    # Source profile config
    # shellcheck source=/dev/null
    source "${profile_path}"
    
    if [ "${LOG_SCHEDULER_DECISIONS}" = "true" ]; then
        scheduler_log_info "Loaded profile: ${profile_name} from ${profile_path}"
    fi
    
    return 0
}

###############################################################################
# Reboot Handling
###############################################################################

# Handle reboot if required
handle_reboot() {
    if [ "${AUTO_REBOOT_IF_REQUIRED}" != "true" ]; then
        return 0
    fi
    
    if [ ! -f "/var/run/reboot-required" ]; then
        return 0
    fi
    
    scheduler_log_warn "Reboot required after updates"
    
    # Check for cancellation file
    if [ "${REBOOT_REQUIRES_CONFIRMATION}" = "true" ]; then
        local cancel_file="/var/run/security-updates-reboot-cancel"
        if [ -f "${cancel_file}" ]; then
            scheduler_log_info "Reboot cancelled (${cancel_file} exists). Removing cancel file."
            rm -f "${cancel_file}"
            return 0
        fi
        # Create cancel file
        touch "${cancel_file}"
        scheduler_log_info "Reboot scheduled in ${REBOOT_DELAY_MINUTES} minutes. Cancel by deleting: ${cancel_file}"
    fi
    
    # Schedule reboot
    if [ "${REBOOT_DELAY_MINUTES}" -gt 0 ]; then
        scheduler_log_info "Scheduling reboot in ${REBOOT_DELAY_MINUTES} minutes..."
        shutdown -r +"${REBOOT_DELAY_MINUTES}" "Security updates require reboot"
    else
        scheduler_log_info "Rebooting now..."
        shutdown -r now "Security updates require reboot"
    fi
}

###############################################################################
# Main Logic
###############################################################################

scheduler_log_info "=== Scheduler Started ==="

# Determine which profile to use
SELECTED_PROFILE="${DEFAULT_PROFILE}"
PROFILE_REASON="default profile"

# Check preconfigured windows first
if matched_profile=$(check_preconfigured_windows); then
    SELECTED_PROFILE="${matched_profile}"
    PROFILE_REASON="preconfigured maintenance window"
fi

# Check custom windows (can override preconfigured if matches first)
if matched_profile=$(check_custom_windows); then
    SELECTED_PROFILE="${matched_profile}"
    PROFILE_REASON="custom maintenance window"
fi

if [ "${LOG_SCHEDULER_DECISIONS}" = "true" ]; then
    scheduler_log_info "Selected profile: ${SELECTED_PROFILE} (${PROFILE_REASON})"
fi

# Load base config first (if not already loaded)
if [ -z "${LOG_FILE:-}" ]; then
    BASE_CONFIG="${BASE_CONFIG:-}"
    if [ -z "${BASE_CONFIG}" ]; then
        if [ -f "${SCRIPT_DIR}/config.conf" ]; then
            BASE_CONFIG="${SCRIPT_DIR}/config.conf"
        elif [ -f "/etc/security-updates/config.conf" ]; then
            BASE_CONFIG="/etc/security-updates/config.conf"
        fi
    fi
    
    if [ -n "${BASE_CONFIG}" ] && [ -f "${BASE_CONFIG}" ]; then
        # shellcheck source=/dev/null
        source "${BASE_CONFIG}"
        if [ "${LOG_SCHEDULER_DECISIONS}" = "true" ]; then
            scheduler_log_info "Loaded base config: ${BASE_CONFIG}"
        fi
    fi
fi

# Load profile (overrides base config settings)
if ! load_profile "${SELECTED_PROFILE}"; then
    scheduler_log_error "Failed to load profile. Exiting."
    exit 1
fi

# Send pre-maintenance notification
if [ "${NOTIFY_BEFORE_MAINTENANCE}" = "true" ] && [ -n "${PRE_MAINTENANCE_NOTIFICATION_CMD}" ]; then
    if [ "${PROFILE_REASON}" != "default profile" ]; then
        scheduler_log_info "Sending pre-maintenance notification..."
        eval "${PRE_MAINTENANCE_NOTIFICATION_CMD}" || true
    fi
fi

# Run updates using apply-security-updates.sh
scheduler_log_info "Running updates with profile: ${SELECTED_PROFILE}"
if "${SCRIPT_DIR}/apply-security-updates.sh"; then
    scheduler_log_info "Updates completed successfully"
    
    # Send post-update notification
    if [ "${NOTIFY_AFTER_UPDATES}" = "true" ] && [ -n "${POST_UPDATE_NOTIFICATION_CMD}" ]; then
        scheduler_log_info "Sending post-update notification..."
        eval "${POST_UPDATE_NOTIFICATION_CMD}" || true
    fi
    
    # Handle reboot if required
    handle_reboot
else
    scheduler_log_error "Updates failed"
    exit 1
fi

scheduler_log_info "=== Scheduler Completed ==="
