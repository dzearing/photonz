#!/bin/zsh
# Stall return drill: prove a loop stalled on something only a person can clear
# tells them when they come back to the Mac, once per return, and never without
# a stall.
#
#   queue/bin/stall-return-drill.sh
#
# On 2026-09-30 the loop stalled on sign-in at 22:05 and told the person at
# once, as it should. Nobody was at the Mac. The once-a-day rule then kept it
# quiet, the person came back the next day to nothing waiting for them, and the
# loop sat on 39 refusals for twenty hours until they happened to log in that
# evening (queue/loop.log; one stall_notified event in queue/history.jsonl).
#
# This drill sources the real go-loop.sh for its real stall_wait and
# notify_person (PHOTONZ_GO_LOOP_DEFS_ONLY, so nothing below the definitions
# runs) and drives them in a throwaway queue, with a stand-in for the Mac's idle
# clock that reads out a script of readings and a stand-in for osascript that
# writes down every notification instead of raising it.
#
#   1. stalled, the person away then back: exactly one notice, naming the fix
#   2. still there afterwards: nothing more
#   3. away again and back again: one more, because it is one per return
#   4. the wait is cut short on their return, so a sign-in is picked up soon
#   5. loop.log and history.jsonl both say when the return notice went out
#   6. a retry while they are away does not forget that they are away
#   7. the stall clears while they are away: nothing on their return
#   8. no stall at all, away then back: nothing
#   9. the night of 2026-09-30 replayed through the rule: one notice, at 18:25
#
# Nothing here touches the real queue or raises a real notification.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO"

SANDBOX_DIR=$(mktemp -d -t photonz-stall-return-drill)
trap 'rm -rf "$SANDBOX_DIR"' EXIT
QUEUE="$SANDBOX_DIR/queue"
BIN="$SANDBOX_DIR/bin"
mkdir -p "$QUEUE" "$BIN"

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); print -r -- "  ok   $1"; }
bad()  { FAIL=$((FAIL+1)); print -r -- "  FAIL $1"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; print -r -- "         $3"; fi; }

# Every notification lands here, one line each, instead of on the screen.
NOTES="$SANDBOX_DIR/notifications.txt"; : > "$NOTES"
cat > "$BIN/osascript" <<FAKE
#!/bin/zsh
print -r -- "\$@" >> "$NOTES"
FAKE
chmod +x "$BIN/osascript"

# The Mac's idle clock, as a script: each call reads the next line of READINGS
# and the last one repeats once the script runs out.
READINGS="$SANDBOX_DIR/readings.txt"
cat > "$BIN/person-at-mac.sh" <<FAKE
#!/bin/zsh
f="$READINGS"
first=\$(head -n 1 "\$f" 2>/dev/null)
if (( \$(wc -l < "\$f") > 1 )); then tail -n +2 "\$f" > "\$f.next" && mv "\$f.next" "\$f"; fi
print -r -- "\${first:-0}"
FAKE
chmod +x "$BIN/person-at-mac.sh"
readings() { print -l -- "$@" > "$READINGS"; }

export PATH="$BIN:$PATH"
export PHOTONZ_QUEUE_DIR="$QUEUE"
export PHOTONZ_PERSON_AT_MAC="$BIN/person-at-mac.sh"
export PHOTONZ_PRESENCE_POLL=1
export PHOTONZ_RETURN_RETRY=1
export PHOTONZ_GO_LOOP_DEFS_ONLY=1
source queue/bin/go-loop.sh || { print -r -- "could not source go-loop.sh for its definitions"; exit 1 }

# A stall on record exactly as recordRunnerExit leaves one: started twenty hours
# ago, told once at its start.
stall_on_record() { # $1 = reason
  node -e '
const fs = require("fs"), f = process.argv[1];
const s = (() => { try { return JSON.parse(fs.readFileSync(f, "utf8")); } catch { return {}; } })();
const at = new Date(Date.now() - 20 * 3600 * 1000).toISOString();
s.stall = { reason: process.argv[2], since: at, notifiedAt: at, notices: 1, attempts: 39 };
fs.writeFileSync(f, JSON.stringify(s, null, 2));
' "$QUEUE/status.json" "$1"
}
stall_field() { node -e 'const s = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")); const v = s.stall ? s.stall[process.argv[2]] : "none"; console.log(v === undefined ? "" : v)' "$QUEUE/status.json" "$1"; }
notes() { wc -l < "$NOTES" | tr -d ' '; }

print -r -- "[drill] stall return: stalled on sign-in, the person away then back"
stall_on_record signin
readings 3600 3600 2 2 2
start=$SECONDS
stall_wait 30 signin
took=$((SECONDS - start))
check "1. away then back to a stalled loop: exactly one notice" '[[ $(notes) == 1 ]]' "$(notes) notification(s): $(cat "$NOTES")"
check "   it says what is wrong and the one thing that ends it" \
  'grep -q "Stopped 20h ago while you were away. Sign-in needed" "$NOTES" && grep -q "Run claude in a terminal and log in" "$NOTES"' "$(cat "$NOTES")"
