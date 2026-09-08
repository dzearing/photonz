import CoreGraphics
import Foundation
import PhotonzCore
import Testing

@Suite("AnnotationStyles")
struct AnnotationStylesTests {

    // Defaults must match the 3.6 smart defaults: red strokes, yellow highlight.
    @Test func defaultsMatchSmartDefaults() {
        let styles = AnnotationStyles()
        for tool in Tool.allCases {
            #expect(styles.content(for: tool) == tool.defaultAnnotation)
        }
    }

    @Test func nonAnnotationToolsHaveNoContentOrColor() {
        let styles = AnnotationStyles()
        for tool in [Tool.select, .crop, .text] {
            #expect(styles.content(for: tool) == nil)
            #expect(styles.colorHex(for: tool) == nil)
        }
    }

    // Per-type colors: setting a color for one shape must NOT change the others
    // (the user wants each object type to remember its own settings).
    @Test func colorIsPerShape() {
        var styles = AnnotationStyles()
        styles.setColorHex("#007AFF", for: .arrow)
        #expect(styles.colorHex(for: .arrow) == "#007AFF")
        #expect(styles.content(for: .arrow)?.colorHex == "#007AFF")
        // Other shapes are untouched — still the red default.
        for tool in [Tool.line, .rectangle, .ellipse] {
            #expect(styles.colorHex(for: tool) == "#FF3B30")
        }
        #expect(styles.colorHex(for: .highlight) == "#FFD60A")
    }

    @Test func highlightColorIsIndependent() {
        var styles = AnnotationStyles()
        styles.setColorHex("#34C759", for: .highlight)
        #expect(styles.colorHex(for: .highlight) == "#34C759")
        #expect(styles.content(for: .highlight)?.colorHex == "#34C759")
        #expect(styles.colorHex(for: .arrow) == "#FF3B30")
    }

    @Test func settingColorForNonAnnotationToolIsIgnored() {
        var styles = AnnotationStyles()
        styles.setColorHex("#007AFF", for: .select)
        #expect(styles == AnnotationStyles())
    }

