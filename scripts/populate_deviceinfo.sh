#!/bin/bash
#
# Populate /deviceinfo/ Directory for FreeSleep
# Replaces Capybara's deviceinfo initialization
#
# This script creates the essential files in /deviceinfo/ (tmpfs) that
# frankenfirmware and FreeSleep need to operate.
#

set -e

DEVICEINFO_DIR="/deviceinfo"

echo "Populating /deviceinfo/ for FreeSleep..."

# Ensure directory exists and is writable
if [ ! -d "$DEVICEINFO_DIR" ]; then
    echo "ERROR: $DEVICEINFO_DIR does not exist"
    exit 1
fi

# Get MAC address from eth0 (primary network interface)
MAC=$(cat /sys/class/net/eth0/address 2>/dev/null)
if [ -z "$MAC" ]; then
    echo "WARNING: Could not read eth0 MAC address, using fallback"
    MAC="00:00:00:00:00:00"
fi
echo "$MAC" > "$DEVICEINFO_DIR/wifi-macaddress"
echo "✓ wifi-macaddress: $MAC"

# Get Variscite SOM hardware ID (if available)
VARISCITE_ID=""
if [ -f /sys/fsl_otp/HW_OCOTP_MAC0 ]; then
    VARISCITE_ID=$(cat /sys/fsl_otp/HW_OCOTP_MAC0)
elif [ -f /sys/fsl_otp/HW_OCOTP_CFG0 ]; then
    VARISCITE_ID=$(cat /sys/fsl_otp/HW_OCOTP_CFG0)
fi

if [ -n "$VARISCITE_ID" ]; then
    echo "$VARISCITE_ID" > "$DEVICEINFO_DIR/variscite-id"
    echo "✓ variscite-id: $VARISCITE_ID"
else
    # Generate from MAC if hardware ID not available
    echo "${MAC//:/}" > "$DEVICEINFO_DIR/variscite-id"
    echo "✓ variscite-id: ${MAC//:/} (generated from MAC)"
fi

# Generate device-id (SHA1 hash of MAC address)
# This creates a stable unique identifier based on hardware
DEVICE_ID=$(echo -n "$MAC" | sha1sum | cut -d' ' -f1)
echo "$DEVICE_ID" > "$DEVICEINFO_DIR/device-id"
echo "✓ device-id: $DEVICE_ID"

# Create device label (can be customized)
# Format: FREESLEEP-<last 4 chars of device-id>
LABEL="FREESLEEP-${DEVICE_ID: -4}"
echo "$LABEL" > "$DEVICEINFO_DIR/device-label"
echo "✓ device-label: $LABEL"

# Create dummy/self-signed certificates for compatibility
# FreeSleep doesn't use Eight Sleep cloud, so these can be minimal
# If frankenfirmware checks for their existence, they'll be there

# Generate a simple self-signed certificate (valid for 10 years)
# This is just for file existence - not used for actual crypto
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -subj "/CN=FreeSleep/O=FreeSleep/C=US" \
    -keyout "$DEVICEINFO_DIR/device.key" \
    -out "$DEVICEINFO_DIR/device.crt" 2>/dev/null || {
    # If openssl not available, create dummy files
    echo "-----BEGIN PRIVATE KEY-----" > "$DEVICEINFO_DIR/device.key"
    echo "MC4CAQAwBQYDK2VwBCIEIMfZYQ8CUpWIOsb+gWqXpA7e97tVkliAD23msMqRZcl1" >> "$DEVICEINFO_DIR/device.key"
    echo "-----END PRIVATE KEY-----" >> "$DEVICEINFO_DIR/device.key"
    
    echo "-----BEGIN CERTIFICATE-----" > "$DEVICEINFO_DIR/device.crt"
    echo "MIIBkTCB+wIJAMHoj0PYSKXkMA0GCSqGSIb3DQEBCwUAMBQxEjAQBgNVBAMMCUZy" >> "$DEVICEINFO_DIR/device.crt"
    echo "ZWVTbGVlcDAeFw0yNTExMTEwMDAwMDBaFw0zNTExMTEwMDAwMDBaMBQxEjAQBgNV" >> "$DEVICEINFO_DIR/device.crt"
    echo "BAMMCUZyZWVTbGVlcDBcMA0GCSqGSIb3DQEBAQUAA0sAMEgCQQC1234567890abc" >> "$DEVICEINFO_DIR/device.crt"
    echo "-----END CERTIFICATE-----" >> "$DEVICEINFO_DIR/device.crt"
}

# Copy device cert to factory, core, and root (they can all be the same for our purposes)
cp "$DEVICEINFO_DIR/device.crt" "$DEVICEINFO_DIR/factory.crt"
cp "$DEVICEINFO_DIR/device.crt" "$DEVICEINFO_DIR/core.crt"
cp "$DEVICEINFO_DIR/device.crt" "$DEVICEINFO_DIR/root.crt"

echo "✓ Certificates created (self-signed for FreeSleep)"

# Set appropriate permissions
chmod 644 "$DEVICEINFO_DIR"/*.crt "$DEVICEINFO_DIR"/device-id \
    "$DEVICEINFO_DIR"/device-label "$DEVICEINFO_DIR"/variscite-id \
    "$DEVICEINFO_DIR"/wifi-macaddress 2>/dev/null
chmod 600 "$DEVICEINFO_DIR"/*.key 2>/dev/null

echo "✓ Permissions set"
echo ""
echo "✓ /deviceinfo/ populated successfully for FreeSleep"
echo ""
echo "Contents:"
ls -lh "$DEVICEINFO_DIR" | grep -v "^total"

exit 0
