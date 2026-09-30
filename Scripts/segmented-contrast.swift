// Draws the shipped segmented control (Sources/Photonz/DesignSystem/
// SegmentedControl.swift) in every state it can be in, light and dark, over
// white, black and mid grey, and MEASURES every word against the pixels drawn
// behind it. Exits 1 when any word reads below 4.5:1 (3:1 for a picture), and
// names the specimen, the scheme, the backdrop and what the word sat on.
//
// The user, 2026-09-30: "I do not want white on white or black on black cases
// EVER." Scripts/test.sh runs this after the tests, so a colour change that
// breaks the rule fails the build.
//
// Run:
//   swiftc -parse-as-library -swift-version 6 Sources/Photonz/VideoKit/*.swift \
//     Sources/PhotonzCore/SegmentThumbMotion.swift Sources/PhotonzCore/SegmentInk.swift \
//     Sources/PhotonzCore/RGBA.swift Sources/Photonz/DesignSystem/SegmentedControl.swift \
//     Scripts/segmented-contrast.swift -o /tmp/segmented-contrast && /tmp/segmented-contrast [out folder]
//
// How a word is measured: each specimen is drawn twice, once with its words and
// once with them hidden and everything else the same. Where the two differ is a
// word, and the second picture is what lies behind it. The pixels of one
// segment are grouped by what is behind them (the rail, the hover plate, the
// chip: a word the moving chip is half over is two groups), and each group's
// contrast is read at its glyph cores, the pixels a word covers fully.
//
// The chip's glass is drawn by the window server, which an offscreen render
// does not have: here the glass is drawn as plain white under the chip's
// colour, the brightest it could ever be and so the worst case for a white
// word. The glass itself is measured on a real capture of the app
// (segmented-thumb-glass-walk). Pressed is not drawn: it is the hovered
// colours at 97%.
import AppKit
import SwiftUI

// MARK: - The app's seams, stubbed

extension View {
    func kitHover(_ name: String = "", perform: @escaping (Bool) -> Void) -> some View {
        onHover(perform: perform)
    }

    func playtestControl(_ name: String, detail: String = "") -> some View { self }

    func toolTip(_ label: String, key: String? = nil, detail: String? = nil, fallback: String? = nil,
                 below: Bool = false) -> some View { self }

    func segmentToolTips(_ labels: [String], fallback: String, below: Bool = false) -> some View { self }
}

struct PanelFieldRow<Control: View>: View {
    let label: String
    @ViewBuilder let control: Control

    init(_ label: String, @ViewBuilder control: () -> Control) {
        self.label = label
        self.control = control()
    }

    var body: some View { HStack { Text(label); control } }
}

@MainActor final class Experiments {
    static let shared = Experiments()
    var designedSegmentedEnabled: Bool { true }
}

// MARK: - Specimens

struct Specimen {
    var name: String
    var words: [String]
    var on: Int?
    var size: SegmentedControl<Int>.Size = .regular
    var form: SegmentedControl<Int>.Form = .fill
    var width: CGFloat = 240
    var hovered: Int?
    var unavailable: Int?
    var disabled = false
    var focused = false
    var travel: CGFloat?
    var pictures: [String]?

    @MainActor func view(words showsWords: Bool) -> some View {
        let control = DesignedSegments<Int>(
            label: name,
            options: words.indices.map { index in
                .init(index, words[index],
                      image: pictures.flatMap { NSImage(systemSymbolName: $0[index], accessibilityDescription: words[index]) },
                      disabledReason: index == unavailable ? "Not now" : nil)
            },
            selection: on, size: size, form: form, showsTitles: pictures == nil,
            tipsBelow: false, shownHovered: hovered, shownFocused: focused, shownTravel: travel,
            showsWords: showsWords, glassAsWhite: true) { _ in }
        return control
            .disabled(disabled)
            .frame(width: form == .fill ? width : nil)
            .fixedSize(horizontal: form == .natural, vertical: false)
    }
}

let specimens: [Specimen] = [
    Specimen(name: "rest", words: ["Fill", "Fit", "Crop"], on: 1),
    Specimen(name: "hovered", words: ["Fill", "Fit", "Crop"], on: 1, hovered: 0),
    Specimen(name: "one unavailable", words: ["Fill", "Fit", "Stretch"], on: 0, unavailable: 2),
    Specimen(name: "disabled", words: ["Fill", "Fit", "Crop"], on: 1, disabled: true),
    Specimen(name: "focused", words: ["Fill", "Fit", "Crop"], on: 0, focused: true),
    Specimen(name: "nothing picked", words: ["Hug", "Fixed"], on: nil),
    Specimen(name: "mid-move a third", words: ["Left", "Center", "Right"], on: 2, travel: 0.33),
    Specimen(name: "mid-move half", words: ["Left", "Center", "Right"], on: 2, travel: 0.5),
    Specimen(name: "mid-move most", words: ["Left", "Center", "Right"], on: 2, travel: 0.8),
    Specimen(name: "small", words: ["All", "Text", "Shapes"], on: 2, size: .small, form: .natural),
    Specimen(name: "large", words: ["All", "Text", "Shapes"], on: 0, size: .large, form: .natural),
    Specimen(name: "title bar View | Edit", words: ["View", "Edit"], on: 1, size: .small, width: 96),
    Specimen(name: "history filter", words: ["All", "Screenshots", "Videos"], on: 0, form: .natural),
    Specimen(name: "pictures", words: ["Left", "Centre", "Right"], on: 0, form: .natural,
             pictures: ["text.alignleft", "text.aligncenter", "text.alignright"]),
]

// MARK: - Measuring

struct Bitmap {
    let width: Int, height: Int
    var bytes: [UInt8]

