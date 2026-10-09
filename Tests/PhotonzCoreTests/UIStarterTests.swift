import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// The Design UI start (`docs/design/mocks/pages/ui-entry-wt.html`, steps 3
/// to 7): an empty window's Design UI row opens a 1280 by 800 canvas already
/// holding a Login starter frame laid out as a column, so the next thing a
/// person does is drag a component onto it.
///
/// "The starter frame is an ordinary frame. The template gave you a head
/// start, not a mode." So every test here reads the document as the rest of
/// the app does: a frame, its layout and its children, nothing special.
@Suite("The Design UI start")
struct UIStarterTests {

    /// Built once: every call makes fresh ids, and a test that compared two
    /// of them would be comparing two different documents.
    private let document = UIStarter.document()

    private var login: Layer? { document.layers.first }

    // MARK: - The canvas

    @Test("The canvas is 1280 by 800 and holds one frame called Login, and nothing else")
    func oneFrameOnALaptopCanvas() {
        #expect(document.canvasSize == CGSize(width: 1280, height: 800))
        #expect(document.layers.count == 1)
        #expect(login?.name == "Login")
        #expect(login?.isFrame == true)
        // No colors or text styles of its own: the shelf is the app's starters
        // and nothing the template made up.
        #expect(document.colorStyles.isEmpty)
        #expect(document.componentOriginals.isEmpty)
    }

    @Test("Login is a column with gap 12 and padding 24, as the mock's Properties show")
    func theFrameIsAColumn() throws {
        let layout = try #require(login?.group?.layout)
        #expect(layout.kind == .stack)
        #expect(layout.direction == .column)
        #expect(layout.gap == 12)
        #expect(layout.padding == GroupPadding(24))
    }

    @Test("Login holds the mock's headline, subhead and two fields, top to bottom")
    func theFrameHoldsTheMocksLayers() throws {
        let children = try #require(login?.children)
        #expect(children.map(\.name) == ["Headline", "Subhead", "Email field", "Password field"])
        #expect(children[0].text?.string == "Welcome back")
        #expect(children[1].text?.string == "Sign in to continue")
        // A field is a box with quiet words in it, the same shape the Text
        // field starter is drawn in.
        let email = children[2]
        #expect(email.children.map(\.name) == ["Background", "Placeholder"])
        #expect(email.children[1].text?.string == "you@example.com")
        #expect(children[3].children[1].text?.string == "••••••••")
    }

    @Test("Login is 320 wide, the rows run 24 in from its edges with 12 between them")
    func theRowsAreLaidOut() throws {
        let frame = try #require(login)
        #expect(frame.frame.width == 320)
        // What is drawn, which is what the column lays out: the words, not
        // the slack a text box keeps past them, and a group's whole box.
        let rows = frame.children.map(\.contentBounds)
        for (row, name) in zip(rows, frame.children.map(\.name)) {
            #expect(row.minX == 24, "\(name) sits 24 in from the left")
            #expect(row.width == 272, "\(name) runs the width inside the padding")
        }
        #expect(rows[0].minY == 24)
        for (above, below) in zip(rows, rows.dropFirst()) {
            #expect(below.minY == above.maxY + 12)
        }
        #expect(rows[2].height == 36)
        #expect(rows[3].height == 36)
        // The frame closes around them: 24 under the last row.
        let last = try #require(rows.last)
        #expect(frame.frame.height == last.maxY + 24)
    }

    @Test("Login sits in the middle of the canvas")
    func theFrameIsCentred() throws {
        let frame = try #require(login).frame
        #expect(frame.minX == 480)
        #expect(abs(frame.midY - 400) <= 1)
    }

    @Test("The starter is already laid out: the flow moves nothing when it runs")
    func theStarterIsAlreadyFlowed() {
        var flowed = document
        flowed.reflowLayouts()
        #expect(flowed == document)
    }

    // MARK: - Using it

    @Test("A Button dropped on Login joins the column, last, as a linked copy, and the frame grows to hold it")
    func aButtonLandsInTheColumn() throws {
        var history = History(document: document)
        let frame = try #require(login)
        let heightBefore = frame.frame.height
        var placed: UUID?
        let report = history.perform {
            placed = $0.insertStarterComponent(.button, at: CGPoint(x: frame.frame.midX,
                                                                    y: frame.frame.maxY - 30))
        }
        let id = try #require(placed)
        // Placing a copy is not an edit that reached any other copy, so it
        // says nothing, even though the column stretched it as it landed.
        #expect(report.componentSync.isEmpty)
        let after = history.current
        #expect(after.parentID(of: id) == frame.id)
        let grown = try #require(after.layer(id: frame.id))
        #expect(grown.children.last?.id == id)
        #expect(grown.children.count == 5)
        let button = try #require(after.layer(id: id))
        #expect(button.group?.instanceOf == StarterComponent.button.componentID)
        #expect(button.contentBounds.minY == grown.children[3].contentBounds.maxY + 12)
        // It runs the width of the column, the way the mock's Sign in button
        // does: Login stretches what it holds across unless told otherwise.
        #expect(button.contentBounds.minX == 24)
        #expect(button.contentBounds.width == 272)
        #expect(grown.frame.height == heightBefore + button.contentBounds.height + 12)
        // Undoing the drop takes the button and leaves the starter frame.
        history.undo()
        #expect(history.current.layers.map(\.name) == ["Login"])
        #expect(history.current.layer(id: frame.id)?.children.count == 4)
    }

    @Test("The starter frame is ordinary: deleting it leaves an empty canvas")
    func theFrameCanBeDeleted() throws {
        var doc = document
        let id = try #require(login?.id)
        doc.removeLayer(id: id)
        #expect(doc.layers.isEmpty)
        #expect(doc.canvasSize == CGSize(width: 1280, height: 800))
    }

    // MARK: - Its name

    @Test("The first one is untitled-ui, the ones after it count on")
    func names() {
        #expect(UIStarter.documentName(number: 1) == "untitled-ui")
        #expect(UIStarter.documentName(number: 2) == "untitled-ui 2")
        #expect(UIStarter.documentName(number: 7) == "untitled-ui 7")
    }

    @Test("The row's words fit the card: a label, not a sentence")
    func rowTitle() {
        #expect(UIStarter.rowTitle == "Design UI")
        #expect(UIStarter.menuTitle == "New UI Design")
    }

    @Test("Design UI is on by default in Next and absent from Current")
    func flag() {
        #expect(FeatureCatalog.defaultSettings(for: .next).isEnabled(FeatureCatalog.designUIStartFlag))
        #expect(!FeatureCatalog.flags(for: .current).contains { $0.name == FeatureCatalog.designUIStartFlag })
    }
}
