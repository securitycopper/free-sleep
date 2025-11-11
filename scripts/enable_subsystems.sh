#!/bin/bash
#
# Enable Pod Subsystems via PCAL6416A GPIO Expander
# 
# This script configures the PCAL6416A I2C GPIO expander at address 0x20
# to enable the Frozen (temperature control) and Sensor subsystems.
#
# Based on OpenSleep's reset.rs implementation.
# Datasheet: https://www.nxp.com/docs/en/data-sheet/PCAL6416A.pdf
#

set -e

I2C_BUS=1
I2C_ADDR=0x20

# Register addresses
REG_OUTPUT_PORT_0=0x02
REG_CONFIG_PORT_0=0x06
REG_CONFIG_PORT_1=0x07

# Configuration values
PORT_0_CONFIG=0xFC  # 0b11111100 - pins 0,1 as outputs
PORT_1_CONFIG=0x31  # 0b00110001
OUTPUT_RESET=0xFF   # 0b11111111 - assert reset (all high)
OUTPUT_ENABLED=0xFD # 0b11111101 - de-assert reset (bit 1 low = enable)

echo "Enabling Pod subsystems via PCAL6416A GPIO expander..."

# Check if i2c-tools is available
if ! command -v i2cset &> /dev/null; then
    echo "ERROR: i2cset not found. Install i2c-tools package."
    exit 1
fi

# Check if device exists on I2C bus
if ! i2cdetect -y $I2C_BUS | grep -q "20"; then
    echo "WARNING: PCAL6416A not detected at address 0x$I2C_ADDR on bus $I2C_BUS"
    echo "Attempting to continue anyway..."
fi

# Step 1: Configure port 0 (set pins 0,1 as outputs)
echo "Configuring Port 0..."
i2cset -y $I2C_BUS $I2C_ADDR $REG_CONFIG_PORT_0 $PORT_0_CONFIG
sleep 0.01

# Step 2: Configure port 1
echo "Configuring Port 1..."
i2cset -y $I2C_BUS $I2C_ADDR $REG_CONFIG_PORT_1 $PORT_1_CONFIG
sleep 0.01

# Step 3: Assert reset (set all pins high)
echo "Asserting reset..."
i2cset -y $I2C_BUS $I2C_ADDR $REG_OUTPUT_PORT_0 $OUTPUT_RESET
sleep 0.1

# Step 4: De-assert reset to enable subsystems (set bit 1 low)
echo "Enabling subsystems..."
i2cset -y $I2C_BUS $I2C_ADDR $REG_OUTPUT_PORT_0 $OUTPUT_ENABLED
sleep 0.1

echo "✓ Subsystems enabled successfully"

# Verify the configuration
echo ""
echo "Current configuration:"
i2cdump -y $I2C_BUS $I2C_ADDR | head -3

exit 0
