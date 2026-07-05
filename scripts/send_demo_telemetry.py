#!/usr/bin/env python3
"""Send animated UDP JSON telemetry snapshots to the FPV HUD iPhone app."""

from __future__ import annotations

import argparse
import json
import math
import socket
import time
from typing import Any


DEFAULT_HOST = "192.168.1.50"
DEFAULT_PORT = 5601
DEFAULT_RATE_HZ = 20.0
DEFAULT_DROP_IDLE_SECONDS = 5.0


def clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def make_packet(start_time: float, sequence: int, profile: str) -> dict[str, Any]:
    elapsed = time.monotonic() - start_time
    noisy = profile == "noisy"
    stale_profile = profile == "stale"
    wave = math.sin(elapsed * 0.9)
    fast_wave = math.sin(elapsed * 2.2)
    steering_amplitude = 0.95 if noisy else 0.75
    steering = math.sin(elapsed * (1.9 if noisy else 1.4)) * steering_amplitude
    throttle = clamp((math.sin(elapsed * 0.7) + 1.0) * 0.5, 0.0, 1.0)
    brake = clamp((math.sin(elapsed * 0.45 + math.pi) - 0.55) * 1.8, 0.0, 1.0)
    speed_noise = fast_wave * (6.0 if noisy else 2.5)
    speed = max(0.0, 8.0 + throttle * 42.0 - brake * 18.0 + speed_noise)
    gear = max(1, min(5, int(speed // 12.0) + 1))
    ers = int(clamp(55.0 + math.sin(elapsed * 0.35) * 35.0, 0.0, 100.0))
    lq_center = 72.0 if noisy else 88.0
    lq_swing = 28.0 if noisy else 10.0
    lq = int(clamp(lq_center + math.sin(elapsed * 0.9) * lq_swing, 25.0, 100.0))
    rssi = int(round((-72.0 if noisy else -64.0) + math.sin(elapsed * 0.65) * (16.0 if noisy else 9.0)))
    snr = int(round((11.0 if noisy else 17.0) + math.sin(elapsed * 1.1) * (11.0 if noisy else 6.0)))
    battery = max(11.5, 16.2 - elapsed * 0.003 + wave * 0.05)
    video_lock = int(elapsed * (2 if noisy else 1)) % (7 if noisy else 23) != 0

    warning = ""
    if not video_lock:
        warning = "VIDEO LOCK DROPPED"
    elif lq < 65:
        warning = "LINK QUALITY LOW"
    elif battery < 12.0:
        warning = "BATTERY LOW"
    elif stale_profile:
        warning = "SIMULATED STALE SOURCE"

    packet: dict[str, Any] = {
        "timestamp_ms": int(time.time() * 1000),
        "battery_v": round(battery, 2),
        "link_quality": lq,
        "rssi_dbm": rssi,
        "snr_db": snr,
        "speed_kmh": round(speed, 1),
        "gear": gear,
        "drive_mode": "GEARBOX_ERS",
        "ers_percent": ers,
        "throttle": round(throttle, 3),
        "brake": round(brake, 3),
        "steering": round(steering, 3),
        "camera_yaw_deg": round(math.sin(elapsed * 0.45) * 22.0, 1),
        "camera_pitch_deg": round(math.sin(elapsed * 0.32) * 8.0, 1),
        "head_tracking_mode": "DS4",
        "video_lock": video_lock,
        "warning": warning,
        "test_sequence": sequence,
    }

    if stale_profile:
        packet["stale_data_warnings"] = ["speed", "flightMode"]

    return packet


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Send animated telemetry snapshots to the FPV HUD app over UDP."
    )
    parser.add_argument("--host", default=DEFAULT_HOST, help="iPhone IP address")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help="Telemetry UDP port")
    parser.add_argument("--rate", type=float, default=DEFAULT_RATE_HZ, help="Send rate in Hz")
    parser.add_argument(
        "--duration",
        type=float,
        default=0.0,
        help="Seconds to run; without --drop-after this is also the send duration. 0 means run until Ctrl-C.",
    )
    parser.add_argument(
        "--drop-after",
        type=float,
        default=None,
        help="Stop sending after N seconds but keep the process alive to test stale/lost HUD behavior.",
    )
    parser.add_argument(
        "--idle-after-stop",
        type=float,
        default=0.0,
        help="After --duration expires, stay alive without sending for this many seconds.",
    )
    parser.add_argument(
        "--profile",
        choices=("normal", "stale", "noisy"),
        default="normal",
        help="Telemetry profile to send.",
    )
    parser.add_argument(
        "--malformed",
        action="store_true",
        help="Send one malformed UDP payload and exit.",
    )
    parser.add_argument(
        "--malformed-once",
        action="store_true",
        help="Send one malformed UDP payload before normal telemetry.",
    )
    parser.add_argument(
        "--malformed-every",
        type=int,
        default=0,
        help="Send malformed JSON every N packets; 0 disables.",
    )
    parser.add_argument(
        "--malformed-only",
        action="store_true",
        help="Send malformed JSON continuously instead of telemetry.",
    )
    return parser.parse_args()


def malformed_payload(sequence: int) -> bytes:
    return f'{{"timestamp_ms": {int(time.time() * 1000)}, "seq": {sequence}, bad json'.encode(
        "utf-8"
    )


def main() -> int:
    args = parse_args()
    if not 1 <= args.port <= 65535:
        raise SystemExit("--port must be in 1...65535")
    if args.rate <= 0:
        raise SystemExit("--rate must be greater than 0")
    if args.duration < 0 or args.idle_after_stop < 0:
        raise SystemExit("--duration and --idle-after-stop must be non-negative")
    if args.drop_after is not None and args.drop_after < 0:
        raise SystemExit("--drop-after must be non-negative")

    interval = 1.0 / args.rate
    destination = (args.host.strip(), args.port)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    start_time = time.monotonic()
    next_send = start_time
    sequence = 0
    total_duration = args.duration if args.duration > 0 else None
    send_until = args.drop_after if args.drop_after is not None else total_duration

    if args.drop_after is not None and total_duration is None:
        idle = args.idle_after_stop if args.idle_after_stop > 0 else DEFAULT_DROP_IDLE_SECONDS
        total_duration = args.drop_after + idle

    if args.drop_after is not None and total_duration is not None and total_duration < args.drop_after:
        raise SystemExit("--duration must be greater than or equal to --drop-after")

    print(
        f"sending telemetry to {destination[0]}:{destination[1]} at {args.rate:g} Hz, "
        f"profile={args.profile} "
        f"({'until Ctrl-C' if total_duration is None else f'for {total_duration:g}s'})"
    )

    if args.malformed:
        sock.sendto(malformed_payload(sequence), destination)
        print("sent one malformed payload")
        return 0

    if args.malformed_once:
        sock.sendto(malformed_payload(sequence), destination)
        print("sent one malformed payload")

    drop_announced = False

    try:
        while True:
            now = time.monotonic()
            elapsed = now - start_time
            if total_duration is not None and elapsed >= total_duration:
                break

            if send_until is not None and elapsed >= send_until:
                if not drop_announced:
                    print(f"stopped sending at {elapsed:.2f}s; process remains alive for stale/lost testing")
                    drop_announced = True
                time.sleep(0.05)
                continue

            sleep_for = next_send - now
            if sleep_for > 0:
                time.sleep(min(sleep_for, 0.05))
                continue

            sequence += 1
            should_malformed = args.malformed_only or (
                args.malformed_every > 0 and sequence % args.malformed_every == 0
            )
            if should_malformed:
                payload = malformed_payload(sequence)
            else:
                payload = json.dumps(
                    make_packet(start_time, sequence, args.profile),
                    separators=(",", ":"),
                ).encode("utf-8")

            sock.sendto(payload, destination)
            if sequence == 1 or sequence % max(1, int(args.rate)) == 0:
                label = "malformed" if should_malformed else "telemetry"
                print(f"sent {sequence} packets, last={label}")
            next_send += interval

    except KeyboardInterrupt:
        print("\nstopped by user")
        return 0

    print(f"finished after {sequence} packets")
    if args.drop_after is None and args.idle_after_stop > 0:
        print(f"idling for {args.idle_after_stop:g}s so the app can show stale/lost telemetry")
        time.sleep(args.idle_after_stop)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
