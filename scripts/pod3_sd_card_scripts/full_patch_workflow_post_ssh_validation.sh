#!/bin/bash

# Pod 3 (SD Card) Post-Patch Validation Script - FreeSleep Edition
# Run this on the Pod 3 after patching to validate the FreeSleep setup
# Usage: ./full_patch_workflow_post_ssh_validation.sh
#
# ⚠️  For Pod 3 with SD card only!

set -e

echo "========================================"
echo "Pod 3 (SD Card) FreeSleep Validation"
echo "========================================"
echo ""

# === System Information ===
echo "=== System Information ==="
echo "Hostname: $(hostname 2>/dev/null || echo 'unknown')"
echo "Boot time: $(uptime -s 2>/dev/null || cat /proc/uptime | awk '{print int($1)}' | xargs -I {} echo '{} seconds ago')"
echo ""

# === MAC Address (Important: Changes on factory reset!) ===
echo "=== MAC Address ==="
WLAN_MAC=$(cat /sys/class/net/wlan0/address 2>/dev/null || echo "unknown")
echo "wlan0 MAC: $WLAN_MAC"
echo ""
echo "⚠️  IMPORTANT: MAC address changes after factory reset!"
echo "   If you have MAC filtering on your router/firewall,"
echo "   you'll need to update the whitelist after each reset."
echo ""

# === WiFi and Network Status ===
echo "=== WiFi Status ==="
# Try multiple commands to get WiFi status
if command -v iwconfig >/dev/null 2>&1; then
    iwconfig wlan0 2>/dev/null
elif command -v iw >/dev/null 2>&1; then
    iw dev wlan0 info 2>/dev/null
else
    echo "Interface state: $(cat /sys/class/net/wlan0/operstate 2>/dev/null || echo 'unknown')"
fi
echo ""

echo "=== IP Address ==="
# Try ip command first, fall back to ifconfig or cat /proc/net
if command -v ip >/dev/null 2>&1; then
    ip addr show wlan0
elif command -v ifconfig >/dev/null 2>&1; then
    ifconfig wlan0
else
    echo "Checking via /sys filesystem..."
    if [ -d /sys/class/net/wlan0 ]; then
        echo "wlan0 exists"
        echo "MAC Address: $(cat /sys/class/net/wlan0/address 2>/dev/null)"
        echo "State: $(cat /sys/class/net/wlan0/operstate 2>/dev/null)"
        # Try to get IP from busybox or other tools
        if command -v busybox >/dev/null 2>&1; then
            busybox ifconfig wlan0
        fi
    else
        echo "wlan0 interface not found"
    fi
fi
echo ""

echo "=== Routing Table ==="
if command -v ip >/dev/null 2>&1; then
    ip route
elif command -v route >/dev/null 2>&1; then
    route -n
elif command -v netstat >/dev/null 2>&1; then
    netstat -rn
else
    echo "No routing tools available"
fi
echo ""

echo "=== Internet Connectivity ==="
ping -c 3 8.8.8.8 2>/dev/null || echo "No internet connectivity or ping not available"
echo ""

echo "=== DNS Configuration ==="
if [ -f /etc/resolv.conf ]; then
    echo "✓ /etc/resolv.conf exists"
    echo "DNS Servers:"
    grep nameserver /etc/resolv.conf | head -5
    echo ""
    echo "Testing DNS resolution:"
    if command -v nslookup >/dev/null 2>&1; then
        nslookup raw.githubusercontent.com 2>&1 | head -10
    elif command -v dig >/dev/null 2>&1; then
        dig raw.githubusercontent.com +short 2>&1 | head -5
    elif command -v host >/dev/null 2>&1; then
        host raw.githubusercontent.com 2>&1
    else
        echo "No DNS lookup tools available"
    fi
else
    echo "✗ /etc/resolv.conf NOT FOUND"
    echo "  This will prevent FreeSleep installation from working!"
fi
echo ""

