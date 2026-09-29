import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// A title with a fade in and a fade out shows while it plays
/// (`a-title-with-a-fade-in-and-a-fade-out-shows-duri`).
///
/// The user put a title on a recording, gave it Animate In, Fade and Animate
/// Out, Fade, and never saw it play. What they hit was the canvas compositing
/// a big recording without telling the renderer (`ShownSizeCompositeTests`);
/// these hold the model's half: whatever order the two presets go on in, and
/// however the title's bar is moved or trimmed afterwards, the words are gone
/// at the title's two ends, up in the middle, and the keys sit at the title's
/// own in and out. Trimming used to leave an Out's keys where the old end was,
/// so a title dragged longer went off early and stayed gone.
@Suite("A faded title plays the way its keys say")
struct TitleFadePlaybackTests {

    typealias Fixture = ClipKeyMarksTests

    /// What the renderer composites for the title at a moment: its opacity,
    /// or nought where it is not on screen at all.
    static func shownOpacity(_ doc: PhotonzDocument, _ id: UUID, atMS ms: Int) -> Double {
        guard let layer = doc.drawn(atTimeMS: ms).layers.first(where: { $0.id == id }),
              layer.isVisible else { return 0 }
        return layer.style.opacity
    }

    static func value(_ doc: PhotonzDocument, _ id: UUID, _ property: MotionProperty, atMS ms: Int) -> MotionValue? {
        doc.keyedValue(layerID: id, .motion(property), atDocumentTimeMS: ms)
    }

