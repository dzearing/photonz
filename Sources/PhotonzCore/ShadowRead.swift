import CoreGraphics
import Foundation

/// Reads the shadow a box throws, off the picture, so a separated card can
/// bring it with it as a REAL shadow rather than leaving a grey halo of itself
/// baked into the page.
///
/// This is the one part of Separate into Layers where getting it wrong is worse
/// than not doing it at all: a card wearing a shadow that is not the one it had
/// looks broken in a way a card with no shadow does not. So the reading is
/// modelled rather than guessed, and every gate below is a reason to hand back
/// nil.
///
/// ## The model
///
/// A drop shadow is the box's own silhouette, blurred by a gaussian, moved by
/// an offset, painted in one colour at one opacity. Along the middle of a
/// straight edge, well away from the corners, the blur of a half-plane is
/// exactly the gaussian's own integral, so how dark the picture is `t` pixels
/// out from that edge is
///
///     alpha(t) = opacity · Phi((o - t) / sigma)
///
/// where `o` is how far the shadow reaches past that edge: `-dx` on the left,
/// `+dx` on the right, `-dy` on the top, `+dy` on the bottom. Four unknowns —
/// opacity, sigma, dx, dy — fitted against all four edges at once, which is
/// what makes the reading checkable: a real shadow explains every edge with the
/// SAME opacity and the SAME sigma, and almost nothing else does.
///
/// ## What is deliberately not read
///
/// - **Spread.** A shadow whose silhouette was grown or shrunk before blurring
///   reaches the same distance past the left edge as past the right, which this
///   model cannot say at the same time as an offset. Those come back nil and
///   the box stays in the picture. Real UI shadows almost never carry one.
/// - **A tinted shadow.** The colour is read as black at some opacity, which is
///   what a screenshot's shadow nearly always is. A shadow whose darkening does
///   not point straight at black is refused rather than approximated.
/// - **A glow.** Only darkening is read. Something brighter than the page
///   around a box is not a shadow and is left alone.
///
/// Full design: `docs/design/separate-into-layers.md`.
public enum ShadowRead {

    /// A shadow, read off a picture.
    public struct Reading: Equatable, Sendable {
        /// The shadow itself, ready to hang on the layer the box becomes.
        public let style: ShadowStyle
        /// What the page behind the shadow is painted, so the space the box and
        /// its shadow came out of can be filled with it.
        public let page: RGBA
        /// How far past the box, in image pixels, the shadow darkened anything
        /// at all. What has to be painted over so no smudge is left behind.
        public let reach: CGFloat

        public init(style: ShadowStyle, page: RGBA, reach: CGFloat) {
            self.style = style
            self.page = page
            self.reach = reach
        }

        /// What the picture looked like at a pixel BEFORE the box was drawn on
        /// it: the page, darkened by however much of this shadow fell there.
        ///
        /// Used to unmix the box's own antialiased rim, which is a blend of the
        /// box and the shadowed page rather than of the box and the page. The
        /// silhouette is taken as the plain rectangle, so within a corner's
        /// rounding this reads very slightly dark; everywhere else it is the
        /// model the fit was checked against.
        public func background(at x: Int, y: Int, of box: CGRect) -> RGBA {
            let sigma = max(Double(style.radius), 0.0001)
            let dx = Double(style.offset.width), dy = Double(style.offset.height)
            let px = Double(x) + 0.5, py = Double(y) + 0.5
            let across = band(px, Double(box.minX) + dx, Double(box.maxX) + dx, sigma)
            let down = band(py, Double(box.minY) + dy, Double(box.maxY) + dy, sigma)
            let alpha = style.opacity * across * down
            let ink = RGBA(hex: style.colorHex) ?? RGBA(r: 0, g: 0, b: 0)
            return RGBA(r: page.r * (1 - alpha) + ink.r * alpha,
                        g: page.g * (1 - alpha) + ink.g * alpha,
                        b: page.b * (1 - alpha) + ink.b * alpha,
                        a: page.a)
        }

