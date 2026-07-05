#!/usr/bin/env python3
"""Send fake iPhone head-tracking UDP packets for Windows bridge testing.

This script only emits camera-look intent JSON. It does not connect to, command,
or control vehicle hardware.
"""

from __future__ import annotations

import argparse
import json
import math
import random
import socket
import time
from typing import Any


DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 5602
DEFAULT_RATE_HZ = 30.0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Send fake iPhone head-tracking packets to a Windows bridge UDP port."
    )
    parser.add_argument("--host", default=DEFAULT_HOST, help="Bridge host/IP")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help="Bridge UDP port")
    parser.add_argument("--rate", type=float, default=DEFAULT_RATE_HZ, help="Packet rate in Hz")
    parser.add_argument("--duration", type=float, default=0.0, help="Seconds to run. 0 means Ctrl-C.")
    parser.add_argument(
        "--pattern",
        choices=("static", "sine", "sweep", "noisy"),
        default="sine",
        help="Motion pattern to generate.",
    )
    parser.add_argument(
        "--disable-after",
        type=float,
        default=None,
        help="After N seconds, continue sending with tracking_enabled=false.",
    )
    parser.add_argument(
        "--uncentered",
        action="store_true",
        help="Send centered=false for every packet.",
    )
    parser.add_argument(
        "--malformed",
        action="store_true",
        help="Send one malformed UDP payload and exit.",
    )
    parser.add_argument(
        "--malformed-every",
        type=int,
        default=0,
        help="Send malformed JSON every N packets; 0 disables.",
    )
    return parser.parse_args()


def validate_args(args: argparse.Namespace) -> None:
    if not args.host.strip():
        raise SystemExit("--host must not be empty")
    if not 1 <= args.port <= 65535:
        raise SystemExit("--port must be in 1...65535")
    if args.rate <= 0:
        raise SystemExit("--rate must be greater than 0")
    if args.duration < 0:
        raise SystemExit("--duration must be non-negative")
    if args.disable_after is not None and args.disable_after < 0:
        raise SystemExit("--disable-after must be non-negative")
    if args.malformed_every < 0:
        raise SystemExit("--malformed-every must be non-negative")


def values_for_pattern(pattern: str, elapsed: float) -> tuple[float, float, float]:
    if pattern == "static":
        return 12.0, -3.5, 1.5

    if pattern == "sweep":
        period = 6.0
        phase = (elapsed % period) / period
        triangle = 4.0 * abs(phase - 0.5) - 1.0
        return triangle * 45.0, math.sin(elapsed * 0.9) * 12.0, math.sin(elapsed * 0.7) * 8.0

    if pattern == "noisy":
        return (
            math.sin(elapsed * 0.8) * 24.0 + random.uniform(-3.0, 3.0),
            math.sin(elapsed * 0.55 + 0.4) * 9.0 + random.uniform(-1.2, 1.2),
            math.sin(elapsed * 0.7 + 1.1) * 6.0 + random.uniform(-1.0, 1.0),
        )

    return (
        math.sin(elapsed * 0.8) * 28.0,
        math.sin(elapsed * 0.55 + 0.4) * 10.0,
        math.sin(elapsed * 0.7 + 1.1) * 6.0,
    )


def make_packet(
    seq: int,
    yaw_deg: float,
    pitch_deg: float,
    roll_deg: float,
    tracking_enabled: bool,
    centered: bool,
) -> dict[str, Any]:
    return {
        "seq": seq,
        "timestamp_ms": int(time.time() * 1000),
        "yaw_deg": round(yaw_deg, 2),
        "pitch_deg": round(pitch_deg, 2),
        "roll_deg": round(roll_deg, 2),
        "tracking_enabled": tracking_enabled,
        "centered": centered,
    }


def malformed_payload(seq: int) -> bytes:
    return f'{{"seq": {seq}, "timestamp_ms": {int(time.time() * 1000)}, bad json'.encode(
        "utf-8"
    )


def main() -> int:
    args = parse_args()
    validate_args(args)

    destination = (args.host.strip(), args.port)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    if args.malformed:
        sock.sendto(malformed_payload(1), destination)
        print(f"sent one malformed head-tracking payload to {destination[0]}:{destination[1]}")
        return 0

    start_time = time.monotonic()
    next_send = start_time
    next_rate_print = start_time + 1.0
    interval = 1.0 / args.rate
    seq = 0
    window_count = 0
    last_packet: dict[str, Any] | None = None

    print(
        f"sending fake iPhone head tracking to {destination[0]}:{destination[1]} "
        f"at {args.rate:g} Hz pattern={args.pattern} centered={not args.uncentered}"
    )
    print("safety: JSON intent only; no vehicle hardware is controlled")

    try:
        while True:
            now = time.monotonic()
            elapsed = now - start_time
            if args.duration > 0 and elapsed >= args.duration:
                break

            if now < next_send:
                time.sleep(min(next_send - now, 0.02))
                continue

            seq += 1
            tracking_enabled = args.disable_after is None or elapsed < args.disable_after
            yaw_deg, pitch_deg, roll_deg = values_for_pattern(args.pattern, elapsed)
            last_packet = make_packet(
                seq=seq,
                yaw_deg=yaw_deg,
                pitch_deg=pitch_deg,
                roll_deg=roll_deg,
                tracking_enabled=tracking_enabled,
                centered=not args.uncentered,
            )
            if args.malformed_every > 0 and seq % args.malformed_every == 0:
                payload = malformed_payload(seq)
            else:
                payload = json.dumps(last_packet, separators=(",", ":")).encode("utf-8")
            sock.sendto(payload, destination)
            window_count += 1
            next_send += interval

            if now >= next_rate_print:
                print(
                    f"rate={window_count}/s seq={last_packet['seq']} "
                    f"yaw={last_packet['yaw_deg']:>6.2f} "
                    f"pitch={last_packet['pitch_deg']:>6.2f} "
                    f"roll={last_packet['roll_deg']:>6.2f} "
                    f"enabled={last_packet['tracking_enabled']} "
                    f"centered={last_packet['centered']}"
                )
                window_count = 0
                next_rate_print = now + 1.0

    except KeyboardInterrupt:
        print("\nstopped by user")
        return 0

    if last_packet is not None:
        print(
            f"finished after {seq} packets; last yaw={last_packet['yaw_deg']} "
            f"pitch={last_packet['pitch_deg']} roll={last_packet['roll_deg']} "
            f"enabled={last_packet['tracking_enabled']} centered={last_packet['centered']}"
        )
    else:
        print("finished without sending packets")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
