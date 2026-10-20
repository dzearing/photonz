#!/bin/bash
# The scored test set for what Ask and the Photonz skill make, so a change to
# the prompt, the skill or the tools is kept or thrown away on a number
# (Scripts/ask-eval/README.md).
#
#   Scripts/ask-eval.sh run --engine ask|skill --tag "<what changed>"
#   Scripts/ask-eval.sh compare [<run>] [--with <run>|best]
#   Scripts/ask-eval.sh history
#   Scripts/ask-eval.sh calibrate
#
# Runs one case at a time on the probe (never the dev app) and quits it after
# each case. Needs Ollama for --engine ask, and the claude command for the
# skill engine and the judge.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
exec node "$REPO/Scripts/ask-eval/eval.mjs" "$@"
