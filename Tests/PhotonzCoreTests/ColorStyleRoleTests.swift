import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// What a saved color is FOR, and why a color row only offers some of them.
///
/// Reported by the user on 2026-09-03: every color row offered every saved
/// color, so a color made for hairlines was on the menu as something to fill a
/// box with.
struct ColorStyleRoleTests {

    // MARK: - Fixtures

    private func box(fill: String? = "#3366FF", stroke: String = "#101010") -> Layer {
        var annotation = AnnotationContent(shape: .rectangle, start: .zero,
                                           end: CGPoint(x: 60, y: 30))
        annotation.colorHex = stroke
        annotation.fillColorHex = fill
        return Layer(name: "Box", content: .annotation(annotation),
                     frame: CGRect(x: 0, y: 0, width: 60, height: 30))
    }

    private func text(_ color: String = "#FFFFFF") -> Layer {
        Layer(name: "Label", content: .text(TextContent(string: "Hi", colorHex: color)),
              frame: CGRect(x: 0, y: 0, width: 40, height: 20))
    }

    private func document(_ layers: [Layer]) -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 400, height: 400), layers: layers)
    }

    // MARK: - Which slot takes which kind of paint

    @Test func anOutlineAndALetterAreBothInk() {
        #expect(ColorSlot.stroke.styleRole == .ink)
        #expect(ColorSlot.text.styleRole == .ink)
    }

    @Test func anInsideAndASurfaceAreBothSurface() {
        #expect(ColorSlot.fill.styleRole == .surface)
    }

    @Test func everyRoleSaysWhatItIsInPlainWords() {
        #expect(ColorStyleRole.ink.title == "Outlines and text")
        #expect(ColorStyleRole.surface.title == "Fills and backgrounds")
    }

    // MARK: - Saving records what it was saved from

    @Test func savingFromAnOutlineMakesAnInkColor() {
        var doc = document([box()])
        let id = doc.saveColorStyle(from: doc.layers[0].id, slot: .stroke, name: "Hairline")!
        #expect(doc.colorStyle(id: id)?.roles == [.ink])
    }

    @Test func savingFromAnInsideMakesASurfaceColor() {
        var doc = document([box()])
        let id = doc.saveColorStyle(from: doc.layers[0].id, slot: .fill, name: "Card")!
        #expect(doc.colorStyle(id: id)?.roles == [.surface])
    }

    @Test func savingFromTextMakesAnInkColor() {
        var doc = document([text()])
        let id = doc.saveColorStyle(from: doc.layers[0].id, slot: .text, name: "Body")!
        #expect(doc.colorStyle(id: id)?.roles == [.ink])
    }

    // MARK: - A row only offers the colors that belong in it

    @Test func anInkColorIsNotOfferedAsSomethingToFillWith() {
        var doc = document([box()])
        let hairline = doc.saveColorStyle(from: doc.layers[0].id, slot: .stroke,
                                          name: "Hairline")!
        #expect(doc.colorStyles(for: .fill).map(\.id).contains(hairline) == false)
        #expect(doc.colorStyles(for: .stroke).map(\.id) == [hairline])
    }

    @Test func aSurfaceColorIsNotOfferedForAnOutline() {
        var doc = document([box()])
        let card = doc.saveColorStyle(from: doc.layers[0].id, slot: .fill, name: "Card")!
        #expect(doc.colorStyles(for: .stroke).map(\.id).contains(card) == false)
        #expect(doc.colorStyles(for: .fill).map(\.id) == [card])
    }

    @Test func anInkColorIsOfferedOnOutlinesAndOnText() {
        var doc = document([box(), text()])
        let ink = doc.saveColorStyle(from: doc.layers[0].id, slot: .stroke, name: "Ink")!
        #expect(doc.colorStyles(for: .stroke).map(\.id) == [ink])
        #expect(doc.colorStyles(for: .text).map(\.id) == [ink])
    }

    @Test func theRowsKeepTheShelfsOrder() {
        var doc = document([box(), box()])
        let first = doc.saveColorStyle(from: doc.layers[0].id, slot: .stroke, name: "A")!
        let second = doc.saveColorStyle(from: doc.layers[1].id, slot: .stroke, name: "B")!
        #expect(doc.colorStyles(for: .stroke).map(\.id) == [first, second])
    }

    // MARK: - Widening one by hand

    @Test func aColorCanBeSetToServeBothParts() {
        var doc = document([box()])
        let id = doc.saveColorStyle(from: doc.layers[0].id, slot: .stroke, name: "Accent")!
        doc.setColorStyleRoles(id: id, roles: [.ink, .surface])
        #expect(doc.colorStyles(for: .fill).map(\.id) == [id])
        #expect(doc.colorStyles(for: .stroke).map(\.id) == [id])
    }

    @Test func tickingNothingIsRefusedSoAColorNeverVanishes() {
        var doc = document([box()])
        let id = doc.saveColorStyle(from: doc.layers[0].id, slot: .stroke, name: "Accent")!
        doc.setColorStyleRoles(id: id, roles: [])
        #expect(doc.colorStyle(id: id)?.roles == [.ink])
        #expect(doc.colorStyles(for: .stroke).map(\.id) == [id])
    }

    @Test func rolesAreKeptInOneOrderWithoutRepeats() {
        var doc = document([box()])
        let id = doc.saveColorStyle(from: doc.layers[0].id, slot: .stroke, name: "Accent")!
        doc.setColorStyleRoles(id: id, roles: [.surface, .ink, .surface])
        #expect(doc.colorStyle(id: id)?.roles == [.ink, .surface])
    }

    @Test func changingWhatAColorIsForRepaintsNothing() {
        var doc = document([box(fill: "#3366FF", stroke: "#101010")])
        let id = doc.saveColorStyle(from: doc.layers[0].id, slot: .stroke, name: "Accent")!
        doc.setColorStyleRoles(id: id, roles: [.ink, .surface])
        #expect(doc.layers[0].colorHex(for: .stroke) == "#101010")
        #expect(doc.layers[0].colorHex(for: .fill) == "#3366FF")
    }

    // MARK: - Colors saved before any of this existed

    @Test func aColorThatHasNeverSaidIsOfferedEverywhere() {
        var doc = document([box()])
        let id = doc.addColorStyle(name: "Old", colorHex: "#ABCDEF")
        #expect(doc.colorStyle(id: id)?.roles == nil)
        #expect(doc.colorStyles(for: .fill).map(\.id) == [id])
        #expect(doc.colorStyles(for: .stroke).map(\.id) == [id])
        #expect(doc.effectiveColorStyleRoles(id: id) == ColorStyleRole.allCases)
    }

    @Test func aColorThatHasNeverSaidTakesTheRolesItIsAlreadyPainting() {
        var doc = document([box(), text()])
        let id = doc.addColorStyle(name: "Old", colorHex: "#ABCDEF")
        _ = doc.bindColorStyle(layerID: doc.layers[0].id, slot: .fill, styleID: id)
        #expect(doc.effectiveColorStyleRoles(id: id) == [.surface])
        #expect(doc.colorStyles(for: .stroke).isEmpty)
        #expect(doc.colorStyles(for: .fill).map(\.id) == [id])
    }

    @Test func oneOfTheAppsOwnFiveKeepsWhatTheAppMadeItFor() {
        var doc = document([box()])
        // The way a document that predates roles holds Border: right id, no
        // roles written down.
        doc.colorStyles = [ColorStyle(id: StarterStyle.border.styleID,
                                      name: StarterStyle.border.name,
                                      colorHex: StarterStyle.border.colorHex)]
        #expect(doc.effectiveColorStyleRoles(id: StarterStyle.border.styleID) == [.ink])
        #expect(doc.colorStyles(for: .fill).isEmpty)
    }

    @Test func aStyleThatIsNotThereIsForNothing() {
        let doc = document([box()])
        #expect(doc.effectiveColorStyleRoles(id: UUID()).isEmpty)
    }

    // MARK: - The app's own five

    @Test func theAppsOwnFiveEachSayWhatTheyAreFor() {
        #expect(StarterStyle.accent.roles == [.ink, .surface])
        #expect(StarterStyle.surface.roles == [.surface])
        #expect(StarterStyle.text.roles == [.ink])
        #expect(StarterStyle.muted.roles == [.ink])
        #expect(StarterStyle.border.roles == [.ink])
        for starter in StarterStyle.allCases {
            #expect(starter.colorStyle.roles == starter.roles)
        }
    }

    /// The complaint that started this, as a document: with the app's own five
    /// on the shelf, a rectangle's two rows offer different lists, and neither
    /// offers a color meant for the other part.
    @Test func aRectanglesTwoRowsOfferDifferentLists() {
        var doc = document([box()])
        doc.colorStyles = StarterStyle.allCases.map(\.colorStyle)
        #expect(doc.colorStyles(for: .stroke).map(\.name) == ["Accent", "Text", "Muted", "Border"])
        #expect(doc.colorStyles(for: .fill).map(\.name) == ["Accent", "Surface"])
    }

    // MARK: - On disk

    @Test func whatAColorIsForSurvivesARoundTrip() throws {
        let style = ColorStyle(name: "Accent", colorHex: "#3B7DF5", roles: [.ink, .surface])
        let data = try JSONEncoder().encode(style)
        #expect(try JSONDecoder().decode(ColorStyle.self, from: data) == style)
    }

    @Test func aColorWrittenBeforeRolesExistedStillReads() throws {
        let json = "{\"id\":\"\(UUID().uuidString)\",\"name\":\"Old\","
            + "\"colorHex\":\"#ABCDEF\"}"
        let style = try JSONDecoder().decode(ColorStyle.self, from: Data(json.utf8))
        #expect(style.roles == nil)
        #expect(style.suits(.fill))
        #expect(style.suits(.stroke))
    }

    @Test func aColorThatIsForNothingIsNeverWritten() throws {
        let style = ColorStyle(name: "Odd", colorHex: "#ABCDEF", roles: [])
        #expect(style.roles == nil)
        let text = String(decoding: try JSONEncoder().encode(style), as: UTF8.self)
        #expect(!text.contains("roles"))
    }
}
