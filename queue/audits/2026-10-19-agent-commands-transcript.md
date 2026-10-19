# Agent MCP, slice 2: the try path, 2026-10-19

A fresh Claude Code session (`claude -p`, only the Photonz probe server configured, every other MCP server off) while the probe had `Demo recording.mp4` (15 seconds, 1280x800) open at Next defaults. A one-off walk opened the recording, held for the session, then pressed Command Z through Edit > Undo and photographed the window at each stage (pictures beside this file).

Command:

```
claude -p --mcp-config mcp.json --strict-mcp-config --allowedTools 'mcp__photonz-probe__*' --disallowedTools Bash \
  'In Photonz, list the timeline commands, then cut the clip at 5 seconds.'
```

## Transcript

**Tool call** `list_documents` `{}`

Result: `[{"canRedo":false,"canUndo":false,"durationSeconds":15,"file":"/tmp/photonz-agent-try/Demo recording.mp4","front":true,"height":800,"id":"d1","kind":"video","title":"Demo recording.mp4","width":1280}]`

**Tool call** `list_commands` `{"area": "timeline"}`

Result: `[{"area":"timeline","menu":"Sequence","name":"play_pause","needs":"a video","ready":true,"title":"Play"},{"area":"timeline","menu":"Sequence","name":"play_in_to_out","needs":"an in and an out set","ready":false,"title":"Play In to Out"},{"area":"timeline","menu":"Sequence","name":"play_backward","needs":"a video","ready":true,"title":"Play Backward"},{"area":"timeline","menu":"Sequence","name":"stop","needs":"the video playing","ready":false,"title":"Stop"},{"area":"timeline","menu":"Sequence","name":"play_forward","needs":"a video","ready":true,"title":"Play Forward"},{"area":"timeline","menu":"Sequence","name":"go_to_previous_edit","needs":"an edit before the playhead","ready":false,"title ...`

**Tool call** `read_document` `{}`

Result: `{"canRedo":false,"canUndo":false,"canvas":{"height":800,"width":1280},"durationSeconds":15,"file":"/tmp/photonz-agent-try/Demo recording.mp4","id":"d1","kind":"video","layerCount":1,"layers":[{"frame":{"height":800,"width":1280,"x":0,"y":0},"id":"F36FF72F-D2C6-4E6B-AF95-9A0CDB9C8628","kind":"clip","name":"Demo recording","pixels":{"height":800,"width":1280},"time":{"inSeconds":0,"outSeconds":15}}],"playheadSeconds":0,"title":"Demo recording.mp4","tracks":[{"clips":[{"inSeconds":0,"kind":"clip","layer":"F36FF72F-D2C6-4E6B-AF95-9A0CDB9C8628","name":"Demo recording","outSeconds":15}],"id":"F36FF72F-D2C6-4E6B-AF95-9A0CDB9C8628","kind":"video","name":"V1"},{"clips":[],"id":"0AD10000-0000-4000-800 ...`

**Tool call** `run_command` `{"command": "split_at_playhead", "arguments": {"seconds": 5, "layers": ["F36FF72F-D2C6-4E6B-AF95-9A0CDB9C8628"]}}`

Result: `{"canRedo":false,"canUndo":true,"changed":true,"picked":["F36FF72F-D2C6-4E6B-AF95-9A0CDB9C8628"],"playheadSeconds":5,"ran":"split_at_playhead","title":"Split at Playhead"}`

**Tool call** `read_document` `{}`

