import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// A zoom region on a clip: a stretch of the recording where the picture fills
/// the frame with one spot of it, easing in and out, and able to follow the
/// recorded pointer (`ClipZoom.swift`).
@Suite("A zoom region that frames a spot")
struct ClipZoomTests {

    static let movieID = UUID(uuidString: "200A2002-1111-2222-3333-444444444444")!

    static func movie() -> MovieRef {
        MovieRef(id: movieID, pixelSize: CGSize(width: 2000, height: 1000), durationMS: 12_000)
    }

    static func clip(inMS: Int = 0, outMS: Int = 12_000, sourceInMS: Int = 0) -> Layer {
        let reel = movie()
        var layer = Layer(name: "screen-recording",
                          content: .image(reel.frameRef(atSourceMS: 0)),
                          frame: CGRect(x: 0, y: 0, width: 1000, height: 500))
        layer.movie = reel
        layer.time = LayerTime(inMS: inMS, outMS: outMS,
                               sourceInMS: sourceInMS, sourceLengthMS: 12_000)
        return layer
    }

    static func document(_ layer: Layer) -> PhotonzDocument {
        var document = PhotonzDocument(canvasSize: CGSize(width: 1000, height: 500), layers: [layer])
        document.durationMS = layer.time?.outMS
        return document
    }

    static func zoom(start: Int = 2000, end: Int = 6000, ease: Int = 1000,
                     scale: Double = 2, center: CGPoint = CGPoint(x: 0.75, y: 0.25)) -> ClipZoom {
        ClipZoom(startMS: start, endMS: end, easeInMS: ease, easeOutMS: ease,
                 scale: scale, center: center)
    }

    private func near(_ a: CGFloat, _ b: CGFloat, _ slack: CGFloat = 0.0005) -> Bool { abs(a - b) <= slack }
    private func near(_ a: CGRect?, _ b: CGRect, _ slack: CGFloat = 0.0005) -> Bool {
        guard let a else { return false }
        return near(a.minX, b.minX, slack) && near(a.minY, b.minY, slack)
            && near(a.width, b.width, slack) && near(a.height, b.height, slack)
    }

    // MARK: - The region

    @Test func aRegionIsTheWindowItsScaleAndCentreMake() {
        let zoom = Self.zoom(scale: 2, center: CGPoint(x: 0.5, y: 0.5))
        #expect(near(zoom.region, CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)))
    }

    @Test func aRegionNearAnEdgeSlidesBackInsideThePicture() {
        let zoom = Self.zoom(scale: 2, center: CGPoint(x: 0.95, y: 0.05))
        #expect(near(zoom.region, CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)))
    }

    @Test func aDrawnBoxKeepsAllOfItselfInTheFrame() {
        // A box twice as wide as it is tall in the picture's own fractions:
        // the zoom goes in only as far as keeps its whole width on screen.
        let fit = ClipZoom.fitting(CGRect(x: 0.1, y: 0.1, width: 0.4, height: 0.2))
        #expect(fit != nil)
        #expect(near(CGFloat(fit?.scale ?? 0), 2.5))
        #expect(near(fit?.center.x ?? 0, 0.3) && near(fit?.center.y ?? 0, 0.2))
    }

    @Test func aBoxTooSmallOrTooBigIsHeldToWhatAZoomCanBe() {
        #expect(ClipZoom.fitting(CGRect(x: 0.1, y: 0.1, width: 0.001, height: 0.001)) == nil)
        let tight = ClipZoom.fitting(CGRect(x: 0.4, y: 0.4, width: 0.01, height: 0.01))
        #expect(tight?.scale == ClipZoom.mostScale)
        let whole = ClipZoom.fitting(CGRect(x: 0, y: 0, width: 1, height: 1))
        #expect(whole?.scale == 1)
    }

    // MARK: - Easing in, holding, easing out

