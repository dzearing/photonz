import CoreGraphics
import Foundation

/// Ask's look at a layout it made, before it hands back
/// (`docs/design/ask.md`, "Looking at a layout").
///
/// A local model plans from numbers, not a picture: it sets a heading
/// "centred" at an x that is really its left edge, stacks a price onto the line
/// under it, and leaves button words dark on a blue fill (the pricing walk,
/// 2026-10-24 and 2026-11-03). This reads the finished document and mends what
/// any person would see at a glance, for any request:
///
/// - words that do not read against what is behind them take the nearest
///   shade that does (the same rule add_component uses);
/// - a centred heading or label alone on its row that drifted a little off
///   the middle of what sits under it (its button, or the row below it) is
///   centred on it;
/// - words hanging off the box they are on are brought back onto it;
/// - words stacked onto the words above them are moved down to clear them,
///   along with the words under them, when that keeps them inside what they
///   sit on;
/// - words hanging off the canvas come back on.
///
/// What it cannot mend it owns up to in one short sentence. Only layers the
/// request made are moved or recoloured; what was there before is read, never
/// changed. Words are always legible (the user, 2026-09-30).
public enum AskLayoutCheck {

    public enum Fix: Hashable, Sendable {
        case move(layer: UUID, to: CGPoint)
        case recolour(layer: UUID, to: String)
    }

    public struct Review: Hashable, Sendable {
        public var fixes: [Fix] = []
        /// One line per thing looked at and what was done, for the trace.
        public var notes: [String] = []
        /// What could not be mended, in one short sentence; nil when nothing
        /// is left.
        public var sentence: String?
    }

    /// Said beside the change when words still sit on words.
    public static let overlapSentence = "Some words still overlap."

    /// Said beside the change when words are too big for the box they are on.
    public static let spillSentence = "Some words run off their box."

    /// The colour behind words when nothing is painted under them.
    static let canvasColour = "#FFFFFF"

    /// How far off the middle a centred line may sit before it is centred,
    /// in points: closer than this is already centred to the eye.
    static let centredWithin: CGFloat = 2
    /// A centred line a quarter of what is under it or more off its middle
    /// was put there on purpose (a heading over one column of a row).
    static let driftShare: CGFloat = 0.25
    /// Words with this share of their area on a box they are not wholly on
    /// are hanging off it; less, they only touch it.
    static let hangingShare: CGFloat = 0.3
    /// A box with this share of it under words is hanging from them, however
    /// little of the words that is.
    static let coveredShare: CGFloat = 0.5
    /// A box under this many times the width of its words, and under
    /// `chipTallShare` times their height, is a chip or a button: words brought
    /// onto it sit in its middle, not at its edge.
    static let chipShare: CGFloat = 2
    static let chipTallShare: CGFloat = 3
    /// Boxes overlapping by less than this, either way, hold words that do
    /// not touch to the eye: each box has 2 points of padding a side.
    static let touchesBeyond: CGFloat = 5
    /// How far a box moved along a line may still lap the one before it:
    /// their padding, so the words themselves sit a few points apart.
    static let sideBySideGap: CGFloat = 2
    /// Words sharing this much of the narrower one's width are in one
    /// column, stacked; less, they sit side by side.
    static let stackedShare: CGFloat = 0.5

    /// The one colour a picture is, when it is one: pixels live in the app,
    /// and a blank canvas's page is a picture (`ImageStore.flatColourHex`).
    /// Nil for a photo or anything else whose colour cannot be read as one.
    public typealias PictureColour = (ImageRef) -> String?

