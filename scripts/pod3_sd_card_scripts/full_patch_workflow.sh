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
DISABLE_SERVICES=false
FREESLEEP_INSTALL=false
FREESLEEP_REPO_USER="securitycopper"
FREESLEEP_BRANCH="main"
FREESLEEP_BIOMETRICS=false
FREESLEEP_TIMEZONE=""
BUILD_PYTHON=false
OUTPUT_FILE=""
WORK_DIR_CUSTOM=""
VALIDATION_SCRIPT=""
MAC_ADDRESS=""
TIME_SERVER=""

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
Usage: $0 -i IMAGE_FILE -k PUBKEY_FILE [-o OUTPUT_FILE] [-w WORK_DIR] [-m MAC_ADDRESS] [-t TIME_SERVER] [-T TIMEZONE] [-f] [-U USER] [-F BRANCH] [-B] [-Y] [-v VALIDATION_SCRIPT]

⚠️  Pod 3 (SD Card Version) ONLY
   This script is designed for Eight Sleep Pod 3 with removable SD card.
   It does NOT work with Pod 1, 2, 4, 5, or Pod 3 eMMC (non-SD) versions.

🔄 CAPYBARA-ASSISTED WORKFLOW
   This workflow leverages Capybara for WiFi configuration:
   - WiFi setup handled automatically via Eight Sleep app pairing
   - No manual WiFi credentials needed in this script
   - After pairing completes, system auto-transitions to FreeSleep
   - Eight Sleep SSH keys preserved (required for Capybara pairing)
   - Passwordless root access via SSH keys (no password needed)

Required arguments:
  -i IMAGE_FILE    Path to the SD card image file
  -k PUBKEY_FILE   Path to the SSH public key file

Optional arguments:
  -o OUTPUT_FILE   Path for the patched output image (default: <original>-patched.img)
  -w WORK_DIR      Custom working directory (must be empty, needs 16GB free space)
  -m MAC_ADDRESS   Set persistent MAC address for wlan0 (format: AA:BB:CC:DD:EE:FF)
                   Prevents MAC from changing on factory reset
                   Note: Optional - Capybara will configure WiFi connection
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
  -f               Enable FreeSleep auto-install after Capybara pairing
                   FreeSleep will be installed automatically after Eight Sleep pairing completes
                   Installation script: https://raw.githubusercontent.com/securitycopper/free-sleep/main/scripts/install.sh
                   Workflow: Boot → Pair with Eight Sleep app → Auto-transition to FreeSleep
  -U USER          Specify GitHub user/org for FreeSleep fork (default: securitycopper)
                   Useful for testing development forks
                   Example: -U myusername -F my-feature-branch
  -F BRANCH        Specify FreeSleep branch to install (default: main)
                   Examples: main, dev, pod3sd_script
  -B               Enable biometrics after FreeSleep installation
                   Runs: /home/dac/free-sleep/scripts/enable_biometrics.sh
  -Y               Build Python 3.11 from source on first boot (required for biometrics)
                   Compiles Python 3.11.7 targeting GLIBC 2.33 (30-60 min on first boot)
                   Installs to /opt/python3.11/bin/python3.11
                   Required if using -B flag due to system GLIBC 2.33 vs Python 3.9 GLIBC 2.38 incompatibility
  -v VALIDATION    Path to validation script to include in image (default: auto-detect in same directory)
  -h               Show this help message

Example:
  # Capybara-assisted FreeSleep installation (recommended)
  $0 -i sdcard.img -k ~/.ssh/id_rsa.pub -f
  
  # FreeSleep with specific branch and biometrics (requires Python build)
  $0 -i sdcard.img -k ~/.ssh/id_rsa.pub -f -F dev -Y -B
  
  # FreeSleep from a development fork
  $0 -i sdcard.img -k ~/.ssh/id_rsa.pub -f -U myusername -F my-feature
  
  # FreeSleep with persistent MAC address and time server
  $0 -i sdcard.img -k ~/.ssh/id_rsa.pub -f -m "02:11:22:33:44:55" -t "pool.ntp.org"
  
  # FreeSleep with timezone for correct schedule times
  $0 -i sdcard.img -k ~/.ssh/id_rsa.pub -f -T "America/New_York"
  
  # Just SSH access, manual setup later (minimal patching)
  $0 -i sdcard.img -k ~/.ssh/id_rsa.pub
