import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Punching in on something and holding there (`ClipReframe.swift`).
///
/// The task asked for the animation model pointed at Scale and Position rather
/// than a zoom tool, and said that if it needed machinery of its own the model
/// was wrong. It needed two things, both of them general: a motion that can
/// hold part way through, and a clip's motions read on the clip's own clock.
/// Everything below is written against those two rather than against a feature.
@Suite("Punch in on something and hold there")
struct ClipReframeTests {

    // A screen recording: twelve seconds of it, captured at twice the size it
    // is laid out at, which is what a Mac screen recording actually is.
    static let movieID = UUID(uuidString: "C10FEEDD-1111-2222-3333-444444444444")!

    static func movie(pixelSize: CGSize = CGSize(width: 2560, height: 1440)) -> MovieRef {
        MovieRef(id: movieID, pixelSize: pixelSize, durationMS: 12_000)
    }

    static func clip(pixelSize: CGSize = CGSize(width: 2560, height: 1440),
                     inMS: Int = 0, outMS: Int = 12_000, sourceInMS: Int = 0) -> Layer {
        let reel = movie(pixelSize: pixelSize)
        var layer = Layer(name: "screen-recording",
                          content: .image(reel.frameRef(atSourceMS: 0)),
                          frame: CGRect(x: 0, y: 0, width: 1280, height: 720))
        layer.movie = reel
        layer.time = LayerTime(inMS: inMS, outMS: outMS,
                               sourceInMS: sourceInMS, sourceLengthMS: 12_000)
        return layer
    }

    static func document(_ layer: Layer) -> PhotonzDocument {
        var document = PhotonzDocument(canvasSize: CGSize(width: 1280, height: 720),
                                       layers: [layer])
        document.durationMS = layer.time?.outMS
        return document
    }

    /// Where a point of the clip as it was drawn ends up on the canvas at a
    /// moment: the whole answer to "is it pointing at the right thing".
    static func onScreen(_ point: CGPoint, of id: UUID,
                         in document: PhotonzDocument, atMS ms: Int) -> CGPoint? {
        guard let drawn = document.drawn(atTimeMS: ms).layer(id: id),
              let authored = document.layer(id: id) else { return nil }
        let box = authored.frame.standardized
        let now = drawn.frame.standardized
        guard box.width > 0, box.height > 0 else { return nil }
        let factor = now.width / box.width
        return CGPoint(x: now.minX + (point.x - box.minX) * factor,
                       y: now.minY + (point.y - box.minY) * factor)
    }

    static func scalePercent(of id: UUID, in document: PhotonzDocument, atMS ms: Int) -> Double {
        guard let drawn = document.drawn(atTimeMS: ms).layer(id: id),
              let authored = document.layer(id: id),
              authored.frame.width > 0 else { return 100 }
        return Double(drawn.frame.standardized.width / authored.frame.standardized.width) * 100
    }

    // MARK: - A motion can hold part way through

    @Test("A motion with no stops on it is exactly the motion it always was")
    func twoKeysAreUnchanged() {
        let motion = LayerMotion(property: .opacity, from: .number(0), to: .number(100),
                                 timing: MotionTiming(startMS: 0, durationMS: 1000),
                                 curve: .linear, repeats: .once)
        #expect(motion.value(atMS: 0, cycleMS: 4000) == .number(0))
        #expect(motion.value(atMS: 500, cycleMS: 4000) == .number(50))
        #expect(motion.value(atMS: 1000, cycleMS: 4000) == .number(100))
        #expect(motion.keys.count == 2)
    }

    @Test("Two keys holding the same value are a hold, and nothing moves across it")
    func aHoldHolds() {
        let motion = LayerMotion(property: .scale, from: .number(100), to: .number(100),
                                 timing: MotionTiming(startMS: 0, durationMS: 4000),
                                 curve: .linear, repeats: .once,
                                 stops: [MotionStop(atMS: 1000, value: .number(220)),
                                         MotionStop(atMS: 3000, value: .number(220))])
        #expect(motion.value(atMS: 1000, cycleMS: 8000) == .number(220))
        // Every moment of the hold is the same number, which is what a camera
        // that has arrived somewhere does.
        for ms in stride(from: 1000, through: 3000, by: 250) {
            #expect(motion.value(atMS: ms, cycleMS: 8000) == .number(220))
        }
        #expect(motion.value(atMS: 4000, cycleMS: 8000) == .number(100))
        #expect(motion.keys.count == 4)
    }