    /// Down at both ends, fully up in the middle, rising over the first half
    /// second and falling over the last.
    static func expectFadesInAndOut(_ doc: PhotonzDocument, _ id: UUID,
                                    sourceLocation: SourceLocation = #_sourceLocation) {
        guard let time = doc.layer(id: id)?.time else {
            Issue.record("the title has no time", sourceLocation: sourceLocation)
            return
        }
        let at = { (ms: Int) in Self.shownOpacity(doc, id, atMS: ms) }
        #expect(Fixture.number(Self.value(doc, id, .opacity, atMS: time.inMS)) == 0,
                "down at its in point", sourceLocation: sourceLocation)
        #expect(at(time.inMS + 100) > 0.05 && at(time.inMS + 100) < 0.95,
                "on its way up a tenth of a second in", sourceLocation: sourceLocation)
        let middle = (time.inMS + time.outMS) / 2
        #expect(at(middle) == 1, "fully up in the middle", sourceLocation: sourceLocation)
        #expect(at(time.outMS - 600) == 1, "still up before the fade out starts",
                sourceLocation: sourceLocation)
        #expect(at(time.outMS - 100) > 0.05 && at(time.outMS - 100) < 0.95,
                "on its way down a tenth of a second before its out", sourceLocation: sourceLocation)
        #expect((Fixture.number(Self.value(doc, id, .opacity, atMS: time.outMS)) ?? 100) < 1,
                "down at its out point", sourceLocation: sourceLocation)
        let marks = doc.clipKeyMarks(layerID: id).map(\.documentMS)
        #expect(marks == [time.inMS, time.inMS + 500, time.outMS - 500, time.outMS],
                "the keys sit at the title's own in and out", sourceLocation: sourceLocation)
    }

    static func faded(outFirst: Bool = false) -> (PhotonzDocument, UUID) {
        var (doc, id) = Fixture.withTitle()
        if outFirst {
            doc.animateOut(.fade, layerID: id)
            doc.animateIn(.fade, layerID: id)
        } else {
            doc.animateIn(.fade, layerID: id)
            doc.animateOut(.fade, layerID: id)
        }
        return (doc, id)
    }

    @Test("Fade In and Fade Out, in either order, bring the words up and take them down")
    func eitherOrder() {
        for outFirst in [false, true] {
            let (doc, id) = Self.faded(outFirst: outFirst)
            Self.expectFadesInAndOut(doc, id)
        }
    }

    @Test("Moving the title's bar carries its fades with it")
    func movedBar() {
        var (doc, id) = Self.faded()
        let moved = doc.moveClip(id, toInMS: 500)
        #expect(moved)
        Self.expectFadesInAndOut(doc, id)
    }

    @Test("Trimming either end of the bar keeps the fades at the ends",
          arguments: ["end later", "end earlier", "start earlier", "start later", "end dragged"])
    func trimmedBar(edit: String) {
        var (doc, id) = Self.faded()
        let moved: Bool
        switch edit {
        case "end later": moved = doc.moveLayerEnd(id, toMS: 9500)
        case "end earlier": moved = doc.moveLayerEnd(id, toMS: 5000)
        case "start earlier": moved = doc.moveLayerStart(id, toMS: 1000)
        case "start later": moved = doc.moveLayerStart(id, toMS: 3000)
        default: moved = doc.trimClipEnd(id, ofPiece: 0, byMS: 1500)
        }
        #expect(moved)
        Self.expectFadesInAndOut(doc, id)
    }

    /// Whether a layer is fully off by the value of the one property a preset
    /// moves it with.
    static func isOff(_ kind: TitleAnimation, isIn: Bool, _ doc: PhotonzDocument, _ id: UUID, atMS ms: Int) -> Bool {
        switch kind {
        case .fade:
            return (Fixture.number(Self.value(doc, id, .opacity, atMS: ms)) ?? 100) < 1
        case .slide:
            let x = Fixture.point(Self.value(doc, id, .position, atMS: ms))?.x ?? 100
            return isIn ? x <= -400 : x >= doc.canvasSize.width
        case .pop:
            return (Fixture.number(Self.value(doc, id, .opacity, atMS: ms)) ?? 100) < 1
                && (Fixture.number(Self.value(doc, id, .scale, atMS: ms)) ?? 100) < 20
        case .scale:
            return (Fixture.number(Self.value(doc, id, .scale, atMS: ms)) ?? 100) < 20
        }
    }

    /// Every property a preset may key, read at a moment, so the resting
    /// values before a trim can be compared with the ones after it.
    static func pose(_ doc: PhotonzDocument, _ id: UUID, atMS ms: Int) -> String {
        [MotionProperty.opacity, .scale, .position]
            .map { Self.value(doc, id, $0, atMS: ms).map { "\($0)" } ?? "unkeyed" }
            .joined(separator: " | ")
    }

    @Test("Every pair of presets keeps coming on at the start and going off at the end after a trim",
          arguments: TitleAnimation.allCases)
    func everyPairAfterATrim(inKind: TitleAnimation) {
        for outKind in TitleAnimation.allCases {
            for edit in ["end later", "start earlier", "end earlier"] {
                var (doc, id) = Fixture.withTitle()
                doc.animateIn(inKind, layerID: id)
                doc.animateOut(outKind, layerID: id)
                let resting = Self.pose(doc, id, atMS: 5000)
                switch edit {
                case "end later": doc.moveLayerEnd(id, toMS: 9500)
                case "start earlier": doc.moveLayerStart(id, toMS: 1000)
                default: doc.moveLayerEnd(id, toMS: 5000)
                }
                guard let time = doc.layer(id: id)?.time else { continue }
                let label = "\(inKind.title) in, \(outKind.title) out, \(edit)"
                #expect(Self.isOff(inKind, isIn: true, doc, id, atMS: time.inMS), "\(label): off at the in point")
                let middle = Self.pose(doc, id, atMS: (time.inMS + time.outMS) / 2)
                let late = Self.pose(doc, id, atMS: time.outMS - 600)
                #expect(middle == resting, "\(label): up in the middle")
                #expect(late == resting, "\(label): up until the out starts")
                #expect(Self.isOff(outKind, isIn: false, doc, id, atMS: time.outMS), "\(label): off at the out point")
            }
        }
    }

    @Test("A key somebody put in the middle stays where they put it when the end moves")
    func middleKeysStay() {
        var (doc, id) = Self.faded()
        doc.startKeying(layerID: id, .motion(.scale), atDocumentTimeMS: 5000)
        doc.moveLayerEnd(id, toMS: 9500)
        #expect(doc.clipKeyMarks(layerID: id).map(\.documentMS).contains(5000))
    }

    @Test("Trimmed shorter than its two fades, a title still comes up and is gone by its end")
    func trimmedVeryShort() {
        var (doc, id) = Self.faded()
        doc.moveLayerEnd(id, toMS: 2800)
        guard let time = doc.layer(id: id)?.time else { Issue.record("no time"); return }
        #expect(time.lengthMS == 800)
        #expect(Fixture.number(Self.value(doc, id, .opacity, atMS: time.inMS)) == 0)
        #expect(Fixture.number(Self.value(doc, id, .opacity, atMS: time.inMS + 500)) == 100)
        #expect((Fixture.number(Self.value(doc, id, .opacity, atMS: time.outMS)) ?? 100) < 1)
        let marks = doc.clipKeyMarks(layerID: id).map(\.documentMS)
        #expect(marks.allSatisfy { $0 >= time.inMS && $0 <= time.outMS }, "every key on the bar: \(marks)")
    }
}
