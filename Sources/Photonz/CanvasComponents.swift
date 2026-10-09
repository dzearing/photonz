import AppKit
import PhotonzCore

/// The mark a main component wears on the canvas (Next, `next-components`).
///
/// A component that looked exactly like an ordinary group would be a component
/// you could only find out about by opening a panel. So every main carries one
/// word above its top left corner in the component violet, with the four
/// diamond glyph in front of it: the same mark the layers list and the Library
/// tile use, so it is recognisable wherever you meet it. The word is the
/// component's name, or, once the component has more than one drawing on the
/// canvas, which version this drawing is (`CanvasNameLabels.caption`).
///
/// It is chrome, not pixels: drawn by the canvas above the picture, the same
/// size at every zoom, and never in an export. A frame that has been promoted
/// shows this INSTEAD of its frame label, so a box never wears two names.
///
/// The name is a handle, exactly like a screen's name: click it to pick the
/// component, double click it to rename it where it sits. That behaviour is
/// shared with screens and lives in `CanvasNames.swift`.
extension CanvasNSView {

    static let componentGlyphSize: CGFloat = 10

    /// Whether component chrome is drawn at all. A document with no components
    /// in it never sees any of this, which is every screenshot anybody has
    /// taken.
    var componentsEnabled: Bool { Experiments.shared.componentsEnabled }

    /// The mains this canvas should mark, empty when the flag is off or the
    /// document holds none. Also read by the frame chrome, so a promoted frame
    /// drops its own label rather than printing the name twice.
    var markedComponents: [Layer] {
        guard componentsEnabled, let document else { return [] }
        // Only the ones in the picture: an original in the component library
        // is not on this canvas (an editing space is the one place they are).
        var found: [Layer] = []
        document.forEachLayer { if $0.isMainComponent && $0.isVisible { found.append($0) } }
        return found
    }

    /// The copies this canvas should mark. They get the glyph and NO name: a
    /// screen built out of twelve buttons would otherwise wear twelve labels,
    /// and the name of a copy is already in the layers list and the dock.
    var markedComponentInstances: [Layer] {
        guard componentsEnabled, let document else { return [] }
        var found: [Layer] = []
        document.forEachLayer { if $0.isComponentInstance && $0.isVisible { found.append($0) } }
        return found
    }

    func refreshComponentChrome() {
        guard viewport != nil, document != nil,
              !markedComponents.isEmpty || !markedComponentInstances.isEmpty else {
            componentChromeLayer.isHidden = true
            componentChromeLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
            variantGridPanelLayer.isHidden = true
            variantGridPanelLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
            contentLayer.shadowOpacity = Self.pageShadowOpacity
            return
        }
        componentChromeLayer.isHidden = false
        componentChromeLayer.sublayers?.forEach { $0.removeFromSuperlayer() }

        // Where a name goes is decided once, for every chip in the strip at
        // the top of the boxes, so a component in a screen's corner sits on a
        // clear line instead of over the screen's name.
        //
        // The drawing you are looking at goes on LAST, over everything else in
        // the strip: it is the only one wider than the room the row gave it, so
        // it is the only one that can land on a neighbour, and it has to be the
        // one on top when it does.
        let chips = canvasNameChips().filter { $0.kind != .screen }
        for chip in chips where !chip.spelledOut { drawNameChip(chip, into: componentChromeLayer) }
        for chip in chips where chip.spelledOut { drawNameChip(chip, into: componentChromeLayer) }
        drawVariantGridEdges(into: componentChromeLayer)
    }

    /// The components on this canvas laid out as a variant grid right now:
    /// the ones whose drawings are named by the grid's edges instead of their
    /// own chips.
    var componentsShownAsGrid: Set<UUID> {
        guard let document else { return [] }
        var found: Set<UUID> = []
        for main in markedComponents {
            guard let componentID = main.componentID, !found.contains(componentID),
                  document.componentVariantGrid(of: componentID) != nil else { continue }
            found.insert(componentID)
        }
        return found
    }

