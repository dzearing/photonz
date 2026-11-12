import CoreGraphics
import Foundation

extension AskMotion {

    // MARK: What a swing hangs from goes with it

    /// `steps` with every small still part that a swing turns about (the
    /// swing's pivot on it, the two touching at rest) given the swing's own
    /// turn about the same point, so the two move as one piece. The bell of
    /// 2026-11-11 (run 20261111-200328) was drawn as a body and a short bar
    /// on top it hung from; the body swung 14 degrees about the bar and the
    /// bar stayed level, and nine looks of nine read it as the body shearing
    /// and warping under a fixed cap. A part is carried only when it is still
    /// (no keys of its own or of a group it is in), the pivot is on it, it
    /// meets the swinging part, its longest side is at most half the
    /// swinging part's, and one swing alone claims it. Boxes, pivots and keys
    /// only: nothing knows what the parts are.
    public static func carried(_ steps: [AskStep]) -> [AskStep] {
        guard let index = steps.firstIndex(where: { $0.tool == "add_drawing" }),
              let svg = steps[index].arguments["svg"]?.stringValue,
              case .success(let art) = SVGArtwork.parse(svg, keepingGroups: true) else { return steps }
        let keyed = steps.filter { $0.tool == "set_keys" }
        let keyedNames = Set(keyed.compactMap { ($0.arguments["layer"]?.stringValue).flatMap(partReference).map { plain($0.part) } })
        func box(_ part: SVGArtwork.Part) -> CGRect {
            SVGArtwork.shapeBounds(part.shape).insetBy(dx: -part.strokeWidth / 2, dy: -part.strokeWidth / 2)
        }
        // Still parts by name: neither they nor any group they are in is keyed.
        var still: [(name: String, box: CGRect)] = []
        for part in art.parts {
            guard let name = part.name, !keyedNames.contains(plain(name)),
                  !part.groups.contains(where: { keyedNames.contains(plain($0)) }),
                  !still.contains(where: { plain($0.name) == plain(name) }) else { continue }
            still.append((name, box(part)))
        }
        guard !still.isEmpty else { return steps }
        // Each swing about a point off its part's middle, with that point on the grid.
        var claims: [String: [(step: AskStep, pivot: CGPoint)]] = [:]
        for step in keyed where step.arguments["property"]?.stringValue == MotionProperty.rotation.rawValue {
            guard let reference = (step.arguments["layer"]?.stringValue).flatMap(partReference),
                  let turner = AskMotionCheck.box(of: reference.part, in: art),
                  let x = step.arguments["pivot"]?["x"]?.doubleValue, let y = step.arguments["pivot"]?["y"]?.doubleValue else { continue }
            let pivot = isFraction(x, y) ? CGPoint(x: turner.minX + turner.width * x, y: turner.minY + turner.height * y) : CGPoint(x: x, y: y)
            guard hypot(pivot.x - turner.midX, pivot.y - turner.midY) >= 1 else { continue }
            let longest = max(turner.width, turner.height)
            for part in still {
                guard part.box.insetBy(dx: -0.5, dy: -0.5).contains(pivot),
                      part.box.intersects(turner.insetBy(dx: -0.5, dy: -0.5)),
                      max(part.box.width, part.box.height) <= longest / 2 else { continue }
                claims[part.name, default: []].append((step, pivot))
            }
        }
        var out = steps
        for part in still {
            guard let claim = claims[part.name], claim.count == 1, let one = claim.first,
                  let reference = (one.step.arguments["layer"]?.stringValue).flatMap(partReference),
                  var object = one.step.arguments.objectValue else { continue }
            // Written on the grid, never as fractions of the part (a pivot in
            // 0...1 both ways would be read as fractions of the small part).
            guard !isFraction(Double(one.pivot.x), Double(one.pivot.y)) else { continue }
            object["layer"] = .string("$\(reference.step)/\(part.name)")
            object["pivot"] = ["x": .number(rounded(one.pivot.x)), "y": .number(rounded(one.pivot.y))]
            object["replace"] = nil
            guard let at = out.firstIndex(of: one.step) else { continue }
            out.insert(AskStep(tool: "set_keys", arguments: .object(object)), at: at + 1)
        }
        return out
    }
}
