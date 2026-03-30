# Biometrics Installation GLIBC Compatibility Issue

## Summary
Biometrics installation fails on Pod 3 devices due to a GLIBC version mismatch between the downloaded Python 3.9.9 binaries and the system's C library. The Python modules require GLIBC 2.38, but Pod 3 runs an older version.

## Environment
- **Device**: Eight Sleep Pod 3 (SD card variant)
- **Architecture**: ARM64 (aarch64)
- **System**: Custom embedded Linux (based on commit `556615a62a1d1100e5e63dac99560add14689cc5`)
- **FreeSleep Version**: 2.0.5
- **Python Version Attempted**: 3.9.9 (from CPython GitHub releases)

## Problem Description

### What Fails
The biometrics installation script (`/home/dac/free-sleep/scripts/enable_biometrics.sh`) attempts to:
1. Download CPython 3.9.9 source from GitHub
2. Copy Python library files to `/usr/lib64/python3.9/`
3. Create a Python virtual environment at `/home/dac/venv/`
4. Install pip using `python3 -m ensurepip`
5. Install required packages: `numpy scipy pandas cbor2 watchdog sentry-sdk`

### Where It Breaks
**Step 4 fails** with the following error:

```
ImportError: /lib/libc.so.6: version `GLIBC_2.38' not found 
(required by /usr/lib/python3.9/pyexpat.cpython-39-aarch64-linux-gnu.so)
```

This occurs when Python tries to import compiled extension modules (specifically `pyexpat`, used by `xml.parsers.expat`).

### Root Cause
The CPython 3.9.9 binaries downloaded from the official repository are **pre-compiled** and linked against **GLIBC 2.38**. The Pod 3 system has an **older GLIBC version** (likely 2.28-2.33 based on the embedded Linux distribution).

When Python tries to load compiled extension modules (`.so` files), the dynamic linker cannot find the required GLIBC 2.38 symbols, causing the import to fail.

## Technical Details

### Error Stack Trace
```
File "/usr/lib/python3.9/xml/parsers/expat.py", line 4, in <module>
    from pyexpat import *
ImportError: /lib/libc.so.6: version `GLIBC_2.38' not found 
(required by /usr/lib/python3.9/pyexpat.cpython-39-aarch64-linux-gnu.so)
```

### Affected Components
All compiled Python extension modules fail to import:
- `pyexpat` (XML parsing - used by pip, ensurepip)
- `numpy` (numerical computing)
- `scipy` (scientific computing)
- Any package with C extensions

### Current Script Behavior
Location: `/home/dac/free-sleep/scripts/setup_python.sh`

The script:
1. Downloads: `https://github.com/python/cpython/archive/refs/tags/v3.9.9.zip`
2. Extracts to: `/home/dac/python-modules/cpython-3.9.9/`
3. Copies `.py`, `.so`, and other files to `/usr/lib64/python3.9/`

**The problem**: The `.so` files (compiled extension modules) are built for a different GLIBC version than what's on the Pod.

## Impact

### What Doesn't Work
- ✅ Python interpreter runs fine (pure Python code works)
- ❌ Virtual environment creation fails at `ensurepip` step
- ❌ Cannot install pip (requires XML parsing for package metadata)
- ❌ Cannot install any biometrics dependencies (numpy, scipy, heartpy, etc.)
- ❌ Biometrics features completely unavailable:
  - Heart rate monitoring
  - HRV (Heart Rate Variability) analysis
  - Sleep stage detection (REM, deep, light)
  - Respiratory rate calculation
  - Cap sensor threshold calibration

### What Still Works
- ✅ Core FreeSleep functionality (temperature control, scheduling, web UI)
- ✅ Frank service (hardware communication)
- ✅ All non-biometrics features

## Attempted Workarounds

### 1. Manual pip installation
```bash
curl https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py
/home/dac/venv/bin/python3 /tmp/get-pip.py
```
**Result**: Same GLIBC 2.38 error when pip tries to import `xml.parsers.expat`

### 2. Using system Python packages
Not attempted yet - would require different approach in setup script.

### 3. Pre-compiled wheels for older GLIBC
Not attempted - would need to find or build compatible ARM64 wheels.

## Recommended Solutions

