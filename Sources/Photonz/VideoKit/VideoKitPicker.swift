// The kit stands on its own (Scripts/test.sh typechecks it alone, and the
// gallery compiles it with nothing else), so the one pure piece of core it
// uses, `TileGridPlan`, is compiled in beside it there instead of imported.
#if canImport(PhotonzCore)
import PhotonzCore
#endif
import SwiftUI

// MARK: - A tile

extension VideoKit {
    /// A picker tile (`shell.css` `.libtile`): a thumbnail over a name and a
    /// line of detail. The one card every "pick one of these" uses, whether it
    /// is media, a component, a style or a transition, so a person learns the
    /// grammar once.
    struct Tile<Thumbnail: View>: View {
        /// What colour says "this one is picked". Accent for most things,
        /// the component colour for components, amber for a transition (the
        /// same amber a picked cut wears).
        enum Emphasis { case accent, component, cut }

        let name: String
        var detail: String?
        var isSelected = false
        var isDisabled = false
        var emphasis: Emphasis = .accent
        /// The thumbnail's height. Nil for a card thumbnail that keeps a 16:10
        /// shape as the tile grows; the transition tiles use a 30pt strip.
        var thumbnailHeight: CGFloat?
        @ViewBuilder let thumbnail: Thumbnail

        @State private var isHovering = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 10)
            VStack(alignment: .leading, spacing: 0) {
                thumbnailWell
                VStack(alignment: .leading, spacing: 1) {
                    // A name a few points too long for the card ("Tutorial
                    // Sample.mp4" on a Library card at the dock's resting
                    // width) sets a little smaller rather than losing its end.
                    Text(name)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .truncationMode(.tail)
                    if let detail {
                        Text(detail)
                            .font(.system(size: 9, design: .monospaced))
                            .kerning(0.2)
                            .foregroundStyle(Palette.faint)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 7)
                .padding(.top, 5)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(shape.fill(Palette.glassThin))
            .overlay(alignment: .top) {
                Rectangle().fill(Palette.edgeHi).frame(height: 1).padding(.horizontal, 6)
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(borderStyle, lineWidth: isSelected ? 2 : 1))
            .shadow(color: isHovering && !isSelected ? .black.opacity(0.35) : .clear, radius: 6, y: 5)
            .offset(y: isHovering && !isDisabled ? -1 : 0)
            // Quieter, never gone: at 42% its faint detail read 1.5:1, under
            // the system's own disabled label (`Legibility.disabledFloor`).
            .opacity(isDisabled ? 0.55 : 1)
            .contentShape(shape)
            .kitHover(name) { isHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }

        @ViewBuilder private var thumbnailWell: some View {
            if let thumbnailHeight {
                thumbnail
                    .frame(maxWidth: .infinity)
                    .frame(height: thumbnailHeight)
                    .clipped()
            } else {
                Color.clear
                    .aspectRatio(16 / 10, contentMode: .fit)
                    .frame(minHeight: 40)
                    .overlay { thumbnail }
                    .clipped()
            }
        }

        private var borderStyle: AnyShapeStyle {
            guard isSelected else {
                return isHovering ? AnyShapeStyle(Palette.accent.opacity(0.32)) : AnyShapeStyle(Palette.edgeLo)
            }
            switch emphasis {
            case .accent: return AnyShapeStyle(Palette.accent)
            case .component: return AnyShapeStyle(Palette.comp)
            case .cut: return AnyShapeStyle(Palette.warn)
            }
        }
    }
}

// MARK: - The grid they sit in

extension VideoKit {
    /// The grid of tiles (`.libgrid`): as many columns as fit at 96pt or
    /// wider, every tile the same width, so the dock decides how many cards
    /// there are (two at rest, four in a widened dock) instead of the grid
    /// forcing a count. `columns` pins a count, as the transition picker's two
    /// do.
    struct TileGrid: Layout {
        var minimumWidth: CGFloat = Metrics.tileMinimumWidth
        var columns: Int?
        var spacing: CGFloat = 8

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            // An unbounded offer (a frame with no maximum) is answered with
            // the narrowest grid that fits: `TileGridPlan` owns why.
            let plan = plan(width: proposal.width)
            let heights = rowHeights(subviews, plan: plan)
            let total = heights.reduce(0, +) + spacing * CGFloat(max(0, heights.count - 1))
            return CGSize(width: plan.width, height: total)
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            let plan = plan(width: bounds.width)
            let heights = rowHeights(subviews, plan: plan)
            var y = bounds.minY
            for (row, height) in heights.enumerated() {
                for column in 0..<plan.columns {
                    let index = row * plan.columns + column
                    guard index < subviews.count else { break }
                    let x = bounds.minX + CGFloat(column) * (plan.tileWidth + spacing)
                    subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                                          proposal: ProposedViewSize(width: plan.tileWidth, height: height))
                }
                y += height + spacing
            }
        }