EOF
    exit 1
}

while getopts "i:k:o:w:p:P:I:G:D:T:f:U:F:B:Y:b:S:c:v:m:t:dRh" opt; do
    case $opt in
        i) IMG_FILE="$OPTARG" ;;
        k) PUBKEY_FILE="$OPTARG" ;;
        o) OUTPUT_FILE="$OPTARG" ;;
        w) WORK_DIR_CUSTOM="$OPTARG" ;;
        T) FREESLEEP_TIMEZONE="$OPTARG" ;;
        f) FREESLEEP_INSTALL=true ;;
        U) FREESLEEP_REPO_USER="$OPTARG" ;;
        F) FREESLEEP_BRANCH="$OPTARG" ;;
        B) FREESLEEP_BIOMETRICS=true ;;
        Y) BUILD_PYTHON=true ;;
        P) echo "WARNING: -P flag (password) is not supported in Capybara-assisted workflow."
           echo "Passwordless root access via SSH keys is used instead."
           ;;
        I) echo "WARNING: -I flag (static IP) is deprecated in Capybara-assisted workflow."
           echo "Network configuration is handled automatically via Eight Sleep app pairing."
           ;;
        G) echo "WARNING: -G flag (gateway) is deprecated in Capybara-assisted workflow."
           echo "Network configuration is handled automatically via Eight Sleep app pairing."
           ;;
        D) echo "WARNING: -D flag (DNS) is deprecated in Capybara-assisted workflow."
           echo "Network configuration is handled automatically via Eight Sleep app pairing."
           ;;
        s) echo "WARNING: -s flag (SSID) is deprecated in Capybara-assisted workflow."
           echo "WiFi configuration is handled automatically via Eight Sleep app pairing."
           ;;
        p) echo "WARNING: -p flag (PSK) is deprecated in Capybara-assisted workflow."
           echo "WiFi configuration is handled automatically via Eight Sleep app pairing."
           ;;
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
        d) echo "WARNING: -d flag (disable services) is deprecated in Capybara-assisted workflow."
           echo "Eight Sleep services remain active during pairing, then auto-disabled after transition."
           DISABLE_SERVICES=false ;;
        R) echo "WARNING: -R flag (remove SSH keys) is not supported in Capybara-assisted workflow."
           echo "Eight Sleep SSH keys are required for Capybara pairing to function."
           ;;
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

if [[ "$FREESLEEP_BIOMETRICS" == true ]] && [[ "$BUILD_PYTHON" == false ]]; then
    echo ""
    echo "⚠️  WARNING: Biometrics (-B) enabled without Python 3.11 build (-Y)"
    echo ""
    echo "The system has GLIBC 2.33 but Python 3.9 requires GLIBC 2.38."
    echo "Biometrics installation will likely fail without Python 3.11."
    echo ""
    echo "Recommendation: Add -Y flag to build Python 3.11 from source"
    echo "Example: $0 -i sdcard.img -k key.pub -f -Y -B"
    echo ""
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
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

# Capybara-Assisted Workflow: Eight Sleep SSH keys are preserved
# These keys are required for Capybara pairing to function properly
# Only append the user's public key to existing authorized_keys
echo "[*] Appending SSH key (Eight Sleep keys preserved for Capybara)..."
sudo bash -c "cat '$PUBKEY_FILE' >> '$AK_FILE'"
echo "  ✓ Your key appended to existing Eight Sleep keys"

sudo chmod 600 "$AK_FILE"
sudo chown "$REWT_UID:$REWT_GID" "$AK_FILE"

# Capybara-Assisted Workflow: Passwordless root access via SSH keys
# No password configuration needed - SSH key authentication is sufficient
echo "  ✓ Passwordless root access configured via SSH keys"

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

# --- WiFi Configuration Note ---
echo "[*] WiFi Configuration:"
echo "    ℹ️  WiFi setup is handled by Capybara during Eight Sleep app pairing"
echo "    ℹ️  No manual wpa_supplicant configuration needed"
echo "    ℹ️  After pairing, WiFi credentials will be captured for FreeSleep transition"

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
# DNS will be configured by Capybara during Eight Sleep app pairing
# The WiFi credentials obtained during pairing include network configuration
echo "[*] DNS Configuration:"
echo "    ℹ️  DNS configured automatically via Capybara WiFi setup"
echo "    ℹ️  Network stack properly initialized during pairing process"

