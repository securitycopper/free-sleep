# Pod 3 SD Card Scripts - FreeSleep Edition

This directory contains scripts for patching Pod 3 SD card images to install FreeSleep.

## Overview

Pod 3 devices require SD card modification to install FreeSleep. These scripts automate the process of mounting, patching, and preparing SD card images for deployment.

## Main Scripts

- **`full_patch_workflow.sh`** - Main orchestration script for complete patching process
- **`full_patch_workflow_post_ssh_validation.sh`** - Post-deployment validation script
- **`extract_pod3_logs.sh`** - Extract logs from Pod 3 SD card
- **`wsl_build_for_pod.sh`** - WSL-specific build script for Windows users

## Boot Sequence

After patching and factory reset, Pod 3 goes through a **4-boot sequence** to fully install FreeSleep:

```
╔══════════════════════════════════════════════════════════════════════════════════════════╗
║                     FreeSleep Pod 3 - Complete Boot Sequence                             ║
║                     (4 Boots Required After Factory Reset)                               ║
╚══════════════════════════════════════════════════════════════════════════════════════════╝

┌──────────────────────────────────────────────────────────────────────────────────────────┐
│  FACTORY RESET - Extract rootfs.tar.gz                                                   │
│  • Extracts patched filesystem with all FreeSleep services                               │
│  • Includes: subsystem scripts, service units, SSH keys, WiFi config                     │
└──────────────────────────────────────────────────────────────────────────────────────────┘
                                          │
                                          ▼
╔══════════════════════════════════════════════════════════════════════════════════════════╗
║  BOOT 1 - First Boot (Filesystem Setup)                                                  ║
╠══════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                           ║
║  sysinit.target                                                                           ║
║    │                                                                                      ║
║    └─► [firstboot-reboot.service]  ─────► Creates /var/lib/firstboot-complete.flag     ║
║                                            Then: IMMEDIATE REBOOT                         ║
║                                                                                           ║
║  Purpose: Apply filesystem changes from factory reset                                    ║
║  Duration: ~5 seconds                                                                     ║
║                                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════════════════════
                                          │
                                          ▼
╔══════════════════════════════════════════════════════════════════════════════════════════╗
║  BOOT 2 - Second Boot (Eight Sleep Disable + Network Init)                               ║
╠══════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                           ║
║  basic.target                                                                             ║
║    │                                                                                      ║
║    └─► [disable-eightsleep-services.service] ───► Disables & masks:                     ║
║                                                     • swupdate, defibrillator             ║
║                                                     • eight-kernel, telegraf, vector      ║
║                                                     • frankenfirmware, dac                ║
║                                                     • capybara ◄─── MASKED HERE           ║
║                                                     Creates: eightsleep-disabled.flag     ║
║                                                                                           ║
║  network.target                                                                           ║
║    │                                                                                      ║
║    ├─► [free-sleep-wifi.service] ────────────────► Initializes WiFi hardware            ║
║    │                                                (bypasses EEPROM check)               ║
║    │                                                                                      ║
║    └─► [free-sleep-mac.service] ─────────────────► Sets persistent MAC address          ║
║                                                                                           ║
║  network-online.target                                                                    ║
║    │                                                                                      ║
║    └─► [wpa_supplicant@wlan0.service] ──────────► Connects to WiFi                      ║
║                                                    Then: AUTOMATIC REBOOT                 ║
║                                                                                           ║
║  Purpose: Disable Eight Sleep services, initialize network                               ║
║  Duration: ~30 seconds                                                                    ║
║                                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════════════════════
                                          │
                                          ▼
╔══════════════════════════════════════════════════════════════════════════════════════════╗
║  BOOT 3 - Third Boot (FreeSleep Installation)                                            ║
╠══════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                           ║
║  sysinit.target                                                                           ║
║    │                                                                                      ║
║    ├─► [deviceinfo.mount] ───────────────────────► Mounts /deviceinfo tmpfs             ║
║    │                                                                                      ║
║    └─► [populate-deviceinfo.service] ────────────► Creates /deviceinfo/ files:          ║
║         (After: deviceinfo.mount)                   • device-id (from MAC SHA1)          ║
║                                                     • device-label, variscite-id          ║
║                                                     • wifi-macaddress                     ║
║                                                     • dummy certificates                  ║
║                                                                                           ║
║  multi-user.target                                                                        ║
║    │                                                                                      ║
║    ├─► [enable-subsystems.service] ──────────────► Initializes PCAL6416A GPIO:          ║
║    │                                                • Detects I2C bus (0-3)               ║
║    │                                                • Configures GPIO at 0x20             ║
║    │                                                • Enables Frozen & Sensor subsystems  ║
║    │                                                                                      ║
║    └─► [frank.service] ───────────────────────────► ❌ MASKED (waiting for FreeSleep)   ║
║         (drop-in: After=enable-subsystems)                                                ║
║                                                                                           ║
║  network-online.target                                                                    ║
║    │                                                                                      ║
║    └─► [freesleep-installer.service] ────────────► Downloads & installs FreeSleep:      ║
║                                                     • Clones GitHub repo                  ║
║                                                     • npm install (server + app)          ║
║                                                     • Creates free-sleep.service          ║
║                                                     • Unmasks frank.service, dac.service  ║
║                                                     • Enables biometrics (if requested)   ║
║                                                     Creates: freesleep-installed.flag     ║
║                                                     Then: AUTOMATIC REBOOT                 ║
║                                                                                           ║
║  Purpose: Install FreeSleep and prepare hardware services                                ║
║  Duration: ~5-10 minutes (download + npm install)                                        ║
║                                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════════════════════
                                          │
                                          ▼
╔══════════════════════════════════════════════════════════════════════════════════════════╗
║  BOOT 4 - Fourth Boot (FreeSleep Running) ✅ FULLY OPERATIONAL                           ║
╠══════════════════════════════════════════════════════════════════════════════════════════╣
║                                                                                           ║
║  sysinit.target                                                                           ║
║    │                                                                                      ║
║    ├─► [deviceinfo.mount] ───────────────────────► ✅ Mounts /deviceinfo tmpfs          ║
║    │                                                                                      ║
║    └─► [populate-deviceinfo.service] ────────────► ✅ Creates /deviceinfo/ files        ║
║         (After: deviceinfo.mount)                                                         ║
║                                                                                           ║
║  multi-user.target                                                                        ║
║    │                                                                                      ║
║    ├─► [enable-subsystems.service] ──────────────► ✅ Initializes GPIO expander         ║
║    │    (After: populate-deviceinfo)                                                      ║
║    │                                                                                      ║
║    ├─► [dac.service] ─────────────────────────────► ✅ Starts DAC socket server         ║
║    │                                                   Creates: /deviceinfo/dac.sock     ║
║    │                                                                                      ║
║    ├─► [frank.service] ───────────────────────────► ✅ Frankenfirmware connects:        ║
║    │    (After: enable-subsystems, populate-info)     • Reads device-id                  ║
║    │                                                   • Connects to dac.sock            ║
║    │                                                   • Probes sensors (cap_sense)      ║
║    │                                                   • Controls Peltier elements       ║
║    │                                                                                      ║
║    ├─► [free-sleep.service] ──────────────────────► ✅ FreeSleep server starts:         ║
║    │    (modified by freesleep-service-fixer)         • API: http://<IP>:3000           ║
║    │    (After: enable-subsystems)                    • Connects via dac.sock           ║
║    │                                                   • Temperature control active      ║
║    │                                                   • Sleep tracking ready            ║
║    │                                                                                      ║
║    └─► [freesleep-service-fixer.service] ────────► ✅ Adds After=enable-subsystems to   ║
║         (runs once, creates flag)                      free-sleep.service                ║
║                                                                                           ║
║  Optional (if timezone configured):                                                      ║
║    └─► [freesleep-timezone-setter.service] ──────► ✅ Sets timezone via API             ║
║                                                                                           ║
║  ❌ Permanently Disabled Services:                                                        ║
║     • capybara.service (masked)          ◄─── Replaced by our services                  ║
║     • swupdate.service (masked)                                                           ║
║     • defibrillator.service (masked)                                                      ║
║     • eight-kernel.service (masked)                                                       ║
║     • telegraf.service (masked)                                                           ║
║     • vector.service (masked)                                                             ║
║                                                                                           ║
║  🎉 READY FOR USE - All services operational!                                            ║
║  Duration: ~1 minute to full operation                                                    ║
║                                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════════════════════

┌──────────────────────────────────────────────────────────────────────────────────────────┐
│  EVERY SUBSEQUENT BOOT (Normal Operation)                                                │
├──────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                           │
│  deviceinfo.mount             ──► Mounts /deviceinfo tmpfs                               │
│         ▼                                                                                 │
│  populate-deviceinfo.service  ──► Creates /deviceinfo/ files (tmpfs cleared on reboot)  │
│         ▼                                                                                 │
│  enable-subsystems.service    ──► Initializes GPIO expander (I2C 0x20)                  │
│         ▼                                                                                 │
│  dac.service                  ──► Socket server ready                                    │
│         ▼                                                                                 │
│  frank.service                ──► Hardware control active                                │
│         ▼                                                                                 │
│  free-sleep.service           ──► Temperature control + API ready                        │
│                                                                                           │
│  Time to full operation: ~30-60 seconds                                                   │
│                                                                                           │
└──────────────────────────────────────────────────────────────────────────────────────────┘
```

