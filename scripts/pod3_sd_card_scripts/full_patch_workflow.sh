#!/usr/bin/env bash
set -euo pipefail

echo "======================================"
echo "Pod 3 (SD Card) Image Patching Script"
echo "FreeSleep Edition"
echo "======================================"
echo ""
echo "⚠️  IMPORTANT: This script is for Pod 3 with SD card only!"
echo "   - Does NOT work with Pod 1, 2, 4, or 5"
echo "   - Does NOT work with Pod 3 without SD card (eMMC version)"
echo ""
echo "Note: This script requires sudo privileges for:"
echo "  - Mounting disk images (losetup, mount)"
echo "  - Extracting and modifying system files"
echo "  - Setting proper file ownership and permissions"
echo ""

# Default values
IMG_FILE=""
PUBKEY_FILE=""
SSID=""
PSK=""
PASSWORD=""
DISABLE_SERVICES=false
REMOVE_EIGHTSLEEP_KEYS=false
FREESLEEP_INSTALL=false
FREESLEEP_REPO_USER="throwaway31265"
FREESLEEP_BRANCH="main"
FREESLEEP_BIOMETRICS=false
FREESLEEP_TIMEZONE=""
OUTPUT_FILE=""
WORK_DIR_CUSTOM=""
VALIDATION_SCRIPT=""
MAC_ADDRESS=""
TIME_SERVER=""
STATIC_IP=""
STATIC_GATEWAY=""
STATIC_DNS=""

# Valid timezone list (must match server/src/db/timeZones.ts)
VALID_TIMEZONES=(
    "UTC"
    "America/Anchorage"
    "America/Los_Angeles"
    "Pacific/Honolulu"
    "America/Denver"
    "America/Chicago"
    "America/New_York"
    "America/Sao_Paulo"
    "Atlantic/Reykjavik"
    "Europe/London"
    "Europe/Berlin"
    "Europe/Moscow"
    "Africa/Lagos"
    "Africa/Johannesburg"
    "Asia/Dubai"
    "Asia/Kolkata"
    "Asia/Shanghai"
    "Asia/Tokyo"
    "Australia/Sydney"
    "Australia/Brisbane"
    "Pacific/Auckland"
)

# Parse command-line arguments
usage() {
    cat <<EOF
Usage: $0 -i IMAGE_FILE -k PUBKEY_FILE [-o OUTPUT_FILE] [-w WORK_DIR] [-s SSID] [-p PSK] [-P PASSWORD] [-m MAC_ADDRESS] [-t TIME_SERVER] [-I STATIC_IP] [-G GATEWAY] [-D DNS] [-R] [-d] [-f] [-U USER] [-F BRANCH] [-B] [-v VALIDATION_SCRIPT]

⚠️  Pod 3 (SD Card Version) ONLY
   This script is designed for Eight Sleep Pod 3 with removable SD card.
   It does NOT work with Pod 1, 2, 4, 5, or Pod 3 eMMC (non-SD) versions.

Required arguments:
  -i IMAGE_FILE    Path to the SD card image file
  -k PUBKEY_FILE   Path to the SSH public key file

Optional arguments:
  -o OUTPUT_FILE   Path for the patched output image (default: <original>-patched.img)
  -w WORK_DIR      Custom working directory (must be empty, needs 16GB free space)
  -s SSID          WiFi network SSID
  -p PSK           WiFi network password/passphrase
  -P PASSWORD      Password for the rewt user
  -m MAC_ADDRESS   Set persistent MAC address for wlan0 (format: AA:BB:CC:DD:EE:FF)
                   Prevents MAC from changing on factory reset
  -I STATIC_IP     Configure static IP address (format: 192.168.1.100/24)
                   If not provided, DHCP will be used
  -G GATEWAY       Gateway IP address (required if using static IP)
                   Example: 192.168.1.1
  -D DNS           DNS server IP addresses (comma-separated)
                   Example: "8.8.8.8,8.8.4.4" or "192.168.1.1"
                   Required if using static IP
  -T TIMEZONE      Configure timezone for FreeSleep schedules (requires -f)
                   Valid values: UTC, America/New_York, America/Chicago, America/Denver,
                   America/Los_Angeles, America/Anchorage, Pacific/Honolulu, America/Sao_Paulo,
                   Atlantic/Reykjavik, Europe/London, Europe/Berlin, Europe/Moscow,
                   Africa/Lagos, Africa/Johannesburg, Asia/Dubai, Asia/Kolkata,
                   Asia/Shanghai, Asia/Tokyo, Australia/Sydney, Australia/Brisbane,
                   Pacific/Auckland
                   Example: -T "America/New_York"
                   Note: If not set, timezone defaults to UTC. You can change it later in web UI.
  -t TIME_SERVER   Configure NTP time server (e.g., pool.ntp.org, time.google.com)
                   Configures systemd-timesyncd for automatic time synchronization
  -R               [DISABLED] Remove Eight Sleep SSH keys (currently causes SSH connection failure)
                   This feature is being debugged and will be re-enabled in a future update.
  -d               Disable Eight Sleep services on first boot
                   For safety, it waits for a wifi connection before disabling, this ensures the pairing and reset options are not interfered with.
                   WARNING: This prevents normal Eight Sleep app pairing.
                   To restore Eight Sleep functionality, you must reflash the original image.
  -f               Enable FreeSleep auto-install on first boot
                   FreeSleep will be installed automatically after network connection
                   Installation script: https://raw.githubusercontent.com/throwaway31265/free-sleep/main/scripts/install.sh
  -U USER          Specify GitHub user/org for FreeSleep fork (default: throwaway31265)
                   Useful for testing development forks
                   Example: -U myusername -F my-feature-branch
  -F BRANCH        Specify FreeSleep branch to install (default: main)
                   Examples: main, dev, pod3sd_script
  -B               Enable biometrics after FreeSleep installation
                   Runs: /home/dac/free-sleep/scripts/enable_biometrics.sh
  -v VALIDATION    Path to validation script to include in image (default: auto-detect in same directory)
  -h               Show this help message

Example:
  # Basic FreeSleep installation with WiFi
  $0 -i sdcard.img -k ~/.ssh/id_rsa.pub -s "MyWiFi" -p "password123" -f -d
  
  # FreeSleep with specific branch and biometrics
  $0 -i sdcard.img -k ~/.ssh/id_rsa.pub -s "MyWiFi" -p "pass" -f -F dev -B -d
  
  # FreeSleep from a development fork
  $0 -i sdcard.img -k ~/.ssh/id_rsa.pub -s "MyWiFi" -p "pass" -f -U myusername -F my-feature -d
  
  # FreeSleep with persistent MAC address and time server
  $0 -i sdcard.img -k ~/.ssh/id_rsa.pub -s "MyWiFi" -p "pass" -f -m "02:11:22:33:44:55" -t "pool.ntp.org" -d
  
  # FreeSleep with static IP address
  $0 -i sdcard.img -k ~/.ssh/id_rsa.pub -s "MyWiFi" -p "pass" -f -I "192.168.2.52/24" -G "192.168.2.1" -D "192.168.2.1,8.8.8.8" -d
  
  # FreeSleep with timezone for correct schedule times
  $0 -i sdcard.img -k ~/.ssh/id_rsa.pub -s "MyWiFi" -p "pass" -f -T "America/New_York" -d
  
  # Just SSH access, manual FreeSleep install later
  $0 -i sdcard.img -k ~/.ssh/id_rsa.pub -s "MyWiFi" -p "pass"
EOF
    exit 1
}

while getopts "i:k:o:w:s:p:P:I:G:D:T:f:U:F:B:b:S:c:v:m:t:dRh" opt; do
    case $opt in
        i) IMG_FILE="$OPTARG" ;;
        k) PUBKEY_FILE="$OPTARG" ;;
        o) OUTPUT_FILE="$OPTARG" ;;
        w) WORK_DIR_CUSTOM="$OPTARG" ;;
        s) SSID="$OPTARG" ;;
        p) PSK="$OPTARG" ;;
        P) PASSWORD="$OPTARG" ;;
        I) STATIC_IP="$OPTARG" ;;
        G) STATIC_GATEWAY="$OPTARG" ;;
        D) STATIC_DNS="$OPTARG" ;;
        T) FREESLEEP_TIMEZONE="$OPTARG" ;;
        f) FREESLEEP_INSTALL=true ;;
        U) FREESLEEP_REPO_USER="$OPTARG" ;;
        F) FREESLEEP_BRANCH="$OPTARG" ;;
        B) FREESLEEP_BIOMETRICS=true ;;
        b) echo "WARNING: -b flag is deprecated. Use -f to enable FreeSleep auto-install."
           echo "The OpenSleep binary installation method is no longer supported."
           ;;
        S) echo "WARNING: -S flag is deprecated. Use -f to enable FreeSleep auto-install."
           ;;
        c) echo "WARNING: -c flag is deprecated. Use -f to enable FreeSleep auto-install."
           ;;
        v) VALIDATION_SCRIPT="$OPTARG" ;;
        m) MAC_ADDRESS="$OPTARG" ;;
        t) TIME_SERVER="$OPTARG" ;;
        R) echo "ERROR: -R flag is temporarily disabled due to SSH connection issues"
           echo "This feature is being debugged and will be re-enabled in a future update"
           exit 1 ;;
        d) DISABLE_SERVICES=true ;;
        h) usage ;;
        *) usage ;;
    esac
done

# Validate required arguments
if [[ -z "$IMG_FILE" ]] || [[ -z "$PUBKEY_FILE" ]]; then
    echo ""
    echo "Error: Missing required arguments"
    echo ""
    usage
fi

echo "[*] Validating input files..."

# Validate files exist
if [[ ! -f "$IMG_FILE" ]]; then
    echo "Error: Image file not found: $IMG_FILE"
    exit 1
fi
echo "  ✓ Image file found: $IMG_FILE"

if [[ ! -f "$PUBKEY_FILE" ]]; then
    echo "Error: Public key file not found: $PUBKEY_FILE"
    exit 1
fi
echo "  ✓ Public key file found: $PUBKEY_FILE"

# Validate FreeSleep flags
if [[ "$FREESLEEP_BIOMETRICS" == true ]] && [[ "$FREESLEEP_INSTALL" == false ]]; then
    echo "Error: -B (biometrics) requires -f (FreeSleep installation)"
    exit 1
fi

