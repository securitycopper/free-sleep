#!/bin/bash

# Detect which Python to use
if [ -x "/opt/python3.12/bin/python3.12" ]; then
    echo "Using Python 3.12 from /opt/python3.12 (built for GLIBC 2.33 compatibility)"
    PYTHON_CMD="/opt/python3.12/bin/python3.12"
    PYTHON_BIN="/opt/python3.12/bin/python3.12"
    PIP_CMD="/opt/python3.12/bin/pip3.12"
elif [ -x "/opt/python3.11/bin/python3.11" ]; then
    echo "Using Python 3.11 from /opt/python3.11 (built for GLIBC 2.33 compatibility)"
    PYTHON_CMD="/opt/python3.11/bin/python3.11"
    PYTHON_BIN="/opt/python3.11/bin/python3.11"
    PIP_CMD="/opt/python3.11/bin/pip3.11"
else
    echo "Using system Python 3.9"
    PYTHON_CMD="python3"
    PYTHON_BIN="python3"
    PIP_CMD="pip3"
fi

$PYTHON_CMD /home/dac/free-sleep/scripts/is_biometrics_installed.py
result=$?

if [ $result -eq 0 ]; then
  echo "Biometrics environment not setup, continuing with installation..."
elif [ $result -eq 1 ]; then
  echo "Biometrics environment setup already, exiting!"
  exit 0
else
  echo "Unable to check if biometrics installed, exiting..."
  exit 1
fi


set -e  # Exit immediately if any command fails
set -o pipefail  # Catch errors in piped commands
set -u  # Treat unset variables as errors

RED='\033[0;31m'
NC='\033[0m' # No Color

# Catch any errors
trap '
  rc=$?;
  if [ "$rc" -ne 0 ]; then
    echo ""
    echo -e "${RED}Error enabling biometrics!${NC}"
    echo -e "${RED}Command that failed: $BASH_COMMAND - Exit code $rc ${NC}"
    echo ""
    curl -s -X POST http://127.0.0.1:3000/api/services \
      -H "Content-Type: application/json" \
      -d "{
        \"biometrics\": {
          \"jobs\": {
            \"installation\": {
              \"status\": \"failed\"
            }
          }
        }
      }"
  fi
  sh /home/dac/free-sleep/scripts/block_internet_access.sh
  exit $rc
' EXIT


sh /home/dac/free-sleep/scripts/unblock_internet_access.sh
sh /home/dac/free-sleep/scripts/setup_python.sh
sh /home/dac/free-sleep/scripts/install_python_packages.sh
sh /home/dac/free-sleep/scripts/setup_streamer_service.sh

# Mark the installation status as healthy
curl -X POST http://127.0.0.1:3000/api/services \
  -H "Content-Type: application/json" \
  -d '{
    "biometrics": {
      "jobs": {
        "installation": {
          "status": "healthy"
        }
      }
    }
  }'

sh /home/dac/free-sleep/scripts/block_internet_access.sh
cd /home/dac/free-sleep/biometrics/sleep_detection && /home/dac/venv/bin/python calibrate_sensor_thresholds.py