## Service Dependencies

```
═══════════════════════════════════════════════════════════════════════════════════════════

KEY DEPENDENCIES:

  deviceinfo.mount (fstab, auto-generated)
         │
         └──────────► populate-deviceinfo.service (sysinit.target)
                              │
                              ├──────────► enable-subsystems.service (multi-user.target)
                              │                    │
                              │                    ├──────────► frank.service
                              │                    │                  │
                              │                    │                  └──────────► free-sleep.service
                              │                    │
                              └────────────────────┴──────────────────────────────► frank.service

═══════════════════════════════════════════════════════════════════════════════════════════
```

## Timing Summary

| Phase | Duration | Description |
|-------|----------|-------------|
| Factory Reset + Boot 1 | ~5 seconds | Filesystem setup |
| Boot 2 | ~30 seconds | Network init + Eight Sleep disable |
| Boot 3 | ~5-10 minutes | FreeSleep download & install |
| Boot 4 | ~1 minute | Services start |
| **Total** | **~7-12 minutes** | From factory reset to working |
| **Subsequent boots** | **~30-60 seconds** | Normal operation |

## Key Components

### Subsystem Initialization Services

FreeSleep replaces Capybara's hardware initialization with three services:

1. **populate-deviceinfo.service** (sysinit.target)
   - Creates `/deviceinfo/` files from MAC address on every boot
   - Generates device-id via SHA1 hash
   - Must run AFTER `deviceinfo.mount` completes

