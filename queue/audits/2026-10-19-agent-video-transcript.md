# Agent MCP, slice 4: the montage scenario, 2026-10-19

The user's scenario 1, from fresh Claude Code sessions (`claude -p`, only the Photonz probe server configured, every other MCP server off, no Bash, Write or Edit), the probe at Next defaults, History the user's own folder (read only: the five newest recordings, Oct 10 to Oct 19, 3 to 135 seconds each, 3456 by 2234).

```
claude -p --mcp-config mcp.json --strict-mcp-config --allowedTools 'mcp__photonz-probe__*' \
  --disallowedTools Bash Write Edit '<prompt>'
```

`mcp.json` ran `PHOTONZ_APP=probe Scripts/photonz-mcp.sh`. The prompt is the user's words with one sentence added so the session leaves a file: "I made 5 clips in my history. Take the last 5, and create a video montage which has a title page, and subtitle pages per clip with nice consistent layout and transitions. I want to see clips with recommended zooms. Each subtitle should show Case N where n is the clip number (1 through 5). When it looks right, export it as an MP4 to /tmp/photonz-montage/montage.mp4."

## Three runs

| Run | Build | Result | What it found, and what happened to it |
| --- | --- | --- | --- |
| 1 | 79e5acf0 before its last fixes | One video, a 3:00 MP4, 15 zooms, 10 dissolves; 68 turns, 4m42s | Styles kept their sample lines ("Chapter 2", "Session 3", "Design Engineer"); a page could not go in front of another page; a recommended zoom was reported ending before it started; add_title did not say a busy track sent it to a new one; the Keynote Clean starfield draws hard rectangles. The first four fixed in 79e5acf0, the last filed as `the-keynote-clean-title-page-draws-its-starfield` (reproduced). |
| 2 | 79e5acf0 | One video, a 3:00 MP4 | A page fading in over a clip's end came back from video_frame as pure white (it was see-through; the MP4 is black there), so the agent built a black backdrop to hide it; trim could not lengthen a shape. Both fixed in 4d35f1a1. |
| 3 | 4d35f1a1 | One video, a 3:00 MP4 (366 MB, 3456 by 2234), no workarounds | Transcript below. |

The film in the audit (`2026-10-19-agent-video-montage.mp4`) is run 3's document written by the export tool at 480p, small, then re-encoded with ffmpeg to 6.4 MB so it fits in the repository. The full file was 366 MB and is not kept.

## Run 3

Result: `(picture) (picture) (picture) (picture) (picture) (picture) (picture) (picture) (picture) (picture) (picture) (picture) (picture) (picture) (picture) (picture)`

**Tool call** `list_history` `{"limit": 10}`

Result: `[{"file":"/Users/dzearing/Pictures/Screenshots/Screenshot 2026-10-19 at 08.35.22.png","index":0,"kind":"picture","name":"Screenshot 2026-10-19 at 08.35.22.png","taken":"2026-10-19T15:38:41Z"},{"file":"/Users/dzearing/Pictures/Screenshots/Screenshot 2026-10-19 at 08.31.51.png","index":1,"kind":"picture","name":"Screenshot 2026-10-19 at 08.31.51.png","taken":"2026-10-19T15:31:51Z"},{"file":"/Users/dzearing/Pictures/Screenshots/Screenshot 2026-10-19 at 08.17.22.png","index":2,"kind":"picture","name":"Screenshot 2026-10-19 at 08.17.22.png","taken":"2026-10-19T15:17:22Z"},{"file":"/Users/dzearing/P …`

**Tool call** `list_documents` `{}`

Result: `[]`

**Tool call** `list_history` `{"limit": 100}`

Result: `[{"file":"/Users/dzearing/Pictures/Screenshots/Screenshot 2026-10-19 at 08.35.22.png","index":0,"kind":"picture","name":"Screenshot 2026-10-19 at 08.35.22.png","taken":"2026-10-19T15:38:41Z"},{"file":"/Users/dzearing/Pictures/Screenshots/Screenshot 2026-10-19 at 08.31.51.png","index":1,"kind":"picture","name":"Screenshot 2026-10-19 at 08.31.51.png","taken":"2026-10-19T15:31:51Z"},{"file":"/Users/dzearing/Pictures/Screenshots/Screenshot 2026-10-19 at 08.17.22.png","index":2,"kind":"picture","name":"Screenshot 2026-10-19 at 08.17.22.png","taken":"2026-10-19T15:17:22Z"},{"file":"/Users/dzearing/P …`

