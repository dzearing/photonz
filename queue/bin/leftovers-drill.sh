#!/bin/zsh
# Proves what the loop does about a working tree a runner walked out on.
#
# The incident this exists for: 2026-09-16 05:18, the runner on
# separate-finds-the-boxes-in-a-dark-window-too-no ran out of its turn and left
# seven files changed. Nothing said so, and the next task would have committed
# them under its own name. This drill ends a task part way ON PURPOSE and
# watches what the next one starts from.
#
# It runs the REAL go-loop.sh against a throwaway git repo and a throwaway
# queue, with a fake `claude` on PATH. Nothing here touches the real repo, the
# real queue, or the real git history: the loop's git work goes through
# queue/bin/leftovers.mjs, which operates on the repo that CONTAINS the queue
# it was pointed at.
#
# What it checks:
#   1. the loop notices the files a dead runner left, and names the task
#   2. they are put aside in a stash whose message says whose they are
#   3. the next runner starts from a tree with none of them in it
#   4. the task that owns them is handed them back, with the restore command,
#      in its own log
#   5. restoring them brings back exactly what was there, byte for byte
#   6. the queue's own bookkeeping is never stashed
#   7. a file the user had already changed before the runner started is never
#      touched
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO"

# The throwaway repo is a SUBDIRECTORY of the sandbox, and the drill's own
# scratch (the fake runner, what it records) sits beside it rather than inside
# it. Anything inside the repo is dirty working tree as far as the loop is
# concerned, and the loop's whole job here is to stash dirty working tree.
TOP=$(mktemp -d -t photonz-leftovers)
S="$TOP/repo"
BIN="$TOP/bin"; STATE="$TOP/state"
trap 'rm -rf "$TOP"' EXIT
mkdir -p "$BIN" "$STATE" "$S/queue" "$S/Sources"

# ---- the throwaway repo -----------------------------------------------------
git -C "$S" init -q .
git -C "$S" config user.email drill@photonz.local
git -C "$S" config user.name "leftovers drill"
echo 'let base = 1' > "$S/Sources/a.swift"
echo 'the user is editing this' > "$S/README.md"
echo 'keep' > "$S/queue/keep.txt"
git -C "$S" add -A
git -C "$S" commit -qm base

# The user's own edit, made before the loop ever starts. It must survive.
echo 'the user is editing this, and half way through a sentence' > "$S/README.md"

# ---- the fake runner --------------------------------------------------------
# Call 1: dirties two files and exits 0 WITHOUT finalizing its task, which is
#         exactly how a runner that runs out of turn ends.
# Call 2+: records the working tree it was handed, then finishes properly.
cat > "$BIN/claude" <<'FAKE'
#!/bin/zsh
prompt="${@[-1]}"
n=$(( $(cat "$DRILL_STATE/calls" 2>/dev/null || echo 0) + 1 )); echo $n > "$DRILL_STATE/calls"
SBOX="${PHOTONZ_QUEUE_DIR:h}"
file="${prompt##*TASK FILE: }"
id=$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).id)' "$file" 2>/dev/null || echo "-")
# What this runner was handed: the tree as it found it, and the task as it found it.
git -C "$SBOX" status --porcelain > "$DRILL_STATE/tree-at-start-$n.txt"
cp "$file" "$DRILL_STATE/task-at-start-$n.json" 2>/dev/null
echo '{"type":"system","subtype":"init","session_id":"leftovers-drill"}'
if (( n == 1 )); then
  printf 'let base = 1\nlet halfBuilt = "written by run 1"\n' > "$SBOX/Sources/a.swift"
  printf 'brand new and never committed\n' > "$SBOX/Sources/b.swift"
  echo '{"type":"assistant","message":{"content":[{"type":"text","text":"ran out of turn mid-edit"}]}}'
  exit 0
fi
node queue/bin/queue.mjs status "$id" done "drill: finished" >/dev/null
echo '{"type":"result","subtype":"success","result":"done"}'
exit 0
FAKE
chmod +x "$BIN/claude"

export PATH="$BIN:$PATH"
export PHOTONZ_QUEUE_DIR="$S/queue"
export DRILL_STATE="$STATE"
export PHOTONZ_BACKOFF_STEPS="1,1,1"
export PHOTONZ_MAX_ITERS=4
export PHOTONZ_LOOP_RELOAD=0
mkdir -p "$S/queue/digests"; : > "$S/queue/digests/$(date +%F).md"   # skip the digest pass

