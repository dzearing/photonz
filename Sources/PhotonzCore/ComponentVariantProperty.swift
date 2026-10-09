import Foundation

/// A component has PROPERTIES, and the looks it holds are one of them
/// (asked for by the user on 2026-09-15: "Variant is a property of the
/// component").
///
/// The panel used to split one idea in two. An "Adjustable" list held the knobs
/// a copy may set, and a "Versions" list held the drawings a copy may show, so
/// somebody meeting a component was asked to learn two words this app invented
/// for two halves of the same thing. They are one list: **Properties**. A
/// property is anything a copy can be given its own answer for, and a
/// **variant** is the kind of property whose answer picks which drawing of the
/// component the copy shows.
///
/// ### More than one question
///
/// A real button wants a Variant of Primary or Secondary AND a Size of Small
/// or Large, so a component may ask several variant questions at once
/// (`docs/design/mocks/pages/ui-variants.html`, `#segVariant` and `#segSize`).
/// The drawings stay a flat list and each one carries an answer per question.
/// A copy picks each answer on its own, and a combination nobody drew shows
/// the nearest drawing that was (`nearestComponentDrawing`), which is what
/// keeps Type × State × Size from meaning twenty-four drawings somebody has to
/// make by hand.
///
/// The FIRST question is the one every component has always had: its id is the
/// component's own, its name is `variantName`, and each drawing's answer to it
/// is `versionName`. Every question after it is written beside those as
/// `variantAnswers`, so a component asking one question saves exactly what it
/// always did.
///
/// The drawings themselves are still `ComponentVersion` in the code, and the
/// group still writes `versionID` and `versionName` to the file, because those
/// are what a document saved yesterday holds. **Version is the old spelling of
/// the word; nowhere a person can read it says version.**
public struct ComponentVariantProperty: Hashable, Sendable, Identifiable {
    /// Its identity. The first question's is the component's own id; every
    /// question after it has one of its own.
    public var id: UUID
    /// What the row is called on the panel: "Variant" until the author calls it
    /// State, or Type, or Size.
    public var name: String
    /// The answers it chooses between, in the order the drawings first give
    /// them.
    public var options: [ComponentVariantOption]

    public init(id: UUID, name: String, options: [ComponentVariantOption]) {
        self.id = id
        self.name = name
        self.options = options
    }
}

/// One answer to a variant question, and the drawings that give it.
public struct ComponentVariantOption: Hashable, Sendable, Identifiable {
    /// The answer: "Primary", "Large".
    public var name: String
    /// Every drawing giving this answer, in the component's order.
    public var drawings: [ComponentVersion]

    public var id: String { name }

    public init(name: String, drawings: [ComponentVersion]) {
        self.name = name
        self.drawings = drawings
    }
}

/// One drawing's answer to one question after the first, as it is written to
/// the file: which question, what it is called, and the answer. On a COPY it
/// is one answer of the combination the copy asked for, and the question's
/// name is not written.
public struct ComponentVariantAnswer: Hashable, Sendable, Codable {
    public var property: UUID
    public var option: String
    /// What the question is called, carried on every drawing so it outlives
    /// the drawing it was typed on. Nil on a copy.
    public var propertyName: String?

    public init(property: UUID, option: String, propertyName: String? = nil) {
        self.property = property
        self.option = option
        self.propertyName = propertyName
    }
}

/// What the panel shows for one question over the copies picked: its name, its
/// answers, and the one they all give (nil when they differ).
public struct ComponentVariantRowReading: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var options: [String]
    public var chosen: String?

    public init(id: UUID, name: String, options: [String], chosen: String?) {
        self.id = id
        self.name = name
        self.options = options
        self.chosen = chosen
    }
}

extension Layer {

    /// What the variant property of this main's component is called, nil on a
    /// component nobody has renamed it on.
    public var componentVariantName: String? { group?.variantName }
}

// MARK: - Reading it

extension PhotonzDocument {

