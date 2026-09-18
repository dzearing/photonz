import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// The weight a freshly drawn line starts at on an icon frame
/// (`next-icon-frames`).
///
/// Every new shape in the app took four points of line whatever it was drawn
/// on, and on a 24 pixel icon frame four points is a sixth of the whole canvas,
/// so the first mark anybody made on an icon was a blob. The rule here starts
/// them at a weight the icon survives, and stops the moment the user picks a
/// weight of their own.
@Suite("A line starts at a weight the icon survives")
struct IconStrokeWeightTests {

    private let stock = AnnotationContent.defaultStrokeWidth

    private func square(_ side: CGFloat) -> CGSize {
        CGSize(width: side, height: side)
    }

    // MARK: - The weight itself

    @Test("Every icon size gets a weight that reads at that size")
    func weightPerIconSize() {
        // A sixteenth of the frame, on whole pixels: the icon grid is pixels,
        // and a line sitting half on one is the blur icon drawing exists to
        // avoid. 24 lands on the two points Material's 24dp grid uses.
        #expect(IconStrokeWeight.startingWidth(armed: stock, chosen: false, onFrameSized: square(16)) == 1)
        #expect(IconStrokeWeight.startingWidth(armed: stock, chosen: false, onFrameSized: square(24)) == 2)
        #expect(IconStrokeWeight.startingWidth(armed: stock, chosen: false, onFrameSized: square(32)) == 2)
        #expect(IconStrokeWeight.startingWidth(armed: stock, chosen: false, onFrameSized: square(48)) == 3)
        #expect(IconStrokeWeight.startingWidth(armed: stock, chosen: false, onFrameSized: square(64)) == 4)
    }

    @Test("The frame can only make a line thinner, never thicker")
    func neverHeavier() {
        // An app icon is 512 across, where a sixteenth would be 32 points of
        // line. Nobody asked for that: the rule exists to rescue a line that is
        // too heavy for its canvas, so it only ever takes weight off.
        #expect(IconStrokeWeight.startingWidth(armed: stock, chosen: false, onFrameSized: square(512)) == stock)
    }

    @Test("A line is never thinner than one pixel")
    func neverVanishes() {
        // A frame small enough that a sixteenth rounds to nothing still gets a
        // line you can see, or the first mark would be invisible instead of fat.
        #expect(IconStrokeWeight.startingWidth(armed: stock, chosen: false, onFrameSized: square(4)) == 1)
        #expect(IconStrokeWeight.startingWidth(armed: stock, chosen: false, onFrameSized: square(1)) == 1)
    }

    @Test("A size nobody offered is still an icon")
    func typedSize() {
        // Somebody who types 40 into the size field is plainly drawing an icon
        // and would be baffled to find the rule gone.
        #expect(IconStrokeWeight.startingWidth(armed: stock, chosen: false, onFrameSized: square(40)) == 3)
        #expect(IconStrokeWeight.startingWidth(armed: stock, chosen: false, onFrameSized: square(20)) == 1)
    }

    // MARK: - Everywhere else is unchanged

    @Test("A screen still starts at the weight it always did")
    func screensUnchanged() {
        for preset in FramePreset.screens {
            #expect(IconStrokeWeight.startingWidth(armed: stock, chosen: false, onFrameSized: preset.size) == stock)
        }
        // Bare canvas, no frame under the shape at all.
        #expect(IconStrokeWeight.startingWidth(armed: stock, chosen: false, onFrameSized: nil) == stock)
    }