echo "=== Network Configuration Type ==="
if [ -f /etc/systemd/network/25-wlan0.network ]; then
    echo "✓ systemd-networkd configuration found"
    if grep -q "DHCP=yes" /etc/systemd/network/25-wlan0.network 2>/dev/null; then
        echo "  Mode: DHCP"
    elif grep -q "Address=" /etc/systemd/network/25-wlan0.network 2>/dev/null; then
        echo "  Mode: Static IP"
        echo "  Configuration:"
        grep -E "Address=|Gateway=|DNS=" /etc/systemd/network/25-wlan0.network | sed 's/^/    /'
    fi
else
    echo "ℹ systemd-networkd config not found"
fi
echo ""

# === Service Status ===
echo "=========================================="
echo "Services That SHOULD Be Running"
echo "=========================================="
echo ""

echo "=== opensleep-wifi Service ==="
echo "Purpose: Creates wlan0 interface by bypassing EEPROM WiFi check"
echo "Status:"
systemctl status opensleep-wifi --no-pager || echo "opensleep-wifi service not found"
echo ""

echo "=== wpa_supplicant Service ==="
echo "Purpose: Manages WiFi authentication and connection"
echo "Status:"
systemctl status wpa_supplicant@wlan0 --no-pager || echo "wpa_supplicant service not running"
echo ""

echo "=== ssh-early Service ==="
echo "Purpose: Enables SSH access early in boot process"
echo "Status:"
systemctl status ssh-early --no-pager || echo "ssh-early service not found"
echo ""

echo "=== FreeSleep Service ==="
echo "Purpose: Main FreeSleep server for Pod control and web interface"
echo "Status:"
systemctl status free-sleep --no-pager || echo "free-sleep service not found"
echo ""

echo "=== FreeSleep Installer Service ==="
echo "Purpose: Auto-installer for FreeSleep (runs once on first boot)"
echo "Status:"
systemctl status freesleep-installer --no-pager || echo "freesleep-installer service not found (may have already completed)"
if [ -f /var/lib/freesleep-installed.flag ]; then
    echo "✓ FreeSleep installation completed (flag exists)"
else
    echo "⚠ FreeSleep installation may not have completed yet"
fi
echo ""

echo "=========================================="
echo "Services That Should NOT Be Running"
echo "=========================================="
echo ""

echo "=== variscite-wifi Service ==="
echo "Purpose: Original Eight Sleep WiFi service (replaced by opensleep-wifi)"
echo "Expected: masked (symlinked to /dev/null)"
echo "Status:"
systemctl status variscite-wifi --no-pager || echo "variscite-wifi masked or not found"
echo ""

echo "=== capybara Service ==="
echo "Purpose: Eight Sleep's main control daemon (conflicts with FreeSleep)"
echo "Expected: disabled/inactive/masked"
echo "Status:"
systemctl status capybara --no-pager || echo "capybara service status"
echo ""

echo "=== Eight Sleep Services (Should be disabled) ==="
echo "Expected: swupdate-progress, swupdate, defibrillator, eight-kernel, telegraf, vector, frankenfirmware, dac"
echo "Status:"
for service in swupdate-progress swupdate defibrillator eight-kernel telegraf vector frankenfirmware dac swupdate.socket; do
    if systemctl is-active "$service" >/dev/null 2>&1; then
        echo "  ⚠ $service is ACTIVE (should be disabled)"
    elif systemctl is-masked "$service" >/dev/null 2>&1; then
        echo "  ✓ $service is masked"
    else
        echo "  ✓ $service is inactive"
    fi
done
echo ""

# === Verify Files ===
echo "=== Check opensleep-wifi script exists ==="
if [ -f /etc/wifi/opensleep-wifi ]; then
    ls -la /etc/wifi/opensleep-wifi
    echo "✓ opensleep-wifi script found"
else
    echo "✗ opensleep-wifi script NOT found"
fi
echo ""

