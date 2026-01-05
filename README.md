# Linux Security Updates - No Reboot Required

This repository contains scripts to apply security updates on Debian/Ubuntu systems while **skipping packages that require system reboots**.

## Overview

The scripts filter out kernel packages and other critical system packages that would require a restart, applying only safe security updates that can be installed without rebooting.

## Files

- **`apply-security-updates.sh`** - Manual script to apply security updates (skips reboot-required packages)
- **`check-patch-status.sh`** - Quick status check to verify if server was patched and when
- **`unattended-upgrades-config.sh`** - Configuration script for automated updates via unattended-upgrades
- **`README.md`** - This file

## Quick Start

### Option 1: Manual Script (`apply-security-updates.sh`)

This script must be run manually or scheduled via cron. It does NOT run automatically by default.

1. Make the script executable:
   ```bash
   chmod +x apply-security-updates.sh
   ```

2. Run manually with sudo:
   ```bash
   sudo ./apply-security-updates.sh
   ```

3. **To make it automatic, schedule via cron:**
   ```bash
   # Add to crontab (runs daily at 2 AM)
   sudo crontab -e
   # Add this line (update the path to match your script location):
   0 2 * * * /full/path/to/apply-security-updates.sh
   ```

   **Note:** Without cron scheduling, this script only runs when you manually execute it.

### Option 2: Automated Updates with unattended-upgrades

This option uses the system's built-in `unattended-upgrades` service which runs automatically via systemd timers (no cron needed).

**Important:** The `unattended-upgrades` package comes WITH a systemd timer/service already installed. The config script just modifies the configuration files.

1. Run the configuration script once:
   ```bash
   sudo ./unattended-upgrades-config.sh
   ```

2. The script will:
   - Install `unattended-upgrades` package if needed (package includes systemd timer/service)
   - Create/modify config files in `/etc/apt/apt.conf.d/`:
     - Creates `/etc/apt/apt.conf.d/51unattended-upgrades-no-reboot` (package blacklist)
     - Modifies `/etc/apt/apt.conf.d/50unattended-upgrades` (disables auto-reboot)
   - The systemd timer/service already exists (comes with the package)

3. Test the configuration:
   ```bash
   sudo unattended-upgrade --dry-run --debug
   ```

4. **The service runs automatically** - No cron needed! The `unattended-upgrades` systemd timer runs automatically multiple times per day (this is built into the package, not created by the script).

## Packages That Are Skipped

The following packages are excluded from automatic updates as they typically require reboots:

- **Kernel packages**: `linux-image-*`, `linux-headers-*`, `linux-modules-*`
- **Critical libraries**: `libc6`, `libc6-dev`
- **System services**: `systemd`, `systemd-sysv`, `dbus`

## Scripts Overview

- **`apply-security-updates.sh`** - **STANDALONE** script (Option 1)
  - Completely separate from unattended-upgrades package
  - Runs manually or via cron
  - No systemd timers, no config files

- **`unattended-upgrades-config.sh`** - **CONFIGURES** unattended-upgrades service (Option 2)
  - Installs `unattended-upgrades` package if needed (package includes systemd timer)
  - Creates `/etc/apt/apt.conf.d/51unattended-upgrades-no-reboot` (blacklist)
  - Modifies `/etc/apt/apt.conf.d/50unattended-upgrades` (no-reboot setting)
  - Does NOT create timers (they come with the package!)
  
- **`check-unattended-timer.sh`** - **READ-ONLY** status check 
  - Does NOT modify any configuration files
  - Only displays information about timer/service status
  - Safe to run anytime (no changes made)

**Note:** See `ARCHITECTURE.md` for detailed explanation of how these systems work.

## Checking Unattended-Upgrades Timer

The `check-unattended-timer.sh` script is **read-only** - it only displays information and does NOT configure anything.

To check when unattended-upgrades runs automatically, use these commands:

**Quick status:**
```bash
systemctl status unattended-upgrades.timer
systemctl list-timers unattended-upgrades.timer
```

**See next scheduled run:**
```bash
systemctl list-timers --all | grep unattended-upgrades
```

**Check if timer is enabled:**
```bash
systemctl is-enabled unattended-upgrades.timer
```

**View timer configuration:**
```bash
cat /lib/systemd/system/unattended-upgrades.timer
# or
cat /etc/systemd/system/unattended-upgrades.timer
```

**Or use the helper script:**
```bash
./check-unattended-timer.sh
```

## Checking Patch Status

To quickly verify if your server was patched, use the status check script:

```bash
./check-patch-status.sh
```

Or with sudo if you want to check for pending updates:
```bash
sudo ./check-patch-status.sh
```

This script shows:
- Last successful patch time
- Days since last patch
- Pending security updates
- Reboot status
- System uptime

## Logging

The manual script logs to `/var/log/security-updates.log` with timestamps and color-coded output.

## Checking for Required Reboots

Even with this setup, you should periodically check if a reboot is needed:

```bash
# Check if reboot is required
if [ -f /var/run/reboot-required ]; then
    echo "Reboot required for:"
    cat /var/run/reboot-required.pkgs
fi
```

## Notes

- **Security Considerations**: Skipping kernel updates means critical security patches may not be applied until you manually reboot. Consider using live patching solutions (Ubuntu Livepatch or Debian kpatch/KernelCare) to patch kernels without reboots.
- **Monitoring**: Regularly review the logs and check for reboot requirements.
- **Testing**: Always test on a non-production system first.

## Live Patching (Optional)

### Ubuntu Livepatch

For kernel security patches without reboots, Ubuntu offers Livepatch service:

```bash
sudo pro enable livepatch
```

This service is free for up to 3 machines and applies critical kernel security fixes without requiring reboots.

### Debian Live Patching

Debian offers live patching through **kpatch**, though it requires more manual setup than Ubuntu's Livepatch service:

1. **Install kpatch** (available in Debian repositories):
   ```bash
   sudo apt-get update
   sudo apt-get install kpatch kpatch-build
   ```

2. **Build kernel patches**: kpatch requires building patches from source, which is more involved than Ubuntu's managed service.

3. **Alternative - KernelCare**: Third-party commercial service that provides live kernel patching for Debian (similar to Ubuntu Livepatch but requires a subscription).

Note: Unlike Ubuntu's managed Livepatch service, Debian's kpatch requires manual patch creation and management. For production Debian systems, you may want to consider KernelCare or schedule regular maintenance windows for kernel updates.

## Requirements

- Debian or Ubuntu system
- Root/sudo access
- Internet connection for package updates

## License

This is provided as-is for system administration purposes.

