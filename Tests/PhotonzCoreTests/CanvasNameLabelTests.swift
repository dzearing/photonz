import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Where a name draws above its box on the canvas, and what a click on it hits.
@Suite("Canvas name labels")
struct CanvasNameLabelTests {

    /// A frame drawn at (100, 200) 300 x 400 in view space.
    private let frame = CGRect(x: 100, y: 200, width: 300, height: 400)

    @Test("The name sits above the frame's top left corner, clear of its edge")
    func boxHangsAboveTheFrame() {
        let box = CanvasNameLabels.box(forFrameRect: frame)
        #expect(box.minX == frame.minX)
        #expect(box.maxY == frame.minY - CanvasNameLabels.gap)
        #expect(box.height == CanvasNameLabels.height)
        #expect(box.maxY < frame.minY, "the label must never touch the frame edge")
    }

    @Test("A wide frame's name box stops at the cap, a narrow frame's at its own width")
    func boxWidthIsCapped() {
        #expect(CanvasNameLabels.box(forFrameRect: frame).width == CanvasNameLabels.maximumWidth)
        let narrow = CGRect(x: 0, y: 100, width: 120, height: 100)
        #expect(CanvasNameLabels.box(forFrameRect: narrow).width == 120)
        let tiny = CGRect(x: 0, y: 100, width: 8, height: 100)
        #expect(CanvasNameLabels.box(forFrameRect: tiny).width == CanvasNameLabels.minimumWidth)
    }

    @Test("A name that must print whole widens its box instead of losing letters")
    func fittingWholeTextWidensTheBox() {
        let small = CGRect(x: 0, y: 100, width: 70, height: 30)
        // A component wearing its version after its name: "Button \u{00B7} Disabled"
        // is 110 points of text above a 70 point button, and the version is
        // the word that tells two drawings apart, so nothing may be cut.
        let label = CanvasNameLabel(id: UUID(), frameRect: small, textWidth: 110,
                                    leadingInset: 14, fitsWholeText: true)
        #expect(CanvasNameLabels.box(for: label).width == 110)
        // ...and the click follows the letters it can now read.
        #expect(CanvasNameLabels.hitBox(for: label).width > 110)
        // A label that does not ask keeps the old, box-sized behaviour: the
        // strip stays the width of the button, less the room the mark takes,
        // and the letters past it are cut off.
        let plain = CanvasNameLabel(id: UUID(), frameRect: small, textWidth: 110, leadingInset: 14)
        #expect(CanvasNameLabels.box(for: plain).width == small.width - 14)
    }

    @Test("Even a name that must print whole stops at the cap")
    func fittingWholeTextStopsAtTheCap() {
        let label = CanvasNameLabel(id: UUID(), frameRect: frame, textWidth: 4000,
                                    fitsWholeText: true)
        #expect(CanvasNameLabels.box(for: label).width == CanvasNameLabels.maximumWidth)
    }

    @Test("A widened name takes its real width into account when names stack")
    func fittingWholeTextIsStackedByItsRealInk() {
        let small = CGRect(x: 0, y: 100, width: 70, height: 30)
        let label = CanvasNameLabel(id: UUID(), frameRect: small, textWidth: 110,
                                    leadingInset: 14, fitsWholeText: true)
        #expect(CanvasNameLabels.chipBox(for: label).width == 124)
    }

    @Test("The clickable area is the width of the text, not the width of the box")
    func hitBoxFollowsTheText() {
        let hit = CanvasNameLabels.hitBox(forFrameRect: frame, textWidth: 42)
        #expect(hit.width < CanvasNameLabels.maximumWidth)
        // Slop on both sides, so a 10pt name is still an easy target.
        #expect(hit.width > 42)
        #expect(hit.minX < frame.minX)
    }

