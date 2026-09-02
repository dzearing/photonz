#!/bin/zsh
# Runner-failure drill: prove the go loop reacts to a runner that cannot work.
#
#   queue/bin/failure-drill.sh
#
# Two scenarios, each in a throwaway queue with a fake `claude` on PATH, each
# running the REAL go loop and then asserting what the dashboard would show.
#
# Scenario 1, a runner that always dies (the spend limit of 2026-08-23):
#
#   1. every attempt is recorded as a runner_failed event (not a silent reset)
#   2. the loop reports unhealthy, with the runner's own error text
#   3. it backs off instead of hot-retrying
#   4. a task that fails on its own three times in a row gets parked
#   5. failures that span more than one task are blamed on the environment,
#      and anything parked during that streak is handed back
#
# Scenario 2, a login that expires and is later restored (2026-08-26 to 09-01):
#
#   6. a runner that says it could not sign in is an environment failure even
#      though it exits 0 with a "success" result
#   7. the task it was given is handed back uncharged: no failure counted,
#      never parked
#   8. status.json and the loop window say sign-in is needed, at once
#   9. the daily digest is not stubbed as failed; it is retried and written
#      for real once sign-in works, and the loop recovers on its own
#
# Scenario 3, a spend limit that refuses the digest run, then clears (2026-08-26):
#
#  10. a digest runner that prints the spend-limit line and exits 0 is an
#      environment failure: the loop reports unhealthy at once, naming it
#  11. the digest is deferred, not stubbed, and written for real on the next
#      pass once the runner works again
#  12. the task that follows is untouched by it, and the loop recovers
#
# Nothing here touches the real queue or the real repo history.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO"
Q() { node queue/bin/queue.mjs "$@"; }

# ---- scenario 1: a runner that always dies ----------------------------------
SANDBOX=$(mktemp -d -t photonz-drill)
SANDBOX2=$(mktemp -d -t photonz-drill-signin)
SANDBOX3=$(mktemp -d -t photonz-drill-spend)
trap 'rm -rf "$SANDBOX" "$SANDBOX2" "$SANDBOX3"' EXIT
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

# Skip the digest pass: this scenario is about task runners.
mkdir -p "$QDIR/digests"; : > "$QDIR/digests/$(date +%F).md"

Q add "Drill task one" p1-high "drill" >/dev/null
Q add "Drill task two" p1-high "drill" >/dev/null

echo "[drill] scenario 1: running the real go loop against a runner that always exits 1..."
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
check("a real failure is never mistaken for a sign-in failure",
  fails.every((e) => !e.signIn) && !status.lastError.signIn, "signIn flags: " + fails.map((e) => e.signIn ? 1 : 0).join(""));
check("tasks parked during an environment streak are handed back",
  unparks.length >= 1 && tasks.every((t) => !t.parked),
  unparks.length + " unparked; still parked: " + tasks.filter((t) => t.parked).map((t) => t.id).join(", "));
check("no task is left in_progress", tasks.every((t) => t.status !== "in_progress"),
  tasks.map((t) => t.id + "=" + t.status).join(", "));

// The waits have to actually grow, and the shipped defaults have to be the real
// ones: an unset PHOTONZ_BACKOFF_STEPS must not collapse to zero. (The window
// says "waiting" for a plain failure and "retrying in" for a refusal it can
// name, such as this spend-limit line; both are the same wait.)
const waits = [...fs.readFileSync(process.env.DRILL_LOG, "utf8").matchAll(/(?:waiting|retrying in) (\d+)s/g)].map((m) => +m[1]);
check("each failure waits longer than the last",
  waits.length >= 3 && waits.every((w, i) => i === 0 || w >= waits[i - 1]) && waits[0] > 0,
  "waits: " + waits.join("s, ") + "s");
const { BACKOFF_STEPS } = await import(process.cwd() + "/queue/bin/queue-lib.mjs");
check("shipped default backoff is minutes, not zero",
  BACKOFF_STEPS.length > 1 && BACKOFF_STEPS[0] >= 30 && BACKOFF_STEPS[BACKOFF_STEPS.length - 1] >= 900,
  "default steps: " + BACKOFF_STEPS.join(", "));

console.log(failed ? "\n[drill] scenario 1: " + failed + " check(s) failed" : "\n[drill] scenario 1: all checks passed");
process.exit(failed ? 1 : 0);
'
S1=$?

