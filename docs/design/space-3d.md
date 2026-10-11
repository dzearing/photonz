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

## Not done here

The thin Camera row on the timeline (task
`show-the-camera-s-keys-on-a-thin-row-at-the-top`), 3D transitions and title
entrances (step 4). Drag sprites and layer thumbnails of a turned layer are
drawn about their own small canvas's middle, not the frame's.
