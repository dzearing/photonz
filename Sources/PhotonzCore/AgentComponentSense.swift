import CoreGraphics
import Foundation

// What Ask's planner sets right in a component before it is built, beyond
// what nobody could see (`madePlain`): looks that say the opposite of their
// state's name, and words off the sheet's one type scale. A small model on
// this Mac drew an Off checkbox with its tick, a blue or near black Off
// switch, a Disabled field in darker words than its Default, and eight type
// sizes on one sheet (judges of the eval, 2026-10-24). An agent that reads
// refusals is given none of this: it is what a person would fix by hand on
// any component, whatever it is, and nothing here knows which components
// exist or how they should look.

extension AgentNewComponent {
    /// The type scale words on a planned component are set to: the
    /// system's body, title 3 and headline sizes on the Mac. With the
    /// sheet's own 13 point names and the title, a sheet has at most four
    /// sizes (the eval's rule; judges read more as no type scale).
    static let typeScale: [Double] = [13, 15, 17]

    /// `size` on the type scale: the nearest step, a half step rounding down.
    static func onTheScale(_ size: Double) -> Double {
        typeScale.min { abs($0 - size) + ($0 > size ? 0.01 : 0) < abs($1 - size) + ($1 > size ? 0.01 : 0) } ?? size
    }

    /// State names that say the control is off, and that it is on.
    static let offNames: Set<String> = ["off", "unchecked", "unselected", "deselected"]
    static let onNames: Set<String> = ["on", "checked", "selected"]
    /// The light grey an off switch's track is on the Mac.
    static let offTrack = "#E9E9EA"
    /// A fill whose channels spread this far apart is a colour, not a grey.
    static let saturatedSpread = 0.35
    /// A fill darker than this, as light, reads as filled in.
    static let darkLuminance = 0.08

    static func stateWords(_ name: String) -> [String] {
        name.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
    }

    /// The arguments with their words' sizes on the type scale, every part
    /// and every look's change.
    static func onTypeScale(_ args: [String: AgentJSON]) -> [String: AgentJSON] {
        func scaled(_ json: AgentJSON) -> AgentJSON {
            guard var object = json.objectValue, let size = object["fontSize"]?.doubleValue else { return json }
            object["fontSize"] = .number(onTheScale(size))
            return .object(object)
        }
        var out = args
        if let parts = out["parts"]?.arrayValue { out["parts"] = .array(parts.map(scaled)) }
        if let looks = out["looks"]?.arrayValue {
            out["looks"] = .array(looks.map { look in
                guard var object = look.objectValue, let changes = object["changes"]?.arrayValue else { return look }
                object["changes"] = .array(changes.map(scaled))
                return .object(object)
            })
        }
        return out
    }

    /// Sets `key` to `value` on `part` in a look's changes, adding the
    /// change when the look has none for that part.
    static func setting(_ key: String, _ value: AgentJSON, on part: String, in look: AgentJSON) -> AgentJSON {
        guard var object = look.objectValue else { return look }
        var changes = object["changes"]?.arrayValue ?? []
        if let at = changes.firstIndex(where: { ($0["part"]?.stringValue ?? "").trimmingCharacters(in: .whitespaces) == part }),
           var change = changes[at].objectValue {
            change[key] = value
            changes[at] = .object(change)
        } else {
            changes.append(["part": .string(part), key: value])
        }
        object["changes"] = .array(changes)
        return .object(object)
    }

