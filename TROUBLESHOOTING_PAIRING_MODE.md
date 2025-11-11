# Troubleshooting: Device in Pairing Mode (Blue Blinking LED) & Fan Not Working

## Symptoms
- Blue blinking LED (indicates pairing/setup mode)
- Fan not turning on
- Device may not be fully operational

## Quick Diagnosis Steps

### 1. Connect to Pod via SSH

```bash
# Replace <POD_IP> with your Pod's IP address
# Default port: 8822
# Default users: rewt or root
ssh -p 8822 rewt@<POD_IP>
# OR
ssh -p 8822 root@<POD_IP>
```

### 2. Check System Boot Logs

```bash
# View full boot log from current boot
sudo journalctl -b 0 --no-pager

# View system log (last 200 lines)
sudo journalctl -n 200 --no-pager

# Check for errors during boot
sudo journalctl -b 0 -p err --no-pager
```

### 3. Check Free-Sleep Service Status

```bash
# Check opensleep service
sudo systemctl status opensleep
sudo journalctl -u opensleep -n 100 --no-pager

# Check free-sleep service
sudo systemctl status free-sleep
sudo journalctl -u free-sleep -n 100 --no-pager

# Check free-sleep-stream service
sudo systemctl status free-sleep-stream
sudo journalctl -u free-sleep-stream -n 50 --no-pager
```

### 4. Check Network Configuration

```bash
# Check current WiFi connection
nmcli connection show

# Check network status
nmcli device status

# View IP address
nmcli -g ip4.address device show wlan0
```

### 5. Check if Device is in Pairing Mode

The blue blinking LED indicates the device thinks it's not connected to WiFi or not set up.

```bash
# Check NetworkManager connections
cat /persistent/system-connections/*.nmconnection

# Check for the UUID that indicates setup complete
# Should see: uuid=700a7a76-2105-4f46-b1b4-c9f3c791c440
grep uuid /persistent/system-connections/*.nmconnection
```

### 6. Check DAC Service (Controls Fan & Heating/Cooling)

```bash
# Check DAC service status
sudo systemctl status dac

# View DAC logs
sudo journalctl -u dac -n 100 --no-pager

# Check if DAC socket exists
ls -la /deviceinfo/dac.sock
# OR
ls -la /run/dac.sock

# Check what process is listening on the socket
sudo lsof | grep dac.sock
```

### 7. Check System Services Status

```bash
# List all services
sudo systemctl list-units --type=service --no-pager

# Check if Eight Sleep services are disabled (they should be)
sudo systemctl status swupdate swupdate-progress defibrillator
```

## Common Issues & Fixes

### Issue 1: Device Stuck in Pairing Mode (Blue LED)

**Cause**: WiFi not properly configured or UUID not set to indicate setup complete

**Fix**:
```bash
# Update the UUID to take device out of pairing mode
sudo sed -i 's/uuid=.*/uuid=700a7a76-2105-4f46-b1b4-c9f3c791c440/' /persistent/system-connections/*.nmconnection

# Reload network manager
sudo nmcli connection reload

# Restart NetworkManager
sudo systemctl restart NetworkManager
```

### Issue 2: Fan Not Working

**Cause**: DAC service not running or not communicating properly

**Fix**:
```bash
# Check DAC service
sudo systemctl status dac

# Restart DAC service if needed
sudo systemctl restart dac

# Check if free-sleep can communicate with DAC
sudo journalctl -u free-sleep -n 50 --no-pager | grep -i "dac\|socket\|connection"
```

### Issue 3: Services Not Starting on Boot

**Cause**: Services may be disabled or have dependency issues

**Fix**:
```bash
# Enable free-sleep services
sudo systemctl enable opensleep
sudo systemctl enable free-sleep
sudo systemctl enable free-sleep-stream

# Start services manually
sudo systemctl start opensleep
sudo systemctl start free-sleep
sudo systemctl start free-sleep-stream

# Check status
sudo systemctl status opensleep free-sleep free-sleep-stream
```

### Issue 4: Network Not Connected

**Fix**:
```bash
# Reconnect to WiFi (replace WIFI_NAME and PASSWORD)
sudo nmcli connection add type wifi con-name WIFI_NAME ifname wlan0 ssid WIFI_NAME \
  wifi-sec.key-mgmt wpa-psk wifi-sec.psk "PASSWORD" ipv4.method auto ipv6.method auto

# Take out of pairing mode
sudo sed -i 's/uuid=.*/uuid=700a7a76-2105-4f46-b1b4-c9f3c791c440/' /persistent/system-connections/*.nmconnection

# Reload
sudo nmcli connection reload
```

## Comprehensive System Check Script

Run this to get all relevant information:

```bash
#!/bin/bash
echo "=== SYSTEM STATUS ==="
date
uptime
echo ""

echo "=== NETWORK STATUS ==="
nmcli device status
nmcli -g ip4.address device show wlan0
echo ""

echo "=== SERVICE STATUS ==="
systemctl status opensleep --no-pager
systemctl status free-sleep --no-pager
systemctl status free-sleep-stream --no-pager
systemctl status dac --no-pager
echo ""

echo "=== RECENT BOOT LOGS (ERRORS) ==="
journalctl -b 0 -p err -n 50 --no-pager
echo ""

echo "=== FREE-SLEEP LOGS ==="
journalctl -u free-sleep -n 50 --no-pager
echo ""

echo "=== OPENSLEEP LOGS ==="
journalctl -u opensleep -n 50 --no-pager
echo ""

echo "=== DAC LOGS ==="
journalctl -u dac -n 50 --no-pager
echo ""

echo "=== DAC SOCKET ==="
ls -la /deviceinfo/dac.sock 2>/dev/null || ls -la /run/dac.sock 2>/dev/null || echo "DAC socket not found"
echo ""

echo "=== WIFI CONFIGURATION ==="
grep uuid /persistent/system-connections/*.nmconnection
```

## Additional Resources

- Full installation guide: `/INSTALLATION.md`
- Boot analysis: `/scripts/pod3_sd_card_scripts/BOOT_ANALYSIS.md`
- Server README: `/server/README_SERVER.md`

## Getting Help

If issues persist, gather logs and create a GitHub issue with:

```bash
# Collect diagnostic information
sudo journalctl -b 0 --no-pager > /tmp/boot_log.txt
sudo journalctl -u free-sleep --no-pager -n 500 > /tmp/free-sleep.txt
sudo journalctl -u opensleep --no-pager -n 500 > /tmp/opensleep.txt
sudo journalctl -u dac --no-pager -n 500 > /tmp/dac.txt
sudo systemctl list-units --type=service --no-pager > /tmp/services.txt

# Copy these files off the device and attach to GitHub issue
```
