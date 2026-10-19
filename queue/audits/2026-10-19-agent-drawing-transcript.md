# Agent MCP, slice 3: the try path, 2026-10-19

Two fresh Claude Code sessions (`claude -p`, only the Photonz probe server configured, every other MCP server off, no Bash, Write or Edit), the probe at Next defaults. The prompts are the user's own words from the acceptance list.

```
claude -p --mcp-config mcp.json --strict-mcp-config --allowedTools 'mcp__photonz-probe__*' \
  --disallowedTools Bash Write Edit '<prompt>'
```

`mcp.json` ran `PHOTONZ_APP=probe Scripts/photonz-mcp.sh`.

## Scenario 2: "Create a product icon svg of a box inside of a cloud."

Nothing open beforehand. The icon was built from 10 layers (4 shapes for the tile and cloud, 1 rounded box, 4 paths for the box and its tape), checked three times with render_picture, adjusted with set_layer, and exported. The SVG it wrote is `2026-10-19-agent-drawing-1-cloud-box-icon.svg` (953 bytes, vector shapes only, no embedded pictures); `-2-cloud-box-icon-svg-rendered.png` is that file drawn by Quick Look, not by Photonz, and matches the canvas pixel for pixel by eye.

**Tool call** `new_picture` `{"width": 512, "height": 512}`

Result: `{"canRedo":false,"canUndo":false,"front":true,"height":512,"id":"d1","kind":"picture","title":"Untitled 1","width":512}`

**Tool call** `add_shape` `{"shape": "rectangle", "frame": {"x": 32, "y": 32, "width": 448, "height": 448}, "cornerRadius": 100, "fill": "#2F6FEB", "name": "Background"}`

Result: `{"canUndo":true,"frame":{"height":448,"width":448,"x":32,"y":32},"layer":"2BB96863-29FB-4F56-A20A-7F6AEF595BF3","name":"Background"}`

**Tool call** `add_shape` `{"shape": "ellipse", "frame": {"x": 78, "y": 238, "width": 144, "height": 144}, "fill": "#FFFFFF", "name": "Cloud left"}`

Result: `{"canUndo":true,"frame":{"height":144,"width":144,"x":78,"y":238},"layer":"C0DF8448-58DD-425E-8362-F5EFAF9E28D1","name":"Cloud left"}`

**Tool call** `add_shape` `{"shape": "ellipse", "frame": {"x": 150, "y": 130, "width": 200, "height": 200}, "fill": "#FFFFFF", "name": "Cloud top"}`

Result: `{"canUndo":true,"frame":{"height":200,"width":200,"x":150,"y":130},"layer":"FE900E04-AB7A-4B2E-8F53-17D4B21A82BF","name":"Cloud top"}`

**Tool call** `add_shape` `{"shape": "ellipse", "frame": {"x": 268, "y": 198, "width": 164, "height": 164}, "fill": "#FFFFFF", "name": "Cloud right"}`

Result: `{"canUndo":true,"frame":{"height":164,"width":164,"x":268,"y":198},"layer":"300A0C1F-4913-4E3E-B364-1182D0B59C42","name":"Cloud right"}`

**Tool call** `add_shape` `{"shape": "rectangle", "frame": {"x": 110, "y": 290, "width": 310, "height": 92}, "cornerRadius": 46, "fill": "#FFFFFF", "name": "Cloud base"}`

Result: `{"canUndo":true,"frame":{"height":92,"width":310,"x":110,"y":290},"layer":"BF59FFF9-26AF-4A43-9C2C-394A9BF4BE1A","name":"Cloud base"}`

**Tool call** `add_path` `{"points": [{"x": 256, "y": 214}, {"x": 320, "y": 246}, {"x": 256, "y": 278}, {"x": 192, "y": 246}], "closed": true, "fill": "#FBBF24", "name": "Box top"}`

Result: `{"canUndo":true,"frame":{"height":64,"width":128,"x":192,"y":214},"layer":"6E84D634-C2EA-44BF-917A-F30583398AFF","name":"Box top"}`