    @Test func outsideItsStretchTheFrameIsWhole() {
        let zoom = Self.zoom()
        #expect(zoom.window(atMS: 1999) == nil)
        #expect(zoom.window(atMS: 6000) == nil)
        #expect(zoom.window(atMS: 9000) == nil)
    }

    @Test func itHoldsOnTheRegionBetweenItsTwoEases() {
        let zoom = Self.zoom()
        #expect(near(zoom.window(atMS: 3000), zoom.region))
        #expect(near(zoom.window(atMS: 4000), zoom.region))
        #expect(near(zoom.window(atMS: 5000), zoom.region))
    }

    @Test func easingInIsAStraightDollyOntoTheSpot() {
        // Every window on the way in is the whole frame shrunk about ONE
        // fixed point, so the spot never drifts sideways as it arrives.
        let zoom = Self.zoom(center: CGPoint(x: 0.75, y: 0.25))
        let target = zoom.region
        // The fixed point: where the full frame and the region line up.
        let k = target.width
        let anchor = CGPoint(x: target.minX / (1 - k), y: target.minY / (1 - k))
        for ms in stride(from: 2050, to: 3000, by: 150) {
            guard let w = zoom.window(atMS: ms) else {
                Issue.record("no window at \(ms)")
                continue
            }
            #expect(w.width > target.width && w.width < 1)
            #expect(near(w.width, w.height))
            // The anchor sits at the same fraction of every window.
            #expect(near((anchor.x - w.minX) / w.width, anchor.x, 0.001))
            #expect(near((anchor.y - w.minY) / w.height, anchor.y, 0.001))
        }
    }

    @Test func theWayInStartsAndEndsGently() {
        let zoom = Self.zoom()
        let early = zoom.amount(atMS: 2100)
        let middle = zoom.amount(atMS: 2500)
        let late = zoom.amount(atMS: 2900)
        #expect(early < 0.05)
        #expect(near(CGFloat(middle), 0.5, 0.01))
        #expect(late > 0.95)
        // ...and the way out mirrors it.
        #expect(near(CGFloat(zoom.amount(atMS: 5500)), 0.5, 0.01))
    }

    @Test func easesLongerThanTheStretchShareIt() {
        let zoom = Self.zoom(start: 0, end: 1000, ease: 1000)
        let eases = zoom.eases
        #expect(eases.inMS + eases.outMS <= 1000)
        #expect(eases.inMS == 500 && eases.outMS == 500)
        #expect(near(CGFloat(zoom.amount(atMS: 500)), 1, 0.001))
    }

    // MARK: - Following the pointer

    /// A pointer that sits on the left for two seconds, then crosses to the
    /// right over two seconds and stays.
    static func crossing(from: Double = 200, to: Double = 1800) -> PointerTrack {
        var samples: [PointerSample] = []
        for ms in stride(from: 0, through: 10_000, by: 16) {
            let t = min(max(Double(ms - 2000) / 2000, 0), 1)
            samples.append(PointerSample(ms: ms, x: from + (to - from) * t, y: 500))
        }
        return PointerTrack(pixelSize: CGSize(width: 2000, height: 1000), samples: samples, clicks: [])
    }