    /// The variant properties of a component: none while it holds one drawing,
    /// one the moment it holds two, and one more for every question the author
    /// added beside the first.
    ///
    /// A component with a single look has nothing to choose between, so there
    /// is no property and the panel shows none. That is what keeps a plain
    /// component's panel the panel it always was rather than a menu with one
    /// item in it.
    public func componentVariantProperties(of componentID: UUID) -> [ComponentVariantProperty] {
        let drawings = componentVersions(of: componentID)
        guard drawings.count > 1 else { return [] }
        let mains = Dictionary(uniqueKeysWithValues: mainComponents
            .filter { $0.componentID == componentID }.map { ($0.id, $0) })
        func options(_ answer: (ComponentVersion) -> String?) -> [ComponentVariantOption] {
            var found: [ComponentVariantOption] = []
            for drawing in drawings {
                guard let name = answer(drawing) else { continue }
                if let index = found.firstIndex(where: { $0.name == name }) {
                    found[index].drawings.append(drawing)
                } else {
                    found.append(ComponentVariantOption(name: name, drawings: [drawing]))
                }
            }
            return found
        }
        var properties = [ComponentVariantProperty(id: componentID,
                                                   name: componentVariantName(of: componentID),
                                                   options: options { $0.option })]
        for question in componentVariantQuestions(of: componentID) {
            properties.append(ComponentVariantProperty(
                id: question.id, name: question.name,
                options: options { drawing in
                    mains[drawing.layerID]?.group?.variantAnswers
                        .first { $0.property == question.id }?.option
                }))
        }
        return properties
    }

    /// The questions after the first, in the order they were added, each with
    /// the name the drawings carry for it.
    func componentVariantQuestions(of componentID: UUID) -> [(id: UUID, name: String)] {
        var found: [(id: UUID, name: String)] = []
        for main in mainComponents where main.componentID == componentID {
            for answer in main.group?.variantAnswers ?? [] {
                let name = ComponentNaming.normalized(answer.propertyName)
                if let index = found.firstIndex(where: { $0.id == answer.property }) {
                    if found[index].name.isEmpty, let name { found[index].name = name }
                } else {
                    found.append((answer.property, name ?? ""))
                }
            }
        }
        return found.enumerated().map { index, question in
            (question.id, question.name.isEmpty ? ComponentNaming.propertyName(at: index + 2)
                                                : question.name)
        }
    }

    /// One drawing's answer to every question, keyed by question.
    public func componentVariantAnswers(of componentID: UUID,
                                        drawing: ComponentVersion) -> [UUID: String] {
        var answers = [componentID: drawing.option]
        for answer in layer(id: drawing.layerID)?.group?.variantAnswers ?? [] {
            answers[answer.property] = answer.option
        }
        return answers
    }

    /// The drawing that best answers a combination: one that gives every
    /// answer when somebody drew it, and otherwise the NEAREST one that was.
    ///
    /// Nearest means it gives the answer to `keeping` (the question just
    /// picked, so choosing Large always shows something Large), then as many
    /// of the other answers as it can, earlier questions counting for more
    /// than later ones. Ties go to the drawing first in the component's order.
    /// Never nil while the component has a drawing at all, which is what keeps
    /// a copy from ever showing a blank.
    public func nearestComponentDrawing(of componentID: UUID, answers: [UUID: String],
                                        keeping: UUID? = nil) -> ComponentVersion? {
        let drawings = componentVersions(of: componentID)
        let order = [componentID] + componentVariantQuestions(of: componentID).map(\.id)
        var best: (drawing: ComponentVersion, score: Int)?
        for drawing in drawings {
            let given = componentVariantAnswers(of: componentID, drawing: drawing)
            var score = 0
            for (index, property) in order.enumerated() where given[property] == answers[property] {
                score += 1 << (order.count - index)
            }
            if let keeping, given[keeping] == answers[keeping] { score += 1 << (order.count + 1) }
            if best == nil || score > best?.score ?? 0 { best = (drawing, score) }
        }
        return best?.drawing
    }

    /// What this component's variant property is called, falling back to the
    /// word the panel starts it at.
    ///
    /// Read off whichever drawing carries it, because every drawing carries the
    /// same answer and the one it was typed on may since have been deleted.
    public func componentVariantName(of componentID: UUID) -> String {
        for main in mainComponents where main.componentID == componentID {
            if let name = ComponentNaming.normalized(main.componentVariantName) { return name }
        }
        return ComponentNaming.defaultVariantPropertyName
    }

    // MARK: - Naming it

    /// Calls this component's variant property something else — State, Type,
    /// Size. Answers false, changing nothing, for a blank name or for a
    /// component that has no variant property to name.
    ///
    /// Written to EVERY drawing of the component, so the name outlives the
    /// drawing it was typed on.
    @discardableResult
    public mutating func renameComponentVariantProperty(of componentID: UUID,
                                                        to name: String) -> Bool {
        guard let chosen = ComponentNaming.normalized(name) else { return false }
        guard componentVersions(of: componentID).count > 1 else { return false }
        guard chosen != componentVariantName(of: componentID) else { return false }
        var changed = false
        for main in mainComponents where main.componentID == componentID {
            updateLayer(id: main.id) { layer in
                guard var group = layer.group else { return }
                group.variantName = chosen
                layer.content = .group(group)
                changed = true
            }
        }
        return changed
    }
}

