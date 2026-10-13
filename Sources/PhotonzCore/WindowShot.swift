import CoreGraphics
import Foundation

/// A clicked window captured the way the built-in macOS window capture does
/// it: rendered on its own by the window server, with its drop shadow around
/// it and see-through rounded corners, instead of a rectangle cut out of the
/// frozen screen picture with the desktop showing through the corners.
///
/// This decides which look a click asks for and whether what came back is a
/// faithful shot of the window. The capture itself is the app layer's job.
public enum WindowShot {

    public enum Style: Sendable, Equatable {
        /// The window and its shadow, transparent around and in the corners.
        case withShadow
        /// The window's own bounds only, transparent in the corners.
        case bareBounds
    }

    /// Which look a click asks for. `includeShadow` is the setting; holding
    /// Option while clicking gives the other choice, the way Option drops the
    /// shadow in the built-in capture.
    public static func style(includeShadow: Bool, optionHeld: Bool) -> Style {
        (includeShadow != optionHeld) ? .withShadow : .bareBounds
    }

    /// Pixels of rounding a shot may miss the window by and still be the window.
    public static let tolerance: CGFloat = 1

    /// Whether an image `pixelSize` big is a faithful shot of a window
    /// `windowSize` points wide at `scale` pixels per point. A bare shot must
    /// cover the whole window (bigger is fine: a sheet may hang outside it). A
    /// shadowed shot must be larger than the window in both directions, since
    /// a shadow adds margin on every side; one that comes back at the window's
    /// own size had the shadow squeezed inside, shrinking the window, or
    /// dropped, and is not the shot that was asked for.
    public static func isFaithful(pixelSize: CGSize, windowSize: CGSize, scale: CGFloat,
                                  style: Style) -> Bool {
        guard pixelSize.width > 0, pixelSize.height > 0,
              windowSize.width > 0, windowSize.height > 0, scale > 0 else { return false }
        let wanted = CGSize(width: (windowSize.width * scale).rounded(),
                            height: (windowSize.height * scale).rounded())
        switch style {
        case .bareBounds:
            return pixelSize.width >= wanted.width - tolerance
                && pixelSize.height >= wanted.height - tolerance
        case .withShadow:
            return pixelSize.width > wanted.width + tolerance
                && pixelSize.height > wanted.height + tolerance
        }
    }
}

// MARK: - The shadow a clicked window is given

/// A clicked window used to keep the shadow the window server drew around it,
/// baked into the picture, and that shadow reads far too dark on the canvas and
/// pasted into other apps (the user, 2026-10-13: "should be quite a bit more
/// transparent"). So the window is now shot bare and given its shadow as a
/// layer style: macOS's own shape, at `shadowStrength` of the opacity macOS drew
/// it at, which can be lightened, moved, recoloured or switched off later.
extension WindowShot {

    /// How strong a clicked window's shadow is, as a share of macOS's own.
    public static let shadowStrength: Double = 0.4

    /// The two shapes the window server gives a window's shadow, in points.
    /// Measured with `--window-shot-diag` on macOS 26 on 2026-10-12, by fitting
    /// a blurred, offset box to the alpha outward from all four edges of real
    /// titled windows (every fit within 0.6 of a level of 8 bit alpha):
    ///
    /// | window          | blur  | down | spread | opacity |
    /// |-----------------|-------|------|--------|---------|
    /// | inactive, light | 11.75 | 8    | 0.25   | 0.248   |
    /// | inactive, dark  | 11.5  | 8    | 0.75   | 0.431   |
    /// | active, light   | 19.5  | 18   | 0.75   | 0.389   |
    /// | active, dark    | 19.5  | 18   | 0.75   | 0.684   |
    ///
    /// The shape follows whether the window was in front; the opacity also
    /// follows its appearance, so it is read off each shot rather than assumed.
    public struct SystemShadow: Equatable, Sendable {
        public enum Look: Equatable, Sendable { case inactive, active }
        public let look: Look
        /// Gaussian sigma, points.
        public let blur: CGFloat
        /// How far below the window the shadow is thrown, points.
        public let offsetY: CGFloat
        public let spread: CGFloat
        /// The opacity of a light window's shadow, used when none could be read.
        public let lightOpacity: Double

