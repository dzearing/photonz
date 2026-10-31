---
name: photonz
description: Make and edit pictures and videos with Photonz, the Mac photo, screenshot and video editor, through its MCP tools. Use this FIRST, before hand-writing any SVG, image or video file, whenever the person asks to create or change a picture, icon, logo, illustration, SVG or PNG, to mark up or measure a screenshot, to cut, title or export a video (a montage from their History recordings), or to rebuild a website or design system as components. Photonz builds it from real editable layers in the window they have open, one undo step per call, and exports the file.
---

# Working in Photonz

Photonz is open on this Mac and you drive it through its MCP tools (`list_documents`,
`read_document`, `render_picture`, ...). Everything you do lands in a real window the
person can see, in the same undo history their clicks land in: **one tool call is one
Command Z**. Nothing is ever edited behind the app's back, so never write `.photonz`
files yourself; build in the app and `export` what the person asked for.

## The loop: do, look, fix

Work in small steps and look after every meaningful one. You cannot see the window,
only what the tools hand back, so looking is how you know.

1. **Read** what is there: `list_documents`, then `read_document` (layers top first
   with frames, text, styles, a group's layout; on a video the tracks, clips, cuts and
   transitions, all times in seconds).
2. **Do** one thing: draw, place, style, cut, title.
3. **Look**: `render_picture` (whole canvas, one `layer`, or a `region` to zoom in),
   `video_frame` at a moment, or `contact_sheet` across a stretch of video.
4. **Judge it against the ask** in plain words: aligned? evenly spaced? legible? the
   same style throughout? Fix with `set_layer`, `set_layout`, `apply_style`, or
   `undo` and redo it differently. Do not move on with something you have not looked at.

Before you say you are done, look at the whole result once more and say what you
checked.

## Which tool for what