# --- WiFi initialization handled by Capybara ---
# Note: In Capybara-assisted workflow, WiFi hardware initialization and
# configuration is handled by Eight Sleep's Capybara service during pairing.
# No manual WiFi service setup is needed.
echo "[*] WiFi Initialization:"
echo "    ℹ️  WiFi hardware initialization handled by Capybara"
echo "    ℹ️  No manual free-sleep-wifi service needed"
echo "    ℹ️  Eight Sleep app will configure WiFi during pairing"

# --- Enable SSH + Network Early Service ---
echo "[*] Installing ssh-early.service..."

SSH_EARLY_SERVICE="$STAGING_DIR/etc/systemd/system/ssh-early.service"
sudo mkdir -p "$(dirname "$SSH_EARLY_SERVICE")"

# SSH starts early, before most services
# Network will be configured by Capybara during Eight Sleep app pairing
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

sudo chmod 644 "$SSH_EARLY_SERVICE"

# Create systemd symlink
SYSTEMD_WANTS="$STAGING_DIR/etc/systemd/system/multi-user.target.wants"
sudo mkdir -p "$SYSTEMD_WANTS"
sudo ln -sf ../ssh-early.service "$SYSTEMD_WANTS/ssh-early.service"

echo "[+] SSH early service installed and enabled."

# --- Capybara-Assisted Workflow: No Eight Sleep Service Disabling ---
# In the Capybara-assisted workflow, Eight Sleep services (including Capybara)
# remain active during initial boot to allow pairing via the Eight Sleep app.
# After pairing completes and magic_uuid is generated, the transition script
# will automatically disable Eight Sleep services and enable FreeSleep.
echo ""
echo "ℹ️  Capybara-Assisted Workflow Active"
echo "    • Eight Sleep services remain enabled for initial pairing"
echo "    • Use Eight Sleep app to pair Pod and configure WiFi"
echo "    • Update services disabled AFTER pairing completes"
echo "    • System will auto-transition to FreeSleep after pairing"
echo ""

# --- Install pairing monitoring & transition service ---
# This service waits for Capybara pairing to complete, then disables update services
echo "[*] Installing pairing monitor and transition service..."
PAIRING_MONITOR_SERVICE="$STAGING_DIR/etc/systemd/system/monitor-pairing.service"
sudo mkdir -p "$(dirname "$PAIRING_MONITOR_SERVICE")"

sudo bash -c "cat > '$PAIRING_MONITOR_SERVICE'" <<'EOF'
[Unit]
Description=Monitor Capybara Pairing and Transition to FreeSleep
After=network-online.target capybara.service
Wants=network-online.target
# Only run after first reboot, before FreeSleep is installed
ConditionPathExists=/var/lib/firstboot-complete.flag
ConditionPathExists=!/var/lib/pairing-complete.flag

[Service]
Type=oneshot
RemainAfterExit=no
# Wait for customer-wifi.nmconnection AND working internet connectivity
# Then wait additional 2 minutes for Eight Sleep app to complete all setup tasks
ExecStart=/bin/sh -c '\
  echo "Waiting for WiFi configuration..." | systemd-cat -t pairing-monitor; \
  for i in $(seq 1 600); do \
    if [ -f /etc/NetworkManager/system-connections/customer-wifi.nmconnection ]; then \
      echo "WiFi configured! Waiting for network connectivity..." | systemd-cat -t pairing-monitor; \
      for j in $(seq 1 60); do \
        if ping -c 1 8.8.8.8 >/dev/null 2>&1; then \
          echo "Network connected! Waiting 2 minutes for Eight Sleep app to complete setup..." | systemd-cat -t pairing-monitor; \
          sleep 120; \
          echo "Setup grace period complete. Disabling update services..." | systemd-cat -t pairing-monitor; \
          for svc in swupdate-progress swupdate defibrillator swupdate.socket; do \
            systemctl disable --now $svc 2>&1 | systemd-cat -t pairing-monitor || true; \
            systemctl mask $svc 2>&1 | systemd-cat -t pairing-monitor || true; \
          done; \
          echo "Update services disabled" | systemd-cat -t pairing-monitor; \
          touch /var/lib/pairing-complete.flag; \
          echo "Pairing complete, system ready for FreeSleep installation" | systemd-cat -t pairing-monitor; \
          exit 0; \
        fi; \
        sleep 2; \
      done; \
      echo "Timeout waiting for network connectivity" | systemd-cat -t pairing-monitor; \
      exit 1; \
    fi; \
    sleep 2; \
  done; \
  echo "Timeout waiting for WiFi configuration (20 minutes)" | systemd-cat -t pairing-monitor; \
  exit 1'

