# Memory Bank - Quick Reference

## Overview
This directory contains validated commands, procedures, and findings from Pod 3 testing.

**Last Updated**: January 5, 2026  
**Status**: ✅ System Operational - Python 3.12 + Biometrics Working  
**Known Issue**: Bug #8 - Frank socket disconnect on boot (requires manual restart)

---

## Files in This Directory

### `working-commands.md`
Complete reference of all validated commands and procedures:
- DNS resolution fix (CRITICAL)
- Eight Sleep services management
- FreeSleep installation and validation
- Boot sequence analysis
- Troubleshooting commands
- Common issues and solutions

**Use this when**: You need to troubleshoot, validate, or manually test on Pod 3

---

## Critical Discoveries

### 1. Capybara-Assisted Workflow (November 2025)
Eight Sleep app handles WiFi pairing, then system auto-transitions to FreeSleep.

**Key Change**: Removed all manual WiFi configuration (SSID, PSK, wpa_supplicant setup).

**New Boot Sequence** (4 Phases):
- **BOOT 1**: Factory reset reboot (automatic via firstboot-reboot.service)
- **BOOT 2**: Pairing ready (Capybara ACTIVE, update services ENABLED for Eight Sleep app)
- **BOOT 3**: Post-pairing (monitor-pairing.service detects pairing, THEN disables update services)
- **BOOT 4**: FreeSleep operational (Eight Sleep services masked, FreeSleep running)

**Critical Timing**: Update services must stay enabled during pairing (BOOT 2) for Eight Sleep app functionality, then be disabled after pairing completes to prevent unwanted firmware updates.

### 2. Update Services Are Aggressive (CRITICAL)
Update services (swupdate, defibrillator) detect filesystem changes and trigger firmware updates/rollbacks.

**Impact**: Will wipe all modifications including SSH access if not disabled at the right time.

**Solution**: 
- ❌ Old approach: Disable immediately (breaks pairing)
- ✅ New approach: Wait for pairing completion marker, then disable via monitor-pairing.service

**Validation Protocol**: ALWAYS disable update services on first SSH login:
```bash
sudo systemctl disable --now swupdate swupdate-progress defibrillator
sudo systemctl mask swupdate swupdate-progress defibrillator
```

### 3. multi-user.target Never Reached
Pod 3 stops at `network-online.target` and NEVER reaches `multi-user.target`.

**Impact**: Any services configured with `WantedBy=multi-user.target` will never execute.

**Solution**: Use `sysinit.target`, `basic.target`, or `network-online.target` instead.

### 4. DNS Configuration Broken
`/etc/resolv.conf` points to NetworkManager (not used), causing all DNS lookups to fail.

**Impact**: FreeSleep installation fails (cannot download from GitHub).

**Solution**: Create symlink to systemd-resolved: `/run/systemd/resolve/resolv.conf`

### 5. Bug #8 - Frank Socket Disconnect on Boot (CRITICAL)
**Discovered**: December 9, 2025 | **Confirmed**: January 5, 2026

**Symptom**: After Pod boot/reboot, FreeSleep service shows socket errors:
```
error | This socket has been ended by the other party
error | {"error":{"message":"This socket has been ended by the other party"}}
info  | POST /api/deviceStatus - 500
```

**Root Cause**: Race condition between FreeSleep and Frank service startup. Detailed timing analysis from logs:

```
08:09:07 - Frank starts, attempts socket connection immediately
08:09:07 - dac_loop err: asio.system:22 (EINVAL - Invalid argument)
08:09:07 - FreeSleep service starts (systemd)
08:09:20 - FreeSleep creates socket at /deviceinfo/dac.sock (13 seconds after Frank)
08:09:20 - FreeSleep waits for connection
08:09:37 - Frank retries connection (30-second retry interval), succeeds
08:09:51 - Frank crashes with SEGV (segmentation fault)
08:10:04 - Frank auto-restarts (systemd restart policy)
08:10:37 - Connection finally stable after restart
```

**Technical Details**:
- Frank's `dac_loop` attempts connection before socket file exists
- ASIO library returns error 22 (EINVAL) when socket not available
- Frank has 30-second retry interval built into `dac_loop`
- FreeSleep takes 13 seconds to initialize before creating socket
- Initial connection at 08:09:37 is unstable, Frank crashes at 08:09:51
- After Frank restart, connection stabilizes but FreeSleep still has old stale socket reference
- FreeSleep needs restart to get fresh socket connection to new Frank instance

