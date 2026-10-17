import CoreGraphics
import Foundation

/// One part of a placed title as the timeline draws it: a bar from where its in
/// starts to where its out ends, with the in and the out inside it (task
/// `a-title-page-s-parts-each-have-their-own-labelle`).
///
/// Read off the design AS COMPILED, energy and all, and clamped the way the
/// compiler clamps (an in lives in the title's front half, an out in its back
/// half, `TitleCompiler.motions`), so a bar is where the part really is on
/// screen. Times count from the title's first frame; `titleInMS` places them
/// on the document.
public struct TitlePartTiming: Hashable, Sendable {
    /// Where the part is in its title's design.
    public var index: Int
    /// What the Title section's Part menu calls it: Headline, Subtitle, and a
    /// number after a second of the same kind.
    public var name: String
    public var role: TitlePartRole
    /// The piece of the title's group the part moves.
    public var pieceID: UUID
    /// Where the title starts on the document.
    public var titleInMS: Int
    public var inStartMS: Int
    public var inEndMS: Int
    public var outStartMS: Int
    public var outEndMS: Int

    /// The part's first frame on screen and its last, counted from the title's.
    public var startMS: Int { inStartMS }
    public var endMS: Int { outEndMS }

    public init(index: Int, name: String, role: TitlePartRole, pieceID: UUID, titleInMS: Int,
                inStartMS: Int, inEndMS: Int, outStartMS: Int, outEndMS: Int) {
        self.index = index
        self.name = name
        self.role = role
        self.pieceID = pieceID
        self.titleInMS = titleInMS
        self.inStartMS = inStartMS
        self.inEndMS = inEndMS
        self.outStartMS = outStartMS
        self.outEndMS = outEndMS
    }

    /// The name a part goes by wherever a person reads it.
    public static func name(of role: TitlePartRole) -> String {
        switch role {
        case .background: "Background"
        case .headline: "Headline"
        case .subtitle: "Subtitle"
        case .kicker: "Kicker"
        case .accent: "Accent"
        }
    }

    /// `ms`, or the nearest of `moments` within `withinMS` of it: what an end
    /// being dragged catches on (the playhead, the other parts' ends, markers).
    public static func snapped(_ ms: Int, to moments: [Int], withinMS: Int) -> Int {
        guard let nearest = moments.min(by: { abs($0 - ms) < abs($1 - ms) }),
              abs(nearest - ms) <= withinMS else { return ms }
        return nearest
    }
}

/// Which part of a part's bar the hand took.
public enum TitlePartGrab: String, CaseIterable, Hashable, Codable, Sendable {
    /// Its left end: when it starts coming in.
    case start
    /// Its right end: when it has finished going.
    case end
    /// The bar itself: the part slides, its in and out keeping their lengths.
    case body
}

extension TitleRecipe {

    /// Where part `index`'s in and out fall in a title `lengthMS` long, as
    /// compiled.
    func compiledSpan(of index: Int, lengthMS: Int) -> (inStart: Int, inEnd: Int, outStart: Int, outEnd: Int)? {
        let parts = compiled.parts
        guard parts.indices.contains(index) else { return nil }
        return Self.span(of: parts[index], lengthMS: lengthMS)
    }

    /// The compiler's own clamps (`TitleCompiler.motions`).
    static func span(of part: TitlePart, lengthMS: Int) -> (inStart: Int, inEnd: Int, outStart: Int, outEnd: Int) {
        let half = lengthMS / 2
        var inStart = 0, inEnd = 0, outStart = lengthMS, outEnd = lengthMS
        if let build = part.in {
            inStart = min(build.delayMS, half)
            inEnd = min(build.delayMS + build.lengthMS, half)
        }
        if let build = part.out {
            outEnd = max(lengthMS - build.delayMS, half)
            outStart = max(lengthMS - build.delayMS - build.lengthMS, half)
        }
        return (inStart, inEnd, outStart, outEnd)
    }