    @Test("A one letter name still gets a target big enough to click")
    func shortNamesStayClickable() {
        let hit = CanvasNameLabels.hitBox(forFrameRect: frame, textWidth: 4)
        #expect(hit.width >= CanvasNameLabels.minimumHitWidth)
    }

    @Test("A name longer than its box does not answer clicks past the box")
    func hitBoxNeverOutgrowsTheBox() {
        let hit = CanvasNameLabels.hitBox(forFrameRect: frame, textWidth: 4000)
        #expect(hit.maxX <= frame.minX + CanvasNameLabels.maximumWidth + 4)
    }

    @Test("The clickable area leaves the frame's own top edge alone")
    func hitBoxStaysOffTheFrame() {
        let hit = CanvasNameLabels.hitBox(forFrameRect: frame, textWidth: 60)
        #expect(hit.maxY < frame.minY, "clicking the frame's top edge must reach the frame")
    }

    @Test("A click on a name picks that frame")
    func clickOnNameHits() {
        let id = UUID()
        let labels = [CanvasNameLabel(id: id, frameRect: frame, textWidth: 60)]
        let box = CanvasNameLabels.box(forFrameRect: frame)
        #expect(CanvasNameLabels.hit(at: CGPoint(x: box.minX + 4, y: box.midY), labels: labels) == id)
    }

    @Test("A click on blank canvas beside a short name hits nothing")
    func clickBesideNameMisses() {
        let labels = [CanvasNameLabel(id: UUID(), frameRect: frame, textWidth: 30)]
        let box = CanvasNameLabels.box(forFrameRect: frame)
        #expect(CanvasNameLabels.hit(at: CGPoint(x: box.minX + 200, y: box.midY), labels: labels) == nil)
    }

