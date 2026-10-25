import CoreGraphics
import Foundation

// The brush library (`brush-library.html`): every brush as a tile, grouped by
// kind, each tile a sample stroke painted by that very brush. The Library's
// Brushes shelf and the chooser over the tool bar read this one list, so a
// medium added to `BrushMedium` turns up in both with nothing else to edit.
// Painting the tile is PhotonzRender's (`BrushPreview`); this file decides
// what is shown, in what order, and where the sample stroke goes.

/// The kinds a brush is filed under, in the order the mock's chips run.
public enum BrushGroup: String, CaseIterable, Hashable, Sendable {
    case sketch
    case ink
    case paint
    case airbrush
    case texture

    /// What the group is called on screen.
    public var title: String {
        switch self {
        case .sketch: "Sketch"
        case .ink: "Ink"
        case .paint: "Paint"
        case .airbrush: "Airbrush"
        case .texture: "Texture"
        }
    }

    /// The chip's word in the dock, which is narrow: the mock shortens the one
    /// long name there.
    public var chipTitle: String {
        self == .airbrush ? "Air" : title
    }
}

extension BrushMedium {
    /// The group the brush is filed under.
    public var group: BrushGroup {
        switch self {
        case .pencil, .charcoal: .sketch
        case .marker: .ink
        case .oil, .watercolour: .paint
        case .airbrush: .airbrush
        case .chalk, .crayon: .texture
        }
    }

    /// One short line about the brush, for the panel under its settings.
    public var blurb: String {
        switch self {
        case .pencil: "Graphite, from hard and pale to soft."
        case .charcoal: "Loose, dusty charcoal that smudges."
        case .chalk: "Dry chalk with a broken, grainy edge."
        case .crayon: "Waxy crayon that skips over the grain."
        case .marker: "Flat ink that darkens where it crosses."
        case .airbrush: "A soft mist that builds up while held."
        case .oil: "Thick paint that smears and carries."
        case .watercolour: "A wash that pools dark at its edges."
        }
    }
}

/// The library's list: which brushes a group or a search shows, how a tile is
/// named for selection and for a scripted walk, and how the arrow keys move
/// through the chooser's grid.
public enum BrushLibrary {

    /// The brushes a group holds, or every brush for nil (the All chip),
    /// ordered by group and then the order the media are offered in.
    public static func brushes(in group: BrushGroup?, query: String = "") -> [BrushMedium] {
        let ordered = BrushGroup.allCases.flatMap { g in BrushMedium.allCases.filter { $0.group == g } }
        return ordered.filter { medium in
            (group == nil || medium.group == group)
                && LibrarySearch.matches(name: "\(medium.title) \(medium.group.title)", query: query)
        }
    }

    /// The id a tile goes by: steady when its words change.
    public static func entryID(_ medium: BrushMedium) -> String { "brush.\(medium.rawValue)" }

    /// The brush a tile id names, nil for anything else.
    public static func medium(forEntryID id: String) -> BrushMedium? {
        guard id.hasPrefix("brush.") else { return nil }
        return BrushMedium(rawValue: String(id.dropFirst("brush.".count)))
    }

    /// An arrow key in the chooser.
    public enum Arrow: Sendable {
        case left, right, up, down
    }

    /// Where the highlight goes when an arrow is pressed on a grid of `count`
    /// tiles laid `columns` across. Left and right run along the reading
    /// order, up and down move a row; the edges hold, and down from a column
    /// the last row does not reach lands on the last tile. Nothing
    /// highlighted starts at the first tile; nil for an empty grid.
    public static func step(from index: Int?, _ arrow: Arrow, count: Int, columns: Int) -> Int? {
        guard count > 0 else { return nil }
        guard let index else { return 0 }
        let from = min(max(index, 0), count - 1)
        let across = max(columns, 1)
        switch arrow {
        case .left: return max(from - 1, 0)
        case .right: return min(from + 1, count - 1)
        case .up: return from - across >= 0 ? from - across : from
        case .down:
            if from + across < count { return from + across }
            // Already on the last row: stay put.
            return from / across == (count - 1) / across ? from : count - 1
        }
    }
}

/// The sample stroke a brush tile paints: one fixed gesture across the tile,
/// the same every time, so a tile never shimmers between renders, with the
/// brush's own settings and colour.
public enum BrushSample {

    /// How many readings the gesture is made of.
    static let sampleCount = 48

    /// The stroke for `settings` in `colorHex` across a tile of `size`. The
    /// tip is the brush's own size up to what the tile's height can show, so
    /// a 500 point airbrush still reads as a stroke rather than a flood; a
    /// sample always paints, whatever mode the brush is in.
    public static func stroke(settings: BrushSettings, colorHex: String, in size: CGSize) -> BrushStroke {
        var brush = settings
        brush.mode = .paint
        let fits = max(1, Double(size.height) * 0.42)
        if brush.size > fits { brush.set("size", to: fits) }
        let tip = CGFloat(brush.size)
        // The gesture keeps half a tip, and a few points, inside every edge.
        let inset = min(max(4, tip * 0.5 + 2), size.height * 0.45)
        let left = max(inset, size.width * 0.06)
        let right = size.width - left
        let top = inset
        let bottom = size.height - inset
        let samples = (0..<sampleCount).map { i -> StrokeSample in
            let t = Double(i) / Double(sampleCount - 1)
            // One easy S across the tile: up, over and down, the mock's swash.
            let x = left + (right - left) * CGFloat(t)
            let wave = 0.5 - 0.42 * sin(t * 2 * .pi) * (0.55 + 0.45 * sin(t * .pi))
            let y = top + (bottom - top) * CGFloat(wave)
            return StrokeSample(point: CGPoint(x: x, y: y), pressure: pressure(at: t), ms: Double(i) * 16)
        }
        return BrushStroke(samples: samples, settings: brush, colorHex: colorHex, seed: seed(for: settings.medium))
    }

    /// A hand's press along the gesture: light at either end, full in the
    /// middle, so a brush that answers pressure tapers the way the mock's
    /// sample does.
    static func pressure(at t: Double) -> Double {
        let ramp = 0.22
        let edge = pow(min(min(t / ramp, 1), min((1 - t) / ramp, 1)), 0.8)
        return min(max(0.25 + 0.75 * edge, 0), 1)
    }

    /// The tile's seed: fixed per brush, and different between brushes so two
    /// grainy media never share one pattern of grain.
    static func seed(for medium: BrushMedium) -> UInt32 {
        // FNV-1a over the medium's stored name: stable across launches, which
        // `hashValue` is not.
        var hash: UInt32 = 2_166_136_261
        for byte in medium.rawValue.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return hash
    }

    /// Whether the tile's well is the mock's dark one (true) or paper (false)
    /// for a stroke in `colorHex`: whichever the colour stands out against
    /// more, so a black brush is never painted on a black well.
    public static func wellIsDark(forColorHex colorHex: String) -> Bool {
        guard let colour = RGBA(hex: colorHex) else { return true }
        let ink = colour.relativeLuminance
        let againstDark = (ink + 0.05) / (darkWellLuminance + 0.05)
        let againstPaper = (paperWellLuminance + 0.05) / (ink + 0.05)
        return againstDark >= againstPaper
    }

    /// The two wells' own brightness: the mock's #1a1d26 and a warm paper.
    static let darkWellLuminance = 0.012
    static let paperWellLuminance = 0.88
}
