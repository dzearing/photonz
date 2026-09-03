import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Step D7: the components the app brings with it, so the Library holds
/// something the first time it opens (`docs/design/ui-building.md`,
/// "Useful on arrival").
struct StarterComponentTests {

    private func document(_ size: CGFloat = 800, pixelScale: CGFloat = 1) -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: size, height: size), pixelScale: pixelScale)
    }

    private let centre = CGPoint(x: 400, y: 400)

    // MARK: - The set itself

    @Test func theSetIsTheFiveThatWereAskedFor() {
        #expect(StarterComponent.allCases.map(\.name)
                == ["Button", "Text Field", "Card", "Nav Bar", "Badge"])
    }

    /// The ids are the app's, not minted per launch: a document saved with a
    /// starter in it opens tomorrow still pointing at the same shelf tile.
    @Test func everyStarterKeepsTheSameIdentityEveryTime() {
        let first = StarterComponent.allCases.map(\.componentID)
        let second = StarterComponent.allCases.map(\.componentID)
        #expect(first == second)
        #expect(Set(first).count == first.count)
        #expect(StarterComponent(componentID: StarterComponent.button.componentID) == .button)
        #expect(StarterComponent(componentID: UUID()) == nil)
    }

    @Test func everyStarterIsAGroupWithAName() {
        for kind in StarterComponent.allCases {
            let layer = StarterComponents.layer(kind)
            #expect(layer.isGroup)
            #expect(layer.name == kind.name)
            #expect(layer.componentID == kind.componentID)
            #expect(layer.children.count >= 2)
            #expect(layer.localBounds.width > 0)
            #expect(layer.localBounds.height > 0)
        }
    }

    /// A control drawn at 36 points would land half size on a Retina capture,
    /// whose canvas is measured in image pixels.
    @Test func aStarterIsBuiltAtTheDocumentsScale() {
        let one = StarterComponents.layer(.button, scale: 1)
        let two = StarterComponents.layer(.button, scale: 2)
        #expect(two.localBounds.width == one.localBounds.width * 2)
        #expect(two.localBounds.height == one.localBounds.height * 2)
    }

    /// The redline contrast halo belongs on a caption over a screenshot, not on
    /// a button's label.
    @Test func starterTextCarriesNoContrastHalo() {
        for kind in StarterComponent.allCases {
            for child in StarterComponents.layer(kind).selfAndDescendants {
                guard case .text = child.content else { continue }
                #expect(child.style.shadow == nil)
            }
        }
    }

    // MARK: - Built from named colors

    @Test func everyPaintedPieceComesFromANamedStyle() {
        for kind in StarterComponent.allCases {
            let layer = StarterComponents.layer(kind)
            for child in layer.children {
                for slot in child.colorSlots where paints(child, slot) {
                    #expect(child.colorStyleID(for: slot) != nil,
                            "\(kind.name) / \(child.name) paints \(slot) by hand")
                }
            }
        }
    }

    /// Whether a slot's color is one you can actually see: a box with no
    /// border still carries an ink color it never draws.
    private func paints(_ layer: Layer, _ slot: ColorSlot) -> Bool {
        guard layer.colorHex(for: slot) != nil else { return false }
        guard case .annotation(let annotation) = layer.content, slot == .stroke else { return true }
        return annotation.strokeWidth > 0
    }

    @Test func aStarterOnlyNamesTheColorsItActuallyUses() {
        #expect(StarterComponent.button.usedStyles.contains(.accent))
        #expect(!StarterComponent.button.usedStyles.contains(.border))
        #expect(StarterComponent.textField.usedStyles.contains(.border))
    }

    // MARK: - Dropping one

    @Test func droppingOneBringsTheOriginalIntoTheDocument() {
        var doc = document()
        let placed = doc.insertStarterComponent(.button, at: centre)
        #expect(placed != nil)
        #expect(doc.mainComponents.count == 1)
        #expect(doc.mainComponent(componentID: StarterComponent.button.componentID) != nil)
    }

    @Test func theOriginalLandsCentredOnWhereItWasDropped() {
        var doc = document()
        guard let placed = doc.insertStarterComponent(.button, at: centre),
              let box = doc.canvasBounds(of: placed) else { Issue.record("not placed"); return }
        #expect(abs(box.midX - centre.x) < 0.51)
        #expect(abs(box.midY - centre.y) < 0.51)
    }

    @Test func droppingOneBringsItsNamedColorsWithIt() {
        var doc = document()
        doc.insertStarterComponent(.button, at: centre)
        let names = doc.colorStyles.map(\.name)
        #expect(names.contains(StarterStyle.accent.name))
        #expect(names.contains(StarterStyle.surface.name))
        // ...and nothing it does not use.
        #expect(!names.contains(StarterStyle.border.name))
    }

    @Test func recoloringOneStyleRepaintsEveryStarterWearingIt() {
        var doc = document()
        doc.insertStarterComponent(.button, at: CGPoint(x: 200, y: 200))
        doc.insertStarterComponent(.badge, at: CGPoint(x: 500, y: 500))
        guard let accent = doc.colorStyles.first(where: { $0.name == StarterStyle.accent.name })
        else { Issue.record("no accent"); return }
        let repainted = doc.setColorStyleHex(styleID: accent.id, hex: "#00FF00")
        #expect(repainted >= 2)
        let painted = doc.allLayers.filter { $0.colorStyleID(for: .fill) == accent.id }
        #expect(!painted.isEmpty)
        #expect(painted.allSatisfy { $0.colorHex(for: .fill) == "#00FF00" })
    }

    /// A person who already keeps an "Accent" gets theirs, not a second one
    /// with the same name and a different color.
    @Test func aStyleYouAlreadyHaveIsUsedRatherThanDuplicated() {
        var doc = document()
        let mine = doc.addColorStyle(name: StarterStyle.accent.name, colorHex: "#FF0000")
        doc.insertStarterComponent(.button, at: centre)
        #expect(doc.colorStyles.filter { $0.name == StarterStyle.accent.name }.count == 1)
        let painted = doc.allLayers.filter { $0.colorStyleID(for: .fill) == mine }
        #expect(painted.count == 1)
        #expect(painted.first?.colorHex(for: .fill) == "#FF0000")
    }

    /// The second drop is a copy, not a second original: a shelf with two
    /// Buttons on it that do not follow each other is the thing components
    /// exist to prevent.
    @Test func droppingTheSameStarterTwiceMakesACopy() {
        var doc = document()
        doc.insertStarterComponent(.button, at: CGPoint(x: 200, y: 200))
        let second = doc.insertStarterComponent(.button, at: CGPoint(x: 500, y: 500))
        #expect(doc.mainComponents.count == 1)
        #expect(second != nil)
        #expect(doc.layer(id: second ?? UUID())?.isComponentInstance == true)
        #expect(doc.instanceCount(of: StarterComponent.button.componentID) == 1)
    }

    // MARK: - An ordinary component

    @Test func aDroppedStarterArrivesWithItsKnobs() {
        var doc = document()
        doc.insertStarterComponent(.card, at: centre)
        let knobs = doc.componentProperties(of: StarterComponent.card.componentID)
        #expect(knobs.map(\.name) == ["Title", "Body", "Picture"])
        #expect(knobs.map(\.kind) == [.text, .text, .visible])
    }

    @Test func aCopyOfAStarterTakesAnOverrideLikeAnyOther() {
        var doc = document()
        doc.insertStarterComponent(.button, at: CGPoint(x: 200, y: 200))
        guard let copy = doc.insertStarterComponent(.button, at: CGPoint(x: 500, y: 500)),
              let knob = doc.componentProperties(of: StarterComponent.button.componentID).first
        else { Issue.record("no copy or no knob"); return }
        let took = doc.setInstanceOverride(instance: copy, property: knob.id, value: .text("Save"))
        #expect(took)
        doc.syncComponentInstances()
        let wording = doc.layer(id: copy)?.selfAndDescendants.compactMap { layer -> String? in
            guard case .text(let text) = layer.content else { return nil }
            return text.string
        }
        #expect(wording == ["Save"])
    }

    @Test func aDroppedStarterCanBeTakenApart() {
        var doc = document()
        doc.insertStarterComponent(.button, at: CGPoint(x: 200, y: 200))
        guard let copy = doc.insertStarterComponent(.button, at: CGPoint(x: 500, y: 500))
        else { Issue.record("no copy"); return }
        #expect(doc.canDetachInstance(ids: [copy]))
        let detached = doc.detachInstance(id: copy)
        #expect(detached)
        #expect(doc.layer(id: copy)?.isComponentInstance == false)
        #expect(doc.layer(id: copy)?.children.count ?? 0 >= 2)
    }

    // MARK: - The shelf

    @Test func theShelfOffersEveryStarterInAFreshDocument() {
        let doc = document()
        let entries = doc.starterComponentEntries
        #expect(entries.count == StarterComponent.allCases.count)
        #expect(entries.allSatisfy { $0.scope == .components })
        #expect(entries.first?.detail == StarterComponents.shelfDetail)
    }

    /// One tile per component, not two: once the original is in the document,
    /// the document's own entry is the one that describes it.
    @Test func aStarterYouHaveTakenIsListedOnceByTheDocument() {
        var doc = document()
        doc.insertStarterComponent(.button, at: centre)
        #expect(doc.starterComponentEntries.count == StarterComponent.allCases.count - 1)
        #expect(!doc.starterComponentEntries.contains { $0.id == StarterComponent.button.componentID.uuidString })
        let mine = doc.componentLibraryEntries
        #expect(mine.count == 1)
        #expect(mine.first?.id == StarterComponent.button.componentID.uuidString)
        #expect(mine.first?.name == "Button")
    }

    // MARK: - Costing a document nothing until it is used

    @Test func aDocumentThatUsesNoneOfThemCarriesNoneOfThem() throws {
        let doc = document()
        let data = try JSONEncoder().encode(doc)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(!text.contains("colorStyles"))
        #expect(!text.contains("componentID"))
    }

    @Test func aDroppedStarterSurvivesASaveAndReopen() throws {
        var doc = document()
        doc.insertStarterComponent(.navBar, at: centre)
        let round = try JSONDecoder().decode(PhotonzDocument.self, from: JSONEncoder().encode(doc))
        #expect(round == doc)
        #expect(round.mainComponent(componentID: StarterComponent.navBar.componentID) != nil)
        #expect(round.componentProperties(of: StarterComponent.navBar.componentID).count == 2)
    }
}
