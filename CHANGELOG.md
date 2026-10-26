# Changelog

All notable user-visible changes. Format: `## <version> — <date>`, newest first.

## 0.19.0 — 2026-10-25

**Paint with real brushes.** Press B for the Brush and paint onto a Paint layer. Pick a brush from tiles that each show its own stroke: a graphite Pencil from hard and pale to soft and dark, charcoal, chalk and crayon that catch on the paper grain, a flat marker that darkens where strokes cross, an airbrush that builds up while you hold it, oil paint that carries and smears colour and runs dry, and watercolour washes that pool, bleed, granulate and bloom into each other while wet. Smudge mode smears what is already there. A pen's pressure, tilt and speed shape every brush, and a mouse stroke tapers in and out. Each brush keeps its own settings, shown over the tool bar and in the panel.

**Ask runs on your Mac, with nothing else to install.** Ask's model now runs inside Photonz. Settings > Ask downloads it once, Photonz starts it when you ask and lets it go when you are done, and it works with no network at all. Qwen3.8 27B is the new default. Ask can paint a drawing with a picture model on your Mac and trace it into layers you can edit. It plans a pose or a scene first, checks the drawing against the plan, and keeps every figure whole.

**Ask makes things, not just edits them.** Describe what you want with nothing open and Ask makes it. It can build a sheet of real components with their states, laid out as one clean table. Find the misalignments marks alignment, gap, padding and border faults as redlines on a screenshot. A request sent while Ask is busy waits its turn and can be cancelled, and each row says what it made, like "Drew a cat". Command K opens Ask on videos too, and Ask in the title bar is easy to spot.

**A File menu like every Mac app.** New sits at the top and makes an Image or a Video, followed by Open and Open Recent. The menu bar icon's menu starts the same way, with capture below.

**Lighter on memory.** Closing a window gives its memory back, and Photonz holds itself to a memory budget however long it stays open.

**Agents can drive Photonz.** An agent can reach the running app, run any menu command by name, read and see the open document, draw a picture, redline a screenshot, cut a video from History clips with titles, transitions and zooms, and build a design system.

**More you can do.** A layer can be flipped horizontally or vertically. A border follows the shape it is on, not the box around it. A chart is your own data and moves when your numbers change. The next thing you draw keeps the last one's look and fade. Opening a folded panel section takes room from the sections above it.

**Next is where most of this lives.** Open Experiments from the app menu to switch between Current and Next. Both ship in the same app.

**Fixes worth naming.** Smudging after a few paint strokes no longer freezes the app. The Library holds still under a click. A title part's timing dragged by hand survives a change of style.

## 0.18.0 — 2026-10-19

**Recording with sound works in the downloaded app.** In 0.17.0, macOS turned down the microphone for Photonz without ever asking, and the app never showed up under Privacy & Security > Microphone. That meant the released app could not record your voice at all. Now the first recording with the microphone on brings up the usual macOS prompt. Allow it once and your voice is recorded from then on.

**Keys you can see, pick and type.** Every key dot is picked with one click, and Backspace deletes it. Clicking a key opens a small popover just above it where you type that key's exact value, with a Reset at the bottom. A layer's track lists only the values that are actually animated. Once a layer has keys, any change you make to it keys itself. Pick a row by its name and drag the layer on the canvas, and the whole animation moves together. Width and height in the Info popover now keep their proportion, and a chain link turns that off.

**Curves you shape segment by segment.** On the value graph, a click picks a point or the stretch between two points. Command-click adds a point without changing the line's shape, and a plain click never adds one. Each segment has its own curve, set from its right-click menu or from Easing in the timeline bar, which also handles a mix of picked points and segments together. Option and the scroll wheel zoom the graph's values, and a double click fits them again. Camera keys now ease in and out like every other key.

**Sound stays with its picture.** A recording's own sound sits on a row just under its video and is joined to it, so adding, deleting or reordering tracks never pulls the two apart. Detach Audio moves the sound to an Audio track, and Re-attach brings it back. A sound clip opens a menu when you right-click it. Its volume line follows the same rules as the value graph: click to pick, Command-click to add, a curve for each segment, and a separate menu for each part.

**Ripple trim and Join Through Edit.** Hold Command while you drag a clip's edge and everything after it follows, so no gap opens. A cut that took nothing out joins back into one piece with Join Through Edit. Copy a transition from one cut and paste it onto others, or onto every cut inside a range. A cut with no spare frames offers to shorten itself so a dissolve fits. Option E opens a cut into its two clips on their own rows, showing exactly where both are on screen during the overlap.

**Speed that changes across a clip.** Add Speed Stops to a clip and its speed can ramp or hold between them. The speed curve shows under the clip, and you can drag its stops along and up and down while you watch the picture. A stop can become a freeze that holds its frame for as long as you like, and cutting a clip inside a freeze splits the hold between the two halves.

**More timeline editing.** Freeze Frame now asks how long the freeze should be and only holds that clip's track, unless you tick Freeze every track. Clean Noise and Hide Picture work on just one stretch of a clip, and a cleaned stretch eases in and out with no click at its edges. Right-click menus on the timeline are short and laid out the same way everywhere. A right-click never moves the playhead, and scrolling along time stays smooth.