    @Test func aFollowingZoomKeepsThePointerInsideItsFrame() {
        var zoom = Self.zoom(start: 0, end: 8000, ease: 500, scale: 3, center: CGPoint(x: 0.5, y: 0.5))
        zoom.followsCursor = true
        zoom.bakeCursor(from: Self.crossing())
        for ms in stride(from: 600, through: 7400, by: 100) {
            guard let w = zoom.window(atMS: ms),
                  let p = Self.crossing().position(atMS: ms) else {
                Issue.record("nothing at \(ms)")
                continue
            }
            let unit = CGPoint(x: p.x / 2000, y: p.y / 1000)
            let margin = w.width * ClipZoom.followMargin
            #expect(unit.x >= w.minX + margin - 0.001 && unit.x <= w.maxX - margin + 0.001,
                    "pointer at \(unit.x) left the frame \(w.minX)...\(w.maxX) at \(ms)")
            // The zoom level stays the region's.
            #expect(near(w.width, 1 / 3, 0.001))
        }
    }

    @Test func aFollowingZoomGlidesRatherThanJumps() {
        var zoom = Self.zoom(start: 0, end: 8000, ease: 500, scale: 3, center: CGPoint(x: 0.5, y: 0.5))
        zoom.followsCursor = true
        // A crossing that never meets the picture's edge, where the camera
        // has to stop.
        zoom.bakeCursor(from: Self.crossing(from: 600, to: 1400))
        // Frame to frame at sixty a second, the camera never moves more than a
        // sliver of the picture, and its speed changes smoothly: no lurch
        // where the pointer set off or stopped.
        var last: CGFloat?
        var lastStep: CGFloat = 0
        for ms in stride(from: 1000, through: 7000, by: 16) {
            guard let w = zoom.window(atMS: ms) else { continue }
            if let last {
                let step = w.midX - last
                #expect(abs(step) < 0.01, "jumped \(step) at \(ms)")
                #expect(abs(step - lastStep) < 0.001, "lurched at \(ms)")
                lastStep = step
            }
            last = w.midX
        }
    }

    @Test func aBakedPathOnlyKeepsWhatTheZoomNeeds() {
        var zoom = Self.zoom(start: 3000, end: 5000)
        zoom.bakeCursor(from: Self.crossing())
        let samples = zoom.cursor?.samples ?? []
        #expect(!samples.isEmpty)
        #expect((samples.first?.ms ?? 0) >= 3000 - ClipZoom.cursorReachMS)
        #expect((samples.last?.ms ?? .max) <= 5000 + ClipZoom.cursorReachMS)
        // Thinned to about thirty a second rather than every sixteen ms.
        #expect(samples.count < (2000 + 2 * ClipZoom.cursorReachMS) / 30 + 3)
    }

    @Test func aZoomWithNoPathToFollowStaysPut() {
        var zoom = Self.zoom()
        zoom.followsCursor = true
        #expect(near(zoom.window(atMS: 4000), zoom.region))
    }

    @Test func aBakedPathSurvivesTheFile() throws {
        var zoom = Self.zoom()
        zoom.followsCursor = true
        zoom.bakeCursor(from: Self.crossing())
        let back = try JSONDecoder().decode(ClipZoom.self, from: JSONEncoder().encode(zoom))
        #expect(back.followsCursor)
        #expect(back.cursor?.samples.count == zoom.cursor?.samples.count)
        #expect(back.center == zoom.center && back.scale == zoom.scale)
    }

    // MARK: - On the clip

    @Test func addingAZoomStartsItAtThePlayhead() throws {
        var document = Self.document(Self.clip())
        let id = try #require(document.layers.first?.id)
        let addedMade = document.addZoom(toClip: id, atTimeMS: 2000, around: nil)
        let added = try #require(addedMade)
        #expect(added.startMS == 2000)
        #expect(added.endMS == 2000 + ClipZoom.defaultLengthMS)
        #expect(added.scale == ClipZoom.defaultScale)
        #expect(added.center == CGPoint(x: 0.5, y: 0.5))
        #expect(document.layer(id: id)?.zooms?.count == 1)
    }

    @Test func aZoomAddedNearTheEndIsShortenedToFit() throws {
        var document = Self.document(Self.clip())
        let id = try #require(document.layers.first?.id)
        let addedMade = document.addZoom(toClip: id, atTimeMS: 11_000, around: nil)
        let added = try #require(addedMade)
        #expect(added.endMS == 12_000)
        let refused = document.addZoom(toClip: id, atTimeMS: 11_900, around: nil)
        #expect(refused == nil)
    }

    @Test func aZoomIsNeverAddedOnTopOfAnother() throws {
        var document = Self.document(Self.clip())
        let id = try #require(document.layers.first?.id)
        let firstMade = document.addZoom(toClip: id, atTimeMS: 2000, around: nil)
        #expect(firstMade != nil)
        let refused = document.addZoom(toClip: id, atTimeMS: 3000, around: nil)
        #expect(refused == nil)
        // Just before it, it is cut short to end where the next begins.
        let beforeMade = document.addZoom(toClip: id, atTimeMS: 500, around: nil)
        let before = try #require(beforeMade)
        #expect(before.endMS == 2000)
    }

    @Test func aZoomAddedAroundAPointCentresThere() throws {
        var document = Self.document(Self.clip())
        let id = try #require(document.layers.first?.id)
        let addedMade = document.addZoom(toClip: id, atTimeMS: 0, around: CGPoint(x: 0.8, y: 0.3))
        let added = try #require(addedMade)
        #expect(added.center == CGPoint(x: 0.75, y: 0.3))
    }

    @Test func aZoomIsDrawnAsTheWindowOfTheClipAtThatMoment() throws {
        var layer = Self.clip()
        layer.zooms = [Self.zoom(start: 2000, end: 6000, ease: 1000, scale: 2, center: CGPoint(x: 0.5, y: 0.5))]
        let document = Self.document(layer)
        #expect(document.drawn(atTimeMS: 1000).layer(id: layer.id)?.zoomWindow == nil)
        let held = document.drawn(atTimeMS: 4000).layer(id: layer.id)
        #expect(near(held?.zoomWindow, CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)))
        // The box on the canvas does not move: the picture inside it does.
        #expect(held?.frame == layer.frame)
        #expect(document.layer(id: layer.id)?.zoomWindow == nil)
    }

    @Test func aZoomStaysOnItsFramesWhenTheClipIsTrimmed() throws {
        // The zoom is nailed to the recording's own clock, so trimming a
        // second off the front moves it a second earlier on the timeline.
        var layer = Self.clip(inMS: 0, outMS: 11_000, sourceInMS: 1000)
        layer.zooms = [Self.zoom(start: 2000, end: 6000, ease: 1000, scale: 2, center: CGPoint(x: 0.5, y: 0.5))]
        let document = Self.document(layer)
        #expect(near(document.drawn(atTimeMS: 3000).layer(id: layer.id)?.zoomWindow,
                     CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)))
        let span = try #require(layer.timelineSpanMS(of: layer.zooms?.first?.id))
        #expect(span.start == 1000 && span.end == 5000)
    }

    @Test func movingAZoomIsHeldInsideTheClipAndClearOfItsNeighbours() throws {
        var layer = Self.clip()
        let first = Self.zoom(start: 1000, end: 3000)
        let second = Self.zoom(start: 6000, end: 8000)
        layer.zooms = [first, second]
        var document = Self.document(layer)
        document.updateZoom(onClip: layer.id, id: second.id) { $0.startMS -= 4000; $0.endMS -= 4000 }
        let moved = try #require(document.layer(id: layer.id)?.zooms?.first { $0.id == second.id })
        #expect(moved.startMS == 3000 && moved.endMS == 5000)
        document.updateZoom(onClip: layer.id, id: second.id) { $0.endMS = 50_000 }
        let stretched = try #require(document.layer(id: layer.id)?.zooms?.first { $0.id == second.id })
        #expect(stretched.endMS == 12_000)
        document.updateZoom(onClip: layer.id, id: second.id) { $0.startMS = stretched.endMS - 10 }
        let squeezed = try #require(document.layer(id: layer.id)?.zooms?.first { $0.id == second.id })
        #expect(squeezed.endMS - squeezed.startMS >= ClipZoom.shortestMS)
    }

    @Test func removingAZoomLeavesTheOthers() throws {
        var layer = Self.clip()
        let first = Self.zoom(start: 1000, end: 3000)
        let second = Self.zoom(start: 6000, end: 8000)
        layer.zooms = [first, second]
        var document = Self.document(layer)
        let removed = document.removeZoom(onClip: layer.id, id: first.id)
        #expect(removed)
        #expect(document.layer(id: layer.id)?.zooms?.map(\.id) == [second.id])
        let removedLast = document.removeZoom(onClip: layer.id, id: second.id)
        #expect(removedLast)
        #expect(document.layer(id: layer.id)?.zooms == nil)
    }

    @Test func theZoomFactorSaysHowMuchSharperAFrameIsWorthReading() {
        var layer = Self.clip()
        layer.zooms = [Self.zoom(start: 2000, end: 6000, ease: 1000, scale: 3, center: CGPoint(x: 0.5, y: 0.5))]
        #expect(layer.zoomFactor(atDocumentTimeMS: 1000) == 1)
        #expect(near(CGFloat(layer.zoomFactor(atDocumentTimeMS: 4000)), 3, 0.001))
    }

    // MARK: - Suggesting zooms from the clicks

    static func click(_ ms: Int, _ x: Double, _ y: Double) -> PointerClick {
        PointerClick(downMS: ms, upMS: ms + 80, point: CGPoint(x: x, y: y), button: .left)
    }

    @Test func clicksCloseTogetherBecomeOneZoomAroundThem() {
        let clicks = [Self.click(3000, 1500, 200), Self.click(3800, 1600, 260), Self.click(4500, 1550, 300)]
        let suggested = ClipZoom.suggestions(clicks: clicks, pixelSize: CGSize(width: 2000, height: 1000),
                                             sourceRange: 0...12_000, keepingClearOf: [])
        #expect(suggested.count == 1)
        guard let zoom = suggested.first else { return }
        // It has arrived by the first click and is still there after the last.
        #expect(zoom.startMS + zoom.easeInMS <= 3000)
        #expect(zoom.endMS - zoom.easeOutMS >= 4500)
        // ...framing the clicks.
        for click in clicks {
            let unit = CGPoint(x: click.point.x / 2000, y: click.point.y / 1000)
            #expect(zoom.region.contains(unit))
        }
        #expect(zoom.scale > 1.2)
    }

    @Test func clicksFarApartInTimeAreSeparateZooms() {
        let clicks = [Self.click(1500, 400, 300), Self.click(8000, 1600, 700)]
        let suggested = ClipZoom.suggestions(clicks: clicks, pixelSize: CGSize(width: 2000, height: 1000),
                                             sourceRange: 0...12_000, keepingClearOf: [])
        #expect(suggested.count == 2)
        #expect(suggested.map(\.startMS) == suggested.map(\.startMS).sorted())
        if suggested.count == 2 { #expect(suggested[0].endMS <= suggested[1].startMS) }
    }

    @Test func aSuggestionNeverLandsOnAZoomAlreadyThere() {
        let clicks = [Self.click(3000, 1500, 200), Self.click(9000, 400, 300)]
        let existing = Self.zoom(start: 2000, end: 5000)
        let suggested = ClipZoom.suggestions(clicks: clicks, pixelSize: CGSize(width: 2000, height: 1000),
                                             sourceRange: 0...12_000, keepingClearOf: [existing])
        #expect(suggested.count == 1)
        #expect(suggested.first.map { $0.startMS >= 5000 } == true)
    }

    @Test func noClicksSuggestNothing() {
        #expect(ClipZoom.suggestions(clicks: [], pixelSize: CGSize(width: 2000, height: 1000),
                                     sourceRange: 0...12_000, keepingClearOf: []).isEmpty)
    }

    @Test func aSuggestionIsKeptInsideTheClip() {
        let clicks = [Self.click(200, 1000, 500), Self.click(11_900, 1000, 500)]
        let suggested = ClipZoom.suggestions(clicks: clicks, pixelSize: CGSize(width: 2000, height: 1000),
                                             sourceRange: 0...12_000, keepingClearOf: [])
        for zoom in suggested {
            #expect(zoom.startMS >= 0 && zoom.endMS <= 12_000)
            #expect(zoom.endMS - zoom.startMS >= ClipZoom.shortestMS)
        }
    }
}
