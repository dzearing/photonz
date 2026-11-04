#!/bin/zsh
# Run this on the Mac where screenshots do not reach the clipboard. It needs no
# permissions, no compiler and no copy of the repo: copy this one file over.
# Take screenshots the way you always do, and paste as usual. For each one it
# says which of these happened:
#   ok        the file landed and the clipboard still held the picture 3 s later
#   NO COPY   a file landed and the clipboard never moved
#   REPLACED  the clipboard held the picture, then something else took its place
#   NO PICTURE the clipboard moved but held no readable picture
# It records clipboard TYPES and SIZES only, never what is on the clipboard.
# Usage: other-mac-report.sh [minutes, default 5] [folder, default ~/Pictures/Screenshots]
minutes="${1:-5}"
folder="${2:-$HOME/Pictures/Screenshots}"
out="${REPORT:-$HOME/Desktop/photonz-clipboard-report-$(date +%Y%m%d-%H%M%S).txt}"
{
  echo "Photonz clipboard report, $(date)"
  echo "macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
  for app in /Applications/Photonz.app; do
    [[ -d $app ]] && echo "$app: $(defaults read "$app/Contents/Info" CFBundleShortVersionString 2>/dev/null)"
  done
  echo "Running copies of Photonz:"
  pgrep -lf '/Contents/MacOS/Photonz' | sed 's/^/  /'
  echo "Displays: $(system_profiler SPDisplaysDataType 2>/dev/null | grep -c Resolution)"
  echo "macOS screenshot shortcuts (on means macOS can take the key before Photonz):"
  keys="$HOME/Library/Preferences/com.apple.symbolichotkeys.plist"
  for pair in "28:shift-cmd-3 to a file" "29:ctrl-shift-cmd-3 to the clipboard" \
              "30:shift-cmd-4 to a file" "31:ctrl-shift-cmd-4 to the clipboard" "184:shift-cmd-5 toolbar"; do
    # Absent means never changed, and macOS ships these on.
    state=$(plutil -extract "AppleSymbolicHotKeys.${pair%%:*}.enabled" raw -o - "$keys" 2>/dev/null)
    [[ "$state" == false || "$state" == 0 ]] && state=off || state=on
    echo "  ${pair#*:}: $state"
  done
  echo "Clipboard helpers running:"
  pgrep -il 'paste|maccy|clipy|alfred|raycast|copyclip|flycut|launchbar' | sed 's/^/  /'
  echo
} | tee "$out"
echo "Watching for $minutes minutes. Take screenshots now. Report: $out"
/usr/bin/osascript -l JavaScript - "$minutes" "$folder" <<'J' 2>&1 | tee -a "$out"
ObjC.import('AppKit')
function run(argv) {
  const minutes = Number(argv[0]), folder = argv[1]
  const pb = $.NSPasteboard.generalPasteboard, fm = $.NSFileManager.defaultManager
  const say = s => { const line = $(s + '\n').dataUsingEncoding($.NSUTF8StringEncoding); $.NSFileHandle.fileHandleWithStandardOutput.writeData(line) }
  const stamp = () => { const d = new Date(); return d.toTimeString().slice(0, 8) + '.' + String(d.getMilliseconds()).padStart(3, '0') }
  const files = () => { const a = fm.contentsOfDirectoryAtPathError(folder, null); return a.isNil() ? [] : ObjC.deepUnwrap(a).filter(n => /\.png$/i.test(n)) }
  const types = () => { const t = pb.types; return t.isNil() ? [] : ObjC.deepUnwrap(t) }
  const hasPicture = () => { const t = types(); return t.includes('public.png') || t.includes('public.tiff') }
  const pngBytes = () => { const d = pb.dataForType('public.png'); return d.isNil() ? -1 : Number(d.length) }
  let seen = new Set(files()), count = Number(pb.changeCount), lastMove = 0, watching = []
  const tally = {}
  const end = Date.now() + minutes * 60000
  while (Date.now() < end) {
    const c = Number(pb.changeCount), now = Date.now()
    if (c !== count) { count = c; lastMove = now; say(`${stamp()} clipboard moved (${types().length} types)`) }
    for (const name of files()) if (!seen.has(name)) {
      seen.add(name); say(`${stamp()} new file ${name}`)
      watching.push({ name, at: now, count: lastMove && now - lastMove < 3000 ? c : null, picture: hasPicture() })
    }
    watching = watching.filter(w => {
      if (w.count === null && lastMove >= w.at) { w.count = Number(pb.changeCount); w.picture = hasPicture() }
      if (Date.now() - w.at < 3000) return true
      const moved = w.count !== null, still = moved && Number(pb.changeCount) === w.count
      const verdict = !moved ? 'NO COPY' : !w.picture ? 'NO PICTURE' : !still ? 'REPLACED' : pngBytes() > 0 ? 'ok' : 'NO PICTURE'
      tally[verdict] = (tally[verdict] || 0) + 1
      say(`${stamp()} ${verdict}: ${w.name}` + (verdict === 'REPLACED' ? ` (now ${types().length} types, picture ${hasPicture() ? 'yes' : 'no'})` : ''))
      return false
    })
    $.NSThread.sleepForTimeInterval(0.02)
  }
  say('Totals: ' + (JSON.stringify(tally) === '{}' ? 'no new screenshot files seen in ' + folder : JSON.stringify(tally)))
}
J