**Titles with parts you can time.** Open a title on the timeline and Background, Headline, Subtitle and each other part gets its own row. Drag a row's ends to change when that part comes in and goes out. Anything made of parts, like a group, a name card or a component, opens into rows the same way the Layers list does. Double-click a title page while a recording is picked and the page goes right before the clip on the same track, joined by a real cross dissolve you can change, shorten or remove.

**Title pages that look like Apple made them.** Ten new title pages lead the shelf, each with careful type, calm colour and gentle motion. The older styles now sit under More Styles and have been toned down: one move per part, slower and quieter backgrounds, lighter headlines. Title text can have tracking, leading, the New York typeface and a gradient that sweeps through the words. Put Text on a Path lays a title's words along a curve you draw with the Pen, and you can animate them along it.

**A Library built for video, with charts.** In a video, the Library is a catalog grouped by kind: title pages, name cards, moving backgrounds, transitions, charts and your own media, all searchable. A moving background lands full frame with a double click or a drag. Six animated charts drop straight into a video: bars that grow, lines that draw, donuts that sweep and numbers that count up. You edit their data in the panel or paste it from a spreadsheet.

**Logos and pictures in a video.** PNG, JPEG, HEIC and SVG files come in through Import Media or a drop, just like footage. An SVG logo stays sharp at any size, even blown up on a 4K frame. Titles land on tracks named Title and pictures on tracks named Gfx, each with its own icon.

**Measuring in one blue.** Size, Gap and Distance now share one look, blue by default, and whatever colour you change one to, the next measurement of any kind starts with it. Gap measures the space the pointer is actually in, reading lines of text as whole lines. After a Size or Gap click, Measure stays in your hand so the next click measures the next thing. A picked Size measurement resizes by the box it measures, and a copied measurement is named for what it measures. A zoom callout tints the band between its two lines.

**A panel that reads top to bottom, and windows that know what they hold.** Layers sit at the top of the panel above a divider you can drag (double-click it to reset). Whatever you picked comes next, and the Library comes last. Pictures leave the Library off until you turn it on, and the panel uses plain switches. A picture opens in Image mode and is offered only the modes that fit it, while a video needs no mode at all.

**Icons and shapes.** Inside an icon, shapes snap to whole units, keylines, edges and centres, and a small readout names the spot. Hold Option to draw a box or circle out from its centre. Adding Rotation to a ring or arc makes it spin, and the timing strip says how long one turn takes. Copy SVG puts an icon's code on the clipboard as text you can paste into a code editor. A recent document's card offers Copy.

**Colour grade a clip.** Color Grade is now in Add Effect, with Temperature, Tint, Exposure, Contrast and Saturation. Each one is a slider you can key, and it starts on a warm grade.

**Next is where all of this lives.** Open Experiments from the app menu to switch between Current and Next. Both ship in the same app, so there is nothing extra to install, and switching takes a relaunch. The microphone fix applies to both.

**Fixes worth naming.** Finishing a typed title and keying a value on a video no longer make the app pause. Picking a title no longer makes the picture jump in size. Command E on a video keeps the clip. A recording that opens straight into Edit fits above the tool bar and the timeline. A lower third's caption plate keeps its gradient when you change its colour. Words that move into a title are never cut off at their box. A moved layer stays under whatever covers it for the whole drag. On small layers or layers turned in 3D, a press lands on what you aimed at.

## 0.17.0 — 2026-10-13

**Layers can turn in depth.** Any layer can now tilt, flip and move nearer or further away, seen through a camera with real perspective. Pick a layer and its 3D grippers are already on it: a flat arc swings it, a tall arc tips it, and an arrow off its pivot pushes it into the distance. Hold Shift to step by 15 degrees, and a small label shows the value as you drag. The same values sit in the panel, and older documents open exactly as they were.

**Transitions and titles that move in 3D.** Six new transitions turn one shot into the next in depth: flip, cube, swing, doorway, revolve and push. Each has its own length, curve, direction and motion blur. Title words can swing in, flip up, tilt or fly in from far away. Text that turns is drawn in true perspective, so the near edge looks nearer and the words never lean like italics.

**Titles that look designed.** The Library now has twelve title styles, from Keynote Clean and Editorial Serif to Tech Terminal and Kinetic Bold, plus three new lower thirds. A title arrives in parts: the background first, then the headline, then the subtitle and accents, and it leaves in reverse. Words can come in a line, a word or a letter at a time, type out with a blinking cursor, or wipe in behind a mask. Fast movement gets motion blur, and a Sounds switch adds a soft whoosh and a tick as the title builds.

**Restyle a title with a few knobs.** Change a title's theme, font pair, energy, intensity or background, and it lays itself out again with its words still easy to read. Original is always one click away. Title tiles in the Library play when you point at them, and a click picks one straight away. Editing a title's words or turning a knob never sets it playing, and one click picks any part of it.

**Title backgrounds that are alive.** A title page can sit on one of ten moving looks: Aurora, Energy Streams, Color Bubbles, Light Rays, Light Leaks, Wind Streams, Architectural Sketch, Particles, Liquid Gradient and Grid Horizon. You pick them from tiles that play, and you can set the speed, strength and scale of each. Backgrounds can also be moving gradients, grain, or your recording behind frosted glass.

**More of a layer can be animated.** Tilt and depth take keys just as easily as moving a layer does. A shadow's distance, direction, colour and opacity can be animated, and so can a glow's colour and a border's width and colour. Camera moves show as diamonds on a thin row at the top of the timeline, where you can click, drag or delete them. Every transition is tuned with a single Curve row, and two new curves, Ease out quint and Ease out expo, join the list everywhere.

