// Draws the design system's segmented control (Sources/Photonz/DesignSystem/
// SegmentedControl.swift) in every size, form and state that
// docs/design/mocks/pages/comp-segmented.html shows, light and dark, so the
// shipped control can be put beside its component page.
//
// Run:
//   swiftc -parse-as-library -swift-version 6 Sources/Photonz/VideoKit/*.swift \
//     Sources/PhotonzCore/CubicBezier.swift Sources/PhotonzCore/SegmentThumbMotion.swift \
//     Sources/Photonz/DesignSystem/SegmentedControl.swift Scripts/segmented-gallery.swift \
//     -o /tmp/segmented-gallery && /tmp/segmented-gallery <output folder>
//
// Compiled with the control's own file, the kit it draws with, and the few
// app seams stubbed below, so what it draws is the shipped code, not a copy.
import AppKit
import SwiftUI

// MARK: - The app's seams, stubbed

extension View {
    func kitHover(_ name: String = "", perform: @escaping (Bool) -> Void) -> some View {
        onHover(perform: perform)
    }

    func playtestControl(_ name: String, detail: String = "") -> some View { self }

    func toolTip(_ label: String, key: String? = nil, fallback: String? = nil,
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

// MARK: - The sheet

typealias Seg = DesignedSegments<Int>

@MainActor func seg(_ words: [String], on: Int? = 0, size: SegmentedControl<Int>.Size = .regular,
         form: SegmentedControl<Int>.Form = .natural, hovered: Int? = nil, focused: Bool = false,
         unavailable: Int? = nil, images: [String]? = nil, showsTitles: Bool = true,
         plate: SegmentedControl<Int>.PlateStyle = .raised,
         morph: (from: Int, at: TimeInterval)? = nil) -> Seg {
    Seg(label: "specimen",
        options: words.indices.map { index in
            .init(index, words[index], image: images.map { Image(systemName: $0[index]) },
                  disabledReason: index == unavailable ? "Not now" : nil)
        },
        selection: on, size: size, form: form, showsTitles: showsTitles, plateStyle: plate,
        tipsBelow: false, shownHovered: hovered, shownFocused: focused, shownMorph: morph) { _ in }
}

struct Specimen<Content: View>: View {
    let name: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name).font(.system(size: 10, weight: .semibold)).foregroundStyle(VideoKit.Palette.faint)
            content
        }
    }
}

struct Sheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom, spacing: 22) {
                Specimen(name: "SMALL 24") { seg(["All", "Text", "Shapes"], size: .small) }
                Specimen(name: "DEFAULT 28") { seg(["All", "Text", "Shapes"]) }
                Specimen(name: "LARGE 32") { seg(["All", "Text", "Shapes"], size: .large) }
            }
            HStack(alignment: .bottom, spacing: 22) {
                Specimen(name: "FILL") { seg(["Fill", "Fit", "Crop"], form: .fill).frame(width: 216) }
                Specimen(name: "ICONS") {
                    seg(["Align left", "Align centre", "Align right"],
                        images: ["text.alignleft", "text.aligncenter", "text.alignright"], showsTitles: false)
                }
                Specimen(name: "ICON + LABEL") {
                    seg(["Show", "Hide"], images: ["eye", "eye.slash"])
                }
            }
            HStack(alignment: .bottom, spacing: 22) {
                Specimen(name: "REST") { seg(["Fill", "Fit"]) }
                Specimen(name: "HOVER") { seg(["Fill", "Fit"], hovered: 1) }
                Specimen(name: "FOCUS") { seg(["Fill", "Fit"], focused: true) }
                Specimen(name: "ONE UNAVAILABLE") { seg(["Fill", "Stretch"], unavailable: 1) }
                Specimen(name: "DISABLED") { seg(["Fill", "Fit"]).disabled(true) }
            }
            HStack(alignment: .bottom, spacing: 22) {
                Specimen(name: "NOTHING PICKED (MIXED)") { seg(["Hug", "Fixed"], on: nil) }
                Specimen(name: "PANEL ROW, NARROW") {
                    seg(["Free", "Stack", "Grid"], on: 1, form: .fill).frame(width: 118)
                }
                Specimen(name: "TOO NARROW: A MENU") {
                    seg(["Union", "Subtract", "Intersect", "Exclude"], form: .fill).frame(width: 120)
                }
            }
            HStack(alignment: .bottom, spacing: 22) {
                Specimen(name: "TITLE BAR: VIEW | EDIT") {
                    seg(["View", "Edit"], on: 1, size: .small, form: .fill).frame(width: 96)
                }
                Specimen(name: "HISTORY FILTER (ACCENT)") {
                    seg(["All", "Screenshots", "Recordings"], plate: .accent)
                }
            }
            // The morph from Fill to Crop, a frame every 40ms of its 300ms:
            // the leading edge reaching Crop, both slots spanned a little
            // squashed, the trailing edge following it in. Nothing past Crop.
            Specimen(name: "THE MORPH, FILL TO CROP, EVERY 40MS") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(0..<2) { row in
                        HStack(spacing: 14) {
                            ForEach(0..<4) { column in
                                seg(["Fill", "Fit", "Crop"], on: 2, size: .small,
                                    morph: (from: 0, at: Double(row * 4 + column) * 0.04))
                                    .fixedSize()
                            }
                        }
                    }
                }
            }
        }
        .padding(18)
    }
}

// MARK: - Writing

@MainActor
func write(_ scheme: ColorScheme, to url: URL) {
    let renderer = ImageRenderer(content: Sheet()
        .frame(width: 720, alignment: .leading)
        .background(VideoKit.Palette.panel)
        .environment(\.colorScheme, scheme))
    renderer.scale = 2
    guard let image = renderer.cgImage else { exit(1) }
    let rep = NSBitmapImageRep(cgImage: image)
    guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
    do { try png.write(to: url) } catch { exit(1) }
    print("wrote \(url.path) \(rep.pixelsWide)x\(rep.pixelsHigh)")
}

@main
struct Gallery {
    @MainActor static func main() {
        let args = CommandLine.arguments
        let out = URL(fileURLWithPath: args.count > 1 ? args[1] : "/tmp/segmented-gallery")
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        _ = NSApplication.shared
        write(.dark, to: out.appendingPathComponent("segmented-dark.png"))
        write(.light, to: out.appendingPathComponent("segmented-light.png"))
    }
}