        private func plan(width: CGFloat?) -> TileGridPlan {
            TileGridPlan(offeredWidth: width, minimumWidth: minimumWidth, spacing: spacing, columns: columns)
        }

        private func rowHeights(_ subviews: Subviews, plan: TileGridPlan) -> [CGFloat] {
            stride(from: 0, to: subviews.count, by: plan.columns).map { start in
                subviews[start..<min(start + plan.columns, subviews.count)]
                    .map { $0.sizeThatFits(ProposedViewSize(width: plan.tileWidth, height: nil)).height }
                    .max() ?? 0
            }
        }
    }
}

// MARK: - Transition thumbnails

extension VideoKit {
    /// The picture on a transition tile (`.th-diss`, `.th-dip`, …): one clip's
    /// colour becoming the other's, the way that transition does it.
    struct TransitionThumbnail: View {
        enum Style: CaseIterable {
            case dissolve, dipToBlack, slide, push, morph, cut
            case dipToWhite, wipe, blurThrough
            // The ones that turn in depth: drawn from the same corners the
            // renderer turns the shots to (`DepthTransition.quads`).
            case flip, cube, swing, doorway, revolve, pushInDepth
        }

        let style: Style

        private static let from = rgb(0x12C2E9)
        private static let to = rgb(0xFF5D8F)

