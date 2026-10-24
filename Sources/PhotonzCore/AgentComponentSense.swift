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

    /// First looks that are the resting look, and the looks beside which
    /// that resting look is Off: a checkbox's Default beside Checked is its
    /// unchecked look, while a tab's Default beside Selected is not.
    static let restNames: Set<String> = ["default", "normal", "rest", "resting"]
    static let checkedNames: Set<String> = ["on", "checked"]

    /// The look that is Off: one named so, else a first look named as the
    /// resting look when another is named Checked or On.
    static func offLook(_ names: [String]) -> Int? {
        if let off = names.firstIndex(where: offNames.contains) { return off }
        guard let first = names.first, restNames.contains(first),
              names.dropFirst().contains(where: checkedNames.contains) else { return nil }
        return 0
    }

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
        guard let off = offLook(names), let on = names.firstIndex(where: onNames.contains) else { return args }
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
        // A box given no paint at all is drawn in the default fill.
        func painted(_ part: AgentComponentPart) -> String? {
            part.look.fill?.hexValue ?? (part.look.fill == nil && part.look.stroke == nil ? AgentDrawing.defaultFillHex : nil)
        }
        let boxes = offShown.parts.enumerated().filter { _, part in
            guard !part.hidden, painted(part) != nil, (part.look.opacity ?? 1) > 0 else { return false }
            switch part.kind {
            case .shape: return true
            case .path: return part.closed
            case .text: return false
            }
        }
        if let (index, track) = boxes.max(by: { $0.1.frame.width * $0.1.frame.height < $1.1.frame.width * $1.1.frame.height }),
           let fill = painted(track), let colour = RGBA(hex: fill) {
            let spread = max(colour.r, colour.g, colour.b) - min(colour.r, colour.g, colour.b)
            if spread >= saturatedSpread || colour.linearLuminance < darkLuminance {
                if off == 0 {
                    setPart(track.name, "fill", .string(offTrack))
                    for look in onLooks where painted(found.parts[index]) == painted(found.inLook(found.looks[look]).parts[index]) {
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

    /// An On look that reads as Off, set right: a mark held still inside
    /// the control's box in both looks (a radio's dot, a switch's knob) is
    /// hidden in Off when the box is round or square, and moved to the far
    /// end in On when the box is a long pill, as a person would on any such
    /// control. A mark that moves or hides between the two is left as drawn.
    static func onIsNotOff(_ args: [String: AgentJSON], _ found: AgentNewComponent) -> [String: AgentJSON] {
        let names = found.looks.map { $0.name.trimmingCharacters(in: .whitespaces).lowercased() }
        guard let off = offLook(names), let on = names.firstIndex(where: onNames.contains) else { return args }
        let onLooks = names.indices.filter { index in
            index != off && !stateWords(names[index]).filter(onNames.contains).isEmpty
        }
        let offShown = found.inLook(found.looks[off]), onShown = found.inLook(found.looks[on])
        func area(_ rect: CGRect) -> CGFloat { rect.width * rect.height }
        let shapes = offShown.parts.indices.filter { index in
            if case .shape = offShown.parts[index].kind { return !offShown.parts[index].hidden } else { return false }
        }
        guard let box = shapes.max(by: { area(offShown.parts[$0].frame) < area(offShown.parts[$1].frame) }) else { return args }
        let frame = offShown.parts[box].frame
        guard frame.width > 0, frame.height > 0 else { return args }
        let marks = shapes.filter { index in
            let mark = offShown.parts[index]
            return index != box && area(mark.frame) * 2 <= area(frame) && frame.insetBy(dx: -1, dy: -1).contains(mark.frame)
                && !onShown.parts[index].hidden && onShown.parts[index].frame == mark.frame
                && mark.look.fill?.hexValue != nil
        }
        var out = args
        var looks = out["looks"]?.arrayValue ?? []
        for index in marks {
            let mark = offShown.parts[index]
            if frame.width <= frame.height * 1.3 {
                if off == 0 {
                    guard var parts = out["parts"]?.arrayValue,
                          let at = parts.firstIndex(where: { ($0["name"]?.stringValue ?? "").trimmingCharacters(in: .whitespaces) == mark.name }),
                          var object = parts[at].objectValue else { continue }
                    object["visible"] = false
                    parts[at] = .object(object)
                    out["parts"] = .array(parts)
                    for look in onLooks where look > 0 && look - 1 < looks.count {
                        looks[look - 1] = setting("visible", true, on: mark.name, in: looks[look - 1])
                    }
                } else if off - 1 < looks.count {
                    looks[off - 1] = setting("visible", false, on: mark.name, in: looks[off - 1])
                }
            } else if frame.width >= frame.height * 1.5 {
                let across = frame.maxX - (mark.frame.minX - frame.minX) - mark.frame.width
                guard abs(across - mark.frame.minX) > 2 else { continue }
                for look in onLooks where look > 0 && look - 1 < looks.count
                    && found.inLook(found.looks[look]).parts[index].frame == mark.frame {
                    looks[look - 1] = setting("x", .number(Double(across)), on: mark.name, in: looks[look - 1])
                }
            }
        }
        if !looks.isEmpty { out["looks"] = .array(looks) }
        return out
    }

    /// A mark (a tick, a chevron: an open path) drawn in nearly the colour
    /// of the box it sits on is set white or near black in that look,
    /// whichever stands out more, as words that cannot be read are.
    static func marksStandOut(_ args: [String: AgentJSON], _ found: AgentNewComponent) -> [String: AgentJSON] {
        var out = args
        var looks = out["looks"]?.arrayValue ?? []
        for (lookIndex, look) in found.looks.enumerated() {
            let shown = lookIndex == 0 ? found : found.inLook(look)
            for part in shown.parts where part.kind == .path && !part.closed && !part.hidden {
                let boxes = shown.parts.filter { box in
                    guard case .shape = box.kind, !box.hidden, let _ = box.look.fill?.hexValue else { return false }
                    return box.frame.insetBy(dx: -1, dy: -1).contains(part.frame)
                }
                guard let box = boxes.min(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }),
                      let groundHex = box.look.fill?.hexValue, let ground = RGBA(hex: groundHex),
                      let ink = RGBA(hex: part.look.stroke?.hexValue ?? AgentDrawing.defaultStrokeHex),
                      abs(RGBA.lightnessContrast(text: ink, on: ground)) < leastWordLightness else { continue }
                let choices = ["#FFFFFF", "#1C1C1E"].compactMap { hex in RGBA(hex: hex).map { (hex, $0) } }
                guard let best = choices.max(by: {
                    abs(RGBA.lightnessContrast(text: $0.1, on: ground)) < abs(RGBA.lightnessContrast(text: $1.1, on: ground))
                })?.0 else { continue }
                if lookIndex == 0 {
                    guard var parts = out["parts"]?.arrayValue,
                          let at = parts.firstIndex(where: { ($0["name"]?.stringValue ?? "").trimmingCharacters(in: .whitespaces) == part.name }),
                          var object = parts[at].objectValue else { continue }
                    object["stroke"] = .string(best)
                    parts[at] = .object(object)
                    out["parts"] = .array(parts)
                } else if lookIndex - 1 < looks.count {
                    looks[lookIndex - 1] = setting("stroke", .string(best), on: part.name, in: looks[lookIndex - 1])
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

    /// A Disabled look whose surface stands further from the canvas than
    /// the first look's (a disabled field on #E5E5EA under a default on
    /// #F2F2F7) has it set halfway from the canvas to the first look's, so
    /// it reads faded rather than more active (judges, 2026-10-24).
    static func disabledFillsFaint(_ args: [String: AgentJSON], _ found: AgentNewComponent) -> [String: AgentJSON] {
        var out = args
        guard var looks = out["looks"]?.arrayValue else { return args }
        let canvas = RGBA(hex: canvasColour) ?? RGBA(r: 1, g: 1, b: 1)
        func far(_ x: RGBA) -> Double { max(abs(x.r - canvas.r), abs(x.g - canvas.g), abs(x.b - canvas.b)) }
        for (index, look) in found.looks.enumerated().dropFirst()
        where index - 1 < looks.count && stateWords(look.name).contains("disabled") {
            let shown = found.inLook(look)
            for (at, part) in shown.parts.enumerated() where part.kind != .text && !part.hidden {
                guard let was = found.parts[at].look.fill?.hexValue.flatMap(RGBA.init(hex:)),
                      let now = part.look.fill?.hexValue.flatMap(RGBA.init(hex:)),
                      was.a >= 1, now.a >= 1, far(now) > far(was) + 0.5 / 255 else { continue }
                let faint = RGBA(r: (canvas.r + was.r) / 2, g: (canvas.g + was.g) / 2, b: (canvas.b + was.b) / 2)
                looks[index - 1] = setting("fill", .string(faint.hexString), on: part.name, in: looks[index - 1])
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
        for step in [{ (args: [String: AgentJSON]) in numbersLeftOff(args) },
                     { args in onTypeScale(args) },
                     { args in built(args).map { heldInside(args, $0) } ?? args },
                     { args in built(args).map { offLooksOff(args, $0) } ?? args },
                     { args in built(args).map { onIsNotOff(args, $0) } ?? args },
                     { args in built(args).map { marksStandOut(args, $0) } ?? args },
                     { args in built(args).map { disabledFillsFaint(args, $0) } ?? args },
                     { args in built(args).map { disabledLooksDisabled(args, $0) } ?? args }] {
            let before = built(out)?.problem
            let next = step(out)
            guard let after = built(next) else { continue }
            if after.problem == nil || before != nil { out = next }
        }
        return out
    }
}

// MARK: - Looks a judge could tell apart

extension AgentNewComponent {
    /// How much two looks must differ, as the share of the component that
    /// changes times how far its colour moves (out of 100), for a person to
    /// see two states rather than one twice. A card whose Hover only grows
    /// its shadow is 0; an alert whose Hover deepens one of its buttons a
    /// shade is about 1; a button whose whole fill goes a step darker is 8
    /// or more (judges of Ask's sheets, 2026-10-24: "the hover versions of
    /// the nav bar, badge, alert and card match their defaults").
    static let leastSeenDifference = 1.5
    /// The share of a word's box its ink covers.
    static let inkShare = 0.3
    /// A move or growth this many points or more always shows.
    static let plainMove: CGFloat = 12

    /// The look's parts as drawn, with what `inLook` leaves out (opacity, an
    /// edge's width) set too.
    func drawn(_ look: AgentComponentLook) -> [AgentComponentPart] {
        var parts = inLook(look).parts
        for change in look.changes {
            guard let at = parts.firstIndex(where: { $0.name == change.part }) else { continue }
            let asked = change.change.look
            if let opacity = asked.opacity { parts[at].look.opacity = opacity }
            if let width = asked.strokeWidth { parts[at].look.strokeWidth = width }
        }
        return parts
    }

    /// How far apart two looks are to the eye (see `leastSeenDifference`):
    /// infinite when words, sizes, places or what shows change.
    func seenDifference(_ one: AgentComponentLook, _ other: AgentComponentLook) -> Double {
        let a = drawn(one), b = drawn(other)
        guard a.count == b.count else { return .infinity }
        func box(_ part: AgentComponentPart) -> CGRect {
            part.hidden ? .null : (part.kind == .text ? wordsSpot(part) ?? .null : part.frame)
        }
        let whole = zip(a, b).reduce(CGRect.null) { $0.union(box($1.0)).union(box($1.1)) }
        let area = whole.isNull ? 0 : whole.width * whole.height
        guard area > 0 else { return .infinity }
        let canvas = RGBA(hex: Self.canvasColour) ?? RGBA(r: 1, g: 1, b: 1)
        func ink(_ hex: String?) -> RGBA {
            guard let hex, let colour = RGBA(hex: hex) else { return canvas }
            return RGBA(r: colour.r * colour.a + canvas.r * (1 - colour.a), g: colour.g * colour.a + canvas.g * (1 - colour.a),
                        b: colour.b * colour.a + canvas.b * (1 - colour.a))
        }
        func far(_ x: RGBA, _ y: RGBA) -> Double { max(abs(x.r - y.r), abs(x.g - y.g), abs(x.b - y.b)) * 100 }
        var seen = 0.0
        for (p, q) in zip(a, b) {
            if p.hidden != q.hidden || p.text != q.text || p.fontSize != q.fontSize { return .infinity }
            if p.hidden { continue }
            // A part moved or grown by a quarter of itself, or by a dozen
            // points, plainly shows; less (a knob 24 to 28) counts by the
            // room it gains or loses, as far as its paint stands from the
            // canvas (judges, 2026-10-24: "slider hover looks the same").
            let across = abs(p.frame.minX - q.frame.minX) + abs(p.frame.width - q.frame.width)
            let down = abs(p.frame.minY - q.frame.minY) + abs(p.frame.height - q.frame.height)
            if across >= max(Self.plainMove, p.frame.width * 0.25) || down >= max(Self.plainMove, p.frame.height * 0.25) {
                return .infinity
            }
            let spot = box(p)
            let share = spot.isNull ? 0 : Double(spot.width * spot.height / area)
            let paint = { (part: AgentComponentPart) in
                part.kind == .text ? ink(part.colorHex ?? Self.defaultWordColour) : ink(part.look.fill?.hexValue)
            }
            if p.kind != .text {
                let gained = abs(p.frame.width * p.frame.height - q.frame.width * q.frame.height)
                    + Double(across) * Double(p.frame.height) + Double(down) * Double(p.frame.width)
                seen += Double(gained) / Double(area) * max(far(paint(p), canvas), far(paint(q), canvas))
            }
            // Opacity shows as far as the part stands from the canvas, a
            // word by its ink (a nav's Back at 70%: "looks the same").
            let faded = abs((p.look.opacity ?? 1) - (q.look.opacity ?? 1)) * far(paint(p), canvas) * share
            seen += p.kind == .text ? faded * Self.inkShare : faded
            if p.kind == .text {
                seen += far(ink(p.colorHex ?? Self.defaultWordColour), ink(q.colorHex ?? Self.defaultWordColour)) * share * Self.inkShare
            } else {
                seen += far(ink(p.look.fill?.hexValue), ink(q.look.fill?.hexValue)) * share
                let perimeter = Double(2 * (p.frame.width + p.frame.height))
                func edge(_ part: AgentComponentPart) -> Double {
                    part.look.stroke == nil ? 0 : min(perimeter * Double(part.look.strokeWidth ?? 1) / Double(area), share)
                }
                let edges = max(edge(p), edge(q))
                if edges > 0 {
                    let behind = ink(p.look.fill?.hexValue)
                    let line = { (part: AgentComponentPart) in part.look.stroke == nil ? behind : ink(part.look.stroke?.hexValue) }
                    seen += far(line(p), line(q)) * edges + abs(edge(p) - edge(q)) * far(line(q), behind)
                }
            }
        }
        return seen
    }

    /// The arguments without any later look a person could not tell from an
    /// earlier one kept: a hover that only grows a shadow, a pressed the
    /// same as hover. A component left with one look is still one row.
    static func barelyDifferentLeftOut(_ args: [String: AgentJSON], _ found: AgentNewComponent) -> [String: AgentJSON] {
        guard var looks = args["looks"]?.arrayValue, looks.count == found.looks.count - 1 else { return args }
        var kept = [found.looks[0]]
        var gone: [Int] = []
        for (index, look) in found.looks.enumerated().dropFirst() {
            if kept.contains(where: { found.seenDifference($0, look) < leastSeenDifference }) {
                gone.append(index - 1)
            } else {
                kept.append(look)
            }
        }
        guard !gone.isEmpty else { return args }
        for at in gone.reversed() { looks.remove(at: at) }
        var out = args
        out["looks"] = .array(looks)
        return out
    }

    /// A state's name without a number on its end ("Selected2" is
    /// Selected), and the arguments with every look so named; a look whose
    /// name would then repeat an earlier one is left out (judges, 2026-10-24,
    /// of a header reading "Selected2": "a typo").
    static func unnumbered(_ name: String) -> String {
        var base = Substring(name.trimmingCharacters(in: .whitespaces))
        while let last = base.last, last.isNumber { base = base.dropLast() }
        let trimmed = base.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? name : trimmed
    }

    static func numbersLeftOff(_ args: [String: AgentJSON]) -> [String: AgentJSON] {
        var out = args
        var taken: Set<String> = []
        if let first = args["firstLook"]?.stringValue {
            let name = unnumbered(first)
            out["firstLook"] = .string(name)
            taken.insert(name.lowercased())
        } else {
            taken.insert(defaultLookName.lowercased())
        }
        guard let looks = args["looks"]?.arrayValue else { return out }
        var kept: [AgentJSON] = []
        for look in looks {
            guard var object = look.objectValue, let said = object["name"]?.stringValue else { kept.append(look); continue }
            let name = unnumbered(said)
            guard taken.insert(name.lowercased()).inserted else { continue }
            object["name"] = .string(name)
            kept.append(.object(object))
        }
        out["looks"] = .array(kept)
        return out
    }
}
