#!/bin/bash
#
# WSL Cross-Compilation Build Script for opensleep
# Runs on Ubuntu in WSL to build ARM64 binary for Eight Sleep Pod 3
#
# Usage:
#   ./wsl_build_for_pod.sh [options]
#
# Options:
#   -c, --clean           Clean build (removes target directory)
#   -d, --debug           Build in debug mode (faster compilation)
#   -b, --branch BRANCH   Build specific branch (default: main)
#   -l, --local PATH      Use local checkout at PATH (skip git pull)
#   -u, --upload          Automatically upload to Pod after build
#   -i, --pod-ip IP       Pod IP address (for upload)
#   -p, --pod-port PORT   Pod SSH port (default: 8822)
#   -U, --pod-user USER   Pod SSH user (default: rewt)
#   -h, --help            Show this help message
#

set -e  # Exit on error

# ============================================================================
# Configuration
# ============================================================================

BUILD_MODE="release"
CLEAN_BUILD=false
BRANCH="main"
LOCAL_PATH=""
UPLOAD=false
POD_IP=""
POD_PORT="8822"
POD_USER="rewt"
POD_INSTALL_DIR="/opt/opensleep"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# Helper Functions
# ============================================================================

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✓${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ✗${NC} $1"
}

usage() {
    cat <<EOF
WSL Cross-Compilation Build Script for opensleep

Usage: $0 [options]

Options:
  -c, --clean           Clean build (removes target directory)
  -d, --debug           Build in debug mode (faster compilation)
  -b, --branch BRANCH   Build specific branch (default: main)
  -l, --local PATH      Use local checkout at PATH (skip git operations)
  -u, --upload          Automatically upload to Pod after build
  -i, --pod-ip IP       Pod IP address (required for upload)
  -p, --pod-port PORT   Pod SSH port (default: 8822)
  -U, --pod-user USER   Pod SSH user (default: rewt)
  -h, --help            Show this help message

Examples:
  # Basic build
  $0

  # Clean release build
  $0 --clean

  # Build from local checkout (no git pull)
  $0 --local /mnt/f/workspaces/opensleep

  # Build and upload to Pod
  $0 --upload --pod-ip 192.168.2.52

  # Build specific branch
  $0 --branch issue_6

  # Debug build from local path
  $0 --debug --local /mnt/f/workspaces/opensleep

EOF
    exit 0
}

# ============================================================================
# Parse Arguments
# ============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--clean)
            CLEAN_BUILD=true
            shift
            ;;
        -d|--debug)
            BUILD_MODE="debug"
            shift
            ;;
        -b|--branch)
            BRANCH="$2"
            shift 2
            ;;
        -l|--local)
            LOCAL_PATH="$2"
            shift 2
            ;;
        -u|--upload)
            UPLOAD=true
            shift
            ;;
        -i|--pod-ip)
            POD_IP="$2"
            shift 2
            ;;
        -p|--pod-port)
            POD_PORT="$2"
            shift 2
            ;;
        -U|--pod-user)
            POD_USER="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate local path if provided
if [ -n "$LOCAL_PATH" ] && [ ! -d "$LOCAL_PATH" ]; then
    log_error "Local path does not exist: $LOCAL_PATH"
    exit 1
fi

if [ -n "$LOCAL_PATH" ] && [ ! -f "$LOCAL_PATH/Cargo.toml" ]; then
    log_error "Not a valid opensleep repository: $LOCAL_PATH (missing Cargo.toml)"
    exit 1
fi

# Validate upload requirements
if [ "$UPLOAD" = true ] && [ -z "$POD_IP" ]; then
    log_error "Pod IP address is required for upload. Use --pod-ip"
    exit 1
fi

# ============================================================================
# Main Script
# ============================================================================

log "=========================================="
log "opensleep WSL Build Script"
log "=========================================="
log ""
log "Configuration:"
log "  Build Mode: $BUILD_MODE"
if [ -n "$LOCAL_PATH" ]; then
    log "  Local Path: $LOCAL_PATH"