# ---- scenario 2: a login that expires, then is restored ---------------------
QDIR2="$SANDBOX2/queue"
BIN2="$SANDBOX2/bin"
STATE2="$SANDBOX2/state"
mkdir -p "$QDIR2/digests" "$BIN2" "$STATE2"

# The fake runner mimics the agent CLI with an expired login, byte for byte
# what nine digest runs did: the sign-in failure on stderr and in the stream, a
# "success" result, exit 0. The FIRST run of each kind (digest, task) fails to
# sign in; the second run of that kind succeeds, standing in for a person
# having logged in meanwhile. It also snapshots status.json on every call, so
# the checks can see what the dashboard said while the login was expired.
cat > "$BIN2/claude" <<'FAKE'
#!/bin/zsh
prompt="${@[-1]}"
kind=digest; [[ "$prompt" == *"TASK FILE: "* ]] && kind=task
stamp="$DRILL_STATE/$kind.calls"
n=$(( $(cat "$stamp" 2>/dev/null || echo 0) + 1 )); echo $n > "$stamp"
cp "$PHOTONZ_QUEUE_DIR/status.json" "$DRILL_STATE/status-before-$kind-$n.json" 2>/dev/null
echo '{"type":"system","subtype":"init","session_id":"drill-session"}'
if (( n == 1 )); then
  echo '{"type":"assistant","message":{"content":[{"type":"text","text":"Failed to authenticate: OAuth session expired and could not be refreshed"}]}}'
  echo '{"type":"result","subtype":"success","result":""}'
  echo 'Failed to authenticate: OAuth session expired and could not be refreshed' >&2
  exit 0
fi
if [[ $kind == task ]]; then
  file="${prompt##*TASK FILE: }"
  id=$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).id)' "$file")
  node queue/bin/queue.mjs status "$id" done "drill: finished once sign-in was restored" >/dev/null
else
  printf '# Daily digest %s\n\n## Summary\nA real digest, written once sign-in was restored.\n' "$(date +%F)" > "$PHOTONZ_QUEUE_DIR/digests/$(date +%F).md"
fi
echo '{"type":"result","subtype":"success","result":"done"}'
exit 0
FAKE
chmod +x "$BIN2/claude"

export PATH="$BIN2:$PATH"
export PHOTONZ_QUEUE_DIR="$QDIR2"
export DRILL_STATE="$STATE2"
export PHOTONZ_BACKOFF_STEPS="1,2,3,4,5"
export PHOTONZ_DIGEST_HOUR=0                # the digest pass must run whatever the clock says
export PHOTONZ_MAX_ITERS=3                  # digest (sign-in fails), digest + task (sign-in fails), task

Q add "Drill task three" p1-high "drill" >/dev/null

echo "[drill] scenario 2: running the real go loop against a login that expires, then is restored..."
queue/bin/go-loop.sh > "$SANDBOX2/drill.log" 2>&1
export DRILL_LOG="$SANDBOX2/drill.log"

PHOTONZ_BACKOFF_STEPS= node --input-type=module -e '
const fs = await import("node:fs");
const q = process.env.PHOTONZ_QUEUE_DIR;
const st = process.env.DRILL_STATE;
const today = new Date().toISOString().slice(0, 10);
const read = (f, fb) => { try { return JSON.parse(fs.readFileSync(f, "utf8")); } catch { return fb; } };
const status = read(q + "/status.json", {});
const history = fs.readFileSync(q + "/history.jsonl", "utf8").trim().split("\n").map(JSON.parse);
const tasks = ["p0-critical","p1-high","p2-normal","p3-low"].flatMap((p) => {
  const d = q + "/tasks/" + p;
  return fs.existsSync(d) ? fs.readdirSync(d).map((f) => JSON.parse(fs.readFileSync(d + "/" + f, "utf8"))) : [];
});
const task = tasks[0] || {};
const log = fs.readFileSync(process.env.DRILL_LOG, "utf8");
let failed = 0;
const check = (name, ok, detail) => {
  console.log((ok ? "  PASS  " : "  FAIL  ") + name + (detail ? "\n          " + detail : ""));
  if (!ok) failed++;
};

const fails = history.filter((e) => e.ev === "runner_failed");
const parks = history.filter((e) => e.ev === "task_parked");
const digestFailed = history.filter((e) => e.ev === "digest_failed");
const digestDeferred = history.filter((e) => e.ev === "digest_deferred");
const duringDigest = read(st + "/status-before-digest-2.json", {});
const duringTask = read(st + "/status-before-task-2.json", {});

