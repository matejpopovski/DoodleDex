#!/usr/bin/env bash
# Runs a test target in a throwaway simulator. Usage: scripts/test-ios.sh [DoodleDexTests|DoodleDexUITests]
set -euo pipefail
cd "$(dirname "$0")/.."

target="${1:-DoodleDexTests}"
if [[ -z "${DOODLEDEX_SIM_UDID:-}" ]]; then
    exec scripts/with-simulator.sh "$0" "$target"
fi

xcodebuild test \
    -quiet \
    -project DoodleDex.xcodeproj \
    -scheme DoodleDex \
    -derivedDataPath build/DerivedData \
    -destination "platform=iOS Simulator,id=$DOODLEDEX_SIM_UDID" \
    -only-testing:"$target"