**Faster timeline editing.** Drag a box across the timeline to pick everything it touches, then move or delete it all together. Drag near any edge and the timeline scrolls that way. A range you drew stays in place when you pick a clip, and right-clicking inside it acts on that clip's stretch. A click on the timeline moves the playhead there. Command with an arrow key nudges a clip by one frame, Option drag leaves a copy behind, and a copied clip pastes at the playhead. Several picked clips move to other tracks together, and you can pick several zooms and change them at once.

**Premiere's moves, in more places.** X marks the clip under the playhead, and Shift I and Shift O jump to the In and Out marks. Shift M and Command Shift M jump between markers. Clips and the playhead snap to markers, and you can drag a marker to a new moment. Command R opens the picked clip's speed. Click a gap and press Delete to close it, and any titles and music after it come along. A cut can be rolled to the playhead, and a clip a track will not take tells you why.

**A timeline you can read at a glance.** A gap shows as a dashed, hatched slot, a transition as a band across its cut, and a held frame as a still. A clip you have sped up or slowed down shows how long it originally was. An empty track looks empty, and the Captions track sits under the picture tracks while its words still show on top. Double-click a track group's name to rename it.

**Recordings are ready the moment you stop.** A recording is in history and opens the instant you stop, every time, including full-screen recordings that capture both the Mac's sound and the microphone. Saving an edited recording puts the finished video in history too. A recording that is only cut exports by copying the pieces it keeps, which is much faster. Copy an edit to the clipboard as a video or a GIF, and a GIF plays at the same speed as your edit. You can drag the recording control anywhere and it remembers where you put it. Command Left and Right switch the history filter.

**Watching and playing.** F puts a video in full screen and Escape brings it back, and Control Command F works too. Full-screen Retina recordings keep up as they play, even across cuts and when played backwards with J. The menu bar stays still while a video plays.

**Sound you can see.** A sound's waveform is drawn as one filled shape that follows its fades and volume. Its fade and level points are easier to see and grab, and its trim grip works wherever you take hold of it. Sound you detached can go back into its picture. You can choose the captions language before they are written, join two caption lines into one, and move a word back to the line before.

**Measuring finds the real thing.** Size mode now reads buttons, pills, cards, avatars, icons, badges and stacks. It tells them apart by colour and looks past their glow, at any size. Draw a rough box and it snaps to whatever is inside it. A size measurement is a single item, a faint box with its width and height, that moves, hides and deletes as one and lists as one row. Resizing a zoom callout keeps the shape of what it magnifies, and Shift lets you change that shape. A Magnify lens you drag around leaves no trail behind it.

**Lighter window shadows.** When you capture a window by clicking it, its shadow is now much softer than the one macOS draws. The shadow is a real effect, so you can open the capture later and make it darker, lighter or turn it off. Option-click still captures the window with no shadow at all.

**A calmer canvas and panel.** Position, size and rotation now open from an Info button at the end of the tool bar, or with F8, and they never sit over your picture. Every handle lights up when the pointer rests on it, so you know what a press will grab. Zooming brings up a small zoom control in the corner that fades away on its own. The panel shows a tool's settings only while you are using that tool, and menus and choices throughout the panel share one look. H picks the Hand and Highlight moves to U.

**Starting and building a UI design.** A new window opens on a start page with templates and your recent work, and Design UI starts you on a ready-made login screen. The starter Button comes as Primary, Secondary or Ghost, in three sizes, with an optional icon. A component can have a variant and a size at once, and Edit Original shows you a live copy as you change it. Path corners round when you pull a knob in from the corner, and Pen points show what kind they are as you draw. Copying a drawing also puts it on the clipboard as SVG.

**Next is where all of this lives.** Open Experiments from the app menu to switch between Current and Next. Both ship in the same app, so there is nothing extra to install, and switching takes a relaunch.

**Fixes worth naming.** Turning a layer shows the turn as it happens, every time. A zoom on a cropped video shows exactly the box you drew. A border on a picture that fills the frame shows up. A dip to black or white fades out and back in. Playing backwards at 8x keeps the picture moving. A clip on a locked track stays put. Clicking the empty canvas lets go of a zoomed recording. Blue buttons stay readable when another app is in front, and a new name field always takes your typing.

## 0.16.0 — 2026-10-04

**Record your screen and edit it in the same window.** A recording is now a document like any other. It is ready the moment you stop, it shows in history straight away, and it opens on a sharp first frame. An untouched recording opens to watch: the picture fills the window over the play controls, with nothing else in the way. One switch at the right of the title bar, or Command 2, brings the full editor in, and Command 1 tucks it away again. Save keeps your edit as a project you can open later, and Revert to Original takes you back to what you recorded.

**A real timeline for cutting.** Split a clip, drag the pieces around and drop the ones you do not want. Drag along the ruler to pick a stretch of time, then cut, copy, paste, merge or export just that stretch. Mark an In and an Out and take the stretch out with one key, and Play In to Out plays only that part. The keys you know from Premiere work as soon as a recording opens, including Q and W to trim up to the playhead, and S switches snapping off and on. Pinch to zoom the timeline, drag its top edge to make it taller, drag tracks by their headers to reorder them, and click a track's name to pick it so Delete removes it. Bring in a second clip and cut between the two.

