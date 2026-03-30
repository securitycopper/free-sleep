#!/bin/bash

# Manual Transition to FreeSleep
# Run this script AFTER Eight Sleep app pairing is complete
# This is a fallback if monitor-pairing.service doesn't work correctly

set -e

echo "========================================"
echo "Manual Transition to FreeSleep"
echo "========================================"
echo ""

# Check if already transitioned
if [ -f /var/lib/pairing-complete.flag ]; then
    echo "✓ System already transitioned (pairing-complete.flag exists)"
    echo "  Update services should already be disabled"
    exit 0
fi

# Check if WiFi is configured
if [ ! -f /etc/NetworkManager/system-connections/customer-wifi.nmconnection ]; then
    echo "❌ ERROR: customer-wifi.nmconnection not found"
    echo "   Please pair the Pod with Eight Sleep app first"
    exit 1
fi

echo "✓ WiFi configured (customer-wifi.nmconnection exists)"
echo ""

# Confirm with user
read -p "Have you completed pairing with Eight Sleep app? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted. Complete pairing first, then run this script again."
    exit 1
fi

echo ""
echo "[*] Disabling Eight Sleep update services..."

# Disable update services
for svc in swupdate-progress swupdate defibrillator swupdate.socket; do
    echo "  Disabling $svc..."
    sudo systemctl disable --now "$svc" 2>&1 || true
    sudo systemctl mask "$svc" 2>&1 || true
done

echo ""
echo "[*] Creating pairing-complete flag..."
sudo touch /var/lib/pairing-complete.flag

echo ""
echo "✅ Transition complete!"
echo ""
echo "Next steps:"
echo "  1. Update services are now disabled"
echo "  2. FreeSleep installer should trigger automatically"
echo "  3. Check status: sudo systemctl status freesleep-installer"
echo ""
