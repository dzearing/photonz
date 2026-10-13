import Foundation

/// A CSS timing curve (`LayerMotion`'s easing), evaluated the way a browser
/// does it.
enum CubicBezier {
    /// `cubic-bezier(x1,y1,x2,y2)` evaluated the way a browser does it: find
    /// the parameter whose x is the time you asked for, then read its y.
    ///
    /// Newton first because it converges in a handful of steps on the curves
    /// anybody actually draws, bisection after it because Newton stalls where
    /// the curve is flat and a stalled solver would silently return the wrong
    /// shape rather than fail.
    static func value(_ t: Double, _ x1: Double, _ y1: Double,
                      _ x2: Double, _ y2: Double) -> Double {
        func curve(_ a: Double, _ b: Double, _ u: Double) -> Double {
            let v = 1 - u
            return 3 * v * v * u * a + 3 * v * u * u * b + u * u * u
        }
        func slope(_ a: Double, _ b: Double, _ u: Double) -> Double {
            let v = 1 - u
            return 3 * v * v * a + 6 * v * u * (b - a) + 3 * u * u * (1 - b)
        }
        // A curve with its control points on the diagonal in x is already
        // parameterised by time, which is what linear is.
        if x1 == y1 && x2 == y2 { return t }
        if t <= 0 { return 0 }
        if t >= 1 { return 1 }

        var u = t
        for _ in 0..<8 {
            let x = curve(x1, x2, u) - t
            if abs(x) < 1e-7 { return curve(y1, y2, u) }
            let d = slope(x1, x2, u)
            if abs(d) < 1e-7 { break }
            u -= x / d
        }
        var low = 0.0
        var high = 1.0
        u = t
        for _ in 0..<32 {
            let x = curve(x1, x2, u)
            if abs(x - t) < 1e-7 { break }
            if x > t { high = u } else { low = u }
            u = (low + high) / 2
        }
        return curve(y1, y2, u)
    }
}

// MARK: - Splitting a curve in two

extension CubicBezier {
    /// The curve's own parameter where its time is `t`, found the way `value`
    /// finds it.
    static func parameter(_ t: Double, _ x1: Double, _ x2: Double) -> Double {
        func curve(_ u: Double) -> Double {
            let v = 1 - u
            return 3 * v * v * u * x1 + 3 * v * u * u * x2 + u * u * u
        }
        if t <= 0 { return 0 }
        if t >= 1 { return 1 }
        var low = 0.0
        var high = 1.0
        var u = t
        for _ in 0..<60 {
            let x = curve(u)
            if abs(x - t) < 1e-10 { break }
            if x > t { high = u } else { low = u }
            u = (low + high) / 2
        }
        return u
    }

    /// `cubic-bezier(x1,y1,x2,y2)` cut at time `t` into the two curves that
    /// play its two halves, each stated in its own unit square: the left one
    /// runs from nought to the value at `t`, the right one from there to one.
    /// Nil where a half does not change at all, which has no square to state
    /// it in (it is flat, and any curve plays it).
    static func split(at t: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double)
        -> (left: (Double, Double, Double, Double)?, right: (Double, Double, Double, Double)?) {
        let u = parameter(t, x1, x2)
        func lerp(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u)
        }
        // de Casteljau.
        let p0 = CGPoint.zero, p1 = CGPoint(x: x1, y: y1), p2 = CGPoint(x: x2, y: y2), p3 = CGPoint(x: 1, y: 1)
        let a = lerp(p0, p1), b = lerp(p1, p2), c = lerp(p2, p3)
        let d = lerp(a, b), e = lerp(b, c)
        let mid = lerp(d, e)
        func unit(_ point: CGPoint, from start: CGPoint, to end: CGPoint) -> CGPoint? {
            let w = end.x - start.x, h = end.y - start.y
            guard w > 1e-9, abs(h) > 1e-9 else { return nil }
            return CGPoint(x: (point.x - start.x) / w, y: (point.y - start.y) / h)
        }
        var left: (Double, Double, Double, Double)?
        if let one = unit(a, from: p0, to: mid), let two = unit(d, from: p0, to: mid) {
            left = (Double(one.x), Double(one.y), Double(two.x), Double(two.y))
        }
        var right: (Double, Double, Double, Double)?
        if let one = unit(e, from: mid, to: p3), let two = unit(c, from: mid, to: p3) {
            right = (Double(one.x), Double(one.y), Double(two.x), Double(two.y))
        }
        return (left, right)
    }
}

extension EasingCurve {
    /// The two control points of the cubic Bezier this curve is, where it is
    /// one.
    var bezierControls: (Double, Double, Double, Double)? {
        switch self {
        case .linear: (0, 0, 1, 1)
        case .easeInOut: (0.4, 0, 0.2, 1)
        case .easeIn: (0.4, 0, 1, 1)
        case .easeOut: (0, 0, 0.2, 1)
        case .easeOutQuint: (0.22, 1, 0.36, 1)
        case .easeOutExpo: (0.16, 1, 0.3, 1)
        case let .custom(x1, y1, x2, y2): (x1, y1, x2, y2)
        default: nil
        }
    }

    /// This curve cut at `t` of the way through its time into the two that
    /// play its halves: what a point added part way along a stretch gives
    /// the two stretches it makes, so the line keeps its shape. Exact for
    /// every curve a Bezier draws; a curve no Bezier draws (a bounce, steps)
    /// keeps itself on both halves, the nearest the halves can come.
    public func split(at t: Double) -> (EasingCurve, EasingCurve) {
        if self == .linear { return (.linear, .linear) }
        guard t > 0, t < 1, let (x1, y1, x2, y2) = bezierControls else { return (self, self) }
        let (left, right) = CubicBezier.split(at: t, x1, y1, x2, y2)
        func made(_ controls: (Double, Double, Double, Double)?) -> EasingCurve {
            guard let (a, b, c, d) = controls else { return .linear }
            return .custom(x1: a, y1: b, x2: c, y2: d)
        }
        return (made(left), made(right))
    }
}
