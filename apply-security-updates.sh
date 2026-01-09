#!/bin/bash

#
# Apply security updates without packages that require reboots
# This script filters out kernel packages and other packages that require system restarts
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

###############################################################################
# Load Configuration
###############################################################################

# Default configuration values
LOG_FILE="/var/log/security-updates.log"
LOG_FORMAT="standard"
COLOR_OUTPUT=true
DATADOG_SERVICE="security-updates"
DATADOG_SOURCE="linux-patching"
DATADOG_ENV=""
DATADOG_HOST=""
UPDATE_TYPE="security"
UPDATE_PACKAGE_LISTS=true
QUIET_UPDATE=true
EXIT_IF_NO_UPDATES=false
SKIP_PACKAGES=(
    "linux-image-"
    "linux-headers-"
    "linux-modules-"
    "linux-modules-extra-"
    "linux-tools-"
    "linux-cloud-tools-"
    "linux-base"
    "libc6"
    "libc6-dev"
    "systemd"
    "systemd-sysv"
    "dbus"
)
APT_OPTIONS=()
CHECK_REBOOT_REQUIRED=true
REBOOT_REQUIRED_FILE="/var/run/reboot-required"
WARN_ON_REBOOT_REQUIRED=true
ALLOW_REBOOT_PACKAGES=false
ALLOW_PACKAGES=()

# Load configuration file if it exists
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-}"
if [ -z "${CONFIG_FILE}" ]; then
    # Try local config first, then system config
    if [ -f "${SCRIPT_DIR}/config.conf" ]; then
        CONFIG_FILE="${SCRIPT_DIR}/config.conf"
    elif [ -f "/etc/security-updates/config.conf" ]; then
        CONFIG_FILE="/etc/security-updates/config.conf"
    fi
fi

if [ -n "${CONFIG_FILE}" ] && [ -f "${CONFIG_FILE}" ]; then
    # shellcheck source=/dev/null
    source "${CONFIG_FILE}"
fi

# Set REBOOT_REQUIRED_PACKAGES from SKIP_PACKAGES if config was loaded
if [ "${#SKIP_PACKAGES[@]}" -gt 0 ]; then
    REBOOT_REQUIRED_PACKAGES=("${SKIP_PACKAGES[@]}")
fi

###############################################################################
# Logging Functions
###############################################################################

# Get current timestamp based on log format
get_timestamp() {
    case "${LOG_FORMAT}" in
        syslog)
            date '+%b %d %H:%M:%S'
            ;;
        iso)
            date -u '+%Y-%m-%dT%H:%M:%S.%3NZ' 2>/dev/null || date -u '+%Y-%m-%dT%H:%M:%SZ'
            ;;
        datadog)
            date -u '+%Y-%m-%dT%H:%M:%S.%3NZ' 2>/dev/null || date -u '+%Y-%m-%dT%H:%M:%SZ'
            ;;
        *)
            date '+%Y-%m-%d %H:%M:%S'
            ;;
    esac
}

# Get hostname for logs
get_hostname() {
    if [ -n "${DATADOG_HOST}" ]; then
        echo "${DATADOG_HOST}"
    else
        hostname -f 2>/dev/null || hostname 2>/dev/null || echo "unknown"
    fi
}

# Format log message based on LOG_FORMAT
format_log() {
    local level="$1"
    local message="$2"
    local extra_data="$3"  # JSON extra fields for Datadog
    
    case "${LOG_FORMAT}" in
        datadog)
            # Datadog JSON format
            local hostname
            hostname=$(get_hostname)
            local timestamp
            timestamp=$(get_timestamp)
            # Escape message for JSON (handle quotes, backslashes, newlines)
            local escaped_message
            escaped_message=$(echo "${message}" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
            local json="{"
            json+="\"timestamp\":\"${timestamp}\","
            json+="\"level\":\"${level}\","
            json+="\"message\":\"${escaped_message}\","
            json+="\"service\":\"${DATADOG_SERVICE}\","
            json+="\"source\":\"${DATADOG_SOURCE}\","
            json+="\"host\":\"${hostname}\""
            [ -n "${DATADOG_ENV}" ] && json+=",\"env\":\"${DATADOG_ENV}\""
            [ -n "${extra_data}" ] && json+=",${extra_data}"
            json+="}"
            echo "${json}"
            ;;
        syslog)
            # Syslog format
            local hostname
            hostname=$(get_hostname)
            local timestamp
            timestamp=$(get_timestamp)
            echo "${timestamp} ${hostname} ${DATADOG_SOURCE}: [${level^^}] ${message}"
            ;;
        iso)
            # ISO 8601 format
            local timestamp
            timestamp=$(get_timestamp)
            echo "${timestamp} [${level^^}] ${message}"
            ;;
        standard)
            # Standard format (no ANSI codes)
            local timestamp
            timestamp=$(get_timestamp)
            echo "${timestamp} [${level^^}] ${message}"
            ;;
        color|*)
            # Color format (original, with ANSI codes)
            local color_code=""
            case "${level}" in
                info) color_code="${GREEN}" ;;
                warn) color_code="${YELLOW}" ;;
                error) color_code="${RED}" ;;
            esac
            echo "${color_code}[${level^^}]${NC} ${message}"
            ;;
    esac
}

