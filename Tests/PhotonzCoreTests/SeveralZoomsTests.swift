import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Several zooms on a clip picked together: what they agree on, one change
/// made to all of them, and all of them taken away (`ClipZoom.swift`).
@Suite("Several zooms picked together")
struct SeveralZoomsTests {

    static func zoom(start: Int, end: Int, ease: Int = 700, scale: Double = 2,
                     follows: Bool = false) -> ClipZoom {
        ClipZoom(startMS: start, endMS: end, easeInMS: ease, easeOutMS: ease, scale: scale,
                 center: CGPoint(x: 0.5, y: 0.5), followsCursor: follows)
    }

    static func document(_ zooms: [ClipZoom]) -> (PhotonzDocument, UUID) {
        var layer = ClipZoomTests.clip()
        layer.zooms = zooms
        return (ClipZoomTests.document(layer), layer.id)
    }

    // MARK: - What they agree on

    @Test func zoomsThatAgreeReadTheirSharedValues() {
        let reading = ClipZoomsReading([Self.zoom(start: 0, end: 2000), Self.zoom(start: 3000, end: 5000)])
        #expect(reading.scalePercent == 200)
        #expect(reading.followsCursor == false)
        #expect(reading.easeInMS == 700)
        #expect(reading.easeOutMS == 700)
    }

    @Test func aSettingTheyDisagreeOnReadsAsMixed() {
        var other = Self.zoom(start: 3000, end: 5000, scale: 3, follows: true)
        other.easeOutMS = 300
        let reading = ClipZoomsReading([Self.zoom(start: 0, end: 2000), other])
        #expect(reading.scalePercent == nil)
        #expect(reading.followsCursor == nil)
        #expect(reading.easeInMS == 700)
        #expect(reading.easeOutMS == nil)
    }

    @Test func scalesThatShowTheSamePercentAgree() {
        let reading = ClipZoomsReading([Self.zoom(start: 0, end: 2000, scale: 2.0),
                                        Self.zoom(start: 3000, end: 5000, scale: 2.001)])
        #expect(reading.scalePercent == 200)
    }

    @Test func nothingPickedAgreesOnNothing() {
        let reading = ClipZoomsReading([])
        #expect(reading.scalePercent == nil)
        #expect(reading.followsCursor == nil)
    }

    // MARK: - One change to all of them

    @Test func oneChangeLandsOnEveryZoomNamedAndNoOther() {
        let a = Self.zoom(start: 0, end: 2000)
        let b = Self.zoom(start: 3000, end: 5000)
        let c = Self.zoom(start: 6000, end: 8000)
        var (document, clip) = Self.document([a, b, c])
        document.updateZooms(onClip: clip, ids: [a.id, c.id]) { $0.easeInMS = 300 }
        let zooms = document.layer(id: clip)?.zooms ?? []
        #expect(zooms.first { $0.id == a.id }?.easeInMS == 300)
        #expect(zooms.first { $0.id == b.id }?.easeInMS == 700)
        #expect(zooms.first { $0.id == c.id }?.easeInMS == 300)
    }

    @Test func aChangeToSeveralIsKeptSensibleOnEach() {
        let a = Self.zoom(start: 0, end: 2000)
        let b = Self.zoom(start: 3000, end: 5000)
        var (document, clip) = Self.document([a, b])
        document.updateZooms(onClip: clip, ids: [a.id, b.id]) { $0.scale = 40 }
        let zooms = document.layer(id: clip)?.zooms ?? []
        #expect(zooms.allSatisfy { $0.scale == ClipZoom.mostScale })
        #expect(zooms.map(\.startMS) == [0, 3000])
    }

    // MARK: - Taking them away

    @Test func removingSeveralTakesOnlyThoseAndAnswersHowMany() {
        let a = Self.zoom(start: 0, end: 2000)
        let b = Self.zoom(start: 3000, end: 5000)
        let c = Self.zoom(start: 6000, end: 8000)
        var (document, clip) = Self.document([a, b, c])
        let removed = document.removeZooms(onClip: clip, ids: [a.id, c.id, UUID()])
        #expect(removed == 2)
        #expect(document.layer(id: clip)?.zooms?.map(\.id) == [b.id])
    }

    @Test func removingEveryZoomLeavesTheClipWithNone() {
        let a = Self.zoom(start: 0, end: 2000)
        let b = Self.zoom(start: 3000, end: 5000)
        var (document, clip) = Self.document([a, b])
        #expect(document.removeZooms(onClip: clip, ids: [a.id, b.id]) == 2)
        #expect(document.layer(id: clip)?.zooms == nil)
    }
}
