import SwiftUI

// MARK: - A track: its header and its lane

extension VideoKit {
    /// One row of the timeline (`inspector.css` `.track`): the header on the
    /// left, the lane taking the rest.
    struct TrackRow<Header: View, Lane: View>: View {
        var laneHeight: CGFloat = Metrics.laneHeight
        @ViewBuilder let header: Header
        @ViewBuilder let lane: Lane

        var body: some View {
            HStack(spacing: Metrics.trackGap) {
                header
                lane
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: laneHeight)
            }
        }
    }

    /// The name of a track, with its kind's icon (`.track .tl`).
    ///
    /// The shared look is 58pt and upper case (V1, V2, AUDIO, TITLE).
    /// `video.html`'s own timeline widens it to 84pt and keeps the case, so
    /// both are parameters rather than the kit choosing one.
    struct TrackHeader: View {
        let title: String
        var symbol: String?
        var width: CGFloat = Metrics.trackHeaderWidth
        var uppercase = true
        /// A track the app made rather than the person (captions): its name
        /// is drawn in the component colour with a sparkle.
        var isAutomatic = false

        var body: some View {
            HStack(spacing: isAutomatic ? 3 : 5) {
                if isAutomatic {
                    Image(systemName: "sparkles").font(.system(size: 9, weight: .semibold))
                } else if let symbol {
                    Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
                }
                Text(isUpper ? title.uppercased() : title)
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(isUpper ? 0.4 : 0.2)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .foregroundStyle(isAutomatic ? AnyShapeStyle(Palette.comp) : AnyShapeStyle(Palette.faint))
            .frame(width: width, alignment: .leading)
            .clipped()
        }

        /// An automatic track keeps its own case (`.trk-auto`), the way the
        /// mock writes "Caption".
        private var isUpper: Bool { uppercase && !isAutomatic }
    }
}

// MARK: - The ruler

extension VideoKit {
    /// A tick on the ruler: where it is along the lane, 0 to 1, and what it
    /// says.
    struct RulerTick: Hashable {
        let fraction: Double
        let label: String
    }

    /// The ruler (`.ruler`): a mark and a number at each tick, a hairline
    /// under the lot. It measures the LANES, so it goes in a lane's column,
    /// never across the header.
    ///
    /// A tick at the very end sets its number inside the edge rather than
    /// spilling past it, the way the mock's `.tk.end` does.
    struct TimeRuler: View {
        let ticks: [RulerTick]
        var height: CGFloat = Metrics.rulerHeight

        var body: some View {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    ForEach(ticks, id: \.self) { tick in
                        let isEnd = tick.fraction >= 0.999
                        let x = geo.size.width * min(max(0, tick.fraction), 1)
                        Text(tick.label)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Palette.faint)
                            .fixedSize()
                            .padding(isEnd ? .trailing : .leading, 3)
                            .frame(height: height - 1, alignment: .topLeading)
                            .overlay(alignment: .leading) {
                                if !isEnd { Rectangle().fill(Palette.line).frame(width: 1) }
                            }
                            .alignmentGuide(.leading) { d in isEnd ? d.width - x : -x }
                    }
                }
                .frame(width: geo.size.width, height: height, alignment: .topLeading)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Palette.line).frame(height: 1)
                }
            }
            .frame(height: height)
            .clipped()
        }
    }
}

// MARK: - The playhead

extension VideoKit {
    /// The playhead (`.playhead`): a 2pt red line with a triangle on top,
    /// standing at `fraction` of whatever it is laid over. Lay it over the
    /// lanes' column and it spans every track.
    ///
    /// Drawing only. Where a press on the ruler moves it is the caller's
    /// business, because only the caller knows what a fraction is in time.
    struct Playhead: View {
        let fraction: Double

        var body: some View {
            GeometryReader { geo in
                let x = geo.size.width * min(max(0, fraction), 1)
                ZStack(alignment: .top) {
                    Rectangle()
                        .fill(Palette.crit)
                        .frame(width: Metrics.playheadWidth)
                    PlayheadHead()
                        .fill(Palette.crit)
                        .frame(width: 12, height: 6)
                        .offset(y: -2)
                }
                .frame(width: 12, height: geo.size.height)
                .offset(x: x - 6)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// The triangle on top of the playhead, point down.
    struct PlayheadHead: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.minX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
                path.closeSubpath()
            }
        }
    }
}