check("a runner that could not sign in is recorded as a failure despite exit 0",
  fails.length === 2 && fails.every((e) => e.exit === 0 && e.signIn === true && e.outcome === "signin"),
  fails.length + " runner_failed events: " + JSON.stringify(fails.map((e) => [e.kind, e.exit, e.outcome])));
check("the failure text is the sign-in line",
  fails.every((e) => /Failed to authenticate/.test(e.error || "")), JSON.stringify(fails[0] && fails[0].error));
check("a sign-in failure is blamed on the environment on its own",
  fails.every((e) => e.environment === true), "environment flags: " + fails.map((e) => e.environment ? 1 : 0).join(""));
check("the task is not charged a failure", !(task.failures > 0) && !task.lastError,
  "failures=" + (task.failures || 0) + " lastError=" + JSON.stringify(task.lastError || null));
check("the task is never parked", parks.length === 0 && !task.parked, parks.length + " parked");
check("the task log says it was handed back, not that it failed",
  (task.log || []).some((l) => /could not sign in/.test(l.note)) && !(task.log || []).some((l) => /runner failed \(exit/.test(l.note)),
  (task.log || []).map((l) => l.note).join(" | "));
check("status.json reported sign-in needed while the login was expired",
  duringDigest.health === "unhealthy" && duringDigest.lastError && duringDigest.lastError.signIn === true && duringDigest.lastError.kind === "digest",
  "health=" + duringDigest.health + " signIn=" + (duringDigest.lastError && duringDigest.lastError.signIn));
check("...and again when a task run hit it",
  duringTask.health === "unhealthy" && duringTask.lastError && duringTask.lastError.signIn === true && duringTask.lastError.taskId === task.id,
  "health=" + duringTask.health + " taskId=" + (duringTask.lastError && duringTask.lastError.taskId));
check("the loop window named sign-in as the fix", /sign-in needed: the agent could not authenticate/.test(log),
  (log.match(/sign-in needed[^\n]*/) || ["no such line"])[0]);
check("the digest was not stubbed as failed", digestFailed.length === 0 && digestDeferred.length === 1,
  digestFailed.length + " digest_failed, " + digestDeferred.length + " digest_deferred");
check("the digest was retried and written for real once sign-in worked",
  /written once sign-in was restored/.test(fs.readFileSync(q + "/digests/" + today + ".md", "utf8")),
  "digest exists: " + fs.existsSync(q + "/digests/" + today + ".md"));
check("the task finished once sign-in worked", task.status === "done", task.id + "=" + task.status);
check("the loop recovered on its own", status.health === "ok" && status.consecutiveFailures === 0 && !status.lastError,
  "health=" + status.health + " consecutive=" + status.consecutiveFailures);
check("no task is left in_progress", tasks.every((t) => t.status !== "in_progress"),
  tasks.map((t) => t.id + "=" + t.status).join(", "));

// The status note is overwritten the moment the next run starts (that is what
// "busy" is for), so its wording is checked on a fresh queue with a direct
// call, the same call the loop makes.
process.env.PHOTONZ_QUEUE_DIR = st + "/unit-queue";
fs.mkdirSync(process.env.PHOTONZ_QUEUE_DIR, { recursive: true });
const { pickRunnerError, isSignInFailure, recordRunnerExit, readStatus } = await import(process.cwd() + "/queue/bin/queue-lib.mjs");
const unitExit = recordRunnerExit({ taskId: null, exit: 0, error: "Failed to authenticate: OAuth session expired and could not be refreshed", kind: "digest" });
const unitStatus = readStatus();
check("the status note says sign-in is needed, from the first failure",
  unitExit.outcome === "signin" && unitStatus.health === "unhealthy" && unitStatus.consecutiveFailures === 1 && /sign-in needed/i.test(unitStatus.note || ""),
  "outcome=" + unitExit.outcome + " health=" + unitStatus.health + " note=" + JSON.stringify(unitStatus.note));

// The line picker must find the sign-in failure even when the CLI printed
// something after it, and must not read a working runner as one.
check("the error picker surfaces a sign-in line buried above other stderr lines",
  /Failed to authenticate/.test(pickRunnerError("Failed to authenticate: OAuth session expired and could not be refreshed\nRun /login to sign in\n", "unrelated")),
  JSON.stringify(pickRunnerError("Failed to authenticate: OAuth session expired\nRun /login\n", "")));
check("the error picker keeps the last stderr line for anything else",
  pickRunnerError("first\nRequest timed out\n", "\x1b[1m■ runner finished (success)\x1b[0m") === "Request timed out"
    && pickRunnerError("", "\x1b[1m■ runner finished (success)\x1b[0m") === "■ runner finished (success)",
  "");
check("a working runner is not a sign-in failure", !isSignInFailure("■ runner finished (success)") && !isSignInFailure(""), "");

console.log(failed ? "\n[drill] scenario 2: " + failed + " check(s) failed" : "\n[drill] scenario 2: all checks passed");
process.exit(failed ? 1 : 0);
'
S2=$?

# ---- scenario 3: the spend limit refuses the digest run, then clears --------
QDIR3="$SANDBOX3/queue"
BIN3="$SANDBOX3/bin"
STATE3="$SANDBOX3/state"
mkdir -p "$QDIR3/digests" "$BIN3" "$STATE3"

# The fake runner mimics the agent CLI on 2026-08-26 05:38, byte for byte: the
# spend-limit line in the stream and on stderr, a "success" result, exit 0.
# Only the FIRST digest run is refused; the next digest run and the task run
# work, standing in for the limit having reset meanwhile.
cat > "$BIN3/claude" <<'FAKE'
#!/bin/zsh
prompt="${@[-1]}"
kind=digest; [[ "$prompt" == *"TASK FILE: "* ]] && kind=task
stamp="$DRILL_STATE/$kind.calls"
n=$(( $(cat "$stamp" 2>/dev/null || echo 0) + 1 )); echo $n > "$stamp"
cp "$PHOTONZ_QUEUE_DIR/status.json" "$DRILL_STATE/status-before-$kind-$n.json" 2>/dev/null
echo '{"type":"system","subtype":"init","session_id":"drill-session"}'
limit="You've hit your monthly spend limit · raise it at claude.ai/settings/usage?from=cc_cli_limit_message · your weekly limit resets Aug 29 at 1am (America/Los_Angeles)"
if [[ $kind == digest && $n == 1 ]]; then
  echo "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"$limit\"}]}}"
  echo '{"type":"result","subtype":"success","result":""}'
  echo "$limit" >&2
  exit 0
fi
if [[ $kind == task ]]; then
  file="${prompt##*TASK FILE: }"
  id=$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).id)' "$file")
  node queue/bin/queue.mjs status "$id" done "drill: finished once the spend limit cleared" >/dev/null
