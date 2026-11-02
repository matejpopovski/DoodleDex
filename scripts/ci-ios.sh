#!/usr/bin/env bash
# The simulator half of CI: unit, parity and persistence tests on the newest available iPhone.
set -euo pipefail
exec "$(dirname "$0")/test-ios.sh" DoodleDexTests