    /// A component laid out as a grid on its Edit Original page, drawn the
    /// way the variants mock draws its matrix (`ui-variants.html`, `.pmatrix`):
    /// one soft rounded panel under the drawings, the column answers in small
    /// capitals across its top (`.mh`) and the row answers set right beside
    /// their rows (`.rv`). Read off where the drawings stand
    /// (`ComponentVariantGrid`), so a drawing dragged out of line takes the
    /// panel and its names away rather than leaving them naming the wrong row.
    ///
    /// The panel is painted the document's Surface, the colour the drawings
    /// were made to sit on, so a Ghost look's quiet words read on it the way
    /// they would in a real screen; the names are inked for that panel.
    private func drawVariantGridEdges(into target: CALayer) {
        let panels = variantGridPanelLayer
        panels.sublayers?.forEach { $0.removeFromSuperlayer() }
        panels.isHidden = true
        guard let viewport, let document, let host = layer else { return }
        // Straight under the picture, whatever else has been slipped in
        // beneath it since (the graph paper moves there when it is off).
        if let all = host.sublayers, let content = all.firstIndex(of: contentLayer),
           content == 0 || all[content - 1] !== panels {
            host.insertSublayer(panels, below: contentLayer)
        }
        // The page's shadow would lie across the panel and grey it, so while
        // a grid is up the panel is the page you see and the shadow is off.
        defer { contentLayer.shadowOpacity = panels.isHidden ? Self.pageShadowOpacity : 0 }
        let surfaceHex = document.componentVariantGridSurfaceHex
        let surface = RGBA(hex: surfaceHex) ?? RGBA(r: 1, g: 1, b: 1)
        let light = ComponentVariantGrid.namesWantLightInk(onHex: surfaceHex)
        let ink: CGFloat = light ? 1 : 0
        var seen: Set<UUID> = []
        for main in markedComponents {
            guard let componentID = main.componentID, seen.insert(componentID).inserted,
                  let grid = document.componentVariantGrid(of: componentID) else { continue }
            let drawings = viewRect(forDocRect: grid.cellBounds, in: viewport)
            let rowWidth = grid.rows.map { Self.gridRowNameWidth($0.name) }.max() ?? 0
            let panel = ComponentVariantGrid.Panel(around: drawings, rowNameWidth: rowWidth,
                                                   columnNameHeight: Self.gridColumnNameHeight)
            panels.addSublayer(gridPanelLayer(panel.frame, surface: surface, lightInk: light))
            panels.isHidden = false
            drawLiveCopy(of: componentID, grid: grid, panel: panel.frame, surface: surface,
                         lightInk: light, panels: panels, into: target)

            // Zoomed out far enough, narrow columns come closer together than
            // their names are wide. A name that would run into the one before
            // it is left out rather than printed as one word with it
            // ("DEFAULTLARGE"); it is back as soon as there is room.
            var clearFrom = -CGFloat.infinity
            for column in grid.columns {
                let box = viewRect(forDocRect: column.box, in: viewport)
                let word = Self.gridColumnName(column.name, ink: ink)
                let width = word.size().width.rounded(.up)
                let frame = CGRect(x: (box.midX - width / 2).rounded(), y: panel.columnNameBand.minY,
                                   width: width, height: panel.columnNameBand.height)
                guard frame.minX >= clearFrom else { continue }
                clearFrom = frame.maxX + ComponentVariantGrid.Panel.gap
                target.addSublayer(gridNameLayer(word, frame: frame))
            }
            for row in grid.rows {
                let box = viewRect(forDocRect: row.box, in: viewport)
                let word = Self.gridRowName(row.name, ink: ink)
                let size = word.size()
                let frame = CGRect(x: panel.rowNameRight - size.width.rounded(.up),
                                   y: (box.midY - size.height / 2).rounded(),
                                   width: size.width.rounded(.up), height: size.height.rounded(.up))
                target.addSublayer(gridNameLayer(word, frame: frame))
            }
        }
    }