    @Test("A motion that holds says the whole journey rather than its two ends")
    func aHoldReadsAsAJourney() {
        let motion = LayerMotion(property: .scale, from: .number(100), to: .number(100),
                                 timing: MotionTiming(startMS: 0, durationMS: 4000),
                                 curve: .easeInOut, repeats: .once,
                                 stops: [MotionStop(atMS: 1000, value: .number(220)),
                                         MotionStop(atMS: 3000, value: .number(220))])
        #expect(motion.summary == "100% → 220% → 220% → 100% over 4s")
    }

    @Test("A motion with stops on it writes them, and one without writes nothing extra")
    func stopsSurviveBeingWrittenDown() throws {
        let plain = LayerMotion(property: .opacity, from: .number(0), to: .number(100),
                                timing: MotionTiming(startMS: 0, durationMS: 500))
        let written = try JSONEncoder().encode(plain)
        let text = try #require(String(data: written, encoding: .utf8))
        #expect(!text.contains("stops"))

        let held = LayerMotion(property: .scale, from: .number(100), to: .number(100),
                               timing: MotionTiming(startMS: 0, durationMS: 4000),
                               repeats: .once,
                               stops: [MotionStop(atMS: 1000, value: .number(220))])
        let back = try JSONDecoder().decode(LayerMotion.self,
                                            from: try JSONEncoder().encode(held))
        #expect(back.stops?.count == 1)
        #expect(back.value(atMS: 1000, cycleMS: 8000) == .number(220))
    }

    // MARK: - Pointing at the thing

    @Test("Pointing at a quarter of the frame punches in to four times the size")
    func aRegionBecomesAScale() throws {
        let frame = CGRect(x: 0, y: 0, width: 1280, height: 720)
        let quarter = CGRect(x: 320, y: 180, width: 320, height: 180)
        #expect(ClipReframe.scalePercent(fitting: quarter, into: frame) == 400)
        // A box the shape of nothing in particular fits by its tighter side, so
        // everything inside it stays on screen.
        let wide = CGRect(x: 0, y: 300, width: 640, height: 100)
        let fit = try #require(ClipReframe.scalePercent(fitting: wide, into: frame))
        #expect(abs(fit - 200) < 0.001)
    }

