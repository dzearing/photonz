import Foundation

/// The row's words: what a request did, in the person's own terms. "Drew a
/// cat", "Made the cat's ears bigger", "Resized Cat Ear", never "Drew a
/// drawing" or "Changed a layer" (the user, 2026-10-20). They come from the
/// request itself said as done, the drawing's own subject and the names of
/// the layers it changed, with the steps that landed as the fallback.
public enum AskChangeWords {

    public static let budget = 40
    public static let fallback = "Made a change"

    private struct Kind {
        let verb: String
        let one: String
        let many: String
    }

    private static func kind(_ step: AskStep) -> Kind? {
        switch step.tool {
        case "add_measurement", "mark_measurements": Kind(verb: "Added", one: "a measurement", many: "measurements")
        case "mark_misalignments": Kind(verb: "Found", one: "a misalignment", many: "misalignments")
        case "add_shape", "add_path": Kind(verb: "Drew", one: "a shape", many: "shapes")
        case "add_drawing": Kind(verb: "Drew", one: "a picture", many: "pictures")
        case "add_photo" where step.arguments["look"]?.stringValue == AgentPhotoCall.Look.painting.rawValue:
            Kind(verb: "Painted", one: "a picture", many: "pictures")
        case "add_photo": Kind(verb: "Made", one: "a photo", many: "photos")
        case "paint_stroke": Kind(verb: "Painted", one: "a stroke", many: "strokes")
        case "add_text": Kind(verb: "Added", one: "text", many: "texts")
        case "add_title": Kind(verb: "Added", one: "a title", many: "titles")
        case "place_component": Kind(verb: "Placed", one: "a component", many: "components")
        case "add_component": Kind(verb: "Made", one: "a component", many: "components")
        case "set_layer": Kind(verb: editVerb(step.arguments), one: "a layer", many: "layers")
        case "add_style": Kind(verb: "Saved", one: "a style", many: "styles")
        case "apply_style": Kind(verb: "Restyled", one: "a layer", many: "layers")
        case "set_layout": Kind(verb: "Laid out", one: "a group", many: "groups")
        case "run_command": Kind(verb: "Ran", one: "a command", many: "commands")
        case "cut": Kind(verb: "Made", one: "a cut", many: "cuts")
        case "trim": Kind(verb: "Trimmed", one: "a clip", many: "clips")
        case "move_clip": Kind(verb: "Moved", one: "a clip", many: "clips")
        case "set_transition": Kind(verb: "Added", one: "a transition", many: "transitions")
        case "apply_zooms": Kind(verb: "Added", one: "zooms", many: "zooms")
        default: nil
        }
    }

    /// Steps whose own words already say what was made: a drawing's subject,
    /// the words of a text, a count of marks.
    private static let saysWhatItMade: Set<String> = [
        "add_drawing", "add_photo", "add_text", "add_title", "add_measurement", "mark_measurements", "mark_misalignments",
    ]

    /// What one set_layer did, by which of its values it set.
    private static func editVerb(_ arguments: AgentJSON) -> String {
        var did = Set<String>()
        for key in (arguments.objectValue ?? [:]).keys {
            switch key {
            case "fill", "stroke": did.insert("Recoloured")
            case "width", "height", "fontSize": did.insert("Resized")
            case "x", "y": did.insert("Moved")
            case "name": did.insert("Renamed")
            case "visible": did.insert(arguments["visible"]?.boolValue == false ? "Hid" : "Showed")
            case "flip": did.insert("Flipped")
            case "text": did.insert("Reworded")
            case "cornerRadius": did.insert("Rounded")
            case "document", "layer": break
            default: did.insert("Changed")
            }
        }
        // Setting a whole frame to resize it carries its place along.
        if did == ["Resized", "Moved"] { return "Resized" }
        return did.count == 1 ? did.first ?? "Changed" : "Changed"
    }

