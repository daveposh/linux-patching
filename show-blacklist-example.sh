#!/bin/bash

#
# Show what the blacklist file should contain
#

echo "=== Blacklist File Location ==="
echo "/etc/apt/apt.conf.d/51unattended-upgrades-no-reboot"
echo ""

echo "=== Expected Contents (with entries) ==="
cat << 'EOF'
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

echo ""
echo "=== Package Patterns Explained ==="
echo "The blacklist uses regex patterns:"
echo '  "linux-image-.*"     - Matches any package starting with linux-image-'
echo '  "^libc6$"            - Matches exactly "libc6" (^ = start, $ = end)'
echo '  "linux-base"         - Matches exactly "linux-base"'
echo ""
echo "Total entries: 11 package patterns"
echo ""
echo "=== To verify on your system (requires sudo) ==="
echo "sudo cat /etc/apt/apt.conf.d/51unattended-upgrades-no-reboot"