else
    log "  Branch: $BRANCH"
fi
log "  Clean Build: $CLEAN_BUILD"
log "  Upload: $UPLOAD"
if [ "$UPLOAD" = true ]; then
    log "  Pod: $POD_USER@$POD_IP:$POD_PORT"
fi
log ""

# ============================================================================
# Step 1: Check System Requirements
# ============================================================================

log "Step 1: Checking system requirements..."

# Check if running in WSL
if ! grep -qi microsoft /proc/version 2>/dev/null; then
    log_warning "Not running in WSL, but continuing anyway..."
fi

# Check for Rust
if ! command -v cargo &> /dev/null || ! command -v rustc &> /dev/null; then
    log_warning "Rust not found, installing..."
    log ""
    
    # Install Rust
    if curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y; then
        log_success "Rust installed successfully"
        
        # Source the cargo environment
        if [ -f "$HOME/.cargo/env" ]; then
            source "$HOME/.cargo/env"
        fi
        
        # Verify installation
        if command -v cargo &> /dev/null && command -v rustc &> /dev/null; then
            log_success "Rust $(rustc --version | awk '{print $2}') is now available"
        else
            log_error "Rust installation failed"
            exit 1
        fi
    else
        log_error "Failed to install Rust"
        exit 1
    fi
else
    # Source cargo environment to ensure it's in PATH
    if [ -f "$HOME/.cargo/env" ]; then
        source "$HOME/.cargo/env"
    fi
    log_success "Rust $(rustc --version | awk '{print $2}') found"
fi

# Check for ARM64 target
if ! rustup target list --installed | grep -q aarch64-unknown-linux-musl; then
    log_warning "ARM64 musl target not installed, installing..."
    rustup target add aarch64-unknown-linux-musl
    log_success "ARM64 musl target installed"
else
    log_success "ARM64 musl target already installed"
fi

# Also install gnu target as fallback
if ! rustup target list --installed | grep -q aarch64-unknown-linux-gnu; then
    log "Installing ARM64 gnu target as well..."
    rustup target add aarch64-unknown-linux-gnu
fi

# Check for cross-compiler
MUSL_GCC_INSTALLED=false
if command -v aarch64-linux-musl-gcc &> /dev/null; then
    MUSL_GCC_INSTALLED=true
    log_success "ARM64 musl cross-compiler found: $(aarch64-linux-musl-gcc --version | head -n1)"
elif ! command -v aarch64-linux-gnu-gcc &> /dev/null; then
    log_warning "ARM64 cross-compiler not found, installing..."
    log ""
    
    # Install cross-compiler and dependencies
    log "Running: sudo apt update"
    sudo apt update
    
    log "Running: sudo apt install -y gcc-aarch64-linux-gnu build-essential pkg-config libudev-dev musl-tools"
    if sudo apt install -y gcc-aarch64-linux-gnu build-essential pkg-config libudev-dev musl-tools; then
        log_success "Cross-compiler and dependencies installed"
    else
        log_error "Failed to install cross-compiler"
        log_error "You may need to run manually:"
        log_error "  sudo apt update"
        log_error "  sudo apt install -y gcc-aarch64-linux-gnu build-essential pkg-config libudev-dev musl-tools"
        exit 1
    fi
    
    # Verify installation
    if command -v aarch64-linux-gnu-gcc &> /dev/null; then
        log_success "ARM64 cross-compiler found: $(aarch64-linux-gnu-gcc --version | head -n1)"
    else
        log_error "Cross-compiler installation verification failed"
        exit 1
    fi