    /// The mock's Live instance block over its matrix (`ui-variants.html`,
    /// `.cvblock`, `.instwrap`, `.pmcell.on`): the picked look's cell lit in
    /// the component violet, and above the grid one copy of that look, on a
    /// stage as wide as the grid's panel, with the component ring round it,
    /// the instance badge over it and each block's header above it.
    ///
    /// The copy is chrome, not a layer: anything loose on an Edit Original
    /// page is folded into the component on Done, so a copy put on the page
    /// would become part of it. It is the picked drawing's own pixels, cut out
    /// of the picture the canvas is already showing, so it follows every edit
    /// to that drawing the moment the picture does and costs no render.
    ///
    /// The stage is painted the Surface like the grid's panel, where the mock
    /// leaves it bare on its dark sheet: on the canvas's own backdrop a Ghost
    /// look's quiet words would not read.
    private func drawLiveCopy(of componentID: UUID, grid: ComponentVariantGrid, panel: CGRect,
                              surface: RGBA, lightInk: Bool, panels: CALayer, into target: CALayer) {
        guard let viewport, let document, !grid.cells.isEmpty else { return }
        let shown = liveCopyDrawing(of: componentID, in: grid, document: document)
        guard let cell = grid.cellBox(of: shown),
              let drawing = document.canvasBounds(of: shown) else { return }

        // The lit cell, under the picture with the panel.
        let apart = PhotonzDocument.variantGridGap * viewport.zoom
        let lit = ComponentVariantGrid.Panel.litCell(viewRect(forDocRect: cell, in: viewport), apart: apart)
        panels.addSublayer(litCellLayer(lit))

        // The stage, sized for the tallest look so a pick never moves it.
        let tallest = grid.cells.compactMap { document.canvasBounds(of: $0.layerID)?.height }.max() ?? 0
        let look = viewRect(forDocRect: drawing, in: viewport)
        let stage = ComponentVariantGrid.LiveStage(above: panel, tallest: tallest * viewport.zoom,
                                                   copy: look.size)
        panels.addSublayer(gridPanelLayer(stage.frame, surface: surface, lightInk: lightInk))

        // The look itself, with the room round it its glow and shadow need:
        // half the gap to its neighbours, which no neighbour reaches into.
        let room = PhotonzDocument.variantGridGap / 2
        let source = drawing.insetBy(dx: -room, dy: -room)
            .intersection(CGRect(origin: .zero, size: document.canvasSize))
        if let image, !source.isNull, document.canvasSize.width > 0, document.canvasSize.height > 0 {
            let copy = CALayer()
            copy.contents = image
            let size = document.canvasSize
            // Unit space, top down like the flipped canvas it sits in.
            copy.contentsRect = CGRect(x: source.minX / size.width,
                                       y: source.minY / size.height,
                                       width: source.width / size.width,
                                       height: source.height / size.height)
            copy.contentsGravity = .resize
            copy.magnificationFilter = viewport.zoom >= 2 ? .nearest : .linear
            copy.minificationFilter = .linear
            copy.frame = stage.copy.offsetBy(dx: (source.minX - drawing.minX) * viewport.zoom,
                                             dy: (source.minY - drawing.minY) * viewport.zoom)
            copy.frame.size = CGSize(width: source.width * viewport.zoom,
                                     height: source.height * viewport.zoom)
            target.addSublayer(copy)
        }

        // `.previnst .cring`: the selection frame's shape in the component
        // colour, which is what says this is a copy and not a drawing.
        let ring = CAShapeLayer()
        ring.frame = stage.ring
        ring.path = CGPath(roundedRect: CGRect(origin: .zero, size: stage.ring.size),
                           cornerWidth: 2, cornerHeight: 2, transform: nil)
        ring.fillColor = nil
        ring.strokeColor = Self.liveRingColor
        ring.lineWidth = 1.5
        ring.contentsScale = window?.backingScaleFactor ?? 2
        target.addSublayer(ring)

        // `.cbadge`, centred over the copy: the copy mark and whose copy it is.
        let name = document.layers.first { $0.componentID == componentID && $0.isMainComponent }?.name
            ?? markedComponents.first { $0.componentID == componentID }?.name ?? "Component"
        drawLiveBadge("instance of \(name)", centredAt: stage.copy.midX, top: stage.badgeTop, into: target)

        // `.cv-h`, one over each block.
        let questions = document.componentVariantProperties(of: componentID).map(\.name)
        drawBlockHeader("Live instance", in: stage.header, into: target)
        drawBlockHeader(questions.joined(separator: " \u{00D7} "), in: stage.gridHeader, into: target)
    }

