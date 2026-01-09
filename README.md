# Linux Security Updates - Automated Patching System

This repository contains scripts to apply security updates on Debian/Ubuntu systems with flexible configuration options, maintenance windows, and support for both security-only and all updates, with or without reboots.

## Overview

The system provides three approaches to patching:

1. **Manual Script** - Run updates manually or via cron with simple configuration
2. **Scheduler System** - Automated updates with maintenance windows and profiles (recommended)
3. **unattended-upgrades** - Configuration for the system's built-in unattended-upgrades service

All scripts support configurable logging (standard, syslog, ISO 8601, Datadog JSON) and flexible package filtering.

## Quick Start

### Option 1: Manual Script (`apply-security-updates.sh`)

Simple manual script that can be run on-demand or scheduled via cron.

1. **Copy and configure:**
   ```bash
   cp config.conf.example config.conf
   # Edit config.conf with your preferences
   ```

2. **Run manually:**
   ```bash
   sudo ./apply-security-updates.sh
   ```

3. **Schedule via cron (optional):**
   ```bash
   sudo crontab -e
   # Add: 0 2 * * * /full/path/to/apply-security-updates.sh
   ```

### Option 2: Scheduler System (Recommended)

Automated updates with maintenance windows, profiles, and flexible scheduling.

1. **Install files:**
   ```bash
   # Copy scripts to system location (or keep in repo directory)
   sudo mkdir -p /usr/local/bin/security-updates
   sudo cp apply-security-updates.sh scheduler.sh /usr/local/bin/security-updates/
   sudo chmod +x /usr/local/bin/security-updates/*.sh
   
   # Copy config templates
   sudo mkdir -p /etc/security-updates/profiles
   sudo cp config.conf.example /etc/security-updates/config.conf
   sudo cp scheduler.conf.example /etc/security-updates/scheduler.conf
   sudo cp profiles/*.conf /etc/security-updates/profiles/
   ```

2. **Configure scheduler:**
   ```bash
   sudo nano /etc/security-updates/scheduler.conf
   ```
   
   Enable a maintenance window, for example:
   ```bash
   ENABLE_WEEKLY_SUNDAY=true
   WEEKLY_SUNDAY_START_TIME="02:00"
   WEEKLY_SUNDAY_END_TIME="04:00"
   WEEKLY_SUNDAY_PROFILE="security-no-reboot"
   ```

3. **Install systemd service:**
   ```bash
   sudo cp systemd/security-updates.service /etc/systemd/system/
   sudo cp systemd/security-updates.timer /etc/systemd/system/
   
   # Update service file paths if needed
   sudo nano /etc/systemd/system/security-updates.service
   
   # Enable and start
   sudo systemctl daemon-reload
   sudo systemctl enable security-updates.timer
   sudo systemctl start security-updates.timer
   ```

4. **Check status:**
   ```bash
   sudo systemctl status security-updates.timer
   sudo systemctl list-timers security-updates.timer
   ```

### Option 3: unattended-upgrades

Configure the system's built-in `unattended-upgrades` service.

```bash
sudo ./unattended-upgrades-config.sh
```

**Note:** The `unattended-upgrades` package includes systemd timers - no cron needed. The script only configures the service behavior.

## Architecture

### Manual Script (`apply-security-updates.sh`)

- Standalone script, completely independent
- Reads configuration from `config.conf` (or `/etc/security-updates/config.conf`)
- Can be run manually or scheduled via cron
- Supports multiple log formats (standard, color, syslog, ISO, Datadog JSON)
- Configurable update type (security-only or all updates)
- Package filtering via `SKIP_PACKAGES` and `ALLOW_REBOOT_PACKAGES`

### Scheduler System (`scheduler.sh`)

- Wrapper around `apply-security-updates.sh`
- Handles maintenance window detection and profile selection
- Reads configuration from `scheduler.conf` (or `/etc/security-updates/scheduler.conf`)
- Loads profile configs from `profiles/` directory
- Supports preconfigured maintenance windows:
  - Patch Tuesday (2nd Tuesday of month) - separate windows for non-prod/prod
  - Weekly windows (Sunday/Saturday)
  - Daily early morning window
  - Monthly first Sunday extended window
- Supports custom maintenance windows
- Handles reboots with configurable delay and confirmation
- Logs scheduler decisions for debugging

### unattended-upgrades

- Uses system's built-in `unattended-upgrades` package
- Configured via `/etc/apt/apt.conf.d/` files
- Runs automatically via systemd timers (included with package)
- Package blacklisting to skip reboot-required packages

## Configuration Files

### Main Config (`config.conf`)

