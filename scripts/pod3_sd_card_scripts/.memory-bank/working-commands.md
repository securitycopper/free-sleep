# Known Working Commands for Pod 3 Testing

## Date: November 9, 2025
## Hardware: Eight Sleep Pod 3 (frankenfirmware)
## Network: Static IP 192.168.2.52/24, Gateway 192.168.2.1

---

## DNS Resolution Fix (CRITICAL)

### Problem
`/etc/resolv.conf` points to NetworkManager (broken symlink):
```bash
/etc/resolv.conf -> /etc/resolv-conf.NetworkManager -> ../run/NetworkManager/resolv.conf
```

### Solution (Validated on Live Hardware)
```bash
# Remove broken symlink
sudo rm -f /etc/resolv.conf

# Create correct symlink to systemd-resolved
sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf

# Verify DNS is working
cat /etc/resolv.conf
# Should show: nameserver 192.168.2.1

# Test DNS resolution
nslookup raw.githubusercontent.com
# Should return: 185.199.110.133, 185.199.111.133, etc.

# Test GitHub connectivity
curl -fsSL https://raw.githubusercontent.com/throwaway31265/free-sleep/main/README.md | head -5
```

**Status**: ✅ VALIDATED - Works perfectly on live hardware

---

## Eight Sleep Services Management

### Check Service Status
```bash
# Check all Eight Sleep services
sudo systemctl status capybara dac swupdate swupdate-progress defibrillator 2>&1 | grep -A 2 "Loaded:\|Active:"

# Check specific service
sudo systemctl status capybara --no-pager
```

### Disable Services (Prevents Race Condition)
```bash
# Disable and stop immediately
sudo systemctl disable --now swupdate swupdate-progress defibrillator

# Mask to prevent re-enabling
sudo systemctl mask swupdate swupdate-progress defibrillator capybara dac

# Verify they're masked
systemctl list-unit-files | grep -E "capybara|dac|swupdate|defibrillator"
```

**Status**: ✅ VALIDATED - All services inactive (dead) and masked

---

## FreeSleep Installation

### Manual Installation Trigger
```bash
# Remove stale flag if exists
sudo rm -f /var/lib/freesleep-installed.flag

# Manually start the installer service
sudo systemctl start freesleep-installer.service

# Follow logs in real-time
sudo journalctl -u freesleep-installer.service -f --no-pager
```

### Check Installation Progress
```bash
# Check service status
sudo systemctl status freesleep-installer.service --no-pager

# Check recent logs
sudo journalctl -u freesleep-installer.service --no-pager -n 50

# Check running processes
ps aux | grep -E "(npm|node|install)" | grep -v grep

# Check installation steps completed
tail -50 /var/log/freesleep-install.log
```

### Verify Installation Success
```bash
# Check flag file created
ls -la /var/lib/freesleep-installed.flag

# Check FreeSleep directory exists
ls -la /opt/freesleep/ 2>&1 || ls -la /home/dac/free-sleep/

# Check service status after reboot
sudo systemctl status free-sleep.service --no-pager

# Test web UI locally
curl -s http://localhost:3000 | head -20

# Check Franken connection to dac.sock
sudo journalctl -u free-sleep.service --no-pager | grep "dac.sock"
```

**Status**: ✅ VALIDATED - Installation completed successfully, service running

---

## Boot Sequence Analysis

### Check Boot Count and History
```bash
# List all boots
journalctl --list-boots --no-pager

# Check system uptime
uptime

# Check when system booted
who -b
```

### Check Service Execution in Specific Boot
```bash
# Check if service ran in Boot 0
sudo journalctl -b 0 -u disable-eightsleep-services.service --no-pager

# Check if service ran in Boot -1
sudo journalctl -b -1 -u freesleep-installer.service --no-pager

# Check all systemd services in current boot
sudo journalctl -b 0 --no-pager | grep "Started\|Starting" | head -30
```

### Check Boot Target Status
```bash
# Check multi-user.target status
sudo systemctl status multi-user.target --no-pager

# Check network-online.target status
sudo systemctl status network-online.target --no-pager

# Check basic.target status
sudo systemctl status basic.target --no-pager

# List all active targets
sudo systemctl list-units --type=target --state=active --no-pager
```

