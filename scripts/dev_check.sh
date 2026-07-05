#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

echo "== Python syntax checks =="
python3 -c '
from pathlib import Path

for path in sorted(Path("scripts").glob("*.py")):
    source = path.read_text(encoding="utf-8")
    compile(source, str(path), "exec")
    print(f"ok {path}")
'

echo "== Protocol example validation =="
python3 scripts/validate_protocol_examples.py

echo "== Xcode tests =="
xcodebuild -project FPVHUDApp.xcodeproj \
  -scheme FPVHUDApp \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test
