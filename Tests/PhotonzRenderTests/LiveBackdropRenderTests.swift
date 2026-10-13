import CoreGraphics
import CoreImage
import Foundation
import PhotonzCore
@testable import PhotonzRender
import Testing

/// Title backgrounds that are alive, as drawn (task
/// `title-backgrounds-that-are-alive-auroras-energy`).
///
/// Every look is drawn through the real renderer, as a full-frame title
/// background on a clock. Measured, not looked at: each one is a different
/// picture from every other, it MOVES (the mean change of a pixel over half a
/// second is many times what the retired Mesh managed, which fails the same
/// bar), it never gets bright enough behind light words (or dark enough
/// behind dark ones) for them to stop reading, and it draws a 1080p frame
/// inside the 16 ms a frame has.
@Suite("Title backgrounds that are alive, as drawn", .serialized)
struct LiveBackdropRenderTests {

    static let canvas = CGSize(width: 1920, height: 1080)
    /// The motion bar's measuring size: the mean change of a pixel does not
    /// depend on how many there are, and a quarter of the pixels is a quarter
    /// of the time.
    static let measured = CGSize(width: 960, height: 540)

    /// The bar, in levels of 255 per channel: the mean change of a pixel
    /// between two frames half a second apart. Chosen on 2026-10-12 against
    /// the retired Mesh at its starting drift, which measured 1.31 (see
    /// `meshFailsTheBar`): a look has to move at least twice what Mesh did.
    static let motionBar = 2.6

    static let night = TitleTheme.curated[0]

    static func paint(_ look: LiveLook, theme: TitleTheme = night,
                      _ change: (inout LiveBackdrop) -> Void = { _ in }) -> Paint {
        var live = LiveBackdrop(look: look)
        change(&live)
        return Paint(hex: theme.ground, kind: .live, stops: theme.liveStops, live: live)
    }

    static func document(_ fill: Paint, size: CGSize = canvas, lengthMS: Int = 10_000) -> PhotonzDocument {
        var content = AnnotationContent(shape: .rectangle, strokeWidth: 0, colorHex: fill.hex,
                                        start: .zero, end: CGPoint(x: size.width, y: size.height))
        content.fill = fill
        var layer = Layer(name: "Background", content: .annotation(content), frame: CGRect(origin: .zero, size: size))
        layer.time = LayerTime(inMS: 0, outMS: lengthMS, sourceInMS: 0)
        var doc = PhotonzDocument(canvasSize: size, layers: [layer])
        doc.durationMS = lengthMS
        return doc
    }

    static func frame(_ doc: PhotonzDocument, atMS ms: Int,
                      renderer: DocumentRenderer = DocumentRenderer()) throws -> [UInt8] {
        let image = try #require(renderer.render(doc.drawn(atTimeMS: ms), store: ImageStore()))
        return bytes(image)
    }

    static func bytes(_ image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        data.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                          bytesPerRow: w * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return data
    }

    /// The mean change of a channel, in levels of 255.
    static func meanChange(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var total = 0
        for index in stride(from: 0, to: a.count, by: 4) {
            total += abs(Int(a[index]) - Int(b[index]))
                + abs(Int(a[index + 1]) - Int(b[index + 1]))
                + abs(Int(a[index + 2]) - Int(b[index + 2]))
        }
        return Double(total) / Double(a.count / 4 * 3)
    }