**Impact**: 
- Temperature control API fails (500 errors)
- Device status queries fail
- Occurs on EVERY boot/power cycle
- Affects fresh boots and reboots equally

**Solution** (Manual - Required after every boot):
```bash
# 1. Restart Frank to reset socket
sudo systemctl restart frank.service

# 2. Wait 3-5 seconds for Frank to initialize

# 3. Restart FreeSleep to re-establish connection
sudo systemctl restart free-sleep.service

# 4. Verify socket is working
curl http://localhost:3000/api/deviceStatus
```

**Verification**: If working correctly, you'll see temperature data instead of socket errors in logs.

---

**✅ PERMANENT FIX APPLIED** (January 5, 2026):

Modified `/etc/systemd/system/free-sleep.service`:
```diff
[Unit]
Description=Free Sleep Server
-After=network.target
+After=network.target frank.service
+Wants=frank.service
```

This ensures:
- FreeSleep waits for Frank to start before initializing
- Combined with FreeSleep's built-in 25s timeout + retry, socket connects automatically
- **No manual intervention required** on boot/restart

To apply this fix to other Pods:
```bash
# SSH to Pod
ssh -p 8822 rewt@POD_IP

# Edit service file
sudo nano /etc/systemd/system/free-sleep.service

# Add to [Unit] section:
# After=network.target frank.service
# Wants=frank.service

# Reload and test
sudo systemctl daemon-reload
sudo systemctl restart frank.service free-sleep.service
```

**Status**: ✅ **FIXED** (January 5, 2026) - Systemd service ordering implemented + FreeSleep has built-in retry logic.

**Solution Applied**:
Modified `/etc/systemd/system/free-sleep.service` to add Frank dependency:
```systemd
[Unit]
Description=Free Sleep Server
After=network.target frank.service
Wants=frank.service
```

**How It Works**:
1. `After=frank.service` ensures FreeSleep waits for Frank to start before initializing
2. `Wants=frank.service` creates a dependency relationship (non-blocking)
3. FreeSleep has built-in 25-second connection timeout with automatic retry
4. Even if Frank's socket isn't ready immediately, FreeSleep retries and connects successfully

**Testing Results** (January 5, 2026):
```
08:21:53 - Frank starts
08:21:53 - FreeSleep starts (after Frank)
08:21:58 - FreeSleep creates socket connection
08:22:23 - FreeSleep timeout (25s), retries
08:22:23 - Frank connects successfully
Result: No manual intervention required, socket connects automatically
```

**No Manual Workaround Needed**: System now recovers automatically on every boot. Bug #8 resolved.

---

## Workflow Evolution

### Phase 1: Manual Installation (November 9, 2025)
- ✅ Manual WiFi configuration via wpa_supplicant
- ✅ Static IP setup via systemd-networkd
- ✅ All Eight Sleep services disabled immediately
- **Result**: Working but complex, requires manual WiFi credentials

### Phase 2: Capybara-Assisted (November 13, 2025 - Current)
- ✅ Eight Sleep app handles WiFi pairing
- ✅ Removed manual WiFi configuration (~200 lines)
- ✅ Removed SSH key removal option (keeps Eight Sleep keys for pairing)
- ✅ Removed password flag (SSH keys sufficient)
- ✅ 4-phase boot sequence with proper timing
- ✅ monitor-pairing.service waits for pairing completion
- **Status**: Implementation complete, awaiting fresh SD card test

**Key Files Modified**:
1. `full_patch_workflow.sh` - Added monitor-pairing.service, removed WiFi config
2. `full_patch_workflow_post_ssh_validation.sh` - Boot phase detection and context-aware validation

---

## Current Testing Status (January 5, 2026)

### Deployment Server: 192.168.2.52
- Hardware: Pod 3 with SD card
- WiFi: ZyXEL046080
- MAC: c0:ee:40:8c:ff:76
- FreeSleep: 2.1.3 (main branch)
- Python: 3.12.8 at /opt/python3.12/ (pre-built binary)
- Biometrics: ✅ Fully operational (stream service healthy)
- Status: ✅ System operational after boot, requires Bug #8 workaround