        public static let inactive = SystemShadow(look: .inactive, blur: 11.75, offsetY: 8, spread: 0.5,
                                                  lightOpacity: 0.248)
        public static let active = SystemShadow(look: .active, blur: 19.5, offsetY: 18, spread: 0.75,
                                                lightOpacity: 0.389)
        public static let all = [inactive, active]
    }

    /// Alpha, 0 to 1, read outward from the middle of each edge of a shot with
    /// the shadow in it. Index 0 is the pixel touching the window.
    public struct EdgeProfiles: Equatable, Sendable {
        public var below: [Double]
        public var above: [Double]
        public var left: [Double]
        public var right: [Double]

        public init(below: [Double], above: [Double], left: [Double], right: [Double]) {
            self.below = below
            self.above = above
            self.left = left
            self.right = right
        }
    }

    /// macOS's shadow as it was drawn around one window.
    public struct Reading: Equatable, Sendable {
        public let look: SystemShadow.Look
        /// The soft shadow's opacity.
        public let opacity: Double
        /// The opacity of the one pixel hairline right against the window's
        /// edge, which is what seats a dark window on a dark page.
        public let ringOpacity: Double

        public init(look: SystemShadow.Look, opacity: Double, ringOpacity: Double) {
            self.look = look
            self.opacity = opacity
            self.ringOpacity = ringOpacity
        }

        public var shape: SystemShadow { look == .active ? .active : .inactive }
    }

    /// Which of the two shapes the shadow in a shot is, and how dark macOS drew
    /// it. Each shape is tried against every edge at once with the opacity
    /// solved in closed form, and the one that explains the pixels best wins.
    /// Nil when nothing there reads as a shadow.
    public static func readSystemShadow(_ profiles: EdgeProfiles, pixelScale: CGFloat) -> Reading? {
        let scale = pixelScale > 0 ? pixelScale : 1
        var best: (error: Double, look: SystemShadow.Look, opacity: Double)?
        for shape in SystemShadow.all {
            let sigma = Double(shape.blur * scale)
            let spread = Double(shape.spread * scale), down = Double(shape.offsetY * scale)
            let sides = [(profiles.below, spread + down), (profiles.above, spread - down),
                         (profiles.left, spread), (profiles.right, spread)]
            var dot = 0.0, norm = 0.0, energy = 0.0, count = 0.0
            for (alphas, reach) in sides {
                // Index 0 and 1 hold the hairline; the soft shadow is the rest.
                for t in alphas.indices.dropFirst(2) {
                    let model = gaussianEdge((reach - (Double(t) + 0.5)) / sigma)
                    dot += model * alphas[t]
                    norm += model * model
                    energy += alphas[t] * alphas[t]
                    count += 1
                }
            }
            guard norm > 0, count > 0 else { continue }
            let opacity = dot / norm
            let error = (energy - dot * dot / norm) / count
            if best == nil || error < (best?.error ?? .infinity) { best = (error, shape.look, opacity) }
        }
        // Fainter than two levels of alpha at its darkest is not a shadow.
        guard let best, best.opacity > 0.02, best.opacity <= 1.05 else { return nil }
        let opacity = min(best.opacity, 1)
        let shape = best.look == .active ? SystemShadow.active : SystemShadow.inactive
        // The hairline, from the sides (the throw down moves the top and bottom
        // ones), less what the soft shadow already puts on that pixel.
        let edges = [profiles.left.first, profiles.right.first].compactMap { $0 }
        var ring = 0.0
        if !edges.isEmpty {
            let touching = edges.reduce(0, +) / Double(edges.count)
            let sigma = Double(shape.blur * scale)
            let soft = opacity * gaussianEdge((Double(shape.spread * scale) - 0.5) / sigma)
            ring = soft < 1 ? max(0, 1 - (1 - touching) / (1 - soft)) : 0
        }
        return Reading(look: best.look, opacity: (opacity * 1000).rounded() / 1000,
                       ringOpacity: (min(ring, 1) * 1000).rounded() / 1000)
    }

    /// How dark a gaussian-blurred edge is `x` sigmas inside it.
    private static func gaussianEdge(_ x: Double) -> Double {
        0.5 * (1 + erf(x / 2.0.squareRoot()))
    }