    /// Looks over every top-level layer `after` has that `before` did not.
    public static func review(_ after: PhotonzDocument, before: PhotonzDocument,
                              pictureColour: PictureColour = { _ in nil }) -> Review {
        let had = Set(before.layers.map(\.id))
        var layers = after.layers
        let made = Set(layers.lazy.filter { !had.contains($0.id) }.map(\.id))
        // A video's words sit over footage and time, not a white page:
        // what is behind them is not known here.
        guard !made.isEmpty, after.durationMS == nil else { return Review() }
        var review = Review()
        let canvas = CGRect(origin: .zero, size: after.canvasSize)
        func isMadeWords(_ layer: Layer) -> Bool {
            guard made.contains(layer.id), layer.isVisible, case .text = layer.content else { return false }
            return layer.transform == .identity
        }
        func moved(_ index: Int, to origin: CGPoint) {
            layers[index].frame.origin = CGPoint(x: origin.x.rounded(), y: origin.y.rounded())
        }

        // Off the canvas: back on, when it fits.
        for index in layers.indices where isMadeWords(layers[index]) {
            let frame = layers[index].frame
            guard frame.width <= canvas.width, frame.height <= canvas.height, !canvas.contains(frame) else { continue }
            let x = min(max(frame.minX, canvas.minX), canvas.maxX - frame.width)
            let y = min(max(frame.minY, canvas.minY), canvas.maxY - frame.height)
            moved(index, to: CGPoint(x: x, y: y))
            review.notes.append("brought \(layers[index].name) back onto the canvas")
        }

        // A centred line drifted off the middle of what it sits on, or of
        // the row below it when it sits on the canvas.
        for index in layers.indices where isMadeWords(layers[index]) {
            guard case .text(let content) = layers[index].content, content.alignment == .center else { continue }
            let frame = layers[index].frame
            let home = backdrop(of: index, in: layers, canvas: canvas, picture: pictureColour)
            // A line sharing its row with other words is one of a set (a
            // heading over each column, two labels on a bar), not a title
            // that drifted: pulling it to the middle would stack the set.
            let hasCompany = layers.indices.contains { other in
                other != index && isMadeWords(layers[other])
                    && layers[other].frame.minY < frame.maxY && frame.minY < layers[other].frame.maxY
                    && backdrop(of: other, in: layers, canvas: canvas, picture: pictureColour)?.id == home?.id
            }
            guard !hasCompany else { continue }
            let under: CGRect?
            if let box = home?.frame {
                under = box
            } else {
                under = layers.indices.lazy
                    .filter { made.contains(layers[$0].id) && layers[$0].isVisible && $0 != index }
                    .map { layers[$0].frame }
                    .filter { $0.minY >= frame.maxY - 1 && !$0.contains(canvas) }
                    .reduce(nil as CGRect?) { sofar, next in sofar.map { $0.union(next) } ?? next }
            }
            guard let under, frame.width < under.width else { continue }
            let off = abs(frame.midX - under.midX)
            guard off > centredWithin, off < under.width * driftShare else { continue }
            moved(index, to: CGPoint(x: under.midX - frame.width / 2, y: frame.minY))
            review.notes.append("centred \(layers[index].name) on what is under it (\(Int(off.rounded())) pt off)")
        }

        // Words hanging off the box they are on come back onto it. The colour
        // check reads the middle of the words, so without this "Popular" ran
        // off a purple pill, white on white, and nothing saw it (the pricing
        // walk, 2026-11-03).
        var spillLeft = false
        for index in layers.indices where isMadeWords(layers[index]) {
            let frame = layers[index].frame
            // The topmost filled box they touch decides: words wholly on it
            // are home, whatever it sits on in turn (a pill across a card's
            // edge).
            let box = layers[..<index].last { layer in
                guard layer.isVisible, !layer.frame.contains(canvas),
                      case .annotation(let shape) = layer.content, shape.fill != nil,
                      shape.shape == .rectangle || shape.shape == .ellipse else { return false }
                if layer.frame.contains(frame) { return true }
                let both = layer.frame.intersection(frame)
                guard !both.isNull else { return false }
                let shared = both.width * both.height
                // Most of the words on it, or it mostly under the words (a
                // pill far smaller than what was set on it).
                return shared >= frame.width * frame.height * hangingShare
                    || shared >= layer.frame.width * layer.frame.height * coveredShare
            }
            guard let box, !box.frame.contains(frame) else { continue }
            guard frame.width <= box.frame.width, frame.height <= box.frame.height else {
                spillLeft = true
                review.notes.append("\(layers[index].name) is too big for \(box.name)")
                continue
            }
            let chip = box.frame.width < frame.width * chipShare && box.frame.height < frame.height * chipTallShare
            let x = chip
                ? box.frame.midX - frame.width / 2
                : min(max(frame.minX, box.frame.minX), box.frame.maxX - frame.width)
            let y = min(max(frame.minY, box.frame.minY), box.frame.maxY - frame.height)
            moved(index, to: CGPoint(x: x, y: y))
            review.notes.append("brought \(layers[index].name) back onto \(box.name)")
        }

        // Words on words: the lower moved down to clear the upper, while it
        // stays inside what it sits on; otherwise said.
        var overlapLeft = false
        var settled = false
        var passes = 0
        while !settled, passes < 8 {
            settled = true
            passes += 1
            let words = layers.indices.filter { isMadeWords(layers[$0]) }
                .sorted { (layers[$0].frame.minY, layers[$0].frame.minX) < (layers[$1].frame.minY, layers[$1].frame.minX) }
            overlapLeft = false
            outer: for (n, lower) in words.enumerated() {
                for upper in words[..<n] {
                    let a = layers[upper].frame, b = layers[lower].frame
                    let both = a.intersection(b)
                    guard !both.isNull, both.width > touchesBeyond, both.height > touchesBeyond else { continue }
                    let home = backdrop(of: lower, in: layers, canvas: canvas, picture: pictureColour)
                    let room = home?.frame ?? canvas
                    // A line spilling out of what it sits on is not a stack
                    // to part: moving what is under it only makes it worse
                    // (the eval, 2026-11-03, a price line across three cards
                    // pushed two prices under their "per month").
                    guard room.contains(a), backdrop(of: upper, in: layers, canvas: canvas, picture: pictureColour)?.id == home?.id else { overlapLeft = true; continue }
                    // Starting past the middle of the upper words, they are
                    // on its line ("$29" and "/mo"): they move along it, not
                    // under it.
                    if b.minX > a.midX {
                        let along = CGRect(x: a.maxX - sideBySideGap, y: b.minY, width: b.width, height: b.height)
                        guard room.contains(along) else { overlapLeft = true; continue }
                        moved(lower, to: along.origin)
                        review.notes.append("moved \(layers[lower].name) along from \(layers[upper].name)")
                        settled = false
                        break outer
                    }
                    // Otherwise, sharing little of the width, they only meet
                    // at a corner and neither way is right.
                    guard both.width >= min(a.width, b.width) * stackedShare else { overlapLeft = true; continue }
                    let size: CGFloat
                    if case .text(let content) = layers[lower].content { size = content.fontSize } else { size = 16 }
                    let gap = max(4, (size * 0.25).rounded())
                    let delta = (a.maxY + gap).rounded() - b.minY
                    // The lower words and every word under them in their
                    // column, on the same box, move down together, so their
                    // order holds; nothing moves when that would leave the
                    // box or run into something else made there (a button).
                    let column = words.filter { other in
                        let f = layers[other].frame
                        return other == lower || (other != upper && f.minY >= b.minY
                            && f.intersection(b).width >= min(f.width, b.width) * stackedShare
                            && backdrop(of: other, in: layers, canvas: canvas, picture: pictureColour)?.id == home?.id)
                    }
                    let fixed = layers.indices.filter { other in
                        made.contains(layers[other].id) && layers[other].isVisible && !column.contains(other)
                            && layers[other].id != home?.id && room.contains(layers[other].frame)
                            && !isMadeWords(layers[other])
                    }.map { layers[$0].frame }
                    let fits = column.allSatisfy { other in
                        let was = layers[other].frame, now = was.offsetBy(dx: 0, dy: delta)
                        return room.contains(now) && !fixed.contains { !$0.intersects(was) && $0.intersects(now) }
                    }
                    guard fits else { overlapLeft = true; continue }
                    for other in column {
                        moved(other, to: CGPoint(x: layers[other].frame.minX, y: layers[other].frame.minY + delta))
                    }
                    review.notes.append("moved \(layers[lower].name) down off \(layers[upper].name)"
                                        + (column.count > 1 ? ", with \(column.count - 1) under it" : ""))
                    settled = false
                    break outer
                }
            }
        }
        if overlapLeft {
            review.notes.append("words still overlap")
        }
        review.sentence = overlapLeft ? overlapSentence : spillLeft ? spillSentence : nil

        // Words that cannot be read against what is behind them.
        for index in layers.indices where isMadeWords(layers[index]) {
            guard case .text(var content) = layers[index].content,
                  content.fill == nil, content.plateHex == nil, content.plateGradient == nil,
                  let ground = groundColour(of: index, in: layers, picture: pictureColour).flatMap({ RGBA(hex: $0) }),
                  let ink = RGBA(hex: content.colorHex),
                  let better = betterInk(ink, hex: content.colorHex, on: ground) else { continue }
            let was = content.colorHex
            content.colorHex = better
            layers[index].content = .text(content)
            review.notes.append("recoloured \(layers[index].name) \(was) to \(content.colorHex): it did not read on \(ground.hexString)")
        }

        for (now, then) in zip(layers, after.layers) {
            if now.frame.origin != then.frame.origin { review.fixes.append(.move(layer: now.id, to: now.frame.origin)) }
            if case .text(let new) = now.content, case .text(let old) = then.content, new.colorHex != old.colorHex {
                review.fixes.append(.recolour(layer: now.id, to: new.colorHex))
            }
        }
        return review
    }