    @Test("A click inside the frame itself hits no name")
    func clickInsideFrameMisses() {
        let labels = [CanvasNameLabel(id: UUID(), frameRect: frame, textWidth: 60)]
        #expect(CanvasNameLabels.hit(at: CGPoint(x: frame.minX + 4, y: frame.minY + 2),
                                    labels: labels) == nil)
    }

    @Test("Where two names overlap, the one drawn on top wins")
    func topmostNameWins() {
        let under = UUID()
        let over = UUID()
        let labels = [
            CanvasNameLabel(id: under, frameRect: frame, textWidth: 60),
            CanvasNameLabel(id: over, frameRect: frame.offsetBy(dx: 2, dy: 0), textWidth: 60),
        ]
        let box = CanvasNameLabels.box(forFrameRect: frame)
        #expect(CanvasNameLabels.hit(at: CGPoint(x: box.minX + 10, y: box.midY), labels: labels) == over)
    }

    @Test("No frames means no name to click")
    func emptyMisses() {
        #expect(CanvasNameLabels.hit(at: .zero, labels: []) == nil)
    }

    // MARK: A component's name, drawn behind its mark

    /// The four-diamond mark plus the space after it, in view points.
    private let mark: CGFloat = 14

    @Test("A component's name starts to the right of its mark, on the same line")
    func insetShiftsTheBoxRight() {
        let plain = CanvasNameLabels.box(forFrameRect: frame)
        let marked = CanvasNameLabels.box(forFrameRect: frame, leadingInset: mark)
        #expect(marked.minX == plain.minX + mark)
        #expect(marked.minY == plain.minY, "both names sit on the same line above the box")
        #expect(marked.height == plain.height)
    }

    @Test("The mark eats into the name box rather than pushing it past the right edge")
    func insetNarrowsTheBox() {
        let plain = CanvasNameLabels.box(forFrameRect: frame)
        let marked = CanvasNameLabels.box(forFrameRect: frame, leadingInset: mark)
        #expect(marked.maxX == plain.maxX)
    }

    @Test("A narrow component still keeps room to print its name")
    func insetKeepsAMinimumWidth() {
        let narrow = CGRect(x: 0, y: 100, width: 20, height: 100)
        let box = CanvasNameLabels.box(forFrameRect: narrow, leadingInset: mark)
        #expect(box.width == CanvasNameLabels.minimumWidth)
    }

    @Test("A click on the mark in front of the name is a click on the name")
    func clickOnTheMarkHits() {
        let id = UUID()
        let labels = [CanvasNameLabel(id: id, frameRect: frame, textWidth: 60,
                                      leadingInset: mark)]
        let strip = CanvasNameLabels.box(forFrameRect: frame)
        #expect(CanvasNameLabels.hit(at: CGPoint(x: strip.minX + 2, y: strip.midY),
                                     labels: labels) == id,
                "the mark and the name read as one chip, so the whole chip is the handle")
    }

    @Test("Blank canvas past the end of a marked name is still blank canvas")
    func clickBesideAMarkedNameMisses() {
        let labels = [CanvasNameLabel(id: UUID(), frameRect: frame, textWidth: 30,
                                      leadingInset: mark)]
        let box = CanvasNameLabels.box(forFrameRect: frame, leadingInset: mark)
        #expect(CanvasNameLabels.hit(at: CGPoint(x: box.minX + 120, y: box.midY),
                                     labels: labels) == nil)
    }

    @Test("A click on a component's name picks that component")
    func clickOnComponentNameHits() {
        let id = UUID()
        let labels = [CanvasNameLabel(id: id, frameRect: frame, textWidth: 60,
                                      leadingInset: mark)]
        let box = CanvasNameLabels.box(forFrameRect: frame, leadingInset: mark)
        #expect(CanvasNameLabels.hit(at: CGPoint(x: box.minX + 4, y: box.midY),
                                     labels: labels) == id)
    }

    @Test("A component's name is at least as easy to hit as a screen's")
    func componentHitBoxMatchesAScreens() {
        let plain = CanvasNameLabels.hitBox(forFrameRect: frame, textWidth: 60)
        let marked = CanvasNameLabels.hitBox(forFrameRect: frame, textWidth: 60,
                                             leadingInset: mark)
        // Same left edge, same top and bottom, and the mark's width on top: the
        // chip starts where a screen's name starts and runs a little further.
        #expect(marked.minX == plain.minX)
        #expect(marked.minY == plain.minY)
        #expect(marked.height == plain.height)
        #expect(marked.width == plain.width + mark)
    }

    @Test("A component's name leaves its own top edge alone")
    func componentHitBoxStaysOffTheBox() {
        let hit = CanvasNameLabels.hitBox(forFrameRect: frame, textWidth: 60, leadingInset: mark)
        #expect(hit.maxY < frame.minY)
    }

    // MARK: Two names that want the same spot

    /// A screen 300 x 400, and a button sitting in its top left corner: both
    /// names want the strip above that corner.
    private var stackedPair: [CanvasNameLabel] {
        let screen = CanvasNameLabel(id: UUID(), frameRect: frame, textWidth: 40)
        let button = CanvasNameLabel(id: UUID(),
                                     frameRect: CGRect(x: frame.minX + 8, y: frame.minY + 8,
                                                       width: 120, height: 40),
                                     textWidth: 42, leadingInset: mark)
        return [screen, button]
    }

    @Test("Two names that would print on top of each other end up on different lines")
    func collidingNamesStack() {
        let stacked = CanvasNameLabels.stacked(stackedPair)
        let first = CanvasNameLabels.chipBox(for: stacked[0])
        let second = CanvasNameLabels.chipBox(for: stacked[1])
        #expect(!first.intersects(second), "neither name may be drawn over the other")
        #expect(second.maxY <= first.minY, "the inner name climbs above the one it collided with")
    }

    @Test("The name that was there first keeps its place")
    func firstNameStaysPut() {
        let labels = stackedPair
        let stacked = CanvasNameLabels.stacked(labels)
        #expect(stacked[0].frameRect == labels[0].frameRect)
        #expect(stacked[1].frameRect.minY < labels[1].frameRect.minY)
        #expect(stacked[1].frameRect.minX == labels[1].frameRect.minX,
                "a name only ever climbs, it never slides sideways away from its box")
    }

    @Test("A name that collides with nothing does not move")
    func loneNameDoesNotMove() {
        let labels = [CanvasNameLabel(id: UUID(), frameRect: frame, textWidth: 40)]
        #expect(CanvasNameLabels.stacked(labels)[0].frameRect == frame)
    }

    @Test("Two screens side by side keep their own line")
    func distantNamesDoNotStack() {
        let labels = [
            CanvasNameLabel(id: UUID(), frameRect: frame, textWidth: 40),
            CanvasNameLabel(id: UUID(), frameRect: frame.offsetBy(dx: 400, dy: 0), textWidth: 40),
        ]
        let stacked = CanvasNameLabels.stacked(labels)
        #expect(stacked[1].frameRect == labels[1].frameRect)
    }

    @Test("A short name leaves room beside it: the box is wide, the letters are not")
    func stackingMeasuresTheLettersNotTheBox() {
        // The second box starts 80 points right of the first, whose name is
        // only 40 points of letters. Both boxes are 240 wide and overlap, the
        // names do not.
        let labels = [
            CanvasNameLabel(id: UUID(), frameRect: frame, textWidth: 40),
            CanvasNameLabel(id: UUID(), frameRect: frame.offsetBy(dx: 80, dy: 0), textWidth: 40),
        ]
        #expect(CanvasNameLabels.stacked(labels)[1].frameRect == labels[1].frameRect)
    }

    @Test("Names that nearly touch still get pulled apart")
    func namesNeedBreathingRoom() {
        // Two points of daylight between two names is not enough to read them
        // as two names.
        let labels = [
            CanvasNameLabel(id: UUID(), frameRect: frame, textWidth: 40),
            CanvasNameLabel(id: UUID(), frameRect: frame.offsetBy(dx: 42, dy: 0), textWidth: 40),
        ]
        #expect(CanvasNameLabels.stacked(labels)[1].frameRect.minY < labels[1].frameRect.minY)
    }

    @Test("A component's mark counts as part of its name when they are pulled apart")
    func theMarkIsPartOfTheChip() {
        // The letters start clear of the screen's name, but the mark in front
        // of them does not, and a mark drawn over letters is the same mess.
        let labels = [
            CanvasNameLabel(id: UUID(), frameRect: frame, textWidth: 40),
            CanvasNameLabel(id: UUID(), frameRect: frame.offsetBy(dx: 44, dy: 0),
                            textWidth: 40, leadingInset: mark),
        ]
        #expect(CanvasNameLabels.stacked(labels)[1].frameRect.minY < labels[1].frameRect.minY)
    }

    @Test("Three names in one corner land on three lines")
    func threeNamesStackInOrder() {
        let rect = frame
        let labels = (0..<3).map { i in
            CanvasNameLabel(id: UUID(), frameRect: rect.offsetBy(dx: CGFloat(i) * 2, dy: 0),
                            textWidth: 60)
        }
        let boxes = CanvasNameLabels.stacked(labels).map(CanvasNameLabels.chipBox(for:))
        for (i, box) in boxes.enumerated() {
            for other in boxes[(i + 1)...] {
                #expect(!box.intersects(other))
            }
        }
    }

    @Test("A pile of names in one corner stops climbing instead of flying off screen")
    func stackingIsBounded() {
        let labels = (0..<40).map { _ in
            CanvasNameLabel(id: UUID(), frameRect: frame, textWidth: 60)
        }
        let stacked = CanvasNameLabels.stacked(labels)
        let highest = stacked.map(\.frameRect.minY).min() ?? 0
        #expect(highest >= frame.minY - CanvasNameLabels.rowStep * CGFloat(CanvasNameLabels.maximumRows) - 1)
    }

    @Test("A click lands on the name where it ended up, not where it started")
    func clicksFollowTheStack() {
        let labels = stackedPair
        let stacked = CanvasNameLabels.stacked(labels)
        let lifted = CanvasNameLabels.box(for: stacked[1])
        #expect(CanvasNameLabels.hit(at: CGPoint(x: lifted.minX + 4, y: lifted.midY),
                                     labels: stacked) == labels[1].id)
        let bottom = CanvasNameLabels.box(for: stacked[0])
        #expect(CanvasNameLabels.hit(at: CGPoint(x: bottom.minX + 4, y: bottom.midY),
                                     labels: stacked) == labels[0].id,
                "the name that kept its place still answers clicks there")
    }

    @Test("A stacked name still keeps off its own box's top edge")
    func stackedNamesStayOffTheBox() {
        let stacked = CanvasNameLabels.stacked(stackedPair)
        for label in stacked {
            #expect(CanvasNameLabels.hitBox(for: label).maxY < label.frameRect.minY)
        }
    }

    @Test("A name climbs just far enough to clear what was in its way")
    func liftIsNoBiggerThanItNeedsToBe() {
        // The button's box starts eight points below the screen's, so its name
        // starts eight points lower too: one line up is not enough to clear
        // the screen's name, and two lines is further than it needs.
        let labels = stackedPair
        let stacked = CanvasNameLabels.stacked(labels)
        let first = CanvasNameLabels.chipBox(for: stacked[0])
        let second = CanvasNameLabels.chipBox(for: stacked[1])
        #expect(second.maxY == first.minY - CanvasNameLabels.verticalGap)
    }
}