    // Per-type stroke width: setting one shape's width leaves the others at the
    // default.
    @Test func strokeWidthIsPerShape() {
        var styles = AnnotationStyles()
        styles.setStrokeWidth(8, forShape: .arrow)
        #expect(styles.content(for: .arrow)?.strokeWidth == 8)
        #expect(styles.strokeWidth(forShape: .arrow) == 8)
        #expect(styles.content(for: .line)?.strokeWidth == AnnotationContent.defaultStrokeWidth)
        // A box and an oval draw no stroke of their own: their edge arrives as
        // a Border instead (`OutlineRetirementTests`).
        for tool in [Tool.rectangle, .ellipse] {
            #expect(styles.content(for: tool)?.strokeWidth == 0)
            #expect(styles.arrivingStyle(forShape: tool.annotationShape!)
                .borderEffects.first?.width == AnnotationContent.defaultStrokeWidth)
        }
    }

    // Per-type arrowhead scale (arrow-only knob).
    @Test func arrowheadScaleIsPerShapeAndDefaultsToOne() {
        var styles = AnnotationStyles()
        #expect(styles.arrowheadScale(forShape: .arrow) == 1.0)
        styles.setArrowheadScale(2.5, forShape: .arrow)
        #expect(styles.arrowheadScale(forShape: .arrow) == 2.5)
        #expect(styles.content(for: .arrow)?.arrowheadScale == 2.5)
    }

    // Highlight is a filled box — stroke width must not apply to it.
    @Test func strokeWidthDoesNotApplyToHighlight() {
        var styles = AnnotationStyles()
        styles.setStrokeWidth(12, forShape: .highlight)
        #expect(Tool.highlight.usesStrokeWidth == false)
        #expect(styles.content(for: .highlight)?.strokeWidth
            == Tool.highlight.defaultAnnotation?.strokeWidth)
        for tool in [Tool.arrow, .line, .rectangle, .ellipse] {
            #expect(tool.usesStrokeWidth)
        }
        for tool in [Tool.select, .crop, .text] {
            #expect(tool.usesStrokeWidth == false)
        }
    }

    // Shape routing and tool routing land in the same per-shape bucket.
    @Test func shapeRoutingMatchesToolRouting() {
        var styles = AnnotationStyles()
        styles.setColorHex("#007AFF", forShape: .arrow)
        #expect(styles.colorHex(for: .arrow) == "#007AFF")
        #expect(styles.colorHex(forShape: .arrow) == "#007AFF")
        // A different shape keeps its own bucket.
        #expect(styles.colorHex(forShape: .line) == "#FF3B30")
        styles.setColorHex("#34C759", forShape: .highlight)
        #expect(styles.colorHex(forShape: .highlight) == "#34C759")
        #expect(styles.colorHex(forShape: .rectangle) == "#FF3B30")
    }

    // The UI builds itself from these; they must be valid and selectable.
    @Test func palettesAreValid() {
        #expect(AnnotationStyles.swatches.count >= 6)
        #expect(Set(AnnotationStyles.swatches).count == AnnotationStyles.swatches.count)
        for hex in AnnotationStyles.swatches {
            #expect(RGBA(hex: hex) != nil)
        }
        // Both defaults must be reachable from the swatch row.
        #expect(AnnotationStyles.swatches.contains(AnnotationStyles().colorHex(forShape: .arrow)))
        #expect(AnnotationStyles.swatches.contains(AnnotationStyles().colorHex(forShape: .highlight)))

        #expect(AnnotationStyles.strokeWidths.count >= 3)
        #expect(AnnotationStyles.strokeWidths == AnnotationStyles.strokeWidths.sorted())
        #expect(AnnotationStyles.strokeWidths.allSatisfy { $0 > 0 })
        #expect(AnnotationStyles.strokeWidths.contains(AnnotationStyles().strokeWidth(forShape: .arrow)))
    }

    // Per-type effects (shadow/opacity/…) are remembered per shape, so a new
    // object of that type inherits the last one's look.
    @Test func layerStyleIsPerShape() {
        var styles = AnnotationStyles()
        #expect(styles.layerStyle(forShape: .arrow).shadow == nil)
        var arrowStyle = LayerStyle()
        arrowStyle.shadow = ShadowStyle()
        styles.setLayerStyle(arrowStyle, forShape: .arrow)
        #expect(styles.layerStyle(forShape: .arrow).shadow != nil)
        // Other shapes keep their (shadowless) default.
        #expect(styles.layerStyle(forShape: .line).shadow == nil)
    }

    // Per-type settings survive app restarts via Codable round-trip.
    @Test func codableRoundTrip() throws {
        var styles = AnnotationStyles()
        styles.setColorHex("#AF52DE", for: .line)
        styles.setColorHex("#FF9500", for: .highlight)
        styles.setStrokeWidth(6, forShape: .line)
        styles.setStrokeWidth(10, forShape: .arrow)
        styles.setArrowheadScale(1.8, forShape: .arrow)
        var arrowStyle = LayerStyle()
        arrowStyle.shadow = ShadowStyle(radius: 8, offset: CGSize(width: 2, height: 3), spread: 4)
        styles.setLayerStyle(arrowStyle, forShape: .arrow)
        let data = try JSONEncoder().encode(styles)
        let decoded = try JSONDecoder().decode(AnnotationStyles.self, from: data)
        #expect(decoded == styles)
    }

    // Taking every effect off a shape has to survive a quit as surely as
    // adding one does. A style with an EMPTY list writes no list at all, so
    // this is the round trip that proves the tool comes back holding nothing
    // rather than falling into the old blur-and-shadow reading.
    @Test func aShapeArmedWithNoEffectsComesBackWithNone() throws {
        var styles = AnnotationStyles()
        var boxed = LayerStyle()
        boxed.effects = [.blur(BlurEffect(radius: 8))]
        styles.setLayerStyle(boxed, forShape: .rectangle)
        var stripped = styles.layerStyle(forShape: .rectangle)
        stripped.effects.removeAll()
        styles.setLayerStyle(stripped, forShape: .rectangle)

        let data = try JSONEncoder().encode(styles)
        let decoded = try JSONDecoder().decode(AnnotationStyles.self, from: data)
        #expect(decoded.layerStyle(forShape: .rectangle).effects.isEmpty)
        #expect(decoded.layerStyle(forShape: .rectangle).blurRadius == 0)
    }

    // Switching one off keeps every number on it, and the order they are in is
    // part of the look, so both have to come back off the disk untouched.
    @Test func aSwitchedOffEffectAndItsOrderSurviveARelaunch() throws {
        var styles = AnnotationStyles()
        var boxed = LayerStyle()
        boxed.effects = [
            .border(BorderEffect(width: 3, colorHex: "#123456", position: .outside)),
            .shadow(ShadowStyle(radius: 9, offset: CGSize(width: 2, height: 3), spread: 4)),
        ]
        boxed.effects[0].isOn = false
        styles.setLayerStyle(boxed, forShape: .rectangle)

        let data = try JSONEncoder().encode(styles)
        let decoded = try JSONDecoder().decode(AnnotationStyles.self, from: data)
        let back = decoded.layerStyle(forShape: .rectangle)
        #expect(back.effects.map(\.kind) == [.border, .shadow])
        #expect(back.effects[0].isOn == false)
        #expect(back.borderEffect(at: 0)?.width == 3)
        #expect(back.borderEffect(at: 0)?.colorHex == "#123456")
        #expect(back.effects[1].isOn == true)
    }

    // Old single-bucket prefs migrate: the shared stroke color/width seed every
    // stroke shape; the highlight color seeds highlight.
    @Test func migratesLegacySharedFormat() throws {
        let legacy = """
        {"strokeColorHex":"#007AFF","highlightColorHex":"#FF9500","strokeWidth":8,"arrowheadScale":2.0}
        """.data(using: .utf8)!
        let styles = try JSONDecoder().decode(AnnotationStyles.self, from: legacy)
        for shape in [AnnotationShape.arrow, .line, .rectangle, .ellipse] {
            #expect(styles.colorHex(forShape: shape) == "#007AFF")
            #expect(styles.strokeWidth(forShape: shape) == 8)
        }
        #expect(styles.colorHex(forShape: .highlight) == "#FF9500")
        #expect(styles.arrowheadScale(forShape: .arrow) == 2.0)
    }
}

