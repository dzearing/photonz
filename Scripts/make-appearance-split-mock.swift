// Draws the panel strips in the "what belongs in Appearance and what belongs in
// Effects" decision brief.
// Run: swift Scripts/make-appearance-split-mock.swift <output folder> [prefix]
//
// These are MOCKS, not the app: nothing here is shipped code. Every strip shows
// the SAME rectangle — a red fill, an outline, a border inside the edge, a
// border outside it, and a drop shadow — so the models can be compared on one
// shape. The colours
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


// MARK: - Pieces this brief adds

/// A settings block that says out loud whose settings it is. The line and the
/// step to the right are the whole point: a shadow's Blur can never again read
/// as the layer's own.
struct OwnedSettings<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) { content }
            .padding(.leading, 6)
            .overlay(alignment: .leading) {
                Rectangle().fill(Color.white.opacity(0.16)).frame(width: 2)
            }
            .padding(.leading, 14)
    }
}

/// The header of a section that can be added to.
struct AddableHeader: View {
    let title: String
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(sectionRule).frame(height: 1)
            HStack(spacing: 6) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(titleColor)
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(titleColor)
                Spacer(minLength: 0)
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.75))
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.30))
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
        }
    }
}

struct EmptyEffects: View {
    var body: some View {
        Text("Nothing added yet. Press + for a border, a shadow, a glow or a blur.")
            .font(.system(size: 10))
            .foregroundStyle(Color.white.opacity(0.38))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14).padding(.vertical, 8)
    }
}

// MARK: - The panels

/// What the app draws today: the thing that was reported.
struct TodaySplitPanel: View {
    var body: some View {
        PanelFrame(caption: "Today", note: "Appearance carries a shadow's Blur, Size and Opacity with nothing to say they are the shadow's. Effects underneath carries the layer's own Opacity and Blur. Two Blurs, two Opacities, no owner. And there is nowhere to put a second border.") {
            SectionHeader(title: "Appearance")
            PartsList {
                EffectRow(label: "Fill")
                VStack(alignment: .leading, spacing: 6) {
                    EffectRow(label: "Outline")
                    SliderRow(label: "Width", value: "4 pt", fraction: 0.1)
                }
                VStack(alignment: .leading, spacing: 6) {
                    EffectRow(label: "Shadow", color: .black) { EntryControls() }
                    PopupRow(label: "Kind", value: "Drop")
                    ShadowSettings(blur: "12 pt", blurF: 0.3, size: "0 pt", sizeF: 0,
                                   distance: "4 pt", distanceF: 0.1,
                                   direction: "90°", directionF: 0.25,
                                   opacity: "40%", opacityF: 0.4)
                }
            }
            SectionHeader(title: "Effects")
            VStack(alignment: .leading, spacing: 6) {
                SliderRow(label: "Opacity", value: "100%", fraction: 1)
                SliderRow(label: "Blur", value: "0 pt", fraction: 0)
                SliderRow(label: "Corner Radius", value: "0 pt", fraction: 0)
            }
            .padding(.vertical, 8)
        }
    }
}

