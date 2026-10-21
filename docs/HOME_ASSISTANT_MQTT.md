# Home Assistant Integration (MQTT)

This repository now includes a lightweight MQTT bridge so Home Assistant can:

- Turn each side on/off independently
- Set each side target temperature (°F)
- Read current and target temperatures from both sides

The bridge talks to FreeSleep through the existing REST API (`/api/deviceStatus`) and exposes MQTT topics for Home Assistant.

## 1) Prerequisites

- A running MQTT broker (Mosquitto is fine)
- Home Assistant with MQTT integration enabled
- Pod already running FreeSleep (`http://<POD_IP>:3000`)

## 2) Install the bridge on the pod

```bash
sudo sh /home/dac/free-sleep/scripts/install_home_assistant_mqtt_bridge.sh
```

This installs:

- [home_assistant_mqtt_bridge.py](../scripts/home_assistant_mqtt_bridge.py)
- [free-sleep-ha-mqtt-bridge.service](../scripts/free-sleep-ha-mqtt-bridge.service)
- `/persistent/free-sleep-data/ha-mqtt-bridge.env` (from template)

## 3) Configure broker settings

Edit:

```bash
sudo nano /persistent/free-sleep-data/ha-mqtt-bridge.env
```

Template source in repo:
[home_assistant_mqtt_bridge.env.example](../scripts/home_assistant_mqtt_bridge.env.example)

Minimum values to set:

- `MQTT_HOST`
- `MQTT_PORT`
- `MQTT_USERNAME` / `MQTT_PASSWORD` (if your broker requires auth)

Then restart:

```bash
sudo systemctl restart free-sleep-ha-mqtt-bridge.service
```

## 4) Verify

```bash
systemctl status free-sleep-ha-mqtt-bridge.service --no-pager
journalctl -u free-sleep-ha-mqtt-bridge -n 100 --no-pager
```

## MQTT topics

Default base topic is `freesleep/pod`.

Commands:

- `freesleep/pod/left/power/set` payload: `ON` / `OFF`
- `freesleep/pod/right/power/set` payload: `ON` / `OFF`
- `freesleep/pod/left/target_temperature_f/set` payload: `55` to `110`
- `freesleep/pod/right/target_temperature_f/set` payload: `55` to `110`

State:

- `freesleep/pod/left/power/state`
- `freesleep/pod/right/power/state`
- `freesleep/pod/left/current_temperature_f/state`
- `freesleep/pod/right/current_temperature_f/state`
- `freesleep/pod/left/target_temperature_f/state`
- `freesleep/pod/right/target_temperature_f/state`
- `freesleep/pod/availability` (`online` / `offline`)

## Home Assistant discovery

By default `HA_DISCOVERY_ENABLED=true`, so entities auto-appear in Home Assistant through MQTT discovery.

If you prefer manual entities, set `HA_DISCOVERY_ENABLED=false` and map the command/state topics directly.

