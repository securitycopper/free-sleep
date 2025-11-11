# WSL Build Script for opensleep Pod 3

Build opensleep on Windows using WSL Ubuntu and deploy to your Pod.

## Quick Start

### First Time Setup

1. **Open WSL Ubuntu terminal:**
   ```bash
   wsl
   ```

2. **Install Rust (if not already installed):**
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
   source $HOME/.cargo/env
   ```

3. **Install cross-compilation tools:**
   ```bash
   sudo apt update
   sudo apt install -y gcc-aarch64-linux-gnu build-essential pkg-config libudev-dev
   ```

4. **Add ARM64 target:**
   ```bash
   rustup target add aarch64-unknown-linux-gnu
   ```

### Build and Deploy

Navigate to the opensleep directory in WSL:
```bash
cd /mnt/f/workspaces/opensleep
```

**Build only:**
```bash
./scripts/wsl_build_for_pod.sh
```

**Build and automatically upload to Pod:**
```bash
./scripts/wsl_build_for_pod.sh --upload --pod-ip 192.168.2.52
```

## Usage

```bash
./scripts/wsl_build_for_pod.sh [options]
```

### Options

| Option | Description |
|--------|-------------|
| `-c`, `--clean` | Clean build (removes target directory) |
| `-d`, `--debug` | Build in debug mode (faster compilation) |
| `-b`, `--branch BRANCH` | Build specific branch (default: main) |
| `-u`, `--upload` | Automatically upload to Pod after build |
| `-i`, `--pod-ip IP` | Pod IP address (required for upload) |
| `-p`, `--pod-port PORT` | Pod SSH port (default: 8822) |
| `-U`, `--pod-user USER` | Pod SSH user (default: rewt) |
| `-h`, `--help` | Show help message |

## Examples

### Basic Build
```bash
./scripts/wsl_build_for_pod.sh
```
Binary will be at: `target/aarch64-unknown-linux-gnu/release/opensleep`

### Clean Release Build
```bash
./scripts/wsl_build_for_pod.sh --clean
```

### Build and Upload
```bash
./scripts/wsl_build_for_pod.sh --upload --pod-ip 192.168.2.52
```

### Build Specific Branch
```bash
./scripts/wsl_build_for_pod.sh --branch issue_6 --upload --pod-ip 192.168.2.52
```

### Debug Build (Faster)
```bash
./scripts/wsl_build_for_pod.sh --debug
```

### Custom SSH Port/User
```bash
./scripts/wsl_build_for_pod.sh --upload --pod-ip 192.168.2.52 --pod-port 8822 --pod-user rewt
```

## What the Script Does

### Build Phase
1. ✅ Checks for Rust installation
2. ✅ Verifies ARM64 target is installed
3. ✅ Checks for ARM64 cross-compiler
4. ✅ Configures Cargo for cross-compilation
5. ✅ Builds opensleep for ARM64
6. ✅ Verifies binary architecture

### Upload Phase (if `--upload` specified)
1. ✅ Tests SSH connection to Pod
2. ✅ Creates backup of current binary
3. ✅ Stops opensleep service
4. ✅ Uploads new binary
5. ✅ Installs with correct permissions
6. ✅ Starts service
7. ✅ Verifies service is running
8. ✅ Auto-rollback on failure

## Build Times

- **First build:** 5-15 minutes
- **Incremental builds:** 30-60 seconds
- **Clean builds:** 3-10 minutes

## Troubleshooting

### "Rust not found"
```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env
```

### "ARM64 cross-compiler not found"
```bash
sudo apt update
sudo apt install -y gcc-aarch64-linux-gnu
```

### "Cannot connect to Pod via SSH"
- Check Pod IP address is correct
- Verify Pod is on the network
- Test manually: `ssh -p 8822 rewt@192.168.2.52`

### "Build failed"
- Try clean build: `./scripts/wsl_build_for_pod.sh --clean`
- Check you have all dependencies:
  ```bash
  sudo apt install -y build-essential pkg-config libudev-dev
  ```

### "Service failed to start"
View logs on Pod:
```bash
ssh -p 8822 rewt@192.168.2.52 'sudo journalctl -u opensleep -n 50'
```

## Manual Deployment

If you prefer to manually deploy:

1. **Build:**
   ```bash
   ./scripts/wsl_build_for_pod.sh
   ```

2. **Copy binary:**
   ```bash
   scp -P 8822 target/aarch64-unknown-linux-gnu/release/opensleep rewt@192.168.2.52:/tmp/
   ```

3. **On Pod:**
   ```bash
   sudo systemctl stop opensleep
   sudo mv /tmp/opensleep /opt/opensleep/opensleep
   sudo chmod +x /opt/opensleep/opensleep
   sudo systemctl start opensleep
   ```

## Running from PowerShell

You can also run the script directly from PowerShell:

```powershell
wsl ./scripts/wsl_build_for_pod.sh --upload --pod-ip 192.168.2.52
```

## Benefits Over Pod Native Building

✅ **Faster:** Modern CPU vs embedded ARM processor  
✅ **Reliable:** Full development toolchain available  
✅ **Standard:** This is how embedded development is done  
✅ **Flexible:** Easy to switch between branches  
✅ **Safe:** Automatic backups and rollback  

## Related Documentation

- [WSL Build Guide](../docs/guides/wsl_build_guide.md) - Detailed WSL setup
- [Pod Native Build Guide](../docs/guides/pod_native_build_guide.md) - Why native building didn't work
- [SETUP.md](../SETUP.md) - Pod setup and deployment

## Tips

- **First build is slow:** Subsequent builds are much faster due to incremental compilation
- **Use `--debug` for testing:** Debug builds compile faster but run slower
- **Keep the workspace on Windows:** WSL can access Windows files at `/mnt/f/`
- **Set up SSH keys:** Avoid password prompts with SSH key authentication
