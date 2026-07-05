#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

PROJECT="${FPVHUD_PROJECT:-FPVHUDApp.xcodeproj}"
SCHEME="${FPVHUD_SCHEME:-FPVHUDApp}"
DESTINATION="${FPVHUD_DESTINATION:-platform=iOS Simulator,name=iPhone 17}"

echo "== Validation target =="
echo "project: $PROJECT"
echo "scheme: $SCHEME"
echo "destination: $DESTINATION"

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

echo "== Xcode simulator build =="
xcodebuild -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  build

echo "== Xcode tests =="
xcodebuild -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  test