        private func band(_ p: Double, _ low: Double, _ high: Double, _ sigma: Double) -> Double {
            ShadowRead.phi((p - low) / sigma) - ShadowRead.phi((p - high) / sigma)
        }
    }

    // MARK: - The numbers

    /// How far out from a box the reading looks, in image pixels. A shadow
    /// softer than this has not finished by the time we stop looking, and one
    /// we have not seen the end of is one we cannot claim to know.
    public static let maxReach = 48

    /// The fewest clean pixels a side must offer before it is worth reading. A
    /// box three pixels from the frame has most of its shadow outside the
    /// screenshot.
    public static let minRun = 7

    /// How many pixels along an edge are read at most, so a card spanning a
    /// whole window costs the same as a button.
    public static let maxAlong = 256

    /// The fewest positions along an edge worth taking a median of.
    public static let minAlong = 8

    /// How much of an edge is skipped at each end before sampling, as a
    /// fraction of its length, so the corners' own rounding never votes.
    public static let cornerSkip = 0.25
    /// And at most this many pixels, so a long card still reads most of itself.
    public static let maxCornerSkip = 24.0

    /// How far apart, in levels out of 255, two readings at the same distance
    /// along one edge may sit and still be called the same shadow. A shadow is
    /// constant along a straight edge; a reflection, a neighbour's own shadow
    /// and a page that shades sideways are not.
    public static let alongTolerance = 2.5

    /// How far apart the four edges' far ends may sit and still be called one
    /// page colour.
    public static let pageTolerance = 2.0

    /// How much darker than the reading before it, in levels out of 255, a
    /// reading has to be before it is the next thing along rather than more of
    /// this shadow. Just over half a level: a shadow never darkens outward at
    /// all, so any real step down is somebody else's.
    public static let darkerStep = 0.6

    /// The faintest shadow worth reading, in levels out of 255 at its darkest.
    /// Under three levels there is nothing to fit but rounding noise.
    public static let minPeak = 3.0

    /// How far any one reading may sit from the fitted shadow, in levels out of
    /// 255. This is the gate: a soft darkening that is not a gaussian falloff
    /// off a rectangle cannot get under it.
    public static let fitTolerance = 1.5

    /// How far a darkening may point away from straight-at-black, in levels,
    /// before it is a tint rather than a shadow.
    public static let tintTolerance = 2.0

    /// The blur the reading will consider, in image pixels.
    public static let minSigma = 0.4
    public static let maxSigma = 12.0

    /// The furthest a shadow may be thrown, in image pixels.
    public static let maxOffset = 16.0

    /// How dark, in levels out of 255, the shadow may still be at `reach`
    /// before the reach is called too short. A third of a level rounds to
    /// nothing in a byte, which is what "no smudge left behind" means.
    public static let reachFloor = 0.3

    // MARK: - Reading

