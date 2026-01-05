#!/bin/bash

#
# Configure unattended-upgrades to skip packages that require reboots
# This creates a configuration that prevents automatic installation of reboot-required packages
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} ${1}"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} ${1}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} ${1}"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log_error "Please run as root or with sudo"
    exit 1
fi

# Install unattended-upgrades if not already installed
if ! command -v unattended-upgrade &> /dev/null; then
    log_info "Installing unattended-upgrades..."
    apt-get update -qq
    apt-get install -y unattended-upgrades
fi

# Backup existing configuration
CONFIG_FILE="/etc/apt/apt.conf.d/50unattended-upgrades"
if [ -f "${CONFIG_FILE}" ]; then
    log_info "Backing up existing configuration..."
    cp "${CONFIG_FILE}" "${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
fi

# Create package blacklist configuration
BLACKLIST_FILE="/etc/apt/apt.conf.d/51unattended-upgrades-no-reboot"
log_info "Creating package blacklist configuration..."

cat > "${BLACKLIST_FILE}" << 'EOF'
// Packages that require reboots - exclude from automatic updates
Unattended-Upgrade::Package-Blacklist {
    // Kernel packages
    "linux-image-.*";
    "linux-headers-.*";
    "linux-modules-.*";
    "linux-modules-extra-.*";
    "linux-tools-.*";
    "linux-cloud-tools-.*";
    "linux-base";
    
    // Critical system libraries that require restarts
    "^libc6$";
    "^libc6-dev$";
    
    // Systemd and related
    "^systemd$";
    "^systemd-sysv$";
    "^dbus$";
};
EOF

log_info "Package blacklist configuration created at ${BLACKLIST_FILE}"

# Ensure unattended-upgrades only processes security updates
if ! grep -q "Unattended-Upgrade::Allowed-Origins" "${CONFIG_FILE}" 2>/dev/null; then
    log_warn "Please verify that ${CONFIG_FILE} contains security origins"
    log_warn "It should include: \"\${distro_id}:\${distro_codename}-security\";"
fi

# Ensure automatic reboot is disabled
if ! grep -q "Unattended-Upgrade::Automatic-Reboot" "${CONFIG_FILE}" 2>/dev/null; then
    log_info "Adding Automatic-Reboot=false to configuration..."
    echo "" >> "${CONFIG_FILE}"
    echo "// Prevent automatic reboots" >> "${CONFIG_FILE}"
    echo "Unattended-Upgrade::Automatic-Reboot \"false\";" >> "${CONFIG_FILE}"
fi

log_info "Configuration complete!"
log_info "To test the configuration, run: sudo unattended-upgrade --dry-run --debug"
log_info "To manually trigger updates: sudo unattended-upgrade"

