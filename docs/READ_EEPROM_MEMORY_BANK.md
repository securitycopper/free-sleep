# Reading EEPROM Memory Bank on Pod 3

## Overview

The Pod 3 has an EEPROM (Electrically Erasable Programmable Read-Only Memory) chip that stores hardware configuration information. This memory bank is accessible via I2C (Inter-Integrated Circuit) communication at address **0x52**.

## EEPROM Location

- **I2C Bus**: 0x0
- **Device Address**: 0x52
- **Key Offset**: 0x20 (SOM options/WiFi availability flag)

## Reading EEPROM via SSH

### Prerequisites

1. Connect to your Pod via SSH:
```bash
ssh -p 8822 rewt@<POD_IP>
# OR
ssh -p 8822 root@<POD_IP>
```

2. Ensure you have `i2c-tools` installed (should be pre-installed on Pod 3)

### Basic Commands

#### Read a Single Byte from EEPROM

```bash
# Read WiFi availability flag (offset 0x20)
i2cget -f -y 0x0 0x52 0x20

# Example output: 0x00
# Bit 0 = 0 means WiFi reported as "not available" (even though hardware exists)
```

#### Dump Entire EEPROM Contents

```bash
# Dump all 256 bytes from EEPROM
i2cdump -f -y 0 0x52

# Example output will show 16x16 grid of hex values
```

#### Detect I2C Devices

```bash
# Scan I2C bus 0 for all connected devices
i2cdetect -y 0

# Should show device at address 0x52
```

### Understanding the Data

#### Offset 0x20: SOM Options Byte

This byte contains hardware capability flags:

```bash
# Read the byte
opt=$(i2cget -f -y 0x0 0x52 0x20)

# Check if WiFi bit is set (bit 0)
if [ $((opt & 0x1)) -eq 1 ]; then
    echo "WiFi reported as available"
else
    echo "WiFi reported as NOT available"
fi
```

**On Pod 3:**
- EEPROM reports WiFi as unavailable (bit 0 = 0)
- This is **intentional by Eight Sleep** to force app-based setup
- WiFi hardware (Broadcom BCM4339/2) is physically present and functional
- The EEPROM flag prevents auto-initialization via `variscite-wifi` service

## Complete EEPROM Diagnostic Script

Save this as `read_eeprom.sh` and run on your Pod:

```bash
#!/bin/bash
echo "======================================="
echo "Pod 3 EEPROM Memory Bank Reader"
echo "======================================="
echo ""

# Check if i2c-tools is available
if ! command -v i2cget &> /dev/null; then
    echo "ERROR: i2c-tools not installed"
    echo "Install with: apt-get install i2c-tools"
    exit 1
fi

echo "=== I2C Device Detection ==="
echo "Scanning I2C bus 0 for devices..."
i2cdetect -y 0
echo ""

echo "=== EEPROM Device Check ==="
if i2cdetect -y 0 | grep -q "52"; then
    echo "✓ EEPROM found at address 0x52"
else
    echo "✗ EEPROM not found at address 0x52"
    exit 1
fi
echo ""

echo "=== SOM Options Byte (Offset 0x20) ==="
opt=$(i2cget -f -y 0x0 0x52 0x20)
echo "Raw value: $opt"
echo ""

# Convert hex to decimal for bit checking
opt_dec=$((opt))
echo "Decimal value: $opt_dec"
echo ""

echo "=== Hardware Flags ==="
# Check bit 0 (WiFi)
if [ $((opt_dec & 0x1)) -eq 1 ]; then
    echo "Bit 0 (WiFi):           AVAILABLE ✓"
else
    echo "Bit 0 (WiFi):           NOT AVAILABLE ✗"
    echo "                        (Hardware present but EEPROM flag unset)"
fi

# Check other bits (if documented)
if [ $((opt_dec & 0x2)) -eq 2 ]; then
    echo "Bit 1:                  SET"
else
    echo "Bit 1:                  UNSET"
fi

if [ $((opt_dec & 0x4)) -eq 4 ]; then
    echo "Bit 2:                  SET"
else
    echo "Bit 2:                  UNSET"
fi

if [ $((opt_dec & 0x8)) -eq 8 ]; then
    echo "Bit 3:                  SET"
else
    echo "Bit 3:                  UNSET"
fi
echo ""

echo "=== Full EEPROM Dump ==="
echo "Dumping first 256 bytes from EEPROM..."
echo ""
i2cdump -f -y 0 0x52
echo ""

echo "=== WiFi Hardware Check ==="
if lsmod | grep -q brcmfmac; then
    echo "✓ WiFi driver (brcmfmac) loaded"
else
    echo "✗ WiFi driver (brcmfmac) NOT loaded"
fi

if ip link show wlan0 &> /dev/null; then
    echo "✓ wlan0 interface exists"
    ip link show wlan0 | grep "state"
else
    echo "✗ wlan0 interface NOT found"
fi
echo ""

echo "=== Analysis ==="
if [ $((opt_dec & 0x1)) -eq 0 ]; then
    echo "EEPROM reports WiFi as unavailable, but this is intentional."
    echo "Eight Sleep sets this flag to force app-based setup."
    echo ""
    echo "To enable WiFi on OpenSleep/FreeSleep:"
    echo "  - The opensleep-wifi.service bypasses this EEPROM check"
    echo "  - Check: systemctl status opensleep-wifi"
fi
echo ""
echo "======================================="
echo "EEPROM scan complete"
echo "======================================="
```