### Current Known Issues
1. ✅ Update services disabled (prevents firmware rollback)
2. ✅ Python 3.12 installed successfully (GLIBC 2.33 compatibility achieved)
3. ✅ Biometrics packages installed: numpy 2.3.5, scipy 1.16.3, pandas 2.3.3, cbor2 5.7.1, watchdog 6.0.0, sentry-sdk 2.47.0
4. ⚠️ **Bug #8**: Frank socket disconnect on boot - requires manual restart of Frank + FreeSleep services
5. ✅ Python 3.12 persists through power cycles (SD card storage)

### Recent Events
**January 5, 2026**: Pod was unplugged, restarted after ~1 month offline
- Boot successful (~5-7 minutes)
- All services started correctly
- Bug #8 manifested immediately (expected behavior)
- Applied manual workaround: restart Frank, then FreeSleep
- System fully operational after workaround
- All configurations (Python 3.12, biometrics) persisted correctly

### Next Actions
1. Rebuild SD card with 10-minute grace period
2. Test pairing with Eight Sleep app (verify app completes full setup)
3. Monitor for 10 minutes to ensure no interruption
4. Verify monitor-pairing disables updates after grace period
5. Confirm FreeSleep installation proceeds normally

---

## Manual Installation Validation (Legacy)

**Date**: November 10, 2025 04:27-04:33 UTC  
**Result**: ✅ **SUCCESS**

### What Worked
1. DNS fix applied manually → GitHub downloads successful
2. Eight Sleep services disabled manually → No race condition
3. freesleep-installer triggered manually → Installed successfully
4. System rebooted → FreeSleep service running
5. Web UI accessible at http://192.168.2.52:3000

### Key Success Metrics
- ✅ Prisma migrations: Completed
- ✅ Node.js 24.11.0: Installed via Volta
- ✅ Service memory: 173MB (healthy)
- ✅ Franken connection: /deviceinfo/dac.sock working
- ✅ Boot time: ~6 minutes total

---

## Script Status

### Capybara-Assisted Workflow (Current)
1. ✅ WiFi configuration removed (Eight Sleep app handles pairing)
2. ✅ Static IP/gateway/DNS options removed
3. ✅ SSH key preservation (keeps Eight Sleep keys for Capybara)
4. ✅ Password option removed (SSH keys sufficient)
5. ✅ 4-phase boot sequence with ASCII diagram
6. ✅ monitor-pairing.service (waits for pairing, then disables updates)
7. ✅ Context-aware validation script (detects boot phase)
8. ⏳ Needs pairing completion marker identification
9. ⏳ Needs fresh SD card test

### Ready for Testing
New workflow implemented but requires fresh SD card to validate complete boot sequence.

---

## Quick Commands

### CRITICAL: Disable Update Services on Login
```bash
# ALWAYS run this first when SSHing to Pod
ssh -p 8822 rewt@192.168.2.52
sudo systemctl disable --now swupdate swupdate-progress defibrillator
sudo systemctl mask swupdate swupdate-progress defibrillator
```

### Fix Bug #8 - Frank Socket Disconnect (Required After Every Boot)
```bash
# After boot/reboot, always run this to fix socket connection
ssh -p 8822 rewt@192.168.2.52
sudo systemctl restart frank.service
sleep 5
sudo systemctl restart free-sleep.service

# Verify it's working (should see temperature data, not socket errors)
curl http://localhost:3000/api/deviceStatus
```

### Check FreeSleep Status
```bash
ssh -p 8822 rewt@192.168.2.52
sudo systemctl status free-sleep.service --no-pager
curl http://localhost:3000
```

### Check Eight Sleep Services
```bash
sudo systemctl status capybara dac swupdate defibrillator 2>&1 | grep "Active:"
```

### Check DNS
```bash
cat /etc/resolv.conf
nslookup raw.githubusercontent.com
```

### Check Boot History
```bash
journalctl --list-boots --no-pager
```

### Check Flag Files
```bash
ls -la /var/lib/*.flag
```

---

## Next Steps

1. **Build new image** with all fixes
2. **Flash SD card** and insert into Pod 3
3. **Monitor 4-boot sequence** (~15-20 minutes)
4. **Validate** with test scripts
5. **Access Web UI** at http://192.168.2.52:3000

---

## Support Resources

- **Full commands**: See `working-commands.md`
- **Boot analysis**: See `../BOOT_ANALYSIS.md`
- **Build instructions**: See `../QUICK_INSTALL.md`
- **Script documentation**: See `../README_BUILD_SCRIPT.md`
