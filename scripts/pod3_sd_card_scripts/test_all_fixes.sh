#!/bin/bash
#
# Test All Fixes Script
# 
# This script validates all the fixes we've implemented on a running Pod 3
# instance before rebuilding the image. It checks:
# 1. Static IP configuration
# 2. DNS resolution (symlink fix)
# 3. Passwordless sudo
# 4. FreeSleep installer accessibility
#
# Usage: ./test_all_fixes.sh
# Run remotely: ssh -p 8822 rewt@192.168.2.52 'bash -s' < test_all_fixes.sh
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ERRORS=0

echo "========================================"
echo "Pod 3 - Test All Fixes"
echo "========================================"
echo ""

# Function to print status
print_status() {
    if [[ $1 -eq 0 ]]; then
        echo -e "${GREEN}✓${NC} $2"
    else
        echo -e "${RED}✗${NC} $2"
        ((ERRORS++))
    fi
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "ℹ $1"
}

# === Test 1: Static IP Configuration ===
echo "=== Test 1: Static IP Configuration ==="

# Check network config
if [[ -f /etc/systemd/network/25-wlan0.network ]]; then
    print_status 0 "systemd-networkd config exists"
    
    if grep -q "Address=192.168.2.52" /etc/systemd/network/25-wlan0.network; then
        print_status 0 "Static IP configured: 192.168.2.52"
    else
        print_status 1 "Static IP NOT found in config"
    fi
    
    if grep -q "Gateway=192.168.2.1" /etc/systemd/network/25-wlan0.network; then
        print_status 0 "Gateway configured: 192.168.2.1"
    else
        print_status 1 "Gateway NOT found in config"
    fi
    
    if grep -q "DNS=192.168.2.1" /etc/systemd/network/25-wlan0.network; then
        print_status 0 "DNS server configured: 192.168.2.1"
    else
        print_status 1 "DNS server NOT found in config"
    fi
else
    print_status 1 "systemd-networkd config NOT found"
fi