else
    log_success "ARM64 cross-compiler found: $(aarch64-linux-gnu-gcc --version | head -n1)"
    
    # Check for other dependencies and install if missing
    MISSING_DEPS=()
    
    if ! command -v pkg-config &> /dev/null; then
        MISSING_DEPS+=("pkg-config")
    fi
    
    if ! dpkg -l 2>/dev/null | grep -q libudev-dev; then
        MISSING_DEPS+=("libudev-dev")
    fi
    
    if ! dpkg -l 2>/dev/null | grep -q build-essential; then
        MISSING_DEPS+=("build-essential")
    fi
    
    if ! dpkg -l 2>/dev/null | grep -q musl-tools; then
        MISSING_DEPS+=("musl-tools")
    fi
    
    if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
        log_warning "Missing dependencies: ${MISSING_DEPS[*]}"
        log "Installing missing dependencies..."
        sudo apt update
        if sudo apt install -y "${MISSING_DEPS[@]}"; then
            log_success "Dependencies installed"
        else
            log_warning "Some dependencies may not have installed (non-critical)"
        fi
    fi
fi

# Try to download musl cross-compiler if not available via apt
if ! command -v aarch64-linux-musl-gcc &> /dev/null && [ "$MUSL_GCC_INSTALLED" = false ]; then
    log_warning "Dedicated musl cross-compiler not found"
    log "Will use gnu cross-compiler with static linking flags"
fi

log ""

# ============================================================================
# Step 2: Setup Cargo Configuration
# ============================================================================

log "Step 2: Configuring cross-compilation..."

# Create cargo config directory
mkdir -p ~/.cargo

# Create or update cargo config
if command -v aarch64-linux-musl-gcc &> /dev/null; then
    # Use dedicated musl cross-compiler
    cat > ~/.cargo/config.toml <<'EOF'
[target.aarch64-unknown-linux-gnu]
linker = "aarch64-linux-gnu-gcc"

[target.aarch64-unknown-linux-musl]
linker = "aarch64-linux-musl-gcc"
EOF
    log_success "Cargo configuration updated (using musl cross-compiler)"
else
    # Use gnu cross-compiler with static linking
    cat > ~/.cargo/config.toml <<'EOF'
[target.aarch64-unknown-linux-gnu]
linker = "aarch64-linux-gnu-gcc"

[target.aarch64-unknown-linux-musl]
linker = "aarch64-linux-gnu-gcc"
rustflags = ["-C", "target-feature=+crt-static"]

[build]
rustflags = ["-C", "target-feature=+crt-static"]
EOF
    log_success "Cargo configuration updated (using static linking)"
fi

log ""

# ============================================================================
# Step 3: Get to Repository Directory
# ============================================================================

log "Step 3: Locating repository..."

# If local path provided, use it directly
if [ -n "$LOCAL_PATH" ]; then
    REPO_DIR="$LOCAL_PATH"
    log_success "Using local repository: $REPO_DIR"
    cd "$REPO_DIR"
    
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    log "Current branch: $CURRENT_BRANCH"
    log "Skipping git operations (using local checkout as-is)"
