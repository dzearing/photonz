#!/bin/bash
# Proves a change to a core type rebuilds every test that uses it.
#
# On 2026-09-25 and again on 2026-10-02 a render test failed on correct code,
# every run, until its file was touched: two stored fields had been added to
# LayerMotion ahead of `isOn`, and the test, still compiled against the old
# layout, wrote `isOn` at its old offset. The cause was Package.swift, not the
# compiler: PhotonzRenderTests imported PhotonzCore but listed only
# PhotonzRender, and the build looks only at the modules a target lists.
# PhotonzRender's module came out byte for byte the same, so the tests were
# judged up to date. `Scripts/check-direct-imports.mjs` now keeps every target
# listing what it imports.
#
#     Scripts/stale-build-drill.sh          # a two-module package in a temp folder:
#                                           # stale when the test lists only the
#                                           # middle module, fresh when it lists both
#     Scripts/stale-build-drill.sh --real   # the 2026-10-02 change on this package:
#                                           # fields ahead of LayerMotion.isOn, then
#                                           # MotionRenderTests, which must pass
#
# Exit 0 when everything came out as described, 1 otherwise. --real puts
# LayerMotion.swift back exactly as it found it, however it ends.
set -uo pipefail
cd "$(dirname "$0")/.."
REPO="$PWD"

DEV_DIR="$(xcode-select -p)"
swift_test() {
  if [[ "$DEV_DIR" == *CommandLineTools* ]]; then
    FW="$DEV_DIR/Library/Developer/Frameworks"
    LIB="$DEV_DIR/Library/Developer/usr/lib"
    swift test -Xswiftc -F"$FW" -Xlinker -F"$FW" \
      -Xlinker -rpath -Xlinker "$FW" -Xlinker -rpath -Xlinker "$LIB" "$@"
  else
    swift test "$@"
  fi
}

if [[ "${1:-}" == "--real" ]]; then
  file="Sources/PhotonzCore/LayerMotion.swift"
  backup="$(mktemp -t layer-motion-XXXXXX)"
  cp "$file" "$backup"
  trap 'cp "$backup" "$file"; rm -f "$backup"' EXIT
  grep -q '    public var ownCurve: EasingCurve?' "$file" \
    || { echo "!! LayerMotion no longer has ownCurve; point the drill at another field"; exit 1; }
  echo "==> Building MotionRenderTests as the code stands"
  Scripts/test.sh --filter MotionRenderTests >/dev/null 2>&1 \
    || { echo "!! MotionRenderTests fail before the drill changes anything; fix that first"; exit 1; }
  perl -0pi -e 's/(    public var ownCurve: EasingCurve\?\n)/$1    public var staleDrillA: Double?\n    public var staleDrillB: Double?\n/' "$file"
  echo "==> Added two stored fields ahead of LayerMotion.isOn; running MotionRenderTests again"
  out="$(Scripts/test.sh --filter MotionRenderTests 2>&1)"
  status=$?
  grep -E 'Test run with' <<<"$out"
  if (( status == 0 )); then
    echo "==> Fresh: the tests were rebuilt against the new layout."
    exit 0
  fi
  grep -E '✘ Test .*(recorded an issue|failed)' <<<"$out" | cut -c1-200
  echo "!! STALE: MotionRenderTests failed after a core type changed shape."
  exit 1
fi

# The miniature: Core holds the type, Render uses it, RenderTests writes the
# field that moves.
attempt() {  # $1 = the test target's dependencies, as Swift
  local dir; dir="$(mktemp -d -t stale-build-drill-XXXXXX)"
  mkdir -p "$dir/Sources/Core" "$dir/Sources/Render" "$dir/Tests/RenderTests"
  cat > "$dir/Package.swift" <<EOF
// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "StaleBuildDrill", platforms: [.macOS("26.0")], targets: [
    .target(name: "Core"),
    .target(name: "Render", dependencies: ["Core"]),
    .testTarget(name: "RenderTests", dependencies: $1),
])
EOF
  cat > "$dir/Sources/Core/Motion.swift" <<'EOF'
public struct Motion: Hashable, Sendable {
    public var name: String
    public var pivot: Int?
    public var isOn: Bool
    public init(name: String) { self.name = name; self.pivot = nil; self.isOn = true }
}
public struct Doc: Hashable, Sendable {
    public var motions: [Motion]?
    public init() { motions = [Motion(name: "spin")] }
}
EOF
  cat > "$dir/Sources/Render/Render.swift" <<'EOF'
import Core
public func drawsStill(_ doc: Doc) -> Bool { doc.motions?.first?.isOn == false }
EOF
  cat > "$dir/Tests/RenderTests/RenderTests.swift" <<'EOF'
import Testing
import Core
import Render
@Test func aSwitchedOffMotionDrawsStill() {
    var doc = Doc()
    doc.motions?[0].isOn = false
    #expect(drawsStill(doc), "\(doc)")
}
EOF
  local result
  if ! (cd "$dir" && swift_test >/dev/null 2>&1); then
    result="BROKEN"
  else
    perl -0pi -e 's/(    public var pivot: Int\?\n)/$1    public var ownPivot: Int?\n    public var ownCurve: String?\n/; s/self\.pivot = nil;/self.pivot = nil; self.ownPivot = nil; self.ownCurve = nil;/' \
      "$dir/Sources/Core/Motion.swift"
    if (cd "$dir" && swift_test >/dev/null 2>&1); then result="FRESH"; else result="STALE"; fi
  fi
  rm -rf "$dir"
  echo "$result"
}

only_render="$(attempt '["Render"]')"
echo "==> Test target lists only Render:        $only_render (expected STALE)"
both="$(attempt '["Core", "Render"]')"
echo "==> Test target lists Core and Render:    $both (expected FRESH)"

if [[ "$both" != "FRESH" ]]; then
  echo "!! Listing every imported module no longer keeps the tests fresh: the guard is not enough any more."
  exit 1
fi
if [[ "$only_render" != "STALE" ]]; then
  echo "==> The build now catches the transitive case by itself. The guard is still harmless; this drill's first half can go."
fi
exit 0