    /// Lands the review's fixes. A recoloured line with a shadow keeps one
    /// that suits its new colour.
    public static func apply(_ review: Review, to document: inout PhotonzDocument) {
        for fix in review.fixes {
            switch fix {
            case .move(let id, let origin):
                document.updateLayer(id: id) { $0.frame.origin = origin }
            case .recolour(let id, let hex):
                document.updateLayer(id: id) { layer in
                    guard case .text(var content) = layer.content else { return }
                    content.colorHex = hex
                    layer.content = .text(content)
                    if !layer.style.shadows.isEmpty { layer.style.shadow = TextBuilder.autoContrastShadow(forColorHex: hex) }
                }
            }
        }
    }

    /// The shade words in `ink` should take on `ground`, or nil when theirs
    /// does: the nearest shade that reads when they do not, and white for
    /// plain dark words on a coloured fill where white reads, the way the
    /// system sets a button's label (dark on #007AFF passes on lightness
    /// alone, and every judge read "black text on blue", 2026-10-24).
    static func betterInk(_ ink: RGBA, hex: String, on ground: RGBA) -> String? {
        if RGBA.lightnessContrast(text: ink, on: ground) < AgentNewComponent.leastWordLightness {
            let picked = AgentNewComponent.readable(near: hex, on: ground)
            return picked.caseInsensitiveCompare(hex) == .orderedSame ? nil : picked
        }
        let spread = { (c: RGBA) in max(c.r, c.g, c.b) - min(c.r, c.g, c.b) }
        guard spread(ground) >= AgentNewComponent.saturatedSpread, spread(ink) < 0.1, ink.relativeLuminance < 0.2,
              AgentNewComponent.readable(near: hex, on: ground) == "#FFFFFF" else { return nil }
        return "#FFFFFF"
    }

