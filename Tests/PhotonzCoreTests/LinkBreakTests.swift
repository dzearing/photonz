import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// One notice for every link that quietly breaks
/// (`docs/design/ui-building.md`, "When a link breaks, the app says so").
///
/// Four things stop following what they came from without anybody saying so: a
/// color drifts off the style it was wearing, a part of a copy's look is set by
/// hand, a copy is ungrouped into loose layers, and an original is deleted out
/// from under its copies. They are all the same fact, so they are all one diff
/// of the document before and after an edit, and one sentence.
struct LinkBreakTests {

    // MARK: - Fixtures

    private func box(_ name: String = "Box", fill: String? = "#3366FF",
                     stroke: String = "#101010",
                     rect: CGRect = CGRect(x: 0, y: 0, width: 60, height: 30)) -> Layer {
        var annotation = AnnotationContent(shape: .rectangle, start: .zero,
                                           end: CGPoint(x: rect.width, y: rect.height))
        annotation.colorHex = stroke
        annotation.fillColorHex = fill
        return Layer(name: name, content: .annotation(annotation), frame: rect)
    }

    private func document(_ layers: [Layer]) -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 800, height: 600), layers: layers)
    }

    /// One component named Setting, with two copies of it out on the canvas.
    private func withTwoCopies() -> (history: History, main: UUID, component: UUID,
                                     a: UUID, b: UUID) {
        var doc = document([box("Box", rect: CGRect(x: 10, y: 10, width: 60, height: 30)),
                            box("Label", rect: CGRect(x: 20, y: 50, width: 40, height: 30))])
        let group = doc.groupLayers(ids: Set(doc.layers.map(\.id)), name: "Setting")!
        let component = doc.makeComponent(id: group.id)!
        let a = doc.insertComponentInstance(of: component, at: CGPoint(x: 200, y: 200))!
        let b = doc.insertComponentInstance(of: component, at: CGPoint(x: 500, y: 400))!
        return (History(document: doc), group.id, component, a, b)
    }

    // MARK: - A color lets go of its style

    @Test func paintingOverABoundColorSaysWhichStyleItLetGoOf() {
        var history = History(document: document([box(fill: "#3366FF")]))
        let id = history.current.layers[0].id
        history.perform { _ = $0.saveColorStyle(from: id, slot: .fill, name: "Accent") }
        let report = history.perform { doc in
            doc.updateLayer(id: id) { $0 = AnnotationBuilder.restyled($0, fillColorHex: .some("#FF0000")) }
        }
        #expect(report.linkBreaks.title == "Stopped following")
        #expect(report.linkBreaks.detail == "1 color no longer follows Accent")
    }

    @Test func severalColorsLettingGoOfOneStyleAreOneSentence() {
        var history = History(document: document([box(fill: "#3366FF"), box(fill: "#3366FF")]))
        let ids = history.current.layers.map(\.id)
        var styleID = UUID()
        history.perform { styleID = $0.saveColorStyle(from: ids[0], slot: .fill, name: "Accent")! }
        history.perform { _ = $0.bindColorStyle(layerID: ids[1], slot: .fill, styleID: styleID) }
        let report = history.perform { doc in
            for id in ids {
                doc.updateLayer(id: id) { $0 = AnnotationBuilder.restyled($0, fillColorHex: .some("#FF0000")) }
            }
        }
        #expect(report.linkBreaks.detail == "2 colors no longer follow Accent")
    }

    @Test func pointingASlotAtAnotherStyleIsAChoiceAndBreaksNothing() {
        var history = History(document: document([box(fill: "#3366FF")]))
        let id = history.current.layers[0].id
        var other = UUID()
        history.perform { _ = $0.saveColorStyle(from: id, slot: .fill, name: "Accent") }
        history.perform { other = $0.addColorStyle(name: "Warning", colorHex: "#FF0000") }
        let report = history.perform { _ = $0.bindColorStyle(layerID: id, slot: .fill, styleID: other) }
        #expect(report.linkBreaks.isEmpty)
    }

    @Test func removingAStyleOnPurposeSaysNothing() {
        var history = History(document: document([box(fill: "#3366FF")]))
        let id = history.current.layers[0].id
        var styleID = UUID()
        history.perform { styleID = $0.saveColorStyle(from: id, slot: .fill, name: "Accent")! }
        let report = history.perform { $0.deleteColorStyle(id: styleID) }
        #expect(report.linkBreaks.isEmpty)
    }

    @Test func undoPutsTheColorBackOnItsStyle() {
        var history = History(document: document([box(fill: "#3366FF")]))
        let id = history.current.layers[0].id
        var styleID = UUID()
        history.perform { styleID = $0.saveColorStyle(from: id, slot: .fill, name: "Accent")! }
        history.perform { doc in
            doc.updateLayer(id: id) { $0 = AnnotationBuilder.restyled($0, fillColorHex: .some("#FF0000")) }
        }
        history.undo()
        #expect(history.current.layer(id: id)?.colorStyleID(for: .fill) == styleID)
        #expect(history.current.layer(id: id)?.colorHex(for: .fill) == "#3366FF")
    }

    // MARK: - A part of a copy's look stops following

    @Test func fadingACopyByHandNamesThePartThatStoppedFollowing() {
        var (history, _, _, a, _) = withTwoCopies()
        let report = history.perform { $0.updateLayer(id: a) { $0.style.opacity = 0.3 } }
        #expect(report.linkBreaks.title == "Stopped following")
        #expect(report.linkBreaks.detail == "Opacity on this copy no longer follows Setting")
    }

    @Test func draggingTheSameSliderOnSaysItOnceAndNotEveryFrame() {
        var (history, _, _, a, _) = withTwoCopies()
        _ = history.perform { $0.updateLayer(id: a) { $0.style.opacity = 0.3 } }
        let again = history.perform { $0.updateLayer(id: a) { $0.style.opacity = 0.28 } }
        #expect(again.linkBreaks.isEmpty)
    }

    @Test func stylingTheOriginalBreaksNothingEvenThoughEveryCopyMoves() {
        var (history, main, _, _, _) = withTwoCopies()
        let report = history.perform { $0.updateLayer(id: main) { $0.style.cornerRadius = 12 } }
        #expect(report.componentSync.updatedInstances == 2)
        #expect(report.linkBreaks.isEmpty)
    }

    @Test func twoPartsSetAtOnceReadAsParts() {
        var (history, _, _, a, _) = withTwoCopies()
        let report = history.perform {
            $0.updateLayer(id: a) { layer in
                layer.style.opacity = 0.3
                layer.style.blurRadius = 4
            }
        }
        #expect(report.linkBreaks.detail == "2 parts of this copy no longer follow Setting")
    }

    @Test func puttingAPartBackOnTheOriginalBreaksNothing() {
        var (history, _, _, a, _) = withTwoCopies()
        history.perform { $0.updateLayer(id: a) { $0.style.opacity = 0.3 } }
        let report = history.perform { $0.clearInstanceStyleOverride(instance: a, field: .opacity) }
        #expect(report.linkBreaks.isEmpty)
    }

    @Test func undoPutsThePartBackOnFollowingTheOriginal() {
        var (history, _, _, a, _) = withTwoCopies()
        history.perform { $0.updateLayer(id: a) { $0.style.opacity = 0.3 } }
        history.undo()
        #expect(history.current.instanceStyleOverrides(instance: a).isEmpty)
    }

    // MARK: - A copy is ungrouped into loose layers

    @Test func ungroupingACopySaysItsPiecesAreLooseNow() {
        var (history, _, _, a, _) = withTwoCopies()
        let report = history.perform { _ = $0.ungroupLayers(ids: [a]) }
        #expect(report.linkBreaks.title == "Stopped following")
        #expect(report.linkBreaks.detail == "The pieces of this copy no longer follow Setting")
    }

    @Test func ungroupingTwoCopiesAtOnceIsOneSentence() {
        var (history, _, _, a, b) = withTwoCopies()
        let report = history.perform { _ = $0.ungroupLayers(ids: [a, b]) }
        #expect(report.linkBreaks.detail == "The pieces of 2 copies no longer follow Setting")
    }

    @Test func ungroupingAnOrdinaryGroupSaysNothing() {
        var doc = document([box("Box"), box("Label")])
        let group = doc.groupLayers(ids: Set(doc.layers.map(\.id)), name: "Pair")!
        var history = History(document: doc)
        let report = history.perform { _ = $0.ungroupLayers(ids: [group.id]) }
        #expect(report.linkBreaks.isEmpty)
    }

    @Test func undoPutsAnUngroupedCopyBackTogether() {
        var (history, _, component, a, _) = withTwoCopies()
        history.perform { _ = $0.ungroupLayers(ids: [a]) }
        history.undo()
        #expect(history.current.layer(id: a)?.instanceOf == component)
    }

    // MARK: - An original is deleted out from under its copies

    @Test func deletingAnOriginalSaysHowManyCopiesWereLeftBehind() {
        var (history, main, _, _, _) = withTwoCopies()
        let report = history.perform { $0.removeLayer(id: main) }
        #expect(report.linkBreaks.title == "Stopped following")
        #expect(report.linkBreaks.detail == "2 copies no longer follow Setting")
    }

    @Test func deletingAnOriginalAndItsCopiesTogetherLeavesNobodyBehind() {
        var (history, main, _, a, b) = withTwoCopies()
        let report = history.perform { doc in
            for id in [main, a, b] { doc.removeLayer(id: id) }
        }
        #expect(report.linkBreaks.isEmpty)
    }

    @Test func deletingACopyBreaksNothing() {
        var (history, _, _, a, _) = withTwoCopies()
        let report = history.perform { $0.removeLayer(id: a) }
        #expect(report.linkBreaks.isEmpty)
    }

    @Test func undoPutsTheCopiesBackOnTheirOriginal() {
        var (history, main, component, a, b) = withTwoCopies()
        history.perform { $0.removeLayer(id: main) }
        #expect(history.current.layer(id: a)?.instanceOf == nil)
        history.undo()
        #expect(history.current.layer(id: a)?.instanceOf == component)
        #expect(history.current.layer(id: b)?.instanceOf == component)
    }

    // MARK: - What is inside a copy belongs to the original

    @Test func paintingOverAColorInsideAnOriginalCountsItOnceNotOncePerCopy() {
        var doc = document([box("Box", fill: "#3366FF")])
        let inner = doc.layers[0].id
        let group = doc.groupLayers(ids: [inner], name: "Setting")!
        let component = doc.makeComponent(id: group.id)!
        _ = doc.insertComponentInstance(of: component, at: CGPoint(x: 300, y: 300))
        _ = doc.insertComponentInstance(of: component, at: CGPoint(x: 600, y: 300))
        var history = History(document: doc)
        history.perform { _ = $0.saveColorStyle(from: inner, slot: .fill, name: "Accent") }
        let report = history.perform { doc in
            doc.updateLayer(id: inner) { $0 = AnnotationBuilder.restyled($0, fillColorHex: .some("#FF0000")) }
        }
        #expect(report.linkBreaks.detail == "1 color no longer follows Accent")
    }

    // MARK: - The shared sentence

    @Test func anEditThatBreaksNothingSaysNothing() {
        var (history, _, _, a, _) = withTwoCopies()
        let report = history.perform { $0.updateLayer(id: a) { $0.frame.origin.x += 20 } }
        #expect(report.linkBreaks.isEmpty)
        #expect(report.linkBreaks.detail == nil)
    }

    @Test func aDocumentWithNoStylesAndNoCopiesNeverPaysForTheWalk() {
        var history = History(document: document([box(), box()]))
        let report = history.perform { $0.updateLayer(id: $0.layers[0].id) { $0.frame.origin.x += 5 } }
        #expect(report.linkBreaks.isEmpty)
    }

    @Test func twoKindsOfBreakInOneStepLeadWithTheHeavierOneAndCountTheRest() {
        // One copy taken apart and the original deleted in the same step: the
        // other copy is stranded, and that is the one worth leading with.
        var (history, main, _, a, _) = withTwoCopies()
        let report = history.perform { doc in
            _ = doc.ungroupLayers(ids: [a])
            doc.removeLayer(id: main)
        }
        #expect(report.linkBreaks.detail == "1 copy no longer follows Setting, and 1 more link broke")
    }

    @Test func everyKindReadsAsTheSameSentence() {
        // The point of the shared piece of code: one verdict, one frame.
        let cases: [LinkBreak] = [
            LinkBreak(kind: .colorStyle, count: 1, source: "Accent"),
            LinkBreak(kind: .instanceStyle, count: 1, source: "Setting", part: "Opacity"),
            LinkBreak(kind: .instanceUngrouped, count: 1, source: "Setting"),
            LinkBreak(kind: .originalDeleted, count: 1, source: "Setting")
        ]
        for one in cases {
            let report = LinkBreakReport(breaks: [one])
            #expect(report.title == "Stopped following")
            #expect(report.detail?.contains("no longer follow") == true)
        }
    }

    @Test func aBreakWithNoNameToPointAtStillReads() {
        let report = LinkBreakReport(breaks: [LinkBreak(kind: .originalDeleted, count: 3, source: nil)])
        #expect(report.detail == "3 copies no longer follow their originals")
    }
}

/// The pill a break is said in.
struct LinkBreakNoticeTests {

    private var broken: CopyConfirmation.Subject {
        .linksBroken(LinkBreakReport(breaks: [LinkBreak(kind: .colorStyle, count: 1, source: "Accent")]))
    }

    @Test func aBrokenLinkReadsAsOneVerdictAndOneLine() {
        let pill = CopyConfirmation(subject: broken, shownAt: Date())
        #expect(pill.title == "Stopped following")
        #expect(pill.detail == "1 color no longer follows Accent")
    }

    @Test func aBrokenLinkStaysUpLongerThanACopiedNotice() {
        let t0 = Date()
        let pill = CopyConfirmation(subject: broken, shownAt: t0)
        #expect(pill.lifetime > CopyConfirmation.lifetime)
        #expect(pill.isLive(at: t0.addingTimeInterval(CopyConfirmation.lifetime + 0.1)))
        #expect(!pill.isLive(at: t0.addingTimeInterval(pill.lifetime)))
    }

    @Test func everyOtherNoticeKeepsItsOwnClock() {
        let pill = CopyConfirmation(subject: .measurements(count: 1), shownAt: Date())
        #expect(pill.lifetime == CopyConfirmation.lifetime)
    }
}
