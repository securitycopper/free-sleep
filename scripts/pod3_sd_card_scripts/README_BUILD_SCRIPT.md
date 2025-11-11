# opensleep Build Script

A comprehensive script for building and updating opensleep directly on the Eight Sleep Pod 3.

## Features

- **Intelligent Detection**: Automatically detects what's already installed
- **Idempotent**: Can be run multiple times safely
- **Dual Purpose**: Handles both initial setup and updates
- **Automatic Backups**: Creates backups before installing new binaries
- **Rollback Support**: Automatically restores backup if new build fails
- **Service Management**: Handles service stop/start automatically
- **Logging**: Comprehensive logging to `/var/log/opensleep_build.log`

## Quick Start

### Initial Setup and Build

SSH into your Pod and run:

```bash
cd /opt
curl -O https://raw.githubusercontent.com/securitycopper/opensleep/main/scripts/full_patch_workflow_build_latest.sh
chmod +x full_patch_workflow_build_latest.sh
./full_patch_workflow_build_latest.sh
```

### Update to Latest Version

Simply run the script again:

```bash
cd /opt
./full_patch_workflow_build_latest.sh
```

## Usage

```bash
./full_patch_workflow_build_latest.sh [options]
```

### Options

| Option | Description |
|--------|-------------|
| `-f`, `--force-setup` | Force re-installation of Rust and dependencies |
| `-c`, `--clean` | Clean build (removes target directory) |
| `-s`, `--skip-build` | Skip the build step (setup only) |
| `-d`, `--debug` | Build in debug mode (faster compilation) |
| `-n`, `--no-install` | Build but don't install the binary |
| `-b`, `--branch BRANCH` | Checkout specific branch (default: main) |
| `-r`, `--repo URL` | Use custom repository URL |
| `-h`, `--help` | Show help message |

## Examples

### Standard Update
```bash
./full_patch_workflow_build_latest.sh
```

### Force Clean Rebuild
```bash
./full_patch_workflow_build_latest.sh --clean
```

### Build Specific Branch
```bash
./full_patch_workflow_build_latest.sh --branch issue_6
```

### Setup Only (No Build)
```bash
./full_patch_workflow_build_latest.sh --skip-build
```

### Debug Build (Faster Compilation)
```bash
./full_patch_workflow_build_latest.sh --debug
```

### Build Without Installing
```bash
./full_patch_workflow_build_latest.sh --no-install
```

### Use Custom Repository
```bash
./full_patch_workflow_build_latest.sh --repo https://github.com/yourusername/opensleep-fork.git
```

## What the Script Does

### On First Run (Initial Setup)

1. **System Check**: Verifies disk space (needs ~2GB)
2. **Rust Installation**: Installs Rust toolchain via rustup
3. **Dependencies**: Installs git and other required packages
4. **Clone Repository**: Clones opensleep from GitHub
5. **Build**: Compiles the project (takes 30-60 minutes)
6. **Install**: Installs the binary and manages the service

### On Subsequent Runs (Updates)

1. **System Check**: Verifies disk space (needs ~500MB)
2. **Update Rust**: Updates to latest stable version
3. **Update Repository**: Pulls latest changes from GitHub
4. **Build**: Compiles the updated code (faster due to incremental builds)
5. **Backup**: Creates backup of current binary
6. **Install**: Installs new binary
7. **Service Management**: Restarts service if it was running
8. **Verification**: Checks if service started successfully
9. **Rollback**: Automatically restores backup if new version fails

## Detection Logic

The script intelligently detects:
- ✅ Rust installation status
- ✅ Git installation status
- ✅ Repository clone status
- ✅ Current opensleep version
- ✅ Service running status
- ✅ Available disk space

## Backup Management

- Backups are stored in `/opt/opensleep_backup/`
- Format: `opensleep.YYYYMMDD_HHMMSS`
- Keeps last 5 backups automatically
- Used for automatic rollback on failure

## Logging

All operations are logged to `/var/log/opensleep_build.log`

View the log:
```bash
cat /var/log/opensleep_build.log
tail -f /var/log/opensleep_build.log
```

