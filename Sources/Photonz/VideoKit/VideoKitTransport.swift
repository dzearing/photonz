import SwiftUI

// MARK: - The transport row

extension VideoKit {
    /// The transport (`overlays.css` `.transport`): volume, the three play
    /// buttons, the current time, the scrubber, the length.
    ///
    /// Time controls only. The scrubber is the one child that grows and every
    /// sibling holds its size, so a narrow window squeezes nothing but the
    /// scrubber, and the scrubber never goes below the width you can aim in.
    ///
    /// The buttons and the scrubber come in as views so the caller can hang its
    /// own names and help on each one; `TransportButton` and `Scrubber` are the
    /// pieces to put there.
    struct TransportBar<Volume: View, Controls: View, Scrub: View>: View {
        let current: String
        let duration: String
        @ViewBuilder let volume: Volume
        @ViewBuilder let controls: Controls
        @ViewBuilder let scrubber: Scrub

        var body: some View {
            HStack(spacing: 12) {
                HStack(spacing: 4) { volume }
                HStack(spacing: 4) { controls }
                Timecode(text: current)
                scrubber
                    .frame(minWidth: 180, maxWidth: .infinity)
                Timecode(text: duration)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(Palette.glassChrome)
            .overlay(alignment: .top) {
                // The hairline and the lit edge under it, as one border.
                VStack(spacing: 0) {
                    Rectangle().fill(Palette.edgeLo).frame(height: 1)
                    Rectangle().fill(Palette.edgeHi).frame(height: 1)
                }
            }
        }
    }

    /// A time readout on the transport: monospaced, tabular, never wrapped.
    struct Timecode: View {
        let text: String

        var body: some View {
            Text(text)
                .font(.system(size: 10.5, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(Palette.faint)
                .lineLimit(1)
                .fixedSize()
        }
    }

    /// One round transport button. `ghost` is the small quiet kind (skip,
    /// volume); `primary` is the big accent one, which is play.
    struct TransportButton: View {
        enum Role { case ghost, primary }

        let symbol: String
        let label: String
        var role: Role = .ghost
        let action: () -> Void

        @State private var isHovering = false

        var body: some View {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: role == .primary ? 13 : 11, weight: .semibold))
                    .foregroundStyle(role == .primary ? AnyShapeStyle(Color.white)
                                     : isHovering ? AnyShapeStyle(Palette.ink)
                                     : AnyShapeStyle(Palette.dim))
                    .frame(width: diameter, height: diameter)
                    .background { face }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .kitHover(label) { isHovering = $0 }
            .accessibilityLabel(label)
        }

        private var diameter: CGFloat {
            role == .primary ? Metrics.control : Metrics.controlSmall
        }

        @ViewBuilder private var face: some View {
            switch role {
            case .primary:
                // `.btn.primary`: a lit top edge on the accent, and its glow.
                Circle()
                    .fill(LinearGradient(colors: [Palette.accent.mix(with: .white, by: isHovering ? 0.24 : 0.16),
                                                  Palette.accent],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(Circle().inset(by: 0.5).trim(from: 0.55, to: 0.95)
                        .stroke(Color.white.opacity(0.45), lineWidth: 1))
                    .shadow(color: Palette.accent.opacity(0.6), radius: 8, y: 6)
            case .ghost:
                Circle()
                    .fill(isHovering ? AnyShapeStyle(Palette.glassThin) : AnyShapeStyle(Color.clear))
                    .overlay(Circle().strokeBorder(isHovering ? AnyShapeStyle(Palette.edgeLo)
                                                              : AnyShapeStyle(Color.clear)))
            }
        }
    }
}

// MARK: - The scrubber

extension VideoKit {
    /// Where a scrub is in its life, so a caller can start listening on the
    /// press and stop on the release.
    enum ScrubPhase { case began, changed, ended }

    /// The scrubber (`overlays.css` `.scrub`): a 6pt capsule with the played
    /// part in accent, a large capsule thumb, and marks for in and out.
    ///
    /// What is DRAWN is 6pt; what can be GRABBED is 24pt, because a control
    /// that asks for precision should not also ask you to hit a 6pt line.
    struct Scrubber: View {
        /// Where the playhead is, 0 to 1.
        let fraction: Double
        /// In and out points, or anything else worth a mark, 0 to 1.
        var marks: [Double] = []
        let onScrub: (Double, ScrubPhase) -> Void

        @State private var isHovering = false
        @State private var isDragging = false

        private static let hitHeight: CGFloat = 24
        private static let thumbWidth: CGFloat = 26
        private static let thumbHeight: CGFloat = 18

        var body: some View {
            GeometryReader { geo in
                let width = geo.size.width
                let x = width * clamped(fraction)
                let lifted = isHovering || isDragging
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Palette.lineStrong)
                        .frame(height: lifted ? 8 : 6)
                    Capsule()
                        .fill(Palette.accent)
                        .frame(width: max(0, x), height: lifted ? 8 : 6)
                    ForEach(Array(marks.enumerated()), id: \.offset) { _, mark in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Palette.good)
                            .frame(width: 2, height: (lifted ? 8 : 6) + 8)
                            .offset(x: width * clamped(mark) - 1)
                    }
                    thumb
                        .scaleEffect(lifted ? 1.12 : 1)
                        .offset(x: x - Self.thumbWidth / 2)
                }
                .frame(height: Self.hitHeight)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let phase: ScrubPhase = isDragging ? .changed : .began
                        isDragging = true
                        onScrub(clamped(value.location.x / max(1, width)), phase)
                    }
                    .onEnded { value in
                        isDragging = false
                        onScrub(clamped(value.location.x / max(1, width)), .ended)
                    })
            }
            .frame(height: Self.hitHeight)
            .kitHover("Scrub") { isHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovering || isDragging)
            .accessibilityElement()
            .accessibilityLabel("Scrub")
            .accessibilityValue("\(Int((clamped(fraction) * 100).rounded())) percent")
        }

        /// `--sl-knob`: white, a touch of line colour at the foot, a lit top
        /// edge and a soft shadow.
        private var thumb: some View {
            Capsule()
                .fill(LinearGradient(colors: [.white, Color(white: 0.9)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(Capsule().strokeBorder(Palette.edgeLo))
                .shadow(color: .black.opacity(0.28), radius: 2, y: 1)
                .frame(width: Self.thumbWidth, height: Self.thumbHeight)
        }

        private func clamped(_ value: Double) -> Double { min(max(0, value), 1) }
    }
}