// MARK: - Remembering a styled shape as its tool's default

/// What the next box of this kind arrives wearing, after the last one was
/// styled. The one interesting case is a border that was switched OFF: it has
/// to stay a row on the next shape rather than vanishing, exactly as a
/// switched-off shadow does, so one press brings back the line you had instead
/// of a standard new one from the plus.
@Suite("AnnotationStyles remembering")
struct AnnotationStylesRememberingTests {

    private func boxStyle(border: BorderEffect?) -> LayerStyle {
        var style = LayerStyle()
        if let border { style.effects.append(.border(border)) }
        return style
    }

    // A border switched off is remembered as a row that is off, NOT as no
    // border at all: the next box carries it, switched off, with every number
    // it had. Reported 2026-09-08.
    @Test func aBorderSwitchedOffStaysARowOnTheNextShape() {
        var styles = AnnotationStyles()
        var edge = BorderEffect(width: 9, colorHex: "#0A84FF", position: .inside)
        edge.isOn = false
        styles.remember(boxStyle(border: edge), forShape: .rectangle)

        let arriving = styles.arrivingStyle(forShape: .rectangle)
        #expect(arriving.borderEffects.count == 1)
        let kept = arriving.borderEffects.first
        #expect(kept?.isOn == false)
        #expect(kept?.width == 9)
        #expect(kept?.position == .inside)
        #expect(kept?.colorHex == "#0A84FF")
    }

    // ...and it still paints nothing, which is the behaviour the user asked
    // for on 2026-09-06: take the line off a box and the next box is bare.
    @Test func aBorderSwitchedOffDrawsNoLineOnTheNextShape() {
        var styles = AnnotationStyles()
        var edge = BorderEffect(width: 9, position: .inside)
        edge.isOn = false
        styles.remember(boxStyle(border: edge), forShape: .rectangle)

        #expect(styles.arrivingStyle(forShape: .rectangle).paintedBorders.isEmpty)
        // And no stroke of the shape's own sneaks back in either.
        #expect(styles.content(for: .rectangle)?.strokeWidth == 0)
    }

