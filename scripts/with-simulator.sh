#!/usr/bin/env bash
# Runs a command with DOODLEDEX_SIM_UDID set to a throwaway simulator, then deletes that simulator.
# A private device means the tests never contend with whatever else is open on the machine.
set -euo pipefail

read -r device_type runtime < <(python3 "$(dirname "$0")/pick-simulator.py")
udid=$(xcrun simctl create "DoodleDex-$$" "$device_type" "$runtime")
trap 'xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true; xcrun simctl delete "$udid"' EXIT
echo "simulator $udid: $device_type on $runtime"

DOODLEDEX_SIM_UDID="$udid" "$@"
