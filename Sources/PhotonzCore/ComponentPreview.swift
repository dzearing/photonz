import CoreGraphics
import Foundation

// Preview: trying a page of components as though it were the real thing
// (`docs/design/mocks/pages/component-preview.html`, built as the user answered
// on 2026-11-06). Point at a button and it shows its Hover look, press it and
// it shows Pressed, click a switch and it stays On, Tab through the page.
//
// Which look means which state is read off the look's own name, so there is
// nothing to set up. Everything Preview does lives in one value that is thrown
// away on leaving: a copy's stored look is never written, nothing goes through
// `History`, and what the canvas draws is `drawn(_:)`, a changed copy of the
// document that nothing keeps.

// MARK: - What it says

/// The words of Preview, in one place: the button, the View menu row and the
/// name a walk presses all read the same one.
public enum ComponentPreviewCopy {
    public static let button = "Preview"
    public static let leave = "Esc to leave"
    public static let key = "⌘Return"
}

// MARK: - What a look's name says

/// What one look is for, read from its name.
///
/// A name is up to four things at once: a family of its own ("Primary"), where
/// a latching control rests ("On", "Selected"), a passing moment ("Hover"), and
/// whether it is switched off altogether ("Disabled"). So "On Hover" is the On
/// control under the pointer, and "Primary Hover" is what Primary shows there.
public struct ComponentLookName: Hashable, Sendable {

    /// Where a control that stays put has been left.
    public enum Latch: Hashable, Sendable { case on, selected }

    /// What is happening to a control for as long as it lasts.
    public enum Moment: Hashable, Sendable { case hover, pressed, focused }

    /// The words that are not about state, lower cased and sorted.
    public let stem: [String]
    public let latch: Latch?
    public let moment: Moment?
    public let isDisabled: Bool
    /// Named Off or the like, rather than only being not On.
    public let saysOff: Bool

    private static let hoverNames: Set<String> = ["hover", "hovered"]
    private static let pressedNames: Set<String> = ["pressed"]
    private static let focusedNames: Set<String> = ["focused", "focus"]
    private static let disabledNames: Set<String> = ["disabled"]
    private static let selectedNames: Set<String> = ["selected"]

    public init(_ name: String) {
        var stem: [String] = []
        var latch: Latch?
        var moment: Moment?
        var disabled = false
        var off = false
        for word in AgentNewComponent.stateWords(name) {
            if Self.hoverNames.contains(word) { moment = .hover }
            else if Self.pressedNames.contains(word) { moment = .pressed }
            else if Self.focusedNames.contains(word) { moment = .focused }
            else if Self.disabledNames.contains(word) { disabled = true }
            else if Self.selectedNames.contains(word) { latch = .selected }
            else if AgentNewComponent.checkedNames.contains(word) { latch = .on }
            else if AgentNewComponent.offNames.contains(word) { off = true }
            else if !AgentNewComponent.restNames.contains(word) { stem.append(word) }
        }
        self.stem = stem.sorted()
        self.latch = latch
        self.moment = moment
        self.isDisabled = disabled
        self.saysOff = off
    }

    /// Whether the name says anything about state. Default alone does not: a
    /// component whose only state word is its resting look has nothing to play.
    public var saysAState: Bool { latch != nil || moment != nil || isDisabled || saysOff }

    /// A look a control can stay on.
    var isResting: Bool { moment == nil && !isDisabled }
}

// MARK: - The session

/// Everything that has happened on the page since Preview began.
public struct ComponentPreview: Hashable, Sendable {

    /// Where each copy has been left by a click, as its answer to the question
    /// its looks answer. Only copies a click changed are here.
    public private(set) var resting: [UUID: String] = [:]
    /// The copy under the pointer.
    public private(set) var hovered: UUID?
    /// The copy the press started on, for as long as the button is down.
    public private(set) var armed: UUID?
    /// The copy showing Pressed: `armed` while the pointer is still on it.
    public private(set) var pressed: UUID?
    /// The copy with the keyboard.
    public private(set) var focused: UUID?

