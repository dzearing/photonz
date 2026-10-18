import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// The older title set, toned down to calm, presentable versions of itself
/// (task `the-existing-title-pages-are-toned-down-to-calm`).
///
/// Written before the designs changed. The user, 2026-10-18, after the
/// Apple-level pages landed: "The existing title pages are far too busy so i
/// think we need to audit them and tone them down to make them a little more
/// presentable and more subtle." Each of the twelve keeps its own identity
/// (Editorial stays editorial, Tech Terminal stays a terminal) and takes the
/// approved mock's restraint (`docs/design/mocks/pages/video-titles-apple.html`,
/// held for the ten by `TitleCalmSetTests`): one move per part, travel under
/// 24 points, nothing that springs, flips or turns in depth, ins under a second
/// on a soft ease out, backgrounds slowed to barely moving and lowered in
/// strength, glows and grain faint or gone, one accent colour, and type set
/// with tracking and leading. How much less the backgrounds move is measured on
/// the real renderer (`TitleMoreStylesCalmFramesTests`).
@Suite("The older title set, toned down to calm")
struct TitleMoreStylesCalmTests {

    static let canvas = CGSize(width: 1920, height: 1080)
    static let set = BuiltInTitle.shelved.filter { !$0.isCalm }

    @Test("The set is the twelve: the nine More Styles pages and the three name cards")
    func theTwelve() {
        #expect(Self.set.count == 12)
        #expect(Self.set.filter(\.isMoreStyle).count == 9)
        #expect(Self.set.filter { $0.kind == .nameCard }.count == 3)
    }

    @Test("Nothing springs, flips or turns in depth, and nothing overshoots")
    func noSpringsOrTurns() {
        for preset in Self.set {
            for part in preset.design.parts {
                for build in [part.in, part.out].compactMap({ $0 }) {
                    #expect(!build.kind.isInDepth, "\(preset.name) \(part.path) turns: \(build.kind)")
                    #expect(build.kind != .springPop, "\(preset.name) \(part.path) springs")
                    #expect(build.curve != .easeOutBack, "\(preset.name) \(part.path) overshoots")
                }
            }
        }
    }