// MARK: - A clip

extension VideoKit {
    /// What a clip is, which decides its colour (`.clip.v1`, `.v2`, `.comp`,
    /// `.ov`, `.txt`, `.aud`). Colour says which track a clip came from and
    /// nothing else; retiming, keys and trimming are drawn on top.
    enum ClipKind: CaseIterable {
        case video, videoAlternate, component, overlay, text, audio

        var fill: AnyShapeStyle {
            switch self {
            case .video: AnyShapeStyle(Self.diagonal(0x12C2E9, 0x7C4DFF))
            case .videoAlternate: AnyShapeStyle(Self.diagonal(0x7C4DFF, 0xFF5D8F))
            case .component: AnyShapeStyle(Self.diagonal(0x9A5CFF, 0xC56CFF))
            case .overlay: AnyShapeStyle(Self.diagonal(0x1B7A8C, 0x12C2E9))
            case .text: AnyShapeStyle(rgb(0x2A2F45))
            case .audio: AnyShapeStyle(LinearGradient(colors: [rgb(0x26463A), rgb(0x1C3A30)],
                                                      startPoint: .top, endPoint: .bottom))
            }
        }

        /// The one kind that draws a border, because its fill is close to the
        /// panel it sits on.
        var border: Color? { self == .text ? rgb(0x3D456A) : nil }

        var ink: Color { self == .audio ? rgb(0x88FFEE) : .white }

        /// A 135 degree gradient, top left to bottom right.
        private static func diagonal(_ from: UInt32, _ to: UInt32) -> LinearGradient {
            LinearGradient(colors: [rgb(from), rgb(to)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    /// A clip on a lane (`.clip` and its parts in `video.css`): a rounded bar
    /// in its kind's colour with its name inside, a speed badge when retimed,
    /// a white diamond wherever a key falls, and a grip at each end that shows
    /// on hover or while the clip is being trimmed.
    ///
    /// The caller sizes and places it (its width IS its duration); the clip
    /// only draws what is inside it. Keys are read-only here on purpose: the
    /// timeline says when something changes, the detail pane says to what.
    struct ClipBar: View {
        let title: String
        let kind: ClipKind
        var isSelected = false
        /// The Trim tool has this clip in hand: both grips up, a ring round it.
        var isTrimming = false
        /// "2x", "0.5x", or nothing at normal speed.
        var speed: String?
        /// Where keys fall inside the clip, 0 to 1 of its own length.
        var keys: [Double] = []
        /// Loudness along an audio clip, 0 to 1 per bar. Drawn instead of the
        /// name when present, because a waveform describes the whole clip.
        var levels: [Double]?
        var height: CGFloat = Metrics.laneHeight

        @State private var isHovering = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: Metrics.clipCornerRadius)
            shape
                .fill(kind.fill)
                .overlay { if let border = kind.border { shape.strokeBorder(border) } }
                // The lit top edge every clip has (inset 0 1px 0 white .18).
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.white.opacity(0.18)).frame(height: 1)
                        .padding(.horizontal, Metrics.clipCornerRadius / 2)
                }
                .overlay(alignment: .leading) { content }
                .overlay { keyMarks }
                .overlay(alignment: .topTrailing) { speedBadge }
                .overlay(alignment: .leading) { grip }
                .overlay(alignment: .trailing) { grip }
                .clipShape(shape)
                .overlay {
                    if isSelected || isTrimming {
                        // `outline: 2px; outline-offset: 1px` sits outside the bar.
                        RoundedRectangle(cornerRadius: Metrics.clipCornerRadius + 2)
                            .strokeBorder(Palette.accent, lineWidth: 2)
                            .padding(-3)
                    }
                }
                .shadow(color: isTrimming ? .black.opacity(0.5) : .clear, radius: 8, y: 6)
                .frame(height: height)
                .contentShape(shape)
                .kitHover(title) { isHovering = $0 }
                .animation(.easeOut(duration: 0.12), value: isHovering)
                .accessibilityElement()
                .accessibilityLabel(title)
        }

        @ViewBuilder private var content: some View {
            if let levels {
                Waveform(levels: levels, color: kind.ink)
            } else {
                Text(title)
                    .font(.system(size: height < Metrics.laneHeight ? 9.5 : 10, weight: .semibold))
                    .foregroundStyle(kind.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 8)
            }
        }