**Tool call** `add_path` `{"points": [{"x": 192, "y": 246}, {"x": 256, "y": 278}, {"x": 256, "y": 354}, {"x": 192, "y": 322}], "closed": true, "fill": "#F59E0B", "name": "Box left"}`

Result: `{"canUndo":true,"frame":{"height":108,"width":64,"x":192,"y":246},"layer":"0F6DEE28-9542-4C6A-B548-FAEC2A56190A","name":"Box left"}`

**Tool call** `add_path` `{"points": [{"x": 256, "y": 278}, {"x": 320, "y": 246}, {"x": 320, "y": 322}, {"x": 256, "y": 354}], "closed": true, "fill": "#D97706", "name": "Box right"}`

Result: `{"canUndo":true,"frame":{"height":108,"width":64,"x":256,"y":246},"layer":"80ED2765-1866-4525-BA6E-AAB3F8600E71","name":"Box right"}`

**Tool call** `add_path` `{"points": [{"x": 214, "y": 235}, {"x": 234, "y": 225}, {"x": 298, "y": 257}, {"x": 298, "y": 290}, {"x": 278, "y": 300}, {"x": 278, "y": 267}], "closed": true, "fill": "#FDE68A", "name": "Tape"}`

**Tool call** `render_picture` `{}`

Result: `{"canUndo":true,"frame":{"height":75,"width":84,"x":214,"y":225},"layer":"16A04273-6037-480C-A054-D695DFBCBC0F","name":"Tape"}`

Result: `Untitled 1 (512x512 PNG)[Image: source: /Users/dzearing/.claude/projects/-private-tmp-photonz-agent-draw-session/d91982b5-573b-4d75-9c95-5a90eaa8aa34/tool-results/mcp-photonz-probe-blob-1792442943078-rzvukf.png]`

**Tool call** `set_layer` `{"layer": "300A0C1F-4913-4E3E-B364-1182D0B59C42", "y": 218}`

Result: `{"canUndo":true,"frame":{"height":164,"width":164,"x":268,"y":218},"layer":"300A0C1F-4913-4E3E-B364-1182D0B59C42","name":"Cloud right"}`

**Tool call** `set_layer` `{"layer": "BF59FFF9-26AF-4A43-9C2C-394A9BF4BE1A", "x": 140, "width": 230}`

**Tool call** `render_picture` `{}`

Result: `{"canUndo":true,"frame":{"height":92,"width":230,"x":140,"y":290},"layer":"BF59FFF9-26AF-4A43-9C2C-394A9BF4BE1A","name":"Cloud base"}`

Result: `Untitled 1 (512x512 PNG)[Image: source: /Users/dzearing/.claude/projects/-private-tmp-photonz-agent-draw-session/d91982b5-573b-4d75-9c95-5a90eaa8aa34/tool-results/mcp-photonz-probe-blob-1792442950679-10eixm.png]`

**Tool call** `set_layer` `{"layer": "BF59FFF9-26AF-4A43-9C2C-394A9BF4BE1A", "x": 150, "width": 200, "cornerRadius": 0}`

Result: `{"canUndo":true,"frame":{"height":92,"width":200,"x":150,"y":290},"layer":"BF59FFF9-26AF-4A43-9C2C-394A9BF4BE1A","name":"Cloud base"}`

**Tool call** `render_picture` `{}`

Result: `Untitled 1 (512x512 PNG)[Image: source: /Users/dzearing/.claude/projects/-private-tmp-photonz-agent-draw-session/d91982b5-573b-4d75-9c95-5a90eaa8aa34/tool-results/mcp-photonz-probe-blob-1792442954871-lejryz.png]`

**Tool call** `export` `{"format": "svg", "path": "/private/tmp/photonz-agent-draw/session/cloud-box-icon.svg", "background": false}`

Result: `{"bytes":953,"format":"svg","height":512,"path":"/private/tmp/photonz-agent-draw/session/cloud-box-icon.svg","width":512}`