    @Test("A slip of the hand is not a region")
    func aTinyBoxIsIgnored() {
        let frame = CGRect(x: 0, y: 0, width: 1280, height: 720)
        #expect(ClipReframe.scalePercent(fitting: CGRect(x: 10, y: 10, width: 3, height: 3),
                                         into: frame) == nil)
    }

    @Test("What you pointed at is in the middle of the frame when the move arrives")
    func thePunchLandsOnWhatWasPointedAt() throws {
        let clip = Self.clip()
        var document = Self.document(clip)
        // A button in the lower right quarter of the recording.
        let button = CGRect(x: 840, y: 470, width: 200, height: 80)
        let landed1 = document.punchIn(layerID: clip.id, onRegion: button, atTimeMS: 5000)
        #expect(landed1)

        let landed = try #require(Self.onScreen(CGPoint(x: button.midX, y: button.midY),
                                                of: clip.id, in: document, atMS: 5000))
        #expect(abs(landed.x - 640) < 0.5)
        #expect(abs(landed.y - 360) < 0.5)
    }

    @Test("Before the move the clip is untouched, and the whole picture is on screen")
    func itStartsWide() {
        let clip = Self.clip()
        var document = Self.document(clip)
        let landed2 = document.punchIn(layerID: clip.id,
                                 onRegion: CGRect(x: 840, y: 470, width: 200, height: 80),
                                 atTimeMS: 5000)
        #expect(landed2)
        #expect(abs(Self.scalePercent(of: clip.id, in: document, atMS: 0) - 100) < 0.001)
        #expect(abs(Self.scalePercent(of: clip.id, in: document, atMS: 3000) - 100) < 0.001)
    }

    // MARK: - Smooth, not stepped

    @Test("The push in never goes backwards and never arrives in one step")
    func thePushIsSmooth() {
        let clip = Self.clip()
        var document = Self.document(clip)
        let landed3 = document.punchIn(layerID: clip.id,
                                 onRegion: CGRect(x: 840, y: 470, width: 200, height: 80),
                                 atTimeMS: 5000)
        #expect(landed3)
        var last = Self.scalePercent(of: clip.id, in: document, atMS: 3800)
        var biggestStep = 0.0
        // Every frame of the move, at the grid frames are actually fetched on.
        for ms in stride(from: 3800, through: 5000, by: 33) {
            let now = Self.scalePercent(of: clip.id, in: document, atMS: ms)
            #expect(now >= last - 0.001)
            biggestStep = max(biggestStep, now - last)
            last = now
        }
        // A stepped move would put the whole change into one frame. Eased, no
        // single frame carries more than a small share of it.
        #expect(biggestStep < (last - 100) / 5)
        #expect(last > 100)
    }

    @Test("It leans in and settles rather than arriving at a constant rate")
    func thePushIsEased() {
        let clip = Self.clip()
        var document = Self.document(clip)
        let landed4 = document.punchIn(layerID: clip.id,
                                 onRegion: CGRect(x: 840, y: 470, width: 200, height: 80),
                                 atTimeMS: 5000)
        #expect(landed4)
        let start = Self.scalePercent(of: clip.id, in: document, atMS: 3800)
        let end = Self.scalePercent(of: clip.id, in: document, atMS: 5000)
        let quarter = Self.scalePercent(of: clip.id, in: document, atMS: 4100)
        let linearQuarter = start + (end - start) * 0.25
        // A quarter of the way through in TIME, an eased move has done less
        // than a quarter of the distance: that is the lean.
        #expect(quarter < linearQuarter)
    }

    // MARK: - It holds where it lands

    @Test("After the move the frame does not budge until it is told to")
    func itHoldsWhereItLands() {
        let clip = Self.clip()
        var document = Self.document(clip)
        let landed5 = document.punchIn(layerID: clip.id,
                                 onRegion: CGRect(x: 840, y: 470, width: 200, height: 80),
                                 atTimeMS: 5000)
        #expect(landed5)
        let landed = Self.scalePercent(of: clip.id, in: document, atMS: 5000)
        for ms in [5001, 6000, 8000, 11_999] {
            #expect(abs(Self.scalePercent(of: clip.id, in: document, atMS: ms) - landed) < 0.001)
        }
    }

    @Test("Pulling back out holds the tight frame until the playhead, then leaves")
    func theHoldIsTheGap() throws {
        let clip = Self.clip()
        var document = Self.document(clip)
        let landed6 = document.punchIn(layerID: clip.id,
                                 onRegion: CGRect(x: 840, y: 470, width: 200, height: 80),
                                 atTimeMS: 5000)
        #expect(landed6)
        let tight = Self.scalePercent(of: clip.id, in: document, atMS: 5000)
        let landed7 = document.pullBackOut(layerID: clip.id, atTimeMS: 8000)
        #expect(landed7)

        // Everything between the two is the hold, and nobody asked for it.
        for ms in stride(from: 5000, through: 8000, by: 250) {
            #expect(abs(Self.scalePercent(of: clip.id, in: document, atMS: ms) - tight) < 0.001)
        }
        // ...and by the end of the pull out it is wide again, on the whole
        // picture, exactly where it started.
        #expect(abs(Self.scalePercent(of: clip.id, in: document, atMS: 9200) - 100) < 0.001)
        let middle = try #require(Self.onScreen(CGPoint(x: 640, y: 360), of: clip.id,
                                                in: document, atMS: 9200))
        #expect(abs(middle.x - 640) < 0.5)
        #expect(abs(middle.y - 360) < 0.5)
    }

    @Test("Pulling out with nothing to pull out of does nothing")
    func nothingToPullOutOf() {
        let clip = Self.clip()
        var document = Self.document(clip)
        let landed8 = document.pullBackOut(layerID: clip.id, atTimeMS: 8000)
        #expect(!landed8)
    }

    @Test("A second punch in travels from where the camera is, it does not cut back to wide")
    func aSecondPunchTravels() {
        let clip = Self.clip()
        var document = Self.document(clip)
        let landed9 = document.punchIn(layerID: clip.id,
                                 onRegion: CGRect(x: 840, y: 470, width: 200, height: 80),
                                 atTimeMS: 4000)
        #expect(landed9)
        let first = Self.scalePercent(of: clip.id, in: document, atMS: 4000)
        let landed10 = document.punchIn(layerID: clip.id,
                                 onRegion: CGRect(x: 200, y: 100, width: 400, height: 225),
                                 atTimeMS: 8000)
        #expect(landed10)
        // It held on the first subject right up to the moment the second move
        // begins, rather than snapping wide in between.
        #expect(abs(Self.scalePercent(of: clip.id, in: document, atMS: 6500) - first) < 0.001)
        #expect(Self.scalePercent(of: clip.id, in: document, atMS: 8000) > 100)
    }

    @Test("A punch in early in the clip still has room to move")
    func noRoomBeforeThePlayhead() {
        let clip = Self.clip()
        var document = Self.document(clip)
        let landed11 = document.punchIn(layerID: clip.id,
                                 onRegion: CGRect(x: 840, y: 470, width: 200, height: 80),
                                 atTimeMS: 100)
        #expect(landed11)
        // It cannot arrive before it set off, so it sets off at the first frame
        // and takes the shortest move there is.
        #expect(abs(Self.scalePercent(of: clip.id, in: document, atMS: 0) - 100) < 0.001)
        #expect(Self.scalePercent(of: clip.id, in: document, atMS: 300) > 100)
    }

    // MARK: - It survives a trim

    @Test("Trimming the front of a clip does not leave the move pointing at the wrong frame")
    func itSurvivesATrim() throws {
        let clip = Self.clip()
        var document = Self.document(clip)
        let button = CGRect(x: 840, y: 470, width: 200, height: 80)
        let landed12 = document.punchIn(layerID: clip.id, onRegion: button, atTimeMS: 5000)
        #expect(landed12)
        // The frame of the RECORDING the camera arrives on.
        let arrivedOn = try #require(document.layer(id: clip.id))
            .motionClockMS(atDocumentTimeMS: 5000)
        #expect(arrivedOn == 5000)

        // Two seconds off the front. Everything after it slides two seconds
        // earlier on the timeline, the frames included.
        let landed13 = document.trimClipStart(clip.id, ofPiece: 0, byMS: 2000)
        #expect(landed13)
        let trimmed = try #require(document.layer(id: clip.id))
        #expect(trimmed.motionClockMS(atDocumentTimeMS: 3000) == 5000)

        // The camera is on the button at 0:03 now, which is where that frame
        // went, and it is not on it at 0:05, which is a different frame.
        let landed = try #require(Self.onScreen(CGPoint(x: button.midX, y: button.midY),
                                                of: clip.id, in: document, atMS: 3000))
        #expect(abs(landed.x - 640) < 0.5)
        #expect(abs(landed.y - 360) < 0.5)
    }

    @Test("Splitting a clip and throwing a piece away carries the move with the frames")
    func itSurvivesACut() throws {
        let clip = Self.clip()
        var document = Self.document(clip)
        let button = CGRect(x: 840, y: 470, width: 200, height: 80)
        let landed14 = document.punchIn(layerID: clip.id, onRegion: button, atTimeMS: 8000)
        #expect(landed14)

        // Cut at four seconds and throw the first piece away: what was at 0:08
        // is now at 0:04.
        let landed15 = document.splitClip(clip.id, atMS: 4000)
        #expect(landed15)
        let landed16 = document.removeClipPiece(clip.id, at: 0)
        #expect(landed16)
        let after = try #require(document.layer(id: clip.id))
        #expect(after.motionClockMS(atDocumentTimeMS: 4000) == 8000)

        let landed = try #require(Self.onScreen(CGPoint(x: button.midX, y: button.midY),
                                                of: clip.id, in: document, atMS: 4000))
        #expect(abs(landed.x - 640) < 0.5)
        #expect(abs(landed.y - 360) < 0.5)
    }

    // MARK: - It stays sharp

    @Test("A recording captured at twice its laid out size can be punched in to twice before it softens")
    func theSharpnessBudgetIsTheSourcesOwn() throws {
        let clip = Self.clip()
        #expect(clip.reframeNativePercent == 200)
        var document = Self.document(clip)
        let landed17 = document.punchIn(layerID: clip.id,
                                 onRegion: CGRect(x: 320, y: 180, width: 853, height: 480),
                                 atTimeMS: 5000)
        #expect(landed17)
        let reading = try #require(document.layer(id: clip.id)?
            .reframeReading(atDocumentTimeMS: 5000, documentCycleMS: 12_000))
        #expect(abs(reading.scalePercent - 150) < 1)
        #expect(!reading.isPastNative)
        #expect(reading.sharpnessNote == "Sharp to 200%")
    }

    @Test("Past what the recording holds, the panel says so in numbers rather than a warning")
    func pastNativeIsSaidPlainly() throws {
        let clip = Self.clip(pixelSize: CGSize(width: 1280, height: 720))
        #expect(clip.reframeNativePercent == 100)
        var document = Self.document(clip)
        let landed18 = document.punchIn(layerID: clip.id,
                                 onRegion: CGRect(x: 500, y: 280, width: 280, height: 160),
                                 atTimeMS: 5000)
        #expect(landed18)
        let reading = try #require(document.layer(id: clip.id)?
            .reframeReading(atDocumentTimeMS: 5000, documentCycleMS: 12_000))
        #expect(reading.isPastNative)
        #expect(reading.sharpnessNote == "Past the recording's own detail, which is 100%")
        #expect(reading.headroomPercent == 0)
    }

    @Test("The reading says what is in the middle of the frame, in the recording's own points")
    func theReadingNamesTheCentre() throws {
        let clip = Self.clip()
        var document = Self.document(clip)
        let button = CGRect(x: 840, y: 470, width: 200, height: 80)
        let landed19 = document.punchIn(layerID: clip.id, onRegion: button, atTimeMS: 5000)
        #expect(landed19)
        let reading = try #require(document.layer(id: clip.id)?
            .reframeReading(atDocumentTimeMS: 5000, documentCycleMS: 12_000))
        #expect(abs(reading.centre.x - button.midX) < 0.5)
        #expect(abs(reading.centre.y - button.midY) < 0.5)
        #expect(reading.moves)
    }

    // MARK: - What plays is what exports

    @Test("Every frame the exporter asks for is the frame the canvas would draw")
    func whatPlaysIsWhatExports() {
        let clip = Self.clip()
        var document = Self.document(clip)
        let landed20 = document.punchIn(layerID: clip.id,
                                 onRegion: CGRect(x: 840, y: 470, width: 200, height: 80),
                                 atTimeMS: 5000)
        #expect(landed20)
        let landed21 = document.pullBackOut(layerID: clip.id, atTimeMS: 8000)
        #expect(landed21)
        // The exporter walks the same `drawn(atTimeMS:)` the canvas does
        // (`DocumentVideoExport.swift`), so the test is that asking twice can
        // never answer twice: the picture at a moment is a pure function of the
        // document and the moment.
        for ms in stride(from: 0, through: 11_900, by: 33) {
            #expect(document.drawn(atTimeMS: ms).layers == document.drawn(atTimeMS: ms).layers)
        }
        // ...and the moved layer is never written back into the document, so
        // exporting twice cannot drift.
        #expect(document.layer(id: clip.id)?.frame == clip.frame)
    }

    // MARK: - Putting it back

    @Test("Reset gives the whole frame back and takes the lanes off the strip")
    func resetPutsItBack() {
        let clip = Self.clip()
        var document = Self.document(clip)
        let landed22 = document.punchIn(layerID: clip.id,
                                 onRegion: CGRect(x: 840, y: 470, width: 200, height: 80),
                                 atTimeMS: 5000)
        #expect(landed22)
        #expect(document.layer(id: clip.id)?.isReframed == true)
        let landed23 = document.resetReframe(layerID: clip.id)
        #expect(landed23)
        #expect(document.layer(id: clip.id)?.isReframed == false)
        #expect(document.layer(id: clip.id)?.motions == nil)
        #expect(abs(Self.scalePercent(of: clip.id, in: document, atMS: 5000) - 100) < 0.001)
    }

    @Test("A layer with no time in it takes no reframe, because there is no camera to move")
    func onlyClipsReframe() {
        let still = Layer(name: "Frame", content: .image(ImageRef(id: UUID(),
                                                                  pixelSize: CGSize(width: 40, height: 40))),
                          frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        #expect(!still.takesAReframe)
        #expect(still.motionClockMS(atDocumentTimeMS: 4000) == 4000)
    }
}