else
  printf '# Daily digest %s\n\n## Summary\nA real digest, written once the spend limit cleared.\n' "$(date +%F)" > "$PHOTONZ_QUEUE_DIR/digests/$(date +%F).md"
fi
echo '{"type":"result","subtype":"success","result":"done"}'
exit 0
FAKE
chmod +x "$BIN3/claude"

export PATH="$BIN3:$PATH"
export PHOTONZ_QUEUE_DIR="$QDIR3"
export DRILL_STATE="$STATE3"
export PHOTONZ_BACKOFF_STEPS="1,2,3,4,5"
export PHOTONZ_DIGEST_HOUR=0
export PHOTONZ_MAX_ITERS=2                  # digest (refused), digest + task (both work)

Q add "Drill task four" p1-high "drill" >/dev/null

echo "[drill] scenario 3: running the real go loop against a spend limit that refuses the digest, then clears..."
queue/bin/go-loop.sh > "$SANDBOX3/drill.log" 2>&1
export DRILL_LOG="$SANDBOX3/drill.log"

PHOTONZ_BACKOFF_STEPS= node --input-type=module -e '
const fs = await import("node:fs");
const q = process.env.PHOTONZ_QUEUE_DIR;
const st = process.env.DRILL_STATE;
const today = new Date().toISOString().slice(0, 10);
const read = (f, fb) => { try { return JSON.parse(fs.readFileSync(f, "utf8")); } catch { return fb; } };
const status = read(q + "/status.json", {});
const history = fs.readFileSync(q + "/history.jsonl", "utf8").trim().split("\n").map(JSON.parse);
const tasks = ["p0-critical","p1-high","p2-normal","p3-low"].flatMap((p) => {
  const d = q + "/tasks/" + p;
  return fs.existsSync(d) ? fs.readdirSync(d).map((f) => JSON.parse(fs.readFileSync(d + "/" + f, "utf8"))) : [];
});
const task = tasks[0] || {};
const log = fs.readFileSync(process.env.DRILL_LOG, "utf8");
let failed = 0;
const check = (name, ok, detail) => {
  console.log((ok ? "  PASS  " : "  FAIL  ") + name + (detail ? "\n          " + detail : ""));
  if (!ok) failed++;
};