[Install]
WantedBy=multi-user.target
EOF

sudo chmod 644 "$PAIRING_MONITOR_SERVICE"
# Enable the service
MULTI_USER_WANTS="$STAGING_DIR/etc/systemd/system/multi-user.target.wants"
sudo mkdir -p "$MULTI_USER_WANTS"
sudo ln -sf ../monitor-pairing.service "$MULTI_USER_WANTS/monitor-pairing.service"

echo "[+] Pairing monitor service installed"
echo "    ✓ Waits for /etc/NetworkManager/system-connections/customer-wifi.nmconnection"
echo "    ✓ Then waits for working internet connectivity (ping 8.8.8.8)"
echo "    ✓ Then waits 2 minutes for Eight Sleep app to complete setup"
echo "    ✓ Disables update services AFTER setup grace period"
echo "    ✓ Creates /var/lib/pairing-complete.flag"
echo "    ✓ Preserves Eight Sleep functionality during pairing"

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

# --- Install Python 3.11 builder (if requested) ---
if [[ "$BUILD_PYTHON" = true ]]; then
    echo "[*] Installing Python 3.11 builder..."
    echo "  ℹ️  Python 3.11 Build Configuration"
    echo "  • System has GLIBC 2.33 but Python 3.9.9 requires GLIBC 2.38"
    echo "  • Will build Python 3.11.7 from source on first boot (30-60 minutes)"
    echo "  • Builds after monitor-pairing.service (Eight Sleep updates stopped)"
    echo "  • Installs to /opt/python3.11/ for biometrics compatibility"
    echo ""
    
    # Create Python builder service
    PYTHON_BUILDER_SERVICE="$STAGING_DIR/etc/systemd/system/python-builder.service"
    sudo mkdir -p "$(dirname "$PYTHON_BUILDER_SERVICE")"
    
    sudo bash -c "cat > '$PYTHON_BUILDER_SERVICE'" <<'EOF'
[Unit]
Description=Python 3.11 Source Builder (For Biometrics GLIBC 2.33 Compatibility)
After=network-online.target monitor-pairing.service
Wants=network-online.target
# CRITICAL: Must run after monitor-pairing completes (Eight Sleep updates stopped)
ConditionPathExists=/var/lib/pairing-complete.flag
ConditionPathExists=!/opt/python3.11/bin/python3.11
ConditionPathExists=!/var/lib/python-build-complete.flag

[Service]
Type=oneshot
# Wait for DNS to be working
ExecStartPre=/bin/sh -c 'for i in $(seq 1 120); do nslookup www.python.org >/dev/null 2>&1 && break || sleep 1; done'
# Install build dependencies
ExecStartPre=/bin/sh -c 'echo "Installing build dependencies..." && apt update && apt install -y build-essential libssl-dev zlib1g-dev libncurses5-dev libreadline-dev libsqlite3-dev libgdbm-dev libbz2-dev libexpat1-dev liblzma-dev libffi-dev wget'
# Download Python 3.11.7 source
ExecStartPre=/bin/sh -c 'mkdir -p /tmp/python-build && cd /tmp/python-build && wget -q --show-progress https://www.python.org/ftp/python/3.11.7/Python-3.11.7.tgz && tar -xzf Python-3.11.7.tgz'
# Configure for GLIBC 2.33 compatibility
ExecStartPre=/bin/sh -c 'cd /tmp/python-build/Python-3.11.7 && ./configure --prefix=/opt/python3.11 --enable-optimizations --with-ensurepip=install'
# Build Python (this takes 30-60 minutes)
ExecStart=/bin/sh -c 'cd /tmp/python-build/Python-3.11.7 && make -j$(nproc) && make altinstall'
# Verify installation
ExecStartPost=/bin/sh -c '/opt/python3.11/bin/python3.11 --version && /opt/python3.11/bin/python3.11 -c "import ssl, sqlite3, zlib" && echo "Python 3.11 build successful"'
# Mark build complete
ExecStartPost=/bin/touch /var/lib/python-build-complete.flag
# Clean up build files
ExecStartPost=/bin/rm -rf /tmp/python-build
# Log completion
ExecStartPost=/bin/sh -c 'echo "Python 3.11 build completed at $(date)" >> /var/log/python-build.log'
RemainAfterExit=yes
StandardOutput=journal+console
StandardError=journal+console
TimeoutStartSec=7200