echo "=== Check SSH key ==="
CURRENT_USER=$(whoami)
echo "Current user: $CURRENT_USER"
SSH_KEY_FOUND=false
for key_path in /home/$CURRENT_USER/.ssh/authorized_keys /home/root/.ssh/authorized_keys /root/.ssh/authorized_keys ~/.ssh/authorized_keys; do
    if [ -f "$key_path" ]; then
        ls -la "$key_path"
        echo "✓ SSH authorized_keys found at $key_path"
        echo "Key fingerprint:"
        ssh-keygen -lf "$key_path" 2>/dev/null || echo "Could not read key fingerprint"
        SSH_KEY_FOUND=true
        break
    fi
done
if [ "$SSH_KEY_FOUND" = false ]; then
    echo "ℹ SSH authorized_keys NOT found (using password authentication)"
fi
echo ""

echo "=== Check FreeSleep installation ==="
FREESLEEP_DIR="/home/dac/free-sleep"
if [ -d "$FREESLEEP_DIR" ]; then
    ls -la "$FREESLEEP_DIR"
    echo "✓ FreeSleep directory found at $FREESLEEP_DIR"
    
    # Check for server files
    if [ -f "$FREESLEEP_DIR/server/package.json" ]; then
        echo "✓ FreeSleep server files found"
    else
        echo "⚠ FreeSleep server files not found"
    fi
    
    # Check for data directory
    if [ -d "/persistent/free-sleep-data" ]; then
        echo "✓ FreeSleep data directory exists"
        du -sh /persistent/free-sleep-data 2>/dev/null || echo "  (size unknown)"
    else
        echo "⚠ FreeSleep data directory not found"
    fi
else
    echo "✗ FreeSleep directory NOT found (may not have been installed with -f option)"
fi
echo ""

echo "=== Check FreeSleep web interface ==="
if systemctl is-active free-sleep >/dev/null 2>&1; then
    # Get the local IP address
    LOCAL_IP=$(ip addr show wlan0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1)
    if [ -n "$LOCAL_IP" ]; then
        echo "FreeSleep web interface should be accessible at:"
        echo "  http://$LOCAL_IP:3000"
    else
        echo "FreeSleep web interface should be accessible at:"
        echo "  http://<POD_IP>:3000"
    fi
else
    echo "FreeSleep service is not running, web interface not available"
fi
echo ""

echo "=== Boot Sequence Status ==="
echo "Checking boot flags and logs..."
echo ""
echo "Flag Files:"
if [ -f /var/lib/firstboot-complete.flag ]; then
    echo "  ✓ firstboot-complete.flag exists (created: $(stat -c %y /var/lib/firstboot-complete.flag 2>/dev/null || echo 'unknown'))"
else
    echo "  ✗ firstboot-complete.flag MISSING (firstboot-reboot never ran)"
fi

if [ -f /var/lib/eightsleep-disabled.flag ]; then
    echo "  ✓ eightsleep-disabled.flag exists (created: $(stat -c %y /var/lib/eightsleep-disabled.flag 2>/dev/null || echo 'unknown'))"
else
    echo "  ✗ eightsleep-disabled.flag MISSING (Eight Sleep services not disabled yet)"
fi

if [ -f /var/lib/freesleep-installed.flag ]; then
    echo "  ✓ freesleep-installed.flag exists (created: $(stat -c %y /var/lib/freesleep-installed.flag 2>/dev/null || echo 'unknown'))"
else
    echo "  ✗ freesleep-installed.flag MISSING (FreeSleep not installed yet)"
fi
echo ""

echo "Boot Logs:"
if [ -f /var/log/firstboot.log ]; then
    echo "  ✓ firstboot.log:"
    cat /var/log/firstboot.log | sed 's/^/    /'
else
    echo "  ℹ firstboot.log not found"
fi

if [ -f /var/log/eightsleep-disabled.log ]; then
    echo "  ✓ eightsleep-disabled.log:"
    cat /var/log/eightsleep-disabled.log | sed 's/^/    /'
else
    echo "  ℹ eightsleep-disabled.log not found"
