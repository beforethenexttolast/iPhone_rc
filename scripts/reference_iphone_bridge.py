#!/usr/bin/env python3
"""Standalone log-only reference bridge for iPhone FPV HUD integration tests.

This is a no-hardware test harness. It forwards normalized telemetry snapshots
to the iPhone/Simulator and logs iPhone head-tracking intent packets. It does
not command hardware, CRSF channels, servos, the gimbal, or the car.
"""

from __future__ import annotations

import argparse
import json
import math
import socket
import time
from dataclasses import dataclass
from typing import Any


PROTOCOL_VERSION = 1
DEFAULT_IPHONE_HOST = "127.0.0.1"
DEFAULT_TELEMETRY_PORT = 5601
DEFAULT_HEADTRACKING_PORT = 5602
DEFAULT_TELEMETRY_RATE_HZ = 20.0
HEADTRACKING_STALE_SECONDS = 0.3
LOST_PROFILE_SEND_SECONDS = 2.0


@dataclass(frozen=True)
class Config:
    iphone_host: str
    telemetry_port: int
    headtracking_bind_host: str
    headtracking_port: int
    telemetry_rate_hz: float
    profile: str
    duration: float


@dataclass
class HeadTrackingStats:
    total_packets: int = 0
    valid_packets: int = 0
    invalid_packets: int = 0
    window_packets: int = 0
    last_valid_packet: dict[str, Any] | None = None
    last_valid_monotonic: float | None = None
    last_rate_print: float = 0.0
    stale_announced: bool = False


def clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def require_int(packet: dict[str, Any], key: str) -> int:
    value = packet.get(key)
    if isinstance(value, bool) or not isinstance(value, int):
        raise ValueError(f"{key} must be integer")
    if value < 0:
        raise ValueError(f"{key} must be non-negative")
    return value


def require_bool(packet: dict[str, Any], key: str) -> bool:
    value = packet.get(key)
    if not isinstance(value, bool):
        raise ValueError(f"{key} must be boolean")
    return value


def require_number(packet: dict[str, Any], key: str) -> float:
    value = packet.get(key)
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"{key} must be numeric")
    number = float(value)
    if not math.isfinite(number):
        raise ValueError(f"{key} must be finite")
    return number


def optional_bool(packet: dict[str, Any], key: str) -> bool | None:
    if key not in packet or packet[key] is None:
        return None
    if not isinstance(packet[key], bool):
        raise ValueError(f"{key} must be boolean when present")
    return packet[key]


def validate_headtracking_packet(packet: Any) -> dict[str, Any]:
    if not isinstance(packet, dict):
        raise ValueError("packet must be a JSON object")

    if "protocol_version" in packet and packet["protocol_version"] is not None:
        version = require_int(packet, "protocol_version")
        if version != PROTOCOL_VERSION:
            raise ValueError("protocol_version must be 1 when present")
    else:
        version = None

    yaw_deg = require_number(packet, "yaw_deg")
    pitch_deg = require_number(packet, "pitch_deg")
    roll_deg = require_number(packet, "roll_deg")
    if abs(yaw_deg) > 360 or abs(pitch_deg) > 180 or abs(roll_deg) > 180:
        raise ValueError("yaw/pitch/roll outside expected debug range")

    timeout_ms = None
    if "timeout_ms" in packet and packet["timeout_ms"] is not None:
        timeout_ms = require_int(packet, "timeout_ms")
        if not 1 <= timeout_ms <= 5000:
            raise ValueError("timeout_ms must be in 1...5000")

    return {
        "protocol_version": version,
        "seq": require_int(packet, "seq"),
        "timestamp_ms": require_int(packet, "timestamp_ms"),
        "yaw_deg": yaw_deg,
        "pitch_deg": pitch_deg,
        "roll_deg": roll_deg,
        "tracking_enabled": require_bool(packet, "tracking_enabled"),
        "centered": optional_bool(packet, "centered"),
        "timeout_ms": timeout_ms,
    }