    init?(_ image: CGImage) {
        width = image.width
        height = image.height
        bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        if !drawn { return nil }
    }

    func rgb(_ x: Int, _ y: Int) -> RGBA {
        let at = (y * width + x) * 4
        return RGBA(r: Double(bytes[at]) / 255, g: Double(bytes[at + 1]) / 255, b: Double(bytes[at + 2]) / 255)
    }
}

struct Reading {
    var specimen: String
    var scheme: String
    var backdrop: String
    var segment: Int
    var behind: RGBA
    var word: RGBA
    var ratio: Double
    var least: Double
}

@MainActor
func render<V: View>(_ view: V, scheme: ColorScheme, backdrop: Color) -> CGImage? {
    let renderer = ImageRenderer(content: view
        .padding(12)
        .background(backdrop)
        .environment(\.colorScheme, scheme))
    renderer.scale = 2
    return renderer.cgImage
}

func distance(_ a: RGBA, _ b: RGBA) -> Double {
    abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b)
}

/// Every group of word pixels in one specimen, with its contrast at the cores.
func measure(with: Bitmap, without: Bitmap, segments: Int, name: String, scheme: String,
             backdrop: String) -> [Reading] {
    guard with.width == without.width, with.height == without.height else { return [] }
    // The control spans the columns where anything differs from the corner.
    let corner = without.rgb(0, 0)
    var left = with.width, right = 0
    for y in 0..<without.height {
        for x in 0..<without.width where distance(without.rgb(x, y), corner) > 0.02 {
            left = min(left, x)
            right = max(right, x)
        }
    }
    guard right > left else { return [] }
    let span = Double(right - left + 1)
    struct Key: Hashable { var segment: Int; var r: Int; var g: Int; var b: Int }
    var groups: [Key: [(word: RGBA, behind: RGBA, strength: Double)]] = [:]
    for y in 0..<with.height {
        for x in left...right {
            let word = with.rgb(x, y), behind = without.rgb(x, y)
            let strength = distance(word, behind)
            guard strength > 0.12 else { continue }
            let segment = min(segments - 1, Int(Double(x - left) / span * Double(segments)))
            let key = Key(segment: segment, r: Int(behind.r * 12), g: Int(behind.g * 12), b: Int(behind.b * 12))
            groups[key, default: []].append((word, behind, strength))
        }
    }
    return groups.compactMap { key, pixels in
        guard pixels.count >= 12, let strongest = pixels.map(\.strength).max() else { return nil }
        let cores = pixels.filter { $0.strength >= strongest * 0.8 }
        let ratios = cores.map { SegmentInk.contrast($0.word, $0.behind) }.sorted()
        let middle = ratios[ratios.count / 2]
        let core = cores[cores.count / 2]
        return Reading(specimen: name, scheme: scheme, backdrop: backdrop, segment: key.segment,
                       behind: core.behind, word: core.word, ratio: middle, least: ratios.first ?? middle)
    }
}

// MARK: - The run

@MainActor
func run(out: URL) -> Bool {
    let backdrops: [(String, Color)] = [("white", .white), ("black", .black), ("grey", Color(white: 0.5))]
    var failures: [String] = []
    var measured = 0
    for scheme in [ColorScheme.light, .dark] {
        let schemeName = scheme == .dark ? "dark" : "light"
        for (backdropName, backdrop) in backdrops {
            for specimen in specimens {
                guard let shown = render(specimen.view(words: true), scheme: scheme, backdrop: backdrop),
                      let bare = render(specimen.view(words: false), scheme: scheme, backdrop: backdrop),
                      let with = Bitmap(shown), let without = Bitmap(bare) else {
                    failures.append("\(specimen.name) \(schemeName) over \(backdropName): could not be drawn")
                    continue
                }
                let file = "\(specimen.name)-\(schemeName)-\(backdropName)"
                    .replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "|", with: "")
                if let png = NSBitmapImageRep(cgImage: shown).representation(using: .png, properties: [:]) {
                    try? png.write(to: out.appendingPathComponent("\(file).png"))
                }
                let readings = measure(with: with, without: without, segments: specimen.words.count,
                                       name: specimen.name, scheme: schemeName, backdrop: backdropName)
                let wordsExpected = specimen.words.count
                let segmentsRead = Set(readings.map(\.segment)).count
                if segmentsRead < wordsExpected {
                    failures.append("\(specimen.name) \(schemeName) over \(backdropName): only \(segmentsRead) of "
                                    + "\(wordsExpected) words could be seen at all")
                }
                let floor = specimen.pictures == nil ? SegmentInk.minimum : 3
                for reading in readings {
                    measured += 1
                    if reading.ratio < floor {
                        failures.append(String(format: "%@ %@ over %@, segment %d: %.2f:1 (%@ on %@)",
                                               reading.specimen, reading.scheme, reading.backdrop,
                                               reading.segment + 1, reading.ratio,
                                               reading.word.hexString, reading.behind.hexString))
                    }
                }
            }
        }
    }
    print("segmented-contrast: \(measured) words measured across \(specimens.count) specimens, "
          + "light and dark, over white, black and grey; pictures in \(out.path)")
    if failures.isEmpty {
        print("segmented-contrast: every word reads at 4.5:1 or better (pictures 3:1)")
        return true
    }
    print("segmented-contrast: UNREADABLE (the user: no white on white or black on black, ever):")
    for failure in failures { print("  \(failure)") }
    return false
}

@main
struct ContrastSheet {
    @MainActor static func main() {
        let args = CommandLine.arguments
        let out = URL(fileURLWithPath: args.count > 1 ? args[1] : "/tmp/segmented-contrast")
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        _ = NSApplication.shared
        exit(run(out: out) ? 0 : 1)
    }
}
