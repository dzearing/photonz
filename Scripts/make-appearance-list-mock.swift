// Draws the Appearance panel strips in the "how does the list grow" decision
// brief. Run: swift Scripts/make-appearance-list-mock.swift <output folder> [prefix]
//
// These are MOCKS, not the app: nothing here is shipped code. Every strip shows
// the SAME rectangle — a red fill, a border sitting inside the edge, and two
// drop shadows — so the three models can be compared on one shape. The colours
// and metrics are lifted from Scripts/make-parts-mock.swift, which was traced
// off a probe capture of the real dock.
import AppKit
import SwiftUI

let panelBG = Color(red: 0.161, green: 0.176, blue: 0.196)
let sectionRule = Color.white.opacity(0.08)
let titleColor = Color.white.opacity(0.92)
let labelColor = Color.white.opacity(0.62)
let dimLabel = Color.white.opacity(0.30)
let valueColor = Color.white.opacity(0.85)
let trackColor = Color.white.opacity(0.16)
let knobColor = Color.white.opacity(0.92)
let accent = Color(red: 0.09, green: 0.45, blue: 0.96)
let shapeRed = Color(red: 0.894, green: 0.302, blue: 0.227)
let inkBlue = Color(red: 0.16, green: 0.36, blue: 0.72)

let panelWidth: CGFloat = 300

// MARK: - Pieces

struct SectionHeader: View {
    let title: String
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(sectionRule).frame(height: 1)
            HStack(spacing: 6) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(titleColor)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(titleColor)
                Spacer(minLength: 0)
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.30))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
    }
}

struct Swatch: View {
    var color: Color
    var body: some View {
        RoundedRectangle(cornerRadius: 4).fill(color).frame(width: 22, height: 20)
    }
}

struct StylesMenu: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "swatchpalette").font(.system(size: 11))
            Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
        }
        .foregroundStyle(Color.white.opacity(0.72))
    }
}

struct Checkbox: View {
    var on: Bool
    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(on ? accent : Color.white.opacity(0.10))
            .frame(width: 14, height: 14)
            .overlay { if on {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .heavy)).foregroundStyle(.white)
            } }
            .overlay { if !on {
                RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.22), lineWidth: 1)
            } }
    }
}

/// The trailing controls an entry in an addable list wears: a grip to drag it
/// by, and a cross to take it out. Only a countable kind has them.
struct EntryControls: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 9)).foregroundStyle(Color.white.opacity(0.28))
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.45))
        }
    }
}

/// One effect's headline: name, tick, colour, and whatever the model puts at
/// the trailing edge.
struct EffectRow<Trailing: View>: View {
    var label: String
    var on: Bool = true
    var color: Color? = shapeRed
    var summary: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(on ? labelColor : dimLabel)
                .frame(width: 82, alignment: .leading)
            Checkbox(on: on).frame(width: 16, height: 20, alignment: .leading)
            if on, let color {
                Swatch(color: color)
                StylesMenu()
            } else {
                Color.clear.frame(width: 22, height: 20)
            }
            if let summary, on {
                Text(summary)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.42))
                    .lineLimit(1)
                    .padding(.leading, 2)
            }
            Spacer(minLength: 0)
            trailing
        }
        .frame(height: 22)
        .padding(.horizontal, 14)
    }
}

extension EffectRow where Trailing == EmptyView {
    init(label: String, on: Bool = true, color: Color? = shapeRed, summary: String? = nil) {
        self.init(label: label, on: on, color: color, summary: summary) { EmptyView() }
    }
}

struct SliderRow: View {
    var label: String
    var value: String
    var fraction: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label).font(.system(size: 11)).foregroundStyle(labelColor)
                Spacer()
                Text(value).font(.system(size: 11)).foregroundStyle(valueColor)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(trackColor).frame(height: 4)
                        .frame(maxHeight: .infinity, alignment: .center)
                    Circle().fill(knobColor).frame(width: 13, height: 13)
                        .offset(x: max(0, (proxy.size.width - 13) * fraction))
                }
            }
            .frame(height: 13)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 3)
    }
}