    /// The colour words with no colour of their own should take in `frame`
    /// of `document`: near black, unless what is painted behind that spot
    /// (a blue button) needs another shade to be read.
    public static func defaultInk(at frame: CGRect, in document: PhotonzDocument,
                                  pictureColour: PictureColour = { _ in nil }) -> String {
        let ink = TextContent.agentDefaultColour
        var layers = document.layers
        let probe = Layer(name: "", content: .text(TextContent(string: "", colorHex: ink)), frame: frame)
        layers.append(probe)
        guard let ground = groundColour(of: layers.count - 1, in: layers, picture: pictureColour).flatMap({ RGBA(hex: $0) }),
              let dark = RGBA(hex: ink) else { return ink }
        return betterInk(dark, hex: ink, on: ground) ?? ink
    }

    // MARK: What is behind

    /// The topmost visible filled box or flat picture under the middle of
    /// layer `index`, looking through outlines and words. Nil on the page
    /// (whatever paints it fills the canvas, so nothing sits "in" it) and
    /// nil when something else (a photo, a group) is there first.
    static func backdrop(of index: Int, in layers: [Layer], canvas: CGRect, picture: PictureColour) -> Layer? {
        guard case .box(let layer, _) = behind(index, in: layers, picture: picture),
              !layer.frame.contains(canvas) else { return nil }
        return layer
    }

    /// The colour words at `index` are read against: a box's fill, a flat
    /// picture's colour, the bare canvas's white, or nil when it is not known
    /// (a photo, a gradient).
    static func groundColour(of index: Int, in layers: [Layer], picture: PictureColour) -> String? {
        switch behind(index, in: layers, picture: picture) {
        case .box(_, let hex): hex
        case .canvas: canvasColour
        case .unknown: nil
        }
    }

    private enum Behind {
        case box(Layer, String?)
        case canvas
        case unknown
    }

    private static func behind(_ index: Int, in layers: [Layer], picture: PictureColour) -> Behind {
        let frame = layers[index].frame
        let middle = CGPoint(x: frame.midX, y: frame.midY)
        for layer in layers[..<index].reversed() where layer.isVisible && layer.frame.contains(middle) {
            switch layer.content {
            case .text, .measure, .sound:
                continue
            case .annotation(let shape):
                guard shape.shape == .rectangle || shape.shape == .ellipse else { continue }
                guard let fill = shape.fill else { continue }
                guard fill.kind == .solid else { return .box(layer, nil) }
                let alpha = (RGBA(hex: fill.hex)?.a ?? 1) * layer.style.opacity
                if alpha < 0.5 { continue }
                return .box(layer, fill.hex)
            case .image(let ref):
                guard let flat = picture(ref) else { return .unknown }
                return .box(layer, flat)
            default:
                return .unknown
            }
        }
        return .canvas
    }
}

extension TextContent {
    /// The colour an agent's words take when the call names none.
    public static let agentDefaultColour = "#1C1C1E"
}
