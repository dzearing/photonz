import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A tool holding a saved colour lets go of it in two places, and both of them
/// used to be silent.
///
/// The first is picking a plain colour while the tool is holding a name: that
/// is what picking a plain colour has always meant, but nothing on screen said
/// so at the moment it happened, so the next shape came out a colour of its own
/// and the person still thought they were drawing Accent.
///
/// The second is drawing in a document that has never heard of the name. What a
/// tool holds is a preference and a saved colour lives inside ONE document, so
/// the shape quietly came out the flat colour the tool remembers beside the
/// name. Also true, also silent.
///
/// Both now hand the app a sentence to say. The wording lives here rather than
/// in the view so it can be read without running the app.
struct ToolColorStyleNoticeTests {

    // MARK: - Fixtures

    private func document(_ layers: [Layer] = []) -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 400, height: 400), layers: layers)
    }

    /// A drag's worth of new shape, built the way the canvas builds one.
    private func drawn(_ tool: Tool, with styles: AnnotationStyles) -> Layer? {
        guard let content = styles.content(for: tool) else { return nil }
        return AnnotationBuilder.layer(content: content, from: .zero,
                                       to: CGPoint(x: 80, y: 40))
    }

    // MARK: - Picking a plain colour lets go of the name

    @Test func pickingAPlainColourWhileHoldingANameHasSomethingToSay() throws {
        var styles = AnnotationStyles()
        let accent = UUID()
        styles.arm(Paint(hex: "#B0184A"), styleID: accent, name: "Accent",
                   slot: .stroke, forShape: .arrow)

        let notice = try #require(styles.lettingGoOfColorStyle(slot: .stroke, forShape: .arrow))
        #expect(notice.kind == .letGo)
        #expect(notice.styleID == accent)
        #expect(notice.title == "Stopped following")
        #expect(notice.detail == "The Arrow tool no longer follows Accent")
    }

    @Test func aToolHoldingAPlainColourHasNothingToSay() {
        var styles = AnnotationStyles()
        styles.setPaint(Paint(hex: "#3366FF"), forShape: .arrow)
        #expect(styles.lettingGoOfColorStyle(slot: .stroke, forShape: .arrow) == nil)
    }

    @Test func theSentenceIsSaidOnceBecauseThereIsNothingLeftToLetGoOf() {
        var styles = AnnotationStyles()
        styles.arm(Paint(hex: "#B0184A"), styleID: UUID(), name: "Accent",
                   slot: .stroke, forShape: .arrow)
        #expect(styles.lettingGoOfColorStyle(slot: .stroke, forShape: .arrow) != nil)

        // The pick itself. Painting a slot IS how the name comes off, so a
        // second pull of the same picker has nothing to announce.
        styles.setPaint(Paint(hex: "#3366FF"), forShape: .arrow)
        #expect(styles.lettingGoOfColorStyle(slot: .stroke, forShape: .arrow) == nil)
    }

    @Test func onlyTheSlotBeingPaintedLetsGo() throws {
        var styles = AnnotationStyles()
        styles.arm(Paint(hex: "#B0184A"), styleID: UUID(), name: "Accent",
                   slot: .fill, forShape: .rectangle)
        styles.arm(Paint(hex: "#101010"), styleID: UUID(), name: "Hairline",
                   slot: .stroke, forShape: .rectangle)

        let inside = try #require(styles.lettingGoOfColorStyle(slot: .fill, forShape: .rectangle))
        #expect(inside.detail == "The Rectangle tool no longer follows Accent")
        let outline = try #require(styles.lettingGoOfColorStyle(slot: .stroke, forShape: .rectangle))
        #expect(outline.detail == "The Rectangle tool no longer follows Hairline")
    }

    @Test func takingTheInsideAwayEntirelyAlsoLetsGo() throws {
        var styles = AnnotationStyles()
        styles.arm(Paint(hex: "#B0184A"), styleID: UUID(), name: "Accent",
                   slot: .fill, forShape: .rectangle)
        // "No fill" is a pick like any other: the box stops being Accent.
        let notice = try #require(styles.lettingGoOfColorStyle(slot: .fill, forShape: .rectangle))
        #expect(notice.detail == "The Rectangle tool no longer follows Accent")
        styles.setFillPaint(nil, forShape: .rectangle)
        #expect(styles.lettingGoOfColorStyle(slot: .fill, forShape: .rectangle) == nil)
    }

    // MARK: - A name that cannot come with the tool

    @Test func drawingWhereTheNameDoesNotExistHasSomethingToSay() throws {
        let doc = document()
        var styles = AnnotationStyles()
        let accent = UUID()
        styles.arm(Paint(hex: "#B0184A"), styleID: accent, name: "Accent",
                   slot: .stroke, forShape: .arrow)

        let shape = try #require(drawn(.arrow, with: styles))
        let notice = try #require(doc.armedColorStyleLeftBehind(shape, styles: styles))
        #expect(notice.kind == .notInThisDocument)
        #expect(notice.styleID == accent)
        #expect(notice.title == "No Accent here")
        #expect(notice.detail == "The Arrow is the plain color the tool remembers, not a saved color")
    }

    @Test func drawingWhereTheNameExistsSaysNothing() throws {
        var doc = document()
        var styles = AnnotationStyles()
        let accent = doc.addColorStyle(name: "Accent", colorHex: "#B0184A", roles: [.ink])
        styles.arm(Paint(hex: "#B0184A"), styleID: accent, name: "Accent",
                   slot: .stroke, forShape: .arrow)

        let shape = try #require(drawn(.arrow, with: styles))
        #expect(doc.armedColorStyleLeftBehind(shape, styles: styles) == nil)
    }

    @Test func aToolHoldingNoNameSaysNothingWhereverItDraws() throws {
        let doc = document()
        let styles = AnnotationStyles()
        let shape = try #require(drawn(.rectangle, with: styles))
        #expect(doc.armedColorStyleLeftBehind(shape, styles: styles) == nil)
    }

    @Test func theShapeAndTheNameAreBothInTheSentence() throws {
        let doc = document()
        var styles = AnnotationStyles()
        styles.arm(Paint(hex: "#B0184A"), styleID: UUID(), name: "Surface",
                   slot: .fill, forShape: .rectangle)

        let shape = try #require(drawn(.rectangle, with: styles))
        let notice = try #require(doc.armedColorStyleLeftBehind(shape, styles: styles))
        #expect(notice.title == "No Surface here")
        // Which PART came out plain, not just which shape: a box has two
        // colours and only one of them lost a name.
        #expect(notice.detail
                == "The Rectangle\u{2019}s inside is the plain color the tool remembers, not a saved color")
    }

    /// A box whose inside and outline both hold names this document has never
    /// heard of is one thing that just happened, not two: the pill has one line.
    @Test func aShapeWithTwoLostNamesLeadsWithTheFirstOne() throws {
        let doc = document()
        var styles = AnnotationStyles()
        styles.arm(Paint(hex: "#B0184A"), styleID: UUID(), name: "Surface",
                   slot: .fill, forShape: .rectangle)
        styles.arm(Paint(hex: "#101010"), styleID: UUID(), name: "Hairline",
                   slot: .stroke, forShape: .rectangle)

        let shape = try #require(drawn(.rectangle, with: styles))
        let notice = try #require(doc.armedColorStyleLeftBehind(shape, styles: styles))
        #expect(notice.title == "No Surface here")
    }

    // MARK: - The name the tool remembers

    @Test func theNameIsRememberedBesideTheIdBecauseTheDocumentCannotSupplyIt() {
        var styles = AnnotationStyles()
        let accent = UUID()
        styles.arm(Paint(hex: "#B0184A"), styleID: accent, name: "Accent",
                   slot: .stroke, forShape: .arrow)
        #expect(styles.heldColorStyleName(accent) == "Accent")
    }

    @Test func theRememberedNameSurvivesALaunch() throws {
        var styles = AnnotationStyles()
        let accent = UUID()
        styles.arm(Paint(hex: "#B0184A"), styleID: accent, name: "Accent",
                   slot: .stroke, forShape: .arrow)

        let data = try JSONEncoder().encode(styles)
        let read = try JSONDecoder().decode(AnnotationStyles.self, from: data)
        #expect(read.heldColorStyleName(accent) == "Accent")
        #expect(read.lettingGoOfColorStyle(slot: .stroke, forShape: .arrow)?.detail
                == "The Arrow tool no longer follows Accent")
    }

    @Test func theRememberedNameGoesWhenTheLastToolHoldingItLetsGo() {
        var styles = AnnotationStyles()
        let accent = UUID()
        styles.arm(Paint(hex: "#B0184A"), styleID: accent, name: "Accent",
                   slot: .stroke, forShape: .arrow)
        styles.arm(Paint(hex: "#B0184A"), styleID: accent, name: "Accent",
                   slot: .stroke, forShape: .line)

        styles.setPaint(Paint(hex: "#3366FF"), forShape: .arrow)
        // The line tool still holds it, so the name is still needed.
        #expect(styles.heldColorStyleName(accent) == "Accent")
        styles.setPaint(Paint(hex: "#3366FF"), forShape: .line)
        #expect(styles.heldColorStyleName(accent) == nil)
    }

    /// Prefs written before names were remembered hold an id and nothing else.
    /// The sentence still has to work: it just cannot say which colour.
    @Test func aNameTheToolNeverLearnedStillGetsASentence() throws {
        let doc = document()
        var styles = AnnotationStyles()
        styles.arm(Paint(hex: "#B0184A"), styleID: UUID(), slot: .stroke, forShape: .arrow)

        let letGo = try #require(styles.lettingGoOfColorStyle(slot: .stroke, forShape: .arrow))
        #expect(letGo.detail == "The Arrow tool no longer follows the saved color it was holding")

        let shape = try #require(drawn(.arrow, with: styles))
        let missing = try #require(doc.armedColorStyleLeftBehind(shape, styles: styles))
        #expect(missing.title == "Saved color left behind")
    }

    // MARK: - Where each one is said

    /// Drawing happens on the canvas, so that one takes the canvas pill.
    @Test func thePillSaysWhatTheNoticeSays() {
        let notice = ToolColorStyleNotice(kind: .notInThisDocument, styleID: UUID(),
                                          name: "Accent", shape: .arrow, slot: .stroke)
        let pill = CopyConfirmation(subject: .toolColorStyle(notice), shownAt: Date())
        #expect(pill.title == "No Accent here")
        #expect(pill.detail
                == "The Arrow is the plain color the tool remembers, not a saved color")
        // Long enough to read a sentence naming two things, like every other
        // notice about a link that let go.
        #expect(pill.lifetime == CopyConfirmation.breakLifetime)
    }

    /// Letting go happens inside an open picker, which covers the pill, so that
    /// one takes the row the Using line was in — and a row holds one short line
    /// rather than a verdict over a sentence.
    @Test func theRowGetsOneShortLine() {
        var styles = AnnotationStyles()
        styles.arm(Paint(hex: "#B0184A"), styleID: UUID(), name: "Accent",
                   slot: .stroke, forShape: .arrow)
        #expect(styles.lettingGoOfColorStyle(slot: .stroke, forShape: .arrow)?.line
                == "Let go of Accent")

        var unnamed = AnnotationStyles()
        unnamed.arm(Paint(hex: "#B0184A"), styleID: UUID(), slot: .stroke, forShape: .line)
        #expect(unnamed.lettingGoOfColorStyle(slot: .stroke, forShape: .line)?.line
                == "Let go of the saved color")
    }

    /// The row that speaks is the row whose colour let go, so picking a plain
    /// inside does not put a sentence over a box's outline.
    @Test func theNoticeKnowsWhichPartLetGo() throws {
        var styles = AnnotationStyles()
        styles.arm(Paint(hex: "#B0184A"), styleID: UUID(), name: "Accent",
                   slot: .fill, forShape: .rectangle)
        let notice = try #require(styles.lettingGoOfColorStyle(slot: .fill, forShape: .rectangle))
        #expect(notice.slot == .fill)
        #expect(notice.shape == .rectangle)
    }

    // MARK: - A name this document keeps for other parts

    /// Save a colour, then tick it back to outlines and text in the Library,
    /// and a box tool armed with it for the inside is holding a name the fill
    /// row no longer offers. The box comes out the flat colour the tool
    /// remembers with no link, which is not what the swatch promised.
    @Test func drawingWithANameNotOfferedForThatPartHasSomethingToSay() throws {
        var doc = document()
        var styles = AnnotationStyles()
        let accent = doc.addColorStyle(name: "Accent", colorHex: "#B0184A", roles: [.ink])
        styles.arm(Paint(hex: "#B0184A"), styleID: accent, name: "Accent",
                   slot: .fill, forShape: .rectangle)

        let shape = try #require(drawn(.rectangle, with: styles))
        let notice = try #require(doc.armedColorStyleLeftBehind(shape, styles: styles))
        #expect(notice.kind == .notForThisPart)
        #expect(notice.styleID == accent)
        #expect(notice.slot == .fill)
        #expect(notice.title == "Accent is not for fills")
        #expect(notice.detail
                == "The Rectangle\u{2019}s inside is the plain color the tool remembers, not a saved color")
    }

    @Test func aNameStillOfferedForThatPartSaysNothing() throws {
        var doc = document()
        var styles = AnnotationStyles()
        let surface = doc.addColorStyle(name: "Surface", colorHex: "#101820", roles: [.surface])
        styles.arm(Paint(hex: "#101820"), styleID: surface, name: "Surface",
                   slot: .fill, forShape: .rectangle)

        let shape = try #require(drawn(.rectangle, with: styles))
        #expect(doc.armedColorStyleLeftBehind(shape, styles: styles) == nil)
    }

    /// The other way round: a colour kept for fills, held by a box tool for the
    /// outline. The sentence names the outline, because that is the part that
    /// came out plain.
    @Test func theOutlineIsNamedWhenTheOutlineIsTheOneLeftPlain() throws {
        var doc = document()
        var styles = AnnotationStyles()
        let surface = doc.addColorStyle(name: "Surface", colorHex: "#101820", roles: [.surface])
        styles.arm(Paint(hex: "#101820"), styleID: surface, name: "Surface",
                   slot: .stroke, forShape: .rectangle)

        let shape = try #require(drawn(.rectangle, with: styles))
        let notice = try #require(doc.armedColorStyleLeftBehind(shape, styles: styles))
        #expect(notice.slot == .stroke)
        #expect(notice.title == "Surface is not for outlines")
        #expect(notice.detail
                == "The Rectangle\u{2019}s outline is the plain color the tool remembers, not a saved color")
    }

    /// An arrow IS its colour, so naming its outline would be naming the shape
    /// twice.
    @Test func aShapeThatIsAllOneColourIsNotToldAboutItsOutline() throws {
        var doc = document()
        var styles = AnnotationStyles()
        let surface = doc.addColorStyle(name: "Surface", colorHex: "#101820", roles: [.surface])
        styles.arm(Paint(hex: "#101820"), styleID: surface, name: "Surface",
                   slot: .stroke, forShape: .arrow)

        let shape = try #require(drawn(.arrow, with: styles))
        let notice = try #require(doc.armedColorStyleLeftBehind(shape, styles: styles))
        #expect(notice.kind == .notForThisPart)
        #expect(notice.detail
                == "The Arrow is the plain color the tool remembers, not a saved color")
    }

    /// A tool holding a name for a part it draws nothing in has nothing to
    /// report: a box asked for without an inside is a box without an inside,
    /// and a name must never switch one on. No path through the app reaches
    /// this today — every way of clearing a fill also lets go of the name — so
    /// it is a guard with a test sitting on it.
    @Test func aPartTheToolDrawsNothingInSaysNothing() throws {
        var doc = document()
        var styles = AnnotationStyles()
        let hairline = doc.addColorStyle(name: "Hairline", colorHex: "#101010", roles: [.ink])
        styles.arm(nil, styleID: hairline, name: "Hairline", slot: .fill, forShape: .rectangle)

        let shape = try #require(drawn(.rectangle, with: styles))
        #expect(shape.paint(for: .fill) == nil)
        #expect(doc.armedColorStyleLeftBehind(shape, styles: styles) == nil)
        // ...and the same silence where the document has never heard of it.
        #expect(document().armedColorStyleLeftBehind(shape, styles: styles) == nil)
    }

    /// A tool that picked its name up before names rode along still says which
    /// part came out plain, because that is the half of the sentence it has.
    @Test func aNameTheToolNeverLearnedStillSaysWhichPart() throws {
        var doc = document()
        var styles = AnnotationStyles()
        let accent = doc.addColorStyle(name: "Accent", colorHex: "#B0184A", roles: [.ink])
        styles.arm(Paint(hex: "#B0184A"), styleID: accent, slot: .fill, forShape: .rectangle)

        let shape = try #require(drawn(.rectangle, with: styles))
        let notice = try #require(doc.armedColorStyleLeftBehind(shape, styles: styles))
        #expect(notice.title == "Saved color left behind")
        #expect(notice.detail
                == "The Rectangle\u{2019}s inside is the plain color the tool remembers, not a saved color")
    }

    @Test func thePillSaysWhenANameIsNotForThatPart() {
        let notice = ToolColorStyleNotice(kind: .notForThisPart, styleID: UUID(),
                                          name: "Accent", shape: .rectangle, slot: .fill)
        let pill = CopyConfirmation(subject: .toolColorStyle(notice), shownAt: Date())
        #expect(pill.title == "Accent is not for fills")
        #expect(pill.detail
                == "The Rectangle\u{2019}s inside is the plain color the tool remembers, not a saved color")
        #expect(pill.lifetime == CopyConfirmation.breakLifetime)
    }
}
