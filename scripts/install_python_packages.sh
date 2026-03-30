#!/bin/bash

# Detect which Python to use
if [ -x "/opt/python3.12/bin/python3.12" ]; then
    echo "Using Python 3.12 from /opt/python3.12 (built for GLIBC 2.33 compatibility)"
    PYTHON_CMD="/opt/python3.12/bin/python3.12"
    VENV_PATH="/home/dac/venv"
    
    echo "Creating new python venv with Python 3.12..."
    $PYTHON_CMD -m venv $VENV_PATH
    
    echo "Activating python venv..."
    source $VENV_PATH/bin/activate
    
    echo "Installing packages..."
    set -x
    $VENV_PATH/bin/python -m pip install numpy scipy pandas cbor2 watchdog "sentry-sdk"
    set +x
    
    echo "Python 3.12 venv setup complete!"
    exit 0
elif [ -x "/opt/python3.11/bin/python3.11" ]; then
    echo "Using Python 3.11 from /opt/python3.11 (built for GLIBC 2.33 compatibility)"
    PYTHON_CMD="/opt/python3.11/bin/python3.11"
    VENV_PATH="/home/dac/venv"
    
    echo "Creating new python venv with Python 3.11..."
    $PYTHON_CMD -m venv $VENV_PATH
    
    echo "Activating python venv..."
    source $VENV_PATH/bin/activate
    
    echo "Installing packages..."
    set -x
    $VENV_PATH/bin/python -m pip install numpy scipy pandas cbor2 watchdog "sentry-sdk"
    set +x
    
    echo "Python 3.11 venv setup complete!"
    exit 0
fi

# Fallback to system Python 3.9 with patches
echo "Using system Python 3.9 (requires file patching)"
PYTHON_VERSION_DOT=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}{sys.version_info.minor}")')

if [ "$PYTHON_VERSION" = "39" ]; then
  echo "Detected python version 3.9"
  # Pod 3 with SD card has python version 3.9 & is missing venv
  cp -r /home/dac/free-sleep/scripts/python/$PYTHON_VERSION/venv /usr/lib/python$PYTHON_VERSION_DOT/
  cp /home/dac/free-sleep/scripts/python/plistlib.py /usr/lib/python$PYTHON_VERSION_DOT/
  cp /home/dac/free-sleep/scripts/python/pyexpat.cpython-$PYTHON_VERSION-aarch64-linux-gnu.so /usr/lib/python$PYTHON_VERSION_DOT/
  echo "Copied files for Pod 3 with SD card successfully."
elif [ "$PYTHON_VERSION" = "310" ]; then
  echo "Detected python version 3.10"
  cp /home/dac/free-sleep/scripts/python/plistlib.py /usr/lib64/python$PYTHON_VERSION_DOT/
  cp /home/dac/free-sleep/scripts/python/pyexpat.cpython-$PYTHON_VERSION-aarch64-linux-gnu.so /usr/lib64/python$PYTHON_VERSION_DOT/
  echo "Copied files successfully"
else
  echo -e "\033[33mWARNING: Detected python version $PYTHON_VERSION_DOT \033[0m"
  echo -e "\033[33mWARNING: Biometrics may or may not work!! \033[0m"
fi

echo "Creating new python venv..."
python3 -m venv /home/dac/venv

echo "Activating python venv..."
source /home/dac/venv/bin/activate

set -x
/home/dac/venv/bin/python -m pip install numpy scipy pandas cbor2 watchdog "sentry-sdk"
set +x