    /// The hairline is one pixel grown out of the window and barely softened,
    /// which is what macOS draws at 2x. Divided by how much of the shadow that
    /// pixel gets, so the pixel lands at the opacity read off the shot.
    static let ringSpreadPixels: CGFloat = 1
    static let ringBlurPixels: CGFloat = 0.5
    private static let ringCoverage = gaussianEdge(Double((ringSpreadPixels - 0.5) / ringBlurPixels))

    /// The shadows a clicked window comes in with, in image pixels at
    /// `pixelScale` pixels per point: the soft shadow, then the hairline, both
    /// at `shadowStrength` of what macOS drew. The soft one is first so it is
    /// Shadow 1 in the panel, the one a person reaches for. With no reading,
    /// the lightest shadow macOS draws (an inactive light window) stands in.
    public static func shadows(for reading: Reading?, pixelScale: CGFloat) -> [ShadowStyle] {
        let scale = pixelScale > 0 ? pixelScale : 1
        let shape = reading?.shape ?? .inactive
        let opacity = reading?.opacity ?? shape.lightOpacity
        // An inactive light window's hairline, read with the same diag.
        let ringOpacity = reading?.ringOpacity ?? 0.27
        func rounded(_ value: Double) -> Double { (value * 1000).rounded() / 1000 }
        let ring = ShadowStyle(radius: ringBlurPixels, offset: .zero, spread: ringSpreadPixels,
                               colorHex: "#000000",
                               opacity: rounded(min(1, ringOpacity / ringCoverage) * shadowStrength))
        let soft = ShadowStyle(radius: shape.blur * scale, offset: CGSize(width: 0, height: shape.offsetY * scale),
                               spread: shape.spread * scale, colorHex: "#000000",
                               opacity: rounded(opacity * shadowStrength))
        return [soft, ring]
    }

    /// How far a set of drop shadows reaches past a box on each side, in the
    /// shadows' own units, rounded up to whole pixels. Three sigmas out a
    /// gaussian has let go of all but a seventh of a percent of the shadow,
    /// under one level of an 8 bit alpha at any opacity a shadow has.
    public struct Margins: Equatable, Sendable {
        public var top: CGFloat
        public var left: CGFloat
        public var bottom: CGFloat
        public var right: CGFloat

        public init(top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat) {
            self.top = top
            self.left = left
            self.bottom = bottom
            self.right = right
        }

        public static let zero = Margins(top: 0, left: 0, bottom: 0, right: 0)
    }

    public static func margins(for shadows: [ShadowStyle]) -> Margins {
        var out = Margins.zero
        for shadow in shadows where shadow.paints && shadow.kind == .drop {
            let reach = shadow.radius * 3 + max(shadow.spread, 0)
            out.top = max(out.top, reach - shadow.offset.height)
            out.bottom = max(out.bottom, reach + shadow.offset.height)
            out.left = max(out.left, reach - shadow.offset.width)
            out.right = max(out.right, reach + shadow.offset.width)
        }
        return Margins(top: max(0, out.top.rounded(.up)), left: max(0, out.left.rounded(.up)),
                       bottom: max(0, out.bottom.rounded(.up)), right: max(0, out.right.rounded(.up)))
    }

    /// The document a clicked window becomes: the bare window as one layer,
    /// wearing the window shadow as a layer style, on a transparent canvas just
    /// big enough that none of the shadow is cut off.
    ///
    /// The window layer is not locked: a locked layer cannot be picked, and the
    /// shadow is only reachable through the picked layer's panel.
    public static func document(window ref: ImageRef, pixelScale: CGFloat,
                                reading: Reading?) -> PhotonzDocument {
        let shadows = shadows(for: reading, pixelScale: pixelScale)
        let margin = margins(for: shadows)
        var style = LayerStyle()
        style.shadows = shadows
        let layer = Layer(name: "Window", content: .image(ref),
                          frame: CGRect(x: margin.left, y: margin.top,
                                        width: ref.pixelSize.width, height: ref.pixelSize.height),
                          style: style)
        let canvas = CGSize(width: ref.pixelSize.width + margin.left + margin.right,
                            height: ref.pixelSize.height + margin.top + margin.bottom)
        return PhotonzDocument(canvasSize: canvas, layers: [layer], pixelScale: pixelScale)
    }
}