    // Switching it back on is one press, and what comes back is the line that
    // was there: same width, same side of the edge.
    @Test func switchingTheRememberedRowBackOnRestoresTheLineItHad() {
        var styles = AnnotationStyles()
        var edge = BorderEffect(width: 9, position: .inside)
        edge.isOn = false
        styles.remember(boxStyle(border: edge), forShape: .rectangle)

        var arriving = styles.arrivingStyle(forShape: .rectangle)
        guard let index = arriving.borderEffectIndex else { Issue.record("no row"); return }
        arriving.effects[index].border?.isOn = true
        #expect(arriving.paintedBorders.count == 1)
        #expect(arriving.paintedBorders.first?.width == 9)
        #expect(arriving.paintedBorders.first?.position == .inside)
    }

    // A border left ON is lifted onto the tool and put back by
    // `arrivingStyle`, so the next box wears ONE ring rather than two.
    @Test func aBorderLeftOnArrivesOnceAndKeepsItsWidthAndSide() {
        var styles = AnnotationStyles()
        styles.remember(boxStyle(border: BorderEffect(width: 7, position: .center)),
                        forShape: .rectangle)

        let arriving = styles.arrivingStyle(forShape: .rectangle)
        #expect(arriving.borderEffects.count == 1)
        #expect(arriving.borderEffects.first?.isOn == true)
        #expect(arriving.borderEffects.first?.width == 7)
        #expect(arriving.borderEffects.first?.position == .center)
    }

    // Taking the row off with the cross still means gone for good: that is the
    // whole difference between removing and switching off.
    @Test func aBorderRemovedWithTheCrossIsNotOnTheNextShape() {
        var styles = AnnotationStyles()
        styles.remember(boxStyle(border: nil), forShape: .rectangle)

        #expect(styles.arrivingStyle(forShape: .rectangle).borderEffects.isEmpty)
    }

    // Everything else in the list rides along either way.
    @Test func theRestOfTheEffectsListIsRememberedWithTheBorderOffOrOn() {
        for on in [true, false] {
            var styles = AnnotationStyles()
            var edge = BorderEffect(width: 5)
            edge.isOn = on
            var style = LayerStyle()
            style.effects.append(.shadow(ShadowStyle(kind: .drop)))
            style.effects.append(.border(edge))
            styles.remember(style, forShape: .rectangle)

            let arriving = styles.arrivingStyle(forShape: .rectangle)
            #expect(arriving.shadows.count == 1)
            #expect(arriving.borderEffects.count == 1)
            #expect(arriving.borderEffects.first?.isOn == on)
        }
    }

    // Per kind of shape: switching a box's border off leaves the oval alone.
    @Test func switchingABoxBorderOffLeavesTheOvalAlone() {
        var styles = AnnotationStyles()
        var edge = BorderEffect(width: 9, position: .inside)
        edge.isOn = false
        styles.remember(boxStyle(border: edge), forShape: .rectangle)

        let oval = styles.arrivingStyle(forShape: .ellipse)
        let pristine = AnnotationStyles().arrivingStyle(forShape: .ellipse)
        #expect(oval.borderEffects.count == 1)
        #expect(oval.borderEffects.first?.isOn == true)
        #expect(oval.borderEffects == pristine.borderEffects)
    }

    // The row is still there after a relaunch: what the tool remembers is
    // written to prefs, so quitting with the border off must not be the same
    // as never having had one.
    @Test func theSwitchedOffRowSurvivesARelaunch() throws {
        var styles = AnnotationStyles()
        var edge = BorderEffect(width: 9, position: .center)
        edge.isOn = false
        styles.remember(boxStyle(border: edge), forShape: .rectangle)

        let data = try JSONEncoder().encode(styles)
        let reopened = try JSONDecoder().decode(AnnotationStyles.self, from: data)
        let arriving = reopened.arrivingStyle(forShape: .rectangle)
        #expect(arriving.borderEffects.count == 1)
        #expect(arriving.borderEffects.first?.isOn == false)
        #expect(arriving.borderEffects.first?.width == 9)
        #expect(arriving.borderEffects.first?.position == .center)
    }

    // A line and an arrow ARE their stroke, so there is no edge to lift out of
    // them and the style is remembered whole.
    @Test func shapesThatAreTheirOwnStrokeAreRememberedWhole() {
        for shape in [AnnotationShape.line, .arrow, .highlight] {
            var styles = AnnotationStyles()
            var style = LayerStyle()
            style.effects.append(.border(BorderEffect(width: 3)))
            styles.remember(style, forShape: shape)
            #expect(styles.arrivingStyle(forShape: shape).borderEffects.count == 1)
        }
    }
}
