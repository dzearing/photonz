# 2.5D: layers turned in space

Flat layers that tip, swing and move in depth under one camera, Keynote's and
Apple Motion's kind of 3D. Mock: `docs/design/mocks/pages/video-depth.html`.
Code: `Sources/PhotonzCore/Space3D.swift` (model, maths, outline, click) and
`DocumentRenderer.placedInSpace` (drawing).

## The model

- `Layer.turn3D: LayerTurn3D?`: Rotation X (degrees, positive tips the top
  away), Rotation Y (degrees, positive swings the right edge away), Depth
  (points toward the viewer) and Pivot depth (points in front of the layer the
  turn is taken about; a cube face uses minus half the cube). Nil is flat, so
  old documents read and write byte for byte the same. Optional
  `showsBackFace: false` hides a card once it faces away (two sided cards).
- All four are `MotionProperty` values (`rotationX`, `rotationY`, `depth`,
  `pivotDepth`), keyed and eased like every other value, and offered in the
  panel's Animate a property picker under a 3D group.
- `PhotonzDocument.camera: SceneCamera?`: one camera, a setting of the frame
  (decision card `...-where-does-the-camera-live`, option A): Perspective
  (angle of view, 45 degrees by default, 0 is none), Camera depth (push in),
  Camera X and Y, optional focus (depth of field), and its own keys on the
  document clock (`cameraPerspective`, `cameraDepth`, `cameraX`, `cameraY`).
- Order of a layer's moves: its 2D turn first (in its own plane), then tip,
  then swing, then the push in depth, all about its pivot.

## Compatibility promise

The canvas is the plane z = 0 and the camera looks straight at it, so anything
flat projects onto exactly the pixels it covers today whatever the perspective.
A document with nothing turned and a camera left alone never enters any of the
3D path (`PhotonzDocument.isSeenInSpace`); a render test holds it byte for byte.

## Groups: flatten by default, keep in space on request

Where Keynote and Motion agree, and what CSS does:

- **Default, flattened.** A group draws what it holds in the order the layers
  list gives it, as one flat card, and the card turns as one. A child's own
  tilt still shows, flattened onto the card. Inside a card the camera is put
  back where it started (`Projection3D.unmoved`), so a camera move is taken
  once, by the card.
- **`GroupContent.keeps3D`.** Motion's 3D group, CSS `preserve-3d`: the
  children turn along with the group, each in space, and are drawn furthest
  first (ties keep stack order). Only a group that draws straight through
  (no styling, no clip, not a frame, no 2D turn) can; any other flattens.
- The top level is always stack order: a title pushed back stays over the clip
  below it, as in Keynote.

## Drawing

A flat card seen in perspective is a plane-to-plane map, so four corners decide
every pixel: each layer's finished picture is warped once with
`CIPerspectiveTransform`, after its 2D turn and before its shadow (the shadow
falls from the turned card). Depth of field blurs it first by
`|depth - focus| x amount / 100`. A frame seen in space is always drawn whole
(`RenderDiff`). Measured 2026-10-11: 1080p, ten layers, four tilted and one out
of focus, 5.5ms median, 8.2ms slowest (`Space3DPerfTests`).

## Everything else asks the same question

`drawnQuad(of:)` / `drawnMap(of:)` give where a layer lands; the selection
outline and handles, the click (`hitTestPath`), the marquee and the SVG
picture box all read them. SVG cannot say perspective, so a turned layer goes
out as its picture and is named in the export's fallback list.

## By hand: the canvas, the panel and the menus

Flag `next-turn-in-depth` (on in Next). Design A on the card
`...-how-do-you-turn-a-layer-toward-o`: resting on the turn knob brings out a
flat green arc (Rotation Y, drag sideways) and a tall red arc (Rotation X, drag
up and down); the knob's own middle still turns flat. A blue arrow off the
pivot pushes the layer away (drag up). Shift steps 15 degrees; the drag pill
names the value. Geometry and drag maths: `SpaceHandles`, `SpaceDrag`
(`Sources/PhotonzCore/SpaceEditing.swift`); canvas: `CanvasSpaceHandles.swift`
(the press and cue read `drawnSpaceHandles`, what the chrome last drew). A flat
layer wears nothing new until the knob is hovered; a layer turned in space keeps
its arrow and a pivot crosshair. One undo step per drag; a keyed value becomes a
key at the playhead (`PhotonzDocument.setSpaceTurn`).

