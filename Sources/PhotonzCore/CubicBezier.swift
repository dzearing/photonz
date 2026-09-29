import Foundation

/// A CSS timing curve, on its own so a small piece of motion (the segmented
/// thumb's morph, `SegmentThumbMorph`) can be compiled without the whole of
/// `LayerMotion`: `Scripts/segmented-gallery.swift` builds the control from
/// its own files.
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