**Change the pace.** Speed a stretch up as far as thirty times, or slow a moment down. The sound comes along between half speed and double, and the panel tells you when it has gone quiet. Hold on a frame for as long as you need, and anything you draw while the frame is held stays on screen for exactly that hold. Punch in on something and stay there.

**Zoom in on what matters, and show the clicks.** Add a zoom to a recording and choose where it looks. Follow Cursor makes the zoom glide after the pointer, and Suggest Zooms puts one around every run of clicks. Every click can also show a ripple, a pulse or a spotlight. You can slide a click to a new moment or hide one you do not want.

**Transitions between clips.** Click a cut and pick a transition from tiles, drag one from the panel onto a cut, or press Command T to use your default. Put one transition on every cut in a single step. A transition can sit before, across or after its cut, takes the sound across with it, and a dip can hold on black. A clip can also fade in from black and out to black.

**Title pages and name cards.** Insert a full-frame title page or a lower-third name card from a set of presets, type over it, then save your version as a preset of your own. A title page at the start plays before the recording and dissolves onto it, and a title stays readable over light footage. Titles and name cards also sit as picture tiles on the Library shelf.

**Captions written from the speech, on this Mac.** Choose Add Captions and the app listens to the sound and writes the captions on one Captions track, with nothing sent anywhere. Fix a caption one word at a time, on the picture or on its own lane. Choose how the words appear: a whole caption, a lower third, or a few words at a time with the current word lit. Burn the captions into the video, or save them beside it as an SRT or WebVTT file.

**Sound is something you can see and shape.** Every clip shows its sound on the timeline. Detach the sound from a picture, bring in a voiceover, and hear the sound under the playhead as you drag. Normalize brings up a quiet recording and cleans out background noise first. A picked sound has Audio Effects for Noise reduction, EQ and a Compressor. The mix shows how loud it is and stops itself from going louder than a file can hold. A volume slider sits beside the play controls.

**Animate anything.** Every value in the panel has a key diamond. Set keys to move a layer from one place to another, grow it or fade it, and its path appears on the canvas, where you can drag it into an arc. Copy keys from one layer to another, choose from the same eight easing curves everywhere, and open a layer's track to see one lane for each value that moves. Anything you draw on a video gets its own row on the timeline.

**Export the way you need.** An edited recording leaves through the same Export sheet as everything else. Choose its size, keep to your In and Out marks, and carry on working while a toast shows the progress. A five minute recording exports in less time than it takes to play, and an exported video plays with the same colours you saw in the editor. Any frame can come out as a picture. Save as WebP, choose the quality of any lossy format, and see what a PNG, GIF or SVG will weigh before you save it.

**Draw icons and make them move.** A frame can be icon sized, and it shows the square, the circle and the space an icon has to fit inside. Preview the icon at the sizes it will really be used. The Pen draws straight edges and curves in one outline, a rectangle can become a path you reshape, and two shapes can be joined, cut from each other or reduced to their overlap. Give a part of the icon a property that changes over time, and choose the point it turns around. A strip along the bottom shows every moving part on one cycle. The icon exports as a small animated SVG that stays sharp at every size.

**Take a screenshot apart.** One command separates a screenshot into layers: its text, its boxes, its cards and the rows inside them, with the hole behind each one filled in. Separated text becomes text you can retype in the same typeface, and a separated card keeps a real shadow. A size read off a screenshot matches the size the type really was, and an exported redline comes out as shapes rather than a flat picture.

**Drawing tools that feel right.** The paint bucket floods only the enclosed area you click, the way it does in Photoshop. Click once, let go and click again to draw a line or an arrow. Arrows can bend, and they come in Hand-drawn, Marker, Brush and Sketch styles. Cut a piece onto its own layer and fill the hole it leaves, copy the look of one shape onto another, and see in the Layers list when a layer is being used as a mask.

**Everything has a place.** Every command in the app is also in the menu bar, which is now arranged like a pro Mac editor's, in Title Case. A chip beside the window buttons sets the window up for Icon, Redline, Video or Design work. Every panel section opens and closes from its header, the choice controls are Liquid Glass, and messages tell you what happened in a few words.

**Guides that teach by doing.** New guides walk you through the app's real controls, grouped on shelves: Basics, Redlining, Looks, Colours and Styles, Components, Building UI, Video and Icons. You are offered the tour once, and finishing a guide leaves you ready to work rather than surrounded by samples.

**Next is where all of this lives.** Open Experiments from the app menu to switch between Current and Next. Both ship in the same app, so there is nothing extra to install, and switching takes a relaunch.

**Fixes worth naming.** Renaming a layer no longer quits the app. The first editor window after launch opens as quickly as the ones after it. Playing a recording never blinks, and scrubbing never goes black. A long captioned recording edits without freezing. Pressing Enter on the recording card starts recording at once. A shadow survives export to SVG. A turned shape keeps its turn while you move or resize it. Saying no to Screen Recording is remembered.

## 0.15.0 — 2026-09-12

**Build interfaces, not just mark them up.** A document can hold several screens, a screen is a frame you can size and name, and groups can hold groups as deep as you like. Drop a capture or a shape onto a screen and it goes inside that screen. Everything you build is still layers, so nothing you already knew stops working.

**Things arrange themselves.** A group can lay its contents out as a row, a column or a grid, with room on each of its four sides, a gap between pieces, and wrapping onto the next line when it runs out of width. Tell a container the smallest and largest it may be, tell one piece to take the room left over, or tell it to stretch. A label is as wide as its words, and a button and a card grow to fit their text. A container that is hiding something says so, and can be made to fit in one step.

