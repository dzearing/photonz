import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// What somebody set by hand on a chart's bars or a title's parts survives a
/// change of numbers or a restyle (task
/// `a-chart-or-title-keeps-what-you-set-by-hand-when`).
///
/// Written before the code. A chart laid out again from new numbers keeps
/// each bar's hand work on the bar of the same row, not on whichever bar now
/// sits in its slot, and a row taken away takes its own work with it. An
/// effect the drawing gave a piece and the person then edited keeps their
/// values through a theme, a font pair, an energy or an intensity, where
/// before it went back to the drawing's.
@Suite("Hand work survives new numbers and a restyle")
struct HandWorkSurvivesRestyleTests {

    // MARK: - Which row is which

    static func spec(_ labels: [String]) -> ChartSpec {
        ChartSpec(kind: .bar, title: "T", rows: labels.enumerated().map { ChartRow(label: $1, value: Double($0 + 1)) })
    }

    @Test("A row taken away: every row after it is still itself")
    func rowRemoved() {
        let old = Self.spec(["A", "B", "C", "D"])
        #expect(Self.spec(["B", "C", "D"]).rowSources(from: old) == [1, 2, 3])
        #expect(Self.spec(["A", "C", "D"]).rowSources(from: old) == [0, 2, 3])
    }

    @Test("A row added or renamed where it stands")
    func rowAddedOrRenamed() {
        let old = Self.spec(["A", "B", "C"])
        #expect(Self.spec(["A", "B", "C", "Item 4"]).rowSources(from: old) == [0, 1, 2, nil])
        #expect(Self.spec(["A", "Bee", "C"]).rowSources(from: old) == [0, 1, 2])
        // A whole new table stands where the old one did, as far as both go.
        #expect(Self.spec(["W", "X", "Y"]).rowSources(from: old) == [0, 1, 2])
        #expect(Self.spec(["W", "X"]).rowSources(from: old) == [0, 1])
        #expect(Self.spec(["V", "W", "X", "Y"]).rowSources(from: old) == [0, 1, 2, nil])
    }

    // MARK: - Effects: the drawing's against the hand's

    static let shade = ShadowStyle(radius: 8, offset: .zero, colorHex: "#000000", opacity: 0.5)
    static let paleShade = ShadowStyle(radius: 8, offset: .zero, colorHex: "#FFFFFF", opacity: 0.5)
    static let glow = GlowEffect(colorHex: "#FF2D55", radius: 18)