    /// Which drawing a gridded component's live copy shows: the one picked
    /// now, or inside the one picked now; else the one last picked; else the
    /// look a copy shows when nobody has said otherwise.
    private func liveCopyDrawing(of componentID: UUID, in grid: ComponentVariantGrid,
                                 document: PhotonzDocument) -> UUID {
        let drawings = Set(grid.cells.map(\.layerID))
        var walk = selectedLayerID
        while let id = walk, !drawings.contains(id) { walk = document.parentID(of: id) }
        if let picked = walk { liveCopyPicks[componentID] = picked }
        if let kept = liveCopyPicks[componentID], drawings.contains(kept) { return kept }
        if let first = document.componentVersions(of: componentID).first?.layerID,
           drawings.contains(first) { return first }
        return grid.cells[0].layerID
    }

    /// `--comp`, `#9a5cff`: the component violet the ring and the lit cell
    /// are drawn in.
    static let liveRingColor = CGColor(srgbRed: 0x9A / 255.0, green: 0x5C / 255.0, blue: 0xFF / 255.0, alpha: 1)

    /// `.pmcell.on`: the violet at a fifth behind the look, a violet hairline
    /// round it and a soft ring past that.
    private func litCellLayer(_ frame: CGRect) -> CALayer {
        let cell = CALayer()
        cell.frame = frame
        cell.cornerRadius = ComponentVariantGrid.Panel.litCellCornerRadius
        cell.cornerCurve = .continuous
        cell.contentsScale = window?.backingScaleFactor ?? 2
        cell.backgroundColor = Self.liveRingColor.copy(alpha: 0.22)
        cell.borderWidth = 1
        cell.borderColor = Self.liveRingColor
        // `box-shadow: 0 0 0 1px`, a second line just outside the first.
        cell.shadowColor = Self.liveRingColor
        cell.shadowOpacity = 0.3
        cell.shadowRadius = 0
        cell.shadowOffset = .zero
        cell.shadowPath = CGPath(roundedRect: frame.insetBy(dx: -1, dy: -1)
                                    .offsetBy(dx: -frame.minX, dy: -frame.minY),
                                 cornerWidth: ComponentVariantGrid.Panel.litCellCornerRadius + 1,
                                 cornerHeight: ComponentVariantGrid.Panel.litCellCornerRadius + 1,
                                 transform: nil)
        return cell
    }

    /// `.cbadge`: ten point semibold white words and the copy's one diamond
    /// on the component plate, a six point corner.
    private func drawLiveBadge(_ words: String, centredAt midX: CGFloat, top: CGFloat, into target: CALayer) {
        let font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        let text = NSAttributedString(string: words, attributes: [
            .font: font, .foregroundColor: NSColor.white,
        ])
        let textSize = CGSize(width: text.size().width.rounded(.up), height: text.size().height.rounded(.up))
        let glyph = Self.componentGlyphSize
        let width = 8 + glyph + 5 + textSize.width + 8
        let height = textSize.height + 4
        let plate = CALayer()
        plate.frame = CGRect(x: (midX - width / 2).rounded(), y: top, width: width, height: height)
        plate.cornerRadius = 6
        plate.backgroundColor = Self.componentPlateColor
        plate.contentsScale = window?.backingScaleFactor ?? 2
        target.addSublayer(plate)
        let mark = CAShapeLayer()
        mark.frame = CGRect(x: 8, y: (height - glyph) / 2, width: glyph, height: glyph)
        mark.path = ComponentGlyph.instancePath(in: CGRect(x: 0, y: 0, width: glyph, height: glyph))
        mark.fillColor = Self.plateInkColor
        mark.contentsScale = plate.contentsScale
        plate.addSublayer(mark)
        let label = CATextLayer()
        label.string = text
        label.contentsScale = plate.contentsScale
        label.frame = CGRect(x: 8 + glyph + 5, y: 2, width: textSize.width, height: textSize.height)
        plate.addSublayer(label)
    }

