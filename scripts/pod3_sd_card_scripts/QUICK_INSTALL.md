# One-Line Installer for opensleep Build Script

Use these one-liners to quickly install and run the build script on your Pod 3.

## Quick Install & Build

```bash
curl -sSL https://raw.githubusercontent.com/securitycopper/opensleep/main/scripts/full_patch_workflow_build_latest.sh | bash
```

## Download Script Only (for review)

```bash
curl -O https://raw.githubusercontent.com/securitycopper/opensleep/main/scripts/full_patch_workflow_build_latest.sh && chmod +x full_patch_workflow_build_latest.sh
```

## Install to /opt and Run

```bash
cd /opt && curl -sSL https://raw.githubusercontent.com/securitycopper/opensleep/main/scripts/full_patch_workflow_build_latest.sh -o full_patch_workflow_build_latest.sh && chmod +x full_patch_workflow_build_latest.sh && ./full_patch_workflow_build_latest.sh
```

## With Specific Options

### Install and build from specific branch
```bash
curl -sSL https://raw.githubusercontent.com/securitycopper/opensleep/main/scripts/full_patch_workflow_build_latest.sh | bash -s -- --branch issue_6
```

### Setup only (no build)
```bash
curl -sSL https://raw.githubusercontent.com/securitycopper/opensleep/main/scripts/full_patch_workflow_build_latest.sh | bash -s -- --skip-build
```

## Manual Process

If you prefer to review the script first:

```bash
# Download
curl -O https://raw.githubusercontent.com/securitycopper/opensleep/main/scripts/full_patch_workflow_build_latest.sh

# Review
cat full_patch_workflow_build_latest.sh

# Make executable
chmod +x full_patch_workflow_build_latest.sh

# Run
./full_patch_workflow_build_latest.sh
```

## Verification

After running, verify the installation:

```bash
# Check service status
systemctl status opensleep

# View logs
journalctl -u opensleep -n 20

# Check binary
/opt/opensleep/opensleep --version

# View build log
tail -50 /var/log/opensleep_build.log
```

## Notes

- The script is safe to run multiple times
- It will detect what's already installed
- First run takes 30-60 minutes (downloads and compiles everything)
- Subsequent runs are much faster (5-15 minutes)
- All operations are logged to `/var/log/opensleep_build.log`
