#!/usr/bin/env python3
"""Receive and print iPhone FPV HUD head-tracking UDP intent packets."""

from __future__ import annotations

import argparse
import json
import socket
import time
from typing import Any


DEFAULT_PORT = 5602
STALE_WARNING_SECONDS = 0.300


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Listen for FPV HUD head-tracking UDP JSON packets."
    )
    parser.add_argument("--host", default="0.0.0.0", help="Bind address")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help="UDP port to listen on")
    return parser.parse_args()


def field(packet: dict[str, Any], key: str, default: Any = "--") -> Any:
    value = packet.get(key, default)
    return default if value is None else value


def format_number(value: Any, width: int = 6, precision: int = 1) -> str:
    try:
        return f"{float(value):{width}.{precision}f}"
    except (TypeError, ValueError):
        return f"{value!s:>{width}}"


def main() -> int:
    args = parse_args()
    if not 1 <= args.port <= 65535:
        raise SystemExit("--port must be in 1...65535")

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind((args.host, args.port))
    sock.settimeout(0.05)

    packet_count = 0
    window_count = 0
    last_packet_time: float | None = None
    last_rate_time = time.monotonic()
    warned_stopped = False

    print(f"listening for head-tracking UDP on {args.host}:{args.port}")
    print("no hardware is controlled by this script")

    try:
        while True:
            now = time.monotonic()
            try:
                data, addr = sock.recvfrom(4096)
            except socket.timeout:
                if (
                    last_packet_time is not None
                    and not warned_stopped
                    and now - last_packet_time > STALE_WARNING_SECONDS
                ):
                    print(f"WARNING: no packets for >{int(STALE_WARNING_SECONDS * 1000)} ms")
                    warned_stopped = True
                if now - last_rate_time >= 1.0:
                    print(f"rate={window_count}/s")
                    window_count = 0
                    last_rate_time = now
                continue

            receive_ms = int(time.time() * 1000)
            last_packet_time = time.monotonic()
            warned_stopped = False
            packet_count += 1
            window_count += 1

            try:
                packet = json.loads(data.decode("utf-8"))
            except UnicodeDecodeError as exc:
                print(f"{addr} bad utf-8: {exc}")
                continue
            except json.JSONDecodeError as exc:
                print(f"{addr} bad json: {exc}")
                continue

            timestamp_ms = packet.get("timestamp_ms")
            try:
                age_ms = receive_ms - int(timestamp_ms)
            except (TypeError, ValueError):
                age_ms = None

            age_label = "--" if age_ms is None else f"{age_ms:4d}ms"
            centered = field(packet, "centered")
            print(
                f"#{packet_count:05d} from {addr[0]}:{addr[1]} "
                f"seq={field(packet, 'seq'):>6} age={age_label:>6} "
                f"yaw={format_number(field(packet, 'yaw_deg'))} "
                f"pitch={format_number(field(packet, 'pitch_deg'))} "
                f"roll={format_number(field(packet, 'roll_deg'))} "
                f"enabled={field(packet, 'tracking_enabled')} "
                f"centered={centered}"
            )

            now = time.monotonic()
            if now - last_rate_time >= 1.0:
                print(f"rate={window_count}/s")
                window_count = 0
                last_rate_time = now

    except KeyboardInterrupt:
        print("\nstopped by user")
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