    /// The shadow `box` throws in `field`, or nil when the picture does not say
    /// clearly enough what it was.
    ///
    /// `isBackdrop` says which pixels are the background the box sits on, so
    /// another control's pixels never vote on what is behind this one. The
    /// shadow itself IS backdrop: it is a slow ramp off the page colour, and
    /// the sweep's own region growing keeps it with the page.
    public static func read(_ box: CGRect, in field: PixelField,
                            isBackdrop: (Int, Int) -> Bool) -> Reading? {
        guard !field.isEmpty, box.width >= 2, box.height >= 2 else { return nil }
        // Each edge is read outward until the picture starts getting DARKER
        // again, and cut there. A shadow only ever fades; something further out
        // that darkens is the next thing along, and the commonest next thing is
        // the shadow of the card below this one. Reading past it would find
        // another shadow's darkness in this one's tail and refuse them both.
        var profiles: [Side: [RGBA]] = [:]
        for side in Side.allCases {
            guard let full = profile(side, of: box, in: field, isBackdrop: isBackdrop),
                  full.count >= minRun else { return nil }
            let run = Array(full.prefix(whileFading(full)))
            // And the page has to have come back by the end of it. It has not
            // on a reflection, on a page that shades one way, or on a shadow
            // softer than we look, and none of those is a shadow we can read.
            guard run.count >= 3 else { return nil }
            let tail = Array(run.suffix(3))
            let settled = median(tail)
            guard tail.allSatisfy({ levels(apart($0, settled)) <= pageTolerance })
            else { return nil }
            profiles[side] = run
        }

        // One page colour, agreed on by all four edges. A page that shades from
        // dark to light never agrees with itself here, which is how a gradient
        // stops being mistaken for a shadow thrown one way.
        let tails = Side.allCases.compactMap { profiles[$0].map { median(Array($0.suffix(3))) } }
        guard tails.count == Side.allCases.count else { return nil }
        let page = median(tails)
        guard tails.allSatisfy({ levels(apart($0, page)) <= pageTolerance }) else { return nil }

        // How dark each reading is, as the opacity a BLACK shadow would need —
        // and how far it points away from black, which is the tint check.
        //
        // IN LINEAR LIGHT, because that is where the renderer lays a shadow
        // down. Read in the numbers a PNG stores, a shadow ten percent black
        // over a near-white page measures about nineteen levels; laid down
        // again by the renderer, that same ten percent darkens the page by
        // nine. Fitting in the wrong space produces numbers that look right in
        // the inspector and a card that comes out twice as dark as it was.
        let lit = linear(page)
        let weight = lit.r * lit.r + lit.g * lit.g + lit.b * lit.b
        guard weight > 0.0001 else { return nil }
        var curves: [Side: [Darkness]] = [:]
        for side in Side.allCases {
            guard let profile = profiles[side] else { continue }
            var readings: [Darkness] = []
            for color in profile {
                let c = linear(color)
                let d = [lit.r - c.r, lit.g - c.g, lit.b - c.b]
                let alpha = (d[0] * lit.r + d[1] * lit.g + d[2] * lit.b) / weight
                // How many levels out of 255 this reading moves for a whole
                // unit of opacity, worked out where the reading actually sits.
                // Every tolerance here is written in levels, which is the unit
                // a screenshot is stored in and an error is visible in, and
                // this is what carries them into linear light.
                let channels = [(c.r, lit.r), (c.g, lit.g), (c.b, lit.b)]
                let per = channels.map { 255 * slope($0.0) * $0.1 }.max() ?? 0
                // A glow is not a shadow, and neither is a coloured cast.
                guard alpha * per >= -pageTolerance else { return nil }
                let tint = (0..<3).map { abs(d[$0] - alpha * channels[$0].1)
                    * 255 * slope(channels[$0].0) }.max() ?? 0
                guard tint <= tintTolerance else { return nil }
                readings.append(Darkness(alpha: max(alpha, 0), levelsPerAlpha: per))
            }
            // Only the part that still says something is fitted. Past the
            // point where the shadow has faded into the page, one more reading
            // of the page is another few thousand sums that change no answer.
            curves[side] = Array(readings.prefix(useful(readings)))
        }

        let peak = curves.values.compactMap(\.first)
            .map { $0.alpha * $0.levelsPerAlpha }.max() ?? 0
        guard peak >= minPeak else { return nil }

        guard let fit = fit(curves) else { return nil }
        // Rounded to the step the search moved in. The numbers land in the
        // Appearance list where a person reads and edits them, and a blur of
        // 3.0500000000000003 px is not a number anybody typed.
        func tidy(_ value: Double) -> Double { (value * 100).rounded() / 100 }
        let style = ShadowStyle(radius: CGFloat(tidy(fit.sigma)),
                                offset: CGSize(width: tidy(fit.dx), height: tidy(fit.dy)),
                                spread: 0, colorHex: "#000000",
                                opacity: (fit.opacity * 1000).rounded() / 1000,
                                kind: .drop, isOn: true)
        let pageLevels = [lit.r, lit.g, lit.b].map { 255 * slope($0) * $0 }.max() ?? 0
        guard let reach = reach(fit, pageLevels: pageLevels, profiles: profiles)
        else { return nil }
        return Reading(style: style, page: page, reach: CGFloat(reach))
    }

