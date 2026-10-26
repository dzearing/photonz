#!/bin/bash
# Measures what each test suite costs on its own and writes the table
# Scripts/test.sh deals its slices by (Scripts/test-weights.tsv), so the
# slices CI runs side by side finish together instead of one waiting on the
# heavy render suites another happened to draw (2026-10-26: dealt by name
# alone, three slices were 366, 560 and 821 CPU seconds).
#
#   Scripts/test-weights.sh                         # render and media suites
#   Scripts/test-weights.sh PhotonzCoreTests        # or the targets named
#
# Each suite runs alone (`swift test --skip-build --filter`), four at a time,
# four tests wide each (never the whole pool: see Scripts/test.sh).
# Its weight is its CPU seconds or its wall seconds, whichever is more, less
# what an empty run costs, so a suite that waits on the movie encoder or runs
# one test after another weighs what it holds a slot for. Suites under half a
# second are left out: Scripts/test.sh gives a suite it has no weight for a
# small default. Run it again after adding or reshaping a heavy suite; it
# takes about ten minutes for the render and media suites.
set -euo pipefail
cd "$(dirname "$0")/.."

targets=("$@")
(( ${#targets[@]} )) || targets=(PhotonzRenderTests PhotonzMediaTests)
pattern="^($(IFS='|'; echo "${targets[*]}"))\\."

swift build --build-tests >/dev/null
work="$(mktemp -d -t photonz-test-weights-XXXXXX)"
trap 'rm -rf "$work"' EXIT

swift test list --skip-build 2>/dev/null | grep -E "$pattern" | sed -E 's#/.*##' \
  | LC_ALL=C sort -u > "$work/units"
echo "==> Measuring $(wc -l < "$work/units" | tr -d ' ') suites, four at a time."

# What an empty run costs: the helper starting and finding nothing to do.
measure() {
  local unit="$1" out="$2"
  local filter
  filter="^$(printf '%s' "$unit" | sed 's/[][\.()*+?^$|{}]/\\&/g')(/|\$)"
  /usr/bin/time -p swift test --skip-build --filter "$filter" >/dev/null 2>"$out.time" || true
  awk -v u="$unit" '/^real/ {r=$2} /^user/ {c+=$2} /^sys/ {c+=$2} END {print u "\t" r "\t" c}' \
    "$out.time" > "$out.row"
}
export -f measure
export SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH=4

measure 'PhotonzCoreTests.NoSuchSuiteForTheEmptyRun' "$work/empty"
base_real=$(cut -f2 "$work/empty.row"); base_cpu=$(cut -f3 "$work/empty.row")
echo "==> An empty run: ${base_real}s wall, ${base_cpu}s CPU."

awk '{printf "%s\t%s/%d\n", $0, dir, NR}' dir="$work" "$work/units" \
  | xargs -P 4 -L 1 bash -c 'measure "$0" "$1"'

{
  echo "# Suite<TAB>weight in seconds, from Scripts/test-weights.sh on $(date +%Y-%m-%d)."
  echo "# Read by Scripts/test.sh --shard; suites not listed weigh a small default."
  cat "$work"/[0-9]*.row | awk -F'\t' -v br="$base_real" -v bc="$base_cpu" '{
    r = $2 - br; c = $3 - bc; w = (r > c ? r : c)
    if (w >= 0.5) printf "%s\t%.1f\n", $1, w
  }' | sort -t$'\t' -k2,2 -rn
} > "$work/table"

# Keep the rows for targets this run did not measure.
if [[ -f Scripts/test-weights.tsv ]]; then
  grep -vE '^#' Scripts/test-weights.tsv | grep -vE "$pattern" >> "$work/table" || true
fi
{ grep -E '^#' "$work/table"; grep -vE '^#' "$work/table" | sort -t$'\t' -k2,2 -rn; } \
  > Scripts/test-weights.tsv
echo "==> Wrote Scripts/test-weights.tsv: $(grep -vcE '^#' Scripts/test-weights.tsv) suites weigh half a second or more."