node queue/bin/queue.mjs add "Drill task that runs out of turn" p1-high "drill" >/dev/null
node queue/bin/queue.mjs add "Drill task that comes after it" p2-normal "drill" >/dev/null

echo "[drill] running the real go loop; the first runner dies with a dirty tree..."
queue/bin/go-loop.sh > "$TOP/drill.log" 2>&1
export DRILL_LOG="$TOP/drill.log"
export DRILL_SANDBOX="$S"

node --input-type=module -e '
const fs = await import("node:fs");
const cp = await import("node:child_process");
const S = process.env.DRILL_SANDBOX;
const q = process.env.PHOTONZ_QUEUE_DIR;
const state = process.env.DRILL_STATE;
const log = fs.readFileSync(process.env.DRILL_LOG, "utf8");
const git = (...a) => cp.execFileSync("git", ["-C", S, ...a], { encoding: "utf8" });
const tasks = ["p0-critical","p1-high","p2-normal","p3-low"].flatMap((p) => {
  const d = q + "/tasks/" + p;
  return fs.existsSync(d) ? fs.readdirSync(d).map((f) => JSON.parse(fs.readFileSync(d + "/" + f, "utf8"))) : [];
});
const recs = fs.existsSync(q + "/leftovers")
  ? fs.readdirSync(q + "/leftovers").filter((f) => f.endsWith(".json") && !f.startsWith(".")).map((f) => JSON.parse(fs.readFileSync(q + "/leftovers/" + f, "utf8")))
  : [];
let failed = 0;
const check = (name, ok, detail) => {
  console.log((ok ? "  PASS  " : "  FAIL  ") + name + (detail ? "\n          " + detail : ""));
  if (!ok) failed++;
};

const owner = tasks.find((t) => t.title === "Drill task that runs out of turn");
const rec = recs[0];

check("the loop noticed and said so in its log, naming the task",
  /2 files left changed by Drill task that runs out of turn/.test(log),
  (log.match(/left changed by.*/) || ["no such line in the log"])[0]);

check("exactly one leftovers record, for the task that made them",
  recs.length === 1 && rec && rec.task === owner.id && rec.count === 2,
  JSON.stringify(recs.map((r) => ({ task: r.task, count: r.count, state: r.state }))));

check("both files are named in it",
  !!rec && ["Sources/a.swift", "Sources/b.swift"].every((f) => rec.files.includes(f)),
  JSON.stringify(rec && rec.files));

check("they were put aside, not left in the tree", !!rec && rec.state === "stashed" && !!rec.stash,
  JSON.stringify(rec && { state: rec.state, why: rec.why }));

const stashes = git("stash", "list").trim().split("\n").filter(Boolean);
check("the stash message says whose they are",
  stashes.length === 1 && stashes[0].includes(owner.id),
  stashes.join(" | ") || "no stash");

const tree2 = fs.readFileSync(state + "/tree-at-start-2.txt", "utf8");
check("the NEXT runner started from a tree with none of them in it",
  !/Sources\/a\.swift|Sources\/b\.swift/.test(tree2),
  "tree at start of run 2:\n          " + tree2.trim().split("\n").join("\n          "));

const notes = (owner.log || []).map((e) => e.note);
check("the owning task was told what it left behind",
  notes.some((n) => /ran out of turn with 2 file\(s\) still changed/.test(n)),
  JSON.stringify(notes.filter((n) => /still changed/.test(n))));
check("...and was handed them back when it was claimed again, with the restore command",
  notes.some((n) => /a previous attempt at this task left 2 file\(s\)/.test(n) && n.includes("git stash apply " + rec.stash)),
  JSON.stringify(notes.filter((n) => /previous attempt/.test(n))));
check("the record is marked handed once its task has it", !!rec && !!rec.handed, JSON.stringify(rec && rec.handed));

// Restoring has to bring back exactly what run 1 had written.
git("stash", "apply", rec.stash);
check("restoring brings back exactly what was there",
  fs.readFileSync(S + "/Sources/a.swift", "utf8") === "let base = 1\nlet halfBuilt = \"written by run 1\"\n" &&
  fs.readFileSync(S + "/Sources/b.swift", "utf8") === "brand new and never committed\n",
  JSON.stringify(fs.readFileSync(S + "/Sources/a.swift", "utf8")));

// The queue writes itself constantly and no task owns it; stashing it would
// throw away queue state mid-write.
// --include-untracked so the check reads the new files too: a plain
// `stash show` only lists the tracked half, which would pass without looking.
const stashed = git("stash", "show", "--include-untracked", "--name-only", rec.stash).trim().split("\n").filter(Boolean);
check("the queue’s own bookkeeping was never stashed",
  !recs.some((r) => r.files.some((f) => f === "queue" || f.startsWith("queue/"))) &&
  stashed.length === 2 && !stashed.some((f) => f.startsWith("queue")),
  stashed.join(", "));