    public init() {}

    // MARK: Pointing

    /// The copy a point lands on. A lock is ignored, because it only means not
    /// while editing, and anything else on top answers nil, because a person
    /// could not reach what is under it.
    public func copy(at point: CGPoint, in document: PhotonzDocument, zoom: CGFloat = 1) -> UUID? {
        guard CGRect(origin: .zero, size: document.canvasSize).contains(point),
              let path = document.hitTestPath(point, zoom: zoom, throughLocks: true),
              let layer = document.layer(atPath: path), layer.isComponentInstance
        else { return nil }
        return layer.id
    }

    public mutating func point(at copy: UUID?) {
        hovered = copy
    }

    /// The button went down on `copy`, or on nothing. A press on nothing lets
    /// go of the keyboard, as a click on a page's background does.
    public mutating func press(_ copy: UUID?, in document: PhotonzDocument) {
        guard let copy else {
            armed = nil
            pressed = nil
            focused = nil
            return
        }
        guard !isDisabled(copy, in: document) else {
            armed = nil
            pressed = nil
            return
        }
        armed = copy
        pressed = copy
    }

    /// The pointer moved with the button down. Sliding off lets go without a
    /// click, and sliding back presses again, as a real button does.
    public mutating func drag(over copy: UUID?) {
        hovered = copy
        guard let armed else { return }
        pressed = copy == armed ? armed : nil
    }

    /// The button came up. Only a release over the copy the press started on is
    /// a click. `point` says which word of a segmented control it landed on.
    public mutating func release(over copy: UUID?, at point: CGPoint?, in document: PhotonzDocument) {
        let started = armed
        armed = nil
        pressed = nil
        if let started, started == copy { click(started, at: point, in: document) }
    }

    // MARK: Keys

    /// Every copy Tab stops on, in reading order: not a Disabled one, and not
    /// one with no look to show for it, since Preview adds no ring of its own
    /// and a stop with nothing to see would look like the key had failed.
    public func tabStops(in document: PhotonzDocument) -> [UUID] {
        Self.readingOrder(document.copiesOnThePage()).map(\.id).filter { isTabStop($0, in: document) }
    }

    /// Tab and Shift-Tab. Counted from where the keyboard is in the page rather
    /// than in the stops, so a tab that lost its Focused look by being picked
    /// hands on to its neighbour instead of sending the keyboard back to the
    /// top of the page.
    public mutating func tab(backwards: Bool, in document: PhotonzDocument) {
        let order = Self.readingOrder(document.copiesOnThePage()).map(\.id)
        guard !order.isEmpty else { return }
        let start = focused.flatMap { order.firstIndex(of: $0) }
        let step = backwards ? order.count - 1 : 1
        var index = start ?? (backwards ? 0 : order.count - 1)
        for _ in order.indices {
            index = (index + step) % order.count
            if isTabStop(order[index], in: document) {
                focused = order[index]
                return
            }
        }
    }

    /// Space and Return: a click on whatever has the keyboard.
    public mutating func activateFocus(in document: PhotonzDocument) {
        guard let focused else { return }
        click(focused, at: nil, in: document)
    }

    /// Whether a Command key reaches the menus while Preview is up. The ones
    /// that leave the page alone do: leaving, closing, saving, hiding and
    /// zooming. Everything else stops here, so a stray ⌘Z or ⌘V cannot change
    /// the document somebody is only trying out.
    public static func commandKeyReachesTheMenus(_ key: String) -> Bool {
        ["\r", "\u{3}", "q", "w", "h", "m", "s", "`", ",", "=", "+", "-", "0"].contains(key)
    }

    // MARK: Reading

    /// The look a copy is showing right now, nil for a copy with no named looks.
    public func look(of copy: UUID, in document: PhotonzDocument) -> String? {
        guard let looks = looks(of: copy, in: document) else { return nil }
        return shown(copy, looks)
    }