Controls the behavior of `apply-security-updates.sh`:

- **Logging**: Format (`standard`, `color`, `syslog`, `iso`, `datadog`), log file path, Datadog settings
- **Updates**: Update type (`security` or `all`), package filtering
- **Reboot**: Control reboot-required package installation and behavior
- **Notifications**: Pre/post-update notification commands

See `config.conf.example` for all options with detailed comments.

### Scheduler Config (`scheduler.conf`)

Controls the scheduler system:

- **Scheduling**: Check interval, random delay, timezone
- **Maintenance Windows**: Enable/disable preconfigured windows, define custom windows
- **Profiles**: Default profile, profiles directory
- **Reboot**: Auto-reboot settings, delay, confirmation
- **Notifications**: Pre-maintenance and post-update notifications

See `scheduler.conf.example` for all options with detailed comments.

### Profile Configs (`profiles/*.conf`)

Define update behavior for different scenarios:

- **`security-no-reboot.conf`** - Security updates only, skip reboot-required packages (default)
- **`security-with-reboot.conf`** - Security updates, allow reboot-required packages
- **`all-no-reboot.conf`** - All updates, skip reboot-required packages
- **`all-with-reboot.conf`** - All updates, allow reboot-required packages

Each profile can override settings from the main config:
- `UPDATE_TYPE` - "security" or "all"
- `ALLOW_REBOOT_PACKAGES` - true/false
- Any other settings from `config.conf`

## Maintenance Windows

### Preconfigured Windows

Enable these in `scheduler.conf`:

1. **Patch Tuesday (Non-Prod)**
   - 2nd Tuesday of month, 20:00-23:00
   - Typically uses `security-with-reboot` profile

2. **Patch Tuesday (Prod)**
   - 2nd Tuesday of month, 02:00-05:00
   - Typically uses `security-with-reboot` profile

3. **Weekly Sunday**
   - Every Sunday, configurable time window
   - Default: 02:00-04:00

4. **Weekly Saturday**
   - Every Saturday, configurable time window
   - Default: 02:00-04:00

5. **Daily Early Morning**
   - Every day, early morning window
   - Default: 02:00-04:00

6. **Monthly First Sunday**
   - First Sunday of month, extended window
   - Default: 01:00-06:00

### Custom Windows

Define custom windows in `scheduler.conf`:

```bash
CUSTOM_WINDOWS=(
    "weekday|Monday|18:00|22:00|security-no-reboot"
    "date|2026-01-15|03:00|05:00|security-with-reboot"
    "weekly|Wednesday|01:00|03:00|all-no-reboot"
)
```

Format: `TYPE|MATCH|START|END|PROFILE`
- `TYPE`: `weekday`, `date`, `weekly`, `monthly`
- `MATCH`: Day name, date (YYYY-MM-DD), or day pattern
- `START`/`END`: Time in HH:MM format
- `PROFILE`: Profile name (without .conf extension)

## Profiles

Profiles allow different update strategies for different maintenance windows:

**Example:** Use `security-no-reboot` for daily automatic updates, but `security-with-reboot` during monthly maintenance windows.

Create custom profiles by copying a template:
```bash
cp profiles/security-no-reboot.conf profiles/custom-profile.conf
# Edit custom-profile.conf
```

Reference it in maintenance windows:
```bash
WEEKLY_SUNDAY_PROFILE="custom-profile"
```

## Logging

### Log Formats

Configure `LOG_FORMAT` in `config.conf`:

- **`standard`** - Plain text: `2026-01-05 13:27:05 [INFO] message`
- **`color`** - With ANSI color codes (harder to parse)
- **`syslog`** - Syslog format: `Jan  5 13:27:05 hostname script: [INFO] message`
- **`iso`** - ISO 8601: `2026-01-05T13:27:05+00:00 [INFO] message`
- **`datadog`** - Datadog JSON format (ndjson)

### Log Locations

- Main updates: `/var/log/security-updates.log` (configurable)
- Scheduler: `/var/log/security-updates-scheduler.log` (configurable)

### Datadog Integration

Set `LOG_FORMAT="datadog"` and configure:
- `DATADOG_SERVICE` - Service name
- `DATADOG_SOURCE` - Source/application name
- `DATADOG_ENV` - Environment tag
- `DATADOG_HOST` - Hostname (empty = auto-detect)

Logs are written in Datadog JSON format suitable for direct ingestion.

## Package Filtering

### Updating Specific Packages Only

To update only specific packages (e.g., nginx):

1. **In `config.conf` or a profile:**
   ```bash
   ALLOW_PACKAGES=(
       "nginx"
   )
   UPDATE_TYPE="all"  # or "security"
   ```

