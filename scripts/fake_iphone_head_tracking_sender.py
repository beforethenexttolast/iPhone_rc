#!/usr/bin/env python3
"""Send fake iPhone head-tracking UDP JSON packets to the bridge harness."""

from __future__ import annotations

import argparse
import json
import math
import socket
import time


DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 5602
DEFAULT_RATE_HZ = 30.0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Send fake iPhone head-tracking packets for ground-station bridge tests."
    )
    parser.add_argument("--host", default=DEFAULT_HOST, help="Bridge host/IP")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help="Bridge head UDP port")
    parser.add_argument("--rate", type=float, default=DEFAULT_RATE_HZ, help="Send rate in Hz")
    parser.add_argument("--duration", type=float, default=0.0, help="Seconds to run. 0 means Ctrl-C.")
    parser.add_argument(
        "--not-centered",
        action="store_true",
        help="Send centered=false to verify log-only safety handling.",
    )
    parser.add_argument(
        "--disabled",
        action="store_true",
        help="Send tracking_enabled=false packets.",
    )
    parser.add_argument(
        "--malformed",
        action="store_true",
        help="Send one malformed payload and exit.",
    )
    parser.add_argument(
        "--malformed-every",
        type=int,
        default=0,
        help="Send malformed JSON every N packets; 0 disables.",
    )
    parser.add_argument(
        "--drop-after",
        type=float,
        default=None,
        help="Stop sending after N seconds but keep the process alive to test stale logging.",
    )
    parser.add_argument(
        "--idle-after-stop",
        type=float,
        default=1.0,
        help="Seconds to stay alive after --drop-after.",
    )
    return parser.parse_args()


def malformed_payload(seq: int) -> bytes:
    return f'{{"seq": {seq}, "timestamp_ms": {int(time.time() * 1000)}, bad json'.encode("utf-8")


def make_packet(start_time: float, seq: int, tracking_enabled: bool, centered: bool) -> dict[str, object]:
    elapsed = time.monotonic() - start_time
    return {
        "seq": seq,
        "timestamp_ms": int(time.time() * 1000),
        "yaw_deg": round(math.sin(elapsed * 0.8) * 28.0, 2),
        "pitch_deg": round(math.sin(elapsed * 0.55 + 0.4) * 10.0, 2),
        "roll_deg": round(math.sin(elapsed * 0.7 + 1.1) * 6.0, 2),
        "tracking_enabled": tracking_enabled,
        "centered": centered,
    }


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

    destination = (args.host.strip(), args.port)
    if not destination[0]:
        raise SystemExit("--host must not be empty")

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    if args.malformed:
        sock.sendto(malformed_payload(1), destination)
        print(f"sent one malformed head-tracking payload to {destination[0]}:{destination[1]}")
        return 0

    start_time = time.monotonic()
    next_send = start_time
    interval = 1.0 / args.rate
    seq = 0
    send_until = args.drop_after if args.drop_after is not None else args.duration
    total_duration = args.duration
    if args.drop_after is not None:
        total_duration = max(args.drop_after + args.idle_after_stop, args.duration)

    print(
        f"sending fake iPhone head tracking to {destination[0]}:{destination[1]} "
        f"at {args.rate:g} Hz enabled={not args.disabled} centered={not args.not_centered}"
    )

    try:
        while True:
            now = time.monotonic()
            elapsed = now - start_time
            if total_duration > 0 and elapsed >= total_duration:
                break

            if send_until is not None and send_until > 0 and elapsed >= send_until:
                time.sleep(0.05)
                continue

            if now < next_send:
                time.sleep(min(next_send - now, 0.05))
                continue

            seq += 1
            if args.malformed_every > 0 and seq % args.malformed_every == 0:
                payload = malformed_payload(seq)
            else:
                payload = json.dumps(
                    make_packet(
                        start_time,
                        seq,
                        tracking_enabled=not args.disabled,
                        centered=not args.not_centered,
                    ),
                    separators=(",", ":"),
                ).encode("utf-8")

            sock.sendto(payload, destination)
            if seq == 1 or seq % max(1, int(args.rate)) == 0:
                print(f"sent {seq} fake head packets")
            next_send += interval

    except KeyboardInterrupt:
        print("\nstopped by user")
        return 0

    print(f"finished after {seq} packets")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
