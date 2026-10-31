#!/bin/bash
# bench.sh <label> <gentle 0|1> : start llama-server, time one ~3000-token request with a GPU blit probe beside it.
set -u
M="$HOME/Library/Application Support/Photonz/Models"
BIN="/Users/dzearing/git/photonz/dist/Photonz Probe.app/Contents/Helpers/AskModel/llama-server"
PORT=18977
ARGS=(--model "$M/Qwen3.8-27B-Q4_K_M.gguf" --mmproj "$M/mmproj-Qwen3.8-27B-Q8_0.gguf" --spec-type draft-mtp --model-draft "$M/mtp-Qwen3.8-27B-Q4_0.gguf"
  --host 127.0.0.1 --port $PORT --ctx-size 32768 --n-gpu-layers 999 --jinja --parallel 1 --no-webui)
PRE=()
if [[ $2 == 1 ]]; then ARGS+=(--ubatch-size 128 --batch-size 512 --prio -1 --poll 0 --threads 4); PRE=(/usr/sbin/taskpolicy -b); fi
T0=$SECONDS
${PRE[@]+"${PRE[@]}"} "$BIN" "${ARGS[@]}" > /tmp/photonz-bench/server-$1.log 2>&1 &
S=$!; trap "kill $S 2>/dev/null" EXIT
for i in $(seq 1 600); do curl -sf -m 1 http://127.0.0.1:$PORT/health >/dev/null && break; sleep 0.5; done
echo "$1: loaded in $((SECONDS - T0)) s"
/tmp/photonz-bench/gpulat 8 | sed "s/^/$1 idle-loaded: /"
/tmp/photonz-bench/gpulat 14 > /tmp/photonz-bench/lat-$1.txt &
L=$!
curl -s -m 300 http://127.0.0.1:$PORT/v1/chat/completions -H 'Content-Type: application/json' -d @/tmp/photonz-bench/req.json \
  | python3 -c 'import json,sys; t=json.load(sys.stdin)["timings"]; print("%s: prompt %d tokens at %.1f t/s, generated %d at %.1f t/s" % (sys.argv[1], t["prompt_n"], t["prompt_per_second"], t["predicted_n"], t["predicted_per_second"]))' "$1"
wait $L; sed "s/^/$1 while working: /" /tmp/photonz-bench/lat-$1.txt
kill $S; wait $S 2>/dev/null
for i in $(seq 1 50); do kill -0 $S 2>/dev/null || break; sleep 0.2; done
pgrep -f "llama-server.*--port $PORT" && echo "!! still running" || echo "$1: server gone"