/// What the words above a drawing on the canvas actually say.
@Suite("Canvas name captions")
struct CanvasNameCaptionTests {

    @Test("An ordinary drawing says its name")
    func plainDrawingSaysItsName() {
        let caption = CanvasNameLabels.caption(name: "Home", version: nil, isCopy: false)
        #expect(caption.name == "Home")
        #expect(caption.version == nil)
    }

    @Test("A drawing that is one version of a component says the version, not the name")
    func versionReplacesTheName() {
        // Four drawings of one button all carry the name "Button", so the name
        // is the word that says nothing and the version is the word that says
        // everything. Printing both makes every label two and a half times the
        // width of the drawing it names.
        let caption = CanvasNameLabels.caption(name: "Button", version: "Disabled", isCopy: false)
        #expect(caption.name == nil)
        #expect(caption.version == "Disabled")
    }

    @Test("A copy says its version and never a name")
    func copySaysOnlyItsVersion() {
        #expect(CanvasNameLabels.caption(name: "Button", version: "Loading", isCopy: true)
            == CanvasNameLabels.Caption(name: nil, version: "Loading"))
        #expect(CanvasNameLabels.caption(name: "Button", version: nil, isCopy: true)
            == CanvasNameLabels.Caption(name: nil, version: nil))
    }

    @Test("An empty version is no version, so the name still prints")
    func emptyVersionIsNoVersion() {
        let caption = CanvasNameLabels.caption(name: "Button", version: "", isCopy: false)
        #expect(caption.name == "Button")
        #expect(caption.version == nil)
    }

    @Test("A caption prints the one word it has")
    func captionPrintsItsWord() {
        #expect(CanvasNameLabels.Caption(name: "Home", version: nil).word == "Home")
        #expect(CanvasNameLabels.Caption(name: nil, version: "Disabled").word == "Disabled")
        #expect(CanvasNameLabels.Caption(name: nil, version: nil).word == nil)
    }
}