    /// "Drew a cat", "Made the cat's ears bigger", "Added 8 measurements".
    /// `before` and `after` are the document either side of the request,
    /// which name the layers it changed.
    public static func sentence(_ steps: [AskStep], asked: String = "",
                                before: PhotonzDocument? = nil, after: PhotonzDocument? = nil) -> String {
        // Grouped by what each step's words say, most first, ties in the order asked.
        var groups: [(key: String, kind: Kind, steps: [AskStep])] = []
        for step in steps {
            guard let kind = kind(step) else { continue }
            let key = "\(kind.verb) \(kind.many)"
            if let index = groups.firstIndex(where: { $0.key == key }) {
                groups[index].steps.append(step)
            } else {
                groups.append((key, kind, [step]))
            }
        }
        guard !groups.isEmpty else { return done(asked) ?? fallback }
        let request = Request(asked)

        // One drawing the person described: their words for it.
        if groups.count == 1, groups[0].steps.count == 1, groups[0].steps[0].tool == "add_drawing",
           let request, request.makes, !request.object.isEmpty,
           let subject = groups[0].steps[0].arguments["subject"]?.stringValue,
           request.names(subject) {
            // Cut short where it still names what was drawn.
            // A scene keeps all of itself: "a piano" is not "a cat playing a piano".
            let named = request.namedWords(subject)
            if let said = request.fitted("Drew", cutting: true, keeping: { $0.namedWords(subject) == named }) { return said }
        }
        // The steps say it better than the request when every one names what it made.
        if !groups.allSatisfy({ $0.steps.allSatisfy { saysWhatItMade.contains($0.tool) } }),
           let said = request?.done() {
            return said
        }

        let ordered = groups.enumerated().sorted { a, b in
            (a.element.steps.count, -a.offset) > (b.element.steps.count, -b.offset)
        }.map(\.element)

        func phrase(_ group: (key: String, kind: Kind, steps: [AskStep]), room: Int, alone: Bool) -> String {
            let first = group.steps[0]
            if first.tool == "add_photo" {
                // "a photo of a dog on a beach", so the row says which kind it made.
                let photo = group.kind.one == "a photo"
                let subjects = group.steps.compactMap { step in
                    subjectPhrase(step.arguments["subject"]?.stringValue ?? "", icon: false, asked: asked)
                        .map { photo ? "a photo of \($0)" : $0 }
                }
                if subjects.count == group.steps.count, let listed = list(subjects, room: room, alone: alone) {
                    return listed
                }
                return group.steps.count > 1 ? "\(group.steps.count) \(group.kind.many)" : group.kind.one
            }
            if first.tool == "add_drawing" {
                let subjects = group.steps.compactMap { step in
                    subjectPhrase(step.arguments["subject"]?.stringValue ?? "",
                                  icon: step.arguments["icon"]?.boolValue ?? false, asked: asked)
                }
                if subjects.count == group.steps.count, let listed = list(subjects, room: room, alone: alone) {
                    return listed
                }
                return group.steps.count > 1 ? "\(group.steps.count) pictures" : group.kind.one
            }
            if ["set_layer", "apply_style", "set_layout"].contains(first.tool) {
                let names = layerNames(group.steps, before: before, after: after)
                if !names.isEmpty, let listed = list(names, room: room, alone: alone, more: false) { return listed }
                if !names.isEmpty, names.count > 1 { return "\(names.count) \(group.kind.many)" }
            }
            // One mark_misalignments or mark_measurements step marks each id it names.
            let count = group.steps.reduce(0) { n, step in
                switch step.tool {
                case "mark_misalignments": n + max(1, step.arguments["findings"]?.arrayValue?.count ?? 1)
                case "mark_measurements": n + max(1, step.arguments["marks"]?.arrayValue?.count ?? 1)
                default: n + 1
                }
            }
            if count > 1 { return "\(count) \(group.kind.many)" }
            if group.kind.one == "a title" || group.kind.one == "text",
               let words = first.arguments["text"]?.stringValue?
                   .replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces),
               !words.isEmpty {
                let lead = group.kind.one == "a title" ? "the title " : "the text "
                let space = room - lead.count - 2
                guard space >= 4 else { return group.kind.one }
                let cut = words.count > space ? String(words.prefix(space - 1)) + "\u{2026}" : words
                return "\(lead)\u{201C}\(cut)\u{201D}"
            }
            return group.kind.one
        }
        func clause(_ index: Int, room: Int) -> String {
            let group = ordered[index]
            // A second clause with the same verb leaves the verb out.
            let sameVerb = index > 0 && ordered[index - 1].kind.verb == group.kind.verb
            let verb = index == 0 ? group.kind.verb : group.kind.verb.lowercased()
            let lead = sameVerb ? "" : verb + " "
            return lead + phrase(group, room: room - lead.count, alone: ordered.count == 1)
        }

