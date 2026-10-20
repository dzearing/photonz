#!/bin/bash
# Registers the Photonz MCP server with Claude Code, for this user, and puts
# the Photonz skill beside it, in one command (docs/design/agent-mcp.md):
#
#   Scripts/install-mcp.sh           "photonz": whichever Photonz is running
#                                    (Dev, then the release app, then Probe);
#                                    starts the release app when none is
#   Scripts/install-mcp.sh --probe   "photonz-probe": the task loop's probe app
#   Scripts/install-mcp.sh --remove  takes both servers and the skill back out
#
# The skill (plugin/skills/photonz) is linked, not copied, into the user's
# skills folder, so it follows the repo. The same folder is a Claude Code
# plugin (skill plus server): `claude --plugin-dir <repo>/plugin` loads both
# for one session without installing anything.
#
# Photonz must be running the Next release with "Agents can work in Photonz"
# on in its Experiments window (on by default in Next).
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
command -v claude >/dev/null || { echo "!! The claude command is not on PATH." >&2; exit 1; }

NAME=photonz
ENVS=()
SKILLS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills"
case "${1:-}" in
  --probe) NAME=photonz-probe; ENVS=(-e PHOTONZ_APP=probe) ;;
  --remove)
    claude mcp remove --scope user photonz >/dev/null 2>&1 || true
    claude mcp remove --scope user photonz-probe >/dev/null 2>&1 || true
    # Only our own link: a folder somebody made by hand is theirs.
    [[ -L "$SKILLS/photonz" ]] && rm "$SKILLS/photonz"
    echo "==> Removed the Photonz MCP servers and the Photonz skill."
    exit 0 ;;
  "") ;;
  *) echo "usage: Scripts/install-mcp.sh [--probe|--remove]" >&2; exit 1 ;;
esac

"$REPO/Scripts/photonz-mcp.sh" --build-only
claude mcp remove --scope user "$NAME" >/dev/null 2>&1 || true
claude mcp add --scope user "$NAME" ${ENVS[@]+"${ENVS[@]}"} -- "$REPO/Scripts/photonz-mcp.sh"
mkdir -p "$SKILLS"
if [[ -e "$SKILLS/photonz" && ! -L "$SKILLS/photonz" ]]; then
  echo "!! $SKILLS/photonz already exists and is not this repo's link; the skill was left alone." >&2
else
  ln -sfn "$REPO/plugin/skills/photonz" "$SKILLS/photonz"
fi
echo "==> Installed \"$NAME\" and the Photonz skill. Start a new Claude Code session and ask: what is open in Photonz?"
