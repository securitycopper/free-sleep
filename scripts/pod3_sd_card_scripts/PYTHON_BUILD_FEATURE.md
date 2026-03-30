# Python 3.11 Build Feature for SD Card Images

## Overview

Pod 3 with SD card has a **GLIBC incompatibility** that prevents biometrics from working:
- System has: **GLIBC 2.33** (2021)
- Python 3.9.9 requires: **GLIBC 2.38** (2023)
- Gap: **5 major versions**
- Impact: All compiled Python extensions fail (numpy, scipy, pip, etc.)

## Solution

Build Python 3.11.7 from source **targeting GLIBC 2.33** during the SD card image patching process.

## Usage

### Basic FreeSleep Installation (No Biometrics)
```bash
./full_patch_workflow.sh -i sdcard.img -k ~/.ssh/id_rsa.pub -f
```

### FreeSleep with Biometrics (Requires Python Build)
```bash
./full_patch_workflow.sh -i sdcard.img -k ~/.ssh/id_rsa.pub -f -Y -B
```

### Flag Details

| Flag | Description |
|------|-------------|
| `-Y` | Build Python 3.11 from source on first boot (30-60 minutes) |
| `-B` | Enable biometrics after FreeSleep installation |

**Note**: `-B` flag now warns if `-Y` is not also provided, since biometrics requires Python 3.11.

## How It Works

### 1. Image Patching Phase
When `-Y` flag is used, the script:
- Creates `python-builder.service` systemd unit
- Configures it to run after `monitor-pairing.service` (Eight Sleep updates stopped)
- Configures `freesleep-installer.service` to wait for Python build completion

### 2. First Boot Phase (After Pairing)
The `python-builder.service`:
1. Waits for `/var/lib/pairing-complete.flag` (monitor-pairing finished)
2. Installs build dependencies via apt
3. Downloads Python 3.11.7 source from python.org
4. Configures with `--prefix=/opt/python3.11 --enable-optimizations`
5. Compiles Python (30-60 minutes on ARM Cortex-A53)
6. Installs to `/opt/python3.11/`
7. Creates `/var/lib/python-build-complete.flag`
8. Cleans up build files

### 3. FreeSleep Installation Phase
The `freesleep-installer.service`:
- Waits for `/var/lib/python-build-complete.flag` (if `-Y` was used)
- Runs FreeSleep installation
- Biometrics scripts automatically detect and use `/opt/python3.11/bin/python3.11`

## Modified Scripts

### `full_patch_workflow.sh`
- Added `-Y` flag for Python build option
- Created `python-builder.service` systemd unit
- Updated `freesleep-installer.service` to depend on Python build
- Added validation warning if `-B` used without `-Y`

### `enable_biometrics.sh`
```bash
# Auto-detects Python 3.11 if available
if [ -x "/opt/python3.11/bin/python3.11" ]; then
    PYTHON_CMD="/opt/python3.11/bin/python3.11"
else
    PYTHON_CMD="python3"  # Fallback to system Python
fi
```

### `install_python_packages.sh`
```bash
# Uses Python 3.11 if available, falls back to system Python
if [ -x "/opt/python3.11/bin/python3.11" ]; then
    /opt/python3.11/bin/python3.11 -m venv /home/dac/venv
else
    python3 -m venv /home/dac/venv  # Requires file patching
fi
```

## Service Dependencies

```
Boot Sequence:
1. firstboot-reboot.service      (Reboots after factory reset)
2. monitor-pairing.service       (Waits for pairing, stops Eight Sleep updates)
3. python-builder.service        (Builds Python 3.11, if -Y flag used)
4. freesleep-installer.service   (Installs FreeSleep)
5. Reboot (applies all changes)
```

## Build Time

- **First boot with `-Y`**: 30-60 minutes (Python compilation)
- **First boot without `-Y`**: 5-10 minutes (normal)

## Verification

After first boot completes:

```bash
# Check Python 3.11 installed
ls -lh /opt/python3.11/bin/python3.11

# Verify Python works
/opt/python3.11/bin/python3.11 --version
# Expected: Python 3.11.7

# Check no GLIBC dependency issues
/opt/python3.11/bin/python3.11 -c "import ssl, sqlite3, zlib"
# Should run without errors

# Verify venv can be created
/opt/python3.11/bin/python3.11 -m venv /tmp/test_venv
source /tmp/test_venv/bin/activate
pip --version
# Should work without GLIBC errors
```

## Logs

Monitor Python build progress:
```bash
# SSH into Pod
ssh -p 8822 rewt@192.168.2.52

# Watch Python build logs
sudo journalctl -u python-builder.service -f

# Check if build completed
ls -la /var/lib/python-build-complete.flag
```

## Storage Requirements

- Build process: ~500MB temporary (cleaned up after)
- Final installation: ~150MB in `/opt/python3.11/`

## Troubleshooting

### Build Failed
```bash
# Check logs
sudo journalctl -u python-builder.service -n 200

# Common issues:
# - Network timeout during download
# - Insufficient storage (need 500MB+ free)
# - Build dependencies failed to install
```

### Biometrics Still Not Working
```bash
# Verify Python 3.11 is being used
grep "Using Python" /var/log/freesleep-install.log

# Check venv was created with Python 3.11
cat /home/dac/venv/pyvenv.cfg | grep home

# Test Python manually
/opt/python3.11/bin/python3.11 -m pip list
```

## Future Improvements

- Pre-compile Python 3.11 binaries for ARM64 GLIBC 2.33
- Include in FreeSleep repo for faster installation
- Add progress indicator for 30-60 min build time
- Cache build artifacts for factory reset scenarios
