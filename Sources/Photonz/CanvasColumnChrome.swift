import AppKit
import PhotonzCore

/// The columns a screen is designed to, drawn on the canvas (Next,
/// `next-frames`).
///
/// Chrome, not content: drawn by this view rather than by the renderer, so it
/// can never land in an export or a copied picture, and the document pays
/// nothing for it beyond the four numbers a screen carries.
///
/// Three things make it behave:
///
/// - **Bands, over the screen, not lines under it.** The plain reading of the
///   ask was to draw the columns behind everything on the screen. A new screen
///   paints itself white, so a band behind it is a band nobody can see: the
///   feature would ship looking broken on the very first screen anybody makes.
///   So the columns are drawn OVER the screen and its contents, filled at a low
///   enough alpha that the UI underneath stays completely readable. Same call
///   the canvas grid made, for the same reason.
/// - **A different ink from the grid.** The canvas grid is the accent sunk most
///   of the way into grey, drawn as hairlines. These are a warm red wash with
///   no outline at all. The two can be switched on at once and they have to
///   read as two different things rather than one broken one, so they differ in
///   colour AND in kind: fine lines against soft bands.
/// - **Only what is on screen.** A screen scrolled out of the window contributes
///   nothing, and a band is clipped to the part of the view it actually covers,
///   so a canvas of twenty screens costs what the visible one or two do.
extension CanvasNSView {

    func refreshColumnChrome() {
        guard framesEnabled, let viewport, let document, document.hasFrames,
              bounds.width > 0.5, bounds.height > 0.5 else {
            hideColumnChrome()
            return
        }
        // One sublayer per screen showing columns, because the ink depends on
        // what that screen is painted: a white screen takes the faintest wash
        // that still reads, a dark one takes a stronger one. Two screens on one
        // canvas can be painted differently, so one colour for the lot would be
        // wrong on one of them.
        var drawn: [CAShapeLayer] = []
        for frame in document.frames {
            guard frame.isVisible, let columns = frame.columns, columns.isVisible,
                  let box = document.canvasBounds(of: frame.id) else { continue }
            // A screen scrolled out of the window draws nothing at all.
            guard viewRect(forDocRect: box, in: viewport).intersects(bounds) else { continue }
            let path = CGMutablePath()
            for band in columns.bands(in: box) {
                let rect = viewRect(forDocRect: band, in: viewport).intersection(bounds)
                guard !rect.isNull, rect.width >= 0.5, rect.height >= 0.5 else { continue }
                // Whole view points, so a band's edge sits on a device pixel
                // rather than smearing across two of them — the same reason
                // the grid rounds its lines.
                path.addRect(CGRect(x: rect.minX.rounded(), y: rect.minY.rounded(),
                                    width: max(1, rect.width.rounded()),
                                    height: rect.height.rounded()))
            }
            guard !path.isEmpty else { continue }
            let shape = columnBandLayer(reusing: drawn.count)
            shape.path = path
            shape.fillColor = columnBandInk(on: frame)
            shape.isHidden = false
            drawn.append(shape)
        }
        for spare in (columnChromeLayer.sublayers ?? []).dropFirst(drawn.count) {
            (spare as? CAShapeLayer)?.path = nil
            spare.isHidden = true
        }
        columnChromeLayer.isHidden = drawn.isEmpty
    }

    /// A band layer, made once and then reused: a canvas of screens redraws on
    /// every scroll, and rebuilding layers per frame is how a scroll gets
    /// expensive.
    private func columnBandLayer(reusing index: Int) -> CAShapeLayer {
        let existing = columnChromeLayer.sublayers ?? []
        if index < existing.count, let shape = existing[index] as? CAShapeLayer { return shape }
        let shape = CAShapeLayer()
        shape.strokeColor = nil
        columnChromeLayer.addSublayer(shape)
        return shape
    }

    private func hideColumnChrome() {
        guard !columnChromeLayer.isHidden else { return }
        for shape in columnChromeLayer.sublayers ?? [] {
            (shape as? CAShapeLayer)?.path = nil
            shape.isHidden = true
        }
        columnChromeLayer.isHidden = true
    }

    /// A warm red at low strength: the colour a column overlay is drawn in
    /// almost everywhere, and deliberately nothing like the canvas grid's
    /// cooled accent, so a person with both switched on sees two different
    /// things rather than one broken one.
    ///
    /// The strength follows THE SCREEN, not the app's theme. What a band has to
    /// read against is the surface it is lying on, and a screen paints its own:
    /// a white screen in a dark app is still white. So a dark screen takes a
    /// stronger wash, a light one the faintest that reads, and a screen you can
    /// see straight through is judged by the canvas behind it instead.
    private func columnBandInk(on frame: Layer) -> CGColor {
        let surface = frame.group?.backgroundHex.flatMap { RGBA(hex: $0) }
        let luminance: Double
        if let surface, (surface.a) > 0.5 {
            luminance = surface.relativeLuminance
        } else {
            luminance = isDarkAppearance ? 0 : 1
        }
        // A tenth over a light surface is the faintest wash that still reads;
        // over a dark one it needs half as much again to survive.
        let alpha: CGFloat = luminance >= 0.5 ? 0.10 : 0.20
        var ink = CGColor(red: 1, green: 0.29, blue: 0.35, alpha: alpha)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let warm = NSColor(calibratedRed: 1, green: 0.29, blue: 0.35, alpha: 1)
            if let converted = warm.usingColorSpace(.sRGB) {
                ink = converted.withAlphaComponent(alpha).cgColor
            }
        }
        return ink
    }

    private var isDarkAppearance: Bool {
        effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// What the columns are drawing RIGHT NOW, read off the layer itself rather
    /// than recomputed from the settings, so a walk asserts on what is on
    /// screen. Also says what a drag would catch, so one line of the log
    /// answers "does the pull match the picture".
    var playtestColumnReport: String {
        guard framesEnabled else { return "frames off in Experiments" }
        guard let document else { return "no document" }
        let showing = document.frames.filter { $0.columns?.isVisible == true }
        guard !showing.isEmpty else { return "no screen is showing columns" }
        let names = showing.map { frame -> String in
            let columns = frame.columns ?? FrameColumns()
            return "\(frame.name) \(columns.count)×\(Int(columns.gutter))/\(Int(columns.margin))"
        }.joined(separator: " · ")
        let drawn = columnChromeLayer.isHidden ? "nothing drawn" : "drawn"
        let pull = document.columnBands(excluding: []).count
        return "\(names) · \(drawn) · pulls to \(pull) columns"
    }
}