        let first = clause(0, room: budget)
        var sentence = first
        switch ordered.count {
        case 1:
            break
        case 2:
            let two = first + " and " + clause(1, room: budget - first.count - 5)
            sentence = two.count <= budget ? two : first + " and 1 more"
        default:
            let more = " and \(ordered.count - 2) more"
            let two = first + ", " + clause(1, room: budget - first.count - 2 - more.count) + more
            sentence = two.count <= budget ? two : first + " and \(ordered.count - 1) more"
        }
        return sentence.count <= budget ? sentence : String(sentence.prefix(budget - 1)) + "\u{2026}"
    }

    /// "a cat", "a cat and a dog", "a cat, a dog and a bird", or when they do
    /// not fit, "a cat and 2 more" while it is the only clause. Nil when even
    /// that does not fit.
    private static func list(_ items: [String], room: Int, alone: Bool, more: Bool = true) -> String? {
        guard let head = items.first else { return nil }
        let all = items.count == 1 ? head
            : items.dropLast().joined(separator: ", ") + " and " + (items.last ?? "")
        if all.count <= room { return all }
        if items.count == 1 { return head }
        let short = head + " and \(items.count - 1) more"
        return (alone || !more) && short.count <= room ? short : nil
    }

    /// The names of the layers the steps acted on, first named first.
    private static func layerNames(_ steps: [AskStep], before: PhotonzDocument?, after: PhotonzDocument?) -> [String] {
        var names: [String] = []
        for step in steps {
            let ids = [step.arguments["layer"]?.stringValue].compactMap { $0 }
                + (step.arguments["layers"]?.arrayValue ?? []).compactMap(\.stringValue)
            for id in ids.compactMap(UUID.init(uuidString:)) {
                guard let layer = before?.layer(id: id) ?? after?.layer(id: id) else { continue }
                let name = layer.name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty, !names.contains(name) { names.append(name) }
            }
        }
        return names
    }

    private static let determiners: Set<String> = ["a", "an", "the", "some", "this", "that", "these", "those", "your", "two", "three"]
    private static let prepositions: Set<String> = [
        "over", "on", "at", "in", "with", "of", "under", "by", "near", "beside", "behind", "above", "below",
        "against", "across", "from", "for", "and", "as", "into", "inside",
    ]

    /// A drawing's subject as a phrase: "a cat", "an owl", "mountains", "the
    /// sun over mountains" when the person said "the", "a smiley face icon".
    static func subjectPhrase(_ subject: String, icon: Bool, asked: String) -> String? {
        var words = subject.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return nil }
        if icon, !words.contains(where: { $0.lowercased().hasPrefix("icon") }) { words.append("icon") }
        let lead = words[0].lowercased()
        if determiners.contains(lead) { return words.joined(separator: " ") }
        if lead == "my" { return (["your"] + words.dropFirst()).joined(separator: " ") }
        let phrase = words.joined(separator: " ")
        // The article the person put before it, past a few describing words.
        let said = Request.words(asked).map { $0.lowercased() }
        if let at = said.indices.first(where: { said[$0] == lead }) {
            for before in said[max(0, at - 4)..<at].reversed() {
                if determiners.contains(before) { return before + " " + phrase }
                if before == "my" { return "your " + phrase }
                if prepositions.contains(before) { break }
            }
        }
        // A plural head word ("mountains", "trees over a lake") takes none.
        let head = words.prefix { !prepositions.contains($0.lowercased()) }.last?.lowercased() ?? lead
        if head.count > 3, head.hasSuffix("s"), !head.hasSuffix("ss"), !head.hasSuffix("us"), !head.hasSuffix("is") {
            return phrase
        }
        return ("aeiou".contains(lead.first ?? "x") ? "an " : "a ") + phrase
    }

    /// The request said as done, within the budget: "make the title bigger"
    /// is "Made the title bigger". Nil when it does not start with something
    /// to do, or does not fit.
    public static func done(_ asked: String) -> String? {
        Request(asked)?.done()
    }

    /// A request read as an instruction: what to do and to what.
    struct Request {
        /// The verb as done, capitalized.
        let past: String
        /// Everything after the verb, in the person's words, said back to them.
        let object: String
        /// Asks for something new to be made, rather than a change.
        let makes: Bool

        static let irregular: [String: String] = [
            "draw": "drew", "make": "made", "build": "built", "put": "put", "set": "set", "cut": "cut",
            "split": "split", "spread": "spread", "give": "gave", "take": "took", "bring": "brought", "send": "sent",
            "shrink": "shrank", "grow": "grew", "hide": "hid", "show": "showed", "write": "wrote", "keep": "kept",
            "swap": "swapped", "flip": "flipped", "trim": "trimmed", "crop": "cropped", "blur": "blurred",
            "drag": "dragged", "drop": "dropped", "thin": "thinned", "dim": "dimmed", "pin": "pinned",
            "speed": "sped", "lay": "laid", "redraw": "redrew", "remake": "remade", "rewrite": "rewrote",
            "slow": "slowed", "stop": "stopped", "fit": "fitted", "outline": "outlined",
        ]
        static let regular: Set<String> = [
            "add", "change", "move", "color", "colour", "recolor", "recolour", "resize", "rotate", "scale", "fade",
            "align", "center", "centre", "round", "remove", "delete", "rename", "replace", "fill", "darken",
            "lighten", "brighten", "sharpen", "duplicate", "copy", "mirror", "straighten", "tidy", "fix", "space",
            "line", "shift", "nudge", "raise", "lower", "stretch", "widen", "narrow", "thicken", "tint", "paint",
            "type", "label", "mark", "measure", "annotate", "highlight", "underline", "bold", "italicize",
            "increase", "decrease", "reduce", "double", "halve", "create", "design", "sketch", "render",
            "illustrate", "turn", "enlarge", "extend", "shorten", "lengthen", "soften", "smooth", "sort", "group",
            "ungroup", "arrange", "reorder", "flatten", "invert", "apply", "insert", "place", "position", "border",
            "frame", "animate", "zoom", "mute", "clean", "tweak", "adjust", "update", "convert", "restyle",
            "redo", "redesign", "recreate", "rearrange", "crossfade", "join",
            "merge", "connect", "point", "distribute", "reverse", "loop", "export", "pick", "match",
        ]
        /// Verbs that ask for something new.
        static let making: Set<String> = [
            "draw", "make", "create", "build", "sketch", "paint", "design", "add", "render", "illustrate", "give",
            "put", "place", "insert", "redraw", "remake", "recreate",
        ]
        static let leading = [
            "please", "pls", "plz", "hey", "ok", "okay", "now", "also", "and", "then", "just", "can you", "could you",
            "would you", "will you", "can u", "could u", "i want you to", "i'd like you to", "i would like you to",
            "go ahead and", "let's", "lets", "try to", "try and",
        ]
        static let trailing = ["please", "pls", "plz", "thanks", "thank you", "thx", "for me"]
        static let said: [String: String] = ["my": "your", "mine": "yours", "myself": "yourself", "me": "you"]
        /// Where a long thing-to-make can be cut short and still be a thing.
        static let cuts = [":", ",", ";", " that ", " which ", " who ", " with ", " for ", " of ", " on ", " in ",
                           " at ", " around ", " using ", " showing ", " to ", " from ", " and ", " as "]

        static func words(_ text: String) -> [String] {
            text.split(whereSeparator: \.isWhitespace).map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:\"")) }
                .filter { !$0.isEmpty }
        }

        static func past(_ verb: String) -> String? {
            if let found = irregular[verb] { return found }
            guard regular.contains(verb) else { return nil }
            if verb.hasSuffix("e") { return verb + "d" }
            if verb.hasSuffix("y"), let before = verb.dropLast().last, !"aeiou".contains(before) {
                return String(verb.dropLast()) + "ied"
            }
            return verb + "ed"
        }

        init(past: String, object: String, makes: Bool) {
            self.past = past
            self.object = object
            self.makes = makes
        }

        init?(_ asked: String) {
            var text = asked.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            func trimEnd() { while let last = text.last, ".,!?;: ".contains(last) { text.removeLast() } }
            trimEnd()
            var stripping = true
            while stripping {
                stripping = false
                for filler in Self.leading where text.lowercased().hasPrefix(filler + " ") || text.lowercased().hasPrefix(filler + ",") {
                    text = String(text.dropFirst(filler.count)).trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
                    stripping = true
                }
                for filler in Self.trailing where text.lowercased().hasSuffix(" " + filler) || text.lowercased().hasSuffix("," + filler) {
                    text = String(text.dropLast(filler.count + 1))
                    trimEnd()
                    stripping = true
                }
            }
            var words = text.split(separator: " ").map(String.init)
            guard let verb = words.first?.lowercased(), let past = Self.past(verb) else { return nil }
            words.removeFirst()
            makes = Self.making.contains(verb)
            if makes {
                // "draw me a cat" is a cat, "a picture of a cat" is a cat.
                if words.first?.lowercased() == "me" { words.removeFirst() }
                let lower = words.map { $0.lowercased() }
                if let of = lower.firstIndex(of: "of"), of > 0, of <= 4, of + 1 < lower.count,
                   ["picture", "drawing", "illustration", "image", "sketch", "painting", "svg"].contains(lower[of - 1]),
                   ["a", "an", "the", "some"].contains(lower[0]) {
                    words.removeFirst(of + 1)
                }
            }
            object = words.map { word in
                Self.said[word.lowercased()] ?? word
            }.joined(separator: " ")
            self.past = past.prefix(1).uppercased() + past.dropFirst()
        }

        /// The past verb and everything after it, cut short at a natural
        /// break when it asks for a thing and does not fit, or nil.
        func done() -> String? {
            // Only a thing to make can lose its trailing detail; "make the
            // title bigger" without "bigger" says nothing.
            let lead = object.split(separator: " ").first?.lowercased() ?? ""
            return fitted(past, cutting: makes && (["a", "an", "some"].contains(lead) || Int(lead) != nil))
        }

        /// `verb` and the object, whole when it fits, else when `cutting` the
        /// longest part before a natural break that fits and still passes `keeping`.
        func fitted(_ verb: String, cutting: Bool, keeping: (Request) -> Bool = { _ in true }) -> String? {
            let whole = object.isEmpty ? verb : verb + " " + object
            if whole.count <= AskChangeWords.budget { return whole }
            guard cutting else { return nil }
            var best: String?
            for cut in Self.cuts {
                var from = object.startIndex
                while let range = object.range(of: cut, range: from..<object.endIndex) {
                    let kept = String(object[..<range.lowerBound])
                    let said = verb + " " + kept
                    if kept.split(separator: " ").count >= 2, said.count <= AskChangeWords.budget,
                       said.count > (best?.count ?? 0),
                       keeping(Request(past: past, object: kept, makes: makes)) {
                        best = said
                    }
                    from = range.upperBound
                }
            }
            return best
        }

        /// Whether the request's words name the drawing's subject.
        func names(_ subject: String) -> Bool {
            !namedWords(subject).isEmpty
        }

        /// The words of the drawing's subject that the request's words name.
        func namedWords(_ subject: String) -> Set<String> {
            let mine = Self.words(object).map { $0.lowercased() }
            return Set(Self.words(subject).map { $0.lowercased() }.filter { $0.count >= 3 && $0 != "icon" }
                .filter { word in mine.contains { $0.hasPrefix(word) } })
        }
    }
}
