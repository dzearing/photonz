# Agent MCP, slice 1: the try path, 2026-10-19

A fresh Claude Code session (`claude -p`, only the Photonz probe server configured, every other MCP server off), with the probe app open on `Demo recording.mp4` (a 15 second, 1280x800 test recording with a running clock in its top left corner). The prompt was the acceptance item's own words.

Command:

```
claude -p --mcp-config mcp.json --strict-mcp-config --allowedTools 'mcp__photonz-probe__*' --disallowedTools Bash \
  'what is open in Photonz, and show me the frame 10 seconds in'
```

`mcp.json` ran `PHOTONZ_APP=probe Scripts/photonz-mcp.sh`. The picture the session was handed is `2026-10-19-agent-mcp-frame-at-10s.png` beside this file.

## Transcript

**Tool call** `list_documents` `{}`

Result: `[{"canRedo":false,"canUndo":false,"durationSeconds":15,"file":"/tmp/photonz-agent-try/Demo recording.mp4","front":true,"height":800,"id":"d1","kind":"video","title":"Demo recording.mp4","width":1280}]`

**Tool call** `video_frame` `{"document": "d1", "seconds": 10}`

Result: `Demo recording.mp4 at 0:10.0 (1024x640 PNG)` / (a PNG)

**Tool call** `read_document` `{"document": "d1"}`

Result: `{"canRedo":false,"canUndo":false,"canvas":{"height":800,"width":1280},"durationSeconds":15,"file":"/tmp/photonz-agent-try/Demo recording.mp4","id":"d1","kind":"video","layerCount":1,"layers":[{"frame":{"height":800,"width":1280,"x":0,"y":0},"id":"1C9600C4-0EE9-43AC-82E3-E98786D5EC7D","kind":"clip","name":"Demo recording","pixels":{"height":800,"width":1280},"time":{"inSeconds":0,"outSeconds":15}}],"playheadSeconds":0,"title":"Demo recording.mp4","tracks":[{"clips":[{"inSeconds":0,"kind":"clip","layer":"1C9600C4-0EE9-43AC-82E3-E98786D5EC7D","name":"Demo recording","outSeconds":15}],"id":"1C9600C4-0EE9-43AC-82E3-E98786D5EC7D","kind":"video","name":"V1"},{"clips":[],"id":"0AD10000-0000-4000-800 ...`

**Tool call** `video_frame` `{"document": "d1", "seconds": 10.02, "region": {"x": 0, "y": 0, "width": 120, "height": 40}, "maxSize": 240}`

Result: `Demo recording.mp4 at 0:10.0 (120x40 PNG)` / (a PNG)

**Tool call** `video_frame` `{"document": "d1", "seconds": 10.04, "region": {"x": 0, "y": 0, "width": 120, "height": 40}, "maxSize": 240}`

Result: `Demo recording.mp4 at 0:10.0 (120x40 PNG)` / (a PNG)

**Answer**

Photonz has one document open, and it's the one in front:

- **Demo recording.mp4** (`/tmp/photonz-agent-try/Demo recording.mp4`)
- Video, 1280×800, 15 seconds long
- One video track (V1) with a single clip running 0–15s, plus an empty audio track
- Nothing to undo or redo, so it hasn't been edited. The playhead is at 0:00.

**The frame at 0:10:**

It's a test pattern: six vertical color bars (red, green, yellow, blue, magenta, cyan). A rainbow line runs diagonally from bottom-left to top-right, and there's a checkerboard patch at the lower right, dotted lines at the upper right, and a few small markers.

One thing to know: the timecode stamped into the video reads **00:00:09.967, frame 299**, not 10.000. I checked more times to see why:

| Requested | Frame shown |
|---|---|
| 10.00s | 299 (09.967) |
| 10.02s | 299 (09.967) |
| 10.04s | 300 (10.000) |

So the tool looks about one frame (roughly 33ms at 30fps) behind the requested time. The cause could be how it rounds, how the file's timestamps start, or how that overlay numbers frames; I haven't found which. If you need the exact frame-300 image, ask for 10.04s. I can also look into the offset if it matters for what you're doing.

