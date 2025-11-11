#!/usr/bin/env bash
# Initialize PCAL6416A GPIO expander to enable Pod subsystems
# This replaces Capybara's hardware initialization function

set -euo pipefail

echo "Enabling Pod subsystems via PCAL6416A GPIO expander..."

# Detect which I2C bus has the GPIO expander at 0x20
GPIO_ADDR=0x20
I2C_BUS=""

for bus in 0 1 2 3; do
    if i2cdetect -y $bus 2>/dev/null | grep -q " 20 "; then
        I2C_BUS=$bus
        echo "Found GPIO expander on I2C bus $I2C_BUS"
        break
    fi
done

if [ -z "$I2C_BUS" ]; then
    echo "ERROR: GPIO expander not found on any I2C bus"
    exit 1
fi

# Configure Port 0 (register 0x06): Output configuration
echo "Configuring Port 0..."
i2cset -y $I2C_BUS $GPIO_ADDR 0x06 0xFC

# Configure Port 1 (register 0x07): Output configuration
echo "Configuring Port 1..."
i2cset -y $I2C_BUS $GPIO_ADDR 0x07 0x31

# Assert reset (register 0x02): Enable subsystems
echo "Asserting reset..."
i2cset -y $I2C_BUS $GPIO_ADDR 0x02 0xFE

# Enable subsystems (register 0x02): Final configuration
echo "Enabling subsystems..."
i2cset -y $I2C_BUS $GPIO_ADDR 0x02 0xFD

echo "✓ Subsystems enabled successfully on I2C bus $I2C_BUS"
