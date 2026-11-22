import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// The other seven of the designed set, redesigned by the same colour and
/// type rules as the five (task `seven-more-built-in-titles-look-as-refined-as-th`).
///
/// Written before the designs changed. On the blind score of 2026-11-21 they
/// sat between 4.50 and 6.17 against a calm median of 6.83, all for the same
/// reasons: stock violet and electric blue, plain SF Pro, "Your Title". The
/// rules are `docs/design/video-titles-polish.md`, "Colour and type rules for
/// title pages"; how they look is judged from the reel and the blind score,
/// and this holds what can be counted.
@Suite("Seven more titles redesigned by the same rules")
struct TitleRedesignSevenTests {

    static let canvas = CGSize(width: 1920, height: 1080)
    static let seven: [BuiltInTitle] = [.editorial, .glass, .lightLeak, .gradientGlow, .splitWipe, .underline, .pill]
    static let five: [BuiltInTitle] = [.keynote, .softGlass, .kinetic, .terminal, .stacked]

    @Test("The seven keep their names and their places")
    func names() {
        #expect(Self.seven.map(\.name) == ["Editorial Serif", "Behind Glass", "Light Leak", "Gradient Glow",
                                           "Split Wipe", "Minimal Underline", "Pill Card"])
        #expect(Self.seven.prefix(4).allSatisfy { $0.isMoreStyle })
        #expect(Self.seven.suffix(3).allSatisfy { $0.kind == .nameCard })
    }

    @Test("No saturated purple, violet or electric blue anywhere in the seven")
    func noStockPurpleOrBlue() {
        for preset in Self.seven {
            for hex in TitleRedesignTests.colours(preset.layer(in: Self.canvas)) {
                guard let (hue, saturation, value) = TitleRedesignTests.hueAndSaturation(hex) else { continue }
                let stock = (215...300).contains(hue) && saturation > 0.35 && value > 0.25
                #expect(!stock, "\(preset.name) uses \(hex) (hue \(Int(hue)), saturation \(String(format: "%.2f", saturation)))")
            }
            // Glows and shadows count too: a violet glow is still violet.
            for piece in preset.layer(in: Self.canvas).selfAndDescendants {
                for effect in piece.style.effects {
                    guard let glow = effect.glow,
                          let (hue, saturation, value) = TitleRedesignTests.hueAndSaturation(glow.colorHex) else { continue }
                    #expect(!((215...300).contains(hue) && saturation > 0.35 && value > 0.25),
                            "\(preset.name) \(piece.name) glows \(glow.colorHex)")
                }
            }
        }
    }

    @Test("Every headline is set in a face chosen for it, none plain SF Pro, none the same as another's")
    func chosenFaces() throws {
        var faces: [String: String] = [:]
        for preset in Self.five {
            faces[try TitleRedesignTests.headline(preset).fontName] = preset.name
        }
        for preset in Self.seven {
            let words = try TitleRedesignTests.headline(preset)
            #expect(!words.fontName.hasPrefix("SF Pro"), "\(preset.name) is still plain SF Pro")
            #expect(faces[words.fontName] == nil,
                    "\(preset.name) shares \(words.fontName) with \(faces[words.fontName] ?? "")")
            faces[words.fontName] = preset.name
        }
    }

    @Test("Each carries a typographic idea, two sizes three to eight times apart, and a headline never set open")
    func typographicIdea() throws {
        for preset in Self.seven {
            let layer = preset.layer(in: Self.canvas)
            let headline = try TitleRedesignTests.headline(preset)
            let others = layer.selfAndDescendants.compactMap(\.text).filter { $0 != headline }
            let secondFamily = others.contains { $0.fontName != headline.fontName }
            let openCaps = others.contains { ($0.tracking ?? 0) >= 0.1 && $0.string == $0.string.uppercased() }
            #expect(secondFamily || openCaps, "\(preset.name) has no idea in its type")
            #expect((headline.tracking ?? 0) <= 0.02, "\(preset.name)'s headline is set open")
            let sizes = Set(layer.selfAndDescendants.compactMap { $0.text.map { Double($0.fontSize) } })
            if let high = sizes.max(), let low = sizes.min(), low > 0 {
                #expect((2.6...9).contains(high / low), "\(preset.name) sizes \(sizes.sorted())")
            }
        }
    }

    @Test("Sample copy that fits each, never a placeholder")
    func sampleCopy() {
        let placeholders = ["your title", "your name", "role or title", "a short line about it"]
        for preset in Self.seven {
            for words in preset.layer(in: Self.canvas).selfAndDescendants.compactMap(\.text) {
                #expect(!placeholders.contains(words.string.lowercased()), "\(preset.name) shows \"\(words.string)\"")
            }
        }
    }

    @Test("Never pure white words; headlines read at 7:1 or better on their ground, small lines at 4.5:1")
    func contrast() throws {
        for preset in Self.seven {
            let layer = preset.layer(in: Self.canvas)
            // Gradient Glow's words are drawn in its gradient, not their own
            // white, which nobody sees: its stops are what is read.
            let painted = TitleDesign.find("Gradient", in: layer)?.annotation?.fill?.stops.map(\.hex) ?? []
            for words in layer.selfAndDescendants where words.text != nil {
                guard let text = words.text, let ground = Self.ground(of: words, in: layer) else {
                    Issue.record("\(preset.name) \(words.name) stands on nothing")
                    continue
                }
                let inks = words.name == "Title" && !painted.isEmpty ? painted : [text.colorHex]
                if inks == [text.colorHex] {
                    #expect(text.colorHex.uppercased() != "#FFFFFF", "\(preset.name) \(words.name) is pure white")
                }
                for hex in inks {
                    guard let ink = RGBA(hex: hex) else { continue }
                    let ratio = SegmentInk.contrast(ink, ground)
                    let needed = text.fontSize >= 60 ? 7.0 : 4.5
                    #expect(ratio >= needed, "\(preset.name) \(words.name) \(hex) reads at \(String(format: "%.2f", ratio)):1")
                }
            }
        }
    }

    /// The colour words stand on, as `TitleRedesignTests.ground`, leaving
    /// out the gradient that fills Gradient Glow's words: it is their ink.
    static func ground(of words: Layer, in title: Layer) -> RGBA? {
        let pieces = TitleSetTests.flattened(title)
        guard let mine = pieces.first(where: { $0.piece.id == words.id })?.frame else { return nil }
        let middle = CGPoint(x: mine.midX, y: mine.midY)
        var behind: RGBA?
        for (piece, frame) in pieces where piece.id != words.id && piece.text == nil && piece.name != "Gradient" {
            guard let fill = piece.annotation?.fill, frame.contains(middle), frame.height > mine.height,
                  let colour = RGBA(hex: String(fill.hex.prefix(7))) else { continue }
            let alpha = Double(piece.style.opacity)
            if let under = behind {
                behind = RGBA(r: colour.r * alpha + under.r * (1 - alpha), g: colour.g * alpha + under.g * (1 - alpha),
                              b: colour.b * alpha + under.b * (1 - alpha))
            } else {
                behind = colour
            }
        }
        return behind
    }

    @Test("No blob or rounded square stands in for a logo")
    func structuralOrnament() {
        for preset in Self.seven {
            for piece in preset.layer(in: Self.canvas).selfAndDescendants where piece.text == nil {
                guard let shape = piece.annotation, !["Background", "Shade", "Gradient"].contains(piece.name) else { continue }
                let square = abs(piece.frame.width - piece.frame.height) < 4 && piece.frame.width > 20
                #expect(!(square && shape.cornerRadius > 0) && shape.shape != .ellipse,
                        "\(preset.name) \(piece.name) is a decorative mark")
            }
        }
    }

    @Test("A rule belongs to its type: as wide as the words it sits under")
    func rulesFitTheirType() throws {
        let layer = BuiltInTitle.editorial.layer(in: Self.canvas)
        let rule = try #require(TitleDesign.find("Rule", in: layer))
        let title = try #require(TitleDesign.find("Title", in: layer))
        #expect(abs(rule.frame.width - title.frame.width) <= title.frame.width * 0.35,
                "rule \(Int(rule.frame.width)) under words \(Int(title.frame.width))")
    }

    // MARK: - Old documents and shelf entries

    @Test("A shelf entry or drag that names one opens the new design")
    func entriesOpenTheNewDesign() throws {
        for preset in Self.seven {
            let opened = try #require(TitlePreset(entryID: "title.builtIn.\(preset.rawValue)", saved: []), "\(preset.rawValue)")
            #expect(opened.name == preset.name)
            let fresh = try #require(BuiltInTitle(rawValue: preset.rawValue))
            #expect(try TitleRedesignTests.headline(fresh).fontName == TitleRedesignTests.headline(preset).fontName)
        }
    }

    @Test("A document holding one of the old seven opens drawing it exactly as it was")
    func oldDocumentsKeepTheirLook() throws {
        for preset in Self.seven {
            var (doc, id) = try TitleSetTests.placed(preset)
            // As a document saved before the redesign has it: plain SF Pro,
            // "Your Title" and an electric blue fill wherever one is filled.
            let title = try #require(doc.layer(id: id))
            let headlinePath = try #require(preset.design.parts.first { $0.role == .headline }?.path)
            let headline = try #require(TitleDesign.find(headlinePath, in: title))
            doc.updateLayer(id: headline.id) { layer in
                guard case .text(var words) = layer.content else { return }
                words.fontName = "SF Pro"
                words.string = "Your Title"
                layer.content = .text(words)
            }
            if let background = TitleDesign.find("Background", in: title) {
                doc.updateLayer(id: background.id) { layer in
                    guard case .annotation(var content) = layer.content, var fill = content.fill else { return }
                    fill.hex = "#1A4DFF"
                    if !fill.stops.isEmpty { fill.stops[0].hex = "#1A4DFF" }
                    content.fill = fill
                    layer.content = .annotation(content)
                }
            }
            let opened = try JSONDecoder().decode(PhotonzDocument.self, from: JSONEncoder().encode(doc))
            let reopened = try #require(opened.layer(id: id))
            let words = TitleDesign.find(headlinePath, in: reopened)?.text
            #expect(words?.fontName == "SF Pro", "\(preset.name)")
            #expect(words?.string == "Your Title", "\(preset.name)")
            if TitleDesign.find("Background", in: title)?.annotation?.fill != nil {
                #expect(TitleDesign.find("Background", in: reopened)?.annotation?.fill?.hex == "#1A4DFF", "\(preset.name)")
            }
            #expect(opened.drawn(atTimeMS: 3000).layer(id: id) == doc.drawn(atTimeMS: 3000).layer(id: id))
        }
    }
}