> The five most recent recordings in History (screenshots skipped) are indices 56, 53, 52, 26, 15. They span Oct 10–19. I'll put them in recording order, oldest = Case 1.

**Tool call** `new_video` `{"clips": [{"historyIndex": 56}, {"historyIndex": 53}, {"historyIndex": 52}, {"historyIndex": 26}, {"historyIndex": 15}]}`

Result: `{"clips":[{"clip":"64BB82A0-B223-4109-82C4-AFCAF9FE7F5D","durationSeconds":7.583,"inSeconds":0,"name":"Recording 2026-10-10 at 19.44.21","outSeconds":7.583,"track":"V1"},{"clip":"E45CB55E-A33F-495E-BBF9-5F4BB9B8AF5C","durationSeconds":10.573,"inSeconds":7.583,"name":"Recording 2026-10-10 at 20.14.54","outSeconds":10.573,"track":"V1"},{"clip":"2A660E16-F370-4B19-99A8-7F9B6A5B0AD8","durationSeconds":145.165,"inSeconds":10.573,"name":"Recording 2026-10-11 at 05.12.59","outSeconds":145.165,"track":"V1"},{"clip":"96F9E1AC-F69E-4780-B2A4-490F3B613976","durationSeconds":150.978,"inSeconds":145.165,"n …`

**Tool call** `read_document` `{"document": "d1"}`

Result: `{"canRedo":false,"canUndo":true,"canvas":{"height":2234,"width":3456},"cuts":[{"atSeconds":7.583,"from":"Recording 2026-10-10 at 19.44.21","to":"Recording 2026-10-10 at 20.14.54"},{"atSeconds":10.573,"from":"Recording 2026-10-10 at 20.14.54","to":"Recording 2026-10-11 at 05.12.59"},{"atSeconds":145.165,"from":"Recording 2026-10-11 at 05.12.59","to":"Recording 2026-10-18 at 15.48.58"},{"atSeconds":150.978,"from":"Recording 2026-10-18 at 15.48.58","to":"Recording 2026-10-19 at 07.50.53"}],"durationSeconds":156.496,"id":"d1","kind":"video","layerCount":5,"layers":[{"frame":{"height":2234,"width": …`

**Tool call** `list_titles` `{"document": "d1"}`

Result: `{"nameCard":["Split Wipe","Minimal Underline","Pill Card"],"titlePage":["Keynote Section","Film Super","Session Title","Chapter Card","Editorial","Sessions Stage","Launch","Gradient Word","Big Number","End Card","Keynote Clean","Soft Gradient Glass","Kinetic Bold","Editorial Serif","Tech Terminal","Behind Glass","Light Leak","Gradient Glow","Stacked Stagger"]}`

**Tool call** `recommended_zooms` `{"document": "d1"}`

Result: `[{"clicks":6,"clip":"64BB82A0-B223-4109-82C4-AFCAF9FE7F5D","has":0,"name":"Recording 2026-10-10 at 19.44.21","recommended":[{"fromSeconds":0,"percent":131,"toSeconds":6.904}]},{"clicks":2,"clip":"E45CB55E-A33F-495E-BBF9-5F4BB9B8AF5C","has":0,"name":"Recording 2026-10-10 at 20.14.54","recommended":[{"fromSeconds":7.583,"percent":200,"toSeconds":10.573}]},{"clicks":19,"clip":"2A660E16-F370-4B19-99A8-7F9B6A5B0AD8","has":0,"name":"Recording 2026-10-11 at 05.12.59","recommended":[{"fromSeconds":10.602,"percent":199,"toSeconds":14.461},{"fromSeconds":15.175,"percent":200,"toSeconds":17.575},{"fromSe …`

**Tool call** `apply_zooms` `{"document": "d1"}`

Result: `{"added":{"2A660E16-F370-4B19-99A8-7F9B6A5B0AD8":11,"5E09E448-02E3-4B8D-ABB4-435973EEE820":1,"64BB82A0-B223-4109-82C4-AFCAF9FE7F5D":1,"96F9E1AC-F69E-4780-B2A4-490F3B613976":1,"E45CB55E-A33F-495E-BBF9-5F4BB9B8AF5C":1},"total":15}`