check "   the stall records the return and that they are here" \
  '[[ $(stall_field returnNotices) == 1 && $(stall_field away) == false && -n $(stall_field returnedAt) ]]' \
  "returnNotices=$(stall_field returnNotices) away=$(stall_field away)"
check "4. the 30s wait was cut short once they came back" '(( took < 10 ))' "waited ${took}s"
check "5. loop.log says when the return notice went out" \
  'grep -q "notified you on your return: Photonz build loop has stopped" "$QUEUE/loop.log"' "$(tail -3 "$QUEUE/loop.log")"
check "   and history.jsonl records it as a return notice" \
  'grep -q "\"ev\":\"stall_notified\".*\"reason\":\"signin\".*\"hours\":20.*\"on\":\"return\"" "$QUEUE/history.jsonl"' "$(grep stall_ "$QUEUE/history.jsonl")"

print -r -- "[drill] stall return: still at the Mac"
readings 2 5 30 120 600
stall_wait 5 signin
check "2. a person who stays at the Mac hears nothing more" '[[ $(notes) == 1 ]]' "$(notes) notification(s)"

print -r -- "[drill] stall return: away again, and back again"
readings 1800 1800 3
stall_wait 5 signin
check "3. a second return is a second notice: one per return" '[[ $(notes) == 2 && $(stall_field returnNotices) == 2 ]]' "$(notes) notification(s), returnNotices=$(stall_field returnNotices)"

print -r -- "[drill] stall return: a retry while they are away"
readings 3600
stall_wait 2 signin
Q runner-exit - 0 --reason signin "Not logged in · Please run /login" >/dev/null
check "6. a refusal while they are away keeps them away" '[[ $(stall_field away) == true && $(stall_field attempts) == 40 ]]' "away=$(stall_field away) attempts=$(stall_field attempts)"
readings 4
stall_wait 2 signin
check "   so their return after it is still told" '[[ $(notes) == 3 ]]' "$(notes) notification(s)"

print -r -- "[drill] stall return: the stall clears while they are away"
readings 3600
stall_wait 2 signin
Q runner-exit - 0 --reason '' >/dev/null
readings 2 2 2
stall_wait 3 signin
check "7. a stall that cleared while they were away tells them nothing" '[[ $(notes) == 3 && $(stall_field reason) == none ]]' "$(notes) notification(s), stall=$(stall_field reason)"

print -r -- "[drill] stall return: no stall at all"
readings 3600 3600 2 2
stall_wait 4 signin
stall_wait 2 ""
check "8. away then back with no stall: nothing" '[[ $(notes) == 3 ]]' "$(notes) notification(s)"

print -r -- "[drill] stall return: the night of 2026-09-30, replayed through the rule"
node --input-type=module -e '
const { advanceStall, advancePresence } = await import(process.cwd() + "/queue/bin/queue-lib.mjs");
// Local Pacific times from queue/loop.log, as UTC: the person stopped touching
// the Mac at 21:30, the stall began 22:05, refusals every half hour after it,
// and they came back at 18:25 the next day.
const at = (iso) => new Date(iso).toISOString();
let s = advanceStall(null, "signin", at("2026-10-01T05:05:09Z")).stall;
let told = [];
const idleAt = (t) => t < Date.parse("2026-10-02T01:25:00Z") ? (t - Date.parse("2026-10-01T04:30:00Z")) / 1000 : 3;
for (let t = Date.parse("2026-10-01T05:05:29Z"); t <= Date.parse("2026-10-02T01:40:00Z"); t += 20000) {
  if ((t - Date.parse("2026-10-01T05:05:09Z")) % 1800000 < 20000) s = advanceStall(s, "signin", at(t)).stall;
  const r = advancePresence(s, Math.max(0, Math.round(idleAt(t))), at(t));
  s = r.stall;
  if (r.notify) told.push([at(t), r.hours]);
}
const okay = told.length === 1 && told[0][0] >= "2026-10-02T01:25:00Z" && told[0][0] < "2026-10-02T01:26:00Z" && told[0][1] === 20;
console.log((okay ? "  ok   " : "  FAIL ") + "9. that night would have told them once, the minute they came back, twenty hours in" + (okay ? "" : "\n         " + JSON.stringify(told)));
process.exit(okay ? 0 : 1);
' && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

print -r -- ""
if (( FAIL )); then print -r -- "[drill] stall return: $FAIL check(s) failed, $PASS passed"; exit 1; fi
print -r -- "[drill] stall return: all $PASS checks passed"