/// Dragging a punch-in's bar on the timing strip (`LayerMotion.retimed(to:)`).
@Suite("A move that holds survives being dragged on the strip")
struct ReframeRetimingTests {

    static func punch() -> LayerMotion {
        LayerMotion(property: .scale, from: .number(100), to: .number(100),
                    timing: MotionTiming(startMS: 1000, durationMS: 4000),
                    curve: .easeInOut, repeats: .once,
                    stops: [MotionStop(atMS: 2000, value: .number(220)),
                            MotionStop(atMS: 4000, value: .number(220))])
    }

    @Test("Dragging the bar later carries the hold with it")
    func laterCarriesTheHold() {
        let moved = Self.punch().retimed(to: MotionTiming(startMS: 3000, durationMS: 4000))
        #expect(moved.stops?.map(\.atMS) == [4000, 6000])
        #expect(moved.value(atMS: 3000, cycleMS: 12_000) == .number(100))
        #expect(moved.value(atMS: 5000, cycleMS: 12_000) == .number(220))
    }

    @Test("Stretching the bar stretches the hold in proportion")
    func stretchingKeepsTheShape() {
        let moved = Self.punch().retimed(to: MotionTiming(startMS: 1000, durationMS: 8000))
        #expect(moved.stops?.map(\.atMS) == [3000, 7000])
        #expect(moved.value(atMS: 5000, cycleMS: 16_000) == .number(220))
        #expect(moved.value(atMS: 9000, cycleMS: 16_000) == .number(100))
    }

