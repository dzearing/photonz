import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Alpha read outward from the middle of each edge of a real window shot.
private enum Measured {
    static func bytes(_ values: [Int]) -> [Double] { values.map { Double($0) / 255 } }

    /// macOS 26, a active dark window at 2x, read by `--window-shot-diag` on 2026-10-12.
    static let activeDark = WindowShot.EdgeProfiles(
        below: bytes([247,146,144,142,140,139,138,137,134,134,132,131,129,128,125,124,124,121,120,119,116,114,113,112,110,108,106,104,103,101,99,97,96,93,93,90,88,87,86,84,81,80,78,77,74,73,70,69,69,65,65,63,61,59,58,57,55,53,51,50,49,47,46,44,43,41,40,38,37,36,35,34,32,31,29,29,28,27,25,24,24,22,22,21,20,18,18,18,17,16,15,14,14,13,13,11,11,10,11,9,9,9,9,8,7,7,6,7,6,6,5,4,6,4,4,5,4,3,4,3,3,2,2,2,3,2,2,1,2,1,2,1,1,1,1,1,0,1,0,1,0,1,0,0,0,0,0,0]),
        above: bytes([239,35,30,29,27,26,25,25,24,23,21,21,20,19,17,18,16,15,16,14,14,13,13,11,12,11,10,9,9,9,8,8,7,7,7,7,6,6,5,6,5,5,4,4,4,4,3,4,2,2,3,2,2,2,2,1,2,2,1,1,1,1,0,1,0,0,0,1,0,0,0,0,0,0,0,0]),
        left: bytes([243,90,85,83,81,80,78,77,74,73,72,70,68,66,63,62,61,60,58,56,55,53,51,50,48,48,45,44,43,41,40,39,37,36,35,34,32,32,30,29,27,26,26,25,23,23,21,20,19,20,18,17,17,16,15,15,13,14,12,12,12,11,11,10,9,9,8,8,7,8,6,7,5,6,6,6,5,5,3,4,3,4,4,3,3,3,3,3,2,3,1,2,2,1,2,1,1,1,1,1,0,1,0,1,0,0,0,0,0,0,0,0]),
        right: bytes([243,89,85,83,82,81,78,76,75,73,72,69,68,66,64,63,61,60,58,57,55,53,52,49,49,47,46,44,42,42,40,38,37,35,35,33,33,32,30,28,28,26,26,24,24,23,22,21,20,19,18,18,17,15,16,14,14,13,12,12,11,11,11,9,9,8,8,8,8,8,7,6,6,5,6,5,5,5,4,4,4,4,3,4,3,2,3,2,3,2,2,2,1,2,2,1,1,0,1,0,1,1,0,0,0,0,0,0,0,0,0,0]))
    /// macOS 26, a inactive light window at 2x, read by `--window-shot-diag` on 2026-10-12.
    static let inactiveLight = WindowShot.EdgeProfiles(
        below: bytes([90,51,46,45,44,43,42,41,40,39,38,37,36,35,34,32,32,30,29,28,28,26,24,25,23,22,22,20,19,18,18,16,16,15,14,13,13,12,11,11,10,9,9,8,7,7,7,5,6,5,4,4,4,4,2,4,3,3,3,2,2,1,2,1,1,1,1,1,1,1,1,1,1,1,0,0,0,1,0,0,0,0,0,0]),
        above: bytes([63,20,14,13,12,13,11,11,11,8,8,8,7,7,6,6,5,5,5,4,4,4,3,3,3,3,2,2,2,2,2,2,1,1,1,1,1,1,1,1,1,0,0,1,0,0,0,0,0,0,0,0]),
        left: bytes([76,36,28,29,28,26,25,25,22,22,22,20,19,19,18,17,16,15,14,13,12,12,11,10,9,10,8,7,8,7,7,7,5,5,4,5,5,3,3,3,2,3,3,2,2,2,2,2,2,1,1,1,1,1,0,1,0,1,0,0,0,0,0,1,0,0,0,0]),
        right: bytes([77,36,30,28,27,27,25,24,24,22,21,21,20,17,18,16,16,15,14,14,12,11,12,10,10,9,8,8,7,7,6,6,6,6,5,4,4,4,3,2,3,2,2,3,2,1,2,1,2,2,1,1,0,0,1,0,1,0,0,0,0,0,0,0,0,0,0,0]))
}

@Suite("A clicked window's shadow is a lighter, editable layer style")
struct WindowShotShadowTests {

    @Test func readsTheActiveShadowOffARealDarkWindow() throws {
        let reading = try #require(WindowShot.readSystemShadow(Measured.activeDark, pixelScale: 2))
        #expect(reading.look == .active)
        // Fitted offline at 0.684 against every edge.
        #expect(abs(reading.opacity - 0.68) < 0.04)
        // The dark window's hairline is all but opaque.
        #expect(reading.ringOpacity > 0.8)
    }