    /// The short note for the pill: under the pointer is a component whose
    /// looks say nothing about state, so nothing here will change. Thirty
    /// characters at most, whatever the component is called, since it is
    /// chrome (UX-PATTERNS §4).
    public func note(in document: PhotonzDocument) -> String? {
        guard let hovered, let copy = document.layer(id: hovered),
              let componentID = copy.instanceOf else { return nil }
        if looks(of: hovered, in: document) != nil { return nil }
        let tail = ": no state looks"
        let room = Self.noteBudget - tail.count
        let name = document.mainComponent(componentID: componentID)?.name ?? copy.name
        let fitted = name.count <= room ? name : String(name.prefix(room - 1)) + "…"
        return fitted + tail
    }

    /// The document as Preview draws it: every copy not at its stored look moved
    /// to the one it is showing, on a value nothing keeps. A page with nothing
    /// happening comes straight back.
    public func drawn(_ document: PhotonzDocument) -> PhotonzDocument {
        var ids = Set(resting.keys)
        for id in [hovered, pressed, focused] { if let id { ids.insert(id) } }
        var out = document
        var changed = false
        for id in ids {
            guard let looks = looks(of: id, in: document) else { continue }
            let want = shown(id, looks)
            guard want != looks.stored else { continue }
            var answers = document.instanceVariantAnswers(of: id)
            answers[looks.question] = want
            guard let drawing = document.nearestComponentDrawing(of: looks.componentID, answers: answers,
                                                                 keeping: looks.question)
            else { continue }
            out.updateLayer(id: id) { layer in
                guard var group = layer.group else { return }
                group.instanceVersion = drawing.id
                group.instanceAnswers = []
                layer.content = .group(group)
            }
            changed = true
        }
        guard changed else { return document }
        out.syncComponentInstances()
        return out
    }

    // MARK: - The rules

    /// One copy's looks: the question they answer, and what it says today.
    struct Looks {
        var componentID: UUID
        /// The variant question whose answers are the looks.
        var question: UUID
        var options: [String]
        /// What the document says this copy shows.
        var stored: String
        /// The looks are named for the words drawn on the control.
        var isWordControl: Bool
    }

    /// Reads which question a copy's looks answer: the first whose answers say
    /// anything about state, otherwise one whose answers are words drawn on the
    /// control itself, which is how the sheets draw a segmented control. Nil
    /// for a component with neither.
    func looks(of copy: UUID, in document: PhotonzDocument) -> Looks? {
        guard let layer = document.layer(id: copy), let componentID = layer.instanceOf else { return nil }
        let questions = document.componentVariantProperties(of: componentID)
        let answers = document.instanceVariantAnswers(of: copy)
        func reading(_ question: ComponentVariantProperty, words: Bool) -> Looks? {
            guard let stored = answers[question.id] else { return nil }
            return Looks(componentID: componentID, question: question.id,
                         options: question.options.map(\.name), stored: stored, isWordControl: words)
        }
        if let question = questions.first(where: { each in
            each.options.contains { ComponentLookName($0.name).saysAState }
        }) {
            return reading(question, words: false)
        }
        let drawn = Set(Self.words(in: layer, at: .zero).map { $0.word.lowercased() })
        if let question = questions.first(where: { each in
            each.options.filter { drawn.contains($0.name.lowercased()) }.count >= 2
        }) {
            return reading(question, words: true)
        }
        return nil
    }

    /// Where this copy has been left: a click's answer while that look still
    /// exists, otherwise what the document says.
    private func base(_ copy: UUID, _ looks: Looks) -> String {
        if let left = resting[copy], looks.options.contains(left) { return left }
        return looks.stored
    }

    func isDisabled(_ copy: UUID, in document: PhotonzDocument) -> Bool {
        guard let looks = looks(of: copy, in: document) else { return false }
        return ComponentLookName(base(copy, looks)).isDisabled
    }

    private func isTabStop(_ copy: UUID, in document: PhotonzDocument) -> Bool {
        guard let looks = looks(of: copy, in: document) else { return false }
        let base = base(copy, looks)
        guard !ComponentLookName(base).isDisabled else { return false }
        return Self.look(for: .focused, from: base, in: looks.options) != nil
    }