[Install]
WantedBy=network-online.target
EOF

    sudo chmod 644 "$PYTHON_BUILDER_SERVICE"
    
    # Enable the service in network-online.target
    NETWORK_ONLINE_WANTS="$STAGING_DIR/etc/systemd/system/network-online.target.wants"
    sudo mkdir -p "$NETWORK_ONLINE_WANTS"
    sudo ln -sf ../python-builder.service "$NETWORK_ONLINE_WANTS/python-builder.service"
    
    echo "[+] Python 3.11 builder configured"
    echo "    ✓ Runs after pairing-complete.flag (monitor-pairing service complete)"
    echo "    ✓ Downloads Python 3.11.7 source from python.org"
    echo "    ✓ Builds with --enable-optimizations targeting GLIBC 2.33"
    echo "    ✓ Installs to /opt/python3.11/bin/python3.11"
    echo "    ⏱️  Build time: 30-60 minutes on first boot"
    echo "    ⚠️  FreeSleep installer will wait for python-build-complete.flag"
fi

# --- Install FreeSleep auto-installer ---
if [[ "$FREESLEEP_INSTALL" = true ]]; then
    echo "[*] Installing FreeSleep auto-installer..."
    
    echo "  ℹ️  Capybara-Assisted Installation Workflow"
    echo "  • Network connectivity provided by Capybara during Eight Sleep app pairing"
    echo "  • FreeSleep will install automatically after pairing completes"
    echo "  • No manual WiFi configuration required"
    echo ""
    echo "  Using branch: $FREESLEEP_BRANCH"
    echo "  Using repository: https://github.com/$FREESLEEP_REPO_USER/free-sleep"
    if [[ "$FREESLEEP_BIOMETRICS" = true ]]; then
        echo "  Biometrics will be enabled after installation"
    fi
    
    # Create FreeSleep installer service
    FREESLEEP_INSTALLER_SERVICE="$STAGING_DIR/etc/systemd/system/freesleep-installer.service"
    sudo mkdir -p "$(dirname "$FREESLEEP_INSTALLER_SERVICE")"
    
    # Determine if we need to wait for Python build
    PYTHON_CONDITION=""
    PYTHON_AFTER=""
    if [[ "$BUILD_PYTHON" = true ]]; then
        PYTHON_CONDITION="ConditionPathExists=/var/lib/python-build-complete.flag"
        PYTHON_AFTER="python-builder.service"
    fi
    
    sudo bash -c "cat > '$FREESLEEP_INSTALLER_SERVICE'" <<'EOF'