else
    # Try to find the opensleep directory
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    REPO_DIR=""

    # Check if we're already in the repo
    if [ -f "$SCRIPT_DIR/../Cargo.toml" ] && grep -q "opensleep" "$SCRIPT_DIR/../Cargo.toml" 2>/dev/null; then
        REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
        log_success "Repository found: $REPO_DIR"
    elif [ -f "$SCRIPT_DIR/Cargo.toml" ] && grep -q "opensleep" "$SCRIPT_DIR/Cargo.toml" 2>/dev/null; then
        REPO_DIR="$SCRIPT_DIR"
        log_success "Repository found: $REPO_DIR"
    else
        log_error "Cannot find opensleep repository"
        log_error "Please run this script from within the opensleep directory"
        log_error "Or use --local /path/to/opensleep"
        exit 1
    fi

    cd "$REPO_DIR"

    # Check current branch
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    log "Current branch: $CURRENT_BRANCH"

    # Checkout requested branch if different
    if [ "$BRANCH" != "$CURRENT_BRANCH" ] && [ "$BRANCH" != "unknown" ]; then
        log "Checking out branch: $BRANCH"
        
        # Fetch from origin (try to handle both SSH and HTTPS)
        if ! git fetch origin 2>&1; then
            log_warning "Git fetch failed, this might be okay if working offline"
        fi
        
        # Try to checkout the branch
        if git checkout "$BRANCH" 2>/dev/null; then
            log_success "Checked out branch: $BRANCH"
            
            # Try to pull latest changes
            if git pull origin "$BRANCH" 2>/dev/null; then
                log_success "Updated to latest changes"
            else
                log_warning "Could not pull latest changes (might be offline or no remote access)"
                log "Continuing with local branch..."
            fi
        else
            log_warning "Could not checkout branch: $BRANCH"
            log "Continuing with current branch: $CURRENT_BRANCH"
            BRANCH="$CURRENT_BRANCH"
        fi
    else
        log "Using current branch: $CURRENT_BRANCH"
        
        # Try to pull latest changes if on the same branch
        if [ "$BRANCH" = "$CURRENT_BRANCH" ] && git remote get-url origin &>/dev/null; then
            log "Attempting to update to latest changes..."
            if git pull 2>/dev/null; then
                log_success "Updated to latest changes"
            else
                log_warning "Could not pull latest changes (might be offline or no remote access)"
                log "Continuing with local code..."
            fi
        fi
    fi
fi

log ""

# ============================================================================
# Step 4: Build the Project
# ============================================================================

log "Step 4: Building opensleep for ARM64..."

# Clean if requested
if [ "$CLEAN_BUILD" = true ]; then
    log "Performing clean build..."
    cargo clean
fi

# Determine build command and binary path
if [ "$BUILD_MODE" = "debug" ]; then
    log "Building in debug mode (faster compilation)..."
    BUILD_CMD="cargo build --target aarch64-unknown-linux-musl"
    BINARY_PATH="target/aarch64-unknown-linux-musl/debug/opensleep"
else
    log "Building in release mode (optimized, static binary)..."
    BUILD_CMD="cargo build --release --target aarch64-unknown-linux-musl"
    BINARY_PATH="target/aarch64-unknown-linux-musl/release/opensleep"
fi

log "Running: $BUILD_CMD"
log ""

START_TIME=$(date +%s)

if $BUILD_CMD; then
    END_TIME=$(date +%s)
    BUILD_TIME=$((END_TIME - START_TIME))
    log_success "Build completed in ${BUILD_TIME} seconds"
else
    log_error "Build failed"
    exit 1
fi

# Verify binary exists
if [ ! -f "$BINARY_PATH" ]; then
    log_error "Binary not found at $BINARY_PATH"
    exit 1
fi

# Check binary architecture
FILE_OUTPUT=$(file "$BINARY_PATH")
if echo "$FILE_OUTPUT" | grep -q "ARM aarch64"; then
    log_success "Binary verified as ARM64"
    
    # Check if it's statically or dynamically linked
    if ldd "$BINARY_PATH" 2>&1 | grep -q "not a dynamic executable"; then
        log_success "Binary is statically linked (no glibc dependency!)"
    elif ldd "$BINARY_PATH" 2>&1 | grep -q "statically linked"; then
        log_success "Binary is statically linked (no glibc dependency!)"
    else
        log_warning "Binary appears to be dynamically linked:"
        ldd "$BINARY_PATH" 2>&1 | head -10 | while read line; do log "  $line"; done
        log_warning "This may cause glibc version issues on older systems"
        log_warning "Binary location: $BINARY_PATH"
    fi
else
    log_error "Binary is not ARM64!"
    log_error "File output: $FILE_OUTPUT"
    exit 1
fi

BINARY_SIZE=$(du -h "$BINARY_PATH" | cut -f1)
log "Binary size: $BINARY_SIZE"
log ""

# Exit if not uploading
if [ "$UPLOAD" = false ]; then
    log_success "Build completed successfully!"
    log ""
    log "Binary location: $BINARY_PATH"
    log ""
    log "To upload to Pod manually:"
    log "  scp -P $POD_PORT $BINARY_PATH $POD_USER@POD_IP:$POD_INSTALL_DIR/"
    log ""
    exit 0