Panel: a 3D section (`Space3DInspector`) with Rotation X, Rotation Y, Depth and
Pivot depth (only once turned), Mixed across several picks, arrow keys step
each layer from its own value, diamonds for one layer in a document with time.
Shown in documents with time, or on a still once a picked layer is turned.
Camera section (`CameraInspector`) when the frame is picked: View > Show
Camera Settings, or the Canvas row. Layer menu and right click: Reset 3D
Rotation, Bring Nearer (⌥⌘]) and Send Further (⌥⌘[), 100 points a step. View:
Reset Camera. Walks: `tilt-and-flip-a-title-in-3d-walk`,
`camera-settings-on-the-frame-walk` (the `spaceHandle` step drives the arcs
with real pointer events).

## Transitions and title entrances in depth

Step 4 (task `3d-transitions-and-title-entrances-flip-cube-swi`). Nothing new
is drawn: each move is the shots or the title's parts turned with
`LayerTurn3D`, so the warp, depth of field and the export are the ones above.

- **Hinge.** `LayerTurn3D.hinge` (a fraction of the box, nil for the flat
  turn's pivot) lets a layer turn about an edge; `Layer.spacePivot` is read by
  `spaceAffine` and the canvas crosshair.
- **Transitions** (`DepthTransitions.swift`): `ClipTransitionKind` Flip, Cube,
  Swing, Doorway, Revolve, Push in depth, listed after the six flat ones in the
  tiles, the Type menu and right-click Add Transition. `DepthTransition.parts`
  is the one geometry the renderer (`Layer.depthTransitionDrawn`) and the
  picker tiles read. Rule: nothing comes nearer than the canvas (each move
  backs off into depth by as much as an edge swings toward you), except the
  doorway's doors, which fade as they pass you. The cube also backs off
  `0.3 x width x sin(pi p)` so the face coming round is seen from the front.
  `ClipTransition.direction` (the way the outgoing shot leaves, Left by
  default) and `motionBlur` (off by default) are written only when set; the
  depth kinds default to 0.8 s on Ease in out (`defaultCurve`), and `fitted`
  lets an untouched curve follow the kind.
- **Motion blur.** A smear is now measured where the camera sees a layer
  (`drawnQuad(..., projection:)`), so keyed 3D turns smear on screen; a
  transition with Motion blur on gets its pictures smeared across a 180 degree
  shutter (`Layer.smearedTransition`).
- **Title builds**: `TitleBuildKind` Swing In (hinged at the edge Direction
  names), Flip Up (back hidden), Fly In From Depth, Tilt Settle, each with its
  out. Whole, they compile to keys on Rotation X/Y and Depth plus
  `TitleCompiler.turnSetup` (hinge, hidden back). By line, word or letter they
  are `TextRevealStyle`s whose `TextRevealPose` carries `turnX`, `turnY`,
  `depthEm`, `hinge`; `TextRevealCompositor` warps each piece through its
  own lens and smears it by its projected corners. Depth of field does not
  reach individual words.
- **A lens per word** (task `text-that-swings-flips-or-flies-in-from-depth-is`).
  Through the document camera (about 1300 px away at 1080p, centred on the
  whole text) a turning word measured near:far 1.04 at its midpoint and words
  off the middle leaned 15 to 35 px like italic type; the user called it "just
  2d animations". Each turning piece is now seen through its own camera
  (`TextRevealCompositor.lens`), centred on its line box and
  `lensDistance` (1.6) times its height (tipping) or width (swinging) away,
  never further than the document's and flat when the document has no
  perspective: the convention for animated type (CSS `perspective()` per
  letter). Depth is kept as the same share of the lens, so a word looks as far
  off and as small as before. Any travelling piece (turned, risen, tracked,
  blurred) may draw up to `TextRevealCompositor.reach(of:reveal:eyeDistance:)`
  past the text box, worked out by following each piece through its whole
  move; the renderer grows the layer's frame by it the way a shape's outside
  stroke does (task `words-that-rise-into-a-title-are-never-cut-off-b`). The depth
  entrances ease on Ease in out sine (half turned at half time), Flip Up starts
  edge on (90), Tilt Settle from 60, and Fly In closes its distance by
  `left²`. Midpoint near:far 1.32 to 1.57 by word and letter
  (`TextDepthPerspectiveTests`, `queue/audits/2026-10-11-text-depth-numbers.json`).
- **The mock in WebKit.** `docs/design/mocks/pages/video-depth.html` was drawn
  flat in WebKit (Safari, the Ghoztty viewer pane): WebKit flattens 3D under a
  rounded `overflow:hidden` clip. Its stages now clip with
  `clip-path: inset(0 round …)`, the title words carry their own
  `perspective()` and the card flip's camera is 400 px.
- **Measured** (2026-10-11): at the midpoint each transition shows a picture
  turned 20 degrees or more (numbers in
  `queue/audits/2026-10-11-depth-reel-numbers.json`); 1080p, ten layers mid
  transition, 5.0 to 6.0 ms median, motion blur on 6 to 16 ms median
  (`DepthTransitionRenderTests.perf`). Reel:
  `PHOTONZ_REEL=1 PHOTONZ_REEL_DIR=queue/audits Scripts/test.sh --filter DepthReelStudy`.
- Walks: `transitions-in-depth-at-a-cut-walk`,
  `transition-direction-on-a-click-walk`, `title-words-turn-in-depth-walk`.

## Not done here

The thin Camera row on the timeline (task
`show-the-camera-s-keys-on-a-thin-row-at-the-top`). Drag sprites and layer
thumbnails of a turned layer are drawn about their own small canvas's middle,
not the frame's.
