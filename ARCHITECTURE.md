# Architecture Overview

This document clarifies how the two update methods work.

## Two Completely Separate Options

### Option 1: `apply-security-updates.sh` (Standalone Script)

**What it is:**
- A standalone bash script (NOT related to unattended-upgrades package)
- Runs manually or via cron
- Does NOT use the unattended-upgrades service

**How it works:**
- Script runs → filters packages → applies updates
- Must be run manually OR scheduled in cron
- Has its own logic (no systemd timers)

**Files:**
- `/var/log/security-updates.log` - Log file

---

### Option 2: `unattended-upgrades` (System Service)

**What it is:**
- A system package/service provided by Debian/Ubuntu
- Runs automatically via systemd timers (NO cron needed)
- Has its own configuration system

**Default State (when package is installed):**
- ✅ Systemd timer/service IS installed and enabled
- ✅ Default config files exist in `/etc/apt/apt.conf.d/`
- ⚠️ Default config may update ALL packages (not just security)
- ⚠️ Default config may auto-reboot

**What `unattended-upgrades-config.sh` does:**
- Installs the `unattended-upgrades` package (if not installed)
- Modifies config files to:
  - Only update security packages
  - Skip reboot-required packages (blacklist)
  - Disable auto-reboot
- Does NOT create timers (they already exist!)

**Files created/modified:**
- `/etc/apt/apt.conf.d/50unattended-upgrades` - Modified (adds no-reboot setting)
- `/etc/apt/apt.conf.d/51unattended-upgrades-no-reboot` - Created (blacklist)
- Systemd timer: `/lib/systemd/system/unattended-upgrades.timer` - Already exists

---

## Key Differences

| Feature | Option 1 (apply-security-updates.sh) | Option 2 (unattended-upgrades) |
|---------|--------------------------------------|--------------------------------|
| **Type** | Standalone script | System service |
| **Scheduling** | Manual or cron | Systemd timer (automatic) |
| **Config Files** | No config files | `/etc/apt/apt.conf.d/*` |
| **Timer** | No timer (needs cron) | Systemd timer (built-in) |
| **Independence** | Completely separate | Part of system |

---

## Service Status Explained

**Important:** The `unattended-upgrades.service` showing as "inactive" or "dead" is **NORMAL**!

- The service is designed to run on-demand (triggered by the timer)
- It exits when finished (doesn't stay running)
- What matters is the **TIMER** status, not the service status
- The timer triggers the service periodically

To check if it's working:
```bash
systemctl status unattended-upgrades.timer  # Check timer (this is what matters)
systemctl list-timers unattended-upgrades.timer  # See next run time
```

## Common Misconceptions

❌ **"unattended-upgrades has no timer by default"**
- ✅ FALSE: The package comes WITH a systemd timer/service

❌ **"Service status should show 'active'"**
- ✅ FALSE: Service shows inactive/dead when not running (normal)
- ✅ TRUE: Timer should be enabled and active

❌ **"apply-security-updates.sh configures unattended-upgrades"**
- ✅ FALSE: They are completely separate systems

❌ **"Config is injected at runtime"**
- ✅ FALSE: Config files are static files in `/etc/apt/apt.conf.d/`

❌ **"unattended-upgrades needs cron"**
- ✅ FALSE: It uses systemd timers (automatic)

---

## Which Should You Use?

**Use Option 1 (`apply-security-updates.sh`) if:**
- You want full control over when updates run
- You prefer a simple script over system services
- You want to schedule via cron

**Use Option 2 (`unattended-upgrades`) if:**
- You want automatic updates (no cron needed)
- You prefer system services over scripts
- You want updates to run automatically via systemd

**Note:** You can use both, but that's usually unnecessary and may cause conflicts.

