import AppKit
import QuartzCore
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
    struct TransportBar<Volume: View, Controls: View, Scrub: View, Trailing: View>: View {
        /// The time now. With `liveCurrent`, only what the time is as wide as
        /// (`Timecode.shape(of:)`): the time itself is read on every frame, in
        /// an island of its own, so the bar is not drawn again thirty times a
        /// second (`Island`).
        let current: String
        let duration: String
        var liveCurrent: (() -> String)? = nil
        @ViewBuilder let volume: Volume
        @ViewBuilder let controls: Controls
        @ViewBuilder let scrubber: Scrub
        /// After the length: what a player adds at its far end (full screen).
        @ViewBuilder var trailing: Trailing

        var body: some View {
            HStack(spacing: 12) {
                HStack(spacing: 4) { volume }
                HStack(spacing: 4) { controls }
                if let liveCurrent {
                    Timecode(text: current)
                        .hidden()
                        .overlay(alignment: .trailing) {
                            LayerIsland(liveCurrent) { now, canvas in Timecode.paint(now, on: canvas) }
                        }
                } else {
                    Timecode(text: current)
                }
                scrubber
                    .frame(minWidth: 180, maxWidth: .infinity)
                Timecode(text: duration)
                trailing
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

        /// The time drawn with layers, as `body` draws it, for a time that
        /// changes on every frame (`TransportBar.liveCurrent`): set to the
        /// right of the island and centred down it.
        @MainActor static func paint(_ text: String, on canvas: IslandCanvas) {
            let font = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular)
            let line = canvas.layer("time") { CATextLayer() }
            line.font = font
            line.fontSize = font.pointSize
            line.alignmentMode = .right
            line.truncationMode = .none
            line.foregroundColor = canvas.color(Palette.faint)
            line.string = text
            let height = ceil(font.ascender - font.descender + font.leading)
            line.frame = CGRect(x: 0, y: ((canvas.bounds.height - height) / 2).rounded(),
                                width: canvas.bounds.width, height: height)
        }

        /// Text as wide as any time up to `longest` in this face, whose
        /// digits all take the same room: what a live time is laid out as, so
        /// the bar is laid out again only when the length changes.
        static func shape(of longest: String) -> String {
            String(longest.map { $0.isNumber ? "0" : $0 })
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
                    .measuredInk()
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
        /// Where the playhead is, 0 to 1. Unused with `liveFraction`.
        let fraction: Double
        /// In and out points, or anything else worth a mark, 0 to 1.
        var marks: [Double] = []
        /// Where the playhead is, read where the bar is drawn: the bar's face
        /// is drawn in an island of its own and read on every frame there,
        /// so the window is not (`Island`). The press, the drag, the hover and
        /// a menu stay on the bar itself.
        var liveFraction: (() -> Double)? = nil
        let onScrub: (Double, ScrubPhase) -> Void

        @State private var isHovering = false
        @State private var isDragging = false

        private static let hitHeight: CGFloat = 24

        var body: some View {
            GeometryReader { geo in
                let width = geo.size.width
                let lifted = isHovering || isDragging
                Group {
                    if let liveFraction {
                        LayerIsland({ ScrubberFace.Spot(liveFraction(), width: width) }) { spot, canvas in
                            ScrubberFace.paint(spot, marks: marks, lifted: lifted, on: canvas)
                        }
                    } else {
                        ScrubberFace(spot: ScrubberFace.Spot(fraction, width: width), marks: marks,
                                     lifted: lifted, width: width)
                    }
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
            // Live, the bar says where it is from inside its island.
            .modifier(ScrubberValue(percent: liveFraction == nil ? ScrubberFace.Spot(fraction, width: 1).said : nil))
        }

        private func clamped(_ value: Double) -> Double { min(max(0, value), 1) }
    }

    private struct ScrubberValue: ViewModifier {
        let percent: String?

        func body(content: Content) -> some View {
            if let percent { content.accessibilityValue(percent) } else { content }
        }
    }

    /// What the scrub bar draws: the line, the played part, the marks and
    /// the knob. Everything that moves with the playhead is in here.
    private struct ScrubberFace: View {
        /// Where the knob is, to the half point, and what the bar says it
        /// is at: all that can be seen of the playhead.
        struct Spot: Equatable {
            var halfPoints: Int
            var percent: Int

            init(_ fraction: Double, width: CGFloat) {
                let now = ScrubberFace.clamped(fraction)
                halfPoints = Int((Double(width) * now * 2).rounded())
                percent = Int((now * 100).rounded())
            }

            var x: CGFloat { CGFloat(halfPoints) / 2 }
            var said: String { "\(percent) percent" }
        }

        let spot: Spot
        let marks: [Double]
        let lifted: Bool
        let width: CGFloat

        private static let thumbWidth: CGFloat = 26
        private static let thumbHeight: CGFloat = 18

        var body: some View {
            let x = spot.x
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
                        .offset(x: width * Self.clamped(mark) - 1)
                }
                thumb
                    .scaleEffect(lifted ? 1.12 : 1)
                    .offset(x: x - Self.thumbWidth / 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .accessibilityElement()
            .accessibilityLabel("Scrub")
            .accessibilityValue(spot.said)
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

        nonisolated static func clamped(_ value: Double) -> Double { min(max(0, value), 1) }

        /// The bar drawn with layers, as `body` draws it, for a playhead that
        /// moves on every frame (`Scrubber.liveFraction`). Lifting and
        /// settling ease over the same 0.12s; following the playhead is
        /// immediate.
        @MainActor static func paint(_ spot: Spot, marks: [Double], lifted: Bool, on canvas: IslandCanvas) {
            let width = canvas.bounds.width
            let middle = canvas.bounds.midY
            let thick: CGFloat = lifted ? 8 : 6
            let x = spot.x
            let track = canvas.layer("track") { CALayer() }
            let played = canvas.layer("played") { CALayer() }
            let markLayers = (0..<max(2, marks.count)).map { index in canvas.layer("mark\(index)") { CALayer() } }
            let thumb = canvas.layer("thumb") { Self.makeThumb() }
            let face = thumb.sublayers?.first as? CAGradientLayer

            let wasLifted = thumb.value(forKey: "lifted") as? Bool
            CATransaction.begin()
            if let wasLifted, wasLifted != lifted {
                CATransaction.setDisableActions(false)
                CATransaction.setAnimationDuration(0.12)
                CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
            }
            thumb.setValue(lifted, forKey: "lifted")
            track.backgroundColor = canvas.color(Palette.lineStrong)
            track.frame = CGRect(x: 0, y: middle - thick / 2, width: width, height: thick)
            track.cornerRadius = thick / 2
            played.backgroundColor = canvas.color(Palette.accent)
            played.frame = CGRect(x: 0, y: middle - thick / 2, width: max(0, x), height: thick)
            played.cornerRadius = thick / 2
            for (index, layer) in markLayers.enumerated() {
                layer.isHidden = index >= marks.count
                guard index < marks.count else { continue }
                layer.backgroundColor = canvas.color(Palette.good)
                layer.cornerRadius = 1
                layer.frame = CGRect(x: width * clamped(marks[index]) - 1, y: middle - (thick + 8) / 2,
                                     width: 2, height: thick + 8)
            }
            thumb.transform = lifted ? CATransform3DMakeScale(1.12, 1.12, 1) : CATransform3DIdentity
            CATransaction.commit()
            // The knob follows the playhead at once, lifted or not.
            thumb.position = CGPoint(x: x, y: middle)
            face?.borderColor = canvas.color(Palette.edgeLo)
        }

        /// `--sl-knob`: white, a touch of line colour at the foot, a lit top
        /// edge and a soft shadow.
        private static func makeThumb() -> CALayer {
            let thumb = CALayer()
            thumb.bounds = CGRect(x: 0, y: 0, width: thumbWidth, height: thumbHeight)
            thumb.shadowColor = CGColor(gray: 0, alpha: 1)
            thumb.shadowOpacity = 0.28
            thumb.shadowRadius = 2
            thumb.shadowOffset = CGSize(width: 0, height: -1)
            thumb.shadowPath = CGPath(roundedRect: thumb.bounds, cornerWidth: thumbHeight / 2,
                                      cornerHeight: thumbHeight / 2, transform: nil)
            let face = CAGradientLayer()
            face.frame = thumb.bounds
            face.colors = [CGColor(gray: 1, alpha: 1), CGColor(gray: 0.9, alpha: 1)]
            // White at the top, as Core Animation measures from the bottom.
            face.startPoint = CGPoint(x: 0.5, y: 1)
            face.endPoint = CGPoint(x: 0.5, y: 0)
            face.cornerRadius = thumbHeight / 2
            face.borderWidth = 1
            thumb.addSublayer(face)
            return thumb
        }
    }
}

extension VideoKit.TransportBar where Trailing == EmptyView {
    /// The editor's transport, which ends at the length.
    init(current: String, duration: String,
         @ViewBuilder volume: () -> Volume,
         @ViewBuilder controls: () -> Controls,
         @ViewBuilder scrubber: () -> Scrub) {
        self.init(current: current, duration: duration, volume: volume, controls: controls,
                  scrubber: scrubber, trailing: { EmptyView() })
    }
}