    // MARK: - One edge

    enum Side: CaseIterable, Hashable {
        case top, bottom, left, right
    }

    /// The picture's colour at each whole pixel of distance outward from one
    /// edge of `box`, as the median across the middle of that edge.
    ///
    /// Stops as soon as the band at that distance is no longer entirely
    /// background — a neighbour, or the frame of the picture — and refuses
    /// outright when the readings along the edge disagree with each other,
    /// since a real shadow is the same all the way along a straight edge.
    static func profile(_ side: Side, of box: CGRect, in field: PixelField,
                        isBackdrop: (Int, Int) -> Bool) -> [RGBA]? {
        let horizontal = side == .top || side == .bottom
        let length = horizontal ? Double(box.width) : Double(box.height)
        let skip = min(length * cornerSkip, maxCornerSkip)
        let from = Int(((horizontal ? Double(box.minX) : Double(box.minY)) + skip).rounded())
        let to = Int(((horizontal ? Double(box.maxX) : Double(box.maxY)) - skip).rounded())
        guard to - from >= minAlong else { return nil }
        let step = max(1, (to - from) / maxAlong)
        let along = Array(stride(from: from, to: to, by: step))

        var out: [RGBA] = []
        for k in 0..<maxReach {
            var colors: [RGBA] = []
            for a in along {
                let (x, y): (Int, Int)
                switch side {
                case .top: (x, y) = (a, Int(box.minY) - 1 - k)
                case .bottom: (x, y) = (a, Int(box.maxY) + k)
                case .left: (x, y) = (Int(box.minX) - 1 - k, a)
                case .right: (x, y) = (Int(box.maxX) + k, a)
                }
                guard x >= 0, y >= 0, x < field.width, y < field.height,
                      isBackdrop(x, y) else { return out }
                colors.append(field.color(x, y))
            }
            let middle = median(colors)
            // A shadow is the same all the way along a straight edge.
            guard colors.allSatisfy({ levels(apart($0, middle)) <= alongTolerance })
            else { return out }
            out.append(middle)
        }
        return out
    }

    /// How much of an edge's readings is this box's own shadow: everything up
    /// to the first reading that is darker than the one before it.
    static func whileFading(_ profile: [RGBA]) -> Int {
        for k in 1..<profile.count {
            let darker = max(profile[k - 1].r - profile[k].r,
                             max(profile[k - 1].g - profile[k].g,
                                 profile[k - 1].b - profile[k].b))
            if levels(darker) > darkerStep { return k }
        }
        return profile.count
    }

    /// How much of one edge's readings is worth fitting: everything down to
    /// where the shadow stopped darkening the page, and three more so the fit
    /// is held to coming back to nothing.
    static func useful(_ readings: [Darkness]) -> Int {
        var last = 0
        for (k, reading) in readings.enumerated()
        where reading.alpha * reading.levelsPerAlpha >= reachFloor { last = k }
        return min(readings.count, last + 4)
    }

    // MARK: - The fit

    struct Fit {
        let sigma: Double
        let dx: Double
        let dy: Double
        let opacity: Double
        let residual: Double
    }