**Components: make it once, use it everywhere.** Turn what you drew into a component and it goes on the Library shelf. Drag out as many copies as you like and they follow the original when it changes. Give one copy its own color, its own size, its own room or its own words without breaking the link, and everything you type is kept. A component can hold more than one version of itself, and a copy can be placed from any version. Components made in one document can be used in another.

**A Library for everything you want to reuse.** Save a color, a gradient, a text treatment or an effect under a name, then drag it off the shelf onto a swatch, onto a row in the layers list, or straight onto the picture. Edit the saved one and everything wearing it follows. The Library arrives with components already in it.

**One way to say what a shape paints.** Appearance holds what a shape simply has: its fill, its outline, its corner radius and its opacity. Effects is a list you add to: shadows, borders, glows and blur. Every part has a switch, a color and its own settings, all in the same shape, so a new effect works the way the last one did. Borders can sit inside the edge, on it, or outside it, can be offset from it, and you can have more than one. Each corner of a shape can be rounded on its own.

**A layer can change what is underneath it.** Put a box over part of a picture and blur it, pixelate it, drain the color out of it or invert it, with a setting to control how much. A layer can also say how it mixes with what is below it. Hiding a name or an email address before you send a screenshot is now something you do in the app, in one move, and it is baked into what you export.

**Columns and a grid you design to.** A screen can show the columns you are building to, starting where its padding starts. The canvas has a grid that thins and thickens as you zoom without ever disappearing, that things snap to while you resize as well as move, and that the arrow keys step by. Guides can be pinned to it.

**Redlining got sharper everywhere.** Measure has explicit modes for a distance, a size and a gap, picked from the tool button itself. Measurements snap to the edges the app finds in your screenshot, to the centres of things, to your guides and to the layers you drew, and Command still drags free. Hold Shift to lock the direction you are measuring. Numbers step out of the way instead of sitting on the thing they measure, and you can slide a number along its own line to any spot that reads better. You can measure shapes you drew yourself, not only screenshots.

**A Measurements panel and a spec you can hand over.** Every measurement in the document is a row you can name, select and delete, with Shift-click and Command-click to take several at once. One copy hands off both the redlined picture and its spec list.

**Arrows that carry a caption.** Type straight after you draw one and the words appear in a bubble that grows from the arrow, over more than one line if you need it. Drag the bubble wherever it reads best, make it a pill or a badge, and pick a different arrowhead.

**Capture a window by clicking it.** Point at a window and it lights up with its title, click and you have it, with its shadow and rounded corners intact. Dragging out a region gives you a loupe with pixel coordinates, the screen dims the instant you start, and the toast afterwards tells you how to open the editor.

**A tool bar that stops moving.** Tools are grouped the way a pro editor groups them, with press and hold on a button to reach the rest of its family or its modes, so picking up a tool never changes how wide the bar is. Choosing a mode from a tool's list now picks that tool up as well. The panel toggle sits in the window title bar where a Mac keeps it, and there is one color picker everywhere a color is chosen.

**Text that behaves.** A text box wraps its words instead of hanging out of its container, keeps room you gave it on purpose, and stays crisp when you zoom in or export at 2x. The font and size menus stop changing width as you move through them.

**Next is where all of this lives.** Open Experiments from the app menu to switch between Current and Next. Both ship in the same app, so there is nothing extra to install, and switching takes a relaunch.

**Fixes worth naming.** A border meets the fill and the edge cleanly, with no hairline of either showing through. A frame shows what you are getting while you drag its handle. Undo puts back a selection you lost. Locked layers stop offering handles that would resize them.

## 0.14.0 — 2026-08-22

**Saving a trimmed recording actually trims it.** Trim a video, press Command-S, and the file itself becomes the trimmed one. Dragging it out of History, pasting it, or opening it later all give you the clip you saved, not the original full length. Video windows now behave like image windows: Command-S saves, the title bar shows an edited dot, and closing with unsaved changes asks first. The untouched original is kept alongside, so trims never stack and "Revert to Original" in the Video menu brings the whole clip back. Recordings you trimmed in an earlier version open with unsaved changes so you can commit or discard them.

**Show in Finder on every capture.** Every tile in History, screenshot or recording, has Show in Finder next to Delete. The video tile's Export GIF and Export HEIC items are gone, since converting formats belongs in the editor's Export menu where MP4 and the quality presets already live. Copy GIF is still on the tile's Copy menu.

**Pin to screen is gone.** It only ever worked on screenshots, never recordings, and an action that shows up on half a list reads as broken. Tile actions are now Copy and Edit for images, Copy and Play for videos, then Show in Finder and Delete on everything.

**Three colors on a caliper.** A measure's line, its readout chip, and the chip's text are now colored independently. Transparency comes from each swatch's own picker, so a fully transparent chip leaves just the line and the number. Existing measurements open exactly as they were.

**Measurements remember what you last used.** Colors, thickness, label size, unit, decimals, and now effects like drop shadow all carry over to the next caliper you draw, the way shapes and text already did.

**Effects reach the whole caliper.** The readout chip is part of the layer now, so opacity, shadow, blur, and blend mode apply to it just like the rest of the measurement. What you see on the canvas is what exports.

