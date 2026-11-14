import CoreGraphics
import Foundation

extension AskMotion {

    // MARK: What drops into an open container goes behind its front

    /// How far a container's line sags from the line across its mouth, at
    /// least, as a share of that mouth: a U, not a shallow bend.
    static let vesselDepth: CGFloat = 0.4
    /// How wide its mouth is, at least, as a share of its longer side.
    static let vesselMouth: CGFloat = 0.5

    /// The inside of an open line that holds things (a can, a cup or a bag
    /// drawn as a U): the convex outline round `points`, closed across the
    /// mouth from `first` to `last`. nil for a plain line, a shallow bend,
    /// or a line whose ends nearly meet (that is a closed shape left open).
    static func vesselRegion(of first: CGPoint, _ last: CGPoint, points: [CGPoint]) -> [CGPoint]? {
        guard points.count >= 3 else { return nil }
        let xs = points.map(\.x), ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return nil }
        let mouth = hypot(last.x - first.x, last.y - first.y)
        guard mouth > 0, mouth >= vesselMouth * max(maxX - minX, maxY - minY) else { return nil }
        // The deepest point off the line across the mouth.
        let (ax, ay) = (last.x - first.x, last.y - first.y)
        let deepest = points.map { (point: CGPoint) -> CGFloat in
            let cross: CGFloat = ax * (point.y - first.y) - ay * (point.x - first.x)
            return abs(cross) / mouth
        }.max() ?? 0
        guard deepest >= vesselDepth * mouth else { return nil }
        let outline = hull(points)
        return outline.count > 2 ? outline : nil
    }

    /// `steps` with a part that is thrown, dropped or put into a container
    /// drawn as an open line drawn behind that container, which gets a
    /// closed white inside, without a line of its own, just under its
    /// outline. Seen from the front, what goes into a bin goes behind the
    /// bin. On pass seventeen's reel (2026-11-13) the user's trash went into
    /// the can and faded there drawn over the can's ribs, a dark blob stuck
    /// to the front of the can: an open outline is a line to the app, with no
    /// inside to hide anything.
    ///
    /// Only a part keyed to move, drawn over the container or already behind
    /// it (then only the inside is added), last seen with
    /// its middle inside the container's outline and seen outside it before;
    /// never when anything else drawn before the container lies in its
    /// mouth (the white would bury it) or the move would change the groups
    /// the part sits in. Its paint is left as it is: a line added round solid
    /// ink here, after every contact was placed, would make it a unit wider
    /// and put it through the lid it was placed against.
    /// Ink, order and keys only: nothing here knows what anything is.
    static func dropsBehind(_ steps: [AskStep]) -> [AskStep] {
        guard let index = steps.firstIndex(where: { $0.tool == "add_drawing" }),
              var svg = steps[index].arguments["svg"]?.stringValue,
              var object = steps[index].arguments.objectValue,
              let lapEnd = steps.last(where: { $0.tool == "set_timing" })?.arguments["seconds"]?.doubleValue
                ?? steps.filter({ $0.tool == "set_keys" }).flatMap({ AskMotionCheck.timed($0).map(\.seconds) }).max(),
              lapEnd > 0 else { return steps }
        func layer(_ step: AskStep) -> String? { (step.arguments["layer"]?.stringValue).flatMap(partReference)?.part }
        let travelling = steps.filter { $0.tool == "set_keys" && $0.arguments["property"]?.stringValue == MotionProperty.position.rawValue }
            .compactMap(layer)
        var names: [String] = []
        for name in travelling where !names.contains(where: { plain($0) == plain(name) }) { names.append(name) }
        var changed = false
        for name in names {
            guard let lap = Lap(steps.replacingDrawing(at: index, with: svg)), lap.isMover(name), lap.carriers(of: name).isEmpty else { continue }
            let art = lap.art
            let own = art.parts.indices.filter { Lap.holds(art.parts[$0], name) }
            guard let first = own.first else { continue }
            // Where it is each moment it can be seen.
            var middles: [(seconds: Double, middle: CGPoint)] = []
            // Where it lands: the last moment it is seen before it goes out
            // of sight, or where it is at the end when it never does.
            var landed: CGPoint?
            var wasSeen = false
            var moment = 0.0
            while moment <= lapEnd + 0.0005 {
                let seen = lap.placed(name, at: moment)?.seen ?? false
                if wasSeen, !seen, let previous = middles.last { landed = previous.middle }
                wasSeen = seen
                if seen {
                    let points = lap.ink(name, at: moment).flatMap { $0 }
                    if !points.isEmpty {
                        middles.append((moment, CGPoint(x: points.map(\.x).reduce(0, +) / CGFloat(points.count),
                                                        y: points.map(\.y).reduce(0, +) / CGFloat(points.count))))
                    }
                }
                moment += 0.01
            }
            guard let lastSeen = landed ?? middles.last?.middle else { continue }
            // The smallest still open line it ends up in, drawn under it.
            let vessels = art.parts.indices.compactMap { at -> (at: Int, region: [CGPoint])? in
                let part = art.parts[at]
                guard !own.contains(at), part.name != nil, part.fill == nil, part.stroke != nil,
                      !lap.isMover(part.name ?? ""), !part.groups.contains(where: { lap.isMover($0) }),
                      case .path(let outline) = part.shape, !outline.closed, outline.rings.count == 1,
                      let ring = outline.rings.first, let start = ring.first?.point, let end = ring.last?.point else { return nil }
                let points = ring.flatMap { anchor in
                    [anchor.point] + [anchor.handleIn, anchor.handleOut].compactMap { handle in
                        handle.map { CGPoint(x: anchor.point.x + $0.x, y: anchor.point.y + $0.y) }
                    }
                }
                guard let region = vesselRegion(of: start, end, points: points),
                      inside(lastSeen, region),
                      middles.contains(where: { !inside($0.middle, region) }) else { return nil }
                return (at, region)
            }
            guard let vessel = vessels.min(by: { area(of: $0.region) < area(of: $1.region) }),
                  let vesselName = art.parts[vessel.at].name else { continue }
            let groupsBefore = own.map { art.parts[$0].groups }
            let places = [vesselName] + art.parts[vessel.at].groups.reversed().filter { group in !own.contains { Lap.holds(art.parts[$0], group) } }
            // Drawn behind the container already (pass nineteen's walk, the
            // model drew the trash first): it stays, and only the inside is
            // added. The can's open outline hid nothing, and the scrap sat
            // on the shut can's front as it faded.
            let behind = own.allSatisfy { $0 < vessel.at }
            let moved = behind ? svg : places.lazy.compactMap { place -> String? in
                guard let text = svgMoving(plain(name), before: plain(place), in: svg),
                      case .success(let after) = SVGArtwork.parse(text, keepingGroups: true),
                      after.parts.filter({ Lap.holds($0, name) }).map(\.groups) == groupsBefore else { return nil }
                return text
            }.first
            guard let moved, let made = insideAdded(under: plain(vesselName), in: moved),
                  case .success(let after) = SVGArtwork.parse(made, keepingGroups: true),
                  let cover = after.parts.firstIndex(where: { $0.name.map(plain) == plain(vesselName) + "inside" }) else { continue }
            // Nothing else drawn under the white may lie in the mouth.
            let mouth = boundingBox(vessel.region).insetBy(dx: 0.25, dy: 0.25)
            let buried = after.parts.indices.contains { at in
                at < cover && !Lap.holds(after.parts[at], name)
                    && SVGArtwork.shapeBounds(after.parts[at].shape).insetBy(dx: -after.parts[at].strokeWidth / 2, dy: -after.parts[at].strokeWidth / 2)
                        .intersects(mouth)
            }
            guard !buried else { continue }
            svg = made
            changed = true
        }
        guard changed else { return steps }
        object["svg"] = .string(svg)
        var out = steps
        out[index] = AskStep(tool: steps[index].tool, arguments: .object(object))
        return out
    }

    /// `svg` with a copy of the path called `name` put just before it,
    /// closed, filled white and drawing no line, its id ending "-inside";
    /// nil when there is no such path or it says no `d`.
    static func insideAdded(under name: String, in svg: String) -> String? {
        guard let range = elementRange(name, in: svg) else { return nil }
        let element = String(svg[range])
        guard element.hasPrefix("<path"),
              let idRange = element.range(of: #"\bid="([^"]*)""#, options: .regularExpression),
              let dRange = element.range(of: #"\bd="([^"]*)""#, options: .regularExpression) else { return nil }
        let id = String(element[idRange].dropFirst(4).dropLast()) + "-inside"
        guard !svg.contains("id=\"\(id)\"") else { return nil }
        let d = String(element[dRange].dropFirst(3).dropLast())
        let copy = paint([("id", id), ("d", d + " Z"), ("fill", "#FFFFFF"), ("stroke", "none")], onElement: element)
        var text = svg
        text.insert(contentsOf: copy, at: range.lowerBound)
        return text
    }

    private static func area(of outline: [CGPoint]) -> CGFloat {
        guard outline.count > 2 else { return 0 }
        var twice: CGFloat = 0
        for (a, b) in zip(outline, outline.dropFirst() + [outline[0]]) { twice += a.x * b.y - b.x * a.y }
        return abs(twice) / 2
    }

    private static func boundingBox(_ points: [CGPoint]) -> CGRect {
        let xs = points.map(\.x), ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return .null }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

private extension Array where Element == AskStep {
    /// The steps with the drawing at `index` saying `svg`.
    func replacingDrawing(at index: Int, with svg: String) -> [AskStep] {
        guard var object = self[index].arguments.objectValue else { return self }
        object["svg"] = .string(svg)
        var out = self
        out[index] = AskStep(tool: self[index].tool, arguments: .object(object))
        return out
    }
}
