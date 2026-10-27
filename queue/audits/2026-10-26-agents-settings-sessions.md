# Agents installed from Settings: two fresh sessions, 2026-10-26

Both run from `/tmp/pz-empty`, an empty folder with no Photonz source, after pressing Install on the Claude Code and GitHub Copilot rows of the probe's Settings > Agents. The server each one ran is `dist/Photonz Probe.app/Contents/Helpers/photonz-mcp` (the bundled bridge); the skill came from the copy Install put in `~/.claude/skills/photonz` and `~/.copilot/skills/photonz`.

Prompt for both: *Describe the picture open in Photonz: list the open documents, read the one in front, and render a picture of it so you can see it. Then say in two or three sentences what it shows, and name the tools you called.*

## Claude Code (`claude -p`, `--allowedTools "mcp__photonz-probe__*"`)

- session start: server `photonz-probe` connected (source user); skills include `photonz`: True
- tool call `ToolSearch` {"query": "select:mcp__photonz-probe__list_documents,mcp__photonz-probe__read_document,mcp__photonz-
  - answer: ['tool_reference', 'tool_reference', 'tool_reference'], ``
- tool call `mcp__photonz-probe__list_documents` {}
  - answer: ['text'], `[{"canRedo":false,"canUndo":false,"front":true,"height":960,"id":"d2","kind":"picture","title":"Untitled","wid`
- tool call `mcp__photonz-probe__read_document` {}
  - answer: ['text'], `{"canRedo":false,"canUndo":false,"canvas":{"height":960,"width":1440},"id":"d2","kind":"picture","layerCount":`
- tool call `mcp__photonz-probe__render_picture` {}
  - answer: ['text', 'image', 'text'], `Untitled (1024x683 PNG)`

Its answer:

**Open documents:** Photonz has two pictures open, both called "Untitled" and both 1440×960. **d2** is in front and **d1** is behind it. Neither one has any undo or redo history.

**The front document (d2):** It has just one layer, a locked image called "Background" that fills the whole canvas. Nothing in it is an editable layer.

**What it shows:** It's a screenshot of a macOS-style "General" settings panel in two white cards. The first card has three switches: "Launch at login" and "Show in menu bar" are on, and "Play sound on capture" is off. The second card has two empty text boxes, "Save captures to" and "File name prefix", and a "Copy to clipboard" switch that's on. Under the cards are a grey "Reset" button and a blue "Save Changes" button. The "File name prefix" label sits a few pixels further right than the other labels, so it's slightly out of line.

**Tools called:** `ToolSearch` (to load the Photonz tools), then `mcp__photonz-probe__list_documents`, `mcp__photonz-probe__read_document` and `mcp__photonz-probe__render_picture`.

## Copilot CLI 1.0.104 (`copilot -p --allow-all-tools`)

`copilot skill list` showed `photonz` from personal skills; `copilot mcp list` showed `photonz-probe (local)` under User servers.

```
● Using model "gpt-6.1-sol" for this session because of an administrator-managed setting. Contact
  your administrator if this is unexpected.

● skill(photonz)

● list_documents (MCP: photonz-probe)
  └ [{"canRedo":false,"canUndo":false,"front":true,"height":960,"id":"d2","kind":...

● read_document (MCP: photonz-probe) · document: "d2"
  └ {"canRedo":false,"canUndo":false,"canvas":{"height":960,"width":1440},"id":"d...

● render_picture (MCP: photonz-probe) · document: "d2"
  └ Untitled (1024x683 PNG)

  􎻮̅̅􎻮̅̍􎻮̅̎􎻮̅̐􎻮̅̒􎻮̅̽􎻮̅̾􎻮̅̿􎻮̅͆􎻮̅͊􎻮̅͋􎻮̅͌􎻮̅͐􎻮̅͑􎻮̅͒􎻮̅͗􎻮̅͛􎻮̅ͣ􎻮̅ͤ􎻮̅ͥ􎻮̅ͦ􎻮̅ͧ􎻮̅ͨ􎻮̅ͩ􎻮̅ͪ􎻮̅ͫ􎻮̅ͬ􎻮̅ͭ􎻮̅ͮ􎻮̅ͯ􎻮̅҃􎻮̅҄􎻮̅҅􎻮̅҆􎻮̅҇􎻮̅֒􎻮̅֓􎻮̅֔􎻮̅֕􎻮̅֗􎻮̅֘􎻮̅֙􎻮̅֜􎻮̅֝􎻮̅֞􎻮̅֟􎻮̅֠􎻮̅֡
  􎻮̍̅􎻮̍̍􎻮̍̎􎻮̍̐􎻮̍̒􎻮̍̽􎻮̍̾􎻮̍̿􎻮̍͆􎻮̍͊􎻮̍͋􎻮̍͌􎻮̍͐􎻮̍͑􎻮̍͒􎻮̍͗􎻮̍͛􎻮̍ͣ􎻮̍ͤ􎻮̍ͥ􎻮̍ͦ􎻮̍ͧ􎻮̍ͨ􎻮̍ͩ􎻮̍ͪ􎻮̍ͫ􎻮̍ͬ􎻮̍ͭ􎻮̍ͮ􎻮̍ͯ􎻮̍҃􎻮̍҄􎻮̍҅􎻮̍҆􎻮̍҇􎻮̍֒􎻮̍֓􎻮̍֔􎻮̍֕􎻮̍֗􎻮̍֘􎻮̍֙􎻮̍֜􎻮̍֝􎻮̍֞􎻮̍֟􎻮̍֠􎻮̍֡
  􎻮̎̅􎻮̎̍􎻮̎̎􎻮̎̐􎻮̎̒􎻮̎̽􎻮̎̾􎻮̎̿􎻮̎͆􎻮̎͊􎻮̎͋􎻮̎͌􎻮̎͐􎻮̎͑􎻮̎͒􎻮̎͗􎻮̎͛􎻮̎ͣ􎻮̎ͤ􎻮̎ͥ􎻮̎ͦ􎻮̎ͧ􎻮̎ͨ􎻮̎ͩ􎻮̎ͪ􎻮̎ͫ􎻮̎ͬ􎻮̎ͭ􎻮̎ͮ􎻮̎ͯ􎻮̎҃􎻮̎҄􎻮̎҅􎻮̎҆􎻮̎҇􎻮̎֒􎻮̎֓􎻮̎֔􎻮̎֕􎻮̎֗􎻮̎֘􎻮̎֙􎻮̎֜􎻮̎֝􎻮̎֞􎻮̎֟􎻮̎֠􎻮̎֡
  􎻮̐̅􎻮̐̍􎻮̐̎􎻮̐̐􎻮̐̒􎻮̐̽􎻮̐̾􎻮̐̿􎻮̐͆􎻮̐͊􎻮̐͋􎻮̐͌􎻮̐͐􎻮̐͑􎻮̐͒􎻮̐͗􎻮̐͛􎻮̐ͣ􎻮̐ͤ􎻮̐ͥ􎻮̐ͦ􎻮̐ͧ􎻮̐ͨ􎻮̐ͩ􎻮̐ͪ􎻮̐ͫ􎻮̐ͬ􎻮̐ͭ􎻮̐ͮ􎻮̐ͯ􎻮̐҃􎻮̐҄􎻮̐҅􎻮̐҆􎻮̐҇􎻮̐֒􎻮̐֓􎻮̐֔􎻮̐֕􎻮̐֗􎻮̐֘􎻮̐֙􎻮̐֜􎻮̐֝􎻮̐֞􎻮̐֟􎻮̐֠􎻮̐֡
  􎻮̒̅􎻮̒̍􎻮̒̎􎻮̒̐􎻮̒̒􎻮̒̽􎻮̒̾􎻮̒̿􎻮̒͆􎻮̒͊􎻮̒͋􎻮̒͌􎻮̒͐􎻮̒͑􎻮̒͒􎻮̒͗􎻮̒͛􎻮̒ͣ􎻮̒ͤ􎻮̒ͥ􎻮̒ͦ􎻮̒ͧ􎻮̒ͨ􎻮̒ͩ􎻮̒ͪ􎻮̒ͫ􎻮̒ͬ􎻮̒ͭ􎻮̒ͮ􎻮̒ͯ􎻮̒҃􎻮̒҄􎻮̒҅􎻮̒҆􎻮̒҇􎻮̒֒􎻮̒֓􎻮̒֔􎻮̒֕􎻮̒֗􎻮̒֘􎻮̒֙􎻮̒֜􎻮̒֝􎻮̒֞􎻮̒֟􎻮̒֠􎻮̒֡
  􎻮̽̅􎻮̽̍􎻮̽̎􎻮̽̐􎻮̽̒􎻮̽̽􎻮̽̾􎻮̽̿􎻮̽͆􎻮̽͊􎻮̽͋􎻮̽͌􎻮̽͐􎻮̽͑􎻮̽͒􎻮̽͗􎻮̽͛􎻮̽ͣ􎻮̽ͤ􎻮̽ͥ􎻮̽ͦ􎻮̽ͧ􎻮̽ͨ􎻮̽ͩ􎻮̽ͪ􎻮̽ͫ􎻮̽ͬ􎻮̽ͭ􎻮̽ͮ􎻮̽ͯ􎻮̽҃􎻮̽҄􎻮̽҅􎻮̽҆􎻮̽҇􎻮̽֒􎻮̽֓􎻮̽֔􎻮̽֕􎻮̽֗􎻮̽֘􎻮̽֙􎻮̽֜􎻮̽֝􎻮̽֞􎻮̽֟􎻮̽֠􎻮̽֡
  􎻮̾̅􎻮̾̍􎻮̾̎􎻮̾̐􎻮̾̒􎻮̾̽􎻮̾̾􎻮̾̿􎻮̾͆􎻮̾͊􎻮̾͋􎻮̾͌􎻮̾͐􎻮̾͑􎻮̾͒􎻮̾͗􎻮̾͛􎻮̾ͣ􎻮̾ͤ􎻮̾ͥ􎻮̾ͦ􎻮̾ͧ􎻮̾ͨ􎻮̾ͩ􎻮̾ͪ􎻮̾ͫ􎻮̾ͬ􎻮̾ͭ􎻮̾ͮ􎻮̾ͯ􎻮̾҃􎻮̾҄􎻮̾҅􎻮̾҆􎻮̾҇􎻮̾֒􎻮̾֓􎻮̾֔􎻮̾֕􎻮̾֗􎻮̾֘􎻮̾֙􎻮̾֜􎻮̾֝􎻮̾֞􎻮̾֟􎻮̾֠􎻮̾֡
  􎻮̿̅􎻮̿̍􎻮̿̎􎻮̿̐􎻮̿̒􎻮̿̽􎻮̿̾􎻮̿̿􎻮̿͆􎻮̿͊􎻮̿͋􎻮̿͌􎻮̿͐􎻮̿͑􎻮̿͒􎻮̿͗􎻮̿͛􎻮̿ͣ􎻮̿ͤ􎻮̿ͥ􎻮̿ͦ􎻮̿ͧ􎻮̿ͨ􎻮̿ͩ􎻮̿ͪ􎻮̿ͫ􎻮̿ͬ􎻮̿ͭ􎻮̿ͮ􎻮̿ͯ􎻮̿҃􎻮̿҄􎻮̿҅􎻮̿҆􎻮̿҇􎻮̿֒􎻮̿֓􎻮̿֔􎻮̿֕􎻮̿֗􎻮̿֘􎻮̿֙􎻮̿֜􎻮̿֝􎻮̿֞􎻮̿֟􎻮̿֠􎻮̿֡
  􎻮͆̅􎻮͆̍􎻮͆̎􎻮͆̐􎻮͆̒􎻮͆̽􎻮͆̾􎻮͆̿􎻮͆͆􎻮͆͊􎻮͆͋􎻮͆͌􎻮͆͐􎻮͆͑􎻮͆͒􎻮͆͗􎻮͆͛􎻮͆ͣ􎻮͆ͤ􎻮͆ͥ􎻮͆ͦ􎻮͆ͧ􎻮͆ͨ􎻮͆ͩ􎻮͆ͪ􎻮͆ͫ􎻮͆ͬ􎻮͆ͭ􎻮͆ͮ􎻮͆ͯ􎻮͆҃􎻮͆҄􎻮͆҅􎻮͆҆􎻮͆҇􎻮͆֒􎻮͆֓􎻮͆֔􎻮͆֕􎻮͆֗􎻮͆֘􎻮͆֙􎻮͆֜􎻮͆֝􎻮͆֞􎻮͆֟􎻮͆֠􎻮͆֡
  􎻮͊̅􎻮͊̍􎻮͊̎􎻮͊̐􎻮͊̒􎻮͊̽􎻮͊̾􎻮͊̿􎻮͊͆􎻮͊͊􎻮͊͋􎻮͊͌􎻮͊͐􎻮͊͑􎻮͊͒􎻮͊͗􎻮͊͛􎻮͊ͣ􎻮͊ͤ􎻮͊ͥ􎻮͊ͦ􎻮͊ͧ􎻮͊ͨ􎻮͊ͩ􎻮͊ͪ􎻮͊ͫ􎻮͊ͬ􎻮͊ͭ􎻮͊ͮ􎻮͊ͯ􎻮͊҃􎻮͊҄􎻮͊҅􎻮͊҆􎻮͊҇􎻮͊֒􎻮͊֓􎻮͊֔􎻮͊֕􎻮͊֗􎻮͊֘􎻮͊֙􎻮͊֜􎻮͊֝􎻮͊֞􎻮͊֟􎻮͊֠􎻮͊֡
  􎻮͋̅􎻮͋̍􎻮͋̎􎻮͋̐􎻮͋̒􎻮͋̽􎻮͋̾􎻮͋̿􎻮͋͆􎻮͋͊􎻮͋͋􎻮͋͌􎻮͋͐􎻮͋͑􎻮͋͒􎻮͋͗􎻮͋͛􎻮͋ͣ􎻮͋ͤ􎻮͋ͥ􎻮͋ͦ􎻮͋ͧ􎻮͋ͨ􎻮͋ͩ􎻮͋ͪ􎻮͋ͫ􎻮͋ͬ􎻮͋ͭ􎻮͋ͮ􎻮͋ͯ􎻮͋҃􎻮͋҄􎻮͋҅􎻮͋҆􎻮͋҇􎻮͋֒􎻮͋֓􎻮͋֔􎻮͋֕􎻮͋֗􎻮͋֘􎻮͋֙􎻮͋֜􎻮͋֝􎻮͋֞􎻮͋֟􎻮͋֠􎻮͋֡
  􎻮͌̅􎻮͌̍􎻮͌̎􎻮͌̐􎻮͌̒􎻮͌̽􎻮͌̾􎻮͌̿􎻮͌͆􎻮͌͊􎻮͌͋􎻮͌͌􎻮͌͐􎻮͌͑􎻮͌͒􎻮͌͗􎻮͌͛􎻮͌ͣ􎻮͌ͤ􎻮͌ͥ􎻮͌ͦ􎻮͌ͧ􎻮͌ͨ􎻮͌ͩ􎻮͌ͪ􎻮͌ͫ􎻮͌ͬ􎻮͌ͭ􎻮͌ͮ􎻮͌ͯ􎻮͌҃􎻮͌҄􎻮͌҅􎻮͌҆􎻮͌҇􎻮͌֒􎻮͌֓􎻮͌֔􎻮͌֕􎻮͌֗􎻮͌֘􎻮͌֙􎻮͌֜􎻮͌֝􎻮͌֞􎻮͌֟􎻮͌֠􎻮͌֡
  􎻮͐̅􎻮͐̍􎻮͐̎􎻮͐̐􎻮͐̒􎻮͐̽􎻮͐̾􎻮͐̿􎻮͐͆􎻮͐͊􎻮͐͋􎻮͐͌􎻮͐͐􎻮͐͑􎻮͐͒􎻮͐͗􎻮͐͛􎻮͐ͣ􎻮͐ͤ􎻮͐ͥ􎻮͐ͦ􎻮͐ͧ􎻮͐ͨ􎻮͐ͩ􎻮͐ͪ􎻮͐ͫ􎻮͐ͬ􎻮͐ͭ􎻮͐ͮ􎻮͐ͯ􎻮͐҃􎻮͐҄􎻮͐҅􎻮͐҆􎻮͐҇􎻮͐֒􎻮͐֓􎻮͐֔􎻮͐֕􎻮͐֗􎻮͐֘􎻮͐֙􎻮͐֜􎻮͐֝􎻮͐֞􎻮͐֟􎻮͐֠􎻮͐֡
  􎻮͑̅􎻮͑̍􎻮͑̎􎻮͑̐􎻮͑̒􎻮͑̽􎻮͑̾􎻮͑̿􎻮͑͆􎻮͑͊􎻮͑͋􎻮͑͌􎻮͑͐􎻮͑͑􎻮͑͒􎻮͑͗􎻮͑͛􎻮͑ͣ􎻮͑ͤ􎻮͑ͥ􎻮͑ͦ􎻮͑ͧ􎻮͑ͨ􎻮͑ͩ􎻮͑ͪ􎻮͑ͫ􎻮͑ͬ􎻮͑ͭ􎻮͑ͮ􎻮͑ͯ􎻮͑҃􎻮͑҄􎻮͑҅􎻮͑҆􎻮͑҇􎻮͑֒􎻮͑֓􎻮͑֔􎻮͑֕􎻮͑֗􎻮͑֘􎻮͑֙􎻮͑֜􎻮͑֝􎻮͑֞􎻮͑֟􎻮͑֠􎻮͑֡
  􎻮͒̅􎻮͒̍􎻮͒̎􎻮͒̐􎻮͒̒􎻮͒̽􎻮͒̾􎻮͒̿􎻮͒͆􎻮͒͊􎻮͒͋􎻮͒͌􎻮͒͐􎻮͒͑􎻮͒͒􎻮͒͗􎻮͒͛􎻮͒ͣ􎻮͒ͤ􎻮͒ͥ􎻮͒ͦ􎻮͒ͧ􎻮͒ͨ􎻮͒ͩ􎻮͒ͪ􎻮͒ͫ􎻮͒ͬ􎻮͒ͭ􎻮͒ͮ􎻮͒ͯ􎻮͒҃􎻮͒҄􎻮͒҅􎻮͒҆􎻮͒҇􎻮͒֒􎻮͒֓􎻮͒֔􎻮͒֕􎻮͒֗􎻮͒֘􎻮͒֙􎻮͒֜􎻮͒֝􎻮͒֞􎻮͒֟􎻮͒֠􎻮͒֡
  􎻮͗̅􎻮͗̍􎻮͗̎􎻮͗̐􎻮͗̒􎻮͗̽􎻮͗̾􎻮͗̿􎻮͗͆􎻮͗͊􎻮͗͋􎻮͗͌􎻮͗͐􎻮͗͑􎻮͗͒􎻮͗͗􎻮͗͛􎻮͗ͣ􎻮͗ͤ􎻮͗ͥ􎻮͗ͦ􎻮͗ͧ􎻮͗ͨ􎻮͗ͩ􎻮͗ͪ􎻮͗ͫ􎻮͗ͬ􎻮͗ͭ􎻮͗ͮ􎻮͗ͯ􎻮͗҃􎻮͗҄􎻮͗҅􎻮͗҆􎻮͗҇􎻮͗֒􎻮͗֓􎻮͗֔􎻮͗֕􎻮͗֗􎻮͗֘􎻮͗֙􎻮͗֜􎻮͗֝􎻮͗֞􎻮͗֟􎻮͗֠􎻮͗֡
  􎻮͛̅􎻮͛̍􎻮͛̎􎻮͛̐􎻮͛̒􎻮͛̽􎻮͛̾􎻮͛̿􎻮͛͆􎻮͛͊􎻮͛͋􎻮͛͌􎻮͛͐􎻮͛͑􎻮͛͒􎻮͛͗􎻮͛͛􎻮͛ͣ􎻮͛ͤ􎻮͛ͥ􎻮͛ͦ􎻮͛ͧ􎻮͛ͨ􎻮͛ͩ􎻮͛ͪ􎻮͛ͫ􎻮͛ͬ􎻮͛ͭ􎻮͛ͮ􎻮͛ͯ􎻮͛҃􎻮͛҄􎻮͛҅􎻮͛҆􎻮͛҇􎻮͛֒􎻮͛֓􎻮͛֔􎻮͛֕􎻮͛֗􎻮͛֘􎻮͛֙􎻮͛֜􎻮͛֝􎻮͛֞􎻮͛֟􎻮͛֠􎻮͛֡

Two documents are open, both **Untitled**, 1440 × 960: `d2` (front) and `d1`. The rendered front picture shows a “General” settings screen with login, menu-bar, capture-sound and clipboard toggles, two empty fields, and Reset and Save Changes buttons.

Tools called: `skill`, `list_resources`, `list_documents`, `read_document`, and `render_picture`.



Changes    +0 -0
AI Credits 6.24 (15s)
Tokens     ↑ 96.3k (75.1k cached, 20.5k written) • ↓ 214 (31 reasoning)
Resume     copilot --resume=2d24c018-e79d-4d5d-afea-0a5f80852b4d
```