**Draw it, then have it.** Every tool that creates something, shapes, text, zoom callouts, and measures, hands you back to Select with the new object selected, so you can nudge it with the arrow keys the moment it exists. Drawing five rectangles now means pressing R five times.

**An Experiments window.** The app menu and the menu-bar menu now open Experiments, where you choose which Photonz you run: Current, the one everyone gets, or Next, where the next-generation experience is being built. Both ship in the same app, so there is nothing extra to install. Switching takes a relaunch; feature flags inside a release apply right away.

## 0.13.0 — 2026-07-25

**A new measure tool.** Measuring is now one caliper instead of a pile of ruler styles. Drag or click out the span you want, then click once more to place the label arm wherever it reads best. The tool snaps to the edges it finds in your screenshot, so lining up on a button or a margin takes no fiddling. Hold Command if you want to ignore the snapping.

**Measurements you can adjust after the fact.** A finished caliper has three handles: the two ends and the label arm. Drag an end to change what you're measuring and the label stays put. Click the label itself to select the caliper.

**A label that stays readable at any zoom.** The measurement chip renders live over the canvas, so it looks the same whether you're zoomed way in or way out, and its border matches the caliper's line weight. Exported and flattened images still carry the label baked in.

**Simpler measure settings.** The inspector is down to what matters: unit, line thickness, label size, and color. Style, direction, and invert are gone because the caliper handles all of that by itself.

**Closing a window no longer loses your edits.** Closing an edited window, including a capture opened from history, asks whether to save instead of quietly throwing the work away. This had regressed in 0.12.0.

## 0.12.0 — 2026-07-19

**Windows open at the right size.** Opening a capture now sizes the window to the image. It shows at 100% whenever it fits, growing the window to give the canvas room to breathe, and only reduces the zoom when even a full-screen window can't hold the whole image at 100%. Your inspector panel's width and whether it's open carry over between sessions and factor into the sizing.

**Closing a window returns you where you were.** Closing an editor window now hands focus back to whatever you were using last, the way any normal window does, instead of pulling another Photonz window forward.

**Rasterize a layer.** Right-click a shape or annotation to bake it into a plain pixel layer in one step, effects and all. Undo brings the editable version right back.

**Load a layer as a selection.** Command-click a layer row, or use "Select Pixels," to turn the layer's shape into a selection you can work with.

**Outline shapes preview as you draw.** A rectangle with just a border now shows up while you're drawing it, instead of looking empty until you let go.

**Crisp borders while resizing.** Dragging a shape's corner now keeps its border at the right thickness and holds the opposite corner in place, instead of stretching until you release the mouse.

**Measurements read in logical pixels.** Measure readouts now default to logical pixels, so a Retina screenshot no longer reads at twice its size. A toggle switches to actual device pixels when you want them.

## 0.11.0 — 2026-07-19

**The editor works at any window size.** The floating toolbar now tucks its overflow into a "…" menu when space runs short, and it floats over the canvas instead of pushing the inspector off-screen. The inspector collapses on its own when the window gets narrow, with a toggle to bring it back, and the window has a sensible minimum size so nothing gets squeezed into an unusable state.

**A roomier, resizable layers panel.** The layers list no longer clips its top rows. It sizes to its content, stays within bounds, scrolls on its own when you have a lot of layers, and has a drag handle so you can make it taller or shorter.

**One color control, everywhere.** Picking a color now works the same way in every spot: swatches, recent colors, HSB and hex fields, and an eyedropper. Each tool remembers the color you last used with it, and Fill and Border each have their own checkbox so you can turn either off.

**Solid shapes by default.** Rectangles and ellipses now fill when you draw them, with simple No Fill and No Border options when you want an outline or a blank shape. A zero-width border no longer leaves a stray hairline.

**Drawing tools stay put.** Drawing tools now stick after you use them, Photoshop style, instead of snapping back to the last selection. The Magic Wand lives with the other selection tools.

**Zoom matches your screen.** Captures and saved images now carry your display's scale, so 100% in the editor is truly the size you see on screen, whether or not you are on a Retina display.

## 0.10.0 — 2026-07-18

**The capture history is easier to browse and quicker to navigate.** The history overlay now has matching margins on the left, right, and top, so it opens wider and gives your captures more room. When it opens, the first item is selected with a highlighted outline, and you can move between captures with the left and right arrow keys. The selected item shows its action buttons, while the others show a friendly note like "15 seconds ago" or "30 minutes ago" so you can see at a glance when each one was taken.

**Filter by what you captured.** A new segmented control at the top lets you switch between All, Screenshots, and Videos, so you can zero in on just the kind of capture you're looking for.

**Copy as GIF shows its progress.** Turning a recording into a GIF takes a moment, so a small progress toast now appears in the bottom-right corner while it's being prepared, instead of leaving you wondering whether anything is happening.

## 0.9.0 — 2026-07-18

**Video controls float and stay out of your way.** The playback controls now hover over the video, QuickTime style, instead of sitting in a fixed strip below it. They stay hidden until you move the pointer toward the bottom of the window, then fade away again once you move off, so nothing covers the video while it plays. Resting the pointer on the controls keeps them up; pressing play tucks them away. You can drag the whole controller to reposition it.

**A real volume control.** The controller now carries a volume slider and a speaker button to mute or unmute, and it remembers your level when you toggle mute. The scrubber and volume slider also got a cleaner, more native look, with a thicker rail and rounded thumbs.