    @Test func readsTheInactiveShadowOffARealLightWindow() throws {
        let reading = try #require(WindowShot.readSystemShadow(Measured.inactiveLight, pixelScale: 2))
        #expect(reading.look == .inactive)
        #expect(abs(reading.opacity - 0.25) < 0.03)
        #expect(reading.ringOpacity > 0.15 && reading.ringOpacity < 0.4)
    }

    @Test func nothingThatLooksLikeAShadowReadsAsNone() {
        let empty = WindowShot.EdgeProfiles(below: [], above: [], left: [], right: [])
        #expect(WindowShot.readSystemShadow(empty, pixelScale: 2) == nil)
        let clear = [Double](repeating: 0, count: 80)
        #expect(WindowShot.readSystemShadow(
            WindowShot.EdgeProfiles(below: clear, above: clear, left: clear, right: clear), pixelScale: 2) == nil)
    }

    @Test func oursIsMacOSShapeAtFortyPercent() throws {
        let reading = try #require(WindowShot.readSystemShadow(Measured.activeDark, pixelScale: 2))
        let shadows = WindowShot.shadows(for: reading, pixelScale: 2)
        #expect(shadows.count == 2)
        let soft = try #require(shadows.first)
        let system = WindowShot.SystemShadow.active
        // Same shape as macOS's, in pixels at 2x.
        #expect(soft.radius == system.blur * 2)
        #expect(soft.offset == CGSize(width: 0, height: system.offsetY * 2))
        #expect(soft.spread == system.spread * 2)
        // At 40 percent of the opacity macOS drew it at.
        #expect(abs(soft.opacity - reading.opacity * WindowShot.shadowStrength) < 0.001)
        #expect(WindowShot.shadowStrength == 0.4)
        // The hairline that seats the edge is lightened the same way.
        let ring = try #require(shadows.last)
        #expect(ring.radius < 1 && ring.spread == 1)
        #expect(ring.opacity < reading.ringOpacity)
        #expect(shadows.allSatisfy { $0.kind == .drop && $0.isOn && $0.colorHex == "#000000" })
    }

    @Test func withNoReadingTheWindowGetsTheLightestMacOSShadowAtFortyPercent() {
        let shadows = WindowShot.shadows(for: nil, pixelScale: 2)
        // The soft shadow is first: Shadow 1 in the panel.
        let soft = shadows.first
        #expect(soft?.radius == WindowShot.SystemShadow.inactive.blur * 2)
        #expect(abs((soft?.opacity ?? 0) - WindowShot.SystemShadow.inactive.lightOpacity * 0.4) < 0.001)
    }

    @Test func theCanvasLeavesRoomForEveryPixelOfTheShadow() {
        let shadows = [ShadowStyle(radius: 10, offset: CGSize(width: 4, height: 20), spread: 2, opacity: 0.3)]
        let m = WindowShot.margins(for: shadows)
        // Three sigmas plus the spread, moved by the offset, rounded up.
        #expect(m.bottom == 52)
        #expect(m.top == 12)
        #expect(m.right == 36)
        #expect(m.left == 28)
        // A shadow switched off reaches nowhere.
        var off = shadows[0]
        off.isOn = false
        #expect(WindowShot.margins(for: [off]) == .zero)
    }

    @Test func theDocumentIsTheBareWindowWearingTheShadow() throws {
        let ref = ImageRef(pixelSize: CGSize(width: 1200, height: 864))
        let reading = try #require(WindowShot.readSystemShadow(Measured.activeDark, pixelScale: 2))
        let document = WindowShot.document(window: ref, pixelScale: 2, reading: reading)
        let shadows = WindowShot.shadows(for: reading, pixelScale: 2)
        let margin = WindowShot.margins(for: shadows)
        #expect(document.pixelScale == 2)
        #expect(document.canvasSize == CGSize(width: 1200 + margin.left + margin.right,
                                              height: 864 + margin.top + margin.bottom))
        let layer = try #require(document.layers.first)
        #expect(document.layers.count == 1)
        #expect(layer.name == "Window")
        // Pickable, so its shadow can be reached in the panel.
        #expect(!layer.isLocked)
        #expect(layer.frame == CGRect(x: margin.left, y: margin.top, width: 1200, height: 864))
        #expect(layer.style.shadows == shadows)
        if case .image(let held) = layer.content { #expect(held == ref) } else { Issue.record("not an image layer") }
        // A shadow from an active window falls well below it.
        #expect(margin.bottom > margin.top)
    }

    @Test func theDocumentSurvivesASaveAndOpen() throws {
        let ref = ImageRef(pixelSize: CGSize(width: 300, height: 200))
        let document = WindowShot.document(window: ref, pixelScale: 2, reading: nil)
        let data = try JSONEncoder().encode(document)
        let back = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(back.layers.first?.style.shadows == document.layers.first?.style.shadows)
    }
}