fi

if [ -f /var/log/freesleep-install.log ]; then
    echo "  ✓ freesleep-install.log:"
    cat /var/log/freesleep-install.log | sed 's/^/    /'
else
    echo "  ℹ freesleep-install.log not found"
fi
echo ""

echo "Boot Count:"
journalctl --list-boots --no-pager 2>&1 | grep -v "Warning:" | grep -v "Failed to search" || echo "  Unable to read boot history"
echo ""

echo "=== Check biometrics status ==="
if [ -f "$FREESLEEP_DIR/biometrics/db.py" ]; then
    echo "✓ Biometrics module found"
    # Check if biometrics packages are installed
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "import numpy, scipy, pandas" 2>/dev/null && echo "✓ Python biometrics dependencies installed" || echo "⚠ Python biometrics dependencies not installed"
    fi
else
    echo "⚠ Biometrics module not found"
fi
echo ""

echo "=== FreeSleep service logs (last 30 lines) ==="
if systemctl is-active free-sleep >/dev/null 2>&1; then
    # Use journalctl if available
    if command -v journalctl >/dev/null 2>&1; then
        # Suppress the ACL/permission warnings
        journalctl -u free-sleep --no-pager -n 30 2>&1 | grep -v "Warning: some journal files were not opened" | grep -v "Failed to search journal ACL" || echo "(no recent logs or insufficient permissions)"
    else
        echo "(journalctl not available, checking log files...)"
        if [ -f /persistent/free-sleep-data/logs/server.log ]; then
            tail -30 /persistent/free-sleep-data/logs/server.log
        else
            echo "(no log files found)"
        fi
    fi
else
    echo "FreeSleep service is not active, checking installation logs..."
    if command -v journalctl >/dev/null 2>&1; then
        journalctl -u freesleep-installer --no-pager -n 30 2>&1 | grep -v "Warning: some journal files were not opened" | grep -v "Failed to search journal ACL" || echo "(no installer logs)"
    elif [ -f /var/log/freesleep-install.log ]; then
        tail -30 /var/log/freesleep-install.log
    else
        echo "(no logs available)"
    fi
fi
echo ""

# === Boot Order Verification ===
echo "=== Service Dependencies (opensleep-wifi) ==="
systemctl list-dependencies opensleep-wifi --no-pager | head -20
echo ""

echo "=== Service Dependencies (ssh-early) ==="
systemctl list-dependencies ssh-early --no-pager | head -20
echo ""

# === Masked Services ===
echo "=== Verify variscite-wifi is masked ==="
systemctl is-enabled variscite-wifi 2>/dev/null || echo "variscite-wifi status check"
ls -la /etc/systemd/system/variscite-wifi.service 2>/dev/null || echo "variscite-wifi service file not found in /etc/systemd/system"
echo ""

# === Summary ===
echo "========================================"
echo "Validation Summary"
echo "========================================"

# Check critical items
ERRORS=0

# Check for IP address using available tools
HAS_IP=false
if command -v ip >/dev/null 2>&1; then
    if ip addr show wlan0 2>/dev/null | grep -q "inet "; then
        HAS_IP=true
    fi
elif command -v ifconfig >/dev/null 2>&1; then
    if ifconfig wlan0 2>/dev/null | grep -q "inet "; then
        HAS_IP=true
    fi
fi

if [ "$HAS_IP" = false ]; then
    echo "✗ wlan0 does not have an IP address"
    ((ERRORS++))
else
    echo "✓ wlan0 has an IP address"
fi

if ! systemctl is-active opensleep-wifi >/dev/null 2>&1; then
    echo "✗ opensleep-wifi service is not active"
    ((ERRORS++))
else
    echo "✓ opensleep-wifi service is active"
fi

if ! systemctl is-active wpa_supplicant@wlan0 >/dev/null 2>&1; then
    echo "✗ wpa_supplicant@wlan0 service is not active"
    ((ERRORS++))
else
    echo "✓ wpa_supplicant@wlan0 service is active"
