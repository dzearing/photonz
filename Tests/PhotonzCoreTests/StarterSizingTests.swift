import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// What each starter is the size of (`docs/design/ui-building.md`, "Every
/// starter says what it is the size of").
///
/// The button and the badge already closed around their words. These are the
/// other three: a card that grows downward when its title gets longer, a bar
/// that holds its width and keeps its title in the middle of it, and a field
/// that holds its width and wraps its placeholder inside the box rather than
/// letting it run out of the right-hand edge.
@Suite("Every starter says what it is the size of")
struct StarterSizingTests {

    private func document() -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 900, height: 700))
    }

    private func piece(_ layer: Layer?, _ name: String) -> Layer? {
        layer?.children.first { $0.name == name }
    }

    /// Where the WORDS are, which is the box without the slack a measured text
    /// box carries on its far edges.
    private func words(_ layer: Layer?) -> CGRect {
        guard let layer else { return .null }
        return CGRect(x: layer.frame.minX, y: layer.frame.minY,
                      width: layer.frame.width - TextMeasurement.slack,
                      height: layer.frame.height - TextMeasurement.slack)
    }

    /// Re-words a piece the way typing over it on the canvas does: the words
    /// change, the box re-measures, and the group it is in flows again.
    private func reword(_ history: inout History, _ id: UUID, _ string: String,
                        anchor: HorizontalPlacement) {
        history.perform { doc in
            doc.updateLayer(id: id) { layer in
                guard case .text(var content) = layer.content else { return }
                let hugging = layer.textHugsItsWords
                content.string = string
                layer.content = .text(content)
                layer = layer.textRefitted(hugging: hugging, anchor: anchor)
            }
        }
    }

    // MARK: - The card

    /// The complaint: a long card title ran past the edge of the card. Now the
    /// title wraps inside the card's room and the card gets taller to hold it.
    @Test("A longer card title makes the card taller, and never wider")
    func aLongerTitleGrowsTheCardDownward() {
        var history = History(document: document())
        var cardID: UUID?
        history.perform { cardID = $0.insertStarterComponent(.card, at: CGPoint(x: 400, y: 300)) }
        guard let cardID, let before = history.current.layer(id: cardID),
              let title = piece(before, "Title"), let body = piece(before, "Body")
        else { Issue.record("no card"); return }
        let room = before.group?.layout?.usedPadding ?? .none
        #expect(before.group?.layout?.hugsWidth == false)
        #expect(before.group?.layout?.hugsHeight == true)

        reword(&history, title.id, "A title long enough that it cannot possibly "
               + "fit on one line inside this card", anchor: .stretch)

        guard let after = history.current.layer(id: cardID),
              let grown = piece(after, "Title"), let moved = piece(after, "Body")
        else { Issue.record("the card lost a piece"); return }
        // Wider is exactly what it must NOT get: a card is 260 because that is
        // the card.
        #expect(after.localBounds.width == before.localBounds.width)
        #expect(after.localBounds.height > before.localBounds.height)
        // The words wrapped inside the room the card keeps, rather than
        // running out past its right-hand edge.
        #expect(grown.frame.minX == room.left)
        #expect(words(grown).maxX <= after.localBounds.width - room.right + 0.01)
        #expect(grown.frame.height > title.frame.height)
        // The line under it came down by what the title gained instead of
        // being written over.
        #expect(moved.frame.minY > body.frame.minY)
        #expect(moved.frame.minY >= grown.frame.maxY)
        // ...and the card still keeps its room under that last line.
        #expect(after.localBounds.height - words(moved).maxY == room.bottom)
    }

    /// The same for the supporting line, and the same for a COPY answering its
    /// knob rather than the original being typed over.
    @Test("A copy told to say more grows too, and only the copy")
    func aCopyGrowsWithItsOwnWording() {
        var history = History(document: document())
        var mainID: UUID?
        history.perform { mainID = $0.insertStarterComponent(.card, at: CGPoint(x: 250, y: 200)) }
        var copyID: UUID?
        history.perform {
            copyID = $0.insertComponentInstance(of: StarterComponent.card.componentID,
                                                at: CGPoint(x: 650, y: 200))
        }
        guard let mainID, let copyID,
              let knob = history.current.instanceProperties(instance: copyID)
                  .first(where: { $0.name == "Body" })
        else { Issue.record("no copy with a Body knob"); return }
        let before = history.current.layer(id: copyID)?.localBounds ?? .null
        history.perform {
            $0.setInstanceOverride(instance: copyID, property: knob.id,
                                   value: .text("Supporting text that carries on for long "
                                                + "enough to need a second and a third line."))
        }
        guard let copy = history.current.layer(id: copyID) else { Issue.record("copy gone"); return }
        #expect(copy.localBounds.width == before.width)
        #expect(copy.localBounds.height > before.height)
        #expect(copy.children.first { $0.name == "Background" }?.frame
                == CGRect(origin: .zero, size: copy.localBounds.size))
        // The original was never asked, so it is the size it was.
        #expect(history.current.layer(id: mainID)?.localBounds.height == before.height)
    }

    /// The picture is a well inside the card, not the surface behind it. Both
    /// it and the background used to say "stretch both ways", which the
    /// container rules read as "I am the box", so the well would have covered
    /// the whole card.
    @Test("A card's picture is a well inside it, not the card itself")
    func thePictureIsAWellNotTheSurface() {
        let card = StarterComponents.layer(.card)
        let room = card.group?.layout?.usedPadding ?? .none
        guard let picture = piece(card, "Picture"),
              let background = piece(card, "Background") else {
            Issue.record("no card pieces")
            return
        }
        #expect(background.frame == CGRect(origin: .zero, size: card.localBounds.size))
        #expect(picture.frame.minX == room.left)
        #expect(picture.frame.width == card.localBounds.width - room.horizontal)
        #expect(picture.frame.height < card.localBounds.height)
    }

    /// A card reads as one thing only if the air in it is even. The gap it is
    /// built with has to mean the space between what a person can see, so the
    /// step from the picture to the title looks like the step from the title
    /// to the line under it.
    @Test("A card breathes evenly: picture to title is the same air as title to body")
    func theCardBreathesEvenly() {
        let card = StarterComponents.layer(.card)
        let gap = card.group?.layout?.usedGap ?? 0
        guard let picture = piece(card, "Picture"), let title = piece(card, "Title"),
              let body = piece(card, "Body") else {
            Issue.record("no card pieces")
            return
        }
        #expect(gap > 0)
        #expect(title.frame.minY - picture.frame.maxY == gap)
        #expect(body.frame.minY - words(title).maxY == gap)
        #expect(card.localBounds.maxY - words(body).maxY
                == (card.group?.layout?.usedPadding.bottom ?? 0))
    }

    /// Hiding the picture closes the space it held rather than leaving a gap:
    /// the show-or-hide knob is worth having because the card re-packs.
    @Test("Hiding a card's picture closes the space it held")
    func hidingThePictureShortensTheCard() {
        var history = History(document: document())
        var cardID: UUID?
        history.perform { cardID = $0.insertStarterComponent(.card, at: CGPoint(x: 400, y: 300)) }
        guard let cardID, let card = history.current.layer(id: cardID),
              let picture = piece(card, "Picture"), let title = piece(card, "Title")
        else { Issue.record("no card"); return }
        let before = card.localBounds.height
        history.perform { $0.updateLayer(id: picture.id) { $0.isVisible = false } }
        guard let after = history.current.layer(id: cardID),
              let raised = piece(after, "Title") else { Issue.record("no card"); return }
        #expect(after.localBounds.height < before)
        #expect(raised.frame.minY < title.frame.minY)
    }

    // MARK: - The nav bar

    @Test("A longer nav bar title stays centred and does not widen the bar")
    func theBarHoldsItsWidthAndCentresItsTitle() {
        // The bar is a ROW, and its title is not one of the things the row
        // lines up: it spans the bar and centres its words on the whole of it,
        // so a longer title re-centres in place rather than growing sideways
        // out of a box that was only as wide as the old words
        // (`GroupChromeTests`).
        var history = History(document: document())
        var barID: UUID?
        history.perform { barID = $0.insertStarterComponent(.navBar, at: CGPoint(x: 400, y: 300)) }
        guard let barID, let before = history.current.layer(id: barID),
              let title = piece(before, "Title") else { Issue.record("no bar"); return }
        #expect(before.group?.layout?.hugsWidth == false)
        #expect(before.group?.layout?.hugsHeight == false)
        #expect(abs(words(title).midX - before.localBounds.width / 2) <= 1)

        reword(&history, title.id, "Notifications and alerts", anchor: .center)

        guard let after = history.current.layer(id: barID),
              let grown = piece(after, "Title") else { Issue.record("no bar"); return }
        #expect(after.localBounds.size == before.localBounds.size)
        #expect(words(grown).width == after.localBounds.width)
        #expect(abs(words(grown).midX - after.localBounds.width / 2) <= 1)
        // The hairline still spans the bar and still hugs the bottom of it.
        guard let divider = piece(after, "Divider") else { Issue.record("no divider"); return }
        #expect(divider.frame.width == after.localBounds.width)
        #expect(divider.frame.maxY == after.localBounds.height)
    }

    // MARK: - The text field

    @Test("A field holds its width and keeps its placeholder inside the box")
    func theFieldHoldsItsWidthAndWrapsItsPlaceholder() {
        var history = History(document: document())
        var fieldID: UUID?
        history.perform { fieldID = $0.insertStarterComponent(.textField, at: CGPoint(x: 400, y: 300)) }
        guard let fieldID, let before = history.current.layer(id: fieldID),
              let placeholder = piece(before, "Placeholder")
        else { Issue.record("no field"); return }
        let room = before.group?.layout?.usedPadding ?? .none
        #expect(before.group?.layout?.hugsWidth == false)
        #expect(before.group?.layout?.hugsHeight == true)
        // The wording sits in from the left by the room the field keeps, and
        // reaches the room on the other side rather than its own last letter.
        #expect(placeholder.frame.minX == room.left)
        #expect(words(placeholder).width == before.localBounds.width - room.horizontal)

        reword(&history, placeholder.id,
               "Search for anything at all in this document", anchor: .stretch)

        guard let after = history.current.layer(id: fieldID),
              let wrapped = piece(after, "Placeholder") else { Issue.record("no field"); return }
        #expect(after.localBounds.width == before.localBounds.width)
        #expect(words(wrapped).maxX <= after.localBounds.width - room.right + 0.01)
        #expect(after.localBounds.height >= before.localBounds.height)
        // The box around it grew by exactly what the words grew by.
        #expect(after.localBounds.height
                == room.vertical + wrapped.frame.height - TextMeasurement.slack)
        guard let background = piece(after, "Background") else { Issue.record("no fill"); return }
        #expect(background.frame == CGRect(origin: .zero, size: after.localBounds.size))
    }

    // MARK: - Saying so

    /// One plain sentence each, and it cannot drift: it is written from the
    /// layout the starter is actually built with.
    @Test("Every starter says which side is its contents and which is a number")
    func everyStarterSaysWhatItIsTheSizeOf() {
        let said = Dictionary(uniqueKeysWithValues:
            StarterComponent.allCases.map { ($0, $0.sizing) })
        for (kind, sentence) in said {
            #expect(!sentence.isEmpty, "\(kind.name) says nothing")
            #expect(sentence.hasSuffix("."), "\(kind.name): \(sentence)")
            // One sentence, not a paragraph.
            #expect(sentence.filter { $0 == "." }.count == 1, "\(kind.name): \(sentence)")
            let layout = StarterComponents.layout(kind)
            let hugsWidth = layout?.hugsWidth ?? true
            let hugsHeight = layout?.hugsHeight ?? true
            #expect(sentence.contains("wide") && sentence.contains("tall"),
                    "\(kind.name) does not name both sides: \(sentence)")
            // A side that is a number says the number; a side that is its
            // contents never does.
            if let width = layout?.usedWidth {
                #expect(sentence.contains("\(Int(width)) points wide"), "\(kind.name): \(sentence)")
            }
            if let height = layout?.usedHeight {
                #expect(sentence.contains("\(Int(height)) "), "\(kind.name): \(sentence)")
            }
            #expect(hugsWidth == sentence.contains("As wide as"), "\(kind.name): \(sentence)")
            #expect(hugsHeight == sentence.contains("as tall as"), "\(kind.name): \(sentence)")
        }
        // The two the last change was about, spelled out, so a rewrite that
        // quietly turns a card into something else fails here.
        #expect(said[.button] == "As wide as its label with the room either side, "
                + "and 36 points tall.")
        #expect(said[.card] == "260 points wide, and as tall as everything on it "
                + "with the room above and below.")
        #expect(said[.navBar] == "A box 320 points wide and 48 points tall.")
    }
}
