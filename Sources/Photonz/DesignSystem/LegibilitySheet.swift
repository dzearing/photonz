#if DEBUG
import AppKit
import PhotonzCore
import SwiftUI

/// **The legibility check.** Draws every shared control that carries words or
/// an icon, in every state it can be drawn in, light and dark, over what can be
/// behind it, and measures every word and icon against the pixels actually
/// drawn behind it. `Scripts/test.sh` runs it after the tests on every run, and
/// it fails the run naming the control, the state, the scheme and the backdrop.
///
/// The user, 2026-09-30: "I do not want white on white or black on black cases
/// EVER", and "I asked specifically for legible". The bar is
/// `Legibility.floor` (about 3:1): text too close to what is behind it to tell
/// apart fails; the system's own pairings (white on the accent, the system
/// label colours on glass) pass as the system draws them.
///
/// Run: `swift build && .build/debug/Photonz --legibility-sheet [out folder]`
/// (debug builds only; the app bundles are release builds and never carry it).
///
/// **How a word is measured.** Each specimen is drawn three times, identical
/// but for its ink: as shipped; with its words and icons left out (a
/// `TextRenderer` that draws nothing, and `measuredInk()` on icons and bitmap
/// words), which is what lies behind them; and with only them, in one flat
/// colour, which is where they are however they were coloured. That third
/// drawing is what finds a white word on white. `InkReading` (PhotonzCore,
/// tested) groups the ink into words and reads each at its glyph cores.
///
/// **What it cannot draw, and so does not measure.** Liquid Glass is drawn by
/// the window server and is absent offscreen: a control on glass is drawn over
/// white, black and grey veiled by the kit's glass tone, the mock's own glass.
/// The segmented control's chip is drawn with its glass as white, its
/// brightest (the glass itself is filmed on the real window by
/// `segmented-thumb-glass-walk`). AppKit menus, pop-up buttons and system
/// buttons are the system's own pairings. A focus ring is drawn only where a
/// control can be told to show one (the segmented control).
@MainActor
enum LegibilitySheet {
    static let argument = "--legibility-sheet"

