# Memory Bank - Quick Reference

## Overview
This directory contains validated commands, procedures, and findings from Pod 3 testing.

**Last Updated**: November 9, 2025  
**Status**: ✅ Manual installation SUCCESSFUL  
**Next Step**: Build new image with all fixes

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

### 1. multi-user.target Never Reached
Pod 3 stops at `network-online.target` and NEVER reaches `multi-user.target`.

**Impact**: Any services configured with `WantedBy=multi-user.target` will never execute.

**Solution**: Use `sysinit.target`, `basic.target`, or `network-online.target` instead.

### 2. DNS Configuration Broken
`/etc/resolv.conf` points to NetworkManager (not used), causing all DNS lookups to fail.

**Impact**: FreeSleep installation fails (cannot download from GitHub).

**Solution**: Create symlink to systemd-resolved: `/run/systemd/resolve/resolv.conf`

### 3. Eight Sleep Services Are Aggressive
Update services (swupdate, defibrillator) detect filesystem changes within seconds and trigger reboots.

**Impact**: Race condition can interrupt installation or lose changes.

**Solution**: Disable services in `basic.target` with `Before=` directives.

---

## Manual Installation Validation

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

### Fixed Issues
1. ✅ DNS resolution fix implemented
2. ✅ Passwordless sudo configured
3. ✅ firstboot-reboot moved to sysinit.target
4. ✅ disable-eightsleep-services moved to basic.target
5. ✅ freesleep-installer moved to network-online.target
6. ✅ Static IP configuration with explicit DNS

### Ready for Production
All fixes validated on live hardware. Script ready to rebuild with 95% confidence.

---

## Quick Commands

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
