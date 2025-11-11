#!/bin/bash
# Rainbow LED pattern for 5 seconds before reboot
# Uses IS31FL3194 LED controller in pattern mode

echo "Setting rainbow LED pattern..."

# Reset the LED controller
i2cset -y 1 0x53 0x4F 0xC5

# Set to pattern mode (bit 0 = 0 for pattern mode)
i2cset -y 1 0x53 0x01 0x00

# Enable all outputs
i2cset -y 1 0x53 0x02 0x07

# Set current band to 30mA (Band 3)
i2cset -y 1 0x53 0x03 0xAA

# Pattern 1: Red -> Yellow -> Green
# Color 1: Red (BRG order: B=0, R=255, G=0)
i2cset -y 1 0x53 0x10 0x00  # Blue
i2cset -y 1 0x53 0x11 0xFF  # Red
i2cset -y 1 0x53 0x12 0x00  # Green

# Color 2: Yellow (BRG: B=0, R=255, G=255)
i2cset -y 1 0x53 0x13 0x00  # Blue
i2cset -y 1 0x53 0x14 0xFF  # Red
i2cset -y 1 0x53 0x15 0xFF  # Green

# Color 3: Green (BRG: B=0, R=0, G=255)
i2cset -y 1 0x53 0x16 0x00  # Blue
i2cset -y 1 0x53 0x17 0x00  # Red
i2cset -y 1 0x53 0x18 0xFF  # Green

# Pattern 2: Cyan -> Blue -> Magenta
# Color 1: Cyan (BRG: B=255, R=0, G=255)
i2cset -y 1 0x53 0x19 0xFF  # Blue
i2cset -y 1 0x53 0x1A 0x00  # Red
i2cset -y 1 0x53 0x1B 0xFF  # Green

# Color 2: Blue (BRG: B=255, R=0, G=0)
i2cset -y 1 0x53 0x1C 0xFF  # Blue
i2cset -y 1 0x53 0x1D 0x00  # Red
i2cset -y 1 0x53 0x1E 0x00  # Green

# Color 3: Magenta (BRG: B=255, R=255, G=0)
i2cset -y 1 0x53 0x1F 0xFF  # Blue
i2cset -y 1 0x53 0x20 0xFF  # Red
i2cset -y 1 0x53 0x21 0x00  # Green

# Pattern 3: Red -> White -> Red
# Color 1: Red (BRG: B=0, R=255, G=0)
i2cset -y 1 0x53 0x22 0x00  # Blue
i2cset -y 1 0x53 0x23 0xFF  # Red
i2cset -y 1 0x53 0x24 0x00  # Green

# Color 2: White (BRG: B=255, R=255, G=255)
i2cset -y 1 0x53 0x25 0xFF  # Blue
i2cset -y 1 0x53 0x26 0xFF  # Red
i2cset -y 1 0x53 0x27 0xFF  # Green

# Color 3: Red (BRG: B=0, R=255, G=0)
i2cset -y 1 0x53 0x28 0x00  # Blue
i2cset -y 1 0x53 0x29 0xFF  # Red
i2cset -y 1 0x53 0x2A 0x00  # Green

# Timing configuration for fast transitions
# Using timing index 2 (0.26s) for fast rainbow effect
# Timing format: bits 7-4 = T4, bits 3-0 = T1
# T1 (rise), T2 (hold), T3 (fall), T4 (between pulses)
# Using: start=0, rise=2, hold=0, fall=2, between=0, off=0
# This gives ~0.26s fade in, no hold, ~0.26s fade out = ~0.5s per color

# Pattern 1 timing (registers 0x2B-0x2D)
i2cset -y 1 0x53 0x2B 0x02  # T1=2 (rise ~0.26s), start=0
i2cset -y 1 0x53 0x2C 0x20  # T3=2 (fall ~0.26s), T2=0 (no hold)
i2cset -y 1 0x53 0x2D 0x00  # T4=0 (between pulses), off=0

# Pattern 2 timing (same fast timing)
i2cset -y 1 0x53 0x2E 0x02
i2cset -y 1 0x53 0x2F 0x20
i2cset -y 1 0x53 0x30 0x00

# Pattern 3 timing (same fast timing)
i2cset -y 1 0x53 0x31 0x02
i2cset -y 1 0x53 0x32 0x20
i2cset -y 1 0x53 0x33 0x00

# Color control: enable all 3 colors in each pattern, play once each
# Pattern 1: bits 7-6=00 (gamma 2.4), bit 5=1 (enable C1), bit 4=1 (enable C2), 
#            bit 3=1 (enable C3), bits 2-1=00 (C1 once), bits 0=0
i2cset -y 1 0x53 0x34 0x38  # Enable all 3 colors, play once

# Pattern 2: same config
i2cset -y 1 0x53 0x35 0x38

# Pattern 3: same config  
i2cset -y 1 0x53 0x36 0x38

# Pattern control: Pattern 1->2, Pattern 2->3, Pattern 3->stop
# Pattern repeat: 1 time through all patterns (5 seconds total)
# Bits 7-6: next action (00=stop, 01=next, 10=prev)
# Bits 5-4: multipulse repeat (00=1 time)
# Bits 3-0: pattern repeat (0000=1 time)

i2cset -y 1 0x53 0x37 0x40  # Pattern 1: go to next, 1 pulse, 1 repeat
i2cset -y 1 0x53 0x38 0x40  # Pattern 2: go to next, 1 pulse, 1 repeat
i2cset -y 1 0x53 0x39 0x00  # Pattern 3: stop, 1 pulse, 1 repeat

# Update color registers
i2cset -y 1 0x53 0x40 0xC5

# Update pattern registers
i2cset -y 1 0x53 0x41 0xC5
i2cset -y 1 0x53 0x42 0xC5
i2cset -y 1 0x53 0x43 0xC5

echo "Rainbow pattern started! (9 colors total)"
echo "Pattern sequence:"
echo "  1. Red -> Yellow -> Green"
echo "  2. Cyan -> Blue -> Magenta"
echo "  3. Red -> White -> Red"
echo ""
echo "Waiting 5 seconds..."

# Wait 5 seconds
sleep 5

echo "Rebooting now..."
reboot