## Service Management

The script automatically:
- Detects if opensleep service is running
- Stops service before installation
- Starts service after installation
- Verifies service started successfully
- Rolls back if service fails to start

Manual service commands:
```bash
# Check status
systemctl status opensleep

# Start service
systemctl start opensleep

# Stop service
systemctl stop opensleep

# Restart service
systemctl restart opensleep

# View logs
journalctl -u opensleep -f
```

## Troubleshooting

### Out of Space

Clean up old artifacts:
```bash
cd /opt/opensleep
cargo clean
```

Or clean Rust cache:
```bash
rm -rf ~/.cargo/registry/cache
```

### Build Fails

Try a clean build:
```bash
./full_patch_workflow_build_latest.sh --clean
```

### Service Won't Start

Check logs:
```bash
journalctl -u opensleep -n 50 --no-pager
```

Restore from backup manually:
```bash
ls -lh /opt/opensleep_backup/
cp /opt/opensleep_backup/opensleep.YYYYMMDD_HHMMSS /opt/opensleep/opensleep
chmod +x /opt/opensleep/opensleep
systemctl start opensleep
```

### Git Issues

If repository is corrupted:
```bash
rm -rf /opt/opensleep
./full_patch_workflow_build_latest.sh
```

### Rust Issues

Force reinstall Rust:
```bash
./full_patch_workflow_build_latest.sh --force-setup
```

## Automated Updates

### Using Cron

Schedule automatic updates (runs weekly at 3 AM Sunday):

```bash
crontab -e
```

Add this line:
```cron
0 3 * * 0 /opt/full_patch_workflow_build_latest.sh >> /var/log/opensleep_auto_update.log 2>&1
```

Or for daily updates at 3 AM:
```cron
0 3 * * * /opt/full_patch_workflow_build_latest.sh >> /var/log/opensleep_auto_update.log 2>&1
```

### Using Systemd Timer

Create a timer service for more control:

```bash
# Create timer unit
cat > /etc/systemd/system/opensleep-update.timer <<EOF
[Unit]
Description=opensleep Update Timer
Requires=opensleep-update.service

[Timer]
OnCalendar=Sun *-*-* 03:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Create service unit
cat > /etc/systemd/system/opensleep-update.service <<EOF
[Unit]
Description=opensleep Update Service
After=network.target

[Service]
Type=oneshot
ExecStart=/opt/full_patch_workflow_build_latest.sh
StandardOutput=journal
StandardError=journal
EOF

# Enable and start timer
systemctl daemon-reload
systemctl enable opensleep-update.timer
systemctl start opensleep-update.timer

# Check timer status
systemctl list-timers opensleep-update.timer
```

## Best Practices

1. **Test Before Automating**: Run the script manually a few times before setting up automatic updates
2. **Monitor Logs**: Check logs after updates to ensure everything works
3. **Keep Backups**: The script keeps 5 backups automatically, but consider additional backups for important configurations
4. **Use Release Builds**: Debug builds are faster to compile but slower to run
5. **Schedule Wisely**: Run updates during off-peak hours (e.g., 3 AM)
6. **Monitor Service**: Set up monitoring to alert if service stops

## Resource Usage

During build:
- **CPU**: 100% utilization
- **Memory**: ~500MB-1GB
- **Storage**: ~2GB for initial setup, ~500MB for updates
- **Time**: 30-60 minutes (first build), 5-15 minutes (updates)

## Security Notes

- Script must be run as root for service management
- Pulls code from GitHub (ensure HTTPS)
- Creates backups before installing
- Automatic rollback on failure

## Related Documentation

- [Pod Native Build Guide](../docs/guides/pod_native_build_guide.md)
- [WSL Build Guide](../docs/guides/wsl_build_guide.md)
- [SETUP.md](../SETUP.md)
- [MQTT.md](../MQTT.md)

## Support

For issues or questions:
- GitHub Issues: https://github.com/securitycopper/opensleep/issues
- Check logs: `/var/log/opensleep_build.log`
- Service logs: `journalctl -u opensleep -f`