        private var keyMarks: some View {
            GeometryReader { geo in
                ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                    KeyMark()
                        .position(x: geo.size.width * min(max(0, key), 1), y: geo.size.height / 2)
                }
            }
            .allowsHitTesting(false)
        }

        @ViewBuilder private var speedBadge: some View {
            if let speed {
                Text(speed)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.5)))
                    .padding(.top, 3)
                    .padding(.trailing, 4)
            }
        }

        /// Invisible at rest, because every clip sits beside another and two
        /// grips each would turn the timeline into a picket fence.
        private var grip: some View {
            let shown = isTrimming || isHovering
            return RoundedRectangle(cornerRadius: 2)
                .fill(isTrimming ? Color.white : Color.white.opacity(0.55))
                .frame(width: isTrimming ? 3 : 2)
                .padding(.vertical, isTrimming ? 4 : 9)
                .frame(width: 7)
                .opacity(shown ? 1 : 0)
        }
    }

    /// A key on a clip (`.kfm`): a 7pt white diamond with a dark hairline so
    /// it reads on any clip colour.
    struct KeyMark: View {
        var body: some View {
            Rectangle()
                .fill(Color.white)
                .overlay(Rectangle().strokeBorder(Color.black.opacity(0.25), lineWidth: 1))
                .frame(width: 7, height: 7)
                .rotationEffect(.degrees(45))
        }
    }

    /// A waveform that spans its whole clip (`.clip .wave`): thin bars, evenly
    /// spread, one per level.
    struct Waveform: View {
        let levels: [Double]
        var color: Color = rgb(0x88FFEE)

        var body: some View {
            HStack(alignment: .center, spacing: 0) {
                ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                    if index > 0 { Spacer(minLength: 0) }
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color.opacity(0.7))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                        .scaleEffect(y: min(max(0.04, level), 1))
                }
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - A transition, sitting on a cut

extension VideoKit {
    /// A transition on the timeline (`video.css` `.xband`). It sits ON the two
    /// clips either side of a cut, centred on it, because a transition
    /// overlaps them rather than taking a slot between them.
    ///
    /// A dip is an outline rather than a fill, so the black it dips through
    /// can still be seen under it.
    struct TransitionBand: View {
        var isDip = false
        var isSelected = false
        var height: CGFloat = Metrics.laneHeight

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 6)
            ZStack {
                if isDip {
                    shape.strokeBorder(Color.white.opacity(0.6),
                                       style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                } else {
                    shape
                        .fill(LinearGradient(colors: [rgb(0x12C2E9, 0.75), rgb(0xFF9D5C, 0.75)],
                                             startPoint: .leading, endPoint: .trailing))
                        .overlay(shape.strokeBorder(Color.white.opacity(0.55)))
                        .shadow(color: .black.opacity(0.4), radius: 5, y: 4)
                }
                TransitionGlyph()
                    .fill(isDip ? Color.white : rgb(0x0B0D18))
                    .frame(width: 10, height: 10)
                    .shadow(color: isDip ? .black.opacity(0.9) : .clear, radius: 1, y: 1)
            }
            .overlay {
                if isSelected {
                    shape.stroke(Palette.accent, lineWidth: 2).padding(-1)
                }
            }
            .overlay(alignment: .leading) { grip.offset(x: -2) }
            .overlay(alignment: .trailing) { grip.offset(x: 2) }
            .frame(height: height)
        }

        private var grip: some View {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(0.9))
                .frame(width: 5, height: 16)
        }
    }

    /// The transition icon (`icons.mjs` `transition`): two wedges meeting in
    /// the middle, one clip closing as the other opens. SF Symbols has no
    /// drawing that says this, so it is drawn from the mock's own path.
    struct TransitionGlyph: Shape {
        func path(in rect: CGRect) -> Path {
            let unit = min(rect.width, rect.height) / 24
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: rect.minX + x * unit, y: rect.minY + y * unit)
            }
            return Path { path in
                path.addLines([p(4.4, 4.4), p(11, 12), p(4.4, 19.6)])
                path.closeSubpath()
                path.addLines([p(19.6, 4.4), p(13, 12), p(19.6, 19.6)])
                path.closeSubpath()
            }
        }
    }
}
