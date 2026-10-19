#!/bin/bash
# The Photonz MCP server, as an agent's MCP client runs it
# (docs/design/agent-mcp.md). Registered by Scripts/install-mcp.sh.
#
# Builds the small bridge program the first time and whenever its own source
# changes (in .build-mcp, apart from the app's build, so it never waits on it),
# then runs it. The bridge finds the running Photonz over its socket and copies
# MCP lines both ways; the app answers everything.
#
#   PHOTONZ_APP=probe|dev|release|<bundle id>   which app to reach (see the doc)
#
# Only the protocol may reach stdout: everything else goes to stderr.
#
#   Scripts/photonz-mcp.sh --build-only   build the bridge and stop
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH="$REPO/.build-mcp"
BIN="$SCRATCH/release/PhotonzMCP"

stale() {
  [[ -x "$BIN" ]] || return 0
  [[ -n "$(find "$REPO/Sources/PhotonzMCP" "$REPO/Sources/PhotonzAgentLink" "$REPO/Package.swift" \
             -newer "$BIN" -print -quit 2>/dev/null)" ]]
}

if stale; then
  echo "photonz-mcp: building the bridge (once)..." >&2
  (cd "$REPO" && swift build -c release --product PhotonzMCP --scratch-path "$SCRATCH" >&2)
fi
[[ "${1:-}" == "--build-only" ]] && exit 0

# The repo's own builds, for when LaunchServices does not know them yet. A go
# loop runner that named no app gets the probe (the bridge decides the same).
APP_CHOICE="${PHOTONZ_APP:-}"
[[ -z "$APP_CHOICE" && -n "${GO_LOOP_PID:-}" ]] && APP_CHOICE=probe
if [[ -z "${PHOTONZ_APP_PATH:-}" ]]; then
  case "$APP_CHOICE" in
    probe) [[ -d "$REPO/dist/Photonz Probe.app" ]] && export PHOTONZ_APP_PATH="$REPO/dist/Photonz Probe.app" ;;
    dev)   [[ -d "$REPO/dist/Photonz Dev.app" ]] && export PHOTONZ_APP_PATH="$REPO/dist/Photonz Dev.app" ;;
  esac
fi
exec "$BIN"
