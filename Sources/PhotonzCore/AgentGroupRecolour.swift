import CoreGraphics
import Foundation

/// A colour set on a group recolours what it holds ("make the cat black", on
/// a drawing that is a group of filled parts). The colour covering the most of
/// the drawing becomes the one asked for, and every other part keeps how much
/// lighter or darker than it it was, in the new hue, so stripes, ears and eyes
/// stay. A part that would land within a glance of the main colour (an eye
/// darker than a body that is now black) is pushed the other way instead, so
/// no detail disappears. It knows nothing about what the drawing is of.
public enum AgentGroupRecolour {

    /// The smallest step in lightness between a detail and the main colour.
    static let leastStep = 0.12

    /// `layer`, a group, with every fill inside it recoloured toward `hex`.
    public static func recolour(_ layer: Layer, to hex: String) -> Layer {
        guard let main = mainColour(of: layer) else { return layer }
        let from = hsl(rgb(main)), to = hsl(rgb(hex))
        func shifted(_ colour: String) -> String {
            if colour.uppercased() == main.uppercased() { return hex.uppercased() }
            let was = hsl(rgb(colour))
            let step = was.l - from.l
            var l = min(0.98, max(0.02, to.l + step))
            if abs(l - to.l) < leastStep {
                var sign: Double = step < 0 ? -1 : 1
                if to.l + sign * leastStep < 0.02 || to.l + sign * leastStep > 0.98 { sign = -sign }
                l = to.l + sign * max(leastStep, abs(step))
            }
            let s = to.s < 0.08 ? to.s : min(1, max(0, to.s + (was.s - from.s) * 0.5))
            return hexString(fromHSL: (to.h, s, min(0.98, max(0.02, l))))
        }
        return mapping(layer, shifted)
    }

    /// The colour a person sees most of in `layer`: a grid of points over
    /// it, each counted for the topmost part drawn there. A traced drawing
    /// stacks a dark silhouette under its lighter body, so the part with the
    /// biggest box is often the one seen least (its outline).
    public static func mainColour(of layer: Layer) -> String? {
        var parts: [Part] = []
        collect(layer, offset: .zero, into: &parts)
        guard !parts.isEmpty else { return nil }
        let box = parts.reduce(CGRect.null) { $0.union($1.box) }
        var seen: [String: Int] = [:]
        let side = 48
        if box.width > 0, box.height > 0 {
            for row in 0..<side {
                for column in 0..<side {
                    let point = CGPoint(x: box.minX + (CGFloat(column) + 0.5) / CGFloat(side) * box.width,
                                        y: box.minY + (CGFloat(row) + 0.5) / CGFloat(side) * box.height)
                    // Children run bottom first, so the last part holding the point is on top.
                    if let top = parts.last(where: { $0.holds(point) }) { seen[top.colour, default: 0] += 1 }
                }
            }
        }
        if let main = seen.max(by: { $0.value < $1.value })?.key { return main }
        // Nothing hit (parts too thin to sample): the biggest box.
        return parts.max { $0.box.width * $0.box.height < $1.box.width * $1.box.height }?.colour
    }

    private struct Part {
        let box: CGRect
        let colour: String
        let outline: CGPath?
        let evenOdd: Bool

        func holds(_ point: CGPoint) -> Bool {
            guard box.contains(point) else { return false }
            guard let outline else { return true }
            return outline.contains(CGPoint(x: point.x - box.minX, y: point.y - box.minY),
                                    using: evenOdd ? .evenOdd : .winding)
        }
    }

    private static func collect(_ layer: Layer, offset: CGPoint, into parts: inout [Part]) {
        let origin = CGPoint(x: offset.x + layer.frame.minX, y: offset.y + layer.frame.minY)
        if let children = layer.group?.children {
            for child in children { collect(child, offset: origin, into: &parts) }
            return
        }
        let box = CGRect(origin: origin, size: layer.frame.size)
        if let path = layer.path, let fill = path.fill {
            parts.append(Part(box: box, colour: fill.hex.uppercased(), outline: path.cgPath, evenOdd: path.fillRule == .evenOdd))
        } else if let fill = layer.annotation?.fill {
            parts.append(Part(box: box, colour: fill.hex.uppercased(), outline: nil, evenOdd: false))
        }
    }

    // MARK: Walking the parts

    private static func mapping(_ layer: Layer, _ shift: (String) -> String) -> Layer {
        var layer = layer
        if var group = layer.group {
            group.children = group.children.map { mapping($0, shift) }
            layer.content = .group(group)
        } else if var path = layer.path, let fill = path.fill {
            path.fill = Paint(hex: shift(fill.hex))
            layer.content = .path(path)
        } else if var annotation = layer.annotation, let fill = annotation.fill {
            annotation.fill = Paint(hex: shift(fill.hex))
            layer.content = .annotation(annotation)
        }
        return layer
    }

    // MARK: Colour

    static func rgb(_ hex: String) -> (r: Double, g: Double, b: Double) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).prefix(6)
        let value = UInt32(digits, radix: 16) ?? 0
        return (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
    }

    static func hsl(_ c: (r: Double, g: Double, b: Double)) -> (h: Double, s: Double, l: Double) {
        let high = max(c.r, c.g, c.b), low = min(c.r, c.g, c.b)
        let l = (high + low) / 2
        guard high > low else { return (0, 0, l) }
        let d = high - low
        let s = l > 0.5 ? d / (2 - high - low) : d / (high + low)
        var h: Double
        if high == c.r { h = (c.g - c.b) / d + (c.g < c.b ? 6 : 0) } else if high == c.g { h = (c.b - c.r) / d + 2 } else { h = (c.r - c.g) / d + 4 }
        h /= 6
        return (h, s, l)
    }

    static func hexString(fromHSL c: (h: Double, s: Double, l: Double)) -> String {
        func channel(_ p: Double, _ q: Double, _ t: Double) -> Double {
            var t = t
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1 / 6 { return p + (q - p) * 6 * t }
            if t < 1 / 2 { return q }
            if t < 2 / 3 { return p + (q - p) * (2 / 3 - t) * 6 }
            return p
        }
        let r, g, b: Double
        if c.s == 0 {
            (r, g, b) = (c.l, c.l, c.l)
        } else {
            let q = c.l < 0.5 ? c.l * (1 + c.s) : c.l + c.s - c.l * c.s
            let p = 2 * c.l - q
            (r, g, b) = (channel(p, q, c.h + 1 / 3), channel(p, q, c.h), channel(p, q, c.h - 1 / 3))
        }
        func byte(_ v: Double) -> Int { Int((min(1, max(0, v)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }
}