    /// The one shadow that explains all four edges, or nil when none does.
    ///
    /// Coarse then fine over sigma and the two offsets. Two things make this
    /// cheap enough to run on every box of a screenshot:
    ///
    /// - the opacity falls out in closed form, since the model is linear in it;
    /// - the left and right edges depend only on `dx` and the top and bottom
    ///   only on `dy`, so for one sigma each edge pair is summed once per
    ///   offset and every (dx, dy) pair after that costs four arithmetic
    ///   operations rather than a walk down forty readings.
    ///
    /// The search minimises the total squared error, which is what those sums
    /// give for nothing. The ANSWER is then judged on the worst single reading,
    /// in levels out of 255, because an average would let one edge be wrong as
    /// long as the other three were right.
    static func fit(_ curves: [Side: [Darkness]]) -> Fit? {
        let all = Side.allCases.compactMap { curves[$0] }.flatMap { $0 }
        let square = all.reduce(0.0) { $0 + $1.alpha * $1.alpha }
        guard square > 0 else { return nil }

        /// How well one edge pair's readings line up with a shadow reaching
        /// `offset` past the near edge, blurred by `sigma`.
        func sums(_ pair: (Side, Side), offset: Double, sigma: Double) -> (mu: Double, mm: Double) {
            var mu = 0.0, mm = 0.0
            for (side, o) in [(pair.0, -offset), (pair.1, offset)] {
                guard let readings = curves[side] else { continue }
                for (k, reading) in readings.enumerated() {
                    let m = phi((o - (Double(k) + 0.5)) / sigma)
                    mu += m * reading.alpha
                    mm += m * m
                }
            }
            return (mu, mm)
        }

        func best(sigmas: [Double], dxs: [Double], dys: [Double])
            -> (sigma: Double, dx: Double, dy: Double)? {
            var winner: (sigma: Double, dx: Double, dy: Double)?
            var lowest = Double.greatestFiniteMagnitude
            for sigma in sigmas where sigma >= minSigma && sigma <= maxSigma {
                let across = dxs.map { sums((.left, .right), offset: $0, sigma: sigma) }
                let down = dys.map { sums((.top, .bottom), offset: $0, sigma: sigma) }
                for (i, dx) in dxs.enumerated() where abs(dx) <= maxOffset {
                    for (j, dy) in dys.enumerated() where abs(dy) <= maxOffset {
                        let mu = across[i].mu + down[j].mu
                        let mm = across[i].mm + down[j].mm
                        guard mm > 1e-9, mu > 0 else { continue }
                        let error = square - mu * mu / mm
                        if error < lowest {
                            lowest = error
                            winner = (sigma, dx, dy)
                        }
                    }
                }
            }
            return winner
        }

        let steps = stride(from: -maxOffset, through: maxOffset, by: 1).map { $0 }
        guard let coarse = best(sigmas: stride(from: minSigma, through: maxSigma, by: 0.5).map { $0 },
                                dxs: steps, dys: steps) else { return nil }
        func around(_ centre: Double) -> [Double] {
            stride(from: centre - 1, through: centre + 1, by: 0.1).map { $0 }
        }
        let fine = best(sigmas: stride(from: coarse.sigma - 0.5, through: coarse.sigma + 0.5,
                                       by: 0.05).map { $0 },
                        dxs: around(coarse.dx), dys: around(coarse.dy)) ?? coarse
        guard let answer = solve(curves, sigma: fine.sigma, dx: fine.dx, dy: fine.dy)
        else { return nil }
        guard answer.residual <= fitTolerance, answer.opacity > 0, answer.opacity <= 1,
              answer.sigma >= minSigma, answer.sigma <= maxSigma else { return nil }
        return answer
    }

    /// The best opacity for one (sigma, dx, dy), and what it leaves unexplained.
    private static func solve(_ curves: [Side: [Darkness]], sigma: Double,
                              dx: Double, dy: Double) -> Fit? {
        var numerator = 0.0, denominator = 0.0
        for side in Side.allCases {
            guard let alphas = curves[side] else { continue }
            let o = reach(of: side, dx: dx, dy: dy)
            for (k, reading) in alphas.enumerated() {
                let m = phi((o - (Double(k) + 0.5)) / sigma)
                numerator += m * reading.alpha
                denominator += m * m
            }
        }
        guard denominator > 1e-9 else { return nil }
        let opacity = numerator / denominator
        guard opacity > 0 else { return nil }
        var residual = 0.0
        for side in Side.allCases {
            guard let alphas = curves[side] else { continue }
            let o = reach(of: side, dx: dx, dy: dy)
            for (k, reading) in alphas.enumerated() {
                let m = opacity * phi((o - (Double(k) + 0.5)) / sigma)
                residual = max(residual, abs(reading.alpha - m) * reading.levelsPerAlpha)
            }
        }
        return Fit(sigma: sigma, dx: dx, dy: dy, opacity: opacity, residual: residual)
    }