### Option 1: Use System Python (Preferred)
**If Python 3.9+ is already installed on the Pod:**
- Skip the CPython download entirely
- Use the system's Python installation which is already compiled against the correct GLIBC
- Modify `setup_python.sh` to detect and use existing Python
- Install packages using system pip or from compatible wheel repositories

**Pros**: 
- No GLIBC compatibility issues
- Faster installation (no download/copy needed)
- Guaranteed to work with system libraries

**Cons**: 
- Depends on system having Python 3.9+ installed
- Less control over Python version

### Option 2: Build Python from Source on Device
Compile Python 3.9.9 directly on the Pod targeting the correct GLIBC:
```bash
wget https://www.python.org/ftp/python/3.9.9/Python-3.9.9.tgz
tar xzf Python-3.9.9.tgz
cd Python-3.9.9
./configure --prefix=/opt/python3.9 --enable-optimizations
make -j$(nproc)
make install
```

**Pros**: 
- Compiled against correct GLIBC version
- Full control over build options
- Guaranteed compatibility

**Cons**: 
- Requires build tools (gcc, make, etc.) on Pod
- Time-consuming (30-60 minutes on embedded hardware)
- Increases SD card image size if pre-built

### Option 3: Use Older Python Binaries
Download pre-compiled Python binaries built against GLIBC 2.28 or 2.29 (common in older embedded systems):
- Check system GLIBC version: `ldd --version` or `ls -l /lib/libc.so.6`
- Download compatible Python build from Python.org or build server
- Sources: deadsnakes PPA, python.org official builds, or custom builds

**Pros**: 
- Similar to current approach
- No build time required

**Cons**: 
- Need to identify exact GLIBC version on Pod
- May require custom build infrastructure
- Hard to maintain across different Pod versions

### Option 4: Use Docker/Container
Run biometrics processing in a lightweight container with compatible libraries:
```bash
docker run --rm -v /deviceinfo:/deviceinfo python:3.9-slim \
  python /home/dac/free-sleep/biometrics/stream/stream.py
```

**Pros**: 
- Complete isolation from system GLIBC
- Easy to update/maintain
- Portable across devices

**Cons**: 
- Requires Docker on embedded device
- Additional memory/storage overhead
- Complexity in service management

### Option 5: Use Conda/Mamba
Use Conda miniforge (ARM64 builds available) which bundles its own GLIBC:
```bash
wget https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-aarch64.sh
bash Miniforge3-Linux-aarch64.sh -b -p /opt/miniforge3
/opt/miniforge3/bin/conda create -n biometrics python=3.9 numpy scipy pandas
```

**Pros**: 
- Bundles compatible libraries
- Well-maintained ARM64 builds
- Easy package management

**Cons**: 
- Large download (~500MB+)
- Higher storage requirements
- Overkill for single-purpose use

## Testing Required

To implement a fix, we need to know:

1. **Exact system GLIBC version**:
   ```bash
   ldd --version
   # OR
   /lib/libc.so.6
   ```

2. **Available system Python**:
   ```bash
   which python3
   python3 --version
   python3 -c "import sys; print(sys.executable)"
   ```

3. **Build tools availability**:
   ```bash
   which gcc make
   gcc --version
   ```

4. **Storage constraints**:
   ```bash
   df -h /
   ```

## Current Workaround

For users who need biometrics NOW:
- Manually build Python from source on the device
- Or accept that biometrics won't work until this is resolved
- Core temperature control features work perfectly

## Files Affected

- `/home/dac/free-sleep/scripts/setup_python.sh` - Downloads and copies Python files
- `/home/dac/free-sleep/scripts/install_python_packages.sh` - Attempts pip install
- `/home/dac/free-sleep/scripts/enable_biometrics.sh` - Main orchestration script
- `/etc/systemd/system/free-sleep-stream.service` - Service that runs biometrics (created but fails to start)

## Deployment Status

**Current deployment (192.168.2.52)**:
- FreeSleep 2.0.5: ✅ Running perfectly
- Core features: ✅ All working
- Biometrics: ❌ Failed installation (GLIBC issue)
- System: ✅ Production ready for non-biometrics use

---

## Request

Could you please advise on the best approach to resolve this? Would you prefer:
1. Detecting and using system Python if available?
2. Building Python from source as part of installation?
3. Providing pre-built Python binaries compatible with Pod 3's GLIBC?
4. A different approach?

Happy to test any solution on my deployment Pod (192.168.2.52).