## Running the Diagnostic Script

```bash
# Make executable
chmod +x read_eeprom.sh

# Run with sudo (I2C access requires root)
sudo ./read_eeprom.sh
```

## Common EEPROM Values on Pod 3

| Offset | Description | Typical Value | Notes |
|--------|-------------|---------------|-------|
| 0x20 | SOM Options | 0x00 or 0xFE | WiFi bit (bit 0) typically unset |
| 0x00-0x0F | Device ID | Varies | Manufacturer/model info |
| 0x10-0x1F | Serial/Version | Varies | Hardware revision data |

## Why EEPROM Shows WiFi as Unavailable

**Eight Sleep's Design:**
1. EEPROM intentionally reports WiFi as unavailable
2. Prevents `variscite-wifi.service` from auto-starting WiFi
3. Forces users to configure via Eight Sleep app (Bluetooth pairing)
4. Ensures device registers with Eight Sleep cloud before WiFi works
5. Prevents unauthorized WiFi connectivity

**FreeSleep Solution:**
- `opensleep-wifi.service` bypasses EEPROM check
- WiFi hardware initialized regardless of EEPROM flag
- Allows direct WiFi configuration without app

## Troubleshooting

### Cannot Access I2C Device

```bash
# Check if I2C devices are available
ls -la /dev/i2c-*

# Load I2C driver if missing
modprobe i2c-dev

# Check kernel messages
dmesg | grep i2c
```

### EEPROM Not Responding

```bash
# Verify device is responding
i2cdetect -y 0

# Try reading with different flags
i2cget -y 0x0 0x52 0x20  # Without -f flag

# Check permissions
sudo i2cget -f -y 0x0 0x52 0x20
```

### Understanding Output

```bash
# Example i2cdetect output:
#      0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f
# 00:          -- -- -- -- -- -- -- -- -- -- -- -- --
# 10: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
# 20: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
# 30: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
# 40: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
# 50: -- -- 52 -- -- -- -- -- -- -- -- -- -- -- -- --
#                ^^
#                EEPROM at 0x52
```

## Related Files

- `/etc/wifi/opensleep-wifi` - Modified WiFi script that bypasses EEPROM check
- `/etc/systemd/system/opensleep-wifi.service` - Service that initializes WiFi
- `/scripts/pod3_sd_card_scripts/full_patch_workflow.md` - Detailed EEPROM analysis

## References

- I2C Tools Documentation: https://linux.die.net/man/8/i2cget
- Pod 3 Boot Analysis: `/scripts/pod3_sd_card_scripts/BOOT_ANALYSIS.md`
- Full Patch Workflow: `/scripts/pod3_sd_card_scripts/full_patch_workflow.md`

## Safety Notes

⚠️ **WARNING:**
- Reading from EEPROM is safe
- **DO NOT attempt to write to EEPROM** without understanding the consequences
- Incorrect EEPROM values could brick your device
- The `i2cset` command can permanently modify EEPROM contents
- Stick to `i2cget` and `i2cdump` for diagnostics only