fi

if ! systemctl is-active ssh-early >/dev/null 2>&1; then
    echo "✗ ssh-early service is not active"
    ((ERRORS++))
else
    echo "✓ ssh-early service is active"
fi

# SSH key check is informational only (password auth is valid too)
SSH_KEY_EXISTS=false
for key_path in /home/root/.ssh/authorized_keys /root/.ssh/authorized_keys ~/.ssh/authorized_keys; do
    if [ -f "$key_path" ]; then
        SSH_KEY_EXISTS=true
        break
    fi
done
if [ "$SSH_KEY_EXISTS" = true ]; then
    echo "✓ SSH key-based authentication configured"
else
    echo "ℹ Using SSH password authentication"
fi

if systemctl is-active variscite-wifi >/dev/null 2>&1; then
    echo "⚠ variscite-wifi service is still active (should be masked)"
    ((ERRORS++))
else
    echo "✓ variscite-wifi service is masked/inactive"
fi

# Check FreeSleep service
if systemctl is-active free-sleep >/dev/null 2>&1; then
    echo "✓ FreeSleep service is active"
else
    echo "✗ FreeSleep service is not active"
    # Check if installation completed
    if [ -f /var/lib/freesleep-installed.flag ]; then
        echo "  (installation completed but service not running - check logs)"
        ((ERRORS++))
    else
        echo "  (installation may still be in progress)"
    fi
fi

# Check FreeSleep directory
if [ -d /home/dac/free-sleep ]; then
    echo "✓ FreeSleep directory exists"
else
    echo "✗ FreeSleep directory not found"
    ((ERRORS++))
fi

# Check DNS configuration
if [ ! -f /etc/resolv.conf ]; then
    echo "✗ /etc/resolv.conf missing - DNS will not work!"
    ((ERRORS++))
elif ! grep -q nameserver /etc/resolv.conf 2>/dev/null; then
    echo "✗ /etc/resolv.conf has no nameservers"
    ((ERRORS++))
else
    echo "✓ DNS configuration exists"
fi

# Check boot sequence completion
if [ ! -f /var/lib/firstboot-complete.flag ]; then
    echo "✗ First boot sequence not complete"
    ((ERRORS++))
else
    echo "✓ First boot completed"
fi

echo ""
echo "=== Eight Sleep Services Status ==="
EIGHT_SLEEP_SERVICES="swupdate-progress swupdate defibrillator eight-kernel telegraf vector frankenfirmware dac swupdate.socket"
for service in $EIGHT_SLEEP_SERVICES; do
    if systemctl is-active "$service" >/dev/null 2>&1; then
        echo "⚠ $service is still active (should be disabled)"
    elif systemctl is-masked "$service" >/dev/null 2>&1; then
        echo "✓ $service is masked"
    elif systemctl is-enabled "$service" >/dev/null 2>&1; then
        echo "⚠ $service is enabled but not running"
    else
        echo "✓ $service is disabled/inactive"
    fi
done

echo ""
if [ $ERRORS -eq 0 ]; then
    echo "✓✓✓ All critical checks passed! ✓✓✓"
    echo "Pod 3 FreeSleep deployment is successful."
    echo ""
    echo "Next steps:"
    echo "  - Access web interface: http://<POD_IP>:3000"
    echo "  - Check logs: journalctl -u free-sleep -f"
    echo "  - Enable biometrics: /home/dac/free-sleep/scripts/enable_biometrics.sh"
else
    echo "✗✗✗ Found $ERRORS issue(s) ✗✗✗"
    echo "Review the output above for details."
    echo ""
    echo "Common troubleshooting:"
    echo "  - Check installation logs: journalctl -u freesleep-installer"
    echo "  - Check FreeSleep logs: journalctl -u free-sleep"
    echo "  - Verify network: ping 8.8.8.8"
    echo "  - Check WiFi: systemctl status wpa_supplicant@wlan0"
fi

echo ""
echo "========================================"