**Key Discovery**: multi-user.target is NEVER reached on Pod 3 (stays "inactive (dead)")

---

## Flag Files Management

### Check All Flag Files
```bash
# List all flag files
ls -la /var/lib/*.flag

# Check specific flags
ls -la /var/lib/firstboot-complete.flag
ls -la /var/lib/eightsleep-disabled.flag
ls -la /var/lib/freesleep-installed.flag
```

### Remove Stale Flags (Testing Only)
```bash
# Remove freesleep-installed flag to re-test installation
sudo rm -f /var/lib/freesleep-installed.flag

# Remove eightsleep-disabled flag to re-test service disabling
sudo rm -f /var/lib/eightsleep-disabled.flag

# Verify removal
ls -la /var/lib/*.flag
```

---

## Network Configuration

### Check Network Status
```bash
# Check IP configuration
ip addr show

# Check default route
ip route show

# Check DNS configuration
cat /etc/resolv.conf

# Test DNS resolution
nslookup google.com
nslookup raw.githubusercontent.com
```

### Static IP Configuration (Applied at Build Time)
```bash
# In full_patch_workflow.sh:
./full_patch_workflow.sh \
  -i original-image.img \
  -k ~/.ssh/id_rsa.pub \
  -s "ZyXEL046080" \
  -p "wifi-password" \
  -m "c0:ee:40:8c:ff:76" \
  -I "192.168.2.52/24" \
  -G "192.168.2.1" \
  -D "192.168.2.1,8.8.8.8,8.8.4.4" \
  -f -d
```

---

## FreeSleep Service Management

### Check FreeSleep Status
```bash
# Service status
sudo systemctl status free-sleep.service --no-pager

# Recent logs (last 50 lines)
sudo journalctl -u free-sleep.service --no-pager -n 50

# Follow logs in real-time
sudo journalctl -u free-sleep.service -f --no-pager

# Check log output format
journalctl -u free-sleep --no-pager --output=cat | tail -20
```

### Start/Stop/Restart FreeSleep
```bash
# Start service
sudo systemctl start free-sleep.service

# Stop service
sudo systemctl stop free-sleep.service

# Restart service
sudo systemctl restart free-sleep.service

# Enable at boot
sudo systemctl enable free-sleep.service
```

### Web UI Access
```bash
# From Pod 3 (localhost)
curl http://localhost:3000

# From external device (Windows PC)
# Browser: http://192.168.2.52:3000
```

---

## Passwordless Sudo

### Test Passwordless Sudo
```bash
# Test if sudo works without password
sudo -n true
echo $?
# Should return: 0 (success)

# Test with actual command
sudo -n systemctl status free-sleep --no-pager
```

### Configuration
```bash
# Check sudoers configuration
sudo cat /etc/sudoers.d/rewt-nopasswd
# Should contain: rewt ALL=(ALL) NOPASSWD: ALL

# Check file permissions
ls -la /etc/sudoers.d/rewt-nopasswd
# Should be: -r--r----- (0440)
```

**Status**: ✅ VALIDATED - Passwordless sudo working

---

## Validation Script Usage

### Run Comprehensive Validation
```bash
# SSH to Pod 3
ssh -p 8822 rewt@192.168.2.52

# Run validation script (if copied to device)
./validate_deployment.sh

# Or run manual checks
echo "=== DNS Check ==="
nslookup raw.githubusercontent.com

echo "=== Service Status ==="
sudo systemctl status free-sleep.service --no-pager | head -15

echo "=== Eight Sleep Services ==="
sudo systemctl status capybara dac swupdate defibrillator 2>&1 | grep "Active:"

echo "=== Flag Files ==="
ls -la /var/lib/*.flag

echo "=== Web UI Check ==="
curl -s http://localhost:3000 | head -10
```

---

## Troubleshooting Commands

### Check systemd Service Files
```bash
# View service configuration
sudo systemctl cat firstboot-reboot.service
sudo systemctl cat disable-eightsleep-services.service
sudo systemctl cat freesleep-installer.service
sudo systemctl cat free-sleep.service

# Check where service is enabled
sudo systemctl show firstboot-reboot.service | grep WantedBy
sudo systemctl show disable-eightsleep-services.service | grep WantedBy
sudo systemctl show freesleep-installer.service | grep WantedBy
```