/// A setting that picks one of a few words: a border's Position, a shadow's
/// Kind. Drawn as the pull-down the panel already uses elsewhere.
struct PopupRow: View {
    var label: String
    var value: String
    var body: some View {
        HStack {
            Text(label).font(.system(size: 11)).foregroundStyle(labelColor)
            Spacer()
            HStack(spacing: 6) {
                Text(value).font(.system(size: 11)).foregroundStyle(valueColor)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.10)))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 3)
    }
}

/// The one gesture that grows the list.
struct AddRow: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus").font(.system(size: 10, weight: .bold))
            Text("Add effect").font(.system(size: 11))
            Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.white.opacity(0.62))
        .padding(.horizontal, 14)
        .padding(.top, 2)
    }
}

struct ShadowSettings: View {
    var blur: String; var blurF: Double
    var size: String; var sizeF: Double
    var distance: String; var distanceF: Double
    var direction: String; var directionF: Double
    var opacity: String; var opacityF: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SliderRow(label: "Blur", value: blur, fraction: blurF)
            SliderRow(label: "Size", value: size, fraction: sizeF)
            SliderRow(label: "Distance", value: distance, fraction: distanceF)
            SliderRow(label: "Direction", value: direction, fraction: directionF)
            SliderRow(label: "Opacity", value: opacity, fraction: opacityF)
        }
    }
}

struct PanelFrame<Content: View>: View {
    let caption: String
    let note: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(caption)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.75))
                Text(note)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.42))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)
            content
            Spacer(minLength: 10)
            Rectangle().fill(sectionRule).frame(height: 1)
        }
        .frame(width: panelWidth, alignment: .leading)
        .background(panelBG)
    }
}

struct PartsList<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) { content }
            .padding(.vertical, 8)
    }
}

// MARK: - The panels

/// What Appearance holds today: three rows, one of each, no way to ask for a
/// second shadow and no word for where the border sits.
struct TodayPanel: View {
    var body: some View {
        PanelFrame(caption: "Today", note: "Three rows, one of each. There is nowhere to put a second shadow and no way to say the border sits inside the edge.") {
            SectionHeader(title: "Appearance")
            PartsList {
                EffectRow(label: "Fill")
                VStack(alignment: .leading, spacing: 6) {
                    EffectRow(label: "Outline")
                    SliderRow(label: "Width", value: "4 pt", fraction: 0.1)
                }
                VStack(alignment: .leading, spacing: 6) {
                    EffectRow(label: "Shadow", color: .black)
                    ShadowSettings(blur: "12 pt", blurF: 0.3, size: "0 pt", sizeF: 0,
                                   distance: "6 pt", distanceF: 0.15,
                                   direction: "135°", directionF: 0.37,
                                   opacity: "35%", opacityF: 0.35)
                }
            }
        }
    }
}

/// A: everything is an entry in one list. A plus at the foot adds, a cross
/// removes, rows drag, and settings stay on screen the way they do today.
struct OptionAPanel: View {
    var body: some View {
        PanelFrame(caption: "A. One list you add to", note: "Fill and Outline are always there. The plus adds a shadow, a glow, a bevel. Anything added has a cross. Rows drag, and the top one paints nearest you.") {
            SectionHeader(title: "Appearance")
            PartsList {
                EffectRow(label: "Fill")
                VStack(alignment: .leading, spacing: 6) {
                    EffectRow(label: "Outline")
                    SliderRow(label: "Width", value: "4 pt", fraction: 0.1)
                    PopupRow(label: "Position", value: "Inside")
                }
                VStack(alignment: .leading, spacing: 6) {
                    EffectRow(label: "Shadow", color: .black) { EntryControls() }
                    PopupRow(label: "Kind", value: "Drop")
                    ShadowSettings(blur: "4 pt", blurF: 0.1, size: "0 pt", sizeF: 0,
                                   distance: "2 pt", distanceF: 0.05,
                                   direction: "135°", directionF: 0.37,
                                   opacity: "55%", opacityF: 0.55)
                }
                VStack(alignment: .leading, spacing: 6) {
                    EffectRow(label: "Shadow", color: inkBlue) { EntryControls() }
                    PopupRow(label: "Kind", value: "Drop")
                    ShadowSettings(blur: "30 pt", blurF: 0.75, size: "4 pt", sizeF: 0.1,
                                   distance: "18 pt", distanceF: 0.45,
                                   direction: "135°", directionF: 0.37,
                                   opacity: "22%", opacityF: 0.22)
                }
                AddRow()
            }
        }
    }
}

