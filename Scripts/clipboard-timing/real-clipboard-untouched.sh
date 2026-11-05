#!/bin/zsh
# Proves walks stay off the Mac's real clipboard: runs every walk that copies or
# pastes (or the ones named), reading the real clipboard's change count either
# side. It reads the count only, never what is on the clipboard. A person who
# copies something during the run moves it too, so read a non-zero with that in
# mind, and run it again before calling it a fault.
# Usage: Scripts/clipboard-timing/real-clipboard-untouched.sh [walk-name-fragment ...]
set -euo pipefail
cd "$(dirname "$0")/../.."
unset PHOTONZ_PROBE_REAL_CLIPBOARD
T=/tmp/copy-timing
mkdir -p "$T"
[[ -x "$T/changecount" ]] || {
  print 'import AppKit\nprint(NSPasteboard.general.changeCount)' > "$T/changecount.swift"
  swiftc -O "$T/changecount.swift" -o "$T/changecount"
}
walks=("$@")
if (( $# == 0 )); then
  walks=(${(f)"$(grep -lE '"(clipboardText|clearClipboard|readClipboard)"' Scripts/playtest/*.json | xargs -n1 basename | sed 's/\.json$//')"})
fi
before=$("$T/changecount")
Scripts/playtest-all.sh --no-build "${walks[@]}"
after=$("$T/changecount")
print "==> ${#walks} walk names, real clipboard moved $((after - before)) times"
(( after == before ))
