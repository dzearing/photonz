import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// A stroke painted through paint_stroke is the stroke a person's pointer
/// paints (`docs/design/brushes.md`, decision 8): handed the same points,
/// presses, leans and times at the same brush, it lands as the same value on
/// the same layer and the composite is the same pixel for pixel, in every
/// medium, with a mouse and with a pen.
@Suite("An agent's stroke paints exactly what the pointer paints")
struct AgentStrokeLikeThePointerTests {

    private let canvas = CGSize(width: 220, height: 150)

    private func white() throws -> CGImage {
        let width = Int(canvas.width), height = Int(canvas.height)
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                             bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(origin: .zero, size: canvas))
        return try #require(context.makeImage())
    }

    private func bytes(_ image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &data, width: image.width, height: image.height,
                                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data
    }

    /// What the canvas records as a hand drags: a wavering line, the pointer's
    /// uneven event times, a pen's press and lean when it is a pen.
    private func hand(pen: Bool) -> [StrokeSample] {
        var ms = 0.0
        return (0...30).map { i in
            let f = CGFloat(i) / 30
            ms += 7 + Double((i * 37) % 11)
            return StrokeSample(point: CGPoint(x: 20 + 180 * f, y: 70 + 30 * sin(f * 5)),
                                pressure: pen ? 0.3 + 0.6 * Double(f) : nil,
                                tilt: pen ? CGPoint(x: 0.4, y: -0.2) : nil, ms: ms)
        }
    }

    /// The same hand as a paint_stroke call.
    private func call(_ samples: [StrokeSample], medium: BrushMedium, size: Double, seed: UInt32) -> AgentJSON {
        let points: [AgentJSON] = samples.map { sample in
            var point: [String: AgentJSON] = ["x": .number(Double(sample.point.x)), "y": .number(Double(sample.point.y)),
                                              "ms": .number(sample.ms)]
            if let pressure = sample.pressure { point["pressure"] = .number(pressure) }
            if let tilt = sample.tilt { point["tilt"] = ["x": .number(Double(tilt.x)), "y": .number(Double(tilt.y))] }
            return .object(point)
        }
        return ["points": .array(points), "medium": .string(medium.rawValue), "color": "#2A6FDB",
                "settings": ["size": .number(size)], "seed": .number(Double(seed))]
    }

    private func composite(_ stroke: BrushStroke, earlier: [BrushStroke]) throws -> (PhotonzDocument, [UInt8]) {
        let store = ImageStore()
        var document = PhotonzDocument.withBaseImage(store.register(try white()))
        var picked = document.layers.first?.id
        for stroke in earlier + [stroke] {
            picked = stroke.settings.mode == .smudge ? document.smudgeStroke(stroke, onto: picked)
                                                     : document.paintStroke(stroke, onto: picked)
        }
        let image = try #require(DocumentRenderer().render(document, store: store))
        return (document, bytes(image))
    }

    @Test(arguments: BrushMedium.allCases)
    func everyMediumWithAMouseAndAPen(_ medium: BrushMedium) throws {
        for pen in [false, true] {
            let samples = hand(pen: pen)
            let seed = UInt32(41 + BrushMedium.allCases.firstIndex(of: medium)!)
            // The pointer: the armed brush, the swatch's colour, a seed, the time it began.
            let armed = BrushSettings(medium: medium, values: ["size": 26])
            let pointer = BrushStroke(samples: samples, settings: armed, colorHex: "#2A6FDB", seed: seed, startedAt: 500)
            // The agent: the same hand as a call, checked, made into a stroke
            // over a brush in hand that is something else entirely.
            guard case .paintStroke(_, let asked) = try AgentTools.request(
                tool: "paint_stroke", arguments: call(samples, medium: medium, size: 26, seed: seed)).get()
            else { Issue.record("not a paint_stroke"); return }
            let agent = try AgentPaint.brushStroke(asked, armed: BrushSettings(medium: .pencil), armedColorHex: "#000000",
                                                   remembered: { BrushSettings(medium: $0) }, startedAt: 500,
                                                   seed: 1).get()
            #expect(agent == pointer, "\(medium) \(pen ? "pen" : "mouse"): the call made a different stroke")
            // Over paint already there, so oil's pickup and a wash's bloom are in it too.
            let under = BrushStroke(samples: [StrokeSample(point: CGPoint(x: 100, y: 20), ms: 0),
                                              StrokeSample(point: CGPoint(x: 110, y: 130), ms: 300)],
                                    settings: BrushSettings(medium: .watercolour, values: ["size": 30]),
                                    colorHex: "#D03030", seed: 3, startedAt: 499)
            let (byPointer, pointerPixels) = try composite(pointer, earlier: [under])
            let (byAgent, agentPixels) = try composite(agent, earlier: [under])
            // The picture under it is registered afresh each time; the paint is what is compared.
            #expect(byAgent.layers.compactMap(\.paint) == byPointer.layers.compactMap(\.paint))
            #expect(byAgent.layers.compactMap(\.paint).first?.strokes.count == 2)
            #expect(agentPixels == pointerPixels, "\(medium) \(pen ? "pen" : "mouse"): the pictures differ")
        }
    }

    @Test func aSmudgeToo() throws {
        let samples = hand(pen: false)
        var armed = BrushSettings(medium: .charcoal, values: ["size": 30])
        armed.mode = .smudge
        let pointer = BrushStroke(samples: samples, settings: armed, colorHex: "#000000", seed: 8, startedAt: 600)
        var json = call(samples, medium: .charcoal, size: 30, seed: 8).objectValue ?? [:]
        json["mode"] = "smudge"
        json["color"] = "#000000"
        guard case .paintStroke(_, let asked) = try AgentTools.request(tool: "paint_stroke", arguments: .object(json)).get()
        else { Issue.record("not a paint_stroke"); return }
        let agent = try AgentPaint.brushStroke(asked, armed: BrushSettings(medium: .oil), armedColorHex: "#000000",
                                               remembered: { BrushSettings(medium: $0) }, startedAt: 600, seed: 1).get()
        #expect(agent == pointer)
        let paint = BrushStroke(samples: hand(pen: true), settings: BrushSettings(medium: .charcoal, values: ["size": 20]),
                                colorHex: "#202020", seed: 2, startedAt: 590)
        let (_, pointerPixels) = try composite(pointer, earlier: [paint])
        let (_, agentPixels) = try composite(agent, earlier: [paint])
        #expect(agentPixels == pointerPixels)
    }
}