/// B: the same list, but an effect you are not editing folds to one line that
/// says what it is set to. Click it to open; only one is open at a time.
struct OptionBPanel: View {
    var body: some View {
        PanelFrame(caption: "B. One list, effects fold to a line", note: "The same growth, but an effect you are not editing shows its settings as a summary. Click one to open it. Two shadows cost two lines instead of twelve.") {
            SectionHeader(title: "Appearance")
            PartsList {
                EffectRow(label: "Fill")
                EffectRow(label: "Outline", summary: "4 pt · Inside")
                EffectRow(label: "Shadow", color: .black, summary: "Drop · 4 pt") { EntryControls() }
                VStack(alignment: .leading, spacing: 6) {
                    EffectRow(label: "Shadow", color: inkBlue) { EntryControls() }
                    PopupRow(label: "Kind", value: "Drop")
                    ShadowSettings(blur: "30 pt", blurF: 0.75, size: "4 pt", sizeF: 0.1,
                                   distance: "18 pt", distanceF: 0.45,
                                   direction: "135°", directionF: 0.37,
                                   opacity: "22%", opacityF: 0.22)
                }
                AddRow()
            }
        }
    }
}

/// C: no growth. Every effect the app knows has a permanent row with a tick,
/// inner and outer are separate rows, and you can never have two of anything.
struct OptionCPanel: View {
    var body: some View {
        PanelFrame(caption: "C. A fixed row for every effect", note: "No plus, no cross, no dragging. Every effect is always on the list so you can find it by reading. You cannot have two shadows, so the second one here had to become an inner shadow.") {
            SectionHeader(title: "Appearance")
            PartsList {
                EffectRow(label: "Fill")
                VStack(alignment: .leading, spacing: 6) {
                    EffectRow(label: "Outline")
                    SliderRow(label: "Width", value: "4 pt", fraction: 0.1)
                }
                EffectRow(label: "Inner Border", on: false, color: nil)
                VStack(alignment: .leading, spacing: 6) {
                    EffectRow(label: "Shadow", color: .black)
                    ShadowSettings(blur: "4 pt", blurF: 0.1, size: "0 pt", sizeF: 0,
                                   distance: "2 pt", distanceF: 0.05,
                                   direction: "135°", directionF: 0.37,
                                   opacity: "55%", opacityF: 0.55)
                }
                VStack(alignment: .leading, spacing: 6) {
                    EffectRow(label: "Inner Shadow", color: inkBlue)
                    ShadowSettings(blur: "30 pt", blurF: 0.75, size: "4 pt", sizeF: 0.1,
                                   distance: "18 pt", distanceF: 0.45,
                                   direction: "135°", directionF: 0.37,
                                   opacity: "22%", opacityF: 0.22)
                }
                EffectRow(label: "Outer Glow", on: false, color: nil)
                EffectRow(label: "Inner Glow", on: false, color: nil)
                EffectRow(label: "Bevel", on: false, color: nil)
            }
        }
    }
}

// MARK: - Render

@MainActor
func write(_ view: some View, to url: URL) {
    let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
    renderer.scale = 2
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("could not render \(url.lastPathComponent)\n".utf8))
        exit(1)
    }
    try? png.write(to: url)
    print("wrote \(url.path) \(rep.pixelsWide)x\(rep.pixelsHigh)")
}

let folder = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let prefix = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "appearance"

MainActor.assumeIsolated {
    write(TodayPanel(), to: folder.appendingPathComponent("\(prefix)-today.png"))
    write(OptionAPanel(), to: folder.appendingPathComponent("\(prefix)-a.png"))
    write(OptionBPanel(), to: folder.appendingPathComponent("\(prefix)-b.png"))
    write(OptionCPanel(), to: folder.appendingPathComponent("\(prefix)-c.png"))
}