/// What a drawing says while it is the one you are looking at: pointer resting
/// on it, or picked. At rest a copy of a component wears a bare mark and no
/// words at all, which is right for a screen built out of twelve buttons and
/// wrong for the one button you are asking about.
@Suite("The name on the drawing you are looking at")
struct CanvasLiveCaptionTests {

    @Test("A copy you are looking at says which component it came from")
    func liveCopySaysItsComponent() {
        let caption = CanvasNameLabels.caption(name: "Save button", version: nil,
                                               isCopy: true, isLive: true)
        #expect(caption.name == "Save button")
        #expect(caption.word == "Save button")
    }

    @Test("A copy at rest still says nothing")
    func restingCopyStaysQuiet() {
        #expect(CanvasNameLabels.caption(name: "Save button", version: nil, isCopy: true).word == nil)
    }

    @Test("A version you are looking at says whose version it is")
    func liveVersionSaysItsComponent() {
        // The trade the version labels made was the component name: four
        // drawings reading Default, Disabled, Loading, Pressed never say what
        // they are four versions OF. Looking at one is when you want that.
        let caption = CanvasNameLabels.caption(name: "Save button", version: "Disabled",
                                               isCopy: false, isLive: true)
        #expect(caption.name == "Save button")
        #expect(caption.version == "Disabled")
        #expect(caption.word == "Save button \u{00B7} Disabled")
    }

