#!/bin/bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: Run this script as root."
  exit 1
fi

SERVICE_SRC="/home/dac/free-sleep/scripts/free-sleep-ha-mqtt-bridge.service"
SERVICE_DEST="/etc/systemd/system/free-sleep-ha-mqtt-bridge.service"
ENV_TEMPLATE="/home/dac/free-sleep/scripts/home_assistant_mqtt_bridge.env.example"
ENV_DEST="/persistent/free-sleep-data/ha-mqtt-bridge.env"

if [ ! -f "$SERVICE_SRC" ]; then
  echo "ERROR: Missing service file at $SERVICE_SRC"
  exit 1
fi

if [ ! -f "$ENV_TEMPLATE" ]; then
  echo "ERROR: Missing env template at $ENV_TEMPLATE"
  exit 1
fi

if [ -x /home/dac/venv/bin/python ]; then
  echo "Installing paho-mqtt into /home/dac/venv..."
  sudo -u dac /home/dac/venv/bin/python -m pip install paho-mqtt
else
  echo "Installing paho-mqtt for dac user in system python..."
  sudo -u dac python3 -m pip install --user paho-mqtt
fi

install -m 644 "$SERVICE_SRC" "$SERVICE_DEST"

if [ ! -f "$ENV_DEST" ]; then
  install -m 640 -o dac -g dac "$ENV_TEMPLATE" "$ENV_DEST"
  echo "Created $ENV_DEST from template. Edit it with your MQTT broker details."
else
  echo "Using existing $ENV_DEST"
fi

systemctl daemon-reload
systemctl enable --now free-sleep-ha-mqtt-bridge.service
systemctl status free-sleep-ha-mqtt-bridge.service --no-pager

echo "Home Assistant MQTT bridge installed."
echo "Logs: journalctl -u free-sleep-ha-mqtt-bridge -f --no-pager"

