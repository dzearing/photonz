import Foundation

/// The rule every word in the app is held to. The user, 2026-09-30: "I do not
/// want white on white or black on black cases EVER", and, the same day, "I
/// didn't ask specifically for 4.5. I asked specifically for legible."
///
/// So the bar is legible, not a WCAG grade. A word fails when it is too close
/// to what is behind it to tell apart: below about 3:1, or the same colour
/// family at nearly the same lightness. White on white, black on black, grey
/// on grey and lavender on pale lavender all fail. Between 2:1 and 3:1 a word
/// still reads when it is plainly another colour from its ground (white on a
/// saturated clip, red on a grey plate), which a lightness ratio alone
/// undersells. The system's own pairings clear it as the system draws them
/// (white on the Mac's blue is 4.0:1), and nothing is ever darkened or
/// recoloured to chase a higher number.
public enum Legibility {
    /// At or above this a word reads, whatever its colours.
    public static let floor = 3.0

    /// Below this nothing rescues a word, however different its colour.
    public static let colourFloor = 2.0

    /// A word that cannot act right now reads quieter, and may go as quiet as
    /// the system's own disabled label on a window (black at 25% on a light
    /// window, 1.8:1), never quieter.
    public static let disabledFloor = 1.8

    /// Below this much colour (the spread of its channels) a colour is a
    /// grey: white, black, a pale tinted plate.
    static let neutral = 0.06

    /// At least this much colour is a real colour (a clip's cyan, the system
    /// red), not a tint.
    static let vivid = 0.3

    /// Two colours closer in hue than this are one family.
    static let sameHue = 45.0

    public static func isLegible(ink: RGBA, on behind: RGBA, disabled: Bool = false) -> Bool {
        let contrast = SegmentInk.contrast(ink, behind)
        if disabled { return contrast >= disabledFloor }
        if contrast >= floor { return true }
        // Colour carries a word only when one side is a real colour, not a
        // bluish grey on a grey, and the other is not of its family.
        let vivid = max(spread(ink), spread(behind)) >= Self.vivid
        return contrast >= colourFloor && vivid && !sameFamily(ink, behind)
    }

    /// How much colour a colour has: the spread of its channels.
    static func spread(_ color: RGBA) -> Double {
        max(color.r, color.g, color.b) - min(color.r, color.g, color.b)
    }

    public static func isLegible(_ reading: InkReading, disabled: Bool = false) -> Bool {
        isLegible(ink: reading.ink, on: reading.behind, disabled: disabled)
    }

    /// Whether two colours read as one family: two greys, or two colours of
    /// nearly the same hue. A grey and a real colour are two families.
    public static func sameFamily(_ one: RGBA, _ two: RGBA) -> Bool {
        let first = hue(one), second = hue(two)
        switch (first, second) {
        case (nil, nil): return true
        case (nil, _), (_, nil): return false
        case let (a?, b?):
            let apart = abs(a - b).truncatingRemainder(dividingBy: 360)
            return min(apart, 360 - apart) < sameHue
        }
    }

    /// A colour's hue in degrees, or nil for a grey.
    static func hue(_ color: RGBA) -> Double? {
        let high = max(color.r, color.g, color.b)
        let spread = spread(color)
        guard spread >= neutral else { return nil }
        let degrees: Double
        if high == color.r {
            degrees = 60 * ((color.g - color.b) / spread)
        } else if high == color.g {
            degrees = 60 * ((color.b - color.r) / spread) + 120
        } else {
            degrees = 60 * ((color.r - color.g) / spread) + 240
        }
        return degrees < 0 ? degrees + 360 : degrees
    }
}

/// A picture as a flat run of sRGB pixels, row by row from the top.
public struct InkPicture: Sendable {
    public var width: Int
    public var height: Int
    public var pixels: [RGBA]

    public init(width: Int, height: Int, pixels: [RGBA]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }
}