[Unit]
Description=FreeSleep Auto-Installer (After Capybara Pairing)
After=network-online.target ssh-early.service firstboot-reboot.service monitor-pairing.service PYTHON_AFTER_PLACEHOLDER
Wants=network-online.target
# CRITICAL: Wait for pairing to complete before installing FreeSleep
ConditionPathExists=/var/lib/firstboot-complete.flag
ConditionPathExists=/var/lib/pairing-complete.flag
PYTHON_CONDITION_PLACEHOLDER
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
    
    # Replace Python build placeholders
    if [[ "$BUILD_PYTHON" = true ]]; then
        sudo sed -i "s|PYTHON_AFTER_PLACEHOLDER|$PYTHON_AFTER|g" "$FREESLEEP_INSTALLER_SERVICE"
        sudo sed -i "s|PYTHON_CONDITION_PLACEHOLDER|$PYTHON_CONDITION|g" "$FREESLEEP_INSTALLER_SERVICE"
    else
        sudo sed -i "s|PYTHON_AFTER_PLACEHOLDER||g" "$FREESLEEP_INSTALLER_SERVICE"
        sudo sed -i "/PYTHON_CONDITION_PLACEHOLDER/d" "$FREESLEEP_INSTALLER_SERVICE"
    fi
    
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
    echo "    ✓ Waits for pairing-complete.flag (monitor-pairing service must finish first)"
    echo "    ✓ Then installs after network is stable (network-online.target)"
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
Documentation=https://github.com/securitycopper/free-sleep
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
Documentation=https://github.com/securitycopper/free-sleep
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
    echo "Adding subsystem and frank dependencies to free-sleep.service..."; \
    MODIFIED=0; \
    if ! grep -q "After=.*enable-subsystems.service" /etc/systemd/system/free-sleep.service; then \
      sed -i "/^After=/s/$/ enable-subsystems.service/" /etc/systemd/system/free-sleep.service; \
      MODIFIED=1; \
      echo "✓ Added enable-subsystems.service dependency"; \
    fi; \
    if ! grep -q "After=.*frank.service" /etc/systemd/system/free-sleep.service; then \
      sed -i "/^After=/s/$/ frank.service/" /etc/systemd/system/free-sleep.service; \
      MODIFIED=1; \
      echo "✓ Added frank.service dependency (ensures dac.sock exists before connecting)"; \
    fi; \
    if [ $MODIFIED -eq 1 ]; then \
      systemctl daemon-reload; \
      echo "✓ free-sleep.service dependencies updated"; \
    else \
      echo "✓ free-sleep.service already has all required dependencies"; \
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
    echo "Troubleshooting & Maintenance:"
    echo "  sh /home/dac/free-sleep/scripts/debug.sh      # System diagnostics"
    echo "  sh /home/dac/free-sleep/scripts/restart.sh    # Restart FreeSleep"
    echo "  sh /home/dac/free-sleep/scripts/reset.sh      # Factory reset"
    echo "  sh /home/dac/free-sleep/scripts/update.sh     # Update to latest"
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
    echo "  ✓ SSH authorized_keys file created (passwordless root access)"
else
    echo "  ✗ Warning: Could not verify authorized_keys"
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
        if [[ "$BUILD_PYTHON" = true ]]; then
            echo "    Python 3.11: Will build on first boot (30-60 min)"
        fi
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

echo ""
echo "🔄 Capybara-Assisted Installation Workflow:"
echo "  • WiFi configured automatically via Eight Sleep app"
echo "  • No manual network setup required"
echo "  • After pairing, system auto-transitions to FreeSleep"