> Zooms applied (15 total). Now the subtitle pages. I'll test one style first and look at it.

**Tool call** `add_title` `{"document": "d1", "clip": "64BB82A0-B223-4109-82C4-AFCAF9FE7F5D", "style": "Keynote Clean", "text": "Case 1"}`

Result: `{"durationSeconds":160.496,"inSeconds":0,"outSeconds":4,"parts":[{"layer":"E338A115-42E6-4A65-B683-FA38746AF8D4","name":"Title","text":"Case 1"}],"sampleLinesTakenOut":["Subtitle"],"style":"Keynote Clean","title":"D76E3CE0-DDA8-4312-A41A-7CDCF4A06AA0","track":"V1"}`

**Tool call** `video_frame` `{"document": "d1", "seconds": 2, "maxSize": 800}`

Result: `Untitled 1 at 0:02.0 (800x517 PNG) (picture)`

> Clean and readable. Adding Cases 2–5 in the same style.

**Tool call** `add_title` `{"document": "d1", "clip": "E45CB55E-A33F-495E-BBF9-5F4BB9B8AF5C", "style": "Keynote Clean", "text": "Case 2"}`

Result: `{"durationSeconds":164.496,"inSeconds":11.583,"outSeconds":15.583,"parts":[{"layer":"05B267C3-04DA-4DDB-B884-642A02721F50","name":"Title","text":"Case 2"}],"sampleLinesTakenOut":["Subtitle"],"style":"Keynote Clean","title":"E87523B3-2C9B-49C4-B042-06E14DF52493","track":"V1"}`

**Tool call** `add_title` `{"document": "d1", "clip": "2A660E16-F370-4B19-99A8-7F9B6A5B0AD8", "style": "Keynote Clean", "text": "Case 3"}`

Result: `{"durationSeconds":168.496,"inSeconds":18.573,"outSeconds":22.573,"parts":[{"layer":"72FCF5D2-3FE8-46F1-AD0F-C476CC1C5333","name":"Title","text":"Case 3"}],"sampleLinesTakenOut":["Subtitle"],"style":"Keynote Clean","title":"71908643-15C3-4059-8A55-85BE9FFCCCA6","track":"V1"}`

**Tool call** `add_title` `{"document": "d1", "clip": "96F9E1AC-F69E-4780-B2A4-490F3B613976", "style": "Keynote Clean", "text": "Case 4"}`

Result: `{"durationSeconds":172.496,"inSeconds":157.165,"outSeconds":161.165,"parts":[{"layer":"FF98A861-E612-4418-91C2-DD23941504B9","name":"Title","text":"Case 4"}],"sampleLinesTakenOut":["Subtitle"],"style":"Keynote Clean","title":"3355476E-C19F-43CB-A5A0-A9281A700579","track":"V1"}`

**Tool call** `add_title` `{"document": "d1", "clip": "5E09E448-02E3-4B8D-ABB4-435973EEE820", "style": "Keynote Clean", "text": "Case 5"}`

Result: `{"durationSeconds":176.496,"inSeconds":166.978,"outSeconds":170.978,"parts":[{"layer":"998A2222-569A-44F9-BF02-4D111ADC443A","name":"Title","text":"Case 5"}],"sampleLinesTakenOut":["Subtitle"],"style":"Keynote Clean","title":"CAB65B9A-76FC-4235-BFBF-D6884D417B5B","track":"V1"}`

**Tool call** `add_title` `{"document": "d1", "clip": "D76E3CE0-DDA8-4312-A41A-7CDCF4A06AA0", "style": "Keynote Clean", "text": "Montage", "subtitle": "Five cases"}`

Result: `{"durationSeconds":180.496,"inSeconds":0,"outSeconds":4,"parts":[{"layer":"9D772F86-0492-43C5-A52E-85C0D32BA080","name":"Title","text":"Montage"},{"layer":"E5C242A1-B4F7-4AAC-BBA3-C2A3148CDB60","name":"Subtitle","text":"Five cases"}],"style":"Keynote Clean","title":"5CCCBD83-1B7D-4D18-A580-1A7265EC5192","track":"V1"}`