    /// The recipe with part `index` retimed by a hand that took `grab` and
    /// moved `byMS` along the title's compiled clock. A part with no in (or no
    /// out) is given a cut where its end lands, so a part that simply sat
    /// there from the start can be made to arrive later. Nil when nothing
    /// would change.
    func retimingPart(_ index: Int, _ grab: TitlePartGrab, byMS: Int, lengthMS: Int) -> TitleRecipe? {
        guard design.parts.indices.contains(index), byMS != 0, lengthMS > 2,
              let now = compiledSpan(of: index, lengthMS: lengthMS) else { return nil }
        let half = lengthMS / 2
        let pace = max(energy.pace, 0.01)
        var part = design.parts[index]
        func designMS(_ compiled: Int) -> Int { max(0, Int((Double(compiled) / pace).rounded())) }
        // Each end stays in the half of the title its build lives in, and
        // never crosses the other.
        let startRange = 0...max(0, min(half - 1, now.outStart - 1))
        let endRange = min(lengthMS, max(half + 1, now.inEnd + 1))...lengthMS
        func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int { min(max(value, range.lowerBound), range.upperBound) }
        var moveStart = 0, moveEnd = 0
        switch grab {
        case .start:
            moveStart = clamp(now.inStart + byMS, startRange) - now.inStart
        case .end:
            moveEnd = clamp(now.outEnd + byMS, endRange) - now.outEnd
        case .body:
            let low = max(startRange.lowerBound - now.inStart, endRange.lowerBound - now.outEnd)
            let high = min(startRange.upperBound - now.inStart, endRange.upperBound - now.outEnd)
            guard low <= high else { return nil }
            moveStart = min(max(byMS, low), high)
            moveEnd = moveStart
        }
        guard moveStart != 0 || moveEnd != 0 else { return nil }
        if moveStart != 0 {
            var build = part.in ?? TitleBuild(.fade, delayMS: 0, lengthMS: 1, curve: .linear)
            build.delayMS = designMS(now.inStart + moveStart)
            part.in = build
        }
        if moveEnd != 0 {
            var build = part.out ?? TitleBuild(.fade, delayMS: 0, lengthMS: 1, curve: .linear)
            build.delayMS = designMS(lengthMS - (now.outEnd + moveEnd))
            part.out = build
        }
        var recipe = self
        recipe.design.parts[index] = part
        return recipe
    }
}

extension PhotonzDocument {

    /// Every part of the placed title `layerID`, in its design's order, with
    /// the bar the timeline draws for it. Empty for anything not a title.
    public func titlePartTimings(layerID: UUID) -> [TitlePartTiming] {
        guard let title = layer(id: layerID), let time = title.time,
              let recipe = title.group?.titleRecipe else { return [] }
        let parts = recipe.compiled.parts
        var seen: [TitlePartRole: Int] = [:]
        let counts = Dictionary(parts.map { ($0.role, 1) }, uniquingKeysWith: +)
        return parts.enumerated().compactMap { index, part in
            seen[part.role, default: 0] += 1
            guard let piece = TitleDesign.find(part.path, in: title) else { return nil }
            let base = TitlePartTiming.name(of: part.role)
            let name = (counts[part.role] ?? 0) > 1 ? "\(base) \(seen[part.role] ?? 1)" : base
            let span = TitleRecipe.span(of: part, lengthMS: time.lengthMS)
            return TitlePartTiming(index: index, name: name, role: part.role, pieceID: piece.id,
                                   titleInMS: time.inMS, inStartMS: span.inStart, inEndMS: span.inEnd,
                                   outStartMS: span.outStart, outEndMS: span.outEnd)
        }
    }

    /// Retime one part of a title as its bar's end (or middle) was dragged
    /// `byMS`: the design changes and the title is compiled again, so the
    /// part's keys, reveal and Part section all follow, and a restyle later
    /// keeps the new timing. False when nothing changed.
    @discardableResult
    public mutating func retimeTitlePart(layerID: UUID, index: Int, grab: TitlePartGrab, byMS: Int) -> Bool {
        guard let time = layer(id: layerID)?.time, let recipe = titleRecipe(layerID: layerID),
              let retimed = recipe.retimingPart(index, grab, byMS: byMS, lengthMS: time.lengthMS)
        else { return false }
        return restyleTitle(layerID: layerID) { $0 = retimed }
    }
}