2. **enable-subsystems.service** (multi-user.target)
   - Initializes PCAL6416A GPIO expander (I2C address 0x20)
   - **Dynamically detects I2C bus** (scans 0-3)
   - Enables Pod hardware subsystems (Frozen + Sensor)

3. **frank.service drop-in override** (freesleep-subsystems.conf)
   - Adds dependencies: `After=enable-subsystems.service populate-deviceinfo.service`
   - Removes Capybara dependency
   - Ensures proper boot order

### Important Notes

⚠️ **Hardware Inconsistency**: Pod 3 devices have varying hardware configurations:
- GPIO expander may be on I2C bus 0, 1, or other buses
- LED controllers may be on different buses
- **Always use dynamic detection, never hard-code hardware addresses**

⚠️ **tmpfs Mount Race Condition**: The `/deviceinfo/` directory is mounted as tmpfs from `/etc/fstab`. The `populate-deviceinfo.service` MUST have `After=deviceinfo.mount` to prevent the mount from clearing populated files.

## Usage

See individual script files for detailed usage instructions:
- `QUICK_INSTALL.md` - Quick start guide
- `README_BUILD_SCRIPT.md` - Build script documentation
- `README_WSL_BUILD.md` - WSL-specific instructions

## Validation

After deployment, run the validation script on the Pod:
```bash
~/validate_deployment.sh
```

This checks:
- ✅ All subsystem services active
- ✅ /deviceinfo/ files present
- ✅ GPIO expander initialized
- ✅ frank and free-sleep services running
- ✅ Network connectivity
- ✅ Eight Sleep services disabled

## Troubleshooting

### Common Issues

**Issue**: `enable-subsystems.service` fails with "Write failed"
- **Cause**: GPIO expander on different I2C bus than expected
- **Fix**: Script now auto-detects bus (version with dynamic detection)

**Issue**: frank.service times out waiting for `/deviceinfo/device-id`
- **Cause**: Race condition - `deviceinfo.mount` cleared files after populate ran
- **Fix**: `populate-deviceinfo.service` now has `After=deviceinfo.mount`

**Issue**: LED stuck blinking blue (pairing mode)
- **Cause**: Cosmetic only - FreeSleep doesn't control LED yet
- **Status**: Not critical, system still functional

## Development

When modifying these scripts:
1. Test on fresh SD card image
2. Validate complete 4-boot sequence
3. Run validation script
4. Update documentation

## Related Documentation

- `.memory-bank/session-2025-11-11-capybara-subsystems.md` - Complete development session
- `.memory-bank/BREAKTHROUGH.md` - Critical bug fixes
- `.memory-bank/next-steps-subsystem-replacement.md` - Implementation guide