def telemetry_packet(start_time: float, sequence: int, profile: str) -> dict[str, Any]:
    elapsed = time.monotonic() - start_time
    noisy = profile == "noisy"
    speed_wave = math.sin(elapsed * (2.6 if noisy else 1.8))
    throttle = clamp((math.sin(elapsed * 0.7) + 1.0) * 0.5, 0.0, 1.0)
    brake = clamp((math.sin(elapsed * 0.45 + math.pi) - 0.55) * 1.8, 0.0, 1.0)
    steering = math.sin(elapsed * (2.1 if noisy else 1.35)) * (0.9 if noisy else 0.65)
    speed = max(0.0, 7.0 + throttle * 40.0 - brake * 16.0 + speed_wave * (5.0 if noisy else 2.0))
    link_quality = int(clamp((70.0 if noisy else 90.0) + math.sin(elapsed) * (25.0 if noisy else 8.0), 0, 100))
    rssi_dbm = int(round((-74.0 if noisy else -63.0) + math.sin(elapsed * 0.6) * (14.0 if noisy else 8.0)))
    snr_db = round((10.0 if noisy else 18.0) + math.sin(elapsed * 1.1) * (8.0 if noisy else 4.0), 1)
    video_lock = int(elapsed * (2 if noisy else 1)) % (6 if noisy else 19) != 0
    warning = ""
    if not video_lock:
        warning = "VIDEO LOCK DROPPED"
    elif link_quality < 60:
        warning = "LINK QUALITY LOW"

    return {
        "protocol_version": PROTOCOL_VERSION,
        "timestamp_ms": int(time.time() * 1000),
        "battery_v": round(max(11.5, 16.0 - elapsed * 0.002), 2),
        "link_quality": link_quality,
        "rssi_dbm": rssi_dbm,
        "snr_db": snr_db,
        "speed_kmh": round(speed, 1),
        "gear": max(1, min(5, int(speed // 12.0) + 1)),
        "drive_mode": "GEARBOX_ERS",
        "ers_percent": int(clamp(55.0 + math.sin(elapsed * 0.35) * 35.0, 0, 100)),
        "throttle": round(throttle, 3),
        "brake": round(brake, 3),
        "steering": round(steering, 3),
        "camera_yaw_deg": round(math.sin(elapsed * 0.45) * 20.0, 1),
        "camera_pitch_deg": round(math.sin(elapsed * 0.32) * 7.0, 1),
        "head_tracking_mode": "OFF",
        "video_lock": video_lock,
        "warning": warning,
        "test_sequence": sequence,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run a standalone log-only reference bridge for iPhone FPV HUD testing."
    )
    parser.add_argument("--iphone-host", default=DEFAULT_IPHONE_HOST, help="iPhone or Simulator IP")
    parser.add_argument("--telemetry-port", type=int, default=DEFAULT_TELEMETRY_PORT)
    parser.add_argument(
        "--headtracking-port",
        type=int,
        default=DEFAULT_HEADTRACKING_PORT,
        help="UDP port used to receive iPhone head-tracking packets.",
    )
    parser.add_argument(
        "--headtracking-bind-host",
        default="0.0.0.0",
        help="Local bind address for head-tracking input.",
    )
    parser.add_argument("--telemetry-rate", type=float, default=DEFAULT_TELEMETRY_RATE_HZ)
    parser.add_argument("--profile", choices=("normal", "noisy", "lost"), default="normal")
    parser.add_argument("--duration", type=float, default=0.0, help="Seconds to run. 0 means Ctrl-C.")
    return parser.parse_args()


def config_from_args(args: argparse.Namespace) -> Config:
    iphone_host = args.iphone_host.strip()
    if not iphone_host:
        raise SystemExit("--iphone-host must not be empty")
    if not 1 <= args.telemetry_port <= 65535:
        raise SystemExit("--telemetry-port must be in 1...65535")
    if not 1 <= args.headtracking_port <= 65535:
        raise SystemExit("--headtracking-port must be in 1...65535")
    if args.telemetry_rate <= 0:
        raise SystemExit("--telemetry-rate must be greater than 0")
    if args.duration < 0:
        raise SystemExit("--duration must be non-negative")

    return Config(
        iphone_host=iphone_host,
        telemetry_port=args.telemetry_port,
        headtracking_bind_host=args.headtracking_bind_host,
        headtracking_port=args.headtracking_port,
        telemetry_rate_hz=args.telemetry_rate,
        profile=args.profile,
        duration=args.duration,
    )


def head_state(stats: HeadTrackingStats, now: float) -> str:
    if stats.last_valid_packet is None or stats.last_valid_monotonic is None:
        return "IDLE"
    if now - stats.last_valid_monotonic > HEADTRACKING_STALE_SECONDS:
        return "STALE"
    if not stats.last_valid_packet["tracking_enabled"]:
        return "INACTIVE"
    if stats.last_valid_packet["centered"] is not True:
        return "NOT_CENTERED"
    return "ACTIVE"


def print_rate_line(stats: HeadTrackingStats, now: float) -> None:
    if now - stats.last_rate_print < 1.0:
        return

    age_label = "--"
    yaw = pitch = roll = "--"
    enabled = centered = "--"
    if stats.last_valid_packet is not None and stats.last_valid_monotonic is not None:
        age_label = f"{int((now - stats.last_valid_monotonic) * 1000)}ms"
        yaw = f"{stats.last_valid_packet['yaw_deg']:.2f}"
        pitch = f"{stats.last_valid_packet['pitch_deg']:.2f}"
        roll = f"{stats.last_valid_packet['roll_deg']:.2f}"
        enabled = str(stats.last_valid_packet["tracking_enabled"])
        centered = str(stats.last_valid_packet["centered"])

    print(
        f"head_rx_rate={stats.window_packets}/s state={head_state(stats, now)} "
        f"valid={stats.valid_packets} invalid={stats.invalid_packets} "
        f"last_age={age_label} yaw={yaw} pitch={pitch} roll={roll} "
        f"enabled={enabled} centered={centered}"
    )
    stats.window_packets = 0
    stats.last_rate_print = now


def receive_headtracking(sock: socket.socket, stats: HeadTrackingStats) -> None:
    now = time.monotonic()
    try:
        data, addr = sock.recvfrom(4096)
    except socket.timeout:
        if (
            stats.last_valid_monotonic is not None
            and not stats.stale_announced
            and now - stats.last_valid_monotonic > HEADTRACKING_STALE_SECONDS
        ):
            print("HEAD TRACK STALE: no valid packet for >300 ms")
            stats.stale_announced = True
        return

    stats.total_packets += 1
    stats.window_packets += 1
    try:
        decoded = json.loads(data.decode("utf-8"))
        packet = validate_headtracking_packet(decoded)
    except (UnicodeDecodeError, json.JSONDecodeError, ValueError) as exc:
        stats.invalid_packets += 1
        print(f"invalid head packet from {addr[0]}:{addr[1]}: {exc}")
        return

    stats.valid_packets += 1
    stats.last_valid_packet = packet
    stats.last_valid_monotonic = now
    stats.stale_announced = False
    receive_ms = int(time.time() * 1000)
    age_ms = receive_ms - packet["timestamp_ms"]
    centered = "--" if packet["centered"] is None else packet["centered"]
    print(
        f"head seq={packet['seq']:>6} age={age_ms:>5}ms "
        f"yaw={packet['yaw_deg']:>7.2f} pitch={packet['pitch_deg']:>7.2f} "
        f"roll={packet['roll_deg']:>7.2f} enabled={packet['tracking_enabled']} "
        f"centered={centered}"
    )


def maybe_send_telemetry(
    sock: socket.socket,
    destination: tuple[str, int],
    config: Config,
    start_time: float,
    next_send: float,
    sequence: int,
) -> tuple[float, int]:
    now = time.monotonic()
    elapsed = now - start_time
    if config.profile == "lost" and elapsed > LOST_PROFILE_SEND_SECONDS:
        return next_send, sequence
    if now < next_send:
        return next_send, sequence

    sequence += 1
    packet = telemetry_packet(start_time, sequence, config.profile)
    sock.sendto(json.dumps(packet, separators=(",", ":")).encode("utf-8"), destination)
    if sequence == 1 or sequence % max(1, int(config.telemetry_rate_hz)) == 0:
        print(
            f"telemetry #{sequence} -> {destination[0]}:{destination[1]} "
            f"profile={config.profile} speed={packet['speed_kmh']}km/h lq={packet['link_quality']}%"
        )
    return next_send + (1.0 / config.telemetry_rate_hz), sequence


def main() -> int:
    config = config_from_args(parse_args())
    telemetry_destination = (config.iphone_host, config.telemetry_port)
    telemetry_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    head_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    head_sock.bind((config.headtracking_bind_host, config.headtracking_port))
    head_sock.settimeout(0.02)

    stats = HeadTrackingStats(last_rate_print=time.monotonic())
    start_time = time.monotonic()
    next_telemetry = start_time
    telemetry_sequence = 0

    print("REFERENCE IPHONE BRIDGE: LOG-ONLY / NO HARDWARE CONTROL")
    print("safety: no CRSF mapping, no pan/tilt output, no vehicle commands")
    print(
        f"telemetry -> {telemetry_destination[0]}:{telemetry_destination[1]} "
        f"at {config.telemetry_rate_hz:g} Hz profile={config.profile}"
    )
    if config.profile == "lost":
        print(f"lost profile: telemetry stops after {LOST_PROFILE_SEND_SECONDS:g}s")
    print(f"head-tracking <- {config.headtracking_bind_host}:{config.headtracking_port}")

    try:
        while True:
            now = time.monotonic()
            if config.duration > 0 and now - start_time >= config.duration:
                break

            next_telemetry, telemetry_sequence = maybe_send_telemetry(
                telemetry_sock,
                telemetry_destination,
                config,
                start_time,
                next_telemetry,
                telemetry_sequence,
            )
            receive_headtracking(head_sock, stats)
            print_rate_line(stats, time.monotonic())

    except KeyboardInterrupt:
        print("\nstopped by user")
        return 0

    print("reference bridge finished")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
