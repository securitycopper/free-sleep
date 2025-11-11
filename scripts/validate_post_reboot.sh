#!/bin/bash
#
# Post-Reboot Validation Script
# Run this after rebooting to validate subsystem initialization and FreeSleep operation
#

echo "=========================================="
echo "FreeSleep Post-Reboot Validation"
echo "=========================================="
echo ""

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

pass() {
    echo -e "${GREEN}✓${NC} $1"
}

fail() {
    echo -e "${RED}✗${NC} $1"
}

warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# 1. Check Capybara is stopped
echo "1. Checking Capybara service..."
if systemctl is-active --quiet capybara; then
    fail "Capybara is still running"
elif systemctl is-enabled --quiet capybara; then
    warn "Capybara is not masked (should be masked)"
else
    pass "Capybara is stopped and masked"
fi
echo ""

# 2. Check subsystem initialization service
echo "2. Checking enable-subsystems service..."
if systemctl is-enabled --quiet enable-subsystems.service; then
    pass "enable-subsystems.service is enabled"
    
    if systemctl is-active --quiet enable-subsystems.service; then
        pass "enable-subsystems.service is active (exited)"
    else
        fail "enable-subsystems.service is not active"
        systemctl status enable-subsystems.service --no-pager | head -15
    fi
else
    fail "enable-subsystems.service is not enabled"
fi
echo ""

# 3. Check frankenfirmware
echo "3. Checking frankenfirmware..."
if pgrep -x frankenfirmware > /dev/null; then
    pass "frankenfirmware is running"
else
    fail "frankenfirmware is NOT running"
fi
echo ""

# 4. Check FreeSleep service
echo "4. Checking free-sleep service..."
if systemctl is-active --quiet free-sleep.service; then
    pass "free-sleep.service is active"
else
    fail "free-sleep.service is not active"
    systemctl status free-sleep.service --no-pager | head -15
fi
echo ""

# 5. Check dac.sock connection
echo "5. Checking dac.sock connection..."
if [ -S /deviceinfo/dac.sock ]; then
    pass "dac.sock exists"
    
    # Check if FreeSleep is connected
    if lsof /deviceinfo/dac.sock 2>/dev/null | grep -q node; then
        pass "FreeSleep connected to dac.sock"
    else
        warn "dac.sock exists but no node process connected"
    fi
else
    fail "dac.sock does NOT exist"
fi
echo ""

# 6. Check GPIO expander state
echo "6. Checking GPIO expander (PCAL6416A)..."
if command -v i2cdump &> /dev/null; then
    OUTPUT=$(i2cget -y 1 0x20 0x02 2>&1)
    if [ $? -eq 0 ]; then
        VALUE=$(echo $OUTPUT | grep -oE '0x[0-9a-fA-F]+')
        if [ "$VALUE" = "0xfd" ] || [ "$VALUE" = "0xFD" ]; then
            pass "GPIO expander configured correctly ($VALUE = enabled)"
        else
            warn "GPIO expander value unexpected: $VALUE (expected 0xFD)"
        fi
    else
        fail "Failed to read GPIO expander"
    fi
else
    warn "i2c-tools not installed, skipping GPIO check"
fi
echo ""

# 7. Check LED controller state
echo "7. Checking LED controller (IS31FL3194)..."
if command -v i2cget &> /dev/null; then
    LED_REG=$(i2cget -y 1 0x53 0x00 2>&1)
    if [ $? -eq 0 ]; then
        pass "LED controller accessible (register 0x00 = $LED_REG)"
        echo "   → Check LED visually: Is it blinking blue? (Should NOT be)"
    else
        warn "Failed to read LED controller"
    fi
else
    warn "i2c-tools not installed, skipping LED check"
fi
echo ""

# 8. Check boot log for service order
echo "8. Checking boot service order..."
echo "   Services should start in order: enable-subsystems → frank → free-sleep"
journalctl -b | grep -E "(enable-subsystems|frank.sh|free-sleep)" | grep -E "(Started|Starting|Finished)" | head -10
echo ""

# 9. Check for errors
echo "9. Checking for errors in logs..."
ERROR_COUNT=$(journalctl -b -p err | wc -l)
if [ $ERROR_COUNT -eq 0 ]; then
    pass "No errors in boot logs"
else
    warn "$ERROR_COUNT error entries found in boot logs"
    echo "   Run: journalctl -b -p err  to view"
fi
echo ""

# 10. Summary
echo "=========================================="
echo "Validation Summary"
echo "=========================================="
echo ""
echo "Critical checks:"
echo "  - Capybara stopped: $(systemctl is-active capybara 2>&1 | grep -q inactive && echo YES || echo NO)"
echo "  - Subsystem init: $(systemctl is-active enable-subsystems.service 2>&1 | grep -q exited && echo YES || echo NO)"
echo "  - FreeSleep running: $(systemctl is-active free-sleep.service 2>&1 | grep -q active && echo YES || echo NO)"
echo "  - dac.sock exists: $([ -S /deviceinfo/dac.sock ] && echo YES || echo NO)"
echo ""
echo "Visual checks needed:"
echo "  [ ] LED is NOT blinking blue (pairing mode)"
echo "  [ ] Temperature control responds to commands"
echo "  [ ] Sensor data visible in FreeSleep"
echo ""

# Final verdict
if systemctl is-active --quiet capybara; then
    echo -e "${RED}FAIL: Capybara is still running!${NC}"
    exit 1
elif ! systemctl is-active --quiet enable-subsystems.service; then
    echo -e "${RED}FAIL: Subsystem initialization did not run!${NC}"
    exit 1
elif ! systemctl is-active --quiet free-sleep.service; then
    echo -e "${RED}FAIL: FreeSleep is not running!${NC}"
    exit 1
else
    echo -e "${GREEN}PASS: All critical services in correct state${NC}"
    echo "Proceed with manual LED and functionality testing"
    exit 0
fi