    /// How far the shadow reaches past one edge, given where it was thrown.
    private static func reach(of side: Side, dx: Double, dy: Double) -> Double {
        switch side {
        case .left: return -dx
        case .right: return dx
        case .top: return -dy
        case .bottom: return dy
        }
    }

    /// How far out the fitted shadow still darkens anything, rounded up to a
    /// whole pixel. Nil when that is further than the picture let us look, in
    /// which case what is out there was never read and painting over it would
    /// be a guess.
    static func reach(_ fit: Fit, pageLevels: Double, profiles: [Side: [RGBA]]) -> Int? {
        var out = 1
        for side in Side.allCases {
            let o = reach(of: side, dx: fit.dx, dy: fit.dy)
            var t = 1
            while t <= maxReach {
                let level = fit.opacity * phi((o - Double(t)) / fit.sigma) * pageLevels
                if level < reachFloor { break }
                t += 1
            }
            guard t <= (profiles[side]?.count ?? 0) else { return nil }
            out = max(out, t)
        }
        return out
    }

    // MARK: - Small arithmetic

    /// One reading off the picture, as the opacity a black shadow would need to
    /// account for it — plus how many levels out of 255 that reading moves for
    /// a whole unit of opacity, so an error worked out in linear light can be
    /// judged in the levels a person would actually see.
    struct Darkness {
        let alpha: Double
        let levelsPerAlpha: Double
    }

    /// One channel of sRGB into the light it stands for.
    static func linear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    static func linear(_ color: RGBA) -> RGBA {
        RGBA(r: linear(color.r), g: linear(color.g), b: linear(color.b), a: color.a)
    }

    /// How fast sRGB moves when the light behind it does, at that much light.
    static func slope(_ light: Double) -> Double {
        light <= 0.0031308 ? 12.92 : (1.055 / 2.4) * pow(max(light, 1e-6), 1 / 2.4 - 1)
    }

    /// The standard normal's own integral: how much of a gaussian sits left of
    /// `z`. Blurring a straight edge with a gaussian produces exactly this.
    ///
    /// Read off a table rather than computed, because the fit asks for it
    /// millions of times per box and `erf` is the whole cost of the search.
    /// Straight-line interpolation between steps of a two-hundredth is right to
    /// about one part in ten million, which is four orders of magnitude finer
    /// than the levels the answer is judged in.
    static func phi(_ z: Double) -> Double {
        if z <= -phiLimit { return 0 }
        if z >= phiLimit { return 1 }
        let x = (z + phiLimit) / phiStep
        let i = Int(x)
        let f = x - Double(i)
        return phiTable[i] * (1 - f) + phiTable[i + 1] * f
    }

    static let phiLimit = 8.0
    static let phiStep = 0.005
    private static let phiTable: [Double] = {
        let count = Int(2 * phiLimit / phiStep) + 2
        return (0..<count).map { 0.5 * (1 + erf((-phiLimit + Double($0) * phiStep) / 2.0.squareRoot())) }
    }()

    /// The per-channel median of a set of colours.
    static func median(_ colors: [RGBA]) -> RGBA {
        guard !colors.isEmpty else { return RGBA(r: 0, g: 0, b: 0, a: 0) }
        func middle(_ values: [Double]) -> Double {
            let sorted = values.sorted()
            return sorted[sorted.count / 2]
        }
        return RGBA(r: middle(colors.map(\.r)), g: middle(colors.map(\.g)),
                    b: middle(colors.map(\.b)), a: middle(colors.map(\.a)))
    }

    /// The largest single-channel difference between two colours.
    static func apart(_ a: RGBA, _ b: RGBA) -> Double {
        max(abs(a.r - b.r), max(abs(a.g - b.g), abs(a.b - b.b)))
    }

    /// A 0…1 difference as levels out of 255, which is the unit every tolerance
    /// here is written in because it is the unit a screenshot is stored in.
    static func levels(_ value: Double) -> Double { value * 255 }
}
