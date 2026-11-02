#!/usr/bin/env bash
# Writes results/simulator_latency.json from an optimized build in a throwaway simulator.
# The figures are simulator latency on the host CPU. They say nothing about a phone.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${DOODLEDEX_SIM_UDID:-}" ]]; then
    exec scripts/with-simulator.sh "$0"
fi

TEST_RUNNER_DOODLEDEX_HOST="$(sysctl -n machdep.cpu.brand_string), $(($(sysctl -n hw.memsize) / 1073741824)) GB" \
TEST_RUNNER_DOODLEDEX_RESULTS_DIR="$PWD/results" xcodebuild test \
    -quiet \
    -project DoodleDex.xcodeproj \
    -scheme DoodleDex \
    -configuration Release \
    -derivedDataPath build/DerivedDataRelease \
    -destination "platform=iOS Simulator,id=$DOODLEDEX_SIM_UDID" \
    -only-testing:DoodleDexTests/LatencyBenchmark \
    ENABLE_TESTABILITY=YES