/// A: two panels, split on one rule.
struct SplitPanel: View {
    var body: some View {
        PanelFrame(caption: "A. Appearance is what it IS, Effects is what you ADD", note: "Appearance holds the things every shape simply has, in the same order every time. Effects starts empty and grows: two borders with different offsets are an inner and an outer one. A part's settings sit behind its own line.") {
            SectionHeader(title: "Appearance")
            PartsList {
                SliderRow(label: "Opacity", value: "100%", fraction: 1)
                EffectRow(label: "Fill")
                VStack(alignment: .leading, spacing: 6) {
                    EffectRow(label: "Outline")
                    OwnedSettings { SliderRow(label: "Width", value: "4 pt", fraction: 0.1) }
                }
                SliderRow(label: "Corner Radius", value: "8 pt", fraction: 0.1)
            }
            AddableHeader(title: "Effects")
            PartsList {
                VStack(alignment: .leading, spacing: 6) {
                    EffectRow(label: "Border", color: inkBlue) { EntryControls() }
                    OwnedSettings {
                        SliderRow(label: "Width", value: "2 pt", fraction: 0.05)
                        PopupRow(label: "Offset", value: "Inside")
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    EffectRow(label: "Border", color: .white) { EntryControls() }
                    OwnedSettings {
                        SliderRow(label: "Width", value: "6 pt", fraction: 0.15)
                        PopupRow(label: "Offset", value: "Outside")
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    EffectRow(label: "Shadow", color: .black) { EntryControls() }
                    OwnedSettings {
                        PopupRow(label: "Kind", value: "Drop")
                        ShadowSettings(blur: "12 pt", blurF: 0.3, size: "0 pt", sizeF: 0,
                                       distance: "4 pt", distanceF: 0.1,
                                       direction: "90°", directionF: 0.25,
                                       opacity: "40%", opacityF: 0.4)
                    }
                }
            }
        }
    }
}

/// B: one panel, no line to learn.
struct OneListPanel: View {
    var body: some View {
        PanelFrame(caption: "B. One panel, no line to learn", note: "No second section. Everything the layer wears is in one list: what it always has on top, what you added under it, with the same plus. There is no rule to remember about which panel a thing lives in, because there is only one.") {
            AddableHeader(title: "Appearance")
            PartsList {
                SliderRow(label: "Opacity", value: "100%", fraction: 1)
                EffectRow(label: "Fill")
                VStack(alignment: .leading, spacing: 6) {
                    EffectRow(label: "Outline")
                    OwnedSettings { SliderRow(label: "Width", value: "4 pt", fraction: 0.1) }
                }
                SliderRow(label: "Corner Radius", value: "8 pt", fraction: 0.1)
                VStack(alignment: .leading, spacing: 6) {
                    EffectRow(label: "Border", color: inkBlue) { EntryControls() }
                    OwnedSettings {
                        SliderRow(label: "Width", value: "2 pt", fraction: 0.05)
                        PopupRow(label: "Offset", value: "Inside")
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    EffectRow(label: "Border", color: .white) { EntryControls() }
                    OwnedSettings {
                        SliderRow(label: "Width", value: "6 pt", fraction: 0.15)
                        PopupRow(label: "Offset", value: "Outside")
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    EffectRow(label: "Shadow", color: .black) { EntryControls() }
                    OwnedSettings {
                        PopupRow(label: "Kind", value: "Drop")
                        ShadowSettings(blur: "12 pt", blurF: 0.3, size: "0 pt", sizeF: 0,
                                       distance: "4 pt", distanceF: 0.1,
                                       direction: "90°", directionF: 0.25,
                                       opacity: "40%", opacityF: 0.4)
                    }
                }
            }
        }
    }
}

/// C: leave the two panels where they are, and only give a part's settings an
/// owner.
struct OwnerOnlyPanel: View {
    var body: some View {
        PanelFrame(caption: "C. Change nothing but the ownership", note: "The two panels stay exactly as they are. The only change is the line down the left of a part's settings, so a shadow's Blur can never be mistaken for the layer's. No second border, and Blur stays in Effects.") {
            SectionHeader(title: "Appearance")
            PartsList {
                EffectRow(label: "Fill")
                VStack(alignment: .leading, spacing: 6) {
                    EffectRow(label: "Outline")
                    OwnedSettings { SliderRow(label: "Width", value: "4 pt", fraction: 0.1) }
                }
                VStack(alignment: .leading, spacing: 6) {
                    EffectRow(label: "Shadow", color: .black) { EntryControls() }
                    OwnedSettings {
                        PopupRow(label: "Kind", value: "Drop")
                        ShadowSettings(blur: "12 pt", blurF: 0.3, size: "0 pt", sizeF: 0,
                                       distance: "4 pt", distanceF: 0.1,
                                       direction: "90°", directionF: 0.25,
                                       opacity: "40%", opacityF: 0.4)
                    }
                }
            }
            SectionHeader(title: "Effects")
            VStack(alignment: .leading, spacing: 6) {
                SliderRow(label: "Opacity", value: "100%", fraction: 1)
                SliderRow(label: "Blur", value: "0 pt", fraction: 0)
                SliderRow(label: "Corner Radius", value: "0 pt", fraction: 0)
            }
            .padding(.vertical, 8)
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
let prefix = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "split"

MainActor.assumeIsolated {
    write(TodaySplitPanel(), to: folder.appendingPathComponent("\(prefix)-today.png"))
    write(SplitPanel(), to: folder.appendingPathComponent("\(prefix)-a.png"))
    write(OneListPanel(), to: folder.appendingPathComponent("\(prefix)-b.png"))
    write(OwnerOnlyPanel(), to: folder.appendingPathComponent("\(prefix)-c.png"))
}
