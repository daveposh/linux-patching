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

# Log file
LOG_FILE="/var/log/security-updates.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "${GREEN}[INFO]${NC} ${1}"
}

log_warn() {
    log "${YELLOW}[WARN]${NC} ${1}"
}

log_error() {
    log "${RED}[ERROR]${NC} ${1}"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log_error "Please run as root or with sudo"
    exit 1
fi

log_info "=== Security Update Script Started at ${TIMESTAMP} ==="

# Update package lists
log_info "Updating package lists..."
if ! apt-get update -qq 2>&1 | tee -a "${LOG_FILE}"; then
    log_error "Failed to update package lists"
    exit 1
fi

# Get list of packages that would require a reboot
# These are typically kernel packages, system libraries, and other critical packages
REBOOT_REQUIRED_PACKAGES=(
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

# Get list of security updates
log_info "Checking for available security updates..."
SECURITY_UPDATES=$(apt list --upgradable 2>/dev/null | grep -i security | awk -F'/' '{print $1}' || true)

if [ -z "${SECURITY_UPDATES}" ]; then
    log_info "No security updates available"
    exit 0
fi

# Filter out packages that require reboots
SAFE_UPDATES=()
SKIPPED_PACKAGES=()

while IFS= read -r package; do
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
done <<< "${SECURITY_UPDATES}"

# Report findings
if [ ${#SKIPPED_PACKAGES[@]} -gt 0 ]; then
    log_warn "Skipping ${#SKIPPED_PACKAGES[@]} package(s) that require reboot:"
    for pkg in "${SKIPPED_PACKAGES[@]}"; do
        log_warn "  - ${pkg}"
    done
fi

if [ ${#SAFE_UPDATES[@]} -eq 0 ]; then
    log_info "No safe security updates available (all updates require reboot)"
    exit 0
fi

log_info "Found ${#SAFE_UPDATES[@]} safe security update(s) to apply:"
for pkg in "${SAFE_UPDATES[@]}"; do
    log_info "  - ${pkg}"
done

# Apply updates using apt-get install --only-upgrade
log_info "Applying security updates..."
if apt-get install -y --only-upgrade "${SAFE_UPDATES[@]}" 2>&1 | tee -a "${LOG_FILE}"; then
    log_info "Security updates applied successfully"
    
    # Check if reboot is still required (in case we missed something)
    if [ -f /var/run/reboot-required ]; then
        log_warn "Reboot may still be required. Check /var/run/reboot-required.pkgs"
    else
        log_info "No reboot required for applied updates"
    fi
else
    log_error "Failed to apply some security updates"
    exit 1
fi

log_info "=== Security Update Script Completed at $(date '+%Y-%m-%d %H:%M:%S') ==="

