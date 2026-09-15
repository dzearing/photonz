import PhotonzCore
import SwiftUI

/// The icon previews strip (Next, `next-icon-previews`).
///
/// A glass row in the canvas's top left corner, one chip per size, holding the
/// icon frame you are working in drawn at 16, 24, 32, 48 and 64 pixels with the
/// number under each. It appears when an icon frame is what you are in and goes
/// the moment you pick anything else.
///
/// Three things about it are deliberate and are the whole reason it works:
///
///  - **Each picture is drawn AT that many pixels**, by the same path Export
///    takes (`DocumentRenderer.iconPreview`). A big picture shrunk smoothly
///    looks plausible and averages a hairline into a believable grey, which
///    would hide the exact thing the strip is for.
///  - **Nothing is smoothed on the way to the screen** (`.interpolation(.none)`),
///    so on a retina display you are looking at the icon's own pixels made
///    square rather than at a softened guess at them.
///  - **When the icon moves, so do the chips.** The card is where a motion is
///    reviewed, because a swing that reads beautifully on a 512 point canvas is
///    a shimmer at 16, so the transport lives here rather than somewhere you
///    would have to look away to reach (`EditorState+Motion`).
///
/// With nothing moving it is still pure chrome: no header, and no hit testing
/// at all, so it can never eat a drag, and it is never in an export.
struct IconPreviewsStrip: View {
    let tiles: [IconPreviewTile]
    /// Whether this frame has anything to play. With a still icon the card is
    /// exactly the row of pictures it has always been.
    let showsTransport: Bool

    /// Between two chips.
    static let gap: CGFloat = 10
    /// Inside the glass, on every side.
    static let padding: CGFloat = 10
    /// The number under a chip, and the air above it.
    static let labelHeight: CGFloat = 16
    /// The transport row, and the air under it. Nought when there is no
    /// transport, which is what `iconPreviewsReservedRect` leans on.
    static let headerHeight: CGFloat = 24
    /// The corner every chip is cut with.
    private static let chipRadius: CGFloat = 7
    private static let cardRadius: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showsTransport { header }
            chips
        }
        .padding(Self.padding)
        .glassEffect(.regular, in: .rect(cornerRadius: Self.cardRadius))
        // Clicks only once there is something to click. With a still icon the
        // card is what it always was: chrome that can never eat a drag. With a
        // transport it takes them, the way the zoom bar and the tool settings
        // capsule do, and the pictures themselves still refuse them.
        .allowsHitTesting(showsTransport)
        .padding(EditorChromeLayout.cornerInset)
        .transition(.opacity)
    }

    /// Play, and how fast. The two controls that turn a row of pictures into a
    /// review: one says watch it, the other says slowly enough to judge it.
    private var header: some View {
        HStack(spacing: 8) {
            Text("Real size")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
            IconPreviewPlayButton()
            MotionSpeedMenu(name: "Preview Speed")
        }
        .frame(height: Self.headerHeight - 6)
    }

    private var chips: some View {
        HStack(alignment: .bottom, spacing: Self.gap) {
            ForEach(tiles) { tile in
                VStack(spacing: 4) {
                    chip(tile)
                    Text("\(Int(tile.side))")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                // A walk can name one preview and read its size off the label.
                .playtestControl("Icon preview \(Int(tile.side))",
                                 detail: tile.image == nil ? "Drawing" : "Drawn")
            }
        }
        .allowsHitTesting(false)
    }

    /// One preview on its chip. The chip is what makes a picture visible at
    /// all: a frame that paints no surface of its own comes back transparent,
    /// and transparent on glass is nothing.
    private func chip(_ tile: IconPreviewTile) -> some View {
        RoundedRectangle(cornerRadius: Self.chipRadius)
            .fill(.quaternary)
            .overlay {
                if let image = tile.image {
                    // Exactly `side` points across, which is the size the icon
                    // will really be: not resizable, not scaled to fit, and
                    // never smoothed.
                    Image(decorative: image, scale: 1)
                        .interpolation(.none)
                        .frame(width: tile.side, height: tile.side)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: Self.chipRadius)
                    .strokeBorder(.separator, lineWidth: 1)
            }
            .frame(width: IconPreviews.chipSide(for: tile.side),
                   height: IconPreviews.chipSide(for: tile.side))
    }
}

/// Play and pause on the previews card.
///
/// The same one state the Motion header's button answers for, deliberately: a
/// second switch for the same thing would be two answers to one question. This
/// one exists because the review happens HERE, at the sizes the icon will
/// really be, and looking away to the side column to start it is looking away
/// from the thing being judged.
private struct IconPreviewPlayButton: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        Button {
            editorState.toggleMotionPreview()
        } label: {
            Image(systemName: editorState.isMotionPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 10, weight: .medium))
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(editorState.isMotionPlaying ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .accessibilityLabel(editorState.isMotionPlaying ? "Pause the preview" : "Play the preview")
        .panelHelp(editorState.isMotionPlaying
                   ? "Stop the loop and put the picture back to the one you drew (Space)"
                   : "Watch it loop at the sizes it will really be used (Space)")
        .playtestControl("Real Size Preview",
                         detail: editorState.isMotionPlaying ? "playing" : "stopped")
    }
}

/// How fast the loop runs (`MotionSpeed.swift`).
///
/// This is what replaces scrubbing a playhead. You cannot usefully drag a hand
/// through 900 milliseconds that repeat, and ninety milliseconds of lag between
/// two parts of one drawing is under six frames at full speed, so the way to
/// judge it is to slow the whole loop until your eye can keep up. Everything
/// slows together, the lag included, because a lag is not a thing in the model:
/// it is the distance between two starts on the one ruler this rate scales.
struct MotionSpeedMenu: View {
    @Environment(EditorState.self) private var editorState
    /// What a walk calls it. There are two of these on screen at once, one on
    /// the previews card and one on the timing strip, and they answer for the
    /// same rate.
    let name: String

    var body: some View {
        Menu {
            ForEach(MotionSpeed.choices, id: \.self) { speed in
                Button(speed.menuTitle) { editorState.setMotionSpeed(speed) }
            }
        } label: {
            Text(editorState.motionSpeed.title)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(editorState.motionSpeed.isSlowed
                                 ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Preview speed")
        .panelHelp("How fast the loop runs. Slow it down to judge a lag no one "
                   + "can see at full speed")
        // Named as a ROW rather than as a control, because a menu wears its own
        // value: naming it by its words would name it "1×" until the moment a
        // walk used it. The row holds still and the words go in the detail,
        // which is the promise every menu in the panel makes.
        .playtestField(name)
    }
}
