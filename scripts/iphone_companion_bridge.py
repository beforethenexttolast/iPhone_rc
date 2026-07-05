#!/usr/bin/env python3
"""Log-only iPhone companion bridge harness for the Windows ground station.

This script mirrors the first Windows integration milestone:
- forward normalized telemetry snapshots to the iPhone HUD over UDP
- receive iPhone head-tracking intent packets over UDP
- validate and log head-tracking state

It does not command hardware, CRSF channels, servos, or the car.
"""

from __future__ import annotations

import argparse
import json
import math
import socket
import time
from dataclasses import dataclass
from typing import Any


DEFAULT_IPHONE_HOST = "127.0.0.1"
DEFAULT_TELEMETRY_PORT = 5601
DEFAULT_HEAD_PORT = 5602
DEFAULT_TELEMETRY_RATE_HZ = 20.0
DEFAULT_HEAD_STALE_MS = 300


@dataclass(frozen=True)
class BridgeConfig:
    bridge_enabled: bool
    iphone_host: str
    telemetry_port: int
    head_bind_host: str
    head_port: int
    telemetry_rate_hz: float
    head_stale_ms: int
    duration: float
    demo_telemetry: bool


@dataclass
class HeadTrackingStats:
    total_packets: int = 0
    window_packets: int = 0
    valid_packets: int = 0
    invalid_packets: int = 0
    last_packet_time: float | None = None
    last_valid_packet_time: float | None = None
    last_valid_packet: dict[str, Any] | None = None
    last_rate_time: float = 0.0
    stale_announced: bool = False


def clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def require_bool(packet: dict[str, Any], key: str) -> bool:
    value = packet.get(key)
    if not isinstance(value, bool):
        raise ValueError(f"{key} must be boolean")
    return value


def optional_bool(packet: dict[str, Any], key: str) -> bool | None:
    if key not in packet or packet[key] is None:
        return None
    if not isinstance(packet[key], bool):
        raise ValueError(f"{key} must be boolean when present")
    return packet[key]


def require_int(packet: dict[str, Any], key: str) -> int:
    value = packet.get(key)
    if isinstance(value, bool) or not isinstance(value, int):
        raise ValueError(f"{key} must be integer")
    if value < 0:
        raise ValueError(f"{key} must be non-negative")
    return value


def require_finite_number(packet: dict[str, Any], key: str) -> float:
    value = packet.get(key)
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"{key} must be numeric")
    number = float(value)
    if not math.isfinite(number):
        raise ValueError(f"{key} must be finite")
    return number


def validate_head_tracking_packet(packet: Any) -> dict[str, Any]:
    if not isinstance(packet, dict):
        raise ValueError("packet must be a JSON object")

    seq = require_int(packet, "seq")
    timestamp_ms = require_int(packet, "timestamp_ms")
    yaw_deg = require_finite_number(packet, "yaw_deg")
    pitch_deg = require_finite_number(packet, "pitch_deg")
    roll_deg = require_finite_number(packet, "roll_deg")
    tracking_enabled = require_bool(packet, "tracking_enabled")
    centered = optional_bool(packet, "centered")

    if abs(yaw_deg) > 360 or abs(pitch_deg) > 180 or abs(roll_deg) > 180:
        raise ValueError("yaw/pitch/roll outside expected debug range")

    return {
        "seq": seq,
        "timestamp_ms": timestamp_ms,
        "yaw_deg": yaw_deg,
        "pitch_deg": pitch_deg,
        "roll_deg": roll_deg,
        "tracking_enabled": tracking_enabled,
        "centered": centered,
    }