    @Test("A copy of an odd version you are looking at says both")
    func liveCopyOfAVersionSaysBoth() {
        #expect(CanvasNameLabels.caption(name: "Save button", version: "Disabled",
                                         isCopy: true, isLive: true).word
                == "Save button \u{00B7} Disabled")
    }

    @Test("A drawing that already said its name says exactly the same thing")
    func lookingAtAPlainComponentChangesNothing() {
        // A component with one drawing has always worn its name. Looking at it
        // must not make the word jump or grow, or every hover on the canvas
        // would twitch.
        let resting = CanvasNameLabels.caption(name: "Save button", version: nil, isCopy: false)
        let live = CanvasNameLabels.caption(name: "Save button", version: nil,
                                            isCopy: false, isLive: true)
        #expect(resting == live)
    }

    @Test("An empty version stays out of the words even when you are looking")
    func liveEmptyVersionIsStillNoVersion() {
        #expect(CanvasNameLabels.caption(name: "Save button", version: "",
                                         isCopy: true, isLive: true).word == "Save button")
    }
}

/// Four versions of one component in a row: the case the whole caption rule
/// exists for. Widths here are what the 10 point label font measures out to,
/// with a 14 point mark in front of the letters.
@Suite("A row of versions")
struct CanvasVersionRowTests {

    /// Four 78 point buttons at 50% zoom: 39 points wide, 51 points apart.
    private func row(textWidths: [CGFloat]) -> [CanvasNameLabel] {
        textWidths.enumerated().map { index, width in
            CanvasNameLabel(id: UUID(),
                            frameRect: CGRect(x: CGFloat(index) * 51, y: 400, width: 39, height: 18),
                            textWidth: width, leadingInset: 14, fitsWholeText: true)
        }
    }

    @Test("Version-only labels leave every drawing in the row with a readable label")
    func versionOnlyLabelsStayReadable() {
        // "Default", "Disabled", "Loading", "Pressed".
        let stacked = CanvasNameLabels.stacked(row(textWidths: [42, 48, 45, 46]))
        let chips = stacked.map(CanvasNameLabels.chipBox(for:))
        for (a, b) in chips.enumerated().flatMap({ i, c in chips.dropFirst(i + 1).map { (c, $0) } }) {
            #expect(!a.intersects(b), "two version labels must never print on top of each other")
        }
        // ...and none of them climbs far enough to stop belonging to its own
        // drawing: one line up is a caption, four is a kite.
        for label in stacked {
            let lift = 400 - label.frameRect.minY
            #expect(lift <= CanvasNameLabels.rowStep,
                    "a version label should never climb more than one line")
        }
    }

    @Test("The same row with the component name repeated on every label climbs four lines")
    func repeatingTheNameBuildsAStaircase() {
        // "Button \u{00B7} Default" and friends: about 92 points of letters over a
        // 39 point drawing. This is the shape the caption rule exists to stop,
        // kept here so it cannot come back unnoticed.
        let stacked = CanvasNameLabels.stacked(row(textWidths: [92, 98, 95, 96]))
        let deepest = stacked.map { 400 - $0.frameRect.minY }.max() ?? 0
        #expect(deepest >= CanvasNameLabels.rowStep * 2,
                "repeating the name forces the row into a staircase")
    }
}