# Log to file (and optionally stdout)
log_to_file() {
    local formatted_msg="$1"
    
    # Write to log file
    echo "${formatted_msg}" >> "${LOG_FILE}"
    
    # Also output to stdout if COLOR_OUTPUT is enabled or format is not datadog
    if [ "${COLOR_OUTPUT}" = "true" ] || [ "${LOG_FORMAT}" != "datadog" ]; then
        # For console output, show colors even if log format is standard
        if [ "${LOG_FORMAT}" = "standard" ] || [ "${LOG_FORMAT}" = "iso" ] || [ "${LOG_FORMAT}" = "syslog" ]; then
            # Show colored version on console for readability
            case "${formatted_msg}" in
                *\[INFO\]*)
                    echo -e "${GREEN}${formatted_msg}${NC}"
                    ;;
                *\[WARN\]*)
                    echo -e "${YELLOW}${formatted_msg}${NC}"
                    ;;
                *\[ERROR\]*)
                    echo -e "${RED}${formatted_msg}${NC}"
                    ;;
                *)
                    echo "${formatted_msg}"
                    ;;
            esac
        else
            echo -e "${formatted_msg}"
        fi
    fi
}

log() {
    local message="$1"
    local formatted_msg
    
    # For color format, preserve original behavior
    if [ "${LOG_FORMAT}" = "color" ]; then
        formatted_msg="${message}"
    else
        # Extract level and message if using color format input
        local level="info"
        local clean_message="${message}"
        if [[ "${message}" =~ ^.*\[INFO\] ]]; then
            level="info"
            clean_message=$(echo "${message}" | sed -E 's/.*\[INFO\][[:space:]]*//' | sed 's/\x1b\[[0-9;]*m//g')
        elif [[ "${message}" =~ ^.*\[WARN\] ]]; then
            level="warn"
            clean_message=$(echo "${message}" | sed -E 's/.*\[WARN\][[:space:]]*//' | sed 's/\x1b\[[0-9;]*m//g')
        elif [[ "${message}" =~ ^.*\[ERROR\] ]]; then
            level="error"
            clean_message=$(echo "${message}" | sed -E 's/.*\[ERROR\][[:space:]]*//' | sed 's/\x1b\[[0-9;]*m//g')
        fi
        formatted_msg=$(format_log "${level}" "${clean_message}")
    fi
    
    log_to_file "${formatted_msg}"
}

log_info() {
    local message="$1"
    local extra_data="${2:-}"
    
    if [ "${LOG_FORMAT}" = "color" ]; then
        log "${GREEN}[INFO]${NC} ${message}"
    else
        local formatted_msg
        formatted_msg=$(format_log "info" "${message}" "${extra_data}")
        log_to_file "${formatted_msg}"
        # Also show on console with color
        if [ "${COLOR_OUTPUT}" = "true" ]; then
            echo -e "${GREEN}[INFO]${NC} ${message}"
        fi
    fi
}

log_warn() {
    local message="$1"
    local extra_data="${2:-}"
    
    if [ "${LOG_FORMAT}" = "color" ]; then
        log "${YELLOW}[WARN]${NC} ${message}"
    else
        local formatted_msg
        formatted_msg=$(format_log "warn" "${message}" "${extra_data}")
        log_to_file "${formatted_msg}"
        # Also show on console with color
        if [ "${COLOR_OUTPUT}" = "true" ]; then
            echo -e "${YELLOW}[WARN]${NC} ${message}"
        fi
    fi
}

