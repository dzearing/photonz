#!/bin/bash
# Two speed walk runs side by side (`Scripts/perf/speed-walk.sh` writes them):
# every number either has, each run's value and the change.
#
#   Scripts/perf/compare.sh <before.json> <after.json> [--margin <percent>]
#
# With --margin it also names the numbers in <after> worse than <before> by
# more than that share plus each number's floor (`SpeedCompare.regressions`),
# and exits 1 when there are any: the rule the short walk fails on.
set -euo pipefail
cd "$(dirname "$0")/../.."
[[ $# -ge 2 ]] || { echo "usage: $0 <before.json> <after.json> [--margin <percent>]" >&2; exit 2; }
swift build --product ReferenceEditTool 2>&1 | grep -E "error" || true
"$(swift build --show-bin-path)/ReferenceEditTool" compare "$@"
