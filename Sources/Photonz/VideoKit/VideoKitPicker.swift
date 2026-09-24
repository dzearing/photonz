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
                    Text(name)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
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
            .opacity(isDisabled ? 0.42 : 1)
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
            let width = proposal.width ?? minimumWidth * 2 + spacing
            let plan = plan(width: width, count: subviews.count)
            let heights = rowHeights(subviews, plan: plan)
            let total = heights.reduce(0, +) + spacing * CGFloat(max(0, heights.count - 1))
            return CGSize(width: width, height: total)
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            let plan = plan(width: bounds.width, count: subviews.count)
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

        private struct Plan { let columns: Int; let tileWidth: CGFloat }

        private func plan(width: CGFloat, count: Int) -> Plan {
            let fit = Int(((width + spacing) / (minimumWidth + spacing)).rounded(.down))
            let columns = max(1, columns ?? fit)
            let tileWidth = max(0, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
            return Plan(columns: columns, tileWidth: tileWidth)
        }

        private func rowHeights(_ subviews: Subviews, plan: Plan) -> [CGFloat] {
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
            case .dipToWhite, .wipe, .blurThrough:
                TransitionMovie(style: style, progress: 0.5)
            }
        }
    }

    /// A transition tile that PLAYS (`video-transition-wt.html`, the picker at
    /// a cut): one shot becoming the other the way that transition does it,
    /// over and over, so the tile shows the behaviour rather than naming it.
    /// Holds still on its middle frame for anyone who has asked the system to
    /// reduce motion.
    struct AnimatedTransitionThumbnail: View {
        let style: TransitionThumbnail.Style
        /// One loop: a beat on the first shot, the transition, a beat on the
        /// second.
        var cycle: Double = 2.2

        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            if reduceMotion {
                TransitionMovie(style: style, progress: 0.5)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    TransitionMovie(style: style, progress: progress(at: context.date))
                }
            }
        }

        private func progress(at date: Date) -> Double {
            let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle) / cycle
            // There and back: a beat on the first shot, across, a beat on the
            // second, and back again, eased so it reads as a move. Most of the
            // loop is spent part way through, where the kinds differ.
            let there = t < 0.5 ? t * 2 : 2 - t * 2
            let raw = min(max((there - 0.1) / 0.8, 0), 1)
            return raw * raw * (3 - 2 * raw)
        }
    }

    /// One frame of a transition between the kit's two stand-in shots.
    struct TransitionMovie: View {
        let style: TransitionThumbnail.Style
        let progress: Double

        var body: some View {
            Canvas { context, size in
                let p = min(max(progress, 0), 1)
                let whole = CGRect(origin: .zero, size: size)
                func shotA(_ rect: CGRect) {
                    context.fill(Path(rect), with: .linearGradient(
                        Gradient(colors: [rgb(0x12C2E9), rgb(0x7C4DFF)]),
                        startPoint: rect.origin, endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
                }
                func shotB(_ rect: CGRect, opacity: Double = 1) {
                    var layer = context
                    layer.opacity = opacity
                    layer.fill(Path(rect), with: .linearGradient(
                        Gradient(colors: [rgb(0xFF9D5C), rgb(0xFF5D8F)]),
                        startPoint: rect.origin, endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
                }
                switch style {
                case .dissolve, .morph:
                    shotA(whole)
                    shotB(whole, opacity: p)
                case .blurThrough:
                    var soft = context
                    soft.addFilter(.blur(radius: 5 * (1 - abs(2 * p - 1))))
                    soft.fill(Path(whole), with: .color(rgb(0x12C2E9)))
                    var over = soft
                    over.opacity = p
                    over.fill(Path(whole), with: .color(rgb(0xFF9D5C)))
                case .dipToBlack, .dipToWhite:
                    if p < 0.5 { shotA(whole) } else { shotB(whole) }
                    let amount = p < 0.5 ? p * 2 : 2 - p * 2
                    var dip = context
                    dip.opacity = amount
                    dip.fill(Path(whole), with: .color(style == .dipToWhite ? .white : rgb(0x05060A)))
                case .push, .slide:
                    shotA(whole.offsetBy(dx: -p * size.width, dy: 0))
                    shotB(whole.offsetBy(dx: (1 - p) * size.width, dy: 0))
                case .wipe:
                    shotA(whole)
                    shotB(CGRect(x: 0, y: 0, width: p * size.width, height: size.height))
                    if p > 0.02, p < 0.98 {
                        context.fill(Path(CGRect(x: p * size.width - 0.5, y: 0, width: 1, height: size.height)),
                                     with: .color(.white.opacity(0.8)))
                    }
                case .cut:
                    if p < 0.5 { shotA(whole) } else { shotB(whole) }
                }
            }
        }
    }
}