    /// `.cv-h`: the component mark and the block's name in small spaced
    /// capitals, at the left of the block. Inked for the canvas backdrop it
    /// sits on, which follows the Mac's light or dark setting.
    private func drawBlockHeader(_ words: String, in band: CGRect, into target: CALayer) {
        var ink = NSColor.secondaryLabelColor.cgColor
        var dark = false
        effectiveAppearance.performAsCurrentDrawingAppearance {
            ink = NSColor.secondaryLabelColor.cgColor
            dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        }
        let glyph = Self.componentGlyphSize
        let mark = CAShapeLayer()
        mark.frame = CGRect(x: band.minX, y: (band.midY - glyph / 2).rounded(), width: glyph, height: glyph)
        mark.path = ComponentGlyph.path(in: CGRect(x: 0, y: 0, width: glyph, height: glyph))
        // `.cv-h .di`, the light violet on the mock's dark sheet; the full
        // violet on a light backdrop, where the light one washes out.
        mark.fillColor = dark
            ? CGColor(srgbRed: 0xC8 / 255.0, green: 0xA8 / 255.0, blue: 0xFF / 255.0, alpha: 1)
            : Self.liveRingColor
        mark.contentsScale = window?.backingScaleFactor ?? 2
        target.addSublayer(mark)
        let text = NSAttributedString(string: words.uppercased(), attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .kern: 10 * 0.06,
            .foregroundColor: NSColor(cgColor: ink) ?? NSColor.secondaryLabelColor,
        ])
        let size = text.size()
        let label = CATextLayer()
        label.string = text
        label.contentsScale = window?.backingScaleFactor ?? 2
        label.frame = CGRect(x: band.minX + glyph + 8, y: (band.midY - size.height / 2).rounded(),
                             width: min(size.width.rounded(.up), max(band.width - glyph - 8, 0)),
                             height: size.height.rounded(.up))
        label.truncationMode = .end
        target.addSublayer(label)
    }

    /// How dark the picture's drop shadow is. It is shaped like the whole
    /// page, so on a page with nothing painted on it (an Edit Original space)
    /// it also lies across the page itself, over anything drawn beneath the
    /// picture.
    static let pageShadowOpacity: Float = 0.45

    /// `.mh`: nine points, semibold, capitals spaced a twentieth apart, at
    /// half strength.
    static let gridColumnNameFont = NSFont.systemFont(ofSize: 9, weight: .semibold)
    /// `.rv`: eleven points, semibold, at nearly full strength.
    static let gridRowNameFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
    static var gridColumnNameHeight: CGFloat {
        gridColumnName("M", ink: 0).size().height.rounded(.up)
    }

    static func gridColumnName(_ name: String, ink: CGFloat) -> NSAttributedString {
        // Half strength on the mock's dark glass; a touch more on a light
        // panel, where nine point grey letters thin out sooner.
        NSAttributedString(string: name.uppercased(), attributes: [
            .font: gridColumnNameFont,
            .kern: 9 * 0.05,
            .foregroundColor: NSColor(white: ink, alpha: ink == 1 ? 0.5 : 0.55),
        ])
    }

    static func gridRowName(_ name: String, ink: CGFloat) -> NSAttributedString {
        NSAttributedString(string: name, attributes: [
            .font: gridRowNameFont,
            .foregroundColor: NSColor(white: ink, alpha: 0.85),
        ])
    }

    static func gridRowNameWidth(_ name: String) -> CGFloat {
        gridRowName(name, ink: 0).size().width.rounded(.up)
    }

    private func gridNameLayer(_ word: NSAttributedString, frame: CGRect) -> CATextLayer {
        let label = CATextLayer()
        label.string = word
        label.contentsScale = window?.backingScaleFactor ?? 2
        label.alignmentMode = .left
        label.frame = frame
        return label
    }

    /// The panel itself: the Surface, a hairline round it and the lighter
    /// line along its top the mock's glass wears (`border`, `inset 0 1px 0`).
    private func gridPanelLayer(_ frame: CGRect, surface: RGBA, lightInk: Bool) -> CALayer {
        let panel = CALayer()
        panel.frame = frame
        panel.cornerRadius = ComponentVariantGrid.Panel.cornerRadius
        panel.cornerCurve = .continuous
        panel.contentsScale = window?.backingScaleFactor ?? 2
        panel.backgroundColor = CGColor(srgbRed: surface.r, green: surface.g, blue: surface.b, alpha: 1)
        panel.borderWidth = 1
        panel.borderColor = lightInk ? CGColor(gray: 1, alpha: 0.12) : CGColor(gray: 0, alpha: 0.1)
        // A soft shadow, so a white panel on a light page still has an edge.
        panel.shadowColor = CGColor(gray: 0, alpha: 1)
        panel.shadowOpacity = 0.18
        panel.shadowRadius = 8
        panel.shadowOffset = CGSize(width: 0, height: 2)
        let shine = CALayer()
        shine.frame = CGRect(x: ComponentVariantGrid.Panel.cornerRadius, y: 1,
                             width: max(frame.width - ComponentVariantGrid.Panel.cornerRadius * 2, 0),
                             height: 1)
        shine.backgroundColor = CGColor(gray: 1, alpha: lightInk ? 0.14 : 0.7)
        panel.addSublayer(shine)
        return panel
    }

    /// The plate a name is drawn on at rest: the component violet, taken down
    /// until white reads on it (`LabelPlate`, the rule the measure readout and
    /// the arrow caption have always used). It is still recognisably the
    /// component violet, so the chip goes on saying which kind of thing this is.
    static let componentPlateColor = CanvasNSView.plateColor(hex: ComponentPaint.violetHex)

    /// The plate a LIVE name is drawn on: the same rule applied to the app's
    /// accent, so "this word answers a click" survives the move onto a plate
    /// and the words stay readable whatever accent colour the Mac is set to —
    /// including a light one, which a fixed white-on-accent pair would lose.
    var livePlateColor: CGColor {
        var accent = NSColor.controlAccentColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            accent = NSColor.controlAccentColor
        }
        guard let srgb = accent.usingColorSpace(.sRGB) else { return Self.componentPlateColor }
        return Self.plateColor(from: RGBA(r: Double(srgb.redComponent),
                                          g: Double(srgb.greenComponent),
                                          b: Double(srgb.blueComponent)))
    }

    private static func plateColor(hex: String) -> CGColor {
        plateColor(from: RGBA(hex: hex) ?? RGBA(r: 0, g: 0, b: 0))
    }

    private static func plateColor(from color: RGBA) -> CGColor {
        let tone = LabelPlate.tone(from: color)
        return CGColor(srgbRed: tone.r, green: tone.g, blue: tone.b, alpha: 1)
    }

    /// The words and the mark on that plate. White, because the plate is always
    /// dark enough for white — which is the whole reason there is a plate.
    static let plateInkColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)

    /// The plate a SCREEN's name is drawn on: a plain grey taken down by the
    /// same rule, because a screen has no colour of its own (`ScreenPaint`).
    /// It is the lightest plate the rule allows, so a canvas of a dozen screens
    /// carries a dozen quiet chips rather than a dozen near-black ones.
    static let screenPlateColor = CanvasNSView.plateColor(hex: ScreenPaint.greyHex)

    /// One chip drawn into the strip: its mark and the word it is saying right
    /// now, on the plate that lets both be read.
    ///
    /// **Everything here is drawn ON the plate.** A name hangs over whatever
    /// picture happens to be open and cannot know what is under it, so before
    /// this the violet letters read at 1.3:1 on the blue a starter button is
    /// painted in and were simply not there. An opaque plate takes that
    /// question away: the only contrast left is white on the plate, which is
    /// fixed and tested (`LabelPlateTests`).
    ///
    /// A screen's name comes through here too, drawn into the frame chrome
    /// rather than this one's, so the two kinds of name are one treatment by
    /// construction: same pill, same padding, same shadow, same white letters,
    /// and only the plate's colour and the mark in front of it saying which
    /// kind of thing is being named. Before this a screen's name was grey ink
    /// straight on the picture, which read at 1.9:1 over a crimson shape.
    func drawNameChip(_ chip: CanvasNameChip, into target: CALayer) {
        let strip = CanvasNameLabels.box(forFrameRect: chip.label.frameRect)
        let renaming = chip.layer.id == canvasRenameID

        // What this chip puts on the canvas right now. Usually the word it is
        // saying; while it is being renamed, only the words the typing will
        // NOT replace, because the field stands over the rest. On a drawing
        // reading "Save button \u{00B7} Disabled" that leaves "Save button
        // \u{00B7} " printed and the box sitting on "Disabled", so which of the
        // two words is being renamed is plain before anything is typed.
        let printed = renaming ? canvasRenamePrefix(of: chip.layer.id) : chip.word

        // The plate, under the mark and the letters both. Its width follows
        // what is actually being printed, so a name with an open field over
        // half of it does not stretch a pill out under the field.
        // A copy's version is the one word somebody is checking, so a chip
        // that is only saying its mark still gets the plate: a mark nobody can
        // see is as much use as a name nobody can read.
        let plate = CALayer()
        plate.frame = CanvasNameLabels.plateBox(
            for: chip.label, printing: Self.captionWidth(printed))
        plate.cornerRadius = 4
        // The screen's own scale, so the pill's rounded corner is cut at the
        // pixels it will be shown with rather than at one-to-one and softened
        // up by the compositor.
        plate.contentsScale = window?.backingScaleFactor ?? 2
        // A live name — picked, or with the pointer resting on it — moves onto
        // the accent plate, which is the only hint anywhere that a name answers
        // a click. A copy's bare mark is not a handle, so it never lights up.
        plate.backgroundColor = !renaming && chip.kind != .copyMark
            && isNameLabelLive(chip.layer.id)
            ? livePlateColor
            : (chip.kind == .screen ? Self.screenPlateColor : Self.componentPlateColor)
        // The same soft shadow the label pill carries, so the plate's own edge
        // still reads when it lands on something its own colour.
        plate.shadowColor = CGColor(gray: 0, alpha: 1)
        plate.shadowOpacity = 0.35
        plate.shadowRadius = 2
        plate.shadowOffset = CGSize(width: 0, height: 1)
        target.addSublayer(plate)

        // The mark stays put through a rename: it says what kind of thing
        // this is, and that does not change while you are typing. A screen has
        // no mark: its name starts at the box's left edge, and grey-instead-of
        // -violet is how the chip says which kind of thing this is.
        guard chip.kind != .screen else {
            if let word = printed {
                target.addSublayer(nameTextLayer(
                    word, color: Self.plateInkColor,
                    frame: CanvasNameLabels.box(for: chip.label)))
            }
            return
        }
        let glyph = CAShapeLayer()
        let box = CGRect(x: strip.minX,
                         y: strip.minY + (strip.height - Self.componentGlyphSize) / 2,
                         width: Self.componentGlyphSize, height: Self.componentGlyphSize)
        // One diamond for a copy, not the original's four: a different shape
        // rather than a different weight, so it still reads at ten points.
        glyph.path = chip.kind == .component
            ? ComponentGlyph.path(in: box)
            : ComponentGlyph.instancePath(in: box)
        glyph.fillColor = Self.plateInkColor
        glyph.contentsScale = window?.backingScaleFactor ?? 2
        glyph.frame = layer?.bounds ?? strip
        target.addSublayer(glyph)

        // A copy of the first version wears its mark and nothing else, until
        // you look at it: a screen built out of twelve ordinary buttons would
        // otherwise carry twelve labels all saying the same word. A name being
        // renamed with nothing kept in front of the field draws nothing either:
        // the field is standing exactly where the word was.
        guard let word = printed else { return }
        target.addSublayer(nameTextLayer(
            word, color: Self.plateInkColor, frame: CanvasNameLabels.box(for: chip.label)))
    }

    /// The one word of canvas chrome above a drawing, drawn the same way for a
    /// name and for a version so both sit on one line with one baseline.
    func nameTextLayer(_ string: String, color: CGColor, frame: CGRect) -> CATextLayer {
        let label = CATextLayer()
        label.string = string
        label.font = Self.nameLabelFont
        label.fontSize = Self.nameLabelFont.pointSize
        label.foregroundColor = color
        label.contentsScale = window?.backingScaleFactor ?? 2
        label.alignmentMode = .left
        label.truncationMode = .end
        label.frame = frame
        return label
    }
}