    /// An Off look that reads as on, set right: a mark (an open stroked
    /// path, a tick) that shows in both Off and On is hidden in Off, and an
    /// Off whose biggest box is filled with a colour or near black is given
    /// the off grey, the On looks keeping the colour it had.
    static func offLooksOff(_ args: [String: AgentJSON], _ found: AgentNewComponent) -> [String: AgentJSON] {
        let names = found.looks.map { $0.name.trimmingCharacters(in: .whitespaces).lowercased() }
        guard let off = names.firstIndex(where: offNames.contains),
              let on = names.firstIndex(where: onNames.contains) else { return args }
        // Every look that is a kind of on: On, On Disabled, Checked Hover.
        let onLooks = names.indices.filter { index in
            index != off && !stateWords(names[index]).filter(onNames.contains).isEmpty
        }
        let offShown = found.inLook(found.looks[off]), onShown = found.inLook(found.looks[on])
        var out = args
        var looks = out["looks"]?.arrayValue ?? []
        func change(_ look: Int, _ key: String, _ value: AgentJSON, _ part: String) {
            guard look > 0, look - 1 < looks.count else { return }
            looks[look - 1] = setting(key, value, on: part, in: looks[look - 1])
        }
        func setPart(_ part: String, _ key: String, _ value: AgentJSON) {
            guard var parts = out["parts"]?.arrayValue,
                  let at = parts.firstIndex(where: { ($0["name"]?.stringValue ?? "").trimmingCharacters(in: .whitespaces) == part }),
                  var object = parts[at].objectValue else { return }
            object[key] = value
            parts[at] = .object(object)
            out["parts"] = .array(parts)
        }

        for (index, part) in offShown.parts.enumerated() where part.kind == .path && !part.closed && !part.hidden
            && !onShown.parts[index].hidden {
            if off == 0 {
                setPart(part.name, "visible", false)
                for look in onLooks { change(look, "visible", true, part.name) }
            } else {
                change(off, "visible", false, part.name)
            }
        }

        // The track is the biggest filled box, a closed path as much as a
        // rectangle; a bigger box with no fill (a hit area round it) is
        // nothing anyone sees (the eval, 2026-10-24: a blue Off toggle got
        // past a check that only looked at the biggest rectangle).
        let boxes = offShown.parts.enumerated().filter { _, part in
            guard !part.hidden, part.look.fill?.hexValue != nil, (part.look.opacity ?? 1) > 0 else { return false }
            switch part.kind {
            case .shape: return true
            case .path: return part.closed
            case .text: return false
            }
        }
        if let (index, track) = boxes.max(by: { $0.1.frame.width * $0.1.frame.height < $1.1.frame.width * $1.1.frame.height }),
           let fill = track.look.fill?.hexValue, let colour = RGBA(hex: fill) {
            let spread = max(colour.r, colour.g, colour.b) - min(colour.r, colour.g, colour.b)
            if spread >= saturatedSpread || colour.linearLuminance < darkLuminance {
                if off == 0 {
                    setPart(track.name, "fill", .string(offTrack))
                    for look in onLooks where found.parts[index].look.fill?.hexValue == found.inLook(found.looks[look]).parts[index].look.fill?.hexValue {
                        change(look, "fill", .string(fill), track.name)
                    }
                } else {
                    change(off, "fill", .string(offTrack), track.name)
                }
            }
        }
        if !looks.isEmpty { out["looks"] = .array(looks) }
        return out
    }

    /// The room a box keeps round what it holds, when nothing it holds
    /// says otherwise, and the least and most it is taken as.
    static let heldRoom: ClosedRange<CGFloat> = 8...24

    /// Boxes and drawn shapes that hang past the edge of the box they mostly
    /// sit in (an alert's buttons under its card) have that box grown to
    /// hold them, keeping on that side the least room it leaves round what
    /// it holds on any other. Words are left to `wordsHalfOn`.
    static func heldInside(_ args: [String: AgentJSON], _ found: AgentNewComponent) -> [String: AgentJSON] {
        func area(_ rect: CGRect) -> CGFloat { rect.isNull ? 0 : rect.width * rect.height }
        let drawn = found.parts.filter { part in
            guard !part.hidden else { return false }
            switch part.kind {
            case .shape: return part.frame.width > 0 && part.frame.height > 0
            case .path: return part.closed
            case .text: return false
            }
        }
        guard let outer = drawn.filter({ if case .shape = $0.kind { true } else { false } })
            .max(by: { area($0.frame) < area($1.frame) }) else { return args }
        let inside = drawn.filter { part in
            part.name != outer.name && area(part.frame) * 2 <= area(outer.frame)
                && area(part.frame.intersection(outer.frame)) >= area(part.frame) / 2
        }
        let crossing = inside.filter { !outer.frame.insetBy(dx: -1, dy: -1).contains($0.frame) }
        guard !crossing.isEmpty else { return args }
        // The room left on every side a held part does not cross.
        let insets = inside.flatMap { part in
            [part.frame.minX - outer.frame.minX, part.frame.minY - outer.frame.minY,
             outer.frame.maxX - part.frame.maxX, outer.frame.maxY - part.frame.maxY].filter { $0 >= 0 }
        }
        let room = min(max(insets.min() ?? 16, heldRoom.lowerBound), heldRoom.upperBound)
        let reach = crossing.map(\.frame).reduce(outer.frame) { $0.union($1) }
        var grown = outer.frame
        if reach.minX < outer.frame.minX - 1 { grown.size.width += grown.minX - (reach.minX - room); grown.origin.x = reach.minX - room }
        if reach.minY < outer.frame.minY - 1 { grown.size.height += grown.minY - (reach.minY - room); grown.origin.y = reach.minY - room }
        if reach.maxX > outer.frame.maxX + 1 { grown.size.width = reach.maxX + room - grown.minX }
        if reach.maxY > outer.frame.maxY + 1 { grown.size.height = reach.maxY + room - grown.minY }
        guard var parts = args["parts"]?.arrayValue,
              let at = parts.firstIndex(where: { ($0["name"]?.stringValue ?? "").trimmingCharacters(in: .whitespaces) == outer.name }),
              var object = parts[at].objectValue else { return args }
        object["x"] = .number(Double(grown.minX))
        object["y"] = .number(Double(grown.minY))
        object["width"] = .number(Double(grown.width))
        object["height"] = .number(Double(grown.height))
        parts[at] = .object(object)
        var out = args
        out["parts"] = .array(parts)
        return out
    }