# Check actual IP
CURRENT_IP=$(ip addr show wlan0 | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
if [[ "$CURRENT_IP" == "192.168.2.52" ]]; then
    print_status 0 "Current IP matches: $CURRENT_IP"
else
    print_status 1 "Current IP mismatch: $CURRENT_IP (expected 192.168.2.52)"
fi

echo ""

# === Test 2: DNS Resolution (Critical Fix) ===
echo "=== Test 2: DNS Resolution ==="

# Check resolv.conf symlink
if [[ -L /etc/resolv.conf ]]; then
    LINK_TARGET=$(readlink /etc/resolv.conf)
    RESOLVED_TARGET=$(readlink -f /etc/resolv.conf)
    
    if [[ "$LINK_TARGET" == "/run/systemd/resolve/resolv.conf" ]] || [[ "$RESOLVED_TARGET" == "/run/systemd/resolve/resolv.conf" ]]; then
        print_status 0 "/etc/resolv.conf points to systemd-resolved"
        print_info "  Link: $LINK_TARGET -> $RESOLVED_TARGET"
    else
        print_status 1 "/etc/resolv.conf points to wrong location: $LINK_TARGET"
        print_warning "  Expected: /run/systemd/resolve/resolv.conf"
        print_warning "  Actual: $RESOLVED_TARGET"
        print_info "  This is the main issue preventing DNS resolution"
    fi
else
    if [[ -f /etc/resolv.conf ]]; then
        print_warning "/etc/resolv.conf is a regular file (not symlink)"
        if grep -q "^nameserver" /etc/resolv.conf; then
            print_status 0 "Nameservers found in resolv.conf"
        else
            print_status 1 "No nameservers in resolv.conf"
        fi
    else
        print_status 1 "/etc/resolv.conf does NOT exist"
    fi
fi

# Check if systemd-resolved config exists
if [[ -f /run/systemd/resolve/resolv.conf ]]; then
    print_status 0 "systemd-resolved config exists"
    NAMESERVERS=$(grep "^nameserver" /run/systemd/resolve/resolv.conf | wc -l)
    print_info "  Found $NAMESERVERS nameserver(s)"
    grep "^nameserver" /run/systemd/resolve/resolv.conf | sed 's/^/  /'
else
    print_status 1 "systemd-resolved config NOT found"
fi

# Test DNS resolution
echo ""
print_info "Testing DNS resolution..."
if nslookup raw.githubusercontent.com >/dev/null 2>&1; then
    print_status 0 "DNS resolution working (raw.githubusercontent.com)"
else
    print_status 1 "DNS resolution FAILED (raw.githubusercontent.com)"
    print_warning "  This will prevent FreeSleep installation"
fi

echo ""

# === Test 3: Passwordless Sudo ===
echo "=== Test 3: Passwordless Sudo ==="

if [[ -f /etc/sudoers.d/rewt-nopasswd ]]; then
    print_status 0 "rewt sudoers file exists"
    
    # Check permissions
    PERMS=$(stat -c "%a" /etc/sudoers.d/rewt-nopasswd)
    if [[ "$PERMS" == "440" ]]; then
        print_status 0 "Permissions correct: $PERMS"
    else
        print_status 1 "Permissions incorrect: $PERMS (should be 440)"
    fi
    
    # Check content
    if grep -q "rewt ALL=(ALL) NOPASSWD: ALL" /etc/sudoers.d/rewt-nopasswd; then
        print_status 0 "NOPASSWD configuration correct"
    else
        print_status 1 "NOPASSWD configuration missing or incorrect"
    fi
else
    print_status 1 "rewt sudoers file NOT found"
    print_warning "  Will require password for sudo commands"
fi

# Test sudo without password (if we're user rewt)
if [[ "$USER" == "rewt" ]]; then
    print_info "Testing passwordless sudo..."
    if sudo -n true 2>/dev/null; then
        print_status 0 "Passwordless sudo working for rewt user"
    else
        print_status 1 "Passwordless sudo NOT working for rewt user"
    fi
fi

echo ""

# === Test 4: FreeSleep Installation Prerequisites ===
echo "=== Test 4: FreeSleep Installation Prerequisites ==="

# Check network connectivity
if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
    print_status 0 "Internet connectivity (8.8.8.8)"
else
    print_status 1 "No internet connectivity"
fi

# Check GitHub accessibility
if curl -fsSL --max-time 10 "https://raw.githubusercontent.com" >/dev/null 2>&1; then
    print_status 0 "GitHub (raw.githubusercontent.com) accessible"
else
    print_status 1 "GitHub NOT accessible"
fi

# Check if FreeSleep installer can be downloaded
INSTALLER_URL="https://raw.githubusercontent.com/eightsleep/free-sleep/main/scripts/install.sh"
if curl -fsSL --max-time 10 "$INSTALLER_URL" >/dev/null 2>&1; then
    print_status 0 "FreeSleep installer URL reachable"
else
    print_warning "FreeSleep installer URL not reachable"
    print_info "  (May be using custom repository)"
fi

echo ""

# === Test 5: Boot Flags ===
echo "=== Test 5: Boot Sequence Flags ==="

if [[ -f /var/lib/firstboot-complete.flag ]]; then
    print_status 0 "firstboot-complete.flag exists"
    TIMESTAMP=$(stat -c "%y" /var/lib/firstboot-complete.flag)
    print_info "  Created: $TIMESTAMP"
else
    print_status 1 "firstboot-complete.flag NOT found"
fi

if [[ -f /var/lib/eightsleep-disabled.flag ]]; then
    print_status 0 "eightsleep-disabled.flag exists"
else
    print_warning "eightsleep-disabled.flag NOT found (Eight Sleep services may still be running)"
fi

if [[ -f /var/lib/freesleep-installed.flag ]]; then
    print_status 0 "freesleep-installed.flag exists"
else
    print_info "freesleep-installed.flag NOT found (FreeSleep not installed yet)"
fi

echo ""

# === Test 6: Eight Sleep Services ===
echo "=== Test 6: Eight Sleep Services Status ==="

SERVICES_TO_CHECK="capybara swupdate defibrillator dac"
ACTIVE_COUNT=0

for service in $SERVICES_TO_CHECK; do
    if systemctl is-active --quiet $service 2>/dev/null; then
        print_warning "$service is ACTIVE (should be disabled)"
        ((ACTIVE_COUNT++))
    else
        print_status 0 "$service is inactive/disabled"
    fi
done

if [[ $ACTIVE_COUNT -gt 0 ]]; then
    print_warning "Eight Sleep services still running - may interfere with FreeSleep"
fi

echo ""

# === Summary ===
echo "========================================"
if [[ $ERRORS -eq 0 ]]; then
    echo -e "${GREEN}✓ ALL TESTS PASSED${NC}"
    echo "========================================"
    echo ""
    echo "The patched image should work correctly!"
    echo ""
    echo "Next steps:"
    echo "  1. Rebuild the image with the fixed script"
    echo "  2. Flash to SD card"
    echo "  3. Factory reset Pod 3"
    echo "  4. FreeSleep should install automatically"
else
    echo -e "${RED}✗ $ERRORS TEST(S) FAILED${NC}"
    echo "========================================"
    echo ""
    echo "Issues found that need to be addressed:"
    echo ""
    if ! grep -q "/run/systemd/resolve/resolv.conf" /etc/resolv.conf 2>/dev/null; then
        echo "  • DNS FIX NEEDED: Run test_dns_fix.sh to fix /etc/resolv.conf"
    fi
    if [[ ! -f /etc/sudoers.d/rewt-nopasswd ]]; then
        echo "  • SUDO FIX NEEDED: Create /etc/sudoers.d/rewt-nopasswd"
    fi
    if [[ $ACTIVE_COUNT -gt 0 ]]; then
        echo "  • SERVICES FIX NEEDED: Disable Eight Sleep services"
    fi
fi

echo ""
exit $ERRORS