check("a file the user had already changed was left alone",
  fs.readFileSync(S + "/README.md", "utf8") === "the user is editing this, and half way through a sentence\n" &&
  !rec.files.includes("README.md"),
  JSON.stringify(fs.readFileSync(S + "/README.md", "utf8")));

const second = tasks.find((t) => t.title === "Drill task that comes after it");
check("the task after it started clean too and finished",
  second && second.status === "done" &&
  !/Sources\/a\.swift|Sources\/b\.swift/.test(fs.readFileSync(state + "/tree-at-start-3.txt", "utf8")),
  second ? second.status : "missing");

console.log(failed ? "\n[drill] " + failed + " check(s) failed" : "\n[drill] all checks passed");
process.exit(failed ? 1 : 0);
'
RC=$?
(( RC != 0 )) && { echo "[drill] loop log:"; sed -n 1,80p "$TOP/drill.log"; }
(( RC != 0 )) && exit $RC

# ---- scenario 2: the stash itself cannot be taken ---------------------------
# Putting the files aside is the good outcome, not a guaranteed one: a repo
# mid-rebase, or one with no commit to stash against, refuses. That case is
# LOUDER, not quieter, because the files really are still sitting in the tree
# for the next task to commit. This is the one deterministic way to make git
# refuse: a repository whose first commit does not exist yet.
TOP2=$(mktemp -d -t photonz-leftovers-stuck)
trap 'rm -rf "$TOP" "$TOP2"' EXIT
S2="$TOP2/repo"
mkdir -p "$S2/queue" "$S2/Sources"
git -C "$S2" init -q .
git -C "$S2" config user.email drill@photonz.local
git -C "$S2" config user.name "leftovers drill"

echo "[drill] scenario 2: a repo where git refuses to stash..."
PHOTONZ_QUEUE_DIR="$S2/queue" node queue/bin/queue.mjs add "Drill task in a repo that cannot stash" p1-high "drill" >/dev/null
TASK2=drill-task-in-a-repo-that-cannot-stash
PHOTONZ_QUEUE_DIR="$S2/queue" node queue/bin/leftovers.mjs snapshot "$TOP2/before.json" >/dev/null
echo 'half built' > "$S2/Sources/c.swift"
STUCK_OUT=$(PHOTONZ_QUEUE_DIR="$S2/queue" node queue/bin/leftovers.mjs settle "$TOP2/before.json" task "$TASK2" failed "Drill task in a repo that cannot stash")

STUCK_OUT="$STUCK_OUT" S2="$S2" TASK2="$TASK2" PHOTONZ_QUEUE_DIR="$S2/queue" node --input-type=module -e '
const fs = await import("node:fs");
const q = process.env.PHOTONZ_QUEUE_DIR;
const lib = await import(process.cwd() + "/queue/bin/queue-lib.mjs");
let failed = 0;
const check = (name, ok, detail) => {
  console.log((ok ? "  PASS  " : "  FAIL  ") + name + (detail ? "\n          " + detail : ""));
  if (!ok) failed++;
};
const rec = lib.readLeftovers()[0];
const task = lib.findTask(process.env.TASK2);
check("it is recorded as still in the tree, not as put aside",
  !!rec && rec.state === "left" && !rec.stash && !!rec.why, JSON.stringify(rec && { state: rec.state, why: rec.why }));
check("the loop says plainly that the next task would commit them",
  /could NOT be put aside/.test(process.env.STUCK_OUT) && /still in the working tree/.test(process.env.STUCK_OUT),
  process.env.STUCK_OUT);
check("the file really is still there", fs.existsSync(process.env.S2 + "/Sources/c.swift"));
check("the owning task is told, in its own log",
  (task.log || []).some((e) => /could not be put aside/.test(e.note) && /Sources\/c\.swift/.test(e.note)),
  JSON.stringify((task.log || []).map((e) => e.note).slice(-1)));
check("the dashboard is told it is stuck, not merely open",
  lib.leftoversState().open === 1 && lib.leftoversState().stuck === 1,
  JSON.stringify(lib.leftoversState()));
console.log(failed ? "\n[drill] scenario 2: " + failed + " check(s) failed" : "\n[drill] scenario 2: all checks passed");
process.exit(failed ? 1 : 0);
'
exit $?
