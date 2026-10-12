import PhotonzCore
import PhotonzRender
import SwiftUI

/// **Background**: what is behind a title's words, as tiles that play
/// (task `title-backgrounds-that-are-alive-auroras-energy`).
///
/// Opened from the Title section's Background row. Every moving look plays in
/// its tile in the title's own theme, so a person picks an aurora by seeing an
/// aurora, never by reading its name. The still ones (None, Solid, Gradient,
/// Glass) sit first; Glass only where there is a picture under the title.
/// No mock draws this picker: it is the transition picker's grammar (the
/// kit's tile grid), which is the panel's picker for a list you judge by eye.
struct TitleBackgroundPicker: View {
    @Environment(EditorState.self) private var editorState

    static let width: CGFloat = 372

    var body: some View {
        let recipe = editorState.titleRecipeInHand
        let theme = recipe?.theme ?? TitleTheme.curated[0]
        let current: TitleBackgroundKind? = recipe?.showsBackground == true ? recipe?.background : nil
        VStack(alignment: .leading, spacing: 0) {
            Text("Background")
                .font(.system(size: 10, weight: .bold))
                .kerning(0.8)
                .textCase(.uppercase)
                .foregroundStyle(VideoKit.Palette.faint)
                .padding(.horizontal, 12)
                .padding(.top, 10)
            VideoKit.TileGrid(columns: 3, spacing: 8) {
                tile("None", isOn: recipe?.showsBackground == false) {
                    TitleBackgroundSwatch(kind: nil, theme: theme, plays: false)
                } pick: {
                    editorState.setTitleBackgroundShown(false)
                }
                ForEach(TitleBackgroundKind.offered(glass: editorState.titleCanBeGlass), id: \.self) { kind in
                    tile(kind.title, isOn: current == kind) {
                        TitleBackgroundSwatch(kind: kind, theme: theme, plays: true)
                    } pick: {
                        editorState.setTitleBackground(kind)
                    }
                }
            }
            .padding(8)
            .playtestField("Background picker")
        }
        .frame(width: Self.width)
    }

    private func tile<Thumb: View>(_ name: String, isOn: Bool, @ViewBuilder thumbnail: () -> Thumb,
                                   pick: @escaping @MainActor () -> Void) -> some View {
        Button {
            pick()
        } label: {
            VideoKit.Tile(name: name, isSelected: isOn, thumbnailHeight: 58) {
                thumbnail()
            }
        }
        .buttonStyle(.plain)
        .playtestControl(name, detail: "Background picker")
        .panelHelp(name)
    }
}

/// A background as a small picture: a moving look playing in the title's
/// theme, or the still fill a solid, gradient or glass background is.
struct TitleBackgroundSwatch: View {
    /// Nil for no background at all.
    let kind: TitleBackgroundKind?
    let theme: TitleTheme
    /// Whether a moving look plays. Off for the swatch inside the Background
    /// row, which only names what is picked.
    var plays = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let kind, let look = kind.look {
                LiveLookThumbnail(paint: Paint(hex: theme.ground, kind: .live, stops: theme.liveStops,
                                               live: LiveBackdrop(look: look)),
                                  plays: plays && !reduceMotion)
            } else if let kind {
                switch kind {
                case .gradient, .mesh:
                    PaintFill(paint: Paint(hex: theme.ground, kind: .linear,
                                           stops: theme.backgrounds.enumerated().map { index, hex in
                                               GradientStop(hex: hex, position: Double(index)
                                                            / Double(max(theme.backgrounds.count - 1, 1)))
                                           },
                                           angle: 160))
                case .glass:
                    ZStack {
                        PaintFill(paint: Paint(hex: "#6E7C94", kind: .linear,
                                               stops: [GradientStop(hex: "#8FA3C4", position: 0),
                                                       GradientStop(hex: "#3C4658", position: 1)]))
                            .blur(radius: 3)
                        Color.black.opacity(0.25)
                    }
                default:
                    Color(hex: theme.ground)
                }
            } else {
                ZStack {
                    Color(nsColor: .controlBackgroundColor)
                    Image(systemName: "circle.slash")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(VideoKit.Palette.faint)
                }
            }
        }
        .clipped()
    }
}

extension TitleBackgroundSwatch {
    /// The small still a dropdown face wears in front of its value: a moving
    /// look's still picture, a gradient, or a flat colour.
    @MainActor static func still(_ kind: TitleBackgroundKind?, theme: TitleTheme) -> AnyShapeStyle? {
        guard let kind else { return nil }
        if let look = kind.look {
            let paint = Paint(hex: theme.ground, kind: .live, stops: theme.liveStops, live: LiveBackdrop(look: look))
            guard let picture = LiveBackdropPainter.cgImage(paint, size: CGSize(width: 28, height: 28)) else {
                return AnyShapeStyle(Color(hex: theme.ground))
            }
            return AnyShapeStyle(ImagePaint(image: Image(decorative: picture, scale: 2)))
        }
        switch kind {
        case .gradient, .mesh:
            return AnyShapeStyle(LinearGradient(colors: theme.backgrounds.map { Color(hex: $0) },
                                                startPoint: .top, endPoint: .bottom))
        case .glass:
            return AnyShapeStyle(Color(hex: "#6E7C94"))
        default:
            return AnyShapeStyle(Color(hex: theme.ground))
        }
    }
}

/// A moving look playing at the size of a tile, drawn by the canvas's own
/// programs (`LiveBackdropPainter`) about twenty times a second. A sketch
/// draws itself in again every nine seconds; everything else simply runs.
struct LiveLookThumbnail: View {
    let paint: Paint
    var plays = true

    var body: some View {
        if plays {
            TimelineView(.animation(minimumInterval: 1.0 / 20)) { context in
                picture(atMS: Self.moment(context.date, look: paint.live?.look))
            }
        } else {
            picture(atMS: nil)
        }
    }

    static func moment(_ date: Date, look: LiveLook?) -> Int {
        let ms = Int((date.timeIntervalSinceReferenceDate * 1000).truncatingRemainder(dividingBy: 3_600_000))
        return look == .sketch ? ms % 9000 : ms
    }

    private func picture(atMS ms: Int?) -> some View {
        GeometryReader { proxy in
            let scale: CGFloat = 2
            let size = CGSize(width: max(proxy.size.width, 1) * scale, height: max(proxy.size.height, 1) * scale)
            if let image = LiveBackdropPainter.cgImage(paint, size: size, atMS: ms) {
                Image(decorative: image, scale: scale)
                    .resizable()
            } else {
                Color(hex: paint.hex)
            }
        }
    }
}