2. **Or create a custom profile:**
   ```bash
   cp profiles/single-package-template.conf profiles/nginx-only.conf
   # Edit nginx-only.conf to set ALLOW_PACKAGES=("nginx")
   ```

3. **Use the profile in scheduler:**
   ```bash
   # In scheduler.conf:
   DEFAULT_PROFILE="nginx-only"
   # Or assign to a maintenance window
   ```

**Example:** Update only nginx:
- The script will only check for and update nginx
- All other packages are ignored
- SKIP_PACKAGES filtering still applies (unless `ALLOW_REBOOT_PACKAGES=true`)
- If nginx requires reboot and `ALLOW_REBOOT_PACKAGES=false`, nginx will still be skipped

**Multiple packages:**
```bash
ALLOW_PACKAGES=(
    "nginx"
    "apache2"
    "mysql-server"
)
```

### Skipping Reboot-Required Packages

To prevent installation of reboot-required packages:

1. **In `config.conf`:**
   ```bash
   ALLOW_REBOOT_PACKAGES=false
   ```

2. **Or add to `SKIP_PACKAGES` array:**
   ```bash
   SKIP_PACKAGES=(
       "linux-image-.*"
       "linux-headers-.*"
       "^libc6$"
   )
   ```

**Important:** `SKIP_PACKAGES` is the mechanism that prevents installation. `CHECK_REBOOT_REQUIRED` and `WARN_ON_REBOOT_REQUIRED` only check *after* installation.

**Note:** If `ALLOW_PACKAGES` is set, it acts as a whitelist - only those packages are considered. `SKIP_PACKAGES` filtering still applies to the whitelist (unless `ALLOW_REBOOT_PACKAGES=true`).

### Common Patterns

Default skipped packages (if `ALLOW_REBOOT_PACKAGES=false`):
- Kernel packages: `linux-image-*`, `linux-headers-*`, `linux-modules-*`
- Critical libraries: `libc6`, `libc6-dev`
- System services: `systemd`, `systemd-sysv`, `dbus`

## Reboot Handling

### Automatic Reboots

Configure in `scheduler.conf`:
```bash
AUTO_REBOOT_IF_REQUIRED=true
REBOOT_DELAY_MINUTES=5
REBOOT_REQUIRES_CONFIRMATION=false
```

The scheduler will:
1. Wait for the delay period
2. Check if confirmation is required
3. If confirmed (or not required), reboot the system

### Manual Reboot Check

Check if a reboot is required:
```bash
if [ -f /var/run/reboot-required ]; then
    echo "Reboot required for:"
    cat /var/run/reboot-required.pkgs
fi
```

## Scripts Overview

| Script | Purpose | When to Use |
|--------|---------|-------------|
| `apply-security-updates.sh` | Core update script | Manual runs, cron jobs, or called by scheduler |
| `scheduler.sh` | Maintenance window wrapper | Automated scheduling via systemd timer |
| `check-patch-status.sh` | Status checker | Quick verification of patch status |
| `show-config.sh` | Configuration viewer | Display all active patching configuration |
| `check-unattended-timer.sh` | Timer diagnostic | Troubleshooting unattended-upgrades |
| `unattended-upgrades-config.sh` | Config generator | One-time setup for unattended-upgrades |

## Checking Status

### Configuration Overview

View all active patching configuration:

```bash
./show-config.sh
```

Shows:
- Config file locations (main, scheduler, profiles)
- Active configuration settings
- Maintenance windows enabled
- Current active profile (if scheduler enabled)
- Systemd timer/service status
- Logging configuration
- Update type and reboot settings
- Notification settings

### Patch Status

```bash
./check-patch-status.sh
# or with sudo to see pending updates:
sudo ./check-patch-status.sh
```

Shows:
- Last successful patch time
- Days since last patch
- List of packages from last update
- Pending security updates
- Reboot status
- System uptime

### Scheduler Status

```bash
sudo systemctl status security-updates.timer
sudo systemctl list-timers security-updates.timer
sudo journalctl -u security-updates.service -n 50
```

### Unattended-Upgrades Status

```bash
./check-unattended-timer.sh
# or manually:
systemctl status unattended-upgrades.timer
systemctl list-timers apt-daily.timer apt-daily-upgrade.timer
```

## Live Patching (Optional)

For kernel security patches without reboots:

### Ubuntu Livepatch

Free for up to 3 machines:
```bash
sudo pro enable livepatch
```

### Debian Live Patching

1. **kpatch** (open source, manual setup):
   ```bash
   sudo apt-get install kpatch kpatch-build
   ```
   Requires building patches from source.

