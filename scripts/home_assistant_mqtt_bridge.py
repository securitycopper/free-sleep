#!/usr/bin/env python3
import json
import os
import sys
import time
from dataclasses import dataclass
from datetime import datetime
from typing import Any, Dict, Optional
from urllib import error, request

try:
    import paho.mqtt.client as mqtt
except ModuleNotFoundError:
    print(
        "ERROR: Missing dependency 'paho-mqtt'. "
        "Install it with: python3 -m pip install --user paho-mqtt",
        file=sys.stderr,
    )
    sys.exit(1)


TRUE_VALUES = {"1", "true", "on", "yes"}
FALSE_VALUES = {"0", "false", "off", "no"}


def log(message: str) -> None:
    timestamp = datetime.now().isoformat(timespec="seconds")
    print(f"[{timestamp}] {message}", flush=True)


@dataclass(frozen=True)
class BridgeConfig:
    mqtt_host: str
    mqtt_port: int
    mqtt_username: str
    mqtt_password: str
    mqtt_client_id: str
    mqtt_base_topic: str
    mqtt_discovery_prefix: str
    ha_discovery_enabled: bool
    poll_interval_seconds: int
    free_sleep_base_url: str
    http_timeout_seconds: int

    @staticmethod
    def _bool_from_env(value: str) -> bool:
        normalized = value.strip().lower()
        if normalized in TRUE_VALUES:
            return True
        if normalized in FALSE_VALUES:
            return False
        raise ValueError(f"Invalid boolean value: {value}")

    @classmethod
    def from_env(cls) -> "BridgeConfig":
        mqtt_port = int(os.getenv("MQTT_PORT", "1883"))
        poll_interval_seconds = int(os.getenv("POLL_INTERVAL_SECONDS", "15"))
        http_timeout_seconds = int(os.getenv("HTTP_TIMEOUT_SECONDS", "8"))
        if poll_interval_seconds < 5:
            raise ValueError("POLL_INTERVAL_SECONDS must be >= 5")
        if http_timeout_seconds < 1:
            raise ValueError("HTTP_TIMEOUT_SECONDS must be >= 1")

        discovery_value = os.getenv("HA_DISCOVERY_ENABLED", "true")
        ha_discovery_enabled = cls._bool_from_env(discovery_value)

        return cls(
            mqtt_host=os.getenv("MQTT_HOST", "127.0.0.1"),
            mqtt_port=mqtt_port,
            mqtt_username=os.getenv("MQTT_USERNAME", "").strip(),
            mqtt_password=os.getenv("MQTT_PASSWORD", "").strip(),
            mqtt_client_id=os.getenv("MQTT_CLIENT_ID", "free-sleep-ha-bridge"),
            mqtt_base_topic=os.getenv("MQTT_BASE_TOPIC", "freesleep/pod").strip("/"),
            mqtt_discovery_prefix=os.getenv("MQTT_DISCOVERY_PREFIX", "homeassistant").strip("/"),
            ha_discovery_enabled=ha_discovery_enabled,
            poll_interval_seconds=poll_interval_seconds,
            free_sleep_base_url=os.getenv("FREE_SLEEP_BASE_URL", "http://127.0.0.1:3000/api").rstrip("/"),
            http_timeout_seconds=http_timeout_seconds,
        )


class FreeSleepApi:
    def __init__(self, base_url: str, timeout_seconds: int) -> None:
        self.base_url = base_url.rstrip("/")
        self.timeout_seconds = timeout_seconds

    def _request_json(
        self,
        path: str,
        method: str = "GET",
        body: Optional[Dict[str, Any]] = None,
    ) -> Optional[Dict[str, Any]]:
        url = f"{self.base_url}{path}"
        headers = {"Accept": "application/json"}
        data = None
        if body is not None:
            headers["Content-Type"] = "application/json"
            data = json.dumps(body).encode("utf-8")

        req = request.Request(url, data=data, headers=headers, method=method)
        try:
            with request.urlopen(req, timeout=self.timeout_seconds) as response:
                raw = response.read()
                if not raw:
                    return None
                return json.loads(raw.decode("utf-8"))
        except error.HTTPError as exc:
            error_body = exc.read().decode("utf-8", errors="replace")
            raise RuntimeError(f"HTTP {exc.code} calling {method} {url}: {error_body}") from exc
        except error.URLError as exc:
            raise RuntimeError(f"Network error calling {method} {url}: {exc}") from exc
        except json.JSONDecodeError as exc:
            raise RuntimeError(f"Invalid JSON response from {method} {url}") from exc

    def get_device_status(self) -> Dict[str, Any]:
        response = self._request_json("/deviceStatus", method="GET")
        if response is None:
            raise RuntimeError("Device status response was empty")
        return response

    def set_side_power(self, side: str, is_on: bool) -> None:
        self._request_json("/deviceStatus", method="POST", body={side: {"isOn": is_on}})

    def set_side_target_temp_f(self, side: str, target_temp_f: int) -> None:
        self._request_json("/deviceStatus", method="POST", body={side: {"targetTemperatureF": target_temp_f}})