    /// The look for a moment from where a copy rests: one of its own family
    /// resting the same way. So an On copy wants On Hover, never the plain Hover
    /// drawn for the off control, which would look as though it had flipped back.
    static func look(for moment: ComponentLookName.Moment, from base: String,
                     in options: [String]) -> String? {
        let resting = ComponentLookName(base)
        return options.first { option in
            let name = ComponentLookName(option)
            return name.moment == moment && !name.isDisabled
                && name.stem == resting.stem && name.latch == resting.latch
        }
    }

    private func shown(_ copy: UUID, _ looks: Looks) -> String {
        let base = base(copy, looks)
        guard !ComponentLookName(base).isDisabled else { return base }
        // While a press is held nothing else lights up, as with real controls.
        let held = pressed == copy
        let over = hovered == copy && (armed == nil || armed == copy)
        var look: String?
        if held { look = Self.look(for: .pressed, from: base, in: looks.options) }
        if look == nil, over || held { look = Self.look(for: .hover, from: base, in: looks.options) }
        if look == nil, focused == copy { look = Self.look(for: .focused, from: base, in: looks.options) }
        return look ?? base
    }

    /// The look a latching control stays on, nil for a control that does not.
    private static func latched(from base: String, in options: [String]) -> String? {
        let stem = ComponentLookName(base).stem
        return options.first { option in
            let name = ComponentLookName(option)
            return name.isResting && name.latch != nil && name.stem == stem
        }
    }

    /// The look it goes back to: one named Off, else its resting look.
    private static func unlatched(from base: String, in options: [String]) -> String? {
        let stem = ComponentLookName(base).stem
        let candidates = options.filter { option in
            let name = ComponentLookName(option)
            return name.isResting && name.latch == nil && name.stem == stem
        }
        return candidates.first { ComponentLookName($0).saysOff } ?? candidates.first
    }

    private mutating func click(_ copy: UUID, at point: CGPoint?, in document: PhotonzDocument) {
        guard let looks = looks(of: copy, in: document) else { return }
        let base = base(copy, looks)
        guard !ComponentLookName(base).isDisabled else { return }
        if looks.isWordControl {
            if let point, let word = word(on: copy, at: point, options: looks.options, in: document) {
                resting[copy] = word
            }
            return
        }
        if let latched = Self.latched(from: base, in: looks.options) {
            let peers = keepsOne(copy, latched: latched, in: document)
            if peers.count > 1 {
                for peer in peers { leave(peer, in: document) }
                resting[copy] = latched
            } else if ComponentLookName(base).latch != nil {
                if let off = Self.unlatched(from: base, in: looks.options) { resting[copy] = off }
            } else {
                resting[copy] = latched
            }
            return
        }
        // A field: nothing to press, so a click is how it takes the keyboard.
        let options = looks.options
        if Self.look(for: .focused, from: base, in: options) != nil,
           Self.look(for: .pressed, from: base, in: options) == nil {
            focused = copy
        }
    }

    /// Puts a peer back to its off look, unless it is Disabled.
    private mutating func leave(_ peer: UUID, in document: PhotonzDocument) {
        guard let looks = looks(of: peer, in: document) else { return }
        let base = base(peer, looks)
        guard !ComponentLookName(base).isDisabled else { return }
        if let off = Self.unlatched(from: base, in: looks.options) { resting[peer] = off }
    }

    /// The copies that keep one picked between them, this one among them:
    /// copies of one component with one parent, when the look is a Selected
    /// one or the component is a radio. A switch or a checkbox is on its own,
    /// however many sit side by side.
    private func keepsOne(_ copy: UUID, latched: String, in document: PhotonzDocument) -> [UUID] {
        guard let componentID = document.layer(id: copy)?.instanceOf else { return [copy] }
        let name = document.mainComponent(componentID: componentID)?.name.lowercased() ?? ""
        guard ComponentLookName(latched).latch == .selected || name.contains("radio") else { return [copy] }
        let page = document.copiesOnThePage()
        guard let parent = page.first(where: { $0.id == copy })?.parent else { return [copy] }
        return page.filter { $0.parent == parent && $0.componentID == componentID }.map(\.id)
    }