Result: `1	<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">
2	  <rect transform="translate(32 32)" x="0" y="0" width="448" height="448" rx="100" fill="#2F6FEB"/>
3	  <ellipse transform="translate(78 238)" cx="72" cy="72" rx="72" ry="72" fill="#FFFFFF"/>
4	  <ellipse tra ...`

**Answer**

I made the icon and saved it as **`/private/tmp/photonz-agent-draw/session/cloud-box-icon.svg`**. I checked the render in Photonz, and the exported file contains clean vector shapes.

It's 512×512 and has three parts:
- **Tile:** a blue (`#2F6FEB`) rounded square with 100pt corner radius. The area outside the tile is transparent.
- **Cloud:** white, built from three overlapping circles on a flat base.
- **Box:** an amber shipping box drawn at an angle, with three shades so it looks 3D. A light strip of tape crosses the lid and runs down the front edge.

The document is still open in Photonz as "Untitled 1", with each part on its own named layer, so you can change colours or proportions there.

The cloud is made of four separate white shapes rather than one combined outline. That's fine for display, but if you need a single path (for a mask or a one-colour version), I can redraw it as one outline.

## Scenario 3: "annotate the ux with measurements around the major ui elements"

`Settings pane.png` (the 1440 x 960 settings-pane fixture, a real 2x capture) was open in the probe, held by a walk that photographed the window before and after (`-3-redline-before-sc.png`, `-4-redline-after-sc.png`, real window captures with the window behind another app).

