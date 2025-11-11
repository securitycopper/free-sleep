#!/bin/bash
#
# Investigation Script: Find Certificate and DeviceInfo Sources
# This script helps locate where Capybara gets device certificates and info
#

echo "=========================================="
echo "DeviceInfo Source Investigation"
echo "=========================================="
echo ""

echo "1. Searching for certificate files in persistent storage..."
echo "---"
find /persistent -name "*.crt" -o -name "*.key" -o -name "*.pem" 2>/dev/null | head -20
echo ""

echo "2. Searching for device-id in persistent storage..."
echo "---"
find /persistent -type f -exec grep -l "device-id\|device_id\|deviceId" {} \; 2>/dev/null | head -10
echo ""

echo "3. Checking for certificate directories..."
echo "---"
ls -la /persistent/ 2>/dev/null | grep -E "(cert|key|ssl|tls|device)"
ls -la /opt/eight/ 2>/dev/null | grep -E "(cert|key|ssl|tls|device)"
echo ""

echo "4. Looking for Capybara configuration files..."
echo "---"
find /opt/eight -name "*.conf" -o -name "*.config" -o -name "*.json" 2>/dev/null | head -10
echo ""

echo "5. Checking Capybara binary for hardcoded paths..."
echo "---"
strings /opt/eight/bin/Eight.Capybara 2>/dev/null | grep -i -E "(deviceinfo|certificate|/persistent)" | head -20
echo ""

echo "6. Current /deviceinfo/ contents (from temporary Capybara run)..."
echo "---"
ls -la /deviceinfo/ 2>/dev/null
echo ""

echo "7. Checking if certificates are in /deviceinfo/ after Capybara..."
echo "---"
for file in /deviceinfo/*.crt /deviceinfo/*.key; do
    if [ -f "$file" ]; then
        echo "File: $file"
        echo "Size: $(stat -c%s "$file") bytes"
        echo "First line: $(head -n1 "$file")"
        echo "---"
    fi
done
echo ""

echo "8. Searching system for device label / serial number..."
echo "---"
find / -name "*label*" -o -name "*serial*" 2>/dev/null | grep -v "/proc\|/sys/dev\|/var" | head -10
echo ""

echo "9. Checking hardware EEPROM / OTP..."
echo "---"
ls -la /sys/fsl_otp/ 2>/dev/null || echo "No OTP directory found"
cat /sys/fsl_otp/* 2>/dev/null | head -20
echo ""

echo "10. MAC addresses..."
echo "---"
cat /sys/class/net/eth0/address 2>/dev/null || echo "No eth0"
cat /sys/class/net/wlan0/address 2>/dev/null || echo "No wlan0"
echo ""

echo "=========================================="
echo "Investigation Complete"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Review the output above"
echo "2. Determine where certificates originate"
echo "3. Create populate_deviceinfo.sh based on findings"
echo "4. Test the solution"
