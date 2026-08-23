#!/bin/zsh
# Runner-failure drill: prove the go loop reacts to a runner that always dies.
#
#   queue/bin/failure-drill.sh
#
# Builds a throwaway queue with two tasks, puts a fake `claude` on PATH that
# always exits non-zero with a spend-limit message, runs the REAL go loop
# against it, then asserts what the dashboard would show:
#
#   1. every attempt is recorded as a runner_failed event (not a silent reset)
#   2. the loop reports unhealthy, with the runner's own error text
#   3. it backs off instead of hot-retrying
#   4. a task that fails on its own three times in a row gets parked
#   5. failures that span more than one task are blamed on the environment,
#      and anything parked during that streak is handed back
#
# Nothing here touches the real queue or the real repo history.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO"
SANDBOX=$(mktemp -d -t photonz-drill)
trap 'rm -rf "$SANDBOX"' EXIT
QDIR="$SANDBOX/queue"
BIN="$SANDBOX/bin"
mkdir -p "$QDIR" "$BIN"

# The fake runner: dies instantly, exactly like every runner did on 2026-08-23.
cat > "$BIN/claude" <<'FAKE'
#!/bin/zsh
echo 'Credit balance is too low: this organization has hit its monthly spend limit.' >&2
exit 1
FAKE
chmod +x "$BIN/claude"

export PATH="$BIN:$PATH"
export PHOTONZ_QUEUE_DIR="$QDIR"
export PHOTONZ_BACKOFF_STEPS="1,2,3,4,5"   # same shape, seconds instead of minutes
export PHOTONZ_MAX_ITERS=6

Q() { node queue/bin/queue.mjs "$@"; }
# Skip the digest pass: this drill is about task runners.
mkdir -p "$QDIR/digests"; : > "$QDIR/digests/$(date +%F).md"

Q add "Drill task one" p1-high "drill" >/dev/null
Q add "Drill task two" p1-high "drill" >/dev/null

echo "[drill] running the real go loop against a runner that always exits 1..."
queue/bin/go-loop.sh > "$SANDBOX/drill.log" 2>&1
export DRILL_LOG="$SANDBOX/drill.log"

PHOTONZ_BACKOFF_STEPS= node --input-type=module -e '
const fs = await import("node:fs");
const q = process.env.PHOTONZ_QUEUE_DIR;
const status = JSON.parse(fs.readFileSync(q + "/status.json", "utf8"));
const history = fs.readFileSync(q + "/history.jsonl", "utf8").trim().split("\n").map(JSON.parse);
const tasks = ["p0-critical","p1-high","p2-normal","p3-low"].flatMap((p) => {
  const d = q + "/tasks/" + p;
  return fs.existsSync(d) ? fs.readdirSync(d).map((f) => JSON.parse(fs.readFileSync(d + "/" + f, "utf8"))) : [];
});
let failed = 0;
const check = (name, ok, detail) => {
  console.log((ok ? "  PASS  " : "  FAIL  ") + name + (detail ? "\n          " + detail : ""));
  if (!ok) failed++;
};

const starts = history.filter((e) => e.ev === "task_started").length;
const fails  = history.filter((e) => e.ev === "runner_failed");
const parks  = history.filter((e) => e.ev === "task_parked");
const unparks = history.filter((e) => e.ev === "task_unparked");
const resets = history.filter((e) => e.ev === "task_reset").length;

check("one runner_failed event per attempt", fails.length === starts,
  starts + " attempts, " + fails.length + " failure events, " + resets + " blind resets");
check("failure text is the runner’s own", fails.every((e) => /monthly spend limit/.test(e.error || "")),
  JSON.stringify(fails[0] && fails[0].error));
check("loop reports unhealthy", status.health === "unhealthy", "health=" + status.health);
check("lastError carries exit code and message",
  !!status.lastError && status.lastError.exit === 1 && /monthly spend limit/.test(status.lastError.message),
  JSON.stringify(status.lastError));
check("consecutive failures counted", status.consecutiveFailures === fails.length,
  status.consecutiveFailures + " vs " + fails.length);
check("it stopped hot-retrying (6 loop passes, not thousands)", starts <= 6, starts + " attempts");
check("a repeatedly-failing task gets parked", parks.length >= 1,
  parks.map((p) => p.id).join(", ") || "none parked");
check("park reason names the error",
  parks.every((p) => /monthly spend limit/.test(p.reason || "")), JSON.stringify(parks[0] && parks[0].reason));
check("failures across tasks are blamed on the environment",
  fails.some((e) => e.environment === true), "environment flags: " + fails.map((e) => e.environment ? 1 : 0).join(""));
check("tasks parked during an environment streak are handed back",
  unparks.length >= 1 && tasks.every((t) => !t.parked),
  unparks.length + " unparked; still parked: " + tasks.filter((t) => t.parked).map((t) => t.id).join(", "));
check("no task is left in_progress", tasks.every((t) => t.status !== "in_progress"),
  tasks.map((t) => t.id + "=" + t.status).join(", "));

// The waits have to actually grow, and the shipped defaults have to be the real
// ones: an unset PHOTONZ_BACKOFF_STEPS must not collapse to zero.
const waits = [...fs.readFileSync(process.env.DRILL_LOG, "utf8").matchAll(/waiting (\d+)s/g)].map((m) => +m[1]);
check("each failure waits longer than the last",
  waits.length >= 3 && waits.every((w, i) => i === 0 || w >= waits[i - 1]) && waits[0] > 0,
  "waits: " + waits.join("s, ") + "s");
const { BACKOFF_STEPS } = await import(process.cwd() + "/queue/bin/queue-lib.mjs");
check("shipped default backoff is minutes, not zero",
  BACKOFF_STEPS.length > 1 && BACKOFF_STEPS[0] >= 30 && BACKOFF_STEPS[BACKOFF_STEPS.length - 1] >= 900,
  "default steps: " + BACKOFF_STEPS.join(", "));

console.log(failed ? "\n[drill] " + failed + " check(s) failed" : "\n[drill] all checks passed");
process.exit(failed ? 1 : 0);
'
