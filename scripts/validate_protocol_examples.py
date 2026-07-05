#!/usr/bin/env python3
"""Validate protocol example JSON files against the checked-in schemas.

This is a small dependency-free validator for the JSON Schema subset used by
this repo. It is not a general-purpose JSON Schema implementation.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import math
import time
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
EXAMPLE_CHECKS = (
    (
        REPO_ROOT / "schemas" / "telemetry_snapshot.schema.json",
        REPO_ROOT / "examples" / "telemetry_snapshot.example.json",
    ),
    (
        REPO_ROOT / "schemas" / "head_tracking_packet.schema.json",
        REPO_ROOT / "examples" / "head_tracking_packet.example.json",
    ),
)
VALID_FIXTURE_CHECKS = (
    (
        REPO_ROOT / "schemas" / "telemetry_snapshot.schema.json",
        REPO_ROOT / "tests" / "fixtures" / "telemetry_fresh.json",
    ),
    (
        REPO_ROOT / "schemas" / "telemetry_snapshot.schema.json",
        REPO_ROOT / "tests" / "fixtures" / "telemetry_stale_like.json",
    ),
    (
        REPO_ROOT / "schemas" / "head_tracking_packet.schema.json",
        REPO_ROOT / "tests" / "fixtures" / "head_tracking_ready.json",
    ),
    (
        REPO_ROOT / "schemas" / "head_tracking_packet.schema.json",
        REPO_ROOT / "tests" / "fixtures" / "head_tracking_active.json",
    ),
    (
        REPO_ROOT / "schemas" / "head_tracking_packet.schema.json",
        REPO_ROOT / "tests" / "fixtures" / "head_tracking_uncentered.json",
    ),
)
JSON_PARSE_ONLY_FIXTURES = (
    REPO_ROOT / "tests" / "fixtures" / "telemetry_minimal.json",
)
MALFORMED_FIXTURES = (
    REPO_ROOT / "tests" / "fixtures" / "telemetry_malformed.json",
    REPO_ROOT / "tests" / "fixtures" / "head_tracking_malformed.json",
)


class ValidationError(ValueError):
    pass


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def type_matches(value: Any, expected: str) -> bool:
    if expected == "object":
        return isinstance(value, dict)
    if expected == "array":
        return isinstance(value, list)
    if expected == "string":
        return isinstance(value, str)
    if expected == "integer":
        return isinstance(value, int) and not isinstance(value, bool)
    if expected == "number":
        return (
            isinstance(value, (int, float))
            and not isinstance(value, bool)
            and math.isfinite(float(value))
        )
    if expected == "boolean":
        return isinstance(value, bool)
    if expected == "null":
        return value is None
    raise ValidationError(f"unsupported schema type {expected!r}")


def validate_type(value: Any, schema: dict[str, Any], path: str) -> None:
    expected = schema.get("type")
    if expected is None:
        return
    options = expected if isinstance(expected, list) else [expected]
    if not any(type_matches(value, option) for option in options):
        joined = " or ".join(options)
        raise ValidationError(f"{path}: expected {joined}, got {type(value).__name__}")


def validate_number_bounds(value: Any, schema: dict[str, Any], path: str) -> None:
    if not isinstance(value, (int, float)) or isinstance(value, bool):
        return
    if "minimum" in schema and value < schema["minimum"]:
        raise ValidationError(f"{path}: {value!r} is below minimum {schema['minimum']!r}")
    if "maximum" in schema and value > schema["maximum"]:
        raise ValidationError(f"{path}: {value!r} is above maximum {schema['maximum']!r}")


def validate_enum(value: Any, schema: dict[str, Any], path: str) -> None:
    if "const" in schema and value != schema["const"]:
        raise ValidationError(f"{path}: expected const {schema['const']!r}, got {value!r}")
    if "enum" in schema and value not in schema["enum"]:
        raise ValidationError(f"{path}: {value!r} is not one of {schema['enum']!r}")


def validate_value(value: Any, schema: dict[str, Any], path: str = "$") -> None:
    validate_type(value, schema, path)
    validate_enum(value, schema, path)
    validate_number_bounds(value, schema, path)

    if isinstance(value, dict):
        for key in schema.get("required", []):
            if key not in value:
                raise ValidationError(f"{path}: missing required property {key!r}")
        properties = schema.get("properties", {})
        for key, child_value in value.items():
            child_schema = properties.get(key)
            if child_schema is not None:
                validate_value(child_value, child_schema, f"{path}.{key}")
            elif schema.get("additionalProperties") is False:
                raise ValidationError(f"{path}: unexpected property {key!r}")

    if isinstance(value, list):
        item_schema = schema.get("items")
        if item_schema is not None:
            for index, item in enumerate(value):
                validate_value(item, item_schema, f"{path}[{index}]")
        if schema.get("uniqueItems") and len(value) != len(set(json.dumps(item, sort_keys=True) for item in value)):
            raise ValidationError(f"{path}: array items must be unique")


def validate_pair(schema_path: Path, example_path: Path) -> None:
    schema = load_json(schema_path)
    example = load_json(example_path)
    validate_value(example, schema)
    print(f"ok {example_path.relative_to(REPO_ROOT)}")


def load_script_module(name: str) -> Any:
    path = REPO_ROOT / "scripts" / f"{name}.py"
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ValidationError(f"could not import {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def validate_generated_packets() -> None:
    telemetry_schema = load_json(REPO_ROOT / "schemas" / "telemetry_snapshot.schema.json")
    head_schema = load_json(REPO_ROOT / "schemas" / "head_tracking_packet.schema.json")
    telemetry_sender = load_script_module("send_demo_telemetry")
    fake_head_sender = load_script_module("send_fake_head_tracking")

    telemetry_packet = telemetry_sender.make_packet(time.monotonic(), 1, "normal")
    validate_value(telemetry_packet, telemetry_schema)
    print("ok scripts/send_demo_telemetry.py generated packet")

    head_packet = fake_head_sender.make_packet(
        seq=1,
        yaw_deg=-12.5,
        pitch_deg=6.8,
        roll_deg=1.2,
        tracking_enabled=True,
        centered=True,
    )
    validate_value(head_packet, head_schema)
    print("ok scripts/send_fake_head_tracking.py generated packet")


def validate_parse_only_fixtures() -> None:
    for path in JSON_PARSE_ONLY_FIXTURES:
        load_json(path)
        print(f"ok {path.relative_to(REPO_ROOT)}")


def validate_malformed_fixtures() -> None:
    for path in MALFORMED_FIXTURES:
        try:
            load_json(path)
        except json.JSONDecodeError:
            print(f"ok {path.relative_to(REPO_ROOT)} rejected")
            continue
        raise ValidationError(f"{path.relative_to(REPO_ROOT)} should be malformed")


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate FPV HUD protocol examples.")
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="Only print failures.",
    )
    args = parser.parse_args()

    for schema_path, example_path in EXAMPLE_CHECKS:
        validate_pair(schema_path, example_path)

    for schema_path, example_path in VALID_FIXTURE_CHECKS:
        validate_pair(schema_path, example_path)

    validate_parse_only_fixtures()
    validate_malformed_fixtures()
    validate_generated_packets()

    if not args.quiet:
        print("protocol examples validated")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
