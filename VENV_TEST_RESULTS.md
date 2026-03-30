Manual testing:
:~$ python3 -m venv /home/dac/venv
Error: [Errno 13] Permission denied: '/home/dac/venv/pyvenv.cfg'

:~$ sudo su
:/home/rewt# python3 -m venv /home/dac/venv
Error: Command '['/home/dac/venv/bin/python3', '-Im', 'ensurepip', '--upgrade', '--default-pip']' returned non-zero exit status 1.

:/home/rewt# sh python3 -m venv /home/dac/venv
/usr/bin/python3: /usr/bin/python3: cannot execute binary file


Claude Sonnet 4.5 testing report of the same command.


# Test Results for `python3 -m venv /home/dac/venv`

## Date: November 15, 2025
## Device: Pod 3 Deployment Server (192.168.2.52)
## FreeSleep Version: 2.0.5

---

## Test 1: Standard venv creation (with pip)

**Command:**
```bash
sudo python3 -m venv /home/dac/venv
```

**Result:** ❌ **FAILED**

**Error:**
```
Error: Command '['/home/dac/venv/bin/python3', '-Im', 'ensurepip', '--upgrade', '--default-pip']' returned non-zero exit status 1.
```

**Analysis:**
The venv creation starts successfully but fails during the `ensurepip` step when it tries to bootstrap pip. This is the same GLIBC 2.38 error we've been encountering.

---

## Test 2: venv creation without pip

**Command:**
```bash
sudo python3 -m venv --without-pip /home/dac/venv
```

**Result:** ✅ **SUCCESS**

**Output:**
```
venv created successfully (without pip)
total 24
drwxr-xr-x  5 root root 4096 Nov 15 12:46 .
drwxr-xr-x 10 dac  dac  4096 Nov 15 12:46 ..
drwxr-xr-x  2 root root 4096 Nov 15 12:46 bin
drwxr-xr-x  2 root root 4096 Nov 15 12:46 include
drwxr-xr-x  3 root root 4096 Nov 15 12:46 lib
lrwxrwxrwx  1 root root    3 Nov 15 12:46 lib64 -> lib
-rw-r--r--  1 root root   69 Nov 15 12:46 pyvenv.cfg
```

**Python Version in venv:**
```bash
/home/dac/venv/bin/python3 --version
# Output: Python 3.9.9
```

**Analysis:**
The virtual environment structure is created successfully. The venv Python binary is a symlink to the system Python 3.9.9.

---

## Test 3: GLIBC error confirmation

**Command:**
```bash
/home/dac/venv/bin/python3 -c 'from pyexpat import *'
```

**Result:** ❌ **FAILED with GLIBC error**

**Error:**
```
Traceback (most recent call last):
  File "<string>", line 1, in <module>
ImportError: /lib/libc.so.6: version `GLIBC_2.38' not found (required by /usr/lib/python3.9/pyexpat.cpython-39-aarch64-linux-gnu.so)
```

**Analysis:**
Even though the venv is created, attempting to import any compiled extension module (like `pyexpat`) fails with the GLIBC version mismatch error. This confirms that the system Python 3.9.9 installation has the same issue - its compiled extension modules were built against GLIBC 2.38.

---

## System Python Information

**Python Location:**
```bash
which python3
# Output: /usr/bin/python3
```

**Python Version:**
```bash
python3 --version
# Output: Python 3.9.9
```

**Full Version String:**
```python
import sys; print(sys.version)
# Output: 3.9.9 (main, Nov 15 2021, 18:05:17) [GCC 11.2.0]
```

**Binary Information:**
```bash
file /usr/bin/python3
# Output: /usr/bin/python3: symbolic link to python3.9
```

**Build Date:** November 15, 2021
**Compiler:** GCC 11.2.0

---

## Conclusion

The system already has Python 3.9.9 installed, but it was **compiled/built with GCC 11.2.0** which uses **GLIBC 2.38**. This means:

1. ✅ The Python interpreter itself runs fine
2. ✅ Pure Python code works
3. ✅ Virtual environment structure can be created (without pip)
4. ❌ Any compiled C extension modules fail to import (GLIBC 2.38 not available)
5. ❌ Cannot use pip/ensurepip (requires xml.parsers.expat which uses pyexpat.so)
6. ❌ Cannot install packages with C extensions (numpy, scipy, etc.)

**The Root Issue:** The system Python 3.9.9 installation itself has compiled extension modules built against GLIBC 2.38, but the Pod's system GLIBC is older (likely 2.28-2.33). This is the same issue we were encountering with the downloaded CPython binaries - the system Python has the exact same problem.

---

## Implications

**Using system Python won't solve the problem** because:
- The system Python's `.so` files (in `/usr/lib/python3.9/`) are already compiled against GLIBC 2.38
- This is the same incompatibility issue we had before

**We need one of these solutions:**

1. **Rebuild Python from source** on the device targeting the correct GLIBC version
2. **Find/create Python binaries** compatible with the Pod's GLIBC version
3. **Use a container** with its own GLIBC
4. **Use Conda/Miniforge** which bundles compatible libraries

The system Python cannot be used as-is without addressing the GLIBC mismatch.

---

## Additional Testing Requested

To help determine the best path forward, please let me know if you'd like me to test:

1. Checking the actual system GLIBC version
2. Checking if build tools (gcc, make) are available
3. Testing if pip can be installed via get-pip.py bootstrap (it will likely fail the same way)
4. Any other diagnostic commands