**Undo only when there's something to undo.** The undo button now appears only for an edit you made this session, and its tooltip spells out exactly which action it will reverse.

## 0.8.0 — 2026-07-17

**The video editor plays like a real player.** Recordings now autoplay when opened and get a proper scrubber: a progress line with a draggable thumb, click-to-seek, and timecodes at each end, with the playback controls centered beneath it. Trim handles no longer take over the window the moment a video opens.

**Trim is now a mode, like crop.** A new scissors button (next to crop) opens trim mode with the familiar Reset, Cancel, and Done controls. Done applies your selection (undo brings it back), Cancel restores things as they were. All the edit buttons on the right side now share the same circular style, so copy and export no longer look out of place.

**Mic recordings can't fail silently anymore.** Starting a recording with a microphone selected used to hang or quietly discard the capture if macOS hadn't settled mic permission yet. Photonz now resolves microphone access before the recording starts, and if something does go wrong you get told instead of losing the take.

## 0.7.0 — 2026-07-13

**Copy straight from the capture toast.** Right after a recording finishes, the toast now has a Copy button: pick **Copy Video** for the MP4 or **Copy GIF** for an animated GIF — no need to open history first. GIFs export at the recording's own frame rate, so the motion is as smooth as what you captured.

**Recording never steals your focus.** Kicking off a recording with <kbd>⌘⇧5</kbd> from another app (say, your browser) no longer yanks an open Photonz editor window to the front. Focus stays right where you left it — whether you start the recording or cancel the setup card.

## 0.6.0 — 2026-07-10

**The video editor grew up.** Recordings now open in a window sized to show the video at its real size, appearing in one step instead of opening small and resizing. You can pinch to zoom and two-finger scroll to pan the video just like images, double-tap the trackpad to jump between fit and 100%, and double-click the empty background to maximize the window.

**Crop by drawing a rectangle.** Cropping a video now works the way you expect: drag a rectangle around the part you want to keep, then fine-tune with the handles. The moment you hit Done, the preview shows just the cropped region, so what you see is what exports. Cancel puts things back the way they were.

**Thumbnails tell the truth.** After you trim or crop a recording, its thumbnail in the capture history updates to match: the picture shows the cropped region from inside the trimmed range, and the length badge shows the trimmed duration. Recording toasts now show a real thumbnail too, with the same play button and length badge as history.

## 0.5.1 — 2026-07-07

**No more permission prompt loops.** Photonz now asks for Screen Recording and Microphone access at most once per launch. If macOS has already recorded a decision, the app respects it instead of re-prompting, and it registers itself with the system before sending you to System Settings, so the Photonz row is already there when you arrive.

**Copy polish.** All in-app text got a pass for plainer, friendlier wording.

## 0.5.0 — 2026-07-06

**Photonz updates itself.** When a new version ships, a small dot appears on the menu-bar icon and the menu offers "Update to vX.Y.Z & Restart" — one click downloads the release, verifies its signature and notarization, swaps it in, and relaunches. "Check for Updates…" offers the same in-place update. No more manual DMG downloads.

**A menu-bar icon that's actually Photonz.** The status item now shows the app icon's ring-and-aperture mark instead of a generic camera symbol, so it's easy to spot at a glance.

**Smoother permission setup.** The microphone prompt now comes to the front instead of appearing behind other windows, and the welcome panel no longer vanishes while you answer it. If macOS refuses to add Photonz to the Screen Recording list (it happens), the walkthrough now explains the fix — use the + button in System Settings — with a "Show Photonz in Finder" button that puts the app in hand for picking.

## 0.4.0 — 2026-07-06

**Copy recordings as video or GIF.** The copy button on a recording (history overlay and video editor) now lets you choose: **Copy Video** puts the MP4 on the clipboard, **Copy GIF** re-encodes and copies an animated GIF — and both paste properly into chat apps like Microsoft Teams and Slack (the clipboard now carries the same file flavors a Finder copy does). Edited copies confirm with a toast when the clipboard is ready.

**Your trim sticks.** Trims and crops made in the video editor are now remembered next to the recording, so exporting or copying from the capture history produces the trimmed clip — not the full-length original. Reopen a recording and your trim handles are right where you left them.

**Friendlier first run.** A welcome walkthrough now guides new installs through the one-time macOS setup: granting Screen Recording (with a relaunch handoff), optionally enabling the microphone for narrated recordings, and freeing <kbd>⌘⇧3/4/5</kbd> when macOS's own screenshot shortcuts are holding them. Reopen it anytime via "Welcome & Permissions…" in the menu.

## 0.3.1 — 2026-07-05

No app changes — a cleaner install. The app bundle itself is now notarized and stapled (not just the DMG), so Photonz launches without any Gatekeeper prompt on other Macs, even on first launch with no network. If an earlier download warned that Apple "could not verify" the app, re-download — that build predated the fix.

## 0.3.0 — 2026-07-05

Photonz grew from an editor into a resident screenshot studio: it now lives in your menu bar, records your screen, measures UI like a design tool, and selects regions like Photoshop.

**Lives in your menu bar.** Photonz is now an always-available agent: capture a region (<kbd>⌘⇧4</kbd>) or full screen (<kbd>⌘⇧3</kbd>) from anywhere, slide down a global capture history overlay (<kbd>⌘⇧H</kbd>), pin any capture as a floating window, and open as many editor windows as you like — one per image. A Quick Access Overlay pops in after each capture for instant pin/edit/copy/save.