    /// How much more a Disabled look's words may stand out than the first
    /// look's before they are dimmed.
    static let disabledLeeway = 5.0
    /// How far a dimmed word is set from what is behind it towards the first
    /// look's colour, tried in turn until it reads.
    static let dimmings = [0.45, 0.6, 0.75, 0.9]

    /// A Disabled look whose words stand out more than the first look's
    /// (a disabled field in black over a default in grey) has them set
    /// between what is behind them and the first look's colour, as faint as
    /// still reads.
    static func disabledLooksDisabled(_ args: [String: AgentJSON], _ found: AgentNewComponent) -> [String: AgentJSON] {
        var out = args
        guard var looks = out["looks"]?.arrayValue else { return args }
        for (index, look) in found.looks.enumerated().dropFirst()
        where index - 1 < looks.count && stateWords(look.name).contains("disabled") {
            let shown = found.inLook(look)
            for (at, part) in shown.parts.enumerated() where part.kind == .text && !part.hidden {
                let first = found.parts[at]
                guard case .some(.some(let was)) = found.wordsBackdrop(first),
                      case .some(.some(let now)) = shown.wordsBackdrop(part),
                      let groundWas = RGBA(hex: was.colour), let ground = RGBA(hex: now.colour),
                      let inkWas = RGBA(hex: first.colorHex ?? defaultWordColour),
                      let ink = RGBA(hex: part.colorHex ?? defaultWordColour) else { continue }
                let before = abs(RGBA.lightnessContrast(text: inkWas, on: groundWas))
                guard abs(RGBA.lightnessContrast(text: ink, on: ground)) > before + disabledLeeway else { continue }
                for t in dimmings {
                    let dim = RGBA(r: ground.r + (inkWas.r - ground.r) * t, g: ground.g + (inkWas.g - ground.g) * t,
                                   b: ground.b + (inkWas.b - ground.b) * t)
                    let reads = abs(RGBA.lightnessContrast(text: dim, on: ground))
                    if reads >= leastWordLightness + disabledLeeway, reads <= before {
                        looks[index - 1] = setting("color", .string(dim.hexString), on: part.name, in: looks[index - 1])
                        break
                    }
                }
            }
        }
        out["looks"] = .array(looks)
        return out
    }

    /// The arguments with each of these set right, every one kept only when
    /// the call it leaves could still be built.
    static func madeSensible(_ args: [String: AgentJSON]) -> [String: AgentJSON] {
        func built(_ args: [String: AgentJSON]) -> AgentNewComponent? {
            if case .success(let found) = AgentTools.componentSpec("add_component", args) { return found }
            return nil
        }
        var out = args
        for step in [{ (args: [String: AgentJSON]) in onTypeScale(args) },
                     { args in built(args).map { heldInside(args, $0) } ?? args },
                     { args in built(args).map { offLooksOff(args, $0) } ?? args },
                     { args in built(args).map { disabledLooksDisabled(args, $0) } ?? args }] {
            let before = built(out)?.problem
            let next = step(out)
            guard let after = built(next) else { continue }
            if after.problem == nil || before != nil { out = next }
        }
        return out
    }
}