class HomeAssistantMqttBridge:
    def __init__(self, config: BridgeConfig, api: FreeSleepApi) -> None:
        self.config = config
        self.api = api
        self.client = mqtt.Client(client_id=config.mqtt_client_id, clean_session=True)

        if config.mqtt_username:
            self.client.username_pw_set(config.mqtt_username, config.mqtt_password)

        self.command_topics = {
            "left_power": self._topic("left/power/set"),
            "right_power": self._topic("right/power/set"),
            "left_target_temp_f": self._topic("left/target_temperature_f/set"),
            "right_target_temp_f": self._topic("right/target_temperature_f/set"),
        }
        self.state_topics = {
            "left_power": self._topic("left/power/state"),
            "right_power": self._topic("right/power/state"),
            "left_current_temp_f": self._topic("left/current_temperature_f/state"),
            "right_current_temp_f": self._topic("right/current_temperature_f/state"),
            "left_target_temp_f": self._topic("left/target_temperature_f/state"),
            "right_target_temp_f": self._topic("right/target_temperature_f/state"),
        }
        self.availability_topic = self._topic("availability")
        self.device_identifier = self.config.mqtt_base_topic.replace("/", "_")

        self.client.will_set(self.availability_topic, payload="offline", retain=True)
        self.client.on_connect = self.on_connect
        self.client.on_message = self.on_message

    def _topic(self, suffix: str) -> str:
        return f"{self.config.mqtt_base_topic}/{suffix}"

    def _publish(self, topic: str, payload: str, retain: bool = True) -> None:
        result = self.client.publish(topic, payload=payload, qos=1, retain=retain)
        if result.rc != mqtt.MQTT_ERR_SUCCESS:
            raise RuntimeError(f"Failed publishing to topic {topic}, rc={result.rc}")

    def _parse_bool(self, value: str) -> bool:
        normalized = value.strip().lower()
        if normalized in TRUE_VALUES:
            return True
        if normalized in FALSE_VALUES:
            return False
        raise ValueError(f"Invalid boolean payload '{value}'")

    def _parse_temp(self, value: str) -> int:
        parsed_value = int(round(float(value.strip())))
        if parsed_value < 55 or parsed_value > 110:
            raise ValueError("target temperature must be between 55 and 110 Fahrenheit")
        return parsed_value

    def _publish_discovery(self) -> None:
        if not self.config.ha_discovery_enabled:
            return

        device_payload = {
            "identifiers": [self.device_identifier],
            "name": "FreeSleep Pod",
            "manufacturer": "FreeSleep",
            "model": "8 Sleep Pod",
        }

        entities = [
            (
                "switch",
                "left_power",
                {
                    "name": "FreeSleep Left Power",
                    "command_topic": self.command_topics["left_power"],
                    "state_topic": self.state_topics["left_power"],
                    "payload_on": "ON",
                    "payload_off": "OFF",
                    "state_on": "ON",
                    "state_off": "OFF",
                    "availability_topic": self.availability_topic,
                    "device": device_payload,
                    "unique_id": f"{self.device_identifier}_left_power",
                },
            ),
            (
                "switch",
                "right_power",
                {
                    "name": "FreeSleep Right Power",
                    "command_topic": self.command_topics["right_power"],
                    "state_topic": self.state_topics["right_power"],
                    "payload_on": "ON",
                    "payload_off": "OFF",
                    "state_on": "ON",
                    "state_off": "OFF",
                    "availability_topic": self.availability_topic,
                    "device": device_payload,
                    "unique_id": f"{self.device_identifier}_right_power",
                },
            ),
            (
                "number",
                "left_target_temp_f",
                {
                    "name": "FreeSleep Left Target Temp",
                    "command_topic": self.command_topics["left_target_temp_f"],
                    "state_topic": self.state_topics["left_target_temp_f"],
                    "availability_topic": self.availability_topic,
                    "device": device_payload,
                    "min": 55,
                    "max": 110,
                    "step": 1,
                    "mode": "box",
                    "unit_of_measurement": "°F",
                    "unique_id": f"{self.device_identifier}_left_target_temp_f",
                },
            ),
            (
                "number",
                "right_target_temp_f",
                {
                    "name": "FreeSleep Right Target Temp",
                    "command_topic": self.command_topics["right_target_temp_f"],
                    "state_topic": self.state_topics["right_target_temp_f"],
                    "availability_topic": self.availability_topic,
                    "device": device_payload,
                    "min": 55,
                    "max": 110,
                    "step": 1,
                    "mode": "box",
                    "unit_of_measurement": "°F",
                    "unique_id": f"{self.device_identifier}_right_target_temp_f",
                },
            ),
            (
                "sensor",
                "left_current_temp_f",
                {
                    "name": "FreeSleep Left Current Temp",
                    "state_topic": self.state_topics["left_current_temp_f"],
                    "availability_topic": self.availability_topic,
                    "device": device_payload,
                    "unit_of_measurement": "°F",
                    "state_class": "measurement",
                    "unique_id": f"{self.device_identifier}_left_current_temp_f",
                },
            ),
            (
                "sensor",
                "right_current_temp_f",
                {
                    "name": "FreeSleep Right Current Temp",
                    "state_topic": self.state_topics["right_current_temp_f"],
                    "availability_topic": self.availability_topic,
                    "device": device_payload,
                    "unit_of_measurement": "°F",
                    "state_class": "measurement",
                    "unique_id": f"{self.device_identifier}_right_current_temp_f",
                },
            ),
        ]

        for component, key, payload in entities:
            config_topic = (
                f"{self.config.mqtt_discovery_prefix}/"
                f"{component}/{self.device_identifier}/{key}/config"
            )
            self._publish(config_topic, json.dumps(payload), retain=True)

        log("Published Home Assistant MQTT discovery entities.")

    def publish_state_once(self) -> None:
        status = self.api.get_device_status()
        left = status["left"]
        right = status["right"]

        self._publish(self.state_topics["left_power"], "ON" if left["isOn"] else "OFF")
        self._publish(self.state_topics["right_power"], "ON" if right["isOn"] else "OFF")
        self._publish(self.state_topics["left_current_temp_f"], str(left["currentTemperatureF"]))
        self._publish(self.state_topics["right_current_temp_f"], str(right["currentTemperatureF"]))
        self._publish(self.state_topics["left_target_temp_f"], str(left["targetTemperatureF"]))
        self._publish(self.state_topics["right_target_temp_f"], str(right["targetTemperatureF"]))
        self._publish(self.availability_topic, "online")

    def on_connect(self, client: mqtt.Client, _userdata: Any, _flags: Any, rc: int, _properties: Any = None) -> None:
        if rc != 0:
            log(f"MQTT connection failed with rc={rc}")
            return

        for topic in self.command_topics.values():
            client.subscribe(topic, qos=1)
            log(f"Subscribed to {topic}")

        self._publish_discovery()
        self._publish(self.availability_topic, "online")
        try:
            self.publish_state_once()
        except RuntimeError as exc:
            log(f"Failed to publish initial state after MQTT connect: {exc}")

    def on_message(self, _client: mqtt.Client, _userdata: Any, msg: mqtt.MQTTMessage) -> None:
        topic = msg.topic
        payload = msg.payload.decode("utf-8").strip()
        if not payload:
            log(f"Ignoring empty payload on topic {topic}")
            return

        try:
            if topic == self.command_topics["left_power"]:
                self.api.set_side_power("left", self._parse_bool(payload))
            elif topic == self.command_topics["right_power"]:
                self.api.set_side_power("right", self._parse_bool(payload))
            elif topic == self.command_topics["left_target_temp_f"]:
                self.api.set_side_target_temp_f("left", self._parse_temp(payload))
            elif topic == self.command_topics["right_target_temp_f"]:
                self.api.set_side_target_temp_f("right", self._parse_temp(payload))
            else:
                log(f"Ignoring message on unknown topic {topic}")
                return
        except (ValueError, RuntimeError) as exc:
            log(f"Failed processing command topic {topic}: {exc}")
            return

        log(f"Applied command from topic {topic} with payload '{payload}'")
        self.publish_state_once()


def main() -> int:
    try:
        config = BridgeConfig.from_env()
    except ValueError as exc:
        print(f"ERROR: Invalid bridge configuration: {exc}", file=sys.stderr)
        return 1

    api = FreeSleepApi(config.free_sleep_base_url, config.http_timeout_seconds)
    bridge = HomeAssistantMqttBridge(config, api)

    log(f"Connecting to MQTT broker at {config.mqtt_host}:{config.mqtt_port}...")
    try:
        bridge.client.connect(config.mqtt_host, config.mqtt_port, keepalive=30)
    except OSError as exc:
        print(f"ERROR: Could not connect to MQTT broker: {exc}", file=sys.stderr)
        return 1
    bridge.client.loop_start()

    try:
        while True:
            try:
                bridge.publish_state_once()
            except RuntimeError as exc:
                log(f"Failed to publish state: {exc}")
            time.sleep(config.poll_interval_seconds)
    except KeyboardInterrupt:
        log("Stopping bridge...")
    finally:
        try:
            bridge.client.publish(bridge.availability_topic, payload="offline", retain=True)
            bridge.client.disconnect()
        finally:
            bridge.client.loop_stop()

    return 0


if __name__ == "__main__":
    sys.exit(main())