**Screen recording.** <kbd>⌘⇧5</kbd> records a region or the full screen with your choice of microphone and a floating stop button. Recordings land in history; trim and crop them in the video editor, then export MP4, GIF, or animated HEIC.

**Measure like a designer.** The new dimension tool (<kbd>I</kbd>) drags pixel-perfect measures with automatic labels, bracket or line caps, and units — and its corners magnetize to the actual UI edges in your screenshot (text baselines, buttons, borders), with ⌘ to drag free. Perfect for spacing audits and redlines.

**Photoshop-style region selection.** Box (<kbd>M</kbd>), ellipse (<kbd>⇧M</kbd>), and magic wand (<kbd>W</kbd>) selections with ⇧ add / ⌥ subtract / ⇧⌥ intersect (the cursor shows a live +/−/× badge), edge snapping, and marching ants for any shape. While a region is active: the bucket fills it, <kbd>⌫</kbd> slices it out of the layer (the layer's frame tightens to what survives), dragging moves the pixels (⌥ for a copy), <kbd>⌘C</kbd> copies the clipped composite, and <kbd>⌘J</kbd> promotes it to a layer. <kbd>⌘N</kbd> makes a new empty layer while keeping the selection, <kbd>⌘D</kbd> deselects, <kbd>⇧⌘I</kbd> inverts.

**A real fill kit.** Paint bucket (<kbd>G</kbd>) with Photoshop-style foreground/background swatches (<kbd>X</kbd> swaps), ⌥⌫ fill, ⌫ clears the Background to your background color, and growing the canvas paints the new area with it. New shapes and text draw in the current foreground color.

**Collage & canvas.** Arrange photo layers into a collage layer with live slots — drop, swap, and reflow by resizing; a Canvas pseudo-layer in the panel lets you resize the document by dragging its edges (⇧ for centered).

**Editor upgrades.** Multi-select layers by marquee and batch-delete; text scaling and a full font picker; a proper color picker with recent colors; the toolbar split into tools / colors / zoom bars with a zoom slider and % stops; undo/redo hardening and redesigned arrows.

**Shortcuts are Photoshop-consistent now**: <kbd>M</kbd>/<kbd>⇧M</kbd>/<kbd>W</kbd> select, <kbd>⌘D</kbd> deselect, <kbd>⌘N</kbd> new layer (New from Clipboard moved to <kbd>⌥⌘N</kbd>), Measure moved to <kbd>I</kbd> (Photoshop's ruler group).

## 0.2.0 — 2026-06-13

Beta. Every editing tool that was a placeholder in 0.1.0 is now wired up — Photonz is feature-complete for daily use, but still pre-1.0 while it gets real-world testing.

**Zoom callouts (the signature feature).** Press <kbd>Z</kbd>, drag a box over any detail, and Photonz flies in a magnified callout connected by leader lines. Choose a rectangle or circle, dial the magnification, and restyle the border — perfect for documentation and bug reports.

**Annotate anything.** Arrows, rectangles, ellipses, highlights, and rich text with full font control. Tools stay sticky for rapid markup, and every annotation remains editable after the fact — re-color it, change stroke width, drag its endpoints, or resize the whole thing. Text gets an automatic contrast shadow so it stays legible on any background.

**Transform tools.** Crop with a dimmed surround, thirds grid, and aspect locks; resize in pixels or percent with presets and an aspect lock; set the canvas size from any anchor; rotate with a knob and skew from the corners. Image layers can be cropped individually.

**Real layers.** A full layers panel with thumbnails, visibility, lock, opacity, drag-to-reorder, and rename. Promote any selection to its own layer (<kbd>⌘J</kbd>), then style it non-destructively — blur, opacity, borders, rounded corners, and drop shadows are all applied live at render time and never baked into pixels. One-click blur-behind (<kbd>⇧⌘B</kbd>) builds a blurred backdrop with a sharp focal cutout. Copy and paste layers, or paste images straight from the clipboard.

**Capture &amp; share.** Grab a screen region (<kbd>⌘⇧4</kbd>) or a full screen (<kbd>⌘⇧3</kbd>) directly into Photonz, browse past captures in a history carousel (<kbd>⌘⇧H</kbd>), save editable `.photonz` documents, and export PNG, JPEG, or HEIC at 1× or 2× (or copy the composite with <kbd>⇧⌘C</kbd>).

**Feels like macOS.** Liquid Glass surfaces throughout, fluid micro-animations, an app icon and About panel, an onboarding empty-state, and a complete, audited keyboard-shortcut set with full menus.

**Fast.** Metal-accelerated Core Image compositing with a content cache and dirty-rect incremental rendering: a 12-megapixel, 10-layer document re-renders in single-digit milliseconds — comfortably under one frame.

Developer ID signed. Notarization is still being finalized, so macOS may ask you to right-click → Open on first launch until a notarized build lands.

## 0.1.0 — 2026-06-12

First preview release — the foundation, not the product.

- Native macOS app (Apple silicon, macOS 26+) with a Liquid Glass toolbar.
- Open or drag-and-drop an image; zoom in/out; undo/redo.
- Under the hood: layered document model, GPU-accelerated Core Image compositor, snapshot undo history, and a fully tested geometry core for the editing tools to come.
- Known limits: annotation/crop/text/zoom-callout tools are visible but not wired up yet. Unsigned build — right-click → Open on first launch.