log_error() {
    local message="$1"
    local extra_data="${2:-}"
    
    if [ "${LOG_FORMAT}" = "color" ]; then
        log "${RED}[ERROR]${NC} ${message}"
    else
        local formatted_msg
        formatted_msg=$(format_log "error" "${message}" "${extra_data}")
        log_to_file "${formatted_msg}"
        # Also show on console with color
        if [ "${COLOR_OUTPUT}" = "true" ]; then
            echo -e "${RED}[ERROR]${NC} ${message}"
        fi
    fi
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log_error "Please run as root or with sudo"
    exit 1
fi

TIMESTAMP=$(get_timestamp)
log_info "=== Security Update Script Started ==="

# Update package lists
if [ "${UPDATE_PACKAGE_LISTS}" = "true" ]; then
    log_info "Updating package lists..."
    UPDATE_CMD="apt-get update"
    if [ "${QUIET_UPDATE}" = "true" ]; then
        UPDATE_CMD="apt-get update -qq"
    fi
    
    if ! ${UPDATE_CMD} 2>&1 | tee -a "${LOG_FILE}"; then
        log_error "Failed to update package lists"
        exit 1
    fi
fi

# Get list of updates based on UPDATE_TYPE
if [ "${UPDATE_TYPE}" = "security" ]; then
    log_info "Checking for available security updates..."
    AVAILABLE_UPDATES=$(apt list --upgradable 2>/dev/null | grep -i security | awk -F'/' '{print $1}' || true)
    UPDATE_TYPE_LABEL="security"
else
    log_info "Checking for available updates (all types)..."
    AVAILABLE_UPDATES=$(apt list --upgradable 2>/dev/null | grep -v "^Listing\.\.\." | awk -F'/' '/\[upgradable\]$/ {print $1}' || true)
    UPDATE_TYPE_LABEL="all"
fi

if [ -z "${AVAILABLE_UPDATES}" ]; then
    log_info "No ${UPDATE_TYPE_LABEL} updates available"
    exit $([ "${EXIT_IF_NO_UPDATES}" = "true" ] && echo 1 || echo 0)
fi

# Filter packages based on ALLOW_PACKAGES (whitelist) if specified
FILTERED_UPDATES=()
if [ ${#ALLOW_PACKAGES[@]} -gt 0 ]; then
    log_info "Filtering to allowed packages only: ${ALLOW_PACKAGES[*]}"
    while IFS= read -r package; do
        [ -z "${package}" ] && continue
        
        # Check if package matches any ALLOW_PACKAGES pattern
        MATCHED=false
        for allowed_pkg in "${ALLOW_PACKAGES[@]}"; do
            if [[ "${package}" == ${allowed_pkg}* ]]; then
                MATCHED=true
                break
            fi
        done
        
        if [ "$MATCHED" = true ]; then
            FILTERED_UPDATES+=("${package}")
        fi
    done <<< "${AVAILABLE_UPDATES}"
    
    if [ ${#FILTERED_UPDATES[@]} -eq 0 ]; then
        log_warn "No available updates match the ALLOW_PACKAGES filter: ${ALLOW_PACKAGES[*]}"
        exit $([ "${EXIT_IF_NO_UPDATES}" = "true" ] && echo 1 || echo 0)
    fi
    AVAILABLE_UPDATES=$(printf '%s\n' "${FILTERED_UPDATES[@]}")
fi

# Filter out packages that require reboots (unless ALLOW_REBOOT_PACKAGES is true)
SAFE_UPDATES=()
SKIPPED_PACKAGES=()

while IFS= read -r package; do
    [ -z "${package}" ] && continue
    
    # If ALLOW_REBOOT_PACKAGES is true, don't skip any packages
    if [ "${ALLOW_REBOOT_PACKAGES}" = "true" ]; then
        SAFE_UPDATES+=("${package}")
        continue
    fi
    
    # Otherwise, filter out packages that require reboots
    SKIP=false
    for reboot_pkg in "${REBOOT_REQUIRED_PACKAGES[@]}"; do
        if [[ "${package}" == ${reboot_pkg}* ]]; then
            SKIP=true
            break
        fi
    done
    
    if [ "$SKIP" = true ]; then
        SKIPPED_PACKAGES+=("${package}")
    else
        SAFE_UPDATES+=("${package}")
    fi
done <<< "${AVAILABLE_UPDATES}"

# Report findings
if [ ${#SKIPPED_PACKAGES[@]} -gt 0 ]; then
    skipped_list=$(IFS=','; echo "${SKIPPED_PACKAGES[*]}")
    extra_data=""
    if [ "${LOG_FORMAT}" = "datadog" ]; then
        # Format packages as JSON array for Datadog
        packages_json="["
        first=true
        for pkg in "${SKIPPED_PACKAGES[@]}"; do
            [ "${first}" = "false" ] && packages_json+=","
            packages_json+="\"${pkg}\""
            first=false
        done
        packages_json+="]"
        extra_data="\"packages_skipped\":${packages_json},\"packages_skipped_count\":${#SKIPPED_PACKAGES[@]}"
    fi
    log_warn "Skipping ${#SKIPPED_PACKAGES[@]} package(s) that require reboot: ${skipped_list}" "${extra_data}"
    for pkg in "${SKIPPED_PACKAGES[@]}"; do
        log_warn "  - ${pkg}"
    done
fi

if [ ${#SAFE_UPDATES[@]} -eq 0 ]; then
    log_info "No safe ${UPDATE_TYPE_LABEL} updates available (all updates require reboot)"
    exit $([ "${EXIT_IF_NO_UPDATES}" = "true" ] && echo 1 || echo 0)
fi

packages_list=$(IFS=','; echo "${SAFE_UPDATES[*]}")
extra_data=""
if [ "${LOG_FORMAT}" = "datadog" ]; then
    # Format packages as JSON array for Datadog
    packages_json="["
    first=true
    for pkg in "${SAFE_UPDATES[@]}"; do
        [ "${first}" = "false" ] && packages_json+=","
        packages_json+="\"${pkg}\""
        first=false
    done
    packages_json+="]"
    extra_data="\"packages\":${packages_json},\"packages_count\":${#SAFE_UPDATES[@]}"
fi
log_info "Found ${#SAFE_UPDATES[@]} safe ${UPDATE_TYPE_LABEL} update(s) to apply: ${packages_list}" "${extra_data}"
for pkg in "${SAFE_UPDATES[@]}"; do
    log_info "  - ${pkg}"
done

# Apply updates using apt-get install --only-upgrade
log_info "Applying ${UPDATE_TYPE_LABEL} updates..."
APT_CMD="apt-get install -y --only-upgrade"
[ ${#APT_OPTIONS[@]} -gt 0 ] && APT_CMD="${APT_CMD} ${APT_OPTIONS[*]}"

if ${APT_CMD} "${SAFE_UPDATES[@]}" 2>&1 | tee -a "${LOG_FILE}"; then
    extra_data=""
    if [ "${LOG_FORMAT}" = "datadog" ]; then
        packages_json="["
        first=true
        for pkg in "${SAFE_UPDATES[@]}"; do
            [ "${first}" = "false" ] && packages_json+=","
            packages_json+="\"${pkg}\""
            first=false
        done
        packages_json+="]"
        extra_data="\"packages_updated\":${packages_json},\"packages_updated_count\":${#SAFE_UPDATES[@]}"
    fi
    log_info "${UPDATE_TYPE_LABEL^} updates applied successfully" "${extra_data}"
    
    # Check if reboot is still required (in case we missed something)
    if [ "${CHECK_REBOOT_REQUIRED}" = "true" ] && [ -f "${REBOOT_REQUIRED_FILE}" ]; then
        if [ "${WARN_ON_REBOOT_REQUIRED}" = "true" ]; then
            log_warn "Reboot may still be required. Check ${REBOOT_REQUIRED_FILE}.pkgs"
        fi
    elif [ "${CHECK_REBOOT_REQUIRED}" = "true" ]; then
        log_info "No reboot required for applied updates"
    fi
else
    log_error "Failed to apply some ${UPDATE_TYPE_LABEL} updates"
    exit 1
fi

TIMESTAMP=$(get_timestamp)
log_info "=== Security Update Script Completed ==="