Measurements placed: 13. Wholly on edges the picture really has (every measured side and foot within 3 px of an edge in the app's own edge map, the map the Measure tool snaps to): 11 of 13, 34 of 36 sides and feet. The two partial ones: the 32 px page margin starts at the picture's own border, and one 20 px distance has its lower end on empty background beside the buttons. Every number matches what the Measure tool's own Size click reads on the same element. The agent hid 3 of its own layers whose readouts crowded others, leaving 10 visible.

Two earlier runs of the same prompt (before find_elements was fixed) are not shown: the first placed 15 measurements, then undid most and replaced them with distances floated beside the elements, only 5 of 13 wholly on edges; the second read the text fields as 218 x 25 (the field's inner border) where the Size click reads 220 x 26. Both led to code changes in this task.

**Tool call** `list_documents` `{}`

Result: `[{"canRedo":false,"canUndo":false,"file":"/tmp/photonz-agent-draw/Settings pane.png","front":true,"height":960,"id":"d1","kind":"picture","title":"Settings pane.png","width":1440}]`

**Tool call** `render_picture` `{}`

**Tool call** `find_elements` `{"limit": 60}`

Result: `Settings pane.png (1024x683 PNG)[Image: source: /Users/dzearing/.claude/projects/-private-tmp-photonz-agent-draw-session/444201f0-90d0-4496-ad21-c4c524625499/tool-results/mcp-photonz-probe-blob-1792444094355-u99hev.png]`

Result: `{"count":31,"elements":[{"height":264,"width":1312,"x":64,"y":148},{"height":264,"width":1312,"x":64,"y":452},{"height":90,"width":1240,"x":96,"y":234},{"height":90,"width":1240,"x":96,"y":322},{"height":90,"width":1240,"x":96,"y":538},{"height":90,"width":1240,"x":96,"y":626},{"height":89,"width":1 ...`

**Tool call** `add_measurement` `{"kind": "size", "box": {"x": 64, "y": 148, "width": 1312, "height": 264}}`

Result: `{"layers":["1B7DCD4E-B3CB-44E8-846C-690CFBCC8E26"],"measured":{"height":264,"width":1312,"x":64,"y":148},"names":["Size 656 × 132"],"onEdges":4,"outOf":4}`

**Tool call** `add_measurement` `{"kind": "gap", "boxes": [{"x": 64, "y": 148, "width": 1312, "height": 264}, {"x": 64, "y": 452, "width": 1312, "height": 264}]}`

Result: `{"layers":["3463F7DE-6BD8-42C1-ABBB-2C1209B8B7B5"],"names":["Gap 20"],"onEdges":2,"outOf":2}`

**Tool call** `add_measurement` `{"kind": "size", "box": {"x": 904, "y": 469, "width": 440, "height": 52}}`

Result: `{"layers":["2F588096-2201-457A-82CE-CFC9CFD7B8BE"],"measured":{"height":52,"width":440,"x":904,"y":469},"names":["Size 220 × 26"],"onEdges":4,"outOf":4}`

**Tool call** `add_measurement` `{"kind": "size", "box": {"x": 1260, "y": 167, "width": 84, "height": 48}}`

Result: `{"layers":["1A903029-54DD-487D-A1B2-F263EE244FBC"],"measured":{"height":48,"width":84,"x":1260,"y":167},"names":["Size 42 × 24"],"onEdges":4,"outOf":4}`

**Tool call** `add_measurement` `{"kind": "size", "box": {"x": 64, "y": 756, "width": 145, "height": 60}}`

Result: `{"layers":["205243DF-C757-4E5F-9346-312EAB5556D5"],"measured":{"height":60,"width":145,"x":64,"y":756},"names":["Size 72 × 30"],"onEdges":4,"outOf":4}`

**Tool call** `add_measurement` `{"kind": "size", "box": {"x": 233, "y": 756, "width": 248, "height": 60}}`

Result: `{"layers":["D3DA7955-6174-4B80-B848-CE9AD6C27FF3"],"measured":{"height":60,"width":248,"x":233,"y":756},"names":["Size 124 × 30"],"onEdges":4,"outOf":4}`

**Tool call** `add_measurement` `{"kind": "gap", "boxes": [{"x": 64, "y": 756, "width": 145, "height": 60}, {"x": 233, "y": 756, "width": 248, "height": 60}]}`

Result: `{"layers":["8D1DA191-2CED-4D0E-8872-9722C1C0E19A"],"names":["Gap 12"],"onEdges":2,"outOf":2}`

**Tool call** `add_measurement` `{"kind": "gap", "boxes": [{"x": 64, "y": 452, "width": 1312, "height": 264}, {"x": 64, "y": 756, "width": 145, "height": 60}]}`

Result: `{"layers":["04B18A55-AE37-4DDB-92BF-44FD9D1E0818"],"names":["Gap 20"],"onEdges":2,"outOf":2}`

**Tool call** `add_measurement` `{"kind": "gap", "boxes": [{"x": 65, "y": 66, "width": 157, "height": 34}, {"x": 64, "y": 148, "width": 1312, "height": 264}]}`

Result: `{"layers":["ADA471E4-6D2B-4041-8AD9-07CD181125DF"],"names":["Gap 24"],"onEdges":2,"outOf":2}`

**Tool call** `add_measurement` `{"kind": "distance", "from": {"x": 0, "y": 280}, "to": {"x": 64, "y": 280}, "axis": "horizontal"}`

Result: `{"layers":["681E5CF0-2669-4CF9-BAC5-C2EA6A76F75D"],"names":["Distance 32"],"onEdges":1,"outOf":2}`

**Tool call** `add_measurement` `{"kind": "distance", "from": {"x": 1344, "y": 191}, "to": {"x": 1376, "y": 191}, "axis": "horizontal"}`

Result: `{"layers":["97C5C28A-0922-41FE-9730-FCFC48058282"],"names":["Distance 16"],"onEdges":2,"outOf":2}`

**Tool call** `render_picture` `{"maxSize": 1440}`

Result: `Settings pane.png (1440x960 PNG)[Image: source: /Users/dzearing/.claude/projects/-private-tmp-photonz-agent-draw-session/444201f0-90d0-4496-ad21-c4c524625499/tool-results/mcp-photonz-probe-blob-1792444108756-fjq4ab.png]`

**Tool call** `read_document` `{}`

Result: `{"canRedo":false,"canUndo":true,"canvas":{"height":960,"width":1440},"file":"/tmp/photonz-agent-draw/Settings pane.png","id":"d1","kind":"picture","layerCount":27,"layers":[{"frame":{"height":108.9,"width":97,"x":1311.5,"y":183},"id":"97C5C28A-0922-41FE-9730-FCFC48058282","kind":"measurement","name" ...`

**Tool call** `set_layer` `{"layer": "E9013262-BF7C-4EB7-AAE6-935352659F4A", "visible": false}`

Result: `{"canUndo":true,"frame":{"height":76,"width":126.5,"x":145,"y":0},"layer":"E9013262-BF7C-4EB7-AAE6-935352659F4A","name":"Height"}`

**Tool call** `set_layer` `{"layer": "04B18A55-AE37-4DDB-92BF-44FD9D1E0818", "visible": false}`

Result: `{"canUndo":true,"frame":{"height":82,"width":179.5,"x":129,"y":708},"layer":"04B18A55-AE37-4DDB-92BF-44FD9D1E0818","name":"Gap 20"}`

**Tool call** `add_measurement` `{"kind": "distance", "from": {"x": 420, "y": 716}, "to": {"x": 420, "y": 756}, "axis": "vertical"}`

Result: `{"layers":["491856BF-B267-4952-A5D6-BF90A15CBA42"],"names":["Distance 20"],"onEdges":2,"outOf":2}`

**Tool call** `render_picture` `{"maxSize": 1440}`

Result: `Settings pane.png (1440x960 PNG)[Image: source: /Users/dzearing/.claude/projects/-private-tmp-photonz-agent-draw-session/444201f0-90d0-4496-ad21-c4c524625499/tool-results/mcp-photonz-probe-blob-1792444124441-4kzred.png]`

**Tool call** `set_layer` `{"layer": "491856BF-B267-4952-A5D6-BF90A15CBA42", "visible": false}`

Result: `{"canUndo":true,"frame":{"height":82,"width":388.89,"x":109.11,"y":708},"layer":"491856BF-B267-4952-A5D6-BF90A15CBA42","name":"Distance 20"}`

**Tool call** `add_measurement` `{"kind": "distance", "from": {"x": 720, "y": 716}, "to": {"x": 720, "y": 756}, "axis": "vertical"}`

Result: `{"layers":["0BCA6FCF-9064-42D8-9B05-31691B7EAA3D"],"names":["Distance 20"],"onEdges":1,"outOf":2}`

**Tool call** `render_picture` `{"maxSize": 1440, "region": {"x": 0, "y": 680, "width": 1440, "height": 280}}`

Result: `Settings pane.png (1440x280 PNG)[Image: source: /Users/dzearing/.claude/projects/-private-tmp-photonz-agent-draw-session/444201f0-90d0-4496-ad21-c4c524625499/tool-results/mcp-photonz-probe-blob-1792444130012-60yn6q.png]`

**Answer**

I added measurements to the major elements of "Settings pane.png" in Photonz. The screenshot is @2x, so the values are in points (half the pixel numbers):

| Element | Measurement |
|---|---|
| Left page margin | 32 |
| "General" heading → first card | 24 |
| Settings card | 656 × 132 |
| Gap between the two cards | 20 |
| Text field | 220 × 26 |
| Toggle | 42 × 24 |
| Toggle → card right edge | 16 |
| Second card → button row | 20 |
| Reset button | 72 × 30 |
| Save Changes button | 124 × 30 |
| Gap between buttons | 12 |

**Inconsistent margins:** the left margin from the card to the labels is 16 pt, but the "File name prefix" label sits about 4 pt further in than the other labels. If that isn't intended, it's an alignment bug in the design.

**Overlap cleanup:** the first pass had labels sitting on top of the Reset and Save Changes buttons. To fix that I hid the Reset button's height label (both buttons are 30 tall, and Save Changes still shows it). I also hid two versions of the "card → buttons" gap and redrew it as a single line in the empty space to the right. Those hidden layers are still in the layer list, and you can undo any of it.

**Still a bit crowded:** the toggle area has three labels plus the card's height line running through it. They're readable but busy. I can move or simplify them if you want.