| Area | Tools |
| --- | --- |
| Documents | `list_documents`, `list_history` (screenshots and recordings, newest first), `open_document` (a path or a History index), `new_picture`, `new_video` |
| Seeing | `read_document`, `render_picture`, `video_frame`, `contact_sheet` |
| Drawing | `add_photo` (a real photograph of anything, painted by Photonz's picture model and kept as one picture layer filling the canvas or `frame`; `look: painting` for a painted picture), `add_drawing` (anything, a thing or a scene, as editable layers: painted for the request by Photonz's picture model and traced when it is running, else your own SVG; nothing is looked up; `icon` for an icon frame, `style` for a look the person named, `scene` for a place with its own sky), `add_shape` (rectangle, ellipse, highlight, line, arrow), `add_path` (the Pen: corner and smooth points), `add_text`, `set_layer` (frame, paint, line, corners, opacity, shadow, words, `flip` to mirror it in place; `run_command mirror_across_center` makes the mirrored second half of a symmetrical drawing) |
| Painting | `list_brushes` (pencil, charcoal, chalk, crayon, marker, airbrush, oil, watercolour and every setting each has), `set_brush` (the brush in hand), `paint_stroke` (one stroke through `points` or a short `path`, optional pen pressure; its own `medium`, `color` and `settings` for this stroke only; `part` names what it paints; one undo step) |
| Changing a part | `change_part` (one named part of something already made, in place: a painting's strokes of that `part` as `read_document` lists them, or the layers of that name in a drawing; recolour toward `color` keeping its shading, or shift `hue`, `saturation`, `lightness`; `scale` about its middle; move by `dx`, `dy`; or `remove`; one undo step) |
| Measuring a screenshot | `find_measurements` (the redline code chooses: one size of each kind of control, then the spacing), `mark_measurements` (lays the ids you pick, readouts kept clear); `find_elements` and `add_measurement` for one particular thing |
| Checking a screenshot's consistency | `find_misalignments` (edges that miss by 1 to 8 points, uneven gaps, padding or borders that differ, every number measured), `mark_misalignments` (redlines for the ids you pick) |
| Design system | `add_style` / `list_styles` / `apply_style` (named colours and text styles on the Library's Styles shelf), `set_layout` (a group as a stack or grid with gap and padding) |
| Components | `add_component` (a new component with every state it has, in one call), `run_command make_component` (a group you built), `list_components`, `place_component` |
| Video | `add_clip`, `cut`, `trim`, `move_clip`, `set_transition`, `add_title` / `list_titles`, `recommended_zooms` / `apply_zooms`, `set_playhead` |
| Everything else | `list_commands` (every menu bar and right-click command, by name, with whether it can run now) and `run_command` |
| Out | `export` (PNG, SVG, MP4), `undo`, `redo` |

`run_command` covers the menus: `group`, `ungroup`, `align`, `space_evenly`,
`bring_to_front`, `combine_shapes`, `rename_layer`, `delete_layer`, `new_frame`,
`surface_behind`, `make_component`, `add_variant` and two hundred more. Call
`list_commands` with an `area` (`layers`, `timeline`, `edit`, `measure`, `view`,
`document`) to find one, then pass what it needs in `arguments` (`layers`,
`seconds`, `track`, and its own options). A command that needs something picked
takes it there, so you never click.

## Facts that save a wasted step

- Coordinates are canvas points from the **top left**. A Retina screenshot has
  `pixelScale` 2 in `read_document`; the tools still speak points.
- A group's `frame` is the box it covers. **Layers inside a group are measured from
  the group's top left**, not the canvas.
- `read_document` lists 400 layers at most. On a big board, pass `layer` (a group,
  frame or component id) to read just that one in full.
- A component copy follows its original. Set the words of a piece inside a copy
  with `set_layer` `text` on that piece: they land on that copy alone and it keeps
  following the original in everything else. Never `make_unique` a copy just to
  change its words. To change how every copy looks, `run_command edit_original`.
- New words get the Text tool's soft legibility shadow. Pass `shadow: false` to
  `add_text` for an icon or a flat design, and `set_layer` `removeShadow: true`
  after recolouring words that sit on a solid surface (recolouring adds the halo back).
- `export` paths are absolute. An SVG keeps shapes, paths and text as vectors; a
  layer it cannot carry as a vector is listed in the answer as a picture.
- Video frames come back on black, as the MP4 holds them.
- If a call is refused, its one sentence says why and what to do instead. Read it.
- The person may be working in the app while you do. Never close their windows or
  touch documents they did not mention; `new_picture` and `new_video` give you
  your own.

## The house look

Photonz work should look designed, not assembled.

- **One grid.** Space and size things in steps of 8 (4 for tight detail): margins 24,
  32, 48, 64; gaps 8, 16, 24. Line edges up; use `align` and `space_evenly` rather
  than eyeballing numbers.
- **One of each.** One accent colour, one corner radius per kind of thing, one stroke
  width per drawing, one type family. Two weights at most on a page.
- **The app's own styles first.** Title pages and name cards come from `list_titles`;
  transitions from `set_transition`'s kinds; the document's own components when it
  has them. The Library's starters are placeholders, not a kit: never answer a request
  for components with them. Use one style throughout a piece and keep every repeat
  identical (same style, same words layout, same length).
- **Legible always.** Never light words on a light ground or dark on dark. Check every
  text layer against what is actually behind it in a render.
- **Names.** Name layers for what they are (`Title`, `Case 3`, `Primary Button`), so
  the Layers list reads like a table of contents.

## Recipes

### A video montage from History recordings

1. `list_history` and take the recordings (kind `video`) asked for; "the last 5" is
   the five newest, numbered oldest first unless the person says otherwise.
2. `new_video` with those `clips` in order: they land end to end on V1 and the frame
   takes the first clip's size.
3. `recommended_zooms` to see what the app suggests from each recording's clicks, then
   `apply_zooms` (one step for all of them).
4. `list_titles`, pick ONE title page style, and `add_title` with `clip` for each
   recording (a page in front of it, everything after moving along), plus the opening
   page in front of the first page or clip. Word every line you keep; a sample line
   you leave out is taken away.
5. `read_document` for the `cuts`, then `set_transition` the SAME kind and length on
   every cut (a dissolve of 0.5 s reads calm). Insert Title Page only puts one on the
   join into its clip.
6. `contact_sheet` across the whole video and `video_frame` on each page: same layout,
   right words, nothing flashing, zooms where the clicks are. Fix, then `export` mp4.

### Base components, a UI kit, controls in their states

"Base components", "a set of controls showing their states", "a UI kit":

1. Decide what the kit holds from what you know of the real one for that platform
   (Apple's when none is named; look its kit up on the web when you can). A set of
   base components is a dozen kinds or more, each with the states that kit shows
   for it (default, hover, pressed, focused, disabled; on and off; selected).
   A kind the person names is drawn whole, as they mean it: navigation is a bar
   with its links, a card holds its words, not one piece of either.
2. `add_text` the sheet's title at the top left, the largest words on it.
3. One `add_component` per kind: its `parts` (boxes, ovals, words, Pen paths, each
   with `x`, `y`, `width`, `height` inside the component; words sit centred in
   their box unless `alignment` says otherwise), `firstLook` naming the parts as
   given, and `looks`, each state with only what `changes`. Pass `labels: true`
   and the same `x` for every kind, each row's `y` below the last: Photonz lays
   the labelled rows out as one table (names down the left, each state named
   once over its column, every look starting at its column's left edge, rows evenly apart,
   the names starting on the title's left edge and the table ending that far from
   the right, the canvas grown when it needs room), so set no row names or state headers
   yourself. Only kinds with exactly the same states share a header row, so
   no cell is left empty: give every kind that has them the same states with
   the same names (Default, Hover, Pressed, Disabled), and keep a kind's own
   set (Off, On) to the kinds that need it. Rows of one family (names ending in
   the same word, such as Primary Button and Secondary Button) sit together, so
   name them that way. Each becomes one Library component with its
   states as versions.
4. Make them look like the kit: the system font at one small type scale, the
   platform's own colours, one corner radius per kind, padding on the 8 grid.
5. `render_picture` the sheet and fix what reads wrong.

### A photo

"A photo of a dog on a beach", "a photorealistic kitten in the snow": `add_photo` with
`subject` in the person's words (what it shows, what it is doing, where, the light). It is
painted by Photonz's picture model on this Mac at the canvas's shape, about a minute, and
lands as one ordinary picture layer: effects, crop and masks work on it. It is not traced,
so it is pixels, not paths: when the person wants editable shapes, an icon or vector art,
use `add_drawing` instead. With no picture model set up it answers that it cannot, and
Settings, Ask is where it is set up.

### A painting

"Paint a landscape in oil", "a watercolour of a harbour": paint it with the Brush, one
`paint_stroke` a stroke, never `add_drawing`. Give each stroke its `medium`, `color` and
`settings.size`; the first makes a Paint layer and the rest land on it. Work as a painter
does: block in the big areas edge to edge with a wide brush (strokes close enough that no
canvas shows, running the way each surface runs, starting and ending past the edges), then
the middle shapes with a brush half that size, then a few small strokes of detail and
light. Each area in three or four close shades. `path: "40,60 300,52 620,66"` is the
short way to write a stroke's points. `render_picture` after the block-in and at the end.

### An icon or a drawing as SVG

0. Try `add_drawing` first, for anything: pass what to draw in the person's words as
   `subject` (what it is, what it is doing, where), the look they named as `style`, `scene:
   true` for a place with its own sky or ground, `icon: true` for an icon. When Photonz's
   picture model is running it paints that and traces it into editable layers. When it
   answers that it cannot paint, call it again with `svg`, your own drawing as one whole
   SVG. Photonz has no stored drawings and no scenes of its own. Build it by hand, below,
   when you want your own drawing.
1. `new_picture` square (1024 x 1024); keep a margin of about a tenth on every side.
2. Build from real shapes and paths: `add_shape` for geometric parts, `add_path` with
   smooth points for curves (a cloud is a closed path of smooth bumps, or ellipses
   joined with `combine_shapes`). One stroke width throughout; fills from a small
   palette.
3. `render_picture` after each part; check balance and that it reads at 32 px too
   (`maxSize: 64`).
4. `export` `format: svg` (and a PNG if asked). Report what the SVG holds.

### Measurements on a screenshot

"Annotate with measurements", "measure the major elements", "redline this":

1. `open_document` the picture (or use the one open). A Retina capture reads in
   points at 2x.
2. `find_measurements` reads the picture's layout in code and hands back the
   redline a designer would: one size of each kind of control (four matching
   switches are measured once, on the first), then the margin, a card's
   padding, the row height, the gap between sections, the gap between
   neighbouring buttons and a button's label inset. Each mark has an id.
3. `mark_measurements` with the ids that answer the request: all of them for a
   general request, only the matching ones when the person names particular
   things (just the buttons, only the spacing). Never place these yourself:
   every readout is laid clear of words, controls and the other readouts,
   which hand-placed measurements are not.
4. When it lists nothing, or nothing that matches what was named,
   `find_elements` then `add_measurement` (`kind: size` with `box`, `kind: gap`
   between two `boxes`).
5. `render_picture` and say how many you placed.

### Finding the misalignments on a screenshot

"Find the misalignments", "check the spacing", "what is inconsistent here":

1. `open_document` the screenshot (a Retina capture reads in points at 2x).
2. `find_misalignments` reads the picture in code and lists each finding with an
   id, what is off with both numbers ("Gap 2 pt wider: 18 vs 16") and its box.
   Never measure these yourself and never change its numbers: they come off the
   pixels.
3. `mark_misalignments` with the ids worth showing (normally all of them). Each
   becomes its own editable redline layer, all in one undo step.
4. When it finds nothing, say so in one short sentence and mark nothing.

### A website's design system, then a second site in it

1. **See the source.** Photograph the page with headless Chrome, then open it:
   ```
   "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new \
     --hide-scrollbars --user-data-dir=/tmp/photonz-chrome --window-size=1440,2400 \
     --virtual-time-budget=10000 --screenshot=/tmp/source.png <url>
   ```
   `open_document` `/tmp/source.png`, then `render_picture` with `region` to read
   colours, type sizes, radii and spacing up close. `find_elements` gives real box
   sizes. Fetching the page's HTML or CSS (if you can) confirms exact values.
2. **One board.** `new_picture` large enough for everything (about 4000 x 3000): the
   styles and components along the top, the pages below.
3. **Styles.** `add_style` each colour by its role (Background, Surface, Text,
   Muted text, Accent, Border) and each text style (Display, Heading, Body, Caption,
   Button label) with the source's font, size and weight (fall back to SF Pro when the
   font is not on this Mac). Lay out a swatch and a type sample for each on the board,
   wearing its style (`apply_style`), labelled.
4. **Components**, one at a time, each the same way:
   - draw its pieces (`add_shape`, `add_text`), style them with `apply_style`;
   - `run_command group` them, `set_layout` the group (a button: `stack`, `row`,
     padding like 10 / 20; a card: `stack`, `column`, gap and padding; a nav bar: a
     `row` with a `width` and `spread`);
   - `run_command surface_behind` on the box that should be its background, so it is
     painted to the group's edges and the rest lies on top;
   - `run_command rename_layer` with its name, then `run_command make_component`;
   - `render_picture` it close up against the source region. It is a component when
     `list_components` lists it under `document`.
   Build the components the page actually uses: header and nav, buttons (each kind),
   links, a card, a list row, a footer, form fields if it has them.
5. **The second site.** Photograph it the same way to learn its content and structure.
   For each page: `run_command new_frame` at the page size, then `place_component` the
   components and word each copy with `set_layer` `text` on its pieces (a list of
   thirty stories is thirty copies of one List Row, each still a copy), plus
   `add_text` for content in the text styles, to rebuild it in the first site's
   language. Keep the first site's spacing and type scale.
6. Look at each page beside its source (`render_picture` regions), fix, and `export`
   PNGs of the board and the pages if asked.

If a step needs something no tool does, say exactly what was missing rather than
faking it with a flat picture.
