import PhotonzCore
import SwiftUI

/// The icon previews strip (Next, `next-icon-previews`).
///
/// A glass card in a corner of the canvas holding the icon frame you are working
/// in, drawn at each interface size up to twice its own, on a Light ground and
/// a Dark one, with the number under each pair. It appears when an icon frame is
/// what you are in and goes the moment you pick anything else.
///
/// Three things about the pictures are deliberate and are why it works:
///
///  - **Each picture is drawn AT that many pixels**, by the same path Export
///    takes (`DocumentRenderer.iconPreview`). A big picture shrunk smoothly
///    looks plausible and averages a hairline into a believable grey, which
///    would hide the exact thing the strip is for.
///  - **Nothing is smoothed on the way to the screen** (`.interpolation(.none)`),
///    so on a retina display you are looking at the icon's own pixels made
///    square rather than at a softened guess at them.
///  - **When the icon moves, so do the previews.** The card is where a motion is
///    reviewed, because a swing that reads beautifully on a 512 point canvas is
///    a shimmer at 16, so the transport lives here rather than somewhere you
///    would have to look away to reach (`EditorState+Motion`).
///
/// And one thing about the card: **nothing in it looks pickable.** It used to be
/// a row of chips, one per size, with one of them on a dark plate as the mock
/// drew it. On 2026-11-04 the user read that plate as the selected size, clicked
/// the others and nothing changed. So there is no chip: each ground is one
/// continuous band that every size sits on, and a press on the card does
/// nothing. It takes the press rather than letting it through, so a click on
/// the previews cannot pick something hidden under them and put them away.
struct IconPreviewsStrip: View {
    @Environment(EditorState.self) private var editorState
    /// Which sizes there is room for. Told, not read, so that panning the
    /// canvas does not redraw the pictures.
    let sides: [CGFloat]
    /// Whether this frame has anything to play.
    let showsTransport: Bool

    private static let groundRadius: CGFloat = 7
    private static let cardRadius: CGFloat = 12
    /// The Dark ground, in the mock's own near black and its edge, the same in
    /// light and dark mode: it is a ground to test against, not chrome.
    private static let darkGround = Color(hex: IconPreviews.darkGroundHex)
    private static let darkEdge = Color(hex: "#2A2F45")
    /// The words on the grounds. Fixed, not system colours, because what is
    /// behind them is fixed too whatever the mode.
    private static let wordOnLight = Color(hex: "#555B6E")
    private static let wordOnDark = Color(hex: "#AEB4C8")

    private var groundWidth: CGFloat {
        IconPreviews.groundWidth(sides: sides, hasTransport: showsTransport)
    }

    var body: some View {
        let tiles = editorState.iconPreviewTiles(sides: sides)
        VStack(alignment: .leading, spacing: 0) {
            header
                .frame(height: IconPreviews.titleHeight)
                .padding(.bottom, IconPreviews.titleGap)
            ground("Light", fill: Color(hex: editorState.iconPreviewGroundHex),
                   edge: AnyShapeStyle(.separator), word: Self.wordOnLight,
                   pictures: tiles.map { ($0.side, $0.light) })
                .padding(.bottom, IconPreviews.groundGap)
            ground("Dark", fill: Self.darkGround, edge: AnyShapeStyle(Self.darkEdge),
                   word: Self.wordOnDark, pictures: tiles.map { ($0.side, $0.dark) })
                .padding(.bottom, IconPreviews.groundGap)
            numbers(tiles)
        }
        .frame(width: groundWidth)
        .padding(IconPreviews.cardPadding)
        .glassEffect(.regular, in: .rect(cornerRadius: Self.cardRadius))
        // The press stops here. Nothing happens, and that is the point.
        .contentShape(.rect(cornerRadius: Self.cardRadius))
        .onTapGesture {}
    }

    /// What this is, and with a motion to review, the two controls that turn
    /// it into a review: one says watch it, the other says slowly enough to
    /// judge it.
    private var header: some View {
        HStack(spacing: 8) {
            Text("Actual sizes")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 0)
            if showsTransport {
                IconPreviewPlayButton()
                MotionSpeedMenu(name: "Preview Speed")
            }
        }
    }

    /// One band every size sits on, side by side along their bottom edges.
    private func ground(_ word: String, fill: Color, edge: AnyShapeStyle, word wordColour: Color,
                        pictures: [(side: CGFloat, image: CGImage?)]) -> some View {
        let height = IconPreviews.groundHeight(sides: sides)
        let leadings = IconPreviews.columnLeadings(sides: sides)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Self.groundRadius).fill(fill)
            RoundedRectangle(cornerRadius: Self.groundRadius).strokeBorder(edge, lineWidth: 1)
            ForEach(Array(zip(pictures, leadings)), id: \.0.side) { picture, leading in
                if let image = picture.image {
                    // Exactly `side` points across, which is the size the icon
                    // will really be: not resizable, not scaled to fit, and
                    // never smoothed.
                    Image(decorative: image, scale: 1)
                        .interpolation(.none)
                        .frame(width: picture.side, height: picture.side)
                        .offset(x: leading,
                                y: height - IconPreviews.groundInsetY - picture.side)
                }
            }
            Text(word)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(wordColour)
                .offset(x: IconPreviews.groundInsetX, y: 3)
        }
        .frame(width: groundWidth, height: height)
    }

    /// The numbers, one under each pair.
    private func numbers(_ tiles: [IconPreviewTile]) -> some View {
        let leadings = IconPreviews.columnLeadings(sides: sides)
        return ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(Array(zip(tiles, leadings)), id: \.0.id) { tile, leading in
                Text("\(Int(tile.side))")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
                    .frame(width: tile.side)
                    .offset(x: leading)
                    // A walk can name one size and read it off the label.
                    .playtestControl("Icon preview \(Int(tile.side))",
                                     detail: tile.light == nil || tile.dark == nil
                                         ? "Drawing" : "Drawn")
            }
        }
        .frame(width: groundWidth, height: IconPreviews.numberHeight)
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
