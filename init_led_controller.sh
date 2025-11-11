#!/usr/bin/env bash
# Initialize IS31FL3194 LED controller for FreeSleep
# This script can be run standalone to test LED initialization

set -euo pipefail

echo "Initializing IS31FL3194 LED controller..."

# Detect which I2C bus has the LED controller at 0x53
LED_ADDR=0x53
I2C_BUS=""

for bus in 0 1 2 3; do
    if i2cdetect -y $bus 2>/dev/null | grep -q " 53 "; then
        I2C_BUS=$bus
        echo "Found LED controller on I2C bus $I2C_BUS"
        break
    fi
done

if [ -z "$I2C_BUS" ]; then
    echo "ERROR: LED controller not found on any I2C bus"
    exit 1
fi

echo "Initializing IS31FL3194..."

# Register 0x00: Shutdown register (0x01 = normal operation, 0x00 = shutdown)
echo "  - Setting normal operation mode..."
i2cset -y $I2C_BUS $LED_ADDR 0x00 0x01

# Small delay for IC to wake up
sleep 0.1

# Register 0x01: Configuration register
# Bit 0: Color mode (0=GRB, 1=RGB) - use 0 for GRB mode
# Bit 1-2: Current setting (00=40mA max current per channel)
echo "  - Configuring color mode and current..."
i2cset -y $I2C_BUS $LED_ADDR 0x01 0x00

# Register 0x03: Output 1 (Red/Green channel) - Set to 100 (0x64) brightness
echo "  - Setting channel 1 brightness..."
i2cset -y $I2C_BUS $LED_ADDR 0x03 0x64

# Register 0x04: Output 2 (Green/Red channel) - Set to 100 (0x64) brightness
echo "  - Setting channel 2 brightness..."
i2cset -y $I2C_BUS $LED_ADDR 0x04 0x64

# Register 0x05: Output 3 (Blue channel) - Set to 100 (0x64) brightness
echo "  - Setting channel 3 brightness..."
i2cset -y $I2C_BUS $LED_ADDR 0x05 0x64

# Register 0x07: Color update register - Write 0x00 to apply changes
echo "  - Applying color changes..."
i2cset -y $I2C_BUS $LED_ADDR 0x07 0x00

echo "✓ LED controller initialized successfully on I2C bus $I2C_BUS"

# Verify initialization by reading back registers
echo ""
echo "Verification (reading registers):"
echo "  Shutdown (0x00): $(i2cget -y $I2C_BUS $LED_ADDR 0x00)"
echo "  Config (0x01):   $(i2cget -y $I2C_BUS $LED_ADDR 0x01)"
echo "  Channel 1 (0x03): $(i2cget -y $I2C_BUS $LED_ADDR 0x03)"
echo "  Channel 2 (0x04): $(i2cget -y $I2C_BUS $LED_ADDR 0x04)"
echo "  Channel 3 (0x05): $(i2cget -y $I2C_BUS $LED_ADDR 0x05)"
echo ""
echo "LED controller is now ready for frank to control!"