    /// Linear luminance of every pixel, as light.
    static func luminances(_ data: [UInt8]) -> [Double] {
        func linear(_ v: UInt8) -> Double {
            let c = Double(v) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        var out: [Double] = []
        out.reserveCapacity(data.count / 4)
        for index in stride(from: 0, to: data.count, by: 4) {
            out.append(0.2126 * linear(data[index]) + 0.7152 * linear(data[index + 1])
                       + 0.0722 * linear(data[index + 2]))
        }
        return out
    }

    /// The mean change between two frames half a second apart, averaged over
    /// four places in the clip.
    static func motion(_ fill: Paint) throws -> Double {
        let doc = document(fill, size: measured)
        let renderer = DocumentRenderer()
        var changes: [Double] = []
        for start in [1000, 2500, 4000, 7000] {
            changes.append(meanChange(try frame(doc, atMS: start, renderer: renderer),
                                      try frame(doc, atMS: start + 500, renderer: renderer)))
        }
        return changes.reduce(0, +) / Double(changes.count)
    }

    @Test("The looks compile on this Mac")
    func compiles() {
        #expect(LiveBackdropPainter.isAvailable)
    }

    @Test("Every look is a picture, and a different picture from every other look")
    func everyLookIsItsOwn() throws {
        var frames: [LiveLook: [UInt8]] = [:]
        for look in LiveLook.allCases {
            let data = try Self.frame(Self.document(Self.paint(look), size: Self.measured), atMS: 3000)
            // Not the flat ground: something is drawn over it.
            let ground = try #require(RGBA(hex: Self.night.ground))
            var flat = data
            for index in stride(from: 0, to: flat.count, by: 4) {
                flat[index] = UInt8((ground.r * 255).rounded())
                flat[index + 1] = UInt8((ground.g * 255).rounded())
                flat[index + 2] = UInt8((ground.b * 255).rounded())
            }
            let over = Self.meanChange(data, flat)
            #expect(over > 4, "\(look.title) is barely there over its ground: \(over)")
            frames[look] = data
        }
        for (one, a) in frames {
            for (other, b) in frames where one.rawValue < other.rawValue {
                let apart = Self.meanChange(a, b)
                #expect(apart > 3, "\(one.title) and \(other.title) look alike: \(apart)")
            }
        }
    }

    @Test("The retired Mesh fails the motion bar")
    func meshFailsTheBar() throws {
        let mesh = Paint(hex: "#0E1030", kind: .mesh,
                         stops: [GradientStop(hex: "#0E1030", position: 0),
                                 GradientStop(hex: "#3A1F8F", position: 0.5),
                                 GradientStop(hex: "#8C2B6B", position: 1)],
                         angle: 200, drift: Paint.startingDrift)
        let moved = try Self.motion(mesh)
        print("[live-motion] Mesh (retired), drift \(Int(Paint.startingDrift)): \(String(format: "%.2f", moved)) levels per half second")
        #expect(moved < Self.motionBar)
    }

    @Test("Every look visibly moves: its pixels change by more than the bar over half a second")
    func everyLookMoves() throws {
        for look in LiveLook.allCases {
            let moved = try Self.motion(Self.paint(look))
            print("[live-motion] \(look.title): \(String(format: "%.2f", moved)) levels per half second")
            #expect(moved >= Self.motionBar, "\(look.title) moves \(moved), under the bar \(Self.motionBar)")
        }
    }

    @Test("A look at the same moment is the same picture, so export draws what playback drew")
    func sameMomentSamePicture() throws {
        for look in [LiveLook.aurora, .sketch, .particles] {
            let doc = Self.document(Self.paint(look), size: Self.measured)
            #expect(try Self.frame(doc, atMS: 2345) == Self.frame(doc, atMS: 2345))
        }
    }

    @Test("Light words read over every part of every look on a dark theme, and dark words on a light one")
    func legible() throws {
        for theme in TitleTheme.curated {
            let palette = LivePalette(Self.paint(.aurora, theme: theme))
            let words = try #require(RGBA(hex: theme.primary)).linearLuminance
            for look in LiveLook.allCases {
                // At the most the Strength knob goes to, the worst case.
                let fill = Self.paint(look, theme: theme) { $0.strength = LiveBackdrop.strengthRange.upperBound }
                let lights = Self.luminances(try Self.frame(Self.document(fill, size: Self.measured), atMS: 4000))
                let worst = palette.lightGround ? (lights.min() ?? 0) : (lights.max() ?? 1)
                let ratio = RGBA.contrast(words, worst)
                #expect(ratio >= 3, "\(theme.name) \(look.title): headline at \(String(format: "%.2f", ratio)):1")
            }
        }
    }

    @Test("Every look draws a 1080p frame inside 16 ms at Normal")
    func fastEnough() throws {
        let renderer = DocumentRenderer()
        for look in LiveLook.allCases {
            let doc = Self.document(Self.paint(look))
            _ = try Self.frame(doc, atMS: 0, renderer: renderer)
            var times: [Double] = []
            for step in 1...6 {
                let drawn = doc.drawn(atTimeMS: step * 33)
                let start = DispatchTime.now().uptimeNanoseconds
                let image = renderer.render(drawn, store: ImageStore())
                times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
                #expect(image != nil)
            }
            let best = times.min() ?? 0
            let median = times.sorted()[times.count / 2]
            print("[live-perf] \(look.title) 1920x1080: best \(String(format: "%.1f", best)) ms, median \(String(format: "%.1f", median)) ms")
            #expect(!MachineSpeed.isGating || best < 16, "\(look.title) took \(best) ms")
        }
    }

    @Test("A held look (Speed nought) is a still picture with its look drawn, not its bare ground")
    func heldLook() throws {
        let held = Self.paint(.sketch) { $0.speed = 0 }
        #expect(!held.moves)
        let doc = Self.document(held, size: Self.measured)
        let early = try Self.frame(doc, atMS: 500)
        let late = try Self.frame(doc, atMS: 6000)
        #expect(early == late)
        let lit = Self.luminances(early).filter { $0 > 0.05 }.count
        #expect(lit > 200, "a held sketch should show its drawing, \(lit) lit pixels")
    }
}