    @Test("A motion with nothing nailed down inside it is re-timed the way it always was")
    func plainMotionsAreUnchanged() {
        let plain = LayerMotion(property: .opacity, from: .number(0), to: .number(100),
                                timing: MotionTiming(startMS: 0, durationMS: 500))
        let moved = plain.retimed(to: MotionTiming(startMS: 200, durationMS: 900))
        #expect(moved.stops == nil)
        #expect(moved.timing == MotionTiming(startMS: 200, durationMS: 900))
    }
}

/// Punch In as a right-click preset: how far in, around where you clicked.
@Suite("Punch In presets")
struct PunchInPresetTests {
    static let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    @Test("A preset with no point punches in on the middle of the picture")
    func middle() {
        let box = ClipReframe.presetRegion(percent: 200, around: nil, in: Self.frame)
        #expect(box == CGRect(x: 480, y: 270, width: 960, height: 540))
        #expect(ClipReframe.scalePercent(fitting: box, into: Self.frame) == 200)
    }

    @Test("A preset around a point centres on it")
    func aroundAPoint() {
        let box = ClipReframe.presetRegion(percent: 200, around: CGPoint(x: 900, y: 500), in: Self.frame)
        #expect(box.midX == 900)
        #expect(box.midY == 500)
    }

    @Test("A point near the edge keeps the whole box on the picture")
    func nearTheEdge() {
        let box = ClipReframe.presetRegion(percent: 150, around: CGPoint(x: 1910, y: 5), in: Self.frame)
        #expect(box.maxX == Self.frame.maxX)
        #expect(box.minY == Self.frame.minY)
        #expect(box.width == 1280)
    }

    @Test("The presets are the three the menu offers")
    func presets() {
        #expect(ClipReframe.punchInPresets == [125, 150, 200])
    }
}