/// Typing over a name that says more than one thing. A drawing reading
/// "Save button · Disabled" renames its VERSION, so the box that opens holds
/// only "Disabled" — and somebody who just read the longer words can
/// reasonably expect to be renaming all of them. The fix is geometry: the box
/// opens over the letters it is going to replace, with the words it will not
/// touch still printed in front of it.
@Suite("The box that opens over a name")
struct CanvasNameFieldBoxTests {

    private var label: CanvasNameLabel {
        CanvasNameLabel(id: UUID(),
                        frameRect: CGRect(x: 200, y: 160, width: 180, height: 60),
                        textWidth: 120,
                        leadingInset: 18,
                        fitsWholeText: true)
    }

    @Test("The words in front of a version are the name and the dot")
    func versionPrefixIsTheNameAndTheDot() {
        let caption = CanvasNameLabels.Caption(name: "Save button", version: "Disabled")
        #expect(caption.versionPrefix == "Save button \u{00B7} ")
        // What it prints is the prefix followed by the version, with nothing
        // added or dropped in between: the field can stand exactly where the
        // version's letters were.
        #expect(caption.word == (caption.versionPrefix ?? "") + "Disabled")
    }

    @Test("A caption saying one thing has nothing standing in front of it")
    func oneWordCaptionHasNoPrefix() {
        #expect(CanvasNameLabels.Caption(name: nil, version: "Disabled").versionPrefix == nil)
        #expect(CanvasNameLabels.Caption(name: "Home", version: nil).versionPrefix == nil)
        #expect(CanvasNameLabels.Caption(name: nil, version: nil).versionPrefix == nil)
        #expect(CanvasNameLabels.Caption(name: "Save button", version: "").versionPrefix == nil)
    }

    @Test("A plain name opens its box over the whole word")
    func plainNameOpensOverTheWholeWord() {
        let box = CanvasNameLabels.box(for: label)
        let field = CanvasNameLabels.fieldBox(for: label, typed: 40)
        #expect(field.minX == box.minX - 3)
        #expect(field.minY == box.minY - 2)
        #expect(field.height == box.height + 4)
    }

    @Test("A box that keeps some words opens after them")
    func keptWordsPushTheBoxAlong() {
        let kept: CGFloat = 74
        let plain = CanvasNameLabels.fieldBox(for: label, typed: 40)
        let shifted = CanvasNameLabels.fieldBox(for: label, keeping: kept, typed: 40)
        #expect(shifted.minX == plain.minX + kept)
        // Same line, same height: the words in front and the letters inside
        // the box have to read as one label rather than two.
        #expect(shifted.minY == plain.minY)
        #expect(shifted.height == plain.height)
        // And it starts where those words end, so it covers the letters it
        // replaces and none of the ones it keeps.
        #expect(shifted.minX >= CanvasNameLabels.box(for: label).minX + kept - 3)
    }

    @Test("The box grows ahead of the typing and stops at the cap")
    func boxGrowsWithWhatIsTyped() {
        let empty = CanvasNameLabels.fieldBox(for: label, typed: 0)
        #expect(empty.width == CanvasNameLabels.fieldMinimumWidth)
        let some = CanvasNameLabels.fieldBox(for: label, typed: 90)
        #expect(some.width == 90 + CanvasNameLabels.fieldSlack)
        let long = CanvasNameLabels.fieldBox(for: label, typed: 900)
        #expect(long.width == CanvasNameLabels.maximumWidth)
    }
}