// MARK: - A question beside the first

extension PhotonzDocument {

    /// Asks a second (or third) variant question of a component, beside the
    /// one it already asks, and answers the new question's id and the new
    /// drawing made for it.
    ///
    /// A question with one answer is not a choice, so it arrives with two:
    /// every drawing the component had answers Default, and a duplicate of
    /// `version` (the first drawing when nil) answers the next one along,
    /// keeping every other answer of the drawing it came from.
    ///
    /// Nil for a component with a single drawing, which has no first question
    /// yet to ask this one beside: "A second Variant" is how that one starts.
    @discardableResult
    public mutating func addComponentVariantProperty(componentID: UUID, from version: UUID? = nil,
                                                     name: String? = nil)
        -> (property: UUID, version: UUID)? {
        let existing = componentVariantProperties(of: componentID)
        guard !existing.isEmpty else { return nil }
        settleComponentVersionIdentities(componentID: componentID)
        let taken = existing.map(\.name)
        let chosen = ComponentNaming.normalized(name).flatMap { candidate in
            taken.contains { $0.caseInsensitiveCompare(candidate) == .orderedSame } ? nil : candidate
        } ?? ComponentNaming.freshPropertyName(taken: taken)
        let property = UUID()
        for main in mainComponents where main.componentID == componentID {
            updateLayer(id: main.id) { layer in
                guard var group = layer.group else { return }
                group.variantAnswers.append(ComponentVariantAnswer(
                    property: property, option: ComponentNaming.defaultVersionName,
                    propertyName: chosen))
                layer.content = .group(group)
            }
        }
        guard let added = addComponentVariantOption(componentID: componentID, property: property,
                                                    from: version)
        else { return nil }
        return (property, added)
    }

    /// Another drawing of a component that differs from `version` (the first
    /// drawing when nil) on ONE question: it gives that question a fresh
    /// answer, "Size 2", and every other question the answer `version` gives.
    /// Answers the new drawing's id.
    @discardableResult
    public mutating func addComponentVariantOption(componentID: UUID, property: UUID,
                                                   from version: UUID? = nil) -> UUID? {
        guard property != componentID else {
            return addComponentVersion(componentID: componentID, from: version)
        }
        guard let question = componentVariantProperties(of: componentID)
                .first(where: { $0.id == property }) else { return nil }
        let names = question.options.map(\.name)
        let fresh = ComponentNaming.freshVersionName(taken: names, count: names.count,
                                                     property: question.name)
        return addComponentVersion(componentID: componentID, from: version,
                                   answer: ComponentVariantAnswer(property: property, option: fresh))
    }

    /// Renames one of a component's variant questions. Answers false, changing
    /// nothing, for a blank name, the name it already has, or a name another
    /// of its questions already has: a copy would show two rows called the
    /// same thing.
    @discardableResult
    public mutating func renameComponentVariantProperty(of componentID: UUID, property: UUID,
                                                        to name: String) -> Bool {
        guard let chosen = ComponentNaming.normalized(name) else { return false }
        let properties = componentVariantProperties(of: componentID)
        guard let current = properties.first(where: { $0.id == property }),
              current.name != chosen,
              !properties.contains(where: {
                  $0.id != property && $0.name.caseInsensitiveCompare(chosen) == .orderedSame
              }) else { return false }
        guard property != componentID else {
            return renameComponentVariantProperty(of: componentID, to: chosen)
        }
        for main in mainComponents where main.componentID == componentID {
            updateLayer(id: main.id) { layer in
                guard var group = layer.group else { return }
                for index in group.variantAnswers.indices where group.variantAnswers[index].property == property {
                    group.variantAnswers[index].propertyName = chosen
                }
                layer.content = .group(group)
            }
        }
        return true
    }