const fails = history.filter((e) => e.ev === "runner_failed");
const digestFailed = history.filter((e) => e.ev === "digest_failed");
const digestDeferred = history.filter((e) => e.ev === "digest_deferred");
const duringDigest = read(st + "/status-before-digest-2.json", {});

check("a digest runner that prints the spend-limit line and exits 0 is recorded as a failure",
  fails.length === 1 && fails[0].kind === "digest" && fails[0].exit === 0 && fails[0].outcome === "spend",
  fails.length + " runner_failed events: " + JSON.stringify(fails.map((e) => [e.kind, e.exit, e.outcome])));
check("the failure is blamed on the environment, with reason spend and not sign-in",
  fails.every((e) => e.environment === true && e.reason === "spend" && !e.signIn),
  JSON.stringify(fails.map((e) => [e.environment, e.reason, e.signIn])));
check("the failure text is the spend-limit line",
  fails.every((e) => /spend limit/.test(e.error || "")), JSON.stringify(fails[0] && fails[0].error));
check("status.json reported the spend limit while it lasted, from the first refusal",
  duringDigest.health === "unhealthy" && duringDigest.consecutiveFailures === 1 && duringDigest.lastError && duringDigest.lastError.reason === "spend" && duringDigest.lastError.kind === "digest",
  "health=" + duringDigest.health + " reason=" + (duringDigest.lastError && duringDigest.lastError.reason));
check("the loop window named the spend limit as the cause", /spend limit hit: the agent refused to run/.test(log),
  (log.match(/spend limit hit[^\n]*/) || ["no such line"])[0]);
check("the digest was not stubbed as failed", digestFailed.length === 0 && digestDeferred.length === 1 && digestDeferred[0].reason === "spend",
  digestFailed.length + " digest_failed, " + JSON.stringify(digestDeferred));
check("the digest was retried and written for real once the limit cleared",
  /written once the spend limit cleared/.test((() => { try { return fs.readFileSync(q + "/digests/" + today + ".md", "utf8"); } catch { return ""; } })()),
  "digest exists: " + fs.existsSync(q + "/digests/" + today + ".md"));
check("the task that followed finished, uncharged and never parked",
  task.status === "done" && !(task.failures > 0) && !task.parked,
  task.id + "=" + task.status + " failures=" + (task.failures || 0));
check("the loop recovered on its own", status.health === "ok" && status.consecutiveFailures === 0 && !status.lastError,
  "health=" + status.health + " consecutive=" + status.consecutiveFailures);
check("no task is left in_progress", tasks.every((t) => t.status !== "in_progress"),
  tasks.map((t) => t.id + "=" + t.status).join(", "));

// Direct calls, the same ones the loop makes, on a fresh queue.
process.env.PHOTONZ_QUEUE_DIR = st + "/unit-queue";
fs.mkdirSync(process.env.PHOTONZ_QUEUE_DIR, { recursive: true });
const { pickRunnerError, environmentSignature, recordRunnerExit, readStatus } = await import(process.cwd() + "/queue/bin/queue-lib.mjs");
const line = "You\u2019ve hit your monthly spend limit \u00b7 raise it at claude.ai/settings/usage \u00b7 your weekly limit resets Aug 29 at 1am";
const unitExit = recordRunnerExit({ taskId: null, exit: 0, error: line, kind: "digest" });
const unitStatus = readStatus();
check("the status note names the spend limit, from the first refusal",
  unitExit.outcome === "spend" && unitExit.reason === "spend" && unitStatus.health === "unhealthy" && /spend limit hit/i.test(unitStatus.note || ""),
  "outcome=" + unitExit.outcome + " note=" + JSON.stringify(unitStatus.note));
check("the error picker surfaces the spend-limit line buried above other stderr lines",
  /spend limit/.test(pickRunnerError(line + "\nsomething printed after\n", "unrelated")), "");
check("the signature table tells the two refusals apart",
  environmentSignature(line).id === "spend" && environmentSignature("Failed to authenticate: OAuth session expired").id === "signin" && environmentSignature("Request timed out") === null, "");

console.log(failed ? "\n[drill] scenario 3: " + failed + " check(s) failed" : "\n[drill] scenario 3: all checks passed");
process.exit(failed ? 1 : 0);
'
S3=$?

if (( S1 == 0 && S2 == 0 && S3 == 0 )); then
  echo "[drill] all checks passed"
  exit 0
fi
echo "[drill] FAILED (scenario 1 exit $S1, scenario 2 exit $S2, scenario 3 exit $S3)"
exit 1