### Check Service Dependencies
```bash
# List what service depends on
sudo systemctl list-dependencies disable-eightsleep-services.service

# List what depends on service
sudo systemctl list-dependencies disable-eightsleep-services.service --reverse

# Show all properties
sudo systemctl show disable-eightsleep-services.service
```

### Check Disk Space
```bash
# Check available space
df -h

# Check directory sizes
du -sh /home/dac/free-sleep/*
du -sh /opt/*
```

### Check Memory Usage
```bash
# Overall memory
free -h

# Process memory
ps aux --sort=-%mem | head -10

# Service memory
sudo systemctl status free-sleep.service --no-pager | grep Memory
```

---

## Expected Boot Sequence (4 Boots)

### Boot -3: Factory Reset
```
Factory reset extracts rootfs.tar.gz to SD card
System continues running with old filesystem in memory
Manual reboot required to load new filesystem
```

### Boot -2: First Boot After Reset
```
firstboot-reboot.service detects first boot
Creates /var/lib/firstboot-complete.flag
Triggers immediate reboot
(sysinit.target)
```

### Boot -1: Disable Eight Sleep Services
```
disable-eightsleep-services.service runs
Disables and masks Eight Sleep services
Creates /var/lib/eightsleep-disabled.flag
Automatic reboot
(basic.target)
```

### Boot 0: Install FreeSleep
```
freesleep-installer.service runs
Waits for DNS (max 120 seconds)
Downloads install.sh from GitHub
Installs Node.js, npm packages, Prisma migration
Creates free-sleep.service
Creates /var/lib/freesleep-installed.flag
Triggers reboot
(network-online.target)
```

### Boot 1: FreeSleep Running
```
free-sleep.service starts automatically
Web UI accessible at http://192.168.2.52:3000
Franken connected to /deviceinfo/dac.sock
System ready for use
```

**Total Time**: ~15-20 minutes from factory reset to fully operational

---

## Common Issues and Solutions

### Issue: DNS Resolution Fails
**Symptom**: `nslookup` returns "can't resolve host"
**Cause**: `/etc/resolv.conf` points to NetworkManager (broken symlink)
**Solution**: Apply DNS fix (see above)

### Issue: Services Never Run
**Symptom**: `journalctl -b 0 -u <service>` shows "No entries"
**Cause**: Service configured for multi-user.target (never reached)
**Solution**: Move service to basic.target or network-online.target

### Issue: Eight Sleep Services Still Running
**Symptom**: capybara, dac, swupdate active
**Cause**: disable-eightsleep-services.service didn't run (wrong target)
**Solution**: Manually disable with `systemctl disable --now` and `systemctl mask`

### Issue: FreeSleep Installation Hangs
**Symptom**: Installation gets stuck at "Waiting for DNS"
**Cause**: DNS resolution not working
**Solution**: Fix DNS first (see DNS Resolution Fix above)

### Issue: Race Condition with Update Services
**Symptom**: System reboots during installation
**Cause**: swupdate/defibrillator detect changes and trigger reboot
**Solution**: Disable services BEFORE making filesystem changes (use basic.target with Before= directives)

### Issue: Flag File Exists But Service Didn't Run
**Symptom**: `/var/lib/freesleep-installed.flag` exists but `/opt/freesleep/` doesn't
**Cause**: Stale flag from previous test
**Solution**: Remove flag with `sudo rm -f /var/lib/freesleep-installed.flag`

---

## Key Learnings

1. **Pod 3 Boot Behavior is Unique**
   - multi-user.target is NEVER reached
   - Use sysinit.target, basic.target, or network-online.target instead
   - Always verify boot targets with `systemctl status <target>`

2. **DNS Configuration Must Be Fixed**
   - resolv.conf NetworkManager symlink is broken
   - Point to systemd-resolved: `/run/systemd/resolve/resolv.conf`
   - Test DNS before attempting GitHub downloads

3. **Service Ordering is Critical**
   - Use `Before=` directives to enforce ordering
   - Use `DefaultDependencies=no` for early execution
   - Disable Eight Sleep services BEFORE they can detect changes