if [[ ! -z "$MAC_ADDRESS" ]]; then
    echo ""
    echo "MAC Address Configuration:"
    echo "  - Persistent MAC: $MAC_ADDRESS"
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
    echo ""
    echo "┌─────────────────────────────────────────────────────────────────────┐"
    echo "│          Boot Sequence (Capybara-Assisted Workflow)                │"
    echo "└─────────────────────────────────────────────────────────────────────┘"
    echo ""
    echo "  Factory Reset"
    echo "  └─> Extracts rootfs.tar.gz with FreeSleep services embedded"
    echo ""
    echo "  ╔═══════════════════════════════════════════════════════════════════╗"
    echo "  ║  BOOT 1: First Boot (Immediate Reboot)                           ║"
    echo "  ╚═══════════════════════════════════════════════════════════════════╝"
    echo "      • firstboot-reboot.service detects factory reset"
    echo "      • Creates /var/lib/firstboot-complete.flag"
    echo "      • Triggers immediate reboot (~30 seconds)"
    echo "      • Purpose: Apply rootfs changes to running system"
    echo ""
    echo "  ╔═══════════════════════════════════════════════════════════════════╗"
    echo "  ║  BOOT 2: Pairing Boot (Eight Sleep App)                          ║"
    echo "  ╚═══════════════════════════════════════════════════════════════════╝"
    echo "      • Eight Sleep services ACTIVE (capybara.service running)"
    echo "      • Pod ready for pairing via Eight Sleep mobile app"
    echo ""
    echo "      ┌─────────────────────────────────────────────────┐"
    echo "      │  👤 USER ACTION REQUIRED                        │"
    echo "      │  ════════════════════════                       │"
    echo "      │  1. Open Eight Sleep mobile app                │"
    echo "      │  2. Select 'Pair Pod'                           │"
    echo "      │  3. Follow pairing wizard                       │"
    echo "      │  4. Select WiFi network & enter password        │"
    echo "      │  5. Wait for pairing to complete                │"
    echo "      │     (LED will indicate success)                 │"
    echo "      └─────────────────────────────────────────────────┘"
    echo ""
    echo "      • Capybara configures WiFi (wpa_supplicant + NetworkManager)"
    echo "      • Creates /etc/NetworkManager/system-connections/customer-wifi.nmconnection"
    echo "      • monitor-pairing.service detects WiFi file"
    echo "      • Validates network connectivity (ping 8.8.8.8)"
    echo "      • Waits 2 minutes for Eight Sleep app to complete setup"
    echo "      • Disables update services (swupdate, defibrillator, etc.)"
    echo "      • Creates /var/lib/pairing-complete.flag"
    echo "      • freesleep-installer.service can now start"
    echo ""
    echo "  ╔═══════════════════════════════════════════════════════════════════╗"
    echo "  ║  BOOT 3: Installation Boot (FreeSleep Setup)                     ║"
    echo "  ╚═══════════════════════════════════════════════════════════════════╝"
    echo "      • freesleep-installer.service starts"
    echo "      • Clones FreeSleep repository from GitHub"
    echo "      • Installs Node.js dependencies (app + server)"
    echo "      • Builds production bundles"
    if [[ "$FREESLEEP_BIOMETRICS" = true ]]; then
    echo "      • Enables biometrics (enable_biometrics.sh)"
    fi
    echo "      • Enables free-sleep.service"
    echo "      • Installation duration: ~5-10 minutes"
    echo "      • System triggers final reboot"
    echo ""
    echo "  ╔═══════════════════════════════════════════════════════════════════╗"
    echo "  ║  BOOT 4: Production Boot (FreeSleep Operational) ✓               ║"
    echo "  ╚═══════════════════════════════════════════════════════════════════╝"
    echo "      • free-sleep.service starts FreeSleep server"
    echo "      • Web UI accessible at http://<POD_IP>:3000"
    if [[ -n "$FREESLEEP_TIMEZONE" ]]; then
    echo "      • Timezone auto-configured: $FREESLEEP_TIMEZONE"
    fi
    echo "      • All subsystems initialized and operational"
    echo "      • Temperature control via frankenfirmware active"
    echo "      • Sleep tracking via biometrics active"
    echo ""
    echo "  ┌─────────────────────────────────────────────────────────────────┐"
    echo "  │  Hardware Initialization Chain (every boot):                   │"
    echo "  └─────────────────────────────────────────────────────────────────┘"
    echo "      populate-deviceinfo → enable-subsystems → frank → free-sleep"
    echo ""
    echo "      • populate-deviceinfo: Creates /deviceinfo/ from MAC address"
    echo "      • enable-subsystems:   Initializes PCAL6416A GPIO expander"
    echo "      • frank:               Frankenfirmware hardware interface"
    echo "      • free-sleep:          FreeSleep server (port 3000)"
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════════╗"
    echo "║  Expected Timeline                                                ║"
    echo "╚═══════════════════════════════════════════════════════════════════╝"
    echo "  • Flash SD card & insert: ~5 minutes"
    echo "  • Boot 1 (factory reset): ~30 seconds"
    echo "  • Boot 2 (pairing ready): ~1 minute"
    echo "  • Eight Sleep app pairing: ~5-10 minutes (user action)"
    echo "  • Auto-transition: ~30 seconds"
    echo "  • Boot 3 (installation): ~5-10 minutes"
    echo "  • Boot 4 (operational): ~30 seconds"
    echo "  ─────────────────────────────────────────────────────────────────"
    echo "  TOTAL TIME: ~15-30 minutes (including user pairing)"
    echo ""
    echo "After Pairing:"
    echo "  - Check status: systemctl status freesleep-installer"
    echo "  - View logs: journalctl -u freesleep-installer -f"
    echo "  - Access FreeSleep: http://<POD_IP>:3000"
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