    /// Types a word over the answer one drawing gives to one question.
    ///
    /// A word another answer to that question already has moves THIS drawing
    /// into it: it is how a second Large is drawn. Any other word renames the
    /// answer on every drawing giving it, so calling Default Medium once calls
    /// it Medium everywhere. Answers whether anything changed; a blank word, or
    /// the word already there, changes nothing.
    @discardableResult
    public mutating func setComponentVariantOption(componentID: UUID, drawing layerID: UUID,
                                                   property: UUID, to name: String) -> Bool {
        guard let chosen = ComponentNaming.normalized(name),
              let question = componentVariantProperties(of: componentID)
                .first(where: { $0.id == property }),
              let current = question.options.first(where: {
                  $0.drawings.contains { $0.layerID == layerID }
              }), current.name != chosen else { return false }
        let joining = question.options.contains { $0.name == chosen }
        let reaching = joining ? [layerID] : current.drawings.map(\.layerID)
        settleComponentVersionIdentities(componentID: componentID)
        for id in reaching {
            updateLayer(id: id) { layer in
                guard var group = layer.group else { return }
                if property == componentID {
                    group.versionName = chosen
                } else {
                    for index in group.variantAnswers.indices
                    where group.variantAnswers[index].property == property {
                        group.variantAnswers[index].option = chosen
                    }
                }
                layer.content = .group(group)
            }
        }
        return true
    }

    // MARK: - A copy's answers

    /// The answer a copy gives to every question its component asks: the
    /// combination it asked for, which is the drawing it shows unless nobody
    /// drew that combination. An answer the component no longer offers falls
    /// back to the drawing's own.
    public func instanceVariantAnswers(of instance: UUID) -> [UUID: String] {
        guard let copy = layer(id: instance), let componentID = copy.instanceOf,
              let shownID = instanceVersion(of: instance),
              let shown = componentVersion(of: componentID, id: shownID) else { return [:] }
        var answers = componentVariantAnswers(of: componentID, drawing: shown)
        let asked = copy.group?.instanceAnswers ?? []
        guard !asked.isEmpty else { return answers }
        let properties = componentVariantProperties(of: componentID)
        for answer in asked {
            guard let question = properties.first(where: { $0.id == answer.property }),
                  question.options.contains(where: { $0.name == answer.option }) else { continue }
            answers[answer.property] = answer.option
        }
        return answers
    }

    /// Gives every copy picked one answer to one question, leaving its other
    /// answers as they were, and shows each the drawing that answers its new
    /// combination, or the nearest one when nobody drew it. Returns how many
    /// copies changed; an answer the question does not offer changes none.
    @discardableResult
    public mutating func setInstanceVariantAnswer(instances: [UUID], property: UUID,
                                                  option: String) -> Int {
        var changed = 0
        for instance in instances {
            guard let copy = layer(id: instance), !copy.isLocked,
                  let componentID = copy.instanceOf,
                  let question = componentVariantProperties(of: componentID)
                    .first(where: { $0.id == property }),
                  question.options.contains(where: { $0.name == option }) else { continue }
            var wanted = instanceVariantAnswers(of: instance)
            guard wanted[property] != option else { continue }
            wanted[property] = option
            guard let drawing = nearestComponentDrawing(of: componentID, answers: wanted,
                                                        keeping: property) else { continue }
            let drawn = componentVariantAnswers(of: componentID, drawing: drawing)
            let order = [componentID] + componentVariantQuestions(of: componentID).map(\.id)
            let remembered = drawn == wanted ? [] : order.compactMap { id in
                wanted[id].map { ComponentVariantAnswer(property: id, option: $0) }
            }
            updateLayer(id: instance) { layer in
                guard var group = layer.group else { return }
                group.instanceVersion = drawing.id
                group.instanceAnswers = remembered
                layer.content = .group(group)
            }
            changed += 1
        }
        return changed
    }
}

// MARK: - What it is called before anybody names it

extension ComponentNaming {

    /// What the looks a component holds are asked about before the author says
    /// otherwise. One word, the one every design tool uses, and a noun for a
    /// thing rather than an adjective for a quality.
    public static let defaultVariantPropertyName = "Variant"

    /// What sits between a drawing's answers where it is named: "Primary · Large".
    public static let answerSeparator = " · "

    /// What the question in position `position` (counting from one) is called
    /// before anybody names it. The second is Size, because size is what a
    /// component is asked next nearly every time; after that a plain count.
    public static func propertyName(at position: Int) -> String {
        position == 2 ? "Size" : "Property \(position)"
    }

    /// A question name nobody is using yet.
    static func freshPropertyName(taken: [String]) -> String {
        func free(_ name: String) -> Bool {
            !taken.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
        }
        let first = propertyName(at: taken.count + 1)
        if free(first) { return first }
        var index = taken.count + 1
        while !free("Property \(index)") { index += 1 }
        return "Property \(index)"
    }
}
