import PhotonzCore
import SwiftUI

/// The gradient half of the one color picker: what KIND of paint this is, and
/// where it is aimed.
///
/// Both are pictures rather than words. The type row shows four thumbnails of
/// YOUR color, so the choice is made by looking at four outcomes instead of
/// reading four nouns and imagining them; the aim pad is a square you point at,
/// because a direction is a thing you point at and 135 degrees is a thing you
/// have to decode. The number is a readout on the pad, never the control.
///
/// Drawn from `docs/design/mocks/pages/color.html`.

// MARK: - A paint, as something SwiftUI can fill with

extension Paint {

    /// The ramp as SwiftUI stops. A paint with no ramp reads as its flat color
    /// at both ends, so a preview of one is a solid block rather than nothing.
    var swiftUIStops: [Gradient.Stop] {
        guard isGradient else {
            let color = Color(hex: hex)
            return [Gradient.Stop(color: color, location: 0),
                    Gradient.Stop(color: color, location: 1)]
        }
        return orderedStops.map {
            Gradient.Stop(color: Color(hex: $0.hex), location: $0.position)
        }
    }

    /// Where a straight run enters and leaves the box it is drawn in. Zero
    /// degrees points at the top, and they increase clockwise, which is how
    /// every gradient anyone has ever written one down says it.
    var swiftUIEnds: (start: UnitPoint, end: UnitPoint) {
        let radians = angle * .pi / 180
        let dx = sin(radians) / 2, dy = -cos(radians) / 2
        return (UnitPoint(x: 0.5 - dx, y: 0.5 - dy), UnitPoint(x: 0.5 + dx, y: 0.5 + dy))
    }

    var swiftUICenter: UnitPoint { UnitPoint(x: center.x, y: center.y) }

    /// This paint drawn as if it were `kind`, which is what a type thumbnail
    /// has to show: the outcome of a choice not yet made.
    func preview(as kind: Kind) -> Paint {
        var copy = self
        copy.kind = kind
        if kind != .solid, copy.stops.count < 2 { copy.stops = Paint.seededStops(from: hex) }
        return copy
    }
}

/// A rectangle painted with a `Paint`, whichever kind it is. Everywhere a
/// gradient is previewed — a type tile, the aim pad, a row's swatch — goes
/// through this one view, so a gradient is drawn the same way wherever it is
/// shown.
struct PaintFill: View {
    let paint: Paint

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            switch paint.kind {
            case .solid:
                Color(hex: paint.hex)
            case .linear:
                LinearGradient(stops: paint.swiftUIStops,
                               startPoint: paint.swiftUIEnds.start,
                               endPoint: paint.swiftUIEnds.end)
            case .radial:
                RadialGradient(stops: paint.swiftUIStops,
                               center: paint.swiftUICenter,
                               startRadius: 0,
                               endRadius: reach(in: size))
            case .angular:
                // SwiftUI starts a sweep at 3 o'clock; a gradient's own zero is
                // 12 o'clock, so the quarter turn between them is taken here
                // rather than being stored in the document.
                AngularGradient(stops: paint.swiftUIStops,
                                center: paint.swiftUICenter,
                                angle: .degrees(paint.angle - 90))
            }
        }
    }

    /// To the furthest corner, so the far end of the ramp stays visible however
    /// off-centre the paint is aimed.
    private func reach(in size: CGSize) -> CGFloat {
        let cx = size.width * paint.center.x, cy = size.height * paint.center.y
        return [CGPoint(x: 0, y: 0), CGPoint(x: size.width, y: 0),
                CGPoint(x: 0, y: size.height), CGPoint(x: size.width, y: size.height)]
            .map { hypot($0.x - cx, $0.y - cy) }.max() ?? 0
    }
}

// MARK: - What kind of paint this is

/// The four outcomes, side by side, each drawn with the colors you are already
/// using. Only slots that can actually hold a ramp ever see this row.
struct PaintTypeRow: View {
    let paint: Paint
    let onPick: (Paint.Kind) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Paint.Kind.allCases, id: \.self) { kind in
                Button { onPick(kind) } label: { tile(kind) }
                    .buttonStyle(.plain)
                    .help("\(kind.title) paint")
                    .accessibilityLabel(kind.title)
                    .accessibilityAddTraits(kind == paint.kind ? [.isSelected] : [])
            }
        }
    }

    private func tile(_ kind: Paint.Kind) -> some View {
        let isOn = kind == paint.kind
        return VStack(spacing: 3) {
            PaintFill(paint: paint.preview(as: kind))
                .frame(height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(.primary.opacity(0.18), lineWidth: 1))
                .overlay {
                    if isOn {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.accentColor, lineWidth: 2)
                            .padding(-2)
                    }
                }
            Text(kind.title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(isOn ? .primary : .secondary)
        }
    }
}