fi

# ============================================================================
# Step 5: Upload to Pod
# ============================================================================

log "Step 5: Uploading to Pod..."

# Test SSH connection first
log "Testing SSH connection to $POD_USER@$POD_IP:$POD_PORT..."
if ! ssh -p "$POD_PORT" -o ConnectTimeout=5 "$POD_USER@$POD_IP" "echo 'Connection successful'" &>/dev/null; then
    log_error "Cannot connect to Pod via SSH"
    log_error "Please check:"
    log_error "  - Pod IP address: $POD_IP"
    log_error "  - SSH port: $POD_PORT"
    log_error "  - SSH user: $POD_USER"
    log_error "  - Network connectivity"
    log_error ""
    log_error "Binary is available at: $BINARY_PATH"
    exit 1
fi

log_success "SSH connection successful"

# Create backup on Pod
log "Creating backup on Pod..."
ssh -p "$POD_PORT" "$POD_USER@$POD_IP" "sudo mkdir -p /opt/opensleep_backup && sudo cp $POD_INSTALL_DIR/opensleep /opt/opensleep_backup/opensleep.\$(date +%Y%m%d_%H%M%S) 2>/dev/null || true"

# Stop service
log "Stopping opensleep service..."
ssh -p "$POD_PORT" "$POD_USER@$POD_IP" "sudo systemctl stop opensleep 2>/dev/null || true"

# Upload binary
log "Uploading binary..."
if scp -P "$POD_PORT" "$BINARY_PATH" "$POD_USER@$POD_IP:/tmp/opensleep"; then
    log_success "Upload successful"
else
    log_error "Upload failed"
    exit 1
fi

# Move to install location and set permissions
log "Installing binary..."
ssh -p "$POD_PORT" "$POD_USER@$POD_IP" "sudo mv /tmp/opensleep $POD_INSTALL_DIR/opensleep && sudo chmod +x $POD_INSTALL_DIR/opensleep"

# Start service
log "Starting opensleep service..."
ssh -p "$POD_PORT" "$POD_USER@$POD_IP" "sudo systemctl start opensleep"

# Wait and check status
sleep 2
if ssh -p "$POD_PORT" "$POD_USER@$POD_IP" "sudo systemctl is-active --quiet opensleep"; then
    log_success "Service started successfully"
else
    log_error "Service failed to start!"
    log_error "Check logs with: ssh -p $POD_PORT $POD_USER@$POD_IP 'sudo journalctl -u opensleep -n 50'"
    
    # Try to restore backup
    log_warning "Attempting to restore backup..."
    ssh -p "$POD_PORT" "$POD_USER@$POD_IP" "sudo cp \$(ls -t /opt/opensleep_backup/opensleep.* | head -n1) $POD_INSTALL_DIR/opensleep && sudo chmod +x $POD_INSTALL_DIR/opensleep && sudo systemctl start opensleep" || true
    exit 1
fi

log ""
log "=========================================="
log "Build and Deploy Complete!"
log "=========================================="
log ""
log "Summary:"
log "  Binary: $BINARY_PATH"
log "  Size: $BINARY_SIZE"
log "  Build Time: ${BUILD_TIME}s"
log "  Deployed to: $POD_USER@$POD_IP:$POD_INSTALL_DIR/opensleep"
log "  Service Status: Running"
log ""
log "Useful commands:"
log "  View logs: ssh -p $POD_PORT $POD_USER@$POD_IP 'sudo journalctl -u opensleep -f'"
log "  Service status: ssh -p $POD_PORT $POD_USER@$POD_IP 'sudo systemctl status opensleep'"
log "  Restart service: ssh -p $POD_PORT $POD_USER@$POD_IP 'sudo systemctl restart opensleep'"
log ""
log_success "All operations completed successfully!"
log ""

exit 0