    @Test("A small frame that is not square is not an icon")
    func onlySquares() {
        // A 512 by 64 banner shown at 16 would be a smear, so it is not an icon
        // and its lines are not an icon's lines either.
        #expect(IconStrokeWeight.startingWidth(armed: stock, chosen: false,
                                               onFrameSized: CGSize(width: 64, height: 32)) == stock)
    }

    // MARK: - It is a starting value, not a lock

    @Test("A weight the user picked is the weight they get")
    func aPickedWeightWins() {
        // The app chooses for you only while you have not chosen. Somebody who
        // sets the line to 8 and draws another shape on the same icon frame
        // gets 8, or the panel would be a control that undoes itself.
        #expect(IconStrokeWeight.startingWidth(armed: 8, chosen: true, onFrameSized: square(24)) == 8)
        #expect(IconStrokeWeight.startingWidth(armed: 1, chosen: true, onFrameSized: square(24)) == 1)
        #expect(IconStrokeWeight.startingWidth(armed: 3, chosen: true, onFrameSized: square(16)) == 3)
    }

    @Test("A four somebody typed is a four, not the four the tool shipped with")
    func aChosenStockWeightWins() {
        // The bug this rule used to have, in one line: the app decided whether
        // you had chosen by comparing your number against the one it ships
        // with, so typing that very number left you with a line at 2 and a row
        // reading 4. What counts is that somebody chose, not what they chose.
        #expect(IconStrokeWeight.startingWidth(armed: stock, chosen: true, onFrameSized: square(24)) == stock)
        #expect(IconStrokeWeight.startingWidth(armed: stock, chosen: false, onFrameSized: square(24)) == 2)
    }

    @Test("A line switched off stays off")
    func offStaysOff() {
        // Zero is what a box whose edge has been taken off is armed with, and
        // giving it a line back would be the app drawing something nobody asked
        // for.
        #expect(IconStrokeWeight.startingWidth(armed: 0, chosen: true, onFrameSized: square(24)) == 0)
        #expect(IconStrokeWeight.startingWidth(armed: 0, chosen: false, onFrameSized: square(24)) == 0)
    }

    // MARK: - Finding the frame a shape lands on

    private func document() -> PhotonzDocument {
        let icon = Layer.frameLayer(name: "Icon", origin: CGPoint(x: 100, y: 100),
                                    size: CGSize(width: 24, height: 24))
        let screen = Layer.frameLayer(name: "Home", origin: CGPoint(x: 400, y: 100),
                                      size: CGSize(width: 390, height: 844))
        return PhotonzDocument(canvasSize: CGSize(width: 2000, height: 1200),
                               layers: [icon, screen])
    }

    @Test("The frame a shape lands on is the one that decides its weight")
    func frameUnderThePoint() {
        let document = document()
        #expect(document.iconFrameSize(under: CGPoint(x: 110, y: 110)) == CGSize(width: 24, height: 24))
        // On the screen beside it: a frame, but not an icon.
        #expect(document.iconFrameSize(under: CGPoint(x: 500, y: 300)) == nil)
        // Out on bare canvas.
        #expect(document.iconFrameSize(under: CGPoint(x: 50, y: 50)) == nil)
    }

    @Test("A shape drawn on an icon frame arrives thin, one on a screen does not")
    func startingWidthInDocument() {
        let document = document()
        #expect(document.startingStrokeWidth(armed: stock, chosen: false, drawnAt: CGPoint(x: 110, y: 110)) == 2)
        #expect(document.startingStrokeWidth(armed: stock, chosen: false, drawnAt: CGPoint(x: 500, y: 300)) == stock)
        #expect(document.startingStrokeWidth(armed: stock, chosen: false, drawnAt: CGPoint(x: 50, y: 50)) == stock)
    }

    @Test("A weight the Pen was armed with wins on an icon frame")
    func anArmedPenIsNotThinned() {
        let document = document()
        // The Pen remembering the weight you last chose means it arrives here
        // holding something other than the stock four, and a starting value
        // that reimposed itself over a choice would be a lock.
        #expect(document.startingStrokeWidth(armed: 9, chosen: true, drawnAt: CGPoint(x: 110, y: 110)) == 9)
        #expect(document.startingStrokeWidth(armed: 1, chosen: true, drawnAt: CGPoint(x: 110, y: 110)) == 1)
        // Still at the weight it ships with, so the frame still gets its say.
        #expect(document.startingStrokeWidth(armed: stock, chosen: false, drawnAt: CGPoint(x: 110, y: 110)) == 2)
    }

    // MARK: - The number the Width row shows

    @Test("The Width row reads the weight the line will really land at")
    func theRowReadsWhatLands() {
        // The two halves of the bug, side by side: the row asks the frame it is
        // being held over the same question the drawing asks, so one number
        // answers both. Before this the row read 4 while the line landed at 2.
        let document = document()
        let styles = AnnotationStyles()
        let iconID = document.layers[0].id
        let screenID = document.layers[1].id

        #expect(document.iconFrameSize(containing: iconID) == CGSize(width: 24, height: 24))
        #expect(document.iconFrameSize(containing: screenID) == nil)

        // Nothing chosen: the row over the icon frame says 2, and 2 is what a
        // line drawn there comes out at.
        let armed = styles.strokeWidth(for: .pen)
        let chosen = styles.strokeWidthWasChosen(for: .pen)
        #expect(document.startingStrokeWidth(armed: armed, chosen: chosen, drawingInside: iconID) == 2)
        #expect(document.startingStrokeWidth(armed: armed, chosen: chosen,
                                             drawnAt: CGPoint(x: 110, y: 110)) == 2)
        // On the screen beside it the row is untouched.
        #expect(document.startingStrokeWidth(armed: armed, chosen: chosen, drawingInside: screenID) == stock)
    }

    @Test("Typing the weight the row was already showing gets you that weight")
    func typingTheShownWeightSticks() {
        // Read 2 on an icon frame, type 2, draw: the line is 2 and the row
        // still says 2. And type the stock 4 instead and you get a 4, which is
        // the case the old rule could not tell from having chosen nothing.
        var styles = AnnotationStyles()
        let document = document()
        let iconID = document.layers[0].id

        styles.setStrokeWidth(2, for: .pen)
        #expect(document.startingStrokeWidth(armed: styles.strokeWidth(for: .pen),
                                             chosen: styles.strokeWidthWasChosen(for: .pen),
                                             drawingInside: iconID) == 2)

        styles.setStrokeWidth(stock, for: .pen)
        #expect(styles.strokeWidth(for: .pen) == stock)
        #expect(document.startingStrokeWidth(armed: styles.strokeWidth(for: .pen),
                                             chosen: styles.strokeWidthWasChosen(for: .pen),
                                             drawingInside: iconID) == stock)
        #expect(document.startingStrokeWidth(armed: styles.strokeWidth(for: .pen),
                                             chosen: styles.strokeWidthWasChosen(for: .pen),
                                             drawnAt: CGPoint(x: 110, y: 110)) == stock)
    }

    // MARK: - With nothing picked, the pointer says which icon

    @Test("The icon the pointer is resting in is the one it names")
    func iconFrameUnderThePointer() {
        let document = document()
        #expect(document.iconFrameID(under: CGPoint(x: 110, y: 110)) == document.layers[0].id)
        // A screen is a frame, but it is not an icon, so it has nothing to say.
        #expect(document.iconFrameID(under: CGPoint(x: 500, y: 300)) == nil)
        #expect(document.iconFrameID(under: CGPoint(x: 50, y: 50)) == nil)
    }

    @Test("With nothing picked, the Width row reads the icon the pointer is in")
    func nothingPickedTheRowFollowsThePointer() {
        // The gap this closes: the row learned which icon it was speaking for
        // from what was PICKED, so picking nothing at all put it back to
        // reading the armed 4 while a line drawn into the frame still landed
        // at 2. Two numbers for one line.
        let document = document()
        let styles = AnnotationStyles()
        let iconID = document.layers[0].id
        let armed = styles.strokeWidth(for: .pen)
        let chosen = styles.strokeWidthWasChosen(for: .pen)

        #expect(document.startingStrokeWidth(armed: armed, chosen: chosen,
                                             picked: nil, pointerIn: iconID) == 2)
        // And that is the weight the line really lands at, asked the way the
        // drawing asks it.
        #expect(document.startingStrokeWidth(armed: armed, chosen: chosen,
                                             drawnAt: CGPoint(x: 110, y: 110)) == 2)
        // Nothing picked and the pointer nowhere useful: the armed weight, as
        // it always was.
        #expect(document.startingStrokeWidth(armed: armed, chosen: chosen,
                                             picked: nil, pointerIn: nil) == stock)
    }

    @Test("What is picked outranks where the pointer is")
    func whatIsPickedWins() {
        // A shape you have chosen is what you are working on wherever the hand
        // has wandered to, so sweeping the pointer over an icon while a shape
        // on a screen is picked must not make the row speak for the icon.
        let document = document()
        let styles = AnnotationStyles()
        let iconID = document.layers[0].id
        let screenID = document.layers[1].id
        let armed = styles.strokeWidth(for: .pen)
        let chosen = styles.strokeWidthWasChosen(for: .pen)

        #expect(document.startingStrokeWidth(armed: armed, chosen: chosen,
                                             picked: screenID, pointerIn: iconID) == stock)
        // The other way round: the icon is picked and the pointer has left it,
        // which is what reaching for the tool bar does.
        #expect(document.startingStrokeWidth(armed: armed, chosen: chosen,
                                             picked: iconID, pointerIn: nil) == 2)
    }

    @Test("A weight somebody chose survives the pointer too")
    func thePointerNeverOverridesAChoice() {
        var styles = AnnotationStyles()
        let document = document()
        let iconID = document.layers[0].id
        styles.setStrokeWidth(stock, for: .pen)
        #expect(document.startingStrokeWidth(armed: styles.strokeWidth(for: .pen),
                                             chosen: styles.strokeWidthWasChosen(for: .pen),
                                             picked: nil, pointerIn: iconID) == stock)
    }

    @Test("A box's and a line's Width rows read the same way the Pen's does")
    func everyShapeRowAgrees() {
        // The gap was never the Pen's alone: every shape tool's Width row had
        // it, since the icon rule landed. A box keeps its weight in a Border
        // rather than a stroke, so it starts at nothing until one is asked for.
        var styles = AnnotationStyles()
        let document = document()
        let iconID = document.layers[0].id

        for shape in [AnnotationShape.line, .arrow] {
            let armed = styles.strokeWidth(forShape: shape)
            #expect(document.startingStrokeWidth(armed: armed,
                                                 chosen: styles.strokeWidthWasChosen(forShape: shape),
                                                 drawingInside: iconID) == 2)
        }
        // Chosen on the bar, honoured everywhere, the stock four included.
        styles.setStrokeWidth(stock, forShape: .line)
        #expect(document.startingStrokeWidth(armed: styles.strokeWidth(forShape: .line),
                                             chosen: styles.strokeWidthWasChosen(forShape: .line),
                                             drawingInside: iconID) == stock)
        // A box asked for a 4 point edge gets a 4 point edge.
        styles.armEdge(width: stock, forShape: .rectangle)
        #expect(document.startingStrokeWidth(armed: styles.strokeWidth(forShape: .rectangle),
                                             chosen: styles.strokeWidthWasChosen(forShape: .rectangle),
                                             drawingInside: iconID) == stock)
    }

    @Test("A weight set on the bar is the weight the Pen draws with")
    func aWidthChosenOnTheBarIsWhatTheNextPathComesOutAt() {
        // The whole chain the Pen's Width row rides on, end to end: the row
        // shows `strokeWidth(for: .pen)`, its commit writes the same place,
        // and the canvas reads it back as the first anchor goes down
        // (`EditorState.armedPenStrokeWidth`).
        var styles = AnnotationStyles()
        let document = document()
        let onTheIcon = CGPoint(x: 110, y: 110)   // inside the 24px frame
        let onBareCanvas = CGPoint(x: 500, y: 300)

        // Untouched, the row shows 2 over the 24px frame, because 2 is what a
        // line drawn there comes out at. The four every line ships with is
        // still what the Pen is armed with off the frame.
        #expect(styles.strokeWidth(for: .pen) == stock)
        #expect(styles.strokeWidthWasChosen(for: .pen) == false)
        #expect(document.startingStrokeWidth(armed: styles.strokeWidth(for: .pen),
                                             chosen: styles.strokeWidthWasChosen(for: .pen),
                                             drawnAt: onTheIcon) == 2)
        #expect(document.startingStrokeWidth(armed: styles.strokeWidth(for: .pen),
                                             chosen: styles.strokeWidthWasChosen(for: .pen),
                                             drawnAt: onBareCanvas) == stock)

        // Set it to two on the bar and that is what lands, on the icon frame
        // and off it alike: a weight somebody chose is never re-decided.
        styles.setStrokeWidth(2, for: .pen)
        #expect(styles.strokeWidth(for: .pen) == 2)
        #expect(styles.strokeWidthWasChosen(for: .pen))
        #expect(document.startingStrokeWidth(armed: styles.strokeWidth(for: .pen),
                                             chosen: styles.strokeWidthWasChosen(for: .pen),
                                             drawnAt: onTheIcon) == 2)
        #expect(document.startingStrokeWidth(armed: styles.strokeWidth(for: .pen),
                                             chosen: styles.strokeWidthWasChosen(for: .pen),
                                             drawnAt: onBareCanvas) == 2)

        // And a heavy one is not thinned either, which is what a row that
        // wrote the stock four back on open would have quietly undone.
        styles.setStrokeWidth(9, for: .pen)
        #expect(document.startingStrokeWidth(armed: styles.strokeWidth(for: .pen),
                                             chosen: styles.strokeWidthWasChosen(for: .pen),
                                             drawnAt: onTheIcon) == 9)
    }

    // MARK: - The line lands wherever this shape keeps it

    @Test("A line and an arrow are thinned on their own stroke")
    func strokeShapesThinned() {
        let document = document()
        let line = AnnotationContent(shape: .line, strokeWidth: stock)
        let onIcon = document.startingOutline(content: line, style: nil, chosen: false,
                                              drawnAt: CGPoint(x: 110, y: 110))
        #expect(onIcon.content.strokeWidth == 2)
        let onScreen = document.startingOutline(content: line, style: nil, chosen: false,
                                                drawnAt: CGPoint(x: 500, y: 300))
        #expect(onScreen.content.strokeWidth == stock)
    }

    @Test("A box is thinned on the border it arrives wearing")
    func borderShapesThinned() {
        // A box and an oval have no stroke of their own: their edge is a Border
        // in the Effects list, so that is the number the rule has to move.
        let document = document()
        let box = AnnotationContent(shape: .rectangle, strokeWidth: 0)
        var style = LayerStyle()
        style.effects.append(.border(BorderEffect(width: stock, position: .inside)))
        let thinned = document.startingOutline(content: box, style: style, chosen: false,
                                               drawnAt: CGPoint(x: 110, y: 110))
        #expect(thinned.style?.borderWidth == 2)
        // The shape's own stroke is still nothing: a box gains no second ring.
        #expect(thinned.content.strokeWidth == 0)
    }

    @Test("A highlight is a wash and is left alone")
    func highlightUntouched() {
        let document = document()
        let wash = AnnotationContent(shape: .highlight, strokeWidth: stock)
        let same = document.startingOutline(content: wash, style: nil, chosen: false,
                                            drawnAt: CGPoint(x: 110, y: 110))
        #expect(same.content.strokeWidth == stock)
    }
}