Result: `{"canRedo":false,"canUndo":true,"canvas":{"height":800,"width":1280},"cuts":[{"atSeconds":5,"from":"Demo recording","to":"Demo recording"}],"durationSeconds":15,"file":"/tmp/photonz-agent-try/Demo recording.mp4","id":"d1","kind":"video","layerCount":1,"layers":[{"frame":{"height":800,"width":1280,"x":0,"y":0},"id":"F36FF72F-D2C6-4E6B-AF95-9A0CDB9C8628","kind":"clip","name":"Demo recording","pixels":{"height":800,"width":1280},"time":{"inSeconds":0,"outSeconds":15}}],"playheadSeconds":5,"title":"Demo recording.mp4","tracks":[{"clips":[{"inSeconds":0,"kind":"clip","layer":"F36FF72F-D2C6-4E6B-AF95-9A0CDB9C8628","name":"Demo recording","outSeconds":15,"pieces":2}],"id":"F36FF72F-D2C6-4E6B-AF95-9 ...`

**Answer**

I cut "Demo recording.mp4" at 5 seconds. Reading the document back, there's now a cut at 5.0s and the 15-second clip on V1 is in 2 pieces (0–5s and 5–15s). It's one undo step if you want it back.

**Timeline commands** (about 95; the ones marked ✓ could run before the cut):

- **Sequence, playback:** Play ✓, Play Backward ✓, Play Forward ✓, Stop, Play In to Out
- **Sequence, navigation:** Go to Next Edit ✓, Go to Previous Edit, Go to In/Out, Go to Next/Previous Marker
- **Sequence, in/out and markers:** Set In ✓, Set Out ✓, Mark Clip ✓, Add Marker ✓, Clear In / Out / Both, Remove Marker, Clear All Markers
- **Sequence, range edits:** Extract, Lift, Split at Range Edges, Merge into One Clip, Split Everything at Playhead, Snap in Timeline ✓ (on)
- **Sequence, captions:** Add Captions, Add Captions for Range, Cancel, Earlier/Later, Clear, Reset; also Revert to Original
- **Sequence > Track:** Add Video ✓ / Audio ✓ / Captions ✓ Track, Add Track Above ✓ / Below ✓, Hide ✓ / Solo ✓ / Lock ✓ / Mute, Group ✓ / Ungroup, Delete Track ✓, Delete Empty Tracks
- **Clip, editing:** Split at Playhead, Delete This Piece, Ripple Delete, Ripple Trim Start/End to Playhead, Nudge Earlier/Later, Break Apart, Select Forward ✓, Roll Edit to Playhead, Join Through Edit
- **Clip, speed:** Speed ✓ (25% to 3000%), Add Speed Stop ✓, Delete Speed Stop, Reset Ramp
- **Clip, framing:** Add Zoom ✓, Suggest Zooms, Punch In, Pull Back Out, Reset Reframe, Show Picture
- **Clip, clicks:** Hide Click at Playhead, Next Click, Show Click Effects
- **Clip, transitions:** Fade In/Out ✓, Transition at Cut (dissolve, dip to black/white, push, wipe, cube and more), Hard Cut, Length, Curve, Reset to Default Length, Apply to Every Cut, Set as / Apply Default Transition
- **Clip, audio:** Detach / Re-attach Audio, Flatten Level, Normalize (peaks to -1 dB, web or podcast loudness), Clean Noise, Reset Gain
- **Clip > Animate:** Start / End at Playhead, Animate In/Out (fade, slide, pop, scale), Key at Playhead, Remove Key, Go to Next/Previous Key, Curve the Path, Select All Keys, Replay Title

Before the cut, Split at Playhead showed as not ready because the playhead was at 0. Passing it the 5-second time and the clip's id made it run.

Now that there's a cut, Transition at Cut should apply to it if you want one.

## Then, in the app

One Command Z (Edit > Undo, through the live menu bar) put the recording back as one clip: the walk logged `command+z reached Edit ▸ Undo and it ran`, with nothing left to undo afterwards, so the agent's call (move the playhead, pick the clip, split it) was exactly one step. Pictures: `2026-10-19-agent-commands-2-after-the-agent.png` (two pieces, cut at 0:05, Piece 1 of 2) and `2026-10-19-agent-commands-3-after-one-command-z.png` (one clip, the title back to "saved").
