#!/usr/bin/env bash
# Runs the UI test tour and captures each marked frame with `simctl io` from outside the test.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${DOODLEDEX_SIM_UDID:-}" ]]; then
    exec scripts/with-simulator.sh "$0"
fi

shots="$PWD/docs/screenshots"
frames="$PWD/build/frames"
markers=$(mktemp -d)
mkdir -p "$shots" "$frames"
xcrun simctl boot "$DOODLEDEX_SIM_UDID"
xcrun simctl bootstatus "$DOODLEDEX_SIM_UDID" >/dev/null
xcrun simctl status_bar "$DOODLEDEX_SIM_UDID" override --time "9:41" --batteryState charged --batteryLevel 100

(
    while true; do
        for ready in "$markers"/*.ready; do
            [[ -e "$ready" ]] || continue
            name=$(basename "$ready" .ready)
            sleep 0.3
            target="$shots"
            [[ "$name" == frame-* ]] && target="$frames"
            xcrun simctl io "$DOODLEDEX_SIM_UDID" screenshot --type=png "$target/$name.png" >/dev/null 2>&1
            rm "$ready"
            touch "$markers/$name.done"
        done
        sleep 0.2
    done
) &
watcher=$!
disown "$watcher"
trap 'kill "$watcher" 2>/dev/null || true; rm -rf "$markers"' EXIT

TEST_RUNNER_DOODLEDEX_SHOT_DIR="$markers" xcodebuild test \
    -quiet \
    -project DoodleDex.xcodeproj \
    -scheme DoodleDex \
    -derivedDataPath build/DerivedData \
    -destination "platform=iOS Simulator,id=$DOODLEDEX_SIM_UDID" \
    -only-testing:DoodleDexUITests/ScreenshotTour

uv run --group train python scripts/make_stroke_gif.py "$frames" "$shots/stroke-by-stroke.gif"