    // MARK: - Words on a control

    /// The word a point is nearest, among the looks' names drawn on this copy.
    /// Nearest rather than inside, so the padding of a segment counts as it.
    private func word(on copy: UUID, at point: CGPoint, options: [String],
                      in document: PhotonzDocument) -> String? {
        guard let layer = document.layer(id: copy), let origin = document.parentOrigin(of: copy) else { return nil }
        let local = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
        let drawn = Self.words(in: layer, at: .zero).compactMap { found -> (String, CGFloat)? in
            guard let option = options.first(where: { $0.caseInsensitiveCompare(found.word) == .orderedSame })
            else { return nil }
            return (option, hypot(found.box.midX - local.x, found.box.midY - local.y))
        }
        return drawn.min { $0.1 < $1.1 }?.0
    }

    /// Every piece of text inside a layer, with its box in the space `origin`
    /// is measured in.
    static func words(in layer: Layer, at origin: CGPoint) -> [(word: String, box: CGRect)] {
        let inner = CGPoint(x: origin.x + layer.frame.origin.x, y: origin.y + layer.frame.origin.y)
        if case .text(let text) = layer.content {
            return [(text.string.trimmingCharacters(in: .whitespacesAndNewlines),
                     layer.frame.offsetBy(dx: origin.x, dy: origin.y))]
        }
        guard layer.isGroup else { return [] }
        return layer.children.flatMap { words(in: $0, at: inner) }
    }

    // MARK: - Reading order

    /// How long the note may be: chrome, so a label of 30 characters.
    static let noteBudget = 30

    /// Top to bottom, left to right. Copies whose middles fall inside the first
    /// one's height share a row, so a row a few points out of line is one row.
    static func readingOrder(_ copies: [PageCopy]) -> [PageCopy] {
        var rows: [[PageCopy]] = []
        for copy in copies.sorted(by: { $0.box.minY < $1.box.minY }) {
            if let first = rows.last?.first, copy.box.midY <= first.box.maxY {
                rows[rows.count - 1].append(copy)
            } else {
                rows.append([copy])
            }
        }
        return rows.flatMap { row in row.sorted { $0.box.minX < $1.box.minX } }
    }
}

// MARK: - The copies on a page

/// One copy a person can reach on the page.
struct PageCopy: Hashable, Sendable {
    var id: UUID
    var componentID: UUID
    /// The group it sits in. Nil is the page itself, so loose copies of one
    /// component count as one group.
    var parent: UUID??
    /// Its box on the canvas.
    var box: CGRect
}

extension PhotonzDocument {

    /// Whether this picture has anything for Preview to play: a recording is a
    /// player already, and a page with no copies has no controls on it.
    public var canPreviewComponents: Bool { !hasTime && holdsComponentInstance }

    /// Every copy on the page a person can see: not a hidden one, and not one
    /// off the canvas, which is where Ask leaves the looks of what it made. What
    /// is inside a copy belongs to its original, so the search stops at a copy.
    func copiesOnThePage() -> [PageCopy] {
        var found: [PageCopy] = []
        let page = CGRect(origin: .zero, size: canvasSize)
        func walk(_ list: [Layer], offset: CGPoint, parent: UUID?) {
            for layer in list where layer.isVisible {
                if let componentID = layer.instanceOf {
                    let box = layer.localBounds.offsetBy(dx: offset.x, dy: offset.y)
                    guard box.intersects(page) else { continue }
                    found.append(PageCopy(id: layer.id, componentID: componentID, parent: .some(parent), box: box))
                } else if layer.isGroup {
                    walk(layer.children,
                         offset: CGPoint(x: offset.x + layer.frame.origin.x, y: offset.y + layer.frame.origin.y),
                         parent: layer.id)
                }
            }
        }
        walk(layers, offset: .zero, parent: nil)
        return found
    }
}