    @Test("Travel stays under 24 points; a scale within 8 percent; tracking opens no more than the mock's")
    func shortTravel() {
        for preset in Self.set {
            for part in preset.design.parts {
                for build in [part.in, part.out].compactMap({ $0 }) {
                    if build.kind == .rise { #expect(build.amount < 24, "\(preset.name) \(part.path) rises \(build.amount)") }
                    if build.kind == .scaleFrom {
                        #expect(abs(build.amount - 100) <= 8, "\(preset.name) \(part.path) scales from \(build.amount)")
                    }
                    if let scale = build.scale { #expect(abs(scale - 100) <= 8, "\(preset.name) \(part.path) \(scale)") }
                    if build.kind == .trackIn { #expect(build.amount <= 10, "\(preset.name) tracks \(build.amount)") }
                    if build.kind == .blurIn { #expect(build.amount <= 18, "\(preset.name) blurs \(build.amount)") }
                }
            }
        }
    }

    @Test("Every in lasts 360 to 950 ms, and every part has one move at most")
    func oneMovePerPart() {
        for preset in Self.set {
            for part in preset.design.parts {
                var moves = 0
                if let build = part.in {
                    #expect((360...950).contains(build.lengthMS), "\(preset.name) \(part.path) in \(build.lengthMS)")
                    if build.kind != .fade { moves += 1 }
                    if build.blur != nil { moves += 1 }
                    if build.scale != nil { moves += 1 }
                }
                // A background may barely move while it holds; a part with
                // words or a mark on it moves once, or holds, not both.
                if part.role != .background, part.hold.kind != .none { moves += 1 }
                #expect(moves <= 1, "\(preset.name) \(part.path) moves \(moves) ways")
            }
        }
    }

    @Test("Moving looks run at a third of their old speed and strength at most; grain and glows are faint")
    func quietBackgrounds() {
        for preset in Self.set {
            for piece in preset.layer(in: Self.canvas).selfAndDescendants {
                if let live = piece.annotation?.fill?.live {
                    #expect(live.speed <= 35, "\(preset.name) \(piece.name) runs at \(live.speed)")
                    #expect(live.strength <= 35, "\(preset.name) \(piece.name) at strength \(live.strength)")
                }
                for effect in piece.style.effects {
                    if let grain = effect.grain { #expect(grain.amount <= 10, "\(preset.name) grain \(grain.amount)") }
                    if let glow = effect.glow { #expect(glow.opacity <= 0.3, "\(preset.name) glow \(glow.opacity)") }
                }
            }
        }
    }

    /// The hue of `hex` in degrees, nil for a grey, a near black or a pale.
    static func hue(_ hex: String) -> Double? {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count >= 6, let value = UInt32(digits.prefix(6), radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255, g = Double((value >> 8) & 0xFF) / 255, b = Double(value & 0xFF) / 255
        let high = max(r, g, b), low = min(r, g, b), span = high - low
        guard high > 0.3, span / high > 0.3 else { return nil }
        var degrees: Double
        if high == r { degrees = 60 * ((g - b) / span) } else if high == g { degrees = 60 * ((b - r) / span + 2) }
        else { degrees = 60 * ((r - g) / span + 4) }
        if degrees < 0 { degrees += 360 }
        return degrees
    }

    /// The narrowest arc of the colour wheel that holds every hue.
    static func arc(_ hues: [Double]) -> Double {
        let sorted = hues.sorted()
        guard sorted.count > 1, let first = sorted.first, let last = sorted.last else { return 0 }
        var widestGap = first + 360 - last
        for (a, b) in zip(sorted, sorted.dropFirst()) { widestGap = max(widestGap, b - a) }
        return 360 - widestGap
    }

    @Test("One accent colour: every coloured thing in a title sits within one family of hues")
    func oneAccent() {
        for preset in Self.set {
            var hues: [Double] = []
            for piece in preset.layer(in: Self.canvas).selfAndDescendants {
                if let text = piece.text, let hue = Self.hue(text.colorHex) { hues.append(hue) }
                if let fill = piece.annotation?.fill {
                    hues += ([fill.hex] + fill.stops.map(\.hex)).compactMap(Self.hue)
                }
            }
            #expect(Self.arc(hues) <= 60, "\(preset.name) spreads its colours over \(Int(Self.arc(hues))) degrees")
        }
    }

    @Test("Headlines are set with tracking and leading, as the mock sets its type")
    func setType() throws {
        for preset in Self.set {
            let layer = preset.layer(in: Self.canvas)
            let headline = try #require(preset.design.parts.first { $0.role == .headline }, "\(preset.name)")
            let words = try #require(TitleDesign.find(headline.path, in: layer)?.text, "\(preset.name)")
            #expect(words.tracking != nil, "\(preset.name)'s headline has no tracking")
            #expect(words.lineHeight != nil, "\(preset.name)'s headline has no line height")
            if words.fontSize >= 90 {
                #expect((words.tracking ?? 0) < 0, "\(preset.name)'s big headline is not set tight")
            }
        }
    }

    @Test("A title already placed keeps drawing as it was: its look lives in the document, not the preset")
    func placedTitlesKeepTheirLook() throws {
        var doc = PhotonzDocument(canvasSize: Self.canvas)
        var shape = AnnotationContent(shape: .rectangle, strokeWidth: 0, colorHex: "#101318",
                                      start: .zero, end: CGPoint(x: Self.canvas.width, y: Self.canvas.height))
        shape.fill = Paint(hex: "#101318")
        var clip = Layer(name: "Recording", content: .annotation(shape), frame: CGRect(origin: .zero, size: Self.canvas))
        clip.time = LayerTime(inMS: 0, outMS: 10_000, sourceInMS: 0, sourceLengthMS: 10_000)
        doc.layers = [clip]
        doc.durationMS = 10_000
        let landed = doc.insertTitle(.lightLeak, atTimeMS: 0)
        let id = try #require(landed).layerID
        // As a document saved before the set was toned down has it: the
        // light leaks at full speed and strength.
        let background = try #require(doc.layer(id: id).flatMap { TitleDesign.find("Background", in: $0) })
        doc.updateLayer(id: background.id) { layer in
            guard case .annotation(var content) = layer.content, var fill = content.fill, var live = fill.live
            else { return }
            live.speed = 100
            live.strength = 65
            fill.live = live
            content.fill = fill
            layer.content = .annotation(content)
        }
        let saved = try JSONEncoder().encode(doc)
        let opened = try JSONDecoder().decode(PhotonzDocument.self, from: saved)
        let reopened = try #require(opened.layer(id: id).flatMap { TitleDesign.find("Background", in: $0) })
        #expect(reopened.annotation?.fill?.live?.speed == 100)
        #expect(reopened.annotation?.fill?.live?.strength == 65)
        #expect(opened.drawn(atTimeMS: 2000).layer(id: id) == doc.drawn(atTimeMS: 2000).layer(id: id))
    }
}