**Tool call** `read_document` `{"document": "d1"}`

Result: `{"canRedo":false,"canUndo":true,"canvas":{"height":2234,"width":3456},"cuts":[{"atSeconds":4,"from":"Title Page","to":"Title Page","transition":{"kind":"dissolve","seconds":0.4}},{"atSeconds":8,"from":"Title Page","to":"Recording 2026-10-10 at 19.44.21","transition":{"kind":"dissolve","seconds":0.4}},{"atSeconds":15.583,"from":"Recording 2026-10-10 at 19.44.21","to":"Title Page"},{"atSeconds":19.583,"from":"Title Page","to":"Recording 2026-10-10 at 20.14.54","transition":{"kind":"dissolve","seconds":0.4}},{"atSeconds":22.573,"from":"Recording 2026-10-10 at 20.14.54","to":"Title Page"},{"atSeco …`

> Zooms travelled with their clips. The four clip → title cuts have no transition, so I'll match them to the 0.4s dissolves on the other cuts.

**Tool call** `set_transition` `{"document": "d1", "seconds": 15.583, "kind": "dissolve", "lengthSeconds": 0.4}`

Result: `{"atSeconds":15.583,"kind":"dissolve","lengthSeconds":0.4}`

**Tool call** `set_transition` `{"document": "d1", "seconds": 22.573, "kind": "dissolve", "lengthSeconds": 0.4}`

Result: `{"atSeconds":22.573,"kind":"dissolve","lengthSeconds":0.4}`

**Tool call** `set_transition` `{"document": "d1", "seconds": 161.165, "kind": "dissolve", "lengthSeconds": 0.4}`

Result: `{"atSeconds":161.165,"kind":"dissolve","lengthSeconds":0.4}`

**Tool call** `set_transition` `{"document": "d1", "seconds": 170.978, "kind": "dissolve", "lengthSeconds": 0.4}`

Result: `{"atSeconds":170.978,"kind":"dissolve","lengthSeconds":0.4}`

> Now let me check it: the title, a zoom inside each clip, and the transitions.

**Tool call** `video_frame` `{"document": "d1", "seconds": 2, "maxSize": 800}`

Result: `Untitled 1 at 0:02.0 (800x517 PNG) (picture)`

**Tool call** `contact_sheet` `{"document": "d1", "fromSeconds": 3.5, "toSeconds": 28, "count": 24, "columns": 6, "cellWidth": 240}`

Result: `Untitled 1: 24 frames at 0:03.5, 0:04.5, 0:05.6, 0:06.6, 0:07.7, 0:08.8, 0:09.8, 0:10.9, 0:12.0, 0:13.0, 0:14.1, 0:15.2, 0:16.2, 0:17.3, 0:18.3, 0:19.4, 0:20.5, 0:21.5, 0:22.6, 0:23.7, 0:24.7, 0:25.8, 0:26.9, 0:27.9, left to right, top to bottom (1496x748 PNG) (picture)`

> Title, Case 1–3 pages, and zooms look right: Case 1 is pushed in at 131% and Case 2/3 at 200%. Next, the end of the timeline.

**Tool call** `contact_sheet` `{"document": "d1", "fromSeconds": 158, "toSeconds": 180.4, "count": 18, "columns": 6, "cellWidth": 240}`

Result: `Untitled 1: 18 frames at 2:38.0, 2:39.3, 2:40.6, 2:41.9, 2:43.2, 2:44.5, 2:45.8, 2:47.2, 2:48.5, 2:49.8, 2:51.1, 2:52.4, 2:53.7, 2:55.1, 2:56.4, 2:57.7, 2:59.0, 3:00.3, left to right, top to bottom (1496x563 PNG) (picture)`

> Everything is consistent all the way through. Exporting now.

**Tool call** `export` `{"document": "d1", "format": "mp4", "path": "/tmp/photonz-montage/montage.mp4"}`

Result: `{"bytes":366046540,"format":"mp4","height":2234,"path":"/tmp/photonz-montage/montage.mp4","seconds":180.496,"width":3456}`

> Now I'll open the exported file to check it.

**Tool call** `open_document` `{"path": "/tmp/photonz-montage/montage.mp4"}`