    /// Draws the sheet and exits, when the process was started to.
    static func runIfAsked() {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: argument) else { return }
        let out = URL(fileURLWithPath: flag + 1 < arguments.count ? arguments[flag + 1]
                      : NSTemporaryDirectory() + "photonz-legibility")
        try? FileManager.default.removeItem(at: out)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        _ = NSApplication.shared
        exit(run(out: out) ? 0 : 1)
    }

    // MARK: - What a control can be drawn over

    /// What lies behind a specimen.
    enum Ground {
        /// A solid surface of the app's (the panel, the timeline dock).
        case panel
        /// The control's own opaque plate (a tooltip, a caption preview):
        /// drawn on the panel, which it covers.
        case own
        /// Liquid Glass over anything: white, black and grey under the kit's
        /// glass tone, since glass is not drawn offscreen.
        case glass
        /// Straight over anything (a badge on a screenshot): white, black
        /// and grey.
        case anything

        var backdrops: [(name: String, color: Color)] {
            switch self {
            case .panel, .own: [("panel", .clear)]
            case .glass, .anything: [("white", .white), ("black", .black), ("grey", Color(white: 0.5))]
            }
        }
    }

    struct Specimen {
        var control: String
        var state: String
        var ground: Ground
        /// Drawn disabled: held to `Legibility.disabledFloor`.
        var disabled = false
        /// How many separate words or icons it must be seen to carry. Zero
        /// is never right: a specimen with none has lost its words.
        var inks = 1
        var view: @MainActor () -> AnyView
    }

    // MARK: - Drawing

    private struct NoInk: TextRenderer {
        func draw(layout: Text.Layout, in context: inout GraphicsContext) {}
    }

    /// Every glyph in the mask colour, its coverage kept as its opacity.
    private struct MaskInk: TextRenderer {
        func draw(layout: Text.Layout, in context: inout GraphicsContext) {
            var flat = ColorMatrix()
            flat.r1 = 0; flat.r5 = 1
            flat.g2 = 0; flat.g5 = 0
            flat.b3 = 0; flat.b5 = 1
            flat.a4 = 1
            context.addFilter(.colorMatrix(flat))
            for line in layout { context.draw(line) }
        }
    }

    private static func framed(_ specimen: Specimen, scheme: ColorScheme, backdrop: Color,
                               pass: VideoKit.InkPass) -> some View {
        let content = specimen.view()
            .environment(\.inkPass, pass)
            .environment(\.drawnOffscreen, true)
            .padding(10)
            .background {
                ZStack {
                    switch specimen.ground {
                    case .panel, .own: Rectangle().fill(VideoKit.Palette.panel)
                    case .glass:
                        Rectangle().fill(backdrop)
                        Rectangle().fill(VideoKit.Palette.glassChrome)
                    case .anything: Rectangle().fill(backdrop)
                    }
                }
            }
            .environment(\.colorScheme, scheme)
        return Group {
            switch pass {
            case .shown: content
            case .bare: content.textRenderer(NoInk())
            case .mask: content.textRenderer(MaskInk())
            }
        }
    }

    private static func render(_ view: some View) -> CGImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.cgImage
    }

    private static func picture(_ image: CGImage) -> InkPicture? {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: raw.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var pixels: [RGBA] = []
        pixels.reserveCapacity(width * height)
        for index in 0..<(width * height) {
            let at = index * 4
            pixels.append(RGBA(r: Double(bytes[at]) / 255, g: Double(bytes[at + 1]) / 255,
                               b: Double(bytes[at + 2]) / 255))
        }
        return InkPicture(width: width, height: height, pixels: pixels)
    }

    /// How much of each pixel the mask colour covers: the mask drawing is
    /// the bare one with the mask colour laid over it at the ink's coverage.
    private static func coverage(mask: InkPicture, bare: InkPicture) -> [Double] {
        let ink = RGBA(r: 1, g: 0, b: 1)
        return zip(mask.pixels, bare.pixels).map { masked, behind in
            let toward = (ink.r - behind.r, ink.g - behind.g, ink.b - behind.b)
            let length = toward.0 * toward.0 + toward.1 * toward.1 + toward.2 * toward.2
            guard length > 0.01 else { return 0 }
            let moved = (masked.r - behind.r) * toward.0 + (masked.g - behind.g) * toward.1
                + (masked.b - behind.b) * toward.2
            return min(max(moved / length, 0), 1)
        }
    }

    private static func write(_ image: CGImage, to url: URL) {
        if let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
            try? png.write(to: url)
        }
    }

    // MARK: - The run

    static func run(out: URL) -> Bool {
        let started = Date()
        let catalogue = LegibilityCatalogue.specimens
        var failures: [String] = []
        var measured = 0
        for scheme in [ColorScheme.light, .dark] {
            let schemeName = scheme == .dark ? "dark" : "light"
            for specimen in catalogue {
                for backdrop in specimen.ground.backdrops {
                    let place = "\(specimen.control), \(specimen.state), \(schemeName)"
                        + (specimen.ground.backdrops.count > 1 ? " over \(backdrop.name)" : "")
                    guard let shownImage = render(framed(specimen, scheme: scheme, backdrop: backdrop.color,
                                                         pass: .shown)),
                          let bareImage = render(framed(specimen, scheme: scheme, backdrop: backdrop.color,
                                                        pass: .bare)),
                          let maskImage = render(framed(specimen, scheme: scheme, backdrop: backdrop.color,
                                                        pass: .mask)),
                          let shown = picture(shownImage), let bare = picture(bareImage),
                          let mask = picture(maskImage),
                          shown.width == bare.width, shown.width == mask.width,
                          shown.height == bare.height, shown.height == mask.height else {
                        failures.append("\(place): could not be drawn three ways alike")
                        continue
                    }
                    let file = place.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
                    let name = String(file).replacingOccurrences(of: "--", with: "-")
                    write(shownImage, to: out.appendingPathComponent("\(name).png"))
                    if ProcessInfo.processInfo.environment["PHOTONZ_LEGIBILITY_PASSES"] != nil {
                        write(bareImage, to: out.appendingPathComponent("\(name)-bare.png"))
                        write(maskImage, to: out.appendingPathComponent("\(name)-mask.png"))
                    }
                    let readings = InkReading.read(shown: shown, bare: bare,
                                                   mask: coverage(mask: mask, bare: bare))
                    measured += readings.count
                    if let only = ProcessInfo.processInfo.environment["PHOTONZ_LEGIBILITY_SHOW"],
                       place.localizedCaseInsensitiveContains(only) {
                        for reading in readings {
                            print(String(format: "  read %@: %.2f:1, %@ on %@, at %d,%d, %dx%d", place,
                                         reading.contrast, reading.ink.hexString, reading.behind.hexString,
                                         reading.minX / 2, reading.minY / 2, (reading.maxX - reading.minX) / 2,
                                         (reading.maxY - reading.minY) / 2))
                        }
                    }
                    let inks = Set(readings.map { "\($0.minX),\($0.minY)" }).count
                    if inks < specimen.inks {
                        failures.append("\(place): \(inks) of the \(specimen.inks) words or icons it carries were found")
                    }
                    for reading in readings where !Legibility.isLegible(reading, disabled: specimen.disabled) {
                        failures.append(String(
                            format: "%@: %.2f:1, %@ on %@, at %d,%d (%@.png)", place, reading.contrast,
                            reading.ink.hexString, reading.behind.hexString,
                            reading.minX / 2, reading.minY / 2, name))
                    }
                }
            }
        }
        let seconds = Date().timeIntervalSince(started)
        print(String(format: "legibility: %d words and icons measured on %d specimens, light and dark, in %.0fs; "
                     + "pictures in %@", measured, catalogue.count, seconds, out.path))
        if failures.isEmpty {
            print(String(format: "legibility: every word and icon reads against what is behind it (%.0f:1, "
                         + "or %.0f:1 in a plainly different colour; %.1f:1 while disabled)",
                         Legibility.floor, Legibility.colourFloor, Legibility.disabledFloor))
            return true
        }
        print("legibility: UNREADABLE (the user: no white on white or black on black, ever):")
        for failure in failures { print("  \(failure)") }
        return false
    }
}
#endif