/// How readable the words in a drawn control are, measured on the pixels.
///
/// The control is drawn three ways, the same size and the same everything
/// else: as shipped (`shown`), with its words left out (`bare`, which is what
/// lies behind every word), and a `mask` saying how much of each pixel a word
/// covers, whatever colour the word was drawn in. The mask is what finds a word
/// that cannot be seen: a white word on white leaves no trace in the picture,
/// and is exactly the word this exists to catch.
///
/// Neighbouring letters are one word; a word is judged at its cores (the pixels
/// a glyph covers fully, never its soft edges), and a word lying across two
/// grounds (half on a chip, half on a rail) is judged once on each.
public struct InkReading: Sendable, Equatable {
    /// Where the word is, in the picture's pixels.
    public var minX: Int
    public var minY: Int
    public var maxX: Int
    public var maxY: Int
    /// The word's colour as drawn, at a typical core.
    public var ink: RGBA
    /// What is drawn behind it there.
    public var behind: RGBA
    /// The word's contrast with what is behind it, the middle of its cores.
    public var contrast: Double
    /// Its weakest core.
    public var least: Double

    /// Letters closer than this many pixels belong to one word.
    static let join = 3
    /// How much of a pixel a word must cover to count as part of it at all.
    static let touch = 0.05

    public static func read(shown: InkPicture, bare: InkPicture, mask: [Double]) -> [InkReading] {
        let width = shown.width, height = shown.height
        let count = width * height
        guard bare.width == width, bare.height == height, shown.pixels.count == count,
              bare.pixels.count == count, mask.count == count else { return [] }

        // Group every touched pixel into words: union-find over the pixels a
        // word touches, joining any two within `join` of each other.
        var parent = [Int32](repeating: -1, count: count)
        var touched: [Int] = []
        for index in 0..<count where mask[index] > touch {
            parent[index] = Int32(index)
            touched.append(index)
        }
        if touched.isEmpty { return [] }

        func root(_ index: Int) -> Int {
            var at = index
            while Int(parent[at]) != at {
                let up = Int(parent[Int(parent[at])])
                parent[at] = Int32(up)
                at = up
            }
            return at
        }

        for index in touched {
            let x = index % width, y = index / width
            // Only look forward (later rows, or later in this row): every pair
            // is seen once from its earlier pixel.
            for dy in 0...join where y + dy < height {
                let fromX = dy == 0 ? 1 : -join
                for dx in fromX...join {
                    let nx = x + dx
                    guard nx >= 0, nx < width else { continue }
                    let other = (y + dy) * width + nx
                    guard parent[other] >= 0 else { continue }
                    let a = root(index), b = root(other)
                    if a != b { parent[max(a, b)] = Int32(min(a, b)) }
                }
            }
        }

        var words: [Int: [Int]] = [:]
        for index in touched { words[root(index), default: []].append(index) }

        var readings: [InkReading] = []
        for (_, pixels) in words.sorted(by: { $0.key < $1.key }) {
            guard let strongest = pixels.map({ mask[$0] }).max() else { continue }
            let cores = pixels.filter { mask[$0] >= strongest * 0.9 }
            var minX = width, minY = height, maxX = 0, maxY = 0
            for index in pixels {
                let x = index % width, y = index / width
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }

            // One reading per ground the word lies on.
            struct Ground: Hashable { var r: Int, g: Int, b: Int }
            var grounds: [Ground: [Int]] = [:]
            for index in cores {
                let behind = bare.pixels[index]
                grounds[Ground(r: Int(behind.r * 12), g: Int(behind.g * 12), b: Int(behind.b * 12)),
                        default: []].append(index)
            }
            // A ground under only a sliver of the word (the anti-aliased rim of
            // a chip) says nothing about how the word reads.
            let enough = max(4, cores.count / 10)
            var groups = grounds.values.filter { $0.count >= enough }
            if groups.isEmpty { groups = [cores] }

            for group in groups {
                let measured = group.map { index in
                    (index: index, contrast: SegmentInk.contrast(shown.pixels[index], bare.pixels[index]))
                }.sorted { $0.contrast < $1.contrast }
                let middle = measured[measured.count / 2]
                readings.append(InkReading(
                    minX: minX, minY: minY, maxX: maxX, maxY: maxY,
                    ink: shown.pixels[middle.index], behind: bare.pixels[middle.index],
                    contrast: middle.contrast, least: measured[0].contrast))
            }
        }
        return readings
    }
}