def make_demo_telemetry(start_time: float, sequence: int) -> dict[str, Any]:
    elapsed = time.monotonic() - start_time
    throttle = clamp((math.sin(elapsed * 0.7) + 1.0) * 0.5, 0.0, 1.0)
    brake = clamp((math.sin(elapsed * 0.45 + math.pi) - 0.55) * 1.8, 0.0, 1.0)
    steering = math.sin(elapsed * 1.4) * 0.7
    speed = max(0.0, 6.0 + throttle * 38.0 - brake * 16.0 + math.sin(elapsed * 2.2) * 2.0)
    gear = max(1, min(5, int(speed // 12.0) + 1))
    ers = int(clamp(58.0 + math.sin(elapsed * 0.35) * 32.0, 0.0, 100.0))
    link_quality = int(clamp(88.0 + math.sin(elapsed * 0.9) * 10.0, 0.0, 100.0))
    video_lock = int(elapsed) % 23 != 0
    warning = "" if video_lock else "VIDEO LOCK DROPPED"

    return {
        "timestamp_ms": int(time.time() * 1000),
        "battery_v": round(max(11.5, 16.2 - elapsed * 0.003), 2),
        "link_quality": link_quality,
        "rssi_dbm": int(round(-64.0 + math.sin(elapsed * 0.65) * 9.0)),
        "snr_db": int(round(17.0 + math.sin(elapsed * 1.1) * 6.0)),
        "speed_kmh": round(speed, 1),
        "gear": gear,
        "drive_mode": "GEARBOX_ERS",
        "ers_percent": ers,
        "throttle": round(throttle, 3),
        "brake": round(brake, 3),
        "steering": round(steering, 3),
        "camera_yaw_deg": round(math.sin(elapsed * 0.45) * 22.0, 1),
        "camera_pitch_deg": round(math.sin(elapsed * 0.32) * 8.0, 1),
        "head_tracking_mode": "OFF",
        "video_lock": video_lock,
        "warning": warning,
        "test_sequence": sequence,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run a log-only iPhone companion bridge harness."
    )
    bridge_group = parser.add_mutually_exclusive_group()
    bridge_group.add_argument(
        "--bridge-enabled",
        dest="bridge_enabled",
        action="store_true",
        help="Run the log-only telemetry/head-tracking bridge.",
    )
    bridge_group.add_argument(
        "--bridge-disabled",
        dest="bridge_enabled",
        action="store_false",
        help="Validate config, print safety state, and exit without opening UDP sockets.",
    )
    parser.add_argument("--iphone-host", default=DEFAULT_IPHONE_HOST, help="iPhone or Simulator IP")
    parser.add_argument(
        "--telemetry-port",
        type=int,
        default=DEFAULT_TELEMETRY_PORT,
        help="iPhone telemetry UDP port",
    )
    parser.add_argument("--head-bind-host", default="0.0.0.0", help="Head-tracking bind address")
    parser.add_argument(
        "--head-port",
        type=int,
        default=DEFAULT_HEAD_PORT,
        help="UDP port for iPhone head-tracking input",
    )
    parser.add_argument(
        "--telemetry-rate",
        type=float,
        default=DEFAULT_TELEMETRY_RATE_HZ,
        help="Telemetry forwarding rate in Hz",
    )
    parser.add_argument(
        "--head-stale-ms",
        type=int,
        default=DEFAULT_HEAD_STALE_MS,
        help="Mark head-tracking stale if no packet arrives for this many milliseconds",
    )
    parser.add_argument(
        "--duration",
        type=float,
        default=0.0,
        help="Seconds to run. 0 means run until Ctrl-C.",
    )
    parser.add_argument(
        "--no-demo-telemetry",
        dest="demo_telemetry",
        action="store_false",
        help="Do not generate demo telemetry; only receive/log head tracking.",
    )
    parser.set_defaults(demo_telemetry=True)
    parser.set_defaults(bridge_enabled=True)
    return parser.parse_args()


def config_from_args(args: argparse.Namespace) -> BridgeConfig:
    iphone_host = args.iphone_host.strip()
    if not iphone_host:
        raise SystemExit("--iphone-host must not be empty")
    for name, value in (
        ("--telemetry-port", args.telemetry_port),
        ("--head-port", args.head_port),
    ):
        if not 1 <= value <= 65535:
            raise SystemExit(f"{name} must be in 1...65535")
    if args.telemetry_rate <= 0:
        raise SystemExit("--telemetry-rate must be greater than 0")
    if args.head_stale_ms <= 0:
        raise SystemExit("--head-stale-ms must be greater than 0")
    if args.duration < 0:
        raise SystemExit("--duration must be non-negative")

    return BridgeConfig(
        bridge_enabled=args.bridge_enabled,
        iphone_host=iphone_host,
        telemetry_port=args.telemetry_port,
        head_bind_host=args.head_bind_host,
        head_port=args.head_port,
        telemetry_rate_hz=args.telemetry_rate,
        head_stale_ms=args.head_stale_ms,
        duration=args.duration,
        demo_telemetry=args.demo_telemetry,
    )


def print_head_rate(stats: HeadTrackingStats, now: float, stale_seconds: float) -> None:
    if now - stats.last_rate_time < 1.0:
        return
    state = head_state(stats, now, stale_seconds)
    age_label = "--"
    yaw_label = "--"
    pitch_label = "--"
    roll_label = "--"
    enabled_label = "--"
    centered_label = "--"
    if stats.last_valid_packet is not None and stats.last_valid_packet_time is not None:
        age_label = f"{int((now - stats.last_valid_packet_time) * 1000)}ms"
        yaw_label = f"{stats.last_valid_packet['yaw_deg']:.2f}"
        pitch_label = f"{stats.last_valid_packet['pitch_deg']:.2f}"
        roll_label = f"{stats.last_valid_packet['roll_deg']:.2f}"
        enabled_label = str(stats.last_valid_packet["tracking_enabled"])
        centered_label = str(stats.last_valid_packet["centered"])
    print(
        "head_rx_rate="
        f"{stats.window_packets}/s valid={stats.valid_packets} invalid={stats.invalid_packets} "
        f"state={state} last_age={age_label} yaw={yaw_label} pitch={pitch_label} "
        f"roll={roll_label} enabled={enabled_label} centered={centered_label}"
    )
    stats.window_packets = 0
    stats.last_rate_time = now


def head_state(stats: HeadTrackingStats, now: float, stale_seconds: float = DEFAULT_HEAD_STALE_MS / 1000.0) -> str:
    if stats.last_valid_packet is None or stats.last_valid_packet_time is None:
        return "IDLE"
    if now - stats.last_valid_packet_time > stale_seconds:
        return "STALE"
    if not stats.last_valid_packet["tracking_enabled"]:
        return "INACTIVE"
    if stats.last_valid_packet["centered"] is not True:
        return "NOT_CENTERED"
    return "ACTIVE"


def receive_head_packet(sock: socket.socket, stats: HeadTrackingStats, stale_seconds: float) -> None:
    now = time.monotonic()
    try:
        data, addr = sock.recvfrom(4096)
    except socket.timeout:
        if (
            stats.last_valid_packet_time is not None
            and not stats.stale_announced
            and now - stats.last_valid_packet_time > stale_seconds
        ):
            print(f"HEAD TRACK STALE: no iPhone packet for >{int(stale_seconds * 1000)} ms")
            stats.stale_announced = True
        return

    stats.total_packets += 1
    stats.window_packets += 1
    stats.last_packet_time = now
    stats.stale_announced = False

    try:
        decoded = json.loads(data.decode("utf-8"))
        packet = validate_head_tracking_packet(decoded)
    except (UnicodeDecodeError, json.JSONDecodeError, ValueError) as exc:
        stats.invalid_packets += 1
        print(f"invalid iPhone head packet from {addr[0]}:{addr[1]}: {exc}")
        return

    stats.valid_packets += 1
    stats.last_valid_packet_time = now
    stats.last_valid_packet = packet
    receive_ms = int(time.time() * 1000)
    age_ms = receive_ms - packet["timestamp_ms"]
    centered = "--" if packet["centered"] is None else packet["centered"]
    print(
        f"iPhone head seq={packet['seq']:>6} age={age_ms:>5}ms "
        f"yaw={packet['yaw_deg']:>7.2f} pitch={packet['pitch_deg']:>7.2f} "
        f"roll={packet['roll_deg']:>7.2f} enabled={packet['tracking_enabled']} "
        f"centered={centered}"
    )


def maybe_send_telemetry(
    sock: socket.socket,
    destination: tuple[str, int],
    start_time: float,
    next_send: float,
    sequence: int,
    interval: float,
    enabled: bool,
) -> tuple[float, int]:
    if not enabled:
        return next_send, sequence

    now = time.monotonic()
    if now < next_send:
        return next_send, sequence

    sequence += 1
    packet = make_demo_telemetry(start_time, sequence)
    payload = json.dumps(packet, separators=(",", ":")).encode("utf-8")
    sock.sendto(payload, destination)
    if sequence == 1 or sequence % max(1, int(1 / interval)) == 0:
        print(
            f"forwarded telemetry #{sequence} to {destination[0]}:{destination[1]} "
            f"speed={packet['speed_kmh']}km/h lq={packet['link_quality']}%"
        )
    return next_send + interval, sequence


def main() -> int:
    config = config_from_args(parse_args())
    print("iPhone companion bridge harness: LOG-ONLY")
    print("safety: no CRSF mapping, no servo/gimbal/car commands, no joystick interference")
    print(f"bridge_enabled={config.bridge_enabled}")
    if not config.bridge_enabled:
        print("bridge disabled: no UDP sockets opened, no telemetry forwarded, no head input received")
        return 0

    telemetry_destination = (config.iphone_host, config.telemetry_port)
    telemetry_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    head_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    head_sock.bind((config.head_bind_host, config.head_port))
    head_sock.settimeout(0.02)

    stats = HeadTrackingStats(last_rate_time=time.monotonic())
    start_time = time.monotonic()
    next_telemetry_send = start_time
    telemetry_sequence = 0
    telemetry_interval = 1.0 / config.telemetry_rate_hz
    stale_seconds = config.head_stale_ms / 1000.0

    print(
        f"telemetry -> {telemetry_destination[0]}:{telemetry_destination[1]} "
        f"at {config.telemetry_rate_hz:g} Hz "
        f"({'demo' if config.demo_telemetry else 'disabled'})"
    )
    print(f"head-tracking <- {config.head_bind_host}:{config.head_port}")

    try:
        while True:
            now = time.monotonic()
            if config.duration > 0 and now - start_time >= config.duration:
                break

            next_telemetry_send, telemetry_sequence = maybe_send_telemetry(
                telemetry_sock,
                telemetry_destination,
                start_time,
                next_telemetry_send,
                telemetry_sequence,
                telemetry_interval,
                config.demo_telemetry,
            )
            receive_head_packet(head_sock, stats, stale_seconds)
            print_head_rate(stats, time.monotonic(), stale_seconds)

    except KeyboardInterrupt:
        print("\nstopped by user")
        return 0

    print("bridge harness finished")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