2. **KernelCare** (commercial, managed service):
   Third-party service providing live kernel patching for Debian (subscription required).

**Note:** Live patching only covers kernel vulnerabilities. System libraries (like `libc6`) still require reboots for some updates.

## Files Structure

```
linux-patching/
├── apply-security-updates.sh      # Core update script
├── scheduler.sh                    # Scheduler wrapper
├── check-patch-status.sh           # Status checker
├── show-config.sh                  # Configuration viewer
├── check-unattended-timer.sh       # Timer diagnostic
├── unattended-upgrades-config.sh   # unattended-upgrades config
├── config.conf.example             # Main config template
├── scheduler.conf.example          # Scheduler config template
├── profiles/                       # Profile configs
│   ├── security-no-reboot.conf
│   ├── security-with-reboot.conf
│   ├── all-no-reboot.conf
│   └── all-with-reboot.conf
├── systemd/                        # Systemd unit files
│   ├── security-updates.service
│   └── security-updates.timer
└── README.md                       # This file
```

## Installation Paths

For system-wide installation:

```bash
# Scripts
/usr/local/bin/security-updates/

# Config files
/etc/security-updates/
/etc/security-updates/profiles/

# Systemd units
/etc/systemd/system/security-updates.service
/etc/systemd/system/security-updates.timer

# Logs
/var/log/security-updates.log
/var/log/security-updates-scheduler.log
```

## Troubleshooting

### Scheduler Not Running

1. Check timer status:
   ```bash
   sudo systemctl status security-updates.timer
   ```

2. Check service logs:
   ```bash
   sudo journalctl -u security-updates.service -n 100
   ```

3. Verify config file:
   ```bash
   sudo bash -n /usr/local/bin/security-updates/scheduler.sh
   ```

### Updates Not Applying

1. Check for pending updates:
   ```bash
   sudo apt update
   sudo apt list --upgradable
   ```

2. Check package filtering:
   ```bash
   # Review SKIP_PACKAGES in config.conf
   cat /etc/security-updates/config.conf | grep SKIP_PACKAGES
   ```

3. Run manually with debug:
   ```bash
   sudo bash -x /usr/local/bin/security-updates/apply-security-updates.sh
   ```

### Profile Not Loading

1. Verify profile exists:
   ```bash
   ls -la /etc/security-updates/profiles/
   ```

2. Check scheduler config:
   ```bash
   grep PROFILE /etc/security-updates/scheduler.conf
   ```

3. Enable scheduler decision logging:
   ```bash
   # In scheduler.conf:
   LOG_SCHEDULER_DECISIONS=true
   ```

## Requirements

- Debian or Ubuntu system
- Root/sudo access
- Internet connection for package updates
- `bash` 4.0+ (for associative arrays in scheduler)
- `systemd` (for scheduler timer, not required for manual/cron usage)

## Notes

- **Security Considerations**: Skipping kernel updates means critical security patches may not be applied until you manually reboot. Consider using live patching solutions.
- **Testing**: Always test on a non-production system first.
- **Monitoring**: Regularly review logs and check for reboot requirements.
- **Maintenance Windows**: Ensure maintenance windows don't conflict with critical system operations.

## Testing

A Docker-based testing framework is available for automated testing of scripts and configurations.

### Quick Start

```bash
# Run all tests
make test
# or
./test/run-tests.sh all

# Run specific test suite
make test-syntax
make test-config
make test-profiles

# Interactive testing
make test-interactive
```

### Test Framework

The testing framework includes:
- **Syntax validation** - Checks all scripts for bash syntax errors
- **Configuration loading** - Tests config file loading and default values
- **Profile validation** - Verifies all profiles load correctly
- **Package filtering** - Tests `ALLOW_PACKAGES` and `SKIP_PACKAGES` logic
- **Scheduler logic** - Tests maintenance window matching and profile selection
- **Integration scenarios** - End-to-end tests for common use cases

See `test/README.md` for detailed documentation.

### Running Tests

```bash
# Using Makefile (recommended)
make test                 # Run all tests
make test-syntax          # Syntax checking only
make test-interactive     # Interactive container

# Using test runner directly
./test/run-tests.sh all   # Run all tests
./test/run-tests.sh interactive  # Interactive mode
```

### Test Scenarios

Individual test scenarios in `test/scenarios/`:
- `test-nginx-only.sh` - Tests single package updates (nginx)
- `test-security-only.sh` - Tests security-only profile
- `test-scheduler-profile-selection.sh` - Tests scheduler profile selection

## License

This is provided as-is for system administration purposes.