# Validate timezone if provided
if [[ -n "$FREESLEEP_TIMEZONE" ]]; then
    if [[ "$FREESLEEP_INSTALL" == false ]]; then
        echo "Error: -T (timezone) requires -f (FreeSleep installation)"
        exit 1
    fi
    
    # Check if timezone is in valid list
    TIMEZONE_VALID=false
    for tz in "${VALID_TIMEZONES[@]}"; do
        if [[ "$FREESLEEP_TIMEZONE" == "$tz" ]]; then
            TIMEZONE_VALID=true
            break
        fi
    done
    
    if [[ "$TIMEZONE_VALID" == false ]]; then
        echo "Error: Invalid timezone: $FREESLEEP_TIMEZONE"
        echo ""
        echo "Valid timezones are:"
        for tz in "${VALID_TIMEZONES[@]}"; do
            echo "  - $tz"
        done
        exit 1
    fi
    
    echo "  ✓ Timezone validated: $FREESLEEP_TIMEZONE"
fi

# Auto-detect validation script if not specified
if [[ -z "$VALIDATION_SCRIPT" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    AUTO_VALIDATION="$SCRIPT_DIR/full_patch_workflow_post_ssh_validation.sh"
    if [[ -f "$AUTO_VALIDATION" ]]; then
        VALIDATION_SCRIPT="$AUTO_VALIDATION"
        echo "  ✓ Auto-detected validation script: $VALIDATION_SCRIPT"
    fi
elif [[ ! -f "$VALIDATION_SCRIPT" ]]; then
    echo "Error: Validation script not found: $VALIDATION_SCRIPT"
    exit 1
else
    echo "  ✓ Validation script found: $VALIDATION_SCRIPT"
fi

# Validate MAC address format if provided
if [[ ! -z "$MAC_ADDRESS" ]]; then
    if [[ ! "$MAC_ADDRESS" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
        echo "Error: Invalid MAC address format: $MAC_ADDRESS"
        echo "Expected format: AA:BB:CC:DD:EE:FF (e.g., 02:11:22:33:44:55)"
        exit 1
    fi
    echo "  ✓ MAC address validated: $MAC_ADDRESS"
fi

echo ""

# Generate default output filename if not provided
if [[ -z "$OUTPUT_FILE" ]]; then
    # Get the absolute path of the input image
    IMG_ABSOLUTE=$(realpath "$IMG_FILE")
    IMG_DIR=$(dirname "$IMG_ABSOLUTE")
    IMG_NAME=$(basename "$IMG_ABSOLUTE")
    
    # Remove extension and add -patched
    IMG_BASE="${IMG_NAME%.*}"
    IMG_EXT="${IMG_NAME##*.}"
    
    # Create output path in same directory as input
    OUTPUT_FILE="${IMG_DIR}/${IMG_BASE}-patched.${IMG_EXT}"
fi

echo "  ✓ Output will be: $OUTPUT_FILE"

# Check if output file already exists
if [[ -f "$OUTPUT_FILE" ]]; then
    echo "Error: Output file already exists: $OUTPUT_FILE"
    echo "Please remove it or specify a different output path with -o"
    exit 1
fi

echo ""
echo "[*] Creating working directory..."

# Handle custom or temporary working directory
if [[ ! -z "$WORK_DIR_CUSTOM" ]]; then
    # Validate custom working directory
    if [[ ! -d "$WORK_DIR_CUSTOM" ]]; then
        echo "Error: Custom working directory does not exist: $WORK_DIR_CUSTOM"
        exit 1
    fi
    
    # Check if directory is empty
    if [[ -n "$(ls -A "$WORK_DIR_CUSTOM" 2>/dev/null)" ]]; then
        echo "Error: Custom working directory is not empty: $WORK_DIR_CUSTOM"
        echo "Please provide an empty directory"
        exit 1
    fi
    
    WORK_DIR="$WORK_DIR_CUSTOM"
    echo "  ✓ Using custom working directory: $WORK_DIR"
else
    WORK_DIR=$(mktemp -d -t work_$(basename "$IMG_FILE").XXXX)
    echo "  ✓ Created temporary working directory: $WORK_DIR"
fi

# Check available space (need at least 16GB)
REQUIRED_SPACE_GB=16
REQUIRED_SPACE_KB=$((REQUIRED_SPACE_GB * 1024 * 1024))
AVAILABLE_SPACE_KB=$(df -k "$WORK_DIR" | tail -1 | awk '{print $4}')
AVAILABLE_SPACE_GB=$((AVAILABLE_SPACE_KB / 1024 / 1024))

echo "[*] Checking available disk space..."
echo "  Available: ${AVAILABLE_SPACE_GB}GB"
echo "  Required:  ${REQUIRED_SPACE_GB}GB"

if [[ $AVAILABLE_SPACE_KB -lt $REQUIRED_SPACE_KB ]]; then
    echo "Error: Insufficient disk space in working directory"
    echo "  Location: $WORK_DIR"
    echo "  Available: ${AVAILABLE_SPACE_GB}GB"
    echo "  Required: ${REQUIRED_SPACE_GB}GB"
    echo "Please free up space or use -w to specify a different working directory"
    exit 1
fi

echo "  ✓ Sufficient space available"

WORKING_IMG="$WORK_DIR/working_image.img"
EXTRACT_DIR="$WORK_DIR/rootfs_extract"
MOUNT_DIR="$WORK_DIR/mount"

echo "[*] Original image: $IMG_FILE"
echo "[*] Output will be saved to: $OUTPUT_FILE"

# --- Copy the original image ---
echo "[*] Copying original image to working directory..."
cp "$IMG_FILE" "$WORKING_IMG"
echo "[+] Image copied successfully"

# --- Cleanup function ---
cleanup() {
    local exit_code=$?
    echo "[*] Cleaning up..."
    
    # Unmount if mounted
    if mountpoint -q "$MOUNT_DIR" 2>/dev/null; then
        echo "[*] Unmounting $MOUNT_DIR..."
        sudo umount "$MOUNT_DIR" 2>/dev/null || true
    fi
    
    # Detach loop device if attached
    if [[ ! -z "$LOOP" ]] && losetup "$LOOP" 2>/dev/null; then
        echo "[*] Detaching loop device $LOOP..."
        sudo losetup -d "$LOOP" 2>/dev/null || true
    fi
    
    # Remove working directory
    if [[ -d "$WORK_DIR" ]]; then
        echo "[*] Removing work directory..."
        rm -rf "$WORK_DIR" 2>/dev/null || true
    fi
    
    if [[ $exit_code -ne 0 ]]; then
        echo "[-] Script failed with exit code $exit_code"
    fi
    
    exit $exit_code
}

# Set trap to call cleanup on exit, interrupt, or termination
trap cleanup EXIT INT TERM

# --- Check if extraction directory already exists with contents ---
if [[ -d "$EXTRACT_DIR" ]] && [[ -n "$(ls -A "$EXTRACT_DIR" 2>/dev/null)" ]]; then
    echo "[-] Error: Extraction directory already exists with contents: $EXTRACT_DIR"
    echo "[-] This may indicate a previous run was interrupted or there's a conflict."
    echo "[-] Please remove the directory manually if you're sure it's safe to do so:"
    echo "[-]   rm -rf \"$EXTRACT_DIR\""
    exit 1
fi

# --- Setup loop device ---
LOOP=$(sudo losetup -Pf --show "$WORKING_IMG")
echo "[*] Loop device: $LOOP"

# --- Mount root partition ---
ROOT_PART="${LOOP}p1"
mkdir -p "$MOUNT_DIR"
sudo mount "$ROOT_PART" "$MOUNT_DIR"
echo "[*] Mounted root partition at $ROOT_PART"

# --- Extract rootfs.tar.gz ---
ROOTFS_TAR_GZ=$(sudo find "$MOUNT_DIR" -name "rootfs.tar.gz" 2>/dev/null | head -n1)
if [[ -z "$ROOTFS_TAR_GZ" ]]; then
    echo "[-] rootfs.tar.gz not found!"
    exit 1
fi

# Ungzip the rootfs.tar.gz
echo "[*] Extracting $ROOTFS_TAR_GZ..."
ROOTFS_TAR="$WORK_DIR/rootfs.tar"
sudo gunzip -c "$ROOTFS_TAR_GZ" > "$ROOTFS_TAR"

# Extract only what we need to modify
mkdir -p "$EXTRACT_DIR"
sudo tar -xf "$ROOTFS_TAR" -C "$EXTRACT_DIR" ./etc/ssh/authorized_keys ./home/rewt ./etc/shadow 2>/dev/null || true

# --- Detect rewt UID/GID ---
REWT_HOME="$EXTRACT_DIR/home/rewt"
if [[ -d "$REWT_HOME" ]]; then
    REWT_UID=$(sudo stat -c "%u" "$REWT_HOME")
    REWT_GID=$(sudo stat -c "%g" "$REWT_HOME")
    echo "[+] rewt detected, UID=$REWT_UID GID=$REWT_GID"
else
    # Default to common embedded Linux UID/GID
    REWT_UID=1001
    REWT_GID=1001
    echo "[+] Using default UID=$REWT_UID GID=$REWT_GID"
fi

# Create a staging directory for files to append
STAGING_DIR="$WORK_DIR/staging"
mkdir -p "$STAGING_DIR"

# --- Append new public key ---
echo "[*] Preparing SSH authorized_keys..."
AK_FILE="$STAGING_DIR/etc/ssh/authorized_keys"
sudo mkdir -p "$(dirname "$AK_FILE")"

# Copy existing keys if they exist, otherwise create new
if sudo tar -xf "$ROOTFS_TAR" -C "$STAGING_DIR" ./etc/ssh/authorized_keys 2>/dev/null; then
    echo "  ✓ Existing authorized_keys found"
else
    sudo mkdir -p "$STAGING_DIR/etc/ssh"
    sudo touch "$AK_FILE"
fi

# Remove Eight Sleep keys if requested
if [[ "$REMOVE_EIGHTSLEEP_KEYS" == true ]]; then
    echo "[*] Removing Eight Sleep SSH keys..."
    echo "[!] WARNING: This will prevent Eight Sleep mobile app pairing!"
    echo "[!] Eight Sleep remote access will be disabled"
    
    # Create new authorized_keys with only the user's key
    # Copy the user's public key
    sudo cp "$PUBKEY_FILE" "$AK_FILE"
    
    # Ensure file ends with newline (SSH keys should end with newline)
    sudo bash -c "echo '' >> '$AK_FILE'"
    
    echo "  ✓ Eight Sleep keys removed, only your key remains"
else
    # Append new public key to existing keys
    sudo bash -c "cat '$PUBKEY_FILE' >> '$AK_FILE'"
    echo "  ✓ Your key appended to existing keys"
fi

sudo chmod 600 "$AK_FILE"
sudo chown "$REWT_UID:$REWT_GID" "$AK_FILE"

# --- Set password if provided ---
if [[ ! -z "$PASSWORD" ]]; then
    echo "[*] Setting password for rewt..."
    echo "[!] WARNING: Password modification is experimental and may cause SSH issues"
    echo "[!] If SSH stops working, re-patch without -P flag"
    
    # Extract shadow and sshd_config files
    if ! sudo tar -xf "$ROOTFS_TAR" -C "$STAGING_DIR" ./etc/shadow ./etc/ssh/sshd_config 2>/dev/null; then
        echo "[-] WARNING: Failed to extract /etc/shadow or /etc/ssh/sshd_config from tar"
        echo "[-] Skipping password modification to avoid breaking SSH"
        echo "[-] You can still use SSH key authentication"
    else
        SHADOW_FILE="$STAGING_DIR/etc/shadow"
        SSHD_CONFIG="$STAGING_DIR/etc/ssh/sshd_config"
        
        PASSWORD_SET=false
        
        if [[ -f "$SHADOW_FILE" ]]; then
            # Get original permissions and ownership before modification
            SHADOW_PERMS=$(sudo stat -c "%a" "$SHADOW_FILE")
            SHADOW_OWNER=$(sudo stat -c "%u:%g" "$SHADOW_FILE")
            
            echo "  [*] Original shadow file: perms=$SHADOW_PERMS owner=$SHADOW_OWNER"
            
            # Validate file has content (check if rewt entry exists)
            if ! sudo grep -q "^rewt:" "$SHADOW_FILE" 2>/dev/null; then
                echo "[-] WARNING: /etc/shadow doesn't contain rewt entry, skipping password modification"
                echo "[-] File may be empty or corrupted"
            else
                HASH=$(openssl passwd -6 "$PASSWORD")
                sudo sed -i "s|^rewt:[^:]*:|rewt:$HASH:|" "$SHADOW_FILE"
                
                # Restore original permissions and ownership
                sudo chmod "$SHADOW_PERMS" "$SHADOW_FILE"
                sudo chown "$SHADOW_OWNER" "$SHADOW_FILE"
                
                # Also write to mounted partition for immediate use
                sudo mkdir -p "$MOUNT_DIR/etc"
                sudo cp "$SHADOW_FILE" "$MOUNT_DIR/etc/shadow"
                sudo chmod "$SHADOW_PERMS" "$MOUNT_DIR/etc/shadow"
                sudo chown "$SHADOW_OWNER" "$MOUNT_DIR/etc/shadow"
                
                PASSWORD_SET=true
                echo "  ✓ Password set, permissions preserved"
            fi
        else
            echo "[-] WARNING: /etc/shadow not found, skipping password modification"
        fi
        
        if [[ -f "$SSHD_CONFIG" ]] && [[ "$PASSWORD_SET" = true ]]; then
            # Get original permissions and ownership before modification
            SSHD_PERMS=$(sudo stat -c "%a" "$SSHD_CONFIG")
            SSHD_OWNER=$(sudo stat -c "%u:%g" "$SSHD_CONFIG")
            
            echo "  [*] Original sshd_config: perms=$SSHD_PERMS owner=$SSHD_OWNER"
            
            # Enable password authentication (handle both commented and uncommented lines)
            sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' "$SSHD_CONFIG"
            
            # Restore original permissions and ownership
            sudo chmod "$SSHD_PERMS" "$SSHD_CONFIG"
            sudo chown "$SSHD_OWNER" "$SSHD_CONFIG"
            
            # Also write to mounted partition for immediate use
            sudo mkdir -p "$MOUNT_DIR/etc/ssh"
            sudo cp "$SSHD_CONFIG" "$MOUNT_DIR/etc/ssh/sshd_config"
            sudo chmod "$SSHD_PERMS" "$MOUNT_DIR/etc/ssh/sshd_config"
            sudo chown "$SSHD_OWNER" "$MOUNT_DIR/etc/ssh/sshd_config"
            
            echo "  ✓ Password authentication enabled, permissions preserved"
        elif [[ "$PASSWORD_SET" = false ]]; then
            echo "[-] Skipping sshd_config modification (password not set)"
        else
            echo "[-] WARNING: /etc/ssh/sshd_config not found, skipping modification"
        fi
        
        if [[ "$PASSWORD_SET" = false ]]; then
            echo ""
            echo "[!] Password was NOT set due to errors"
            echo "[!] SSH key authentication will still work"
        fi
    fi
fi

# --- Configure passwordless sudo for rewt user ---
echo "[*] Configuring passwordless sudo for rewt user..."

SUDOERS_DIR="$STAGING_DIR/etc/sudoers.d"
sudo mkdir -p "$SUDOERS_DIR"

REWT_SUDOERS="$SUDOERS_DIR/rewt-nopasswd"
sudo bash -c "cat > '$REWT_SUDOERS'" <<'EOF'
# Allow rewt user to run any command without password
# This enables validation and troubleshooting scripts to work seamlessly
rewt ALL=(ALL) NOPASSWD: ALL
EOF
sudo chmod 0440 "$REWT_SUDOERS"

echo "  ✓ Passwordless sudo enabled for rewt user"
echo "  ✓ Validation scripts can now run without password prompts"

# --- Create wpa_supplicant WiFi configuration ---
if [[ ! -z "$SSID" && ! -z "$PSK" ]]; then
    echo "[*] Creating wpa_supplicant WiFi configuration..."
    
    # Create wpa_supplicant configuration directory
    WPA_DIR="$STAGING_DIR/etc/wpa_supplicant"
    sudo mkdir -p "$WPA_DIR"
    
    # Create wpa_supplicant configuration for wlan0
    WPA_CONF="$WPA_DIR/wpa_supplicant-wlan0.conf"
    sudo bash -c "cat > '$WPA_CONF'" <<EOF
ctrl_interface=/var/run/wpa_supplicant
ctrl_interface_group=0
update_config=1

network={
    ssid="$SSID"
    psk="$PSK"
    key_mgmt=WPA-PSK
    priority=100
}
EOF
    sudo chmod 600 "$WPA_CONF"
    sudo chown "$REWT_UID:$REWT_GID" "$WPA_CONF"
    
    # Create systemd-networkd configuration for wlan0
    NETWORKD_DIR="$STAGING_DIR/etc/systemd/network"
    sudo mkdir -p "$NETWORKD_DIR"
    
    NETWORKD_CONF="$NETWORKD_DIR/25-wlan0.network"
    
    # Check if static IP configuration is requested
    if [[ ! -z "$STATIC_IP" ]]; then
        echo "[*] Configuring static IP address: $STATIC_IP"
        
        # Validate that gateway and DNS are provided for static IP
        if [[ -z "$STATIC_GATEWAY" ]] || [[ -z "$STATIC_DNS" ]]; then
            echo "ERROR: Static IP requires both gateway (-G) and DNS (-D) to be specified"
            cleanup
            exit 1
        fi
        
        # Convert comma-separated DNS to space-separated
        DNS_SERVERS=$(echo "$STATIC_DNS" | tr ',' ' ')
        
        sudo bash -c "cat > '$NETWORKD_CONF'" <<EOF
[Match]
Name=wlan0

[Network]
Address=$STATIC_IP
Gateway=$STATIC_GATEWAY
DNS=$DNS_SERVERS
DNSSEC=no

[Route]
Metric=100
EOF
        
        # Remove any existing /etc/resolv.conf symlink and create static file
        # Note: Factory Pod 3 images have resolv.conf as a symlink to NetworkManager
        # which won't work since we're using systemd-networkd instead
        RESOLV_CONF="$STAGING_DIR/etc/resolv.conf"
        sudo rm -f "$RESOLV_CONF"
        sudo bash -c "cat > '$RESOLV_CONF'" <<EOF
# Static DNS configuration for FreeSleep
# Created by full_patch_workflow.sh
$(for dns in ${DNS_SERVERS}; do echo "nameserver $dns"; done)
EOF
        sudo chmod 644 "$RESOLV_CONF"
        
        echo "    ✓ Static IP: $STATIC_IP"
        echo "    ✓ Gateway: $STATIC_GATEWAY"
        echo "    ✓ DNS: $STATIC_DNS"
    else
        echo "[*] Configuring DHCP for dynamic IP address"
        
        sudo bash -c "cat > '$NETWORKD_CONF'" <<EOF
[Match]
Name=wlan0

[Network]
DHCP=yes
DNSSEC=no

[DHCP]
RouteMetric=100
UseDNS=yes
EOF
        
        # Fix /etc/resolv.conf symlink for DHCP mode
        # Factory images have resolv.conf pointing to NetworkManager, but we use systemd-networkd
        # Point it to systemd-resolved's dynamic resolv.conf instead
        RESOLV_CONF="$STAGING_DIR/etc/resolv.conf"
        sudo rm -f "$RESOLV_CONF"
        sudo ln -s /run/systemd/resolve/resolv.conf "$RESOLV_CONF"
        
        echo "    ✓ DHCP enabled with DNS from DHCP server"
        echo "    ✓ /etc/resolv.conf symlinked to systemd-resolved"
    fi
    
    sudo chmod 644 "$NETWORKD_CONF"
    sudo chown "$REWT_UID:$REWT_GID" "$NETWORKD_CONF"
    
    # Note: Not copying to MOUNT_DIR - rootfs.tar.gz extraction during factory reset will install it
    # sudo mkdir -p "$MOUNT_DIR/etc/wpa_supplicant"
    # sudo mkdir -p "$MOUNT_DIR/etc/systemd/network"
    # sudo cp "$WPA_CONF" "$MOUNT_DIR/etc/wpa_supplicant/"
    # sudo cp "$NETWORKD_CONF" "$MOUNT_DIR/etc/systemd/network/"
    
    # Disable NetworkManager MAC randomization for wlan0
    NM_CONF_DIR="$STAGING_DIR/etc/NetworkManager/conf.d"
    sudo mkdir -p "$NM_CONF_DIR"
    NM_CONF="$NM_CONF_DIR/99-disable-wifi-mac-randomization.conf"
    sudo bash -c "cat > '$NM_CONF'" <<EOF
[device-mac-randomization]
# Disable MAC randomization for WiFi
wifi.scan-rand-mac-address=no

[connection-mac-randomization]
# Use permanent MAC address
ethernet.cloned-mac-address=permanent
wifi.cloned-mac-address=permanent
EOF
    sudo chmod 644 "$NM_CONF"
    sudo chown 0:0 "$NM_CONF"
    
    # Also write to mounted partition
    sudo mkdir -p "$MOUNT_DIR/etc/NetworkManager/conf.d"
    sudo cp "$NM_CONF" "$MOUNT_DIR/etc/NetworkManager/conf.d/"
    
    echo "[+] Created WiFi configuration for SSID: $SSID"
    echo "    ✓ NetworkManager MAC randomization disabled"
fi

# --- Configure NTP time server ---
if [[ ! -z "$TIME_SERVER" ]]; then
    echo "[*] Configuring NTP time server..."
    
    TIMESYNCD_CONF="$STAGING_DIR/etc/systemd/timesyncd.conf"
    sudo mkdir -p "$(dirname "$TIMESYNCD_CONF")"
    
    sudo bash -c "cat > '$TIMESYNCD_CONF'" <<EOF
[Time]
NTP=$TIME_SERVER
FallbackNTP=pool.ntp.org time.google.com
RootDistanceMaxSec=5
PollIntervalMinSec=32
PollIntervalMaxSec=2048
EOF
    
    sudo chmod 644 "$TIMESYNCD_CONF"
    sudo chown 0:0 "$TIMESYNCD_CONF"
    
    # Note: Not copying to MOUNT_DIR - rootfs.tar.gz extraction during factory reset will install it
    # sudo mkdir -p "$MOUNT_DIR/etc/systemd"
    # sudo cp "$TIMESYNCD_CONF" "$MOUNT_DIR/etc/systemd/"
    
    echo "[+] NTP time server configured: $TIME_SERVER"
    echo "    ✓ systemd-timesyncd will use this server for time synchronization"
fi

# --- DNS Configuration ---
# Relying on DHCP to configure DNS via systemd-networkd or NetworkManager
# The first-boot reboot gives the network stack time to properly configure DNS
# If DHCP doesn't provide DNS, the DNS check in freesleep-installer will timeout
echo "[*] DNS will be configured via DHCP"
echo "    ✓ First-boot reboot ensures DNS is properly initialized"
echo "    ✓ FreeSleep installer checks DNS before proceeding"

# --- WiFi initialization service (must be created before MAC service can reference it) ---
if [[ ! -z "$SSID" ]]; then
    
    # --- Create free-sleep-wifi service to initialize WiFi hardware ---
    echo "[*] Creating free-sleep-wifi service..."
    
    # Check if variscite-wifi script exists on the mounted image
    if sudo test -f "$MOUNT_DIR/etc/wifi/variscite-wifi"; then
        # Create wifi directory in staging
        sudo mkdir -p "$STAGING_DIR/etc/wifi"
        
        # Copy variscite-wifi script as free-sleep-wifi
        sudo cp "$MOUNT_DIR/etc/wifi/variscite-wifi" "$STAGING_DIR/etc/wifi/free-sleep-wifi"
        
        # Bypass EEPROM check - modify wifi_is_available() function to always return 0
        # This is necessary because Pod 3's EEPROM reports WiFi as unavailable even though hardware is present
        sudo sed -i '/^wifi_is_available()/,/^}/{
            /opt=.*i2cget/,/fi$/c\
    # FreeSleep: Bypass EEPROM check - WiFi hardware is physically present\
    # Eight Sleep EEPROM has WiFi bit unset but hardware exists\
    return 0
        }' "$STAGING_DIR/etc/wifi/free-sleep-wifi"
        
        # Ensure script is executable
        sudo chmod +x "$STAGING_DIR/etc/wifi/free-sleep-wifi"
        
        # Create free-sleep-wifi.service
        sudo mkdir -p "$STAGING_DIR/etc/systemd/system"
        FREESLEEP_WIFI_SERVICE="$STAGING_DIR/etc/systemd/system/free-sleep-wifi.service"
        sudo bash -c "cat > '$FREESLEEP_WIFI_SERVICE'" <<'EOF'
[Unit]
Description=FreeSleep WiFi Initialization Service
Before=network.target
After=sysinit.target
ConditionPathExists=/etc/wifi/free-sleep-wifi

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/etc/wifi/free-sleep-wifi start
ExecStop=/etc/wifi/free-sleep-wifi stop

[Install]
WantedBy=network.target
EOF
        sudo chmod 644 "$FREESLEEP_WIFI_SERVICE"
        
        # Enable free-sleep-wifi.service (create symlink in network.target.wants)
        sudo mkdir -p "$STAGING_DIR/etc/systemd/system/network.target.wants"
        sudo ln -sf /etc/systemd/system/free-sleep-wifi.service "$STAGING_DIR/etc/systemd/system/network.target.wants/free-sleep-wifi.service"
        
        # Mask variscite-wifi.service to prevent conflicts
        sudo ln -sf /dev/null "$STAGING_DIR/etc/systemd/system/variscite-wifi.service"
        
        # Note: Not copying to MOUNT_DIR - rootfs.tar.gz extraction during factory reset will install it
        # sudo mkdir -p "$MOUNT_DIR/etc/wifi"
        # sudo cp "$STAGING_DIR/etc/wifi/free-sleep-wifi" "$MOUNT_DIR/etc/wifi/"
        # sudo cp "$FREESLEEP_WIFI_SERVICE" "$MOUNT_DIR/etc/systemd/system/"
        # sudo mkdir -p "$MOUNT_DIR/etc/systemd/system/network.target.wants"
        # sudo ln -sf /etc/systemd/system/free-sleep-wifi.service "$MOUNT_DIR/etc/systemd/system/network.target.wants/free-sleep-wifi.service"
        # sudo ln -sf /dev/null "$MOUNT_DIR/etc/systemd/system/variscite-wifi.service"
        
        echo "[+] free-sleep-wifi service created and enabled"
        echo "    ✓ WiFi hardware will be initialized on boot"
        echo "    ✓ variscite-wifi.service masked (EEPROM check bypassed)"
    else
        echo "[!] WARNING: /etc/wifi/variscite-wifi not found in image"
        echo "    WiFi may not work without manual hardware initialization"
    fi
    
    # --- Configure persistent MAC address (requires free-sleep-wifi service) ---
    if [[ ! -z "$MAC_ADDRESS" ]]; then
        echo "[*] Configuring persistent MAC address..."
        
        # brcmfmac WiFi driver generates random MAC at firmware load time
        # .link files don't work reliably, so we use a service to set MAC after interface is up
        
        SYSTEMD_DIR="$STAGING_DIR/etc/systemd/system"
        sudo mkdir -p "$SYSTEMD_DIR"
        
        # Create a service to set MAC address before networking starts
        MAC_SERVICE="$SYSTEMD_DIR/free-sleep-mac.service"
        sudo bash -c "cat > '$MAC_SERVICE'" <<EOF
[Unit]
Description=FreeSleep Persistent MAC Address
Before=network-pre.target wpa_supplicant@wlan0.service
Wants=network-pre.target
After=free-sleep-wifi.service sys-subsystem-net-devices-wlan0.device
BindsTo=sys-subsystem-net-devices-wlan0.device

[Service]
Type=oneshot
ExecStart=/sbin/ip link set dev wlan0 down
ExecStart=/sbin/ip link set dev wlan0 address $MAC_ADDRESS
ExecStart=/sbin/ip link set dev wlan0 up
RemainAfterExit=yes

[Install]
WantedBy=network.target
EOF
        sudo chmod 644 "$MAC_SERVICE"
        sudo chown 0:0 "$MAC_SERVICE"
        
        # Enable the service
        sudo mkdir -p "$SYSTEMD_DIR/network.target.wants"
        sudo ln -sf ../free-sleep-mac.service "$SYSTEMD_DIR/network.target.wants/free-sleep-mac.service"
        
        # Note: Not copying to MOUNT_DIR - rootfs.tar.gz extraction during factory reset will install it
        # sudo mkdir -p "$MOUNT_DIR/etc/systemd/system/network.target.wants"
        # sudo cp "$MAC_SERVICE" "$MOUNT_DIR/etc/systemd/system/"
        # sudo ln -sf ../free-sleep-mac.service "$MOUNT_DIR/etc/systemd/system/network.target.wants/free-sleep-mac.service"
        
        echo "[+] MAC address set to: $MAC_ADDRESS"
        echo "    MAC will persist across reboots and factory resets"
    fi
fi

# --- Enable SSH + Network Early Service ---
echo "[*] Installing ssh-early.service..."

SSH_EARLY_SERVICE="$STAGING_DIR/etc/systemd/system/ssh-early.service"
sudo mkdir -p "$(dirname "$SSH_EARLY_SERVICE")"

if [[ ! -z "$SSID" ]]; then
    # If WiFi is configured, wait for network and start SSH
    sudo bash -c "cat > '$SSH_EARLY_SERVICE'" <<EOF
[Unit]
Description=Force-enable SSH early in boot
After=network.target free-sleep-wifi.service wpa_supplicant.service
Before=capybara.service variscite-bt.service
Wants=network-online.target
Requires=free-sleep-wifi.service

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 5
ExecStart=/bin/systemctl start sshd.socket
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
else
    # No WiFi configured, just start SSH
    sudo bash -c "cat > '$SSH_EARLY_SERVICE'" <<EOF
[Unit]
Description=Force-enable SSH early in boot
After=network-pre.target
Before=capybara.service variscite-bt.service

[Service]
Type=oneshot
ExecStart=/bin/systemctl start sshd.socket
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
fi

sudo chmod 644 "$SSH_EARLY_SERVICE"

# Create systemd symlink
SYSTEMD_WANTS="$STAGING_DIR/etc/systemd/system/multi-user.target.wants"
sudo mkdir -p "$SYSTEMD_WANTS"
sudo ln -sf ../ssh-early.service "$SYSTEMD_WANTS/ssh-early.service"

# Note: Not copying to MOUNT_DIR - rootfs.tar.gz extraction during factory reset will install it
# sudo mkdir -p "$MOUNT_DIR/etc/systemd/system/multi-user.target.wants"
# sudo cp "$SSH_EARLY_SERVICE" "$MOUNT_DIR/etc/systemd/system/"
# sudo ln -sf ../ssh-early.service "$MOUNT_DIR/etc/systemd/system/multi-user.target.wants/ssh-early.service"

echo "[+] SSH early service installed and enabled."

# --- Enable wpa_supplicant for wlan0 interface ---
if [[ ! -z "$SSID" ]]; then
    echo "[*] Enabling wpa_supplicant@wlan0.service..."
    
    # Create wpa_supplicant service override to wait for free-sleep-wifi
    WPA_OVERRIDE_DIR="$STAGING_DIR/etc/systemd/system/wpa_supplicant@wlan0.service.d"
    sudo mkdir -p "$WPA_OVERRIDE_DIR"
    
    # Add MAC service dependency only if MAC address was configured
    if [[ ! -z "$MAC_ADDRESS" ]]; then
        sudo bash -c "cat > '$WPA_OVERRIDE_DIR/override.conf'" <<'EOF'
[Unit]
After=free-sleep-wifi.service free-sleep-mac.service
Requires=free-sleep-wifi.service free-sleep-mac.service
EOF
        echo "    ✓ wpa_supplicant will wait for free-sleep-wifi and free-sleep-mac"
    else
        sudo bash -c "cat > '$WPA_OVERRIDE_DIR/override.conf'" <<'EOF'
[Unit]
After=free-sleep-wifi.service
Requires=free-sleep-wifi.service
EOF
        echo "    ✓ wpa_supplicant will wait for free-sleep-wifi"
    fi
    
    sudo chmod 644 "$WPA_OVERRIDE_DIR/override.conf"
    
    # Enable wpa_supplicant@wlan0.service
    sudo ln -sf /lib/systemd/system/wpa_supplicant@.service "$SYSTEMD_WANTS/wpa_supplicant@wlan0.service"
    
    # Note: Not copying to MOUNT_DIR - rootfs.tar.gz extraction during factory reset will install it
    # sudo mkdir -p "$MOUNT_DIR/etc/systemd/system/wpa_supplicant@wlan0.service.d"
    # sudo cp "$WPA_OVERRIDE_DIR/override.conf" "$MOUNT_DIR/etc/systemd/system/wpa_supplicant@wlan0.service.d/"
    # sudo ln -sf /lib/systemd/system/wpa_supplicant@.service "$MOUNT_DIR/etc/systemd/system/multi-user.target.wants/wpa_supplicant@wlan0.service"
    
    echo "[+] wpa_supplicant@wlan0.service enabled with free-sleep-wifi dependency"
fi

# --- Create service to disable Eight Sleep services ---
# Auto-enable if FreeSleep is being installed
if [[ "$DISABLE_SERVICES" = true ]] || [[ "$FREESLEEP_INSTALL" = true ]]; then
    echo ""
    echo "⚠️  WARNING: Disabling Eight Sleep services ⚠️"
    echo "This will prevent the Eight Sleep app from pairing with the Pod."
    
    # Warn if FreeSleep is being installed without WiFi configuration
    if [[ -z "$SSID" ]]; then
        echo ""
        echo "⚠️⚠️⚠️  CRITICAL WARNING  ⚠️⚠️⚠️"
        echo "Installing FreeSleep without WiFi credentials!"
        echo "  - Pod 3 has no Ethernet port"
        echo "  - Without WiFi, the device will have NO network connectivity"
        echo "  - The device will be UNREACHABLE without serial console access"
        echo ""
        echo "Recommendation: Provide WiFi credentials with -s and -p flags"
        echo ""
        read -p "Continue anyway? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            echo "Aborting..."
            cleanup
            exit 1
        fi
    fi
    
    echo "This will prevent the Eight Sleep app from pairing with the Pod."
    echo "To restore normal Eight Sleep functionality, you must reflash the original image."
    echo ""
    
    echo "[*] Installing disable-eightsleep-services.service..."

    DISABLE_SERVICE="$STAGING_DIR/etc/systemd/system/disable-eightsleep-services.service"
    sudo mkdir -p "$(dirname "$DISABLE_SERVICE")"
    
    # CRITICAL: Disable Eight Sleep services IMMEDIATELY after first reboot
    # Must run before swupdate/defibrillator detect changes and trigger unwanted reboots
    # Running in basic.target (early boot) before network services start
    sudo bash -c "cat > '$DISABLE_SERVICE'" <<EOF
[Unit]
Description=Disable Eight Sleep services immediately after first boot
# Run very early, right after filesystem and firstboot
After=sysinit.target local-fs.target firstboot-reboot.service
# Must run BEFORE Eight Sleep services can start
Before=network.target network-online.target
Before=swupdate.service swupdate-progress.service defibrillator.service capybara.service dac.service
DefaultDependencies=no
# Only run after first reboot (firstboot-complete exists) but not if already done
ConditionPathExists=/var/lib/firstboot-complete.flag
ConditionPathExists=!/var/lib/eightsleep-disabled.flag

[Service]
Type=oneshot
# Log start
ExecStartPre=/bin/sh -c 'echo "Disabling Eight Sleep services at \$(date)" >> /var/log/eightsleep-disabled.log'
# Disable Eight Sleep services before FreeSleep installation
# Service list matches INSTALLATION.md manual instructions
# Use script to handle non-existent services gracefully (some services may not exist on all firmware versions)
ExecStart=/bin/sh -c 'for svc in swupdate-progress swupdate defibrillator eight-kernel telegraf vector frankenfirmware dac capybara swupdate.socket; do systemctl disable --now \$svc 2>&1 | tee -a /var/log/eightsleep-disabled.log || true; done'
ExecStart=/bin/sh -c 'for svc in swupdate-progress swupdate defibrillator eight-kernel telegraf vector frankenfirmware dac capybara swupdate.socket; do systemctl mask \$svc 2>&1 | tee -a /var/log/eightsleep-disabled.log || true; done'
# Log completion
ExecStartPost=/bin/sh -c 'echo "Eight Sleep services disabled successfully at \$(date)" >> /var/log/eightsleep-disabled.log'
ExecStartPost=/bin/touch /var/lib/eightsleep-disabled.flag
RemainAfterExit=yes
StandardOutput=journal+console
StandardError=journal+console

[Install]
WantedBy=basic.target
EOF

    sudo chmod 644 "$DISABLE_SERVICE"
    # Enable in basic.target for early execution (before network and Eight Sleep services)
    BASIC_TARGET_WANTS="$STAGING_DIR/etc/systemd/system/basic.target.wants"
    sudo mkdir -p "$BASIC_TARGET_WANTS"
    sudo ln -sf ../disable-eightsleep-services.service "$BASIC_TARGET_WANTS/disable-eightsleep-services.service"

    echo "[+] Service to disable Eight Sleep services installed (runs IMMEDIATELY after first boot)."
    echo "    ✓ Will run in basic.target before network and Eight Sleep services"
fi

# --- Install first-boot reboot service (runs before FreeSleep installer) ---
if [[ "$FREESLEEP_INSTALL" = true ]]; then
    echo "[*] Installing first-boot automatic reboot..."
    
    FIRST_BOOT_SERVICE="$STAGING_DIR/etc/systemd/system/firstboot-reboot.service"
    sudo mkdir -p "$(dirname "$FIRST_BOOT_SERVICE")"
    
    sudo bash -c "cat > '$FIRST_BOOT_SERVICE'" <<'EOF'
[Unit]
Description=First Boot Automatic Reboot (Apply Factory Reset Changes)
# Run as early as possible after basic system services
After=sysinit.target local-fs.target
# Must run before network services start
Before=network-pre.target network.target network-online.target ssh-early.service free-sleep-wifi.service
Before=freesleep-installer.service disable-eightsleep-services.service
DefaultDependencies=no
ConditionPathExists=!/var/lib/firstboot-complete.flag

[Service]
Type=oneshot
# Create flag immediately to prevent running again
ExecStart=/bin/touch /var/lib/firstboot-complete.flag
# Log the reboot
ExecStartPost=/bin/sh -c 'echo "Factory reset detected - triggering automatic reboot at $(date)" >> /var/log/firstboot.log'
# Wait briefly to ensure flag is written to disk
ExecStartPost=/bin/sleep 2
# Trigger immediate reboot to apply factory reset changes
ExecStartPost=/sbin/reboot
RemainAfterExit=no
StandardOutput=journal+console
StandardError=journal+console

[Install]
WantedBy=sysinit.target
EOF

    sudo chmod 644 "$FIRST_BOOT_SERVICE"
    # Enable in sysinit.target for earliest possible execution
    SYSINIT_WANTS="$STAGING_DIR/etc/systemd/system/sysinit.target.wants"
    sudo mkdir -p "$SYSINIT_WANTS"
    sudo ln -sf ../firstboot-reboot.service "$SYSINIT_WANTS/firstboot-reboot.service"
    
    # Note: Not copying to MOUNT_DIR - rootfs.tar.gz extraction during factory reset will install it
    # sudo cp "$FIRST_BOOT_SERVICE" "$MOUNT_DIR/etc/systemd/system/"
    # sudo mkdir -p "$MOUNT_DIR/etc/systemd/system/sysinit.target.wants"
    # sudo ln -sf ../firstboot-reboot.service "$MOUNT_DIR/etc/systemd/system/sysinit.target.wants/firstboot-reboot.service"
    
    echo "[+] First-boot automatic reboot installed"
    echo "    ✓ Will automatically reboot after factory reset"
    echo "    ✓ Applies filesystem changes before FreeSleep installation"
fi

# --- Install FreeSleep auto-installer ---
if [[ "$FREESLEEP_INSTALL" = true ]]; then
    echo "[*] Installing FreeSleep auto-installer..."
    
    if [[ -z "$SSID" ]]; then
        echo ""
        echo "⚠️⚠️⚠️  CRITICAL WARNING  ⚠️⚠️⚠️"
        echo "FreeSleep installation requires network connectivity!"
        echo "  - Installation script downloads from GitHub"
        echo "  - Pod 3 has no Ethernet port"
        echo "  - Without WiFi, installation will fail"
        echo ""
        echo "Recommendation: Provide WiFi credentials with -s and -p flags"
        echo ""
        read -p "Continue anyway? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            echo "Aborting..."
            cleanup
            exit 1
        fi
    fi
    
    echo "  Using branch: $FREESLEEP_BRANCH"
    echo "  Using repository: https://github.com/$FREESLEEP_REPO_USER/free-sleep"
    if [[ "$FREESLEEP_BIOMETRICS" = true ]]; then
        echo "  Biometrics will be enabled after installation"
    fi
    
    # Create FreeSleep installer service
    FREESLEEP_INSTALLER_SERVICE="$STAGING_DIR/etc/systemd/system/freesleep-installer.service"
    sudo mkdir -p "$(dirname "$FREESLEEP_INSTALLER_SERVICE")"
    
    sudo bash -c "cat > '$FREESLEEP_INSTALLER_SERVICE'" <<'EOF'
[Unit]
Description=FreeSleep Auto-Installer (Second Boot)
After=network-online.target ssh-early.service firstboot-reboot.service
Wants=network-online.target
ConditionPathExists=/var/lib/firstboot-complete.flag
ConditionPathExists=!/var/lib/freesleep-installed.flag

[Service]
Type=oneshot
# Wait for DNS to be working (test with nslookup, max 120 seconds)
ExecStartPre=/bin/sh -c 'for i in $(seq 1 120); do nslookup raw.githubusercontent.com >/dev/null 2>&1 && break || sleep 1; done'
# Additional wait to ensure DNS is stable
ExecStartPre=/bin/sleep 5
# Install FreeSleep from GitHub
ExecStart=/bin/bash -c "curl -fsSL https://raw.githubusercontent.com/USER_PLACEHOLDER/free-sleep/BRANCH_PLACEHOLDER/scripts/install.sh | /bin/bash"
# Mark installation complete
ExecStartPost=/bin/touch /var/lib/freesleep-installed.flag
# Enable biometrics if requested
BIOMETRICS_PLACEHOLDER
# Log completion
ExecStartPost=/bin/sh -c 'echo "FreeSleep installation completed at $(date)" >> /var/log/freesleep-install.log'
# Reboot to apply all changes cleanly (MAC address, services, etc.)
ExecStartPost=/bin/sh -c 'echo "Rebooting to apply configuration changes..." && sleep 3 && /sbin/reboot'
RemainAfterExit=yes
StandardOutput=journal+console
StandardError=journal+console

[Install]
WantedBy=network-online.target
EOF

    # Replace user and branch placeholders
    sudo sed -i "s|USER_PLACEHOLDER|$FREESLEEP_REPO_USER|g" "$FREESLEEP_INSTALLER_SERVICE"
    sudo sed -i "s|BRANCH_PLACEHOLDER|$FREESLEEP_BRANCH|g" "$FREESLEEP_INSTALLER_SERVICE"
    
    # Add biometrics enable command if requested
    if [[ "$FREESLEEP_BIOMETRICS" = true ]]; then
        BIOMETRICS_CMD="ExecStartPost=/bin/sh -c 'sleep 10 && /bin/bash /home/dac/free-sleep/scripts/enable_biometrics.sh || true'"
        sudo sed -i "s|BIOMETRICS_PLACEHOLDER|$BIOMETRICS_CMD|g" "$FREESLEEP_INSTALLER_SERVICE"
    else
        sudo sed -i "/BIOMETRICS_PLACEHOLDER/d" "$FREESLEEP_INSTALLER_SERVICE"
    fi
    
    sudo chmod 644 "$FREESLEEP_INSTALLER_SERVICE"
    
    # Enable the service in network-online.target (not multi-user.target which is never reached)
    NETWORK_ONLINE_WANTS="$STAGING_DIR/etc/systemd/system/network-online.target.wants"
    sudo mkdir -p "$NETWORK_ONLINE_WANTS"
    sudo ln -sf ../freesleep-installer.service "$NETWORK_ONLINE_WANTS/freesleep-installer.service"
    
    # Note: Not copying to MOUNT_DIR - rootfs.tar.gz extraction during factory reset will install it
    # sudo cp "$FREESLEEP_INSTALLER_SERVICE" "$MOUNT_DIR/etc/systemd/system/"
    # sudo mkdir -p "$MOUNT_DIR/etc/systemd/system/network-online.target.wants"
    # sudo ln -sf ../freesleep-installer.service "$MOUNT_DIR/etc/systemd/system/network-online.target.wants/freesleep-installer.service"
    
    echo "[+] FreeSleep auto-installer configured"
    echo "    ✓ Will install after network is online (network-online.target)"
    echo "    ✓ Branch: $FREESLEEP_BRANCH"
    if [[ "$FREESLEEP_BIOMETRICS" = true ]]; then
        echo "    ✓ Biometrics will be enabled after installation"
    fi
    
    # Create timezone setter service if timezone was specified
    if [[ -n "$FREESLEEP_TIMEZONE" ]]; then
        echo "[*] Configuring timezone auto-setter: $FREESLEEP_TIMEZONE"
        
        TIMEZONE_SETTER_SERVICE="$STAGING_DIR/etc/systemd/system/freesleep-timezone-setter.service"
        sudo mkdir -p "$(dirname "$TIMEZONE_SETTER_SERVICE")"
        
        sudo bash -c "cat > '$TIMEZONE_SETTER_SERVICE'" <<'EOF'
[Unit]
Description=FreeSleep Timezone Auto-Setter (Third Boot)
After=free-sleep.service
Requires=free-sleep.service
ConditionPathExists=!/var/lib/freesleep-timezone-set.flag

[Service]
Type=oneshot
# Wait for FreeSleep API to be ready (max 120 seconds)
ExecStartPre=/bin/sh -c 'for i in $(seq 1 120); do curl -sf http://localhost:3000/api/health >/dev/null 2>&1 && break || sleep 1; done'
# Set timezone via API
ExecStart=/bin/sh -c '\
  echo "Waiting for FreeSleep API to be ready..."; \
  for i in $(seq 1 30); do \
    if curl -s -f http://localhost:3000/api/settings >/dev/null 2>&1; then \
      echo "FreeSleep API is ready, setting timezone..."; \
      TZ_JSON='"'"'{"timeZone":"TIMEZONE_PLACEHOLDER"}'"'"'; \
      if curl -X POST http://localhost:3000/api/settings -H "Content-Type: application/json" -d "$TZ_JSON"; then \
        echo "Timezone successfully set to TIMEZONE_PLACEHOLDER"; \
        exit 0; \
      else \
        echo "Failed to set timezone via API"; \
        exit 1; \
      fi; \
    fi; \
    echo "Waiting for API (attempt $i/30)..."; \
    sleep 2; \
  done; \
  echo "Timeout waiting for FreeSleep API"; \
  exit 1'
# Mark as complete only on success
ExecStartPost=/bin/touch /var/lib/freesleep-timezone-set.flag
# Log completion
ExecStartPost=/bin/sh -c 'echo "Timezone set to TIMEZONE_PLACEHOLDER at $(date)" >> /var/log/freesleep-timezone.log'
RemainAfterExit=yes
StandardOutput=journal+console
StandardError=journal+console

[Install]
WantedBy=multi-user.target
EOF

        # Replace timezone placeholder
        sudo sed -i "s|TIMEZONE_PLACEHOLDER|$FREESLEEP_TIMEZONE|g" "$TIMEZONE_SETTER_SERVICE"
        sudo chmod 644 "$TIMEZONE_SETTER_SERVICE"
        
        # Enable the service
        MULTI_USER_WANTS="$STAGING_DIR/etc/systemd/system/multi-user.target.wants"
        sudo mkdir -p "$MULTI_USER_WANTS"
        sudo ln -sf ../freesleep-timezone-setter.service "$MULTI_USER_WANTS/freesleep-timezone-setter.service"
        
        echo "    ✓ Timezone setter service created"
        echo "    ✓ Will set timezone after FreeSleep starts (third boot)"
        echo "    ✓ Timezone: $FREESLEEP_TIMEZONE"
    fi
    
    # --- Install subsystem initialization services (Pod 3 hardware support) ---
    echo "[*] Installing Pod 3 subsystem initialization services..."
    
    # Create /usr/local/bin directory
    sudo mkdir -p "$STAGING_DIR/usr/local/bin"
    
    # 1. Create populate_deviceinfo.sh script
    POPULATE_DEVICEINFO_SCRIPT="$STAGING_DIR/usr/local/bin/populate_deviceinfo.sh"
    sudo bash -c "cat > '$POPULATE_DEVICEINFO_SCRIPT'" <<'POPSCRIPT'
#!/usr/bin/env bash
# Populate /deviceinfo/ directory on boot (tmpfs - cleared on reboot)
# This replaces Capybara's deviceinfo population function

set -euo pipefail

DEVICEINFO_DIR="/deviceinfo"
mkdir -p "$DEVICEINFO_DIR"

# Get MAC address (used to generate device-id)
MAC=$(cat /sys/class/net/wlan0/address 2>/dev/null || echo "00:00:00:00:00:00")

# Generate device-id from MAC address SHA1 hash (matches Capybara behavior)
DEVICE_ID=$(echo -n "$MAC" | sha1sum | awk '{print $1}')

# Create device files
echo "$DEVICE_ID" > "$DEVICEINFO_DIR/device-id"
echo "free-sleep-pod" > "$DEVICEINFO_DIR/device-label"
echo "imx8mm-var" > "$DEVICEINFO_DIR/variscite-id"
echo "$MAC" > "$DEVICEINFO_DIR/wifi-macaddress"

# Create minimal dummy certificates (not used by FreeSleep)
DUMMY_CERT="-----BEGIN CERTIFICATE-----
MIIBkTCB+wIJAKHHCgVZU2T6MA0GCSqGSIb3DQEBCwUAMA0xCzAJBgNVBAYTAlVT
MB4XDTE1MDEwMTAwMDAwMFoXDTI1MDEwMTAwMDAwMFowDTELMAkGA1UEBhMCVVMw
XDANBgkqhkiG9w0BAQEFAANLADBIAkEAn2N7DF8L9MQhGBQ8e8LqMVV0UzE5X5qW
-----END CERTIFICATE-----"

echo "$DUMMY_CERT" > "$DEVICEINFO_DIR/device.crt"
echo "$DUMMY_CERT" > "$DEVICEINFO_DIR/factory.crt"
echo "$DUMMY_CERT" > "$DEVICEINFO_DIR/core.crt"
echo "$DUMMY_CERT" > "$DEVICEINFO_DIR/root.crt"
echo "$DUMMY_CERT" > "$DEVICEINFO_DIR/device.key"
chmod 600 "$DEVICEINFO_DIR/device.key"

# Set ownership
chown -R root:root "$DEVICEINFO_DIR"
chmod 644 "$DEVICEINFO_DIR"/*.crt "$DEVICEINFO_DIR"/device-* "$DEVICEINFO_DIR"/variscite-* "$DEVICEINFO_DIR"/wifi-*

echo "✓ DeviceInfo populated (device-id: $DEVICE_ID)"
POPSCRIPT
    sudo chmod +x "$POPULATE_DEVICEINFO_SCRIPT"
    
    # 2. Create enable_subsystems.sh script
    ENABLE_SUBSYSTEMS_SCRIPT="$STAGING_DIR/usr/local/bin/enable_subsystems.sh"
    sudo bash -c "cat > '$ENABLE_SUBSYSTEMS_SCRIPT'" <<'ENASCRIPT'
#!/usr/bin/env bash
# Initialize PCAL6416A GPIO expander to enable Pod subsystems
# This replaces Capybara's hardware initialization function

set -euo pipefail

echo "Enabling Pod subsystems via PCAL6416A GPIO expander..."

# Detect which I2C bus has the GPIO expander at 0x20
# Different Pod 3 devices may have the expander on different buses
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

# Initialize IS31FL3194 LED controller at address 0x53
echo "Initializing LED controller..."
LED_ADDR=0x53

# Check if LED controller exists on the same bus
if i2cdetect -y $I2C_BUS 2>/dev/null | grep -q " 53 "; then
    echo "Found LED controller on I2C bus $I2C_BUS"
    
    # Reset and configure IS31FL3194
    # Register 0x00: Shutdown register (0x01 = normal operation)
    i2cset -y $I2C_BUS $LED_ADDR 0x00 0x01
    
    # Register 0x01: Configuration register
    # Bit 0: Color mode (0=GRB, 1=RGB) - use 0 for GRB
    # Bit 1-2: Current setting (00=max current)
    i2cset -y $I2C_BUS $LED_ADDR 0x01 0x00
    
    # Register 0x03: Output 1 (Red/Green channel) - Start at default brightness
    i2cset -y $I2C_BUS $LED_ADDR 0x03 0x64
    
    # Register 0x04: Output 2 (Green/Red channel) - Start at default brightness  
    i2cset -y $I2C_BUS $LED_ADDR 0x04 0x64
    
    # Register 0x05: Output 3 (Blue channel) - Start at default brightness
    i2cset -y $I2C_BUS $LED_ADDR 0x05 0x64
    
    # Register 0x07: Color update register - Apply changes
    i2cset -y $I2C_BUS $LED_ADDR 0x07 0x00
    
    echo "✓ LED controller initialized on I2C bus $I2C_BUS"
else
    echo "⚠ LED controller not found at 0x53 on bus $I2C_BUS (continuing anyway)"
fi

echo "✓ Subsystems enabled successfully on I2C bus $I2C_BUS"
ENASCRIPT
    sudo chmod +x "$ENABLE_SUBSYSTEMS_SCRIPT"
    
    # 3. Create populate-deviceinfo.service
    POPULATE_DEVICEINFO_SERVICE="$STAGING_DIR/etc/systemd/system/populate-deviceinfo.service"
    sudo mkdir -p "$(dirname "$POPULATE_DEVICEINFO_SERVICE")"
    sudo bash -c "cat > '$POPULATE_DEVICEINFO_SERVICE'" <<'EOF'
[Unit]
Description=Populate Device Info Directory for FreeSleep
Documentation=https://github.com/throwaway31265/free-sleep
# CRITICAL: Must run AFTER deviceinfo.mount to avoid race condition
# Without this, deviceinfo.mount may remount tmpfs AFTER we populate it, clearing all files
After=deviceinfo.mount
Requires=deviceinfo.mount
Before=frank.service free-sleep.service enable-subsystems.service
DefaultDependencies=no

[Service]
Type=oneshot
ExecStart=/usr/local/bin/populate_deviceinfo.sh
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=sysinit.target
EOF
    sudo chmod 644 "$POPULATE_DEVICEINFO_SERVICE"
    
    # Enable populate-deviceinfo.service
    SYSINIT_WANTS="$STAGING_DIR/etc/systemd/system/sysinit.target.wants"
    sudo mkdir -p "$SYSINIT_WANTS"
    sudo ln -sf ../populate-deviceinfo.service "$SYSINIT_WANTS/populate-deviceinfo.service"
    
    # 4. Create enable-subsystems.service
    ENABLE_SUBSYSTEMS_SERVICE="$STAGING_DIR/etc/systemd/system/enable-subsystems.service"
    sudo bash -c "cat > '$ENABLE_SUBSYSTEMS_SERVICE'" <<'EOF'
[Unit]
Description=Enable Pod Subsystems (PCAL6416A GPIO Expander)
Documentation=https://www.nxp.com/docs/en/data-sheet/PCAL6416A.pdf
Documentation=https://github.com/throwaway31265/free-sleep
Before=frank.service free-sleep.service
After=populate-deviceinfo.service
Requires=populate-deviceinfo.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/enable_subsystems.sh
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    sudo chmod 644 "$ENABLE_SUBSYSTEMS_SERVICE"
    
    # Enable enable-subsystems.service
    MULTI_USER_WANTS="$STAGING_DIR/etc/systemd/system/multi-user.target.wants"
    sudo mkdir -p "$MULTI_USER_WANTS"
    sudo ln -sf ../enable-subsystems.service "$MULTI_USER_WANTS/enable-subsystems.service"
    
    # 5. Modify frank.service to remove Capybara dependency
    # Note: We create a drop-in override instead of modifying the original file
    FRANK_OVERRIDE_DIR="$STAGING_DIR/lib/systemd/system/frank.service.d"
    sudo mkdir -p "$FRANK_OVERRIDE_DIR"
    FRANK_OVERRIDE="$FRANK_OVERRIDE_DIR/freesleep-subsystems.conf"
    sudo bash -c "cat > '$FRANK_OVERRIDE'" <<'EOF'
[Unit]
# FreeSleep: Remove Capybara dependency (replaced by subsystem services)
# Requires= is a list-type directive that cannot be cleared by drop-ins
# This override adds new dependencies to work with FreeSleep
After=enable-subsystems.service populate-deviceinfo.service

[Install]
# Ensure frank service starts after subsystems are initialized
WantedBy=multi-user.target
EOF
    sudo chmod 644 "$FRANK_OVERRIDE"
    
    # 6. Create post-install service to modify free-sleep.service after installation
    # This service will add dependency on enable-subsystems to free-sleep after it's installed
    FREESLEEP_FIXER_SERVICE="$STAGING_DIR/etc/systemd/system/freesleep-service-fixer.service"
    sudo bash -c "cat > '$FREESLEEP_FIXER_SERVICE'" <<'EOF'
[Unit]
Description=FreeSleep Service Dependency Fixer
After=freesleep-installer.service
ConditionPathExists=/var/lib/freesleep-installed.flag
ConditionPathExists=!/var/lib/freesleep-service-fixed.flag

[Service]
Type=oneshot
ExecStart=/bin/sh -c '\
  if [ -f /etc/systemd/system/free-sleep.service ]; then \
    echo "Adding subsystem dependency to free-sleep.service..."; \
    if ! grep -q "After=.*enable-subsystems.service" /etc/systemd/system/free-sleep.service; then \
      sed -i "/^After=/s/$/ enable-subsystems.service/" /etc/systemd/system/free-sleep.service; \
      systemctl daemon-reload; \
      echo "✓ free-sleep.service updated with subsystem dependency"; \
    else \
      echo "✓ free-sleep.service already has subsystem dependency"; \
    fi; \
  else \
    echo "⚠ free-sleep.service not found, will retry on next boot"; \
    exit 1; \
  fi'
ExecStartPost=/bin/touch /var/lib/freesleep-service-fixed.flag
RemainAfterExit=yes
StandardOutput=journal+console
StandardError=journal+console

[Install]
WantedBy=multi-user.target
EOF
    sudo chmod 644 "$FREESLEEP_FIXER_SERVICE"
    
    # Enable freesleep-service-fixer.service
    sudo ln -sf ../freesleep-service-fixer.service "$MULTI_USER_WANTS/freesleep-service-fixer.service"
    
    # Note: Capybara service is masked by disable-eightsleep-services.service (runs after first boot)
    # No need to mask it here in factory tar since it will be masked early in boot sequence
    
    echo "[+] Pod 3 subsystem initialization services installed"
    echo "    ✓ populate-deviceinfo.service: Creates /deviceinfo/ files on boot"
    echo "    ✓ enable-subsystems.service: Initializes PCAL6416A GPIO expander"
    echo "    ✓ frank.service: Modified to work without Capybara"
    echo "    ✓ freesleep-service-fixer.service: Adds dependency to free-sleep after install"
    echo "    ✓ capybara.service: Masked by disable-eightsleep-services (runs after first boot)"
    echo "    ✓ Boot order: populate-deviceinfo → enable-subsystems → frank → free-sleep"
fi

# --- Add validation script ---
if [[ ! -z "$VALIDATION_SCRIPT" ]]; then
    echo "[*] Adding validation script to image..."
    
    # Create home directory structure
    sudo mkdir -p "$STAGING_DIR/home/rewt"
    
    # Copy validation script to user's home directory
    sudo cp "$VALIDATION_SCRIPT" "$STAGING_DIR/home/rewt/validate_deployment.sh"
    sudo chmod +x "$STAGING_DIR/home/rewt/validate_deployment.sh"
    sudo chown "$REWT_UID:$REWT_GID" "$STAGING_DIR/home/rewt/validate_deployment.sh"
    
    # Also copy to mounted partition for immediate use
    sudo mkdir -p "$MOUNT_DIR/home/rewt"
    sudo cp "$VALIDATION_SCRIPT" "$MOUNT_DIR/home/rewt/validate_deployment.sh"
    sudo chmod +x "$MOUNT_DIR/home/rewt/validate_deployment.sh"
    
    # Create .bashrc with welcome message
    sudo tee "$STAGING_DIR/home/rewt/.bashrc" > /dev/null <<'BASHRC_EOF'
# FreeSleep Pod 3 - Patched System

# Show validation prompt on first interactive login
if [ -f ~/validate_deployment.sh ] && [ -z "$VALIDATION_SHOWN" ]; then
    export VALIDATION_SHOWN=1
    echo ""
    echo "=========================================="
    echo "  FreeSleep Pod 3 - Welcome!"
    echo "=========================================="
    echo ""
    echo "A validation script is available to verify"
    echo "your system configuration."
    echo ""
    echo "Run: ~/validate_deployment.sh"
    echo "Or:  ./validate_deployment.sh"
    echo ""
    echo "To check FreeSleep status:"
    echo "  systemctl status free-sleep"
    echo "  journalctl -u free-sleep -f"
    echo ""
    echo "To check FreeSleep logs:"
    echo "  tail -f /persistent/free-sleep-data/logs/server.log"
    echo ""
    echo "To enable/disable biometrics:"
    echo "  sh /home/dac/free-sleep/scripts/enable_biometrics.sh"
    echo "  sh /home/dac/free-sleep/scripts/disable_biometrics.sh"
    echo ""
    echo "To skip this message in future sessions:"
    echo "  export VALIDATION_SHOWN=1"
    echo ""
fi
BASHRC_EOF
    
    sudo chmod 644 "$STAGING_DIR/home/rewt/.bashrc"
    sudo chown "$REWT_UID:$REWT_GID" "$STAGING_DIR/home/rewt/.bashrc"
    
    # Copy .bashrc to mounted partition
    sudo cp "$STAGING_DIR/home/rewt/.bashrc" "$MOUNT_DIR/home/rewt/.bashrc"
    
    echo "  ✓ Validation script added to /home/rewt/validate_deployment.sh"
    echo "  ✓ Welcome banner configured (shows script location on first login)"
fi

# --- Append modified files to rootfs.tar ---
echo "[*] Appending modified files to rootfs.tar..."

# List of files that might already exist in the tar and need to be replaced
# (tar --delete doesn't work on compressed archives, so we work with uncompressed tar)
FILES_TO_REPLACE=(
    "./etc/ssh/authorized_keys"
    "./etc/resolv.conf"
)

# Only delete shadow and sshd_config if we actually modified them (password was provided)
if [[ ! -z "$PASSWORD" ]]; then
    FILES_TO_REPLACE+=("./etc/shadow")
    FILES_TO_REPLACE+=("./etc/ssh/sshd_config")
fi

# Delete old versions of files that we're replacing (if they exist)
for file in "${FILES_TO_REPLACE[@]}"; do
    if sudo tar -tf "$ROOTFS_TAR" "$file" >/dev/null 2>&1; then
        echo "[*] Removing old $file from tar before updating..."
        sudo tar --delete -f "$ROOTFS_TAR" "$file" 2>/dev/null || true
    fi
done

# Use --numeric-owner to preserve UID/GID
sudo tar --numeric-owner -rf "$ROOTFS_TAR" -C "$STAGING_DIR" .

# --- Recompress rootfs.tar.gz ---
echo "[*] Recompressing rootfs.tar.gz..."
ROOTFS_PATCHED="$WORK_DIR/rootfs-patched.tar.gz"
sudo gzip -c "$ROOTFS_TAR" > "$ROOTFS_PATCHED"

# --- Update rootfs.tar.gz in mounted image ---
echo "[*] Updating rootfs.tar.gz in image..."
sudo cp "$ROOTFS_PATCHED" "$ROOTFS_TAR_GZ"

# --- Verify files ---
echo ""
echo "[*] Verifying patched files..."
if sudo test -f "$STAGING_DIR/etc/ssh/authorized_keys"; then
    echo "  ✓ SSH authorized_keys file created"
else
    echo "  ✗ Warning: Could not verify authorized_keys"
fi

if [[ ! -z "$PASSWORD" ]] && sudo test -f "$STAGING_DIR/etc/ssh/sshd_config"; then
    echo "  ✓ SSH configuration updated"
fi

if [[ ! -z "$SSID" ]] && sudo test -f "$STAGING_DIR/etc/wpa_supplicant/wpa_supplicant-wlan0.conf"; then
    echo "  ✓ WiFi connection configured: $SSID"
    if sudo test -f "$STAGING_DIR/etc/wifi/opensleep-wifi"; then
        echo "  ✓ opensleep-wifi service created (WiFi hardware initialization)"
    fi
fi

if [[ ! -z "$MAC_ADDRESS" ]]; then
    if sudo test -f "$STAGING_DIR/etc/systemd/system/opensleep-mac.service"; then
        echo "  ✓ Persistent MAC address configured: $MAC_ADDRESS"
    fi
fi

if [[ ! -z "$TIME_SERVER" ]]; then
    if sudo test -f "$STAGING_DIR/etc/systemd/timesyncd.conf"; then
        echo "  ✓ NTP time server configured: $TIME_SERVER"
    fi
fi

if [[ "$FREESLEEP_INSTALL" = true ]]; then
    if sudo test -f "$STAGING_DIR/etc/systemd/system/freesleep-installer.service"; then
        echo "  ✓ FreeSleep auto-installer configured"
        echo "    Repository: https://github.com/$FREESLEEP_REPO_USER/free-sleep"
        echo "    Branch: $FREESLEEP_BRANCH"
        if [[ "$FREESLEEP_BIOMETRICS" = true ]]; then
            echo "    Biometrics: Enabled"
        fi
    fi
    
    # Verify subsystem initialization services
    if sudo test -f "$STAGING_DIR/etc/systemd/system/populate-deviceinfo.service"; then
        echo "  ✓ Pod 3 subsystem services configured"
        echo "    - populate-deviceinfo.service (creates /deviceinfo/ files)"
        echo "    - enable-subsystems.service (initializes PCAL6416A GPIO expander)"
        echo "    - frank.service override (removed Capybara dependency)"
        echo "    - freesleep-service-fixer.service (adds deps after install)"
        echo "    - capybara.service masked"
    fi
fi

if [[ ! -z "$VALIDATION_SCRIPT" ]]; then
    if sudo test -f "$STAGING_DIR/home/rewt/validate_deployment.sh"; then
        echo "  ✓ Validation script included at /home/rewt/validate_deployment.sh"
    fi
fi

ROOTFS_SIZE=$(sudo stat -c%s "$ROOTFS_TAR_GZ")
ROOTFS_SIZE_MB=$((ROOTFS_SIZE / 1024 / 1024))
echo "  ✓ Repacked rootfs.tar.gz: ${ROOTFS_SIZE_MB}MB"

echo ""
# --- Move patched image to output location ---
echo "[*] Moving patched image to output location..."
sudo mv "$WORKING_IMG" "$OUTPUT_FILE"
sudo chown $(id -u):$(id -g) "$OUTPUT_FILE"
echo "[+] Patched image saved to: $OUTPUT_FILE"
echo ""
echo "======================================"
echo "[+] Patch workflow complete!"
echo "======================================"

if [[ ! -z "$SSID" ]]; then
    echo ""
    echo "WiFi Configuration:"
    echo "  - Network: $SSID"
    echo "  - free-sleep-wifi service will initialize WiFi hardware"
    echo "  - wpa_supplicant will connect automatically on boot"
    echo "  - variscite-wifi.service masked (EEPROM check bypassed)"
fi

if [[ ! -z "$MAC_ADDRESS" ]]; then
    echo ""
    echo "MAC Address Configuration:"
    echo "  - Persistent MAC: $MAC_ADDRESS"
    echo "  - Configured via free-sleep-mac service"
    echo "  - Will NOT change on factory reset"
    echo "  - Survives reboots and system updates"
fi

if [[ ! -z "$TIME_SERVER" ]]; then
    echo ""
    echo "NTP Time Server Configuration:"
    echo "  - Time server: $TIME_SERVER"
    echo "  - Fallback servers: pool.ntp.org, time.google.com"
    echo "  - systemd-timesyncd will sync time automatically"
    echo "  - Check status: timedatectl status"
fi

if [[ "$FREESLEEP_INSTALL" = true ]]; then
    echo ""
    echo "FreeSleep Configuration:"
    echo "  - Auto-installer will run on SECOND boot (after network initialization)"
    echo "  - Repository: https://github.com/$FREESLEEP_REPO_USER/free-sleep"
    echo "  - Branch: $FREESLEEP_BRANCH"
    echo "  - Server will be accessible at http://<POD_IP>:3000"
    if [[ "$FREESLEEP_BIOMETRICS" = true ]]; then
        echo "  - Biometrics will be enabled automatically"
    fi
    if [[ -n "$FREESLEEP_TIMEZONE" ]]; then
        echo "  - Timezone will be set to: $FREESLEEP_TIMEZONE"
        echo "    (Ensures schedules run at correct local times)"
    else
        echo "  - ⚠️  Timezone defaults to UTC - set via web UI Settings for correct schedule times!"
    fi
    echo "  - Eight Sleep Capybara service disabled (replaced by subsystem services)"
    if [[ ! -z "$SSID" ]]; then
        echo "  - Device will remain reachable via WiFi: $SSID"
    fi
    echo ""
    echo "Boot Sequence:"
    echo "  Factory Reset: Extracts rootfs.tar.gz with patched services"
    echo "  1. First boot: Immediate reboot to apply rootfs changes (firstboot-reboot.service)"
    echo "  2. Second boot: Network init + Eight Sleep disabled → Automatic reboot"
    echo "  3. Third boot: FreeSleep installation (5-10 minutes) → Automatic reboot"  
    echo "  4. Fourth boot: FreeSleep running, all services configured"
    if [[ -n "$FREESLEEP_TIMEZONE" ]]; then
        echo "                 Timezone automatically set on startup"
    fi
    echo ""
    echo "Hardware Initialization (on every boot):"
    echo "  populate-deviceinfo → enable-subsystems → frank → free-sleep"
    echo "  - populate-deviceinfo: Creates /deviceinfo/ files from MAC address"
    echo "  - enable-subsystems: Initializes PCAL6416A GPIO expander"
    echo "  - frank: Frankenfirmware connects to hardware"
    echo "  - free-sleep: FreeSleep controls temperature via frankenfirmware"
    echo ""
    echo "During installation:"
    echo "  - Wait 20-25 minutes total for all reboots and installation"
    echo "  - First reboot happens within seconds (applies filesystem changes)"
    echo "  - Check status: systemctl status freesleep-installer"
    echo "  - View logs: journalctl -u freesleep-installer -f"
    echo "  - After completion: http://<POD_IP>:3000"
fi

if [[ ! -z "$VALIDATION_SCRIPT" ]]; then
    echo ""
    echo "Validation Script:"
    echo "  - Script included at: /home/rewt/validate_deployment.sh"
    echo "  - Welcome banner will show script location on first SSH login"
    echo "  - Run with: ~/validate_deployment.sh or ./validate_deployment.sh"
    echo "  - Validates network, services, and configuration"
fi

echo ""
echo "[*] Flash patched SD card image and perform factory reset to apply changes."
echo "[*] Original image preserved at: $IMG_FILE"
