#!/bin/bash
# Registers the Photonz MCP server with Claude Code, for this user, in one
# command (docs/design/agent-mcp.md):
#
#   Scripts/install-mcp.sh           "photonz": whichever Photonz is running
#                                    (Dev, then the release app, then Probe);
#                                    starts the release app when none is
#   Scripts/install-mcp.sh --probe   "photonz-probe": the task loop's probe app
#   Scripts/install-mcp.sh --remove  takes both back out
#
# Photonz must be running the Next release with "Agents can work in Photonz"
# on in its Experiments window (on by default in Next).
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
command -v claude >/dev/null || { echo "!! The claude command is not on PATH." >&2; exit 1; }

NAME=photonz
ENVS=()
case "${1:-}" in
  --probe) NAME=photonz-probe; ENVS=(-e PHOTONZ_APP=probe) ;;
  --remove)
    claude mcp remove --scope user photonz >/dev/null 2>&1 || true
    claude mcp remove --scope user photonz-probe >/dev/null 2>&1 || true
    echo "==> Removed the Photonz MCP servers."
    exit 0 ;;
  "") ;;
  *) echo "usage: Scripts/install-mcp.sh [--probe|--remove]" >&2; exit 1 ;;
esac

"$REPO/Scripts/photonz-mcp.sh" --build-only
claude mcp remove --scope user "$NAME" >/dev/null 2>&1 || true
claude mcp add --scope user "$NAME" ${ENVS[@]+"${ENVS[@]}"} -- "$REPO/Scripts/photonz-mcp.sh"
echo "==> Installed \"$NAME\". Start a new Claude Code session and ask: what is open in Photonz?"