        var body: some View {
            switch style {
            case .dissolve:
                LinearGradient(stops: [.init(color: Self.from, location: 0),
                                       .init(color: rgb(0x5B53FF), location: 0.45),
                                       .init(color: Self.to, location: 1)],
                               startPoint: .leading, endPoint: .trailing)
            case .dipToBlack:
                LinearGradient(colors: [Self.from, .black, Self.to], startPoint: .leading, endPoint: .trailing)
            case .slide:
                LinearGradient(stops: [.init(color: Self.from, location: 0.46),
                                       .init(color: Self.to, location: 0.54)],
                               startPoint: .leading, endPoint: .trailing)
                    .overlay {
                        GeometryReader { geo in
                            LinearGradient(colors: [.clear, .white.opacity(0.55)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                                .frame(width: geo.size.width * 0.34)
                                .transformEffect(CGAffineTransform(a: 1, b: 0, c: -0.29, d: 1, tx: 0, ty: 0))
                                .offset(x: geo.size.width * 0.5)
                        }
                    }
            case .push:
                // Drawn rather than stacked, so the stripes never ask the
                // tile for more width than its column has.
                Canvas { context, size in
                    var x: CGFloat = 0
                    var index = 0
                    while x < size.width {
                        let stripe = CGRect(x: x, y: 0, width: 5, height: size.height)
                        context.fill(Path(stripe), with: .color(index.isMultiple(of: 2) ? rgb(0x7C4DFF) : Self.from))
                        x += 5
                        index += 1
                    }
                }
            case .morph:
                ZStack {
                    rgb(0x5B53FF)
                    RadialGradient(colors: [Self.from, .clear], center: UnitPoint(x: 0.3, y: 0.5),
                                   startRadius: 0, endRadius: 40)
                    RadialGradient(colors: [Self.to, .clear], center: UnitPoint(x: 0.7, y: 0.5),
                                   startRadius: 0, endRadius: 40)
                }
            case .cut:
                HStack(spacing: 0) { Self.from; Self.to }
                    .overlay { Rectangle().fill(rgb(0x05060A)).frame(width: 2) }
            case .dipToWhite, .wipe, .blurThrough, .flip, .cube, .swing, .doorway, .revolve, .pushInDepth:
                TransitionMovie(style: style, progress: 0.5)
            }
        }
    }

    /// One frame of a transition between the kit's two stand-in shots, or
    /// between two real pictures where it is handed them: the last frame of
    /// the clip going out and the first of the one coming in, each filling
    /// the tile the way the canvas fills the frame.
    struct TransitionMovie: View {
        let style: TransitionThumbnail.Style
        let progress: Double
        var outgoing: CGImage?
        var incoming: CGImage?

        var body: some View {
            Canvas { context, size in
                let p = min(max(progress, 0), 1)
                let whole = CGRect(origin: .zero, size: size)
                func shotA(_ rect: CGRect, in context: GraphicsContext) {
                    if let outgoing { return Self.fill(outgoing, rect, in: context) }
                    context.fill(Path(rect), with: .linearGradient(
                        Gradient(colors: [rgb(0x12C2E9), rgb(0x7C4DFF)]),
                        startPoint: rect.origin, endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
                }
                func shotB(_ rect: CGRect, opacity: Double = 1, in context: GraphicsContext) {
                    var layer = context
                    layer.opacity = opacity
                    if let incoming { return Self.fill(incoming, rect, in: layer) }
                    layer.fill(Path(rect), with: .linearGradient(
                        Gradient(colors: [rgb(0xFF9D5C), rgb(0xFF5D8F)]),
                        startPoint: rect.origin, endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
                }
                switch style {
                case .dissolve, .morph:
                    shotA(whole, in: context)
                    shotB(whole, opacity: p, in: context)
                case .blurThrough:
                    var soft = context
                    soft.addFilter(.blur(radius: 5 * (1 - abs(2 * p - 1))))
                    if outgoing == nil {
                        soft.fill(Path(whole), with: .color(rgb(0x12C2E9)))
                    } else {
                        shotA(whole, in: soft)
                    }
                    if incoming == nil {
                        var over = soft
                        over.opacity = p
                        over.fill(Path(whole), with: .color(rgb(0xFF9D5C)))
                    } else {
                        shotB(whole, opacity: p, in: soft)
                    }
                case .dipToBlack, .dipToWhite:
                    if p < 0.5 { shotA(whole, in: context) } else { shotB(whole, in: context) }
                    let amount = p < 0.5 ? p * 2 : 2 - p * 2
                    var dip = context
                    dip.opacity = amount
                    dip.fill(Path(whole), with: .color(style == .dipToWhite ? .white : rgb(0x05060A)))
                case .push, .slide:
                    shotA(whole.offsetBy(dx: -p * size.width, dy: 0), in: context)
                    shotB(whole.offsetBy(dx: (1 - p) * size.width, dy: 0), in: context)
                case .wipe:
                    shotA(whole, in: context)
                    var revealed = context
                    revealed.clip(to: Path(CGRect(x: 0, y: 0, width: p * size.width, height: size.height)))
                    shotB(whole, in: revealed)
                    if p > 0.02, p < 0.98 {
                        context.fill(Path(CGRect(x: p * size.width - 0.5, y: 0, width: 1, height: size.height)),
                                     with: .color(.white.opacity(0.8)))
                    }
                case .cut:
                    if p < 0.5 { shotA(whole, in: context) } else { shotB(whole, in: context) }
                case .flip, .cube, .swing, .doorway, .revolve, .pushInDepth:
                    context.fill(Path(whole), with: .color(rgb(0x05060A)))
                    #if canImport(PhotonzCore)
                    for (part, quad) in DepthTransition.quads(Self.depthKind(style), direction: .left,
                                                               progress: p, size: size) {
                        guard let quad, part.opacity > 0.001 else { continue }
                        var path = Path()
                        path.addLines(quad)
                        path.closeSubpath()
                        var face = context
                        face.opacity = part.opacity
                        let picture = part.shot == .outgoing ? outgoing : incoming
                        if let picture, let onto = Self.mapping(part.window, of: size, onto: quad) {
                            // The picture turned with the face: flat in its
                            // own box, carried onto the face's corners. At a
                            // tile's size the face's slant reads as depth.
                            var turned = face
                            turned.clip(to: path)
                            turned.concatenate(onto)
                            Self.fill(picture, whole, in: turned)
                        } else {
                            let box = path.boundingRect
                            let colours = part.shot == .outgoing ? [rgb(0x12C2E9), rgb(0x7C4DFF)]
                                                                 : [rgb(0xFF9D5C), rgb(0xFF5D8F)]
                            face.fill(path, with: .linearGradient(Gradient(colors: colours), startPoint: box.origin,
                                                                  endPoint: CGPoint(x: box.maxX, y: box.maxY)))
                        }
                        face.stroke(path, with: .color(.white.opacity(0.35)), lineWidth: 0.5)
                    }
                    #else
                    if p < 0.5 { shotA(whole, in: context) } else { shotB(whole, in: context) }
                    #endif
                }
            }
        }

        /// A picture filling `rect` the way the canvas fills the frame:
        /// scaled to cover it, centred, the overflow cut off.
        nonisolated static func fill(_ picture: CGImage, _ rect: CGRect, in context: GraphicsContext) {
            let width = CGFloat(picture.width), height = CGFloat(picture.height)
            guard width > 0, height > 0, rect.width > 0, rect.height > 0 else { return }
            let scale = max(rect.width / width, rect.height / height)
            let drawn = CGSize(width: width * scale, height: height * scale)
            var inside = context
            inside.clip(to: Path(rect))
            inside.draw(Image(decorative: picture, scale: 1),
                        in: CGRect(x: rect.midX - drawn.width / 2, y: rect.midY - drawn.height / 2,
                                   width: drawn.width, height: drawn.height))
        }

        /// What carries the part of the shot in `window` (a fraction of a
        /// tile of `size`) onto a face's four corners, top left first: the
        /// flat mapping of its top left, top right and bottom left.
        nonisolated static func mapping(_ window: CGRect, of size: CGSize, onto quad: [CGPoint]) -> CGAffineTransform? {
            guard quad.count == 4 else { return nil }
            let box = CGRect(x: window.minX * size.width, y: window.minY * size.height,
                             width: window.width * size.width, height: window.height * size.height)
            guard box.width > 0, box.height > 0 else { return nil }
            let q0 = quad[0], q1 = quad[1], q3 = quad[3]
            let a = (q1.x - q0.x) / box.width, b = (q1.y - q0.y) / box.width
            let c = (q3.x - q0.x) / box.height, d = (q3.y - q0.y) / box.height
            return CGAffineTransform(a: a, b: b, c: c, d: d,
                                     tx: q0.x - a * box.minX - c * box.minY,
                                     ty: q0.y - b * box.minX - d * box.minY)
        }

        #if canImport(PhotonzCore)
        static func depthKind(_ style: TransitionThumbnail.Style) -> ClipTransitionKind {
            switch style {
            case .cube: .cube
            case .swing: .swing
            case .doorway: .doorway
            case .revolve: .revolve
            case .pushInDepth: .pushInDepth
            default: .flip
            }
        }
        #endif
    }
}
