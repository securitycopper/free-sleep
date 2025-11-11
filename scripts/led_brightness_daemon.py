#!/usr/bin/env python3
"""
LED Brightness Control Daemon

This daemon listens to Frank's journal logs for settings updates and controls
the IS31FL3194 LED controller brightness. It fills the gap left by disabled Capybara.

Usage: python3 led_brightness_daemon.py
"""

import os
import sys
import re
import subprocess
import time
import logging

try:
    from smbus2 import SMBus
except ImportError:
    print("ERROR: smbus2 not installed. Run: pip3 install smbus2")
    sys.exit(1)

# LED Controller Configuration
LED_I2C_ADDR = 0x53
LED_REG_CH1_BRIGHTNESS = 0x03
LED_REG_CH2_BRIGHTNESS = 0x04
LED_REG_CH3_BRIGHTNESS = 0x05
LED_REG_UPDATE = 0x07

# Logging setup
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s | %(levelname)s | %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S UTC'
)
logger = logging.getLogger("led_daemon")


def decode_cbor_brightness(hex_payload):
    """
    Extract LED brightness from CBOR hex payload.
    Looking for pattern: 626c62XX where XX is the brightness value
    Returns brightness value (0-100) or None
    """
    match = re.search(r'626c62([0-9a-fA-F]{2})', hex_payload)
    if match:
        return int(match.group(1), 16)
    return None


def set_led_brightness(bus_num, brightness_percent):
    """Set LED brightness on IS31FL3194 controller"""
    if not 0 <= brightness_percent <= 100:
        brightness_percent = max(0, min(100, brightness_percent))
    
    try:
        brightness_value = int((brightness_percent / 100.0) * 255)
        
        bus = SMBus(bus_num)
        bus.write_byte_data(LED_I2C_ADDR, LED_REG_CH1_BRIGHTNESS, brightness_value)
        bus.write_byte_data(LED_I2C_ADDR, LED_REG_CH2_BRIGHTNESS, brightness_value)
        bus.write_byte_data(LED_I2C_ADDR, LED_REG_CH3_BRIGHTNESS, brightness_value)
        bus.write_byte_data(LED_I2C_ADDR, LED_REG_UPDATE, 0x00)
        bus.close()
        
        logger.info(f"Set LED brightness to {brightness_percent}% (0x{brightness_value:02X})")
        return True
    except Exception as e:
        logger.error(f"Failed to set brightness: {e}")
        return False


def find_i2c_bus():
    """Detect which I2C bus has the LED controller"""
    for test_bus in [0, 1, 2, 3]:
        try:
            bus = SMBus(test_bus)
            device_id = bus.read_byte_data(LED_I2C_ADDR, 0x00)
            bus.close()
            if device_id == 0xCE:  # IS31FL3194 device ID
                logger.info(f"Found LED controller on I2C bus {test_bus}")
                return test_bus
        except:
            continue
    return None


def main():
    """Main daemon loop - follows Frank's journal and updates LED"""
    logger.info("LED Brightness Daemon starting...")
    
    # Detect I2C bus
    bus_num = find_i2c_bus()
    if bus_num is None:
        logger.error("LED controller not found on any I2C bus")
        sys.exit(1)
    
    # Start following Frank's journal
    logger.info("Monitoring Frank's journal for LED brightness commands...")
    
    cmd = ["journalctl", "-u", "frank.service", "-f", "-n", "0"]
    process = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1
    )
    
    last_brightness = None
    
    try:
        for line in process.stdout:
            # Look for: dac_loop command: 8 payload: <hex>
            if "dac_loop command: 8 payload:" in line:
                # Extract payload
                match = re.search(r'payload:\s*([0-9a-fA-F]+)', line)
                if match:
                    payload = match.group(1)
                    brightness = decode_cbor_brightness(payload)
                    
                    if brightness is not None and brightness != last_brightness:
                        logger.info(f"Detected brightness change: {brightness}%")
                        if set_led_brightness(bus_num, brightness):
                            last_brightness = brightness
                        
    except KeyboardInterrupt:
        logger.info("Shutting down...")
    finally:
        process.terminate()
        process.wait()


if __name__ == "__main__":
    main()