// MARK: - Where it is aimed, and what is on the ramp

/// The aim pad and the ramp, side by side: the two things a gradient has that a
/// flat color does not.
struct GradientGeometryRow: View {
    @Binding var paint: Paint
    @Binding var stopIndex: Int
    /// Called on every frame of a drag, so the picture follows the aim rather
    /// than appearing where you guessed. Records nothing.
    let onDrag: () -> Void
    /// Called once a change has landed — the end of a drag, a button press —
    /// never on every tick, so aiming a gradient is one undo step.
    let onCommit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            GradientAimPad(paint: $paint, onDrag: onDrag, onCommit: onCommit)
            VStack(alignment: .leading, spacing: 6) {
                GradientRamp(paint: $paint, stopIndex: $stopIndex,
                             onDrag: onDrag, onCommit: onCommit)
                stopBar
            }
        }
    }

    private var stopBar: some View {
        HStack(spacing: 6) {
            Text(readout)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            mini("plus", "Add a stop") {
                stopIndex = paint.addStop(after: stopIndex)
                onCommit()
            }
            mini("minus", "Remove this stop") {
                guard paint.removeStop(at: stopIndex) else { return }
                stopIndex = min(stopIndex, paint.stops.count - 1)
                onCommit()
            }
            .disabled(paint.stops.count <= 2)
            mini("arrow.left.arrow.right", "Reverse the ramp") {
                paint.reverseStops()
                onCommit()
            }
        }
    }

    /// Which stop is being edited, in the words the ramp is showing: the big
    /// square above edits THIS one, and a person needs to be told that once.
    private var readout: String {
        guard paint.stops.indices.contains(stopIndex) else { return "" }
        let place = Int((paint.stops[stopIndex].position * 100).rounded())
        return "Stop \(stopIndex + 1) · \(place)%"
    }

    private func mini(_ symbol: String, _ tip: String,
                      _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 18, height: 16)
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .help(tip)
        .accessibilityLabel(tip)
    }
}

/// The square you point at. Drag it to aim a straight run, or to move where a
/// spreading or sweeping one comes from. The number in the corner reads back
/// what the drag did; it is never the way in.
private struct GradientAimPad: View {
    @Binding var paint: Paint
    /// Every frame while the pointer is down, so the run you are aiming shows
    /// up on the picture as you aim it.
    let onDrag: () -> Void
    let onCommit: () -> Void

    private static let side: CGFloat = 64
    /// How close to the centre counts as taking hold of the centre rather than
    /// aiming around it.
    private static let grabRadius: CGFloat = 0.17

