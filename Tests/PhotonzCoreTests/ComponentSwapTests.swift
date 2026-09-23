import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Pointing a copy already on the canvas at a DIFFERENT component
/// (`a-copy-on-the-canvas-can-be-pointed-at-a-differe`, answered on 2026-09-20
/// with "A row in the panel that says which one it is").
///
/// Before this, changing your mind about which component a copy is meant to be
/// cost you the copy: delete it, drag the other one out of the Library, and
/// type back every knob, every size and every bit of room you had set. On a
/// screen carrying twenty copies nobody does that, so the layout stops being
/// something you explore.
///
/// The contract the whole feature stands on, and the reason these tests are
/// written the way they are: **a copy keeps what is ITS OWN and follows the new
/// original for everything else.** Where it sits, a size it was given by hand,
/// a look it set for itself and any knob the new component also offers are the
/// copy's; everything else comes from the component it now follows.
struct ComponentSwapTests {

    private func document() -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 1400, height: 1400), pixelScale: 1)
    }

    private let drop = CGPoint(x: 400, y: 400)

    /// A document holding a copy of one starter, plus the original of another
    /// to point it at. The second starter is placed far away and its own copy
    /// deleted, so the only copy in the document is the one under test.
    private func documentWithBoth(_ first: StarterComponent,
                                  _ second: StarterComponent) -> (PhotonzDocument, UUID) {
        var doc = document()
        guard let copy = doc.insertStarterComponent(first, at: drop),
              let other = doc.insertStarterComponent(second, at: CGPoint(x: 1100, y: 1100))
        else { Issue.record("nothing placed"); return (doc, UUID()) }
        doc.removeLayers(ids: [other])
        return (doc, copy)
    }

    // MARK: - What it keeps

    @Test func aCopyCanBePointedAtAnotherComponent() {
        var (doc, copy) = documentWithBoth(.button, .badge)
        let report = doc.swapComponentInstances(ids: [copy], to: StarterComponent.badge.componentID)
        #expect(report?.copies == 1)
        #expect(doc.layer(id: copy)?.instanceOf == StarterComponent.badge.componentID)
        #expect(doc.instanceCount(of: StarterComponent.button.componentID) == 0)
        #expect(doc.instanceCount(of: StarterComponent.badge.componentID) == 1)
    }

    @Test func itStaysWhereItWasPut() {
        var (doc, copy) = documentWithBoth(.button, .badge)
        guard let before = doc.canvasBounds(of: copy) else { Issue.record("no box"); return }
        doc.swapComponentInstances(ids: [copy], to: StarterComponent.badge.componentID)
        guard let after = doc.canvasBounds(of: copy) else { Issue.record("no box"); return }
        #expect(abs(after.minX - before.minX) <= 0.5)
        #expect(abs(after.minY - before.minY) <= 0.5)
    }

    /// A knob both components offer, matched by the name on the panel, keeps
    /// the value the copy had typed. Card and Nav Bar both offer "Title".
    @Test func aKnobTheNewComponentAlsoHasKeepsItsValue() {
        var (doc, copy) = documentWithBoth(.card, .navBar)
        guard let title = doc.componentProperties(of: StarterComponent.card.componentID)
            .first(where: { $0.name == "Title" }) else { Issue.record("no Title knob"); return }
        let set = doc.setInstanceOverride(instance: copy, property: title.id, value: .text("Hello"))
        #expect(set)
        let report = doc.swapComponentInstances(ids: [copy], to: StarterComponent.navBar.componentID)
        #expect(report?.keptKnobs == 1)
        #expect(report?.droppedKnobs.isEmpty == true)
        guard let carried = doc.componentProperties(of: StarterComponent.navBar.componentID)
            .first(where: { $0.name == "Title" }) else { Issue.record("no Title knob"); return }
        #expect(doc.layer(id: copy)?.componentOverrides.first?.property == carried.id)
        #expect(doc.instanceValue(instance: copy, property: carried.id)?.textValue == "Hello")
    }

    /// The carried value is not just recorded, it is DRAWN: the copy says
    /// Hello after the swap, the way it did before.
    @Test func theCarriedValueIsWhatTheCopyShows() {
        var (doc, copy) = documentWithBoth(.card, .navBar)
        guard let title = doc.componentProperties(of: StarterComponent.card.componentID)
            .first(where: { $0.name == "Title" }) else { Issue.record("no Title knob"); return }
        doc.setInstanceOverride(instance: copy, property: title.id, value: .text("Hello"))
        doc.swapComponentInstances(ids: [copy], to: StarterComponent.navBar.componentID)
        let words = doc.layer(id: copy)?.selfAndDescendants.compactMap { $0.text?.string } ?? []
        #expect(words.contains("Hello"))
    }

    // MARK: - What it gives up, out loud

    @Test func aKnobTheNewComponentDoesNotHaveIsDroppedAndNamed() {
        var (doc, copy) = documentWithBoth(.button, .badge)
        guard let label = doc.componentProperties(of: StarterComponent.button.componentID)
            .first(where: { $0.name == "Label" }) else { Issue.record("no Label knob"); return }
        doc.setInstanceOverride(instance: copy, property: label.id, value: .text("Save"))
        let report = doc.swapComponentInstances(ids: [copy], to: StarterComponent.badge.componentID)
        #expect(report?.droppedKnobs == ["Label"])
        #expect(report?.keptKnobs == 0)
        #expect(doc.layer(id: copy)?.componentOverrides.isEmpty == true)
    }

    /// A knob the copy never answered is nothing to carry and nothing to
    /// mourn: only the answers a person typed are counted either way.
    @Test func aKnobNobodyAnsweredIsNotReported() {
        var (doc, copy) = documentWithBoth(.button, .badge)
        let report = doc.swapComponentInstances(ids: [copy], to: StarterComponent.badge.componentID)
        #expect(report?.keptKnobs == 0)
        #expect(report?.droppedKnobs.isEmpty == true)
    }

    // MARK: - Its size

    /// A size the copy was GIVEN is the copy's own answer, so it survives.
    @Test func aSizeTheCopyWasGivenSurvives() {
        var (doc, copy) = documentWithBoth(.button, .badge)
        doc.updateLayer(id: copy) { $0.setInstanceSize(InstanceSize(width: 320)) }
        doc.syncComponentInstances()
        doc.swapComponentInstances(ids: [copy], to: StarterComponent.badge.componentID)
        #expect(doc.layer(id: copy)?.group?.instanceSize?.usedWidth == 320)
        #expect(abs((doc.canvasBounds(of: copy)?.width ?? 0) - 320) <= 0.5)
    }

    /// A copy that never had a size of its own follows the NEW original's, the
    /// same way it followed the old one's. Freezing it at the old size would
    /// leave a badge stretched to the width of a button with no way to tell
    /// why.
    @Test func aCopyWithNoSizeOfItsOwnTakesTheNewOriginalSize() {
        var (doc, copy) = documentWithBoth(.button, .badge)
        guard let badge = doc.mainComponent(componentID: StarterComponent.badge.componentID),
              let badgeBox = doc.canvasBounds(of: badge.id) else { Issue.record("no badge"); return }
        doc.swapComponentInstances(ids: [copy], to: StarterComponent.badge.componentID)
        guard let after = doc.canvasBounds(of: copy) else { Issue.record("no box"); return }
        #expect(abs(after.width - badgeBox.width) <= 1)
        #expect(abs(after.height - badgeBox.height) <= 1)
    }

    // MARK: - Its name

    @Test func aCopyNobodyRenamedTakesTheNewComponentName() {
        var (doc, copy) = documentWithBoth(.button, .badge)
        #expect(doc.layer(id: copy)?.name == "Button")
        doc.swapComponentInstances(ids: [copy], to: StarterComponent.badge.componentID)
        #expect(doc.layer(id: copy)?.name == "Badge")
    }

    @Test func aCopyYouNamedYourselfKeepsItsName() {
        var (doc, copy) = documentWithBoth(.button, .badge)
        doc.updateLayer(id: copy) { $0.name = "Save button" }
        doc.swapComponentInstances(ids: [copy], to: StarterComponent.badge.componentID)
        #expect(doc.layer(id: copy)?.name == "Save button")
    }

    // MARK: - Undo

    @Test func oneUndoPutsTheCopyBackKnobsIncluded() {
        var (doc, copy) = documentWithBoth(.button, .badge)
        guard let label = doc.componentProperties(of: StarterComponent.button.componentID)
            .first(where: { $0.name == "Label" }) else { Issue.record("no Label knob"); return }
        doc.setInstanceOverride(instance: copy, property: label.id, value: .text("Save"))
        var history = History(document: doc)
        history.perform { $0.swapComponentInstances(ids: [copy], to: StarterComponent.badge.componentID) }
        #expect(history.current.layer(id: copy)?.instanceOf == StarterComponent.badge.componentID)
        history.undo()
        #expect(history.current.layer(id: copy)?.instanceOf == StarterComponent.button.componentID)
        #expect(history.current.instanceValue(instance: copy, property: label.id)?.textValue == "Save")
        #expect(history.current.layer(id: copy)?.name == "Button")
    }

    // MARK: - Where the copy lives

    @Test func aCopyInsideAGroupSwapsWithoutMovingWhatIsAroundIt() {
        var doc = document()
        guard let copy = doc.insertStarterComponent(.button, at: drop),
              let other = doc.insertStarterComponent(.badge, at: CGPoint(x: 1100, y: 1100))
        else { Issue.record("nothing placed"); return }
        doc.removeLayers(ids: [other])
        let neighbour = Layer(name: "Neighbour", content: .annotation(AnnotationContent(shape: .rectangle)),
                              frame: CGRect(x: 500, y: 500, width: 40, height: 40))
        doc.addLayer(neighbour)
        guard let group = doc.groupLayers(ids: [copy, neighbour.id], name: "Row")
        else { Issue.record("no group"); return }
        let before = doc.canvasBounds(of: neighbour.id)
        doc.swapComponentInstances(ids: [copy], to: StarterComponent.badge.componentID)
        #expect(doc.parentID(of: copy) == group.id)
        #expect(doc.layer(id: copy)?.instanceOf == StarterComponent.badge.componentID)
        #expect(doc.canvasBounds(of: neighbour.id) == before)
    }

    /// A copy sitting INSIDE another component is part of that component's
    /// drawing, so pointing it somewhere else reaches every copy of the
    /// component it lives in.
    @Test func aCopyInsideAnotherComponentSwapsAndEveryCopyOfItFollows() {
        var doc = document()
        guard let card = doc.insertStarterComponent(.card, at: drop),
              let button = doc.insertStarterComponent(.button, at: CGPoint(x: 900, y: 200)),
              let badge = doc.insertStarterComponent(.badge, at: CGPoint(x: 1200, y: 1200)),
              let cardMain = doc.mainComponent(componentID: StarterComponent.card.componentID)
        else { Issue.record("nothing placed"); return }
        doc.removeLayers(ids: [badge])
        // Put the button copy inside the card's ORIGINAL, so the card's copy
        // holds one too.
        let moved = doc.moveLayer(id: button, toGroup: cardMain.id)
        #expect(moved)
        doc.syncComponentInstances()
        guard let inside = doc.layer(id: card)?.children
            .first(where: { $0.instanceOf == StarterComponent.button.componentID })
        else { Issue.record("the card's copy holds no button"); return }
        _ = inside
        doc.swapComponentInstances(ids: [button], to: StarterComponent.badge.componentID)
        #expect(doc.layer(id: button)?.instanceOf == StarterComponent.badge.componentID)
        let followed = doc.layer(id: card)?.children
            .contains { $0.instanceOf == StarterComponent.badge.componentID }
        #expect(followed == true)
    }

    // MARK: - What it refuses

    @Test func aCopyCannotBePointedAtSomethingThatWouldHoldItself() {
        var doc = document()
        guard let card = doc.insertStarterComponent(.card, at: drop),
              let button = doc.insertStarterComponent(.button, at: CGPoint(x: 900, y: 200)),
              let cardMain = doc.mainComponent(componentID: StarterComponent.card.componentID)
        else { Issue.record("nothing placed"); return }
        _ = card
        let moved = doc.moveLayer(id: button, toGroup: cardMain.id)
        #expect(moved)
        // The button copy lives inside the Card original, so pointing it at
        // the Card would make the Card hold itself.
        let refused = doc.swapComponentInstances(ids: [button], to: StarterComponent.card.componentID)
        #expect(refused == nil)
        #expect(doc.layer(id: button)?.instanceOf == StarterComponent.button.componentID)
    }

    @Test func pointingACopyAtWhatItAlreadyFollowsDoesNothing() {
        var (doc, copy) = documentWithBoth(.button, .badge)
        let again = doc.swapComponentInstances(ids: [copy], to: StarterComponent.button.componentID)
        #expect(again == nil)
    }

    @Test func aLockedCopyIsLeftAlone() {
        var (doc, copy) = documentWithBoth(.button, .badge)
        doc.updateLayer(id: copy) { $0.isLocked = true }
        let locked = doc.swapComponentInstances(ids: [copy], to: StarterComponent.badge.componentID)
        #expect(locked == nil)
        #expect(doc.layer(id: copy)?.instanceOf == StarterComponent.button.componentID)
    }

    // MARK: - Several at once

    @Test func everyPickedCopyIsPointedAtItInOneStep() {
        var doc = document()
        guard let first = doc.insertStarterComponent(.button, at: drop),
              let second = doc.insertStarterComponent(.button, at: CGPoint(x: 700, y: 400)),
              let badge = doc.insertStarterComponent(.badge, at: CGPoint(x: 1200, y: 1200))
        else { Issue.record("nothing placed"); return }
        doc.removeLayers(ids: [badge])
        let report = doc.swapComponentInstances(ids: [first, second],
                                                to: StarterComponent.badge.componentID)
        #expect(report?.copies == 2)
        #expect(doc.instanceCount(of: StarterComponent.badge.componentID) == 2)
        #expect(doc.instanceCount(of: StarterComponent.button.componentID) == 0)
    }

    // MARK: - What the row offers

    @Test func theRowOffersEveryOtherComponentAndMarksTheCurrentOne() {
        var (doc, copy) = documentWithBoth(.button, .badge)
        let choices = doc.componentSwapChoices(instances: [copy])
        #expect(choices.map(\.name) == ["Badge", "Button"])
        #expect(choices.first(where: { $0.name == "Button" })?.isCurrent == true)
        #expect(choices.first(where: { $0.name == "Badge" })?.canTake == true)
    }

    @Test func aChoiceThatWouldLoopIsOfferedButCannotBeTaken() {
        var doc = document()
        guard let button = doc.insertStarterComponent(.button, at: drop),
              doc.insertStarterComponent(.card, at: CGPoint(x: 900, y: 200)) != nil,
              let cardMain = doc.mainComponent(componentID: StarterComponent.card.componentID)
        else { Issue.record("nothing placed"); return }
        let moved = doc.moveLayer(id: button, toGroup: cardMain.id)
        #expect(moved)
        let choices = doc.componentSwapChoices(instances: [button])
        #expect(choices.first(where: { $0.name == "Card" })?.canTake == false)
    }
}

/// A guard on the tests above rather than on the app: if Button and Badge were
/// the same size, the size tests would pass without proving anything.
struct ComponentSwapFixtureTests {
    @Test func theTwoStartersUsedInTheSizeTestsAreNotTheSameSize() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1400, height: 1400), pixelScale: 1)
        doc.insertStarterComponent(.button, at: CGPoint(x: 300, y: 300))
        doc.insertStarterComponent(.badge, at: CGPoint(x: 900, y: 900))
        let button = doc.mainComponent(componentID: StarterComponent.button.componentID)
        let badge = doc.mainComponent(componentID: StarterComponent.badge.componentID)
        let buttonBox = button.flatMap { doc.canvasBounds(of: $0.id) }
        let badgeBox = badge.flatMap { doc.canvasBounds(of: $0.id) }
        #expect((buttonBox?.width ?? 0) > (badgeBox?.width ?? 0) + 2)
    }
}