Result: `{"canRedo":false,"canUndo":false,"durationSeconds":180.497,"file":"/tmp/photonz-montage/montage.mp4","front":true,"height":2234,"id":"d2","kind":"video","title":"montage.mp4","width":3456}`

**Tool call** `contact_sheet` `{"document": "d2", "count": 12, "columns": 6, "cellWidth": 200}`

Result: `montage.mp4: 12 frames at 0:00.0, 0:16.4, 0:32.8, 0:49.2, 1:05.6, 1:22.0, 1:38.4, 1:54.8, 2:11.2, 2:27.6, 2:44.0, 3:00.4, left to right, top to bottom (1256x326 PNG) (picture)`

> The first frame is black. That's probably the title fading in, but I'll check that the title page made it into the file.

**Tool call** `video_frame` `{"document": "d2", "seconds": 2, "maxSize": 500}`

Result: `montage.mp4 at 0:02.0 (500x323 PNG) (picture)`

> The montage is exported to `/tmp/photonz-montage/montage.mp4`. It's 3:00 long, 3456×2234 (the recordings' own size), and 366 MB. I opened the exported file and checked frames across the whole video: the title, the Case pages and the zooms are all in it.
> 
> **Which clips I used:** your recent History is all screenshots, so I took the 5 most recent **recordings**. They go back further than you might expect, Oct 10 to Oct 19, so check these are the ones you meant:
> 
> | Case | Recording | Length | Zooms |
> |---|---|---|---|
> | 1 | Oct 10, 19:44:21 | 7.6s | 1 (131%) |
> | 2 | Oct 10, 20:14:54 | 3.0s | 1 (200%) |
> | 3 | Oct 11, 05:12:59 | 2:15 | 11 (200%) |
> | 4 | Oct 18, 15:48:58 | 5.8s | 1 (200%) |
> | 5 | Oct 19, 07:50:53 | 5.5s | 1 (200%) |
> 
> **How it's put together:**
> - **Title page:** "Montage" with a "Five cases" subtitle. I made up that wording, so give me a real title if you have one.
> - **Case pages:** "Case 1" to "Case 5" before each clip. Each is 4 seconds and uses the same "Keynote Clean" style as the title: centred white text on a dark animated background.
> - **Zooms:** all 15 recommended zooms are applied.
> - **Transitions:** every cut is a 0.4s dissolve.
> - **Order:** cases are numbered oldest to newest.
> 
> Case 3 takes up about 75% of the running time. If you want it shorter, I can trim it and re-export.
> 
> The editable timeline is still open in Photonz as "Untitled 1" if you want to tweak it there.


**Session ended** after 212s, 29 turns.

Final answer:

The montage is exported to `/tmp/photonz-montage/montage.mp4`. It's 3:00 long, 3456×2234 (the recordings' own size), and 366 MB. I opened the exported file and checked frames across the whole video: the title, the Case pages and the zooms are all in it.

**Which clips I used:** your recent History is all screenshots, so I took the 5 most recent **recordings**. They go back further than you might expect, Oct 10 to Oct 19, so check these are the ones you meant:

| Case | Recording | Length | Zooms |
|---|---|---|---|
| 1 | Oct 10, 19:44:21 | 7.6s | 1 (131%) |
| 2 | Oct 10, 20:14:54 | 3.0s | 1 (200%) |
| 3 | Oct 11, 05:12:59 | 2:15 | 11 (200%) |
| 4 | Oct 18, 15:48:58 | 5.8s | 1 (200%) |
| 5 | Oct 19, 07:50:53 | 5.5s | 1 (200%) |

**How it's put together:**
- **Title page:** "Montage" with a "Five cases" subtitle. I made up that wording, so give me a real title if you have one.
- **Case pages:** "Case 1" to "Case 5" before each clip. Each is 4 seconds and uses the same "Keynote Clean" style as the title: centred white text on a dark animated background.
- **Zooms:** all 15 recommended zooms are applied.
- **Transitions:** every cut is a 0.4s dissolve.
- **Order:** cases are numbered oldest to newest.

Case 3 takes up about 75% of the running time. If you want it shorter, I can trim it and re-export.

The editable timeline is still open in Photonz as "Untitled 1" if you want to tweak it there.