    @State private var grab: CGSize?
    @State private var isDragging = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            PaintFill(paint: paint)
            handles
            Text(readout)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4).fill(.black.opacity(0.55)))
                .padding(3)
                .allowsHitTesting(false)
        }
        .frame(width: Self.side, height: Self.side)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.primary.opacity(0.18), lineWidth: 1))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    aim(at: value.location, first: !isDragging)
                    isDragging = true
                    onDrag()
                }
                .onEnded { value in
                    aim(at: value.location, first: false)
                    isDragging = false
                    grab = nil
                    onCommit()
                }
        )
        .accessibilityLabel("Gradient direction")
        .accessibilityValue(readout)
        .help(paint.kind == .radial
              ? "Drag to move where the gradient spreads from"
              : "Drag to aim the gradient. Drag the small handle to move where it starts.")
    }

    /// A line from the origin to the direction, with a handle on each end. The
    /// small one moves the origin, the big one aims; both look alike because
    /// both can be picked up, and nothing in the pad is drawn like a handle
    /// unless the pointer can actually take hold of it.
    private var handles: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let origin = CGPoint(x: size.width * paint.center.x, y: size.height * paint.center.y)
            let radians = paint.angle * .pi / 180
            let reach = min(size.width, size.height) / 2 - 4
            let tip = CGPoint(x: origin.x + sin(radians) * reach,
                              y: origin.y - cos(radians) * reach)
            ZStack {
                if paint.kind != .radial {
                    Path { $0.move(to: origin); $0.addLine(to: tip) }
                        .stroke(.white.opacity(0.85), lineWidth: 1.5)
                    handle(at: tip, diameter: 8)
                }
                // Nothing in the pad is drawn like a handle unless it can
                // actually be picked up. A straight run always passes through
                // the middle, so it has no origin to move and gets no handle
                // there — only the end of its axis, which turns it.
                if paint.kind != .linear { handle(at: origin, diameter: 7) }
            }
        }
        .allowsHitTesting(false)
    }

    private func handle(at point: CGPoint, diameter: CGFloat) -> some View {
        Circle()
            .fill(.white)
            .overlay(Circle().strokeBorder(.black.opacity(0.45), lineWidth: 1))
            .frame(width: diameter, height: diameter)
            .position(point)
    }

    private var readout: String {
        switch paint.kind {
        case .radial:
            return "\(Int((paint.center.x * 100).rounded())), \(Int((paint.center.y * 100).rounded()))"
        default:
            return "\(Int(paint.angle.rounded()))°"
        }
    }

    /// Grab, do not teleport: pressing near the origin keeps the offset so it
    /// does not jump out from under the pointer. Press well away from it and a
    /// spreading paint places its origin directly, which is the faster gesture
    /// when that is what you meant.
    private func aim(at point: CGPoint, first: Bool) {
        let x = min(max(point.x / Self.side, 0), 1)
        let y = min(max(point.y / Self.side, 0), 1)
        let cx = paint.center.x, cy = paint.center.y
        if first {
            let onOrigin = abs(x - cx) < Self.grabRadius && abs(y - cy) < Self.grabRadius
            // A straight run has no origin to move: the line always passes
            // through the middle, so every drag on it is an aim.
            grab = (onOrigin && paint.kind != .linear) ? CGSize(width: cx - x, height: cy - y) : nil
        }
        if let grab {
            paint.center = CGPoint(x: min(max(x + grab.width, 0), 1),
                                   y: min(max(y + grab.height, 0), 1))
        } else if paint.kind == .radial {
            paint.center = CGPoint(x: x, y: y)
        } else {
            let dx = x - cx, dy = y - cy
            guard abs(dx) > 0.001 || abs(dy) > 0.001 else { return }
            let degrees = atan2(dx, -dy) * 180 / .pi
            paint.angle = (degrees.rounded() + 360).truncatingRemainder(dividingBy: 360)
        }
    }
}

/// The ramp: the colors in order, with a key for each. Click a key to edit that
/// color in the square above; drag it to move it; the arrow keys nudge it.
private struct GradientRamp: View {
    @Binding var paint: Paint
    @Binding var stopIndex: Int
    /// Every frame while a key is being slid, so the ramp on the picture moves
    /// with the key rather than after it.
    let onDrag: () -> Void
    let onCommit: () -> Void

    private static let height: CGFloat = 24

    /// Where the key was when the drag started. Without it the translation
    /// would be measured against a position that has already moved, and the
    /// key would run away from the pointer.
    @State private var dragOrigin: Double?

    /// Half a key's width. The ramp is inset by this on both sides so a stop
    /// at either end sits fully on it rather than hanging off the edge.
    private static let keyInset: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width - Self.keyInset * 2, 1)
            ZStack(alignment: .topLeading) {
                LinearGradient(stops: paint.swiftUIStops, startPoint: .leading, endPoint: .trailing)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .background {
                        CheckerBoard(square: 4).clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .overlay(RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(.primary.opacity(0.18), lineWidth: 1))
                    .padding(.horizontal, Self.keyInset)
                ForEach(Array(paint.stops.enumerated()), id: \.offset) { index, stop in
                    key(index: index, stop: stop, width: width)
                }
            }
        }
        .frame(height: Self.height)
    }

    private func key(index: Int, stop: GradientStop, width: CGFloat) -> some View {
        let isOn = index == stopIndex
        return RoundedRectangle(cornerRadius: 3)
            .fill(Color(hex: stop.hex))
            .frame(width: 12, height: 12)
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.white, lineWidth: 2))
            .overlay {
                if isOn {
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .padding(-2)
                }
            }
            .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
            .offset(x: Self.keyInset + stop.position * width - 6, y: 6)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        stopIndex = index
                        let from = dragOrigin ?? stop.position
                        dragOrigin = from
                        move(index, to: from + value.translation.width / width)
                        onDrag()
                    }
                    .onEnded { value in
                        stopIndex = index
                        move(index, to: (dragOrigin ?? stop.position) + value.translation.width / width)
                        dragOrigin = nil
                        onCommit()
                    }
            )
            .help("\(stop.hex) at \(Int((stop.position * 100).rounded()))%")
            .accessibilityLabel("Stop \(index + 1)")
    }

    private func move(_ index: Int, to position: Double) {
        guard paint.stops.indices.contains(index) else { return }
        paint.stops[index].position = min(max(position, 0), 1)
    }
}