4. **Eight Sleep Services Are Aggressive**
   - swupdate and defibrillator trigger reboots within seconds
   - Always disable/mask them early in boot sequence
   - Use `systemctl mask` for strongest protection

5. **Validation is Essential**
   - Test on actual hardware (emulators won't show boot quirks)
   - Create test scripts for rapid diagnosis
   - Check logs, status, flags, and processes at each step

---

## Manual Installation Success Log

**Date**: November 10, 2025 04:27-04:33 UTC  
**Method**: Manual trigger of freesleep-installer.service  
**Result**: ✅ SUCCESS

**Timeline**:
```
04:27:00 - Started manual installation
04:28:30 - Node.js 24.11.0 installed via Volta
04:29:22 - npm install started
04:31:10 - Prisma migrations completed
04:31:11 - free-sleep.service created and started
04:31:12 - Installation complete, reboot triggered
04:31:27 - System rebooted (Boot 2)
04:31:27 - free-sleep.service started automatically
04:33:49 - Validation complete: Web UI accessible
```

**Validation Results**:
- ✅ DNS resolution: Working (nslookup successful)
- ✅ Eight Sleep services: All masked and inactive
- ✅ FreeSleep service: Active (running) with 173MB memory
- ✅ Franken server: Connected to /deviceinfo/dac.sock
- ✅ Web UI: Accessible at http://192.168.2.52:3000
- ✅ Flag files: firstboot-complete and freesleep-installed present
- ✅ Boot count: 3 boots (factory reset, installer, running)

**Key Success Factors**:
1. DNS fix applied manually before installation
2. Eight Sleep services disabled manually before installation
3. network-online.target configuration allows service to run
4. Manual trigger bypassed any multi-user.target issues

---

## Script Updates Based on Discoveries

### File: `scripts/install.sh` (Updated November 10, 2025)

**Changed**: free-sleep.service configuration

**From**:
```systemd
[Unit]
After=network.target
[Install]
WantedBy=multi-user.target
```

**To**:
```systemd
[Unit]
After=network-online.target
Wants=network-online.target
[Install]
WantedBy=network-online.target
```

**Reason**: Pod 3 never reaches multi-user.target. Using network-online.target ensures the service will start reliably.

### File: `scripts/pod3_sd_card_scripts/full_patch_workflow.sh` (Updated November 10, 2025)

**Changed**: freesleep-installer.service configuration (lines 1020-1098)

**From**:
```systemd
[Install]
WantedBy=multi-user.target
```

**To**:
```systemd
[Install]
WantedBy=network-online.target
```

**Symlink directory changed from**:
```bash
sudo ln -sf ../freesleep-installer.service "$SYSTEMD_WANTS/freesleep-installer.service"
# Where SYSTEMD_WANTS = multi-user.target.wants
```

**To**:
```bash
NETWORK_ONLINE_WANTS="$STAGING_DIR/etc/systemd/system/network-online.target.wants"
sudo mkdir -p "$NETWORK_ONLINE_WANTS"
sudo ln -sf ../freesleep-installer.service "$NETWORK_ONLINE_WANTS/freesleep-installer.service"
```

**Reason**: freesleep-installer.service was configured for multi-user.target (never reached), causing installation to never run. Moving to network-online.target allows the installer to execute after network is available.

---

## Next Steps for Full Automation

1. **Update Script**
   - ✅ freesleep-installer.service moved to network-online.target
   - ✅ DNS fix included in rootfs
   - ✅ Passwordless sudo configured
   - ✅ All service ordering correct

2. **Build New Image**
   ```bash
   ./full_patch_workflow.sh \
     -i original-image.img \
     -k ~/.ssh/id_rsa.pub \
     -s "ZyXEL046080" \
     -p "wifi-password" \
     -m "c0:ee:40:8c:ff:76" \
     -I "192.168.2.52/24" \
     -G "192.168.2.1" \
     -D "192.168.2.1,8.8.8.8,8.8.4.4" \
     -f -d
   ```

3. **Test Complete 4-Boot Sequence**
   - Flash SD card with new image
   - Monitor all 4 boots
   - Validate final state with test scripts

4. **Document Success**
   - Update QUICK_INSTALL.md with validated procedure
   - Update BOOT_ANALYSIS.md with findings
   - Create troubleshooting guide based on learnings
