#!/usr/bin/env python3
"""Send synthetic RTP/H.265-like UDP packets to the APFPV diagnostic receiver.

This is diagnostics-only test traffic. It does not contain real video frames and
is not intended to be decoded.
"""

from __future__ import annotations

import argparse
import random
import socket
import struct
import time


DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 5600
DEFAULT_RATE_HZ = 60.0
DEFAULT_PAYLOAD_TYPE = 96
DEFAULT_SSRC = 0x46505648


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Send synthetic RTP-like H.265 packets to FPVHUD APFPV diagnostics."
    )
    parser.add_argument("--host", default=DEFAULT_HOST, help="Receiver host/IP")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help="Receiver UDP port")
    parser.add_argument("--rate", type=float, default=DEFAULT_RATE_HZ, help="Packet rate in Hz")
    parser.add_argument("--duration", type=float, default=0.0, help="Seconds to run. 0 means Ctrl-C.")
    parser.add_argument("--payload-type", type=int, default=DEFAULT_PAYLOAD_TYPE, help="RTP payload type")
    parser.add_argument("--ssrc", type=lambda value: int(value, 0), default=DEFAULT_SSRC, help="RTP SSRC")
    parser.add_argument(
        "--include-parameter-sets",
        action="store_true",
        help="Cycle VPS/SPS/PPS NAL units at startup.",
    )
    parser.add_argument(
        "--gap-every",
        type=int,
        default=0,
        help="Skip one RTP sequence number every N packets.",
    )
    parser.add_argument(
        "--out-of-order-every",
        type=int,
        default=0,
        help="Send an older sequence number every N packets.",
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
    if not 0 <= args.payload_type <= 127:
        raise SystemExit("--payload-type must be in 0...127")
    if not 0 <= args.ssrc <= 0xFFFFFFFF:
        raise SystemExit("--ssrc must fit in uint32")
    if args.gap_every < 0 or args.out_of_order_every < 0:
        raise SystemExit("--gap-every and --out-of-order-every must be non-negative")


def h265_nal_header(nal_type: int) -> bytes:
    return bytes([((nal_type & 0x3F) << 1), 0x01])


def synthetic_payload(seq: int, include_parameter_sets: bool) -> bytes:
    if include_parameter_sets and seq <= 3:
        nal_type = [32, 33, 34][seq - 1]
    else:
        nal_type = 1
    body = bytes(random.getrandbits(8) for _ in range(80))
    return h265_nal_header(nal_type) + body


def rtp_packet(
    payload_type: int,
    sequence_number: int,
    timestamp: int,
    ssrc: int,
    payload: bytes,
) -> bytes:
    return struct.pack(
        "!BBHII",
        0x80,
        payload_type & 0x7F,
        sequence_number & 0xFFFF,
        timestamp & 0xFFFFFFFF,
        ssrc & 0xFFFFFFFF,
    ) + payload


def main() -> int:
    args = parse_args()
    validate_args(args)

    destination = (args.host.strip(), args.port)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    start_time = time.monotonic()
    next_send = start_time
    next_rate_print = start_time + 1.0
    interval = 1.0 / args.rate
    packets_sent = 0
    window_count = 0
    sequence_number = 1
    timestamp = 0

    print(
        f"sending synthetic RTP/H.265-like packets to {destination[0]}:{destination[1]} "
        f"at {args.rate:g} Hz payload_type={args.payload_type}"
    )
    print("diagnostic payload only; no real video decode is expected")

    try:
        while True:
            now = time.monotonic()
            elapsed = now - start_time
            if args.duration > 0 and elapsed >= args.duration:
                break
            if now < next_send:
                time.sleep(min(next_send - now, 0.02))
                continue

            packets_sent += 1
            window_count += 1

            send_sequence = sequence_number
            if args.out_of_order_every > 0 and packets_sent % args.out_of_order_every == 0:
                send_sequence = (sequence_number - 3) & 0xFFFF

            payload = synthetic_payload(packets_sent, args.include_parameter_sets)
            sock.sendto(
                rtp_packet(args.payload_type, send_sequence, timestamp, args.ssrc, payload),
                destination,
            )

            sequence_number = (sequence_number + 1) & 0xFFFF
            if args.gap_every > 0 and packets_sent % args.gap_every == 0:
                sequence_number = (sequence_number + 1) & 0xFFFF
            timestamp = (timestamp + 3000) & 0xFFFFFFFF
            next_send += interval

            if now >= next_rate_print:
                print(
                    f"rate={window_count}/s sent={packets_sent} "
                    f"seq={send_sequence} timestamp={timestamp}"
                )
                window_count = 0
                next_rate_print = now + 1.0

    except KeyboardInterrupt:
        print("\nstopped by user")
        return 0

    print(f"finished after {packets_sent} packets")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
