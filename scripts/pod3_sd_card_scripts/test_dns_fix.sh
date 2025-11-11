#!/bin/bash
#
# Test DNS Fix Script
# 
# This script tests the DNS resolution fix on a running Pod 3 instance
# without rebuilding the entire image. It simulates what the patched
# image will do to fix the /etc/resolv.conf symlink issue.
#
# Usage: ./test_dns_fix.sh
# Run on Pod 3: ssh -p 8822 rewt@192.168.2.52 'bash -s' < test_dns_fix.sh
#

set -e

echo "========================================"
echo "Pod 3 DNS Fix Test Script"
echo "========================================"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root or with sudo"
   echo "Usage: sudo $0"
   exit 1
fi

# Backup existing resolv.conf
echo "[1/6] Backing up existing /etc/resolv.conf..."
if [[ -L /etc/resolv.conf ]]; then
    LINK_TARGET=$(readlink -f /etc/resolv.conf)
    echo "  Current: /etc/resolv.conf -> $LINK_TARGET"
    cp -L /etc/resolv.conf /etc/resolv.conf.backup 2>/dev/null || echo "  (symlink is broken, nothing to backup)"
elif [[ -f /etc/resolv.conf ]]; then
    echo "  Current: /etc/resolv.conf is a regular file"
    cp /etc/resolv.conf /etc/resolv.conf.backup
else
    echo "  Current: /etc/resolv.conf does not exist"
fi

# Show current DNS status
echo ""
echo "[2/6] Current DNS status..."
echo "  Checking /run/systemd/resolve/resolv.conf:"
if [[ -f /run/systemd/resolve/resolv.conf ]]; then
    echo "  ✓ systemd-resolved DNS config exists"
    grep "^nameserver" /run/systemd/resolve/resolv.conf | head -3 | sed 's/^/    /'
else
    echo "  ✗ systemd-resolved DNS config NOT found"
fi

echo ""
echo "  Current DNS resolution test:"
if nslookup raw.githubusercontent.com >/dev/null 2>&1; then
    echo "  ✓ DNS already working"
else
    echo "  ✗ DNS NOT working (expected)"
fi

# Remove broken symlink and create new one
echo ""
echo "[3/6] Fixing /etc/resolv.conf symlink..."
rm -f /etc/resolv.conf
ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
echo "  ✓ Removed old symlink"
echo "  ✓ Created new symlink: /etc/resolv.conf -> /run/systemd/resolve/resolv.conf"

# Verify the fix
echo ""
echo "[4/6] Verifying /etc/resolv.conf..."
if [[ -L /etc/resolv.conf ]]; then
    LINK_TARGET=$(readlink -f /etc/resolv.conf)
    echo "  ✓ /etc/resolv.conf -> $LINK_TARGET"
    
    if [[ -f /etc/resolv.conf ]]; then
        echo "  ✓ Symlink target exists and is readable"
        echo ""
        echo "  Nameservers in /etc/resolv.conf:"
        grep "^nameserver" /etc/resolv.conf | sed 's/^/    /'
    else
        echo "  ✗ Symlink target does not exist or is not readable"
        exit 1
    fi
else
    echo "  ✗ /etc/resolv.conf is not a symlink"
    exit 1
fi

# Test DNS resolution
echo ""
echo "[5/6] Testing DNS resolution..."
echo "  Testing: raw.githubusercontent.com"

if nslookup raw.githubusercontent.com; then
    echo ""
    echo "  ✓ DNS resolution SUCCESSFUL!"
else
    echo ""
    echo "  ✗ DNS resolution FAILED"
    exit 1
fi

# Test FreeSleep installer URL
echo ""
echo "[6/6] Testing FreeSleep installer download..."
echo "  Testing: https://raw.githubusercontent.com/eightsleep/free-sleep/main/scripts/install.sh"

if curl -fsSL --max-time 10 "https://raw.githubusercontent.com/eightsleep/free-sleep/main/scripts/install.sh" >/dev/null 2>&1; then
    echo "  ✓ FreeSleep installer URL is reachable!"
else
    echo "  ✗ FreeSleep installer URL NOT reachable"
    echo "  (This might be expected if using a custom repository)"
fi

echo ""
echo "========================================"
echo "✓ DNS Fix Test PASSED!"
echo "========================================"
echo ""
echo "Summary:"
echo "  • /etc/resolv.conf symlink fixed"
echo "  • DNS resolution working"
echo "  • FreeSleep installation should now succeed"
echo ""
echo "To restore original configuration:"
echo "  sudo rm /etc/resolv.conf"
echo "  sudo cp /etc/resolv.conf.backup /etc/resolv.conf"
echo ""
echo "To test FreeSleep installer manually:"
echo "  curl -fsSL https://raw.githubusercontent.com/<your-repo>/free-sleep/<branch>/scripts/install.sh | bash"
echo ""