    @Test("Untouched effects take the new drawing's; edited, added and deleted ones stay the hand's")
    func effectsMerge() {
        var edited = Self.shade
        edited.radius = 30
        // Untouched: the new drawing's.
        #expect(LayerEffect.keepingHandEdits([.shadow(Self.shade)], drawn: [.shadow(Self.shade)],
                                             fresh: [.shadow(Self.paleShade)]) == [.shadow(Self.paleShade)])
        // Edited: the hand's.
        #expect(LayerEffect.keepingHandEdits([.shadow(edited)], drawn: [.shadow(Self.shade)],
                                             fresh: [.shadow(Self.paleShade)]) == [.shadow(edited)])
        // Added: kept, beside the new drawing's own.
        #expect(LayerEffect.keepingHandEdits([.shadow(Self.shade), .glow(Self.glow)], drawn: [.shadow(Self.shade)],
                                             fresh: [.shadow(Self.paleShade)])
                == [.shadow(Self.paleShade), .glow(Self.glow)])
        // Deleted: stays deleted.
        #expect(LayerEffect.keepingHandEdits([], drawn: [.shadow(Self.shade)],
                                             fresh: [.shadow(Self.paleShade)]).isEmpty)
        // One the new drawing gives that the old did not: it arrives.
        #expect(LayerEffect.keepingHandEdits([.glow(Self.glow)], drawn: [],
                                             fresh: [.shadow(Self.paleShade)])
                == [.glow(Self.glow), .shadow(Self.paleShade)])
    }

    // MARK: - Charts

    static func bar(_ doc: PhotonzDocument, _ id: UUID, _ name: String) throws -> Layer {
        try #require(AnimatedChartTests.piece(doc, id, name))
    }

    /// A key at 1.5s holding half opacity, added to the bar's own opacity
    /// keys the way the Keys row adds one.
    static func keyOpacity(_ doc: inout PhotonzDocument, _ pieceID: UUID) {
        doc.updateLayer(id: pieceID) { layer in
            guard var motions = layer.motions, let index = motions.firstIndex(where: { $0.property == .opacity })
            else { return }
            motions[index] = motions[index].settingKey(atMS: 1_500, value: .number(0.5))
            layer.motions = motions
        }
    }

    static func hasOpacityKey(_ layer: Layer?) -> Bool {
        layer?.motions?.first { $0.property == .opacity }?.keyframes
            .contains { $0.atMS == 1_500 && $0.value == .number(0.5) } ?? false
    }

    static func hasTurnKey(_ layer: Layer?) -> Bool {
        layer?.motions?.contains { $0.property == .rotation } ?? false
    }

    @Test("A bar's own opacity and corners set by hand survive new numbers and a theme")
    func barStyleKept() throws {
        var (doc, id) = try AnimatedChartTests.placed(.bar)
        let bar = try Self.bar(doc, id, "Bar 2")
        doc.updateLayer(id: bar.id) { layer in
            layer.style.opacity = 0.6
            layer.style.cornerRadius = 3
        }
        Self.keyOpacity(&doc, bar.id)
        doc.editChart(layerID: id) { $0.rows[1].value *= 2 }
        for when in ["after new numbers", "after a theme"] {
            let now = try Self.bar(doc, id, "Bar 2")
            #expect(now.style.opacity == 0.6, "\(when)")
            #expect(now.style.cornerRadius == 3, "\(when)")
            #expect(Self.hasOpacityKey(now), "\(when)")
            doc.restyleTitle(layerID: id) { $0.theme = TitleTheme.curated[3] }
        }
        // A bar nobody touched is as the chart draws it.
        #expect(try Self.bar(doc, id, "Bar 1").style.opacity == 1)
    }

    @Test("A row taken away takes its bar's keys with it, and the rest keep theirs")
    func rowRemovedTakesItsKeys() throws {
        var (doc, id) = try AnimatedChartTests.placed(.bar)
        let first = try Self.bar(doc, id, "Bar 1")
        let second = try Self.bar(doc, id, "Bar 2")
        let last = try Self.bar(doc, id, "Bar 4")
        doc.updateLayer(id: first.id) { layer in
            layer.motions = (layer.motions ?? []) + [LayerMotion.keyed(.rotation, atMS: 1_500, value: .number(12))]
        }
        doc.updateLayer(id: second.id) { layer in
            layer.motions = (layer.motions ?? []) + [LayerMotion.keyed(.rotation, atMS: 1_500, value: .number(9))]
            layer.style.opacity = 0.6
        }
        Self.keyOpacity(&doc, second.id)
        Self.keyOpacity(&doc, last.id)
        doc.editChart(layerID: id) { $0.rows.remove(at: 0) }
        let bars = try (1...3).map { try Self.bar(doc, id, "Bar \($0)") }
        // The first row's turn went with it.
        #expect(!bars.contains { $0.motions?.contains { $0.property == .rotation && $0.to == .number(12) } == true })
        // The second row is now the first bar, and wears everything it had.
        #expect(bars[0].motions?.contains { $0.property == .rotation && $0.to == .number(9) } == true)
        #expect(Self.hasOpacityKey(bars[0]))
        #expect(bars[0].style.opacity == 0.6)
        #expect(!Self.hasOpacityKey(bars[1]))
        #expect(bars[1].style.opacity == 1)
        // The last row is the last bar still.
        #expect(Self.hasOpacityKey(bars[2]))
        // ...and its value and label words are its own.
        #expect(try Self.bar(doc, id, "Label 1").text?.string == "Q2")
    }

    @Test("An effect the drawing gave a chart's words, edited, survives new numbers and a theme")
    func chartWordsEditedShadowKept() throws {
        var (doc, id) = try AnimatedChartTests.placed(.bar)
        // Over the footage, with no background, its words throw a shadow.
        doc.restyleTitle(layerID: id) { $0.showsBackground = false }
        let value = try Self.bar(doc, id, "Value 2")
        let drawn = try #require(value.style.shadows.first)
        var edited = drawn
        edited.radius = 40
        edited.colorHex = "#FF0000"
        doc.updateLayer(id: value.id) { $0.style.shadows = [edited] + $0.style.shadows.dropFirst() }
        doc.editChart(layerID: id) { $0.rows[1].value *= 2 }
        #expect(try Self.bar(doc, id, "Value 2").style.shadows.first == edited)
        #expect(try Self.bar(doc, id, "Value 2").style.shadows.count == value.style.shadows.count)
        doc.restyleTitle(layerID: id) { $0.theme = TitleTheme.curated[5] }
        #expect(try Self.bar(doc, id, "Value 2").style.shadows.first == edited)
        // Words nobody touched still take the theme's.
        let other = try Self.bar(doc, id, "Value 1")
        #expect(other.style.shadows.first != edited)
    }

    // MARK: - Titles

    @Test("A title's edited shade survives a theme, a font pair and an energy")
    func titleEditedShadeKept() throws {
        var (doc, id) = try TitleRestyleTests.placed(.keynote)
        let subtitle = try #require(TitleRestyleTests.piece(doc, id, "Subtitle"))
        var edited = try #require(subtitle.style.shadows.first)
        edited.radius = 30
        edited.colorHex = "#FF0000"
        doc.updateLayer(id: subtitle.id) { $0.style.shadows = [edited] }
        let changes: [(String, (inout TitleRecipe) -> Void)] = [
            ("theme", { $0.theme = TitleTheme.curated[4] }),
            ("font pair", { $0.fonts = TitleFontPair.curated[1] }),
            ("energy", { $0.energy = .punchy }),
        ]
        for (name, change) in changes {
            TitleRestyleTests.restyle(&doc, id, change)
            #expect(TitleRestyleTests.piece(doc, id, "Subtitle")?.style.shadows == [edited], "after a \(name)")
        }
    }

    @Test("A title's edited glow keeps its size through an energy, a font pair, a theme and an intensity")
    func titleEditedGlowKept() throws {
        var (doc, id) = try TitleRestyleTests.placed(.lightLeak)
        let title = try #require(TitleRestyleTests.piece(doc, id, "Title"))
        var glow = try #require(title.style.effects.compactMap(\.glow).first)
        glow.radius = 77
        let edited = glow
        doc.updateLayer(id: title.id) { layer in
            layer.style.effects = layer.style.effects.map { $0.glow != nil ? .glow(edited) : $0 }
        }
        let changes: [(String, (inout TitleRecipe) -> Void)] = [
            ("energy", { $0.energy = .punchy }),
            ("font pair", { $0.fonts = TitleFontPair.curated[2] }),
            ("theme", { $0.theme = TitleTheme.curated[0] }),
            ("intensity", { $0.intensity = 60 }),
        ]
        for (name, change) in changes {
            TitleRestyleTests.restyle(&doc, id, change)
            let now = TitleRestyleTests.piece(doc, id, "Title")?.style.effects.compactMap(\.glow)
            #expect(now == [edited], "after a \(name)")
        }
    }

    @Test("A glow nobody touched still follows the intensity")
    func titleUntouchedGlowScales() throws {
        var (doc, id) = try TitleRestyleTests.placed(.lightLeak)
        let before = try #require(TitleRestyleTests.piece(doc, id, "Title")?.style.effects.compactMap(\.glow).first)
        TitleRestyleTests.restyle(&doc, id) { $0.energy = .punchy }
        TitleRestyleTests.restyle(&doc, id) { $0.intensity = 50 }
        let after = try #require(TitleRestyleTests.piece(doc, id, "Title")?.style.effects.compactMap(\.glow).first)
        #expect(abs(after.radius - before.radius / 2) < 0.01)
    }

    @Test("A motion blur shutter set by hand survives an energy; one nobody touched follows it")
    func shutterKept() throws {
        var (doc, id) = try TitleRestyleTests.placed(.keynote, motionBlur: true)
        func shutter() -> Double? {
            doc.layer(id: id)?.style.effects.compactMap { effect -> Double? in
                if case .motionBlur(let blur) = effect { return blur.shutterAngle }
                return nil
            }.first
        }
        TitleRestyleTests.restyle(&doc, id) { $0.energy = .punchy }
        #expect(shutter() == TitleEnergy.punchy.shutterAngle)
        doc.updateLayer(id: id) { layer in
            layer.style.effects = layer.style.effects.map { effect in
                guard case .motionBlur(var blur) = effect else { return effect }
                blur.shutterAngle = 45
                return .motionBlur(blur)
            }
        }
        TitleRestyleTests.restyle(&doc, id) { $0.energy = .calm }
        #expect(shutter() == 45)
    }
}
