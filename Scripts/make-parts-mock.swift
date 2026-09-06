// Draws the four panel strips in the "a layer is made of parts" decision brief.
// Run: swift Scripts/make-parts-mock.swift <output folder>
//
// These are MOCKS, not the app: nothing here is shipped code. They exist so the
// decision card can show the same rectangle's panel drawn the way it is today
// and the three ways it could be, at the same size, side by side.
import AppKit
import SwiftUI

// MARK: - The panel's colours, matched to a real probe capture of the dock.

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

let panelWidth: CGFloat = 300

// MARK: - Pieces

struct SectionHeader: View {
    let title: String
    var control: AnyView? = nil
    var dimmed: Bool = false
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(sectionRule).frame(height: 1)
            HStack(spacing: 6) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(dimmed ? dimLabel : titleColor)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(dimmed ? dimLabel : titleColor)
                if let control { control }
                Spacer(minLength: 0)
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10, weight: .regular))
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
        RoundedRectangle(cornerRadius: 4).fill(color)
            .frame(width: 22, height: 20)
    }
}

struct StylesMenu: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "swatchpalette")
                .font(.system(size: 11))
            Image(systemName: "chevron.down")
                .font(.system(size: 7, weight: .bold))
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
            .overlay {
                if on {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(.white)
                }
            }
            .overlay {
                if !on {
                    RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.22), lineWidth: 1)
                }
            }
    }
}

struct SwitchControl: View {
    var on: Bool
    var body: some View {
        Capsule().fill(on ? accent : Color.white.opacity(0.22))
            .frame(width: 26, height: 15)
            .overlay(alignment: on ? .trailing : .leading) {
                Circle().fill(.white).frame(width: 13, height: 13).padding(1)
            }
    }
}

/// A colour row the way the panel draws one today: label, switch, swatch, menu.
struct ColorRow: View {
    var label: String
    var on: Bool = true
    var hasSwitch: Bool = true
    var color: Color = shapeRed
    var showsColor: Bool = true
    var chevron: String? = nil
    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(on ? labelColor : dimLabel)
                .frame(width: 62, alignment: .leading)
            Group {
                if hasSwitch { Checkbox(on: on) } else { Color.clear }
            }
            .frame(width: 16, height: 20, alignment: .leading)
            if showsColor && on {
                Swatch(color: color)
                StylesMenu()
            } else {
                Color.clear.frame(width: 22, height: 20)
            }
            Spacer(minLength: 0)
            if let chevron {
                Image(systemName: chevron)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(on ? Color.white.opacity(0.45) : dimLabel)
            }
        }
        .frame(height: 22)
        .padding(.horizontal, 14)
    }
}

/// A slider row: label on the left, value on the right, track underneath.
struct SliderRow: View {
    var label: String
    var value: String
    var fraction: Double
    var indent: CGFloat = 0
    var dimmed: Bool = false
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label).font(.system(size: 11)).foregroundStyle(dimmed ? dimLabel : labelColor)
                Spacer()
                Text(value).font(.system(size: 11)).foregroundStyle(dimmed ? dimLabel : valueColor)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(trackColor).frame(height: 4)
                        .frame(maxHeight: .infinity, alignment: .center)
                    Circle().fill(dimmed ? Color.white.opacity(0.35) : knobColor)
                        .frame(width: 13, height: 13)
                        .offset(x: max(0, (proxy.size.width - 13) * fraction))
                }
            }
            .frame(height: 13)
        }
        .padding(.leading, 14 + indent)
        .padding(.trailing, 14)
        .padding(.vertical, 3)
    }
}

struct SectionBody<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .padding(.vertical, 8)
    }
}

/// One part written as a heading row with its own settings under it.
struct PartRow: View {
    var name: String
    var on: Bool
    var color: Color = shapeRed
    var chevron: String? = nil
    @ViewBuilder var settings: () -> AnyView
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ColorRow(label: name, on: on, hasSwitch: true, color: color, chevron: chevron)
            if on { settings() }
        }
    }
}

func none() -> AnyView { AnyView(EmptyView()) }

// MARK: - The four panels

struct PanelFrame<Content: View>: View {
    let caption: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(caption)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.55))
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 10)
            content
            Rectangle().fill(sectionRule).frame(height: 1)
        }
        .frame(width: panelWidth, alignment: .leading)
        .background(panelBG)
    }
}

/// What the panel shows today, traced from a probe capture on 2026-09-06.
struct BeforePanel: View {
    var body: some View {
        PanelFrame(caption: "Today") {
            SectionHeader(title: "Color")
            SectionBody {
                ColorRow(label: "Fill", on: true)
                ColorRow(label: "Outline", on: true, hasSwitch: false)
            }
            SectionHeader(title: "Effects")
            SectionBody {
                SliderRow(label: "Opacity", value: "100%", fraction: 1)
                SliderRow(label: "Blur", value: "0 pt", fraction: 0)
                SliderRow(label: "Corner Radius", value: "0 pt", fraction: 0)
            }
            SectionHeader(title: "Rectangle")
            SectionBody {
                SliderRow(label: "Thickness", value: "4 pt", fraction: 0.1)
            }
            SectionHeader(title: "Shadow")
            SectionBody {
                HStack(spacing: 8) {
                    Text("Enable Shadow").font(.system(size: 11)).foregroundStyle(labelColor)
                    SwitchControl(on: false)
                    Spacer()
                }
                .padding(.horizontal, 14)
            }
        }
    }
}

/// A: one list, a part's settings unfold under it when you click it.
struct OptionAPanel: View {
    var body: some View {
        PanelFrame(caption: "A — settings unfold") {
            SectionHeader(title: "Appearance")
            SectionBody {
                ColorRow(label: "Fill", on: true, chevron: "chevron.right")
                VStack(alignment: .leading, spacing: 6) {
                    ColorRow(label: "Outline", on: true, chevron: "chevron.down")
                    SliderRow(label: "Width", value: "4 pt", fraction: 0.1, indent: 18)
                }
                ColorRow(label: "Shadow", on: true, color: .black, chevron: "chevron.right")
            }
            SectionHeader(title: "Rectangle")
            SectionBody {
                SliderRow(label: "Corner Radius", value: "0 pt", fraction: 0)
            }
            SectionHeader(title: "Effects")
            SectionBody {
                SliderRow(label: "Opacity", value: "100%", fraction: 1)
                SliderRow(label: "Blur", value: "0 pt", fraction: 0)
            }
        }
    }
}

/// B: one list, a part's settings are always there while it is on.
struct OptionBPanel: View {
    var body: some View {
        PanelFrame(caption: "B — settings always showing") {
            SectionHeader(title: "Appearance")
            SectionBody {
                ColorRow(label: "Fill", on: true)
                VStack(alignment: .leading, spacing: 6) {
                    ColorRow(label: "Outline", on: true)
                    SliderRow(label: "Width", value: "4 pt", fraction: 0.1, indent: 18)
                }
                VStack(alignment: .leading, spacing: 6) {
                    ColorRow(label: "Shadow", on: true, color: .black)
                    SliderRow(label: "Blur", value: "12 pt", fraction: 0.3, indent: 18)
                    SliderRow(label: "Size", value: "0 pt", fraction: 0, indent: 18)
                    SliderRow(label: "Distance", value: "6 pt", fraction: 0.15, indent: 18)
                    SliderRow(label: "Direction", value: "135°", fraction: 0.37, indent: 18)
                    SliderRow(label: "Opacity", value: "35%", fraction: 0.35, indent: 18)
                }
            }
            SectionHeader(title: "Rectangle")
            SectionBody {
                SliderRow(label: "Corner Radius", value: "0 pt", fraction: 0)
            }
            SectionHeader(title: "Effects")
            SectionBody {
                SliderRow(label: "Opacity", value: "100%", fraction: 1)
                SliderRow(label: "Blur", value: "0 pt", fraction: 0)
            }
        }
    }
}

/// C: every part is a section of its own, with its switch in the heading.
struct OptionCPanel: View {
    var body: some View {
        PanelFrame(caption: "C — a section per part") {
            SectionHeader(title: "Fill", control: AnyView(SwitchControl(on: true).padding(.leading, 4)))
            SectionBody {
                ColorRow(label: "Color", on: true, hasSwitch: false)
            }
            SectionHeader(title: "Outline", control: AnyView(SwitchControl(on: true).padding(.leading, 4)))
            SectionBody {
                ColorRow(label: "Color", on: true, hasSwitch: false)
                SliderRow(label: "Width", value: "4 pt", fraction: 0.1)
            }
            SectionHeader(title: "Shadow", control: AnyView(SwitchControl(on: true).padding(.leading, 4)))
            SectionBody {
                ColorRow(label: "Color", on: true, hasSwitch: false, color: .black)
                SliderRow(label: "Blur", value: "12 pt", fraction: 0.3)
                SliderRow(label: "Size", value: "0 pt", fraction: 0)
                SliderRow(label: "Distance", value: "6 pt", fraction: 0.15)
                SliderRow(label: "Direction", value: "135°", fraction: 0.37)
                SliderRow(label: "Opacity", value: "35%", fraction: 0.35)
            }
            SectionHeader(title: "Rectangle")
            SectionBody {
                SliderRow(label: "Corner Radius", value: "0 pt", fraction: 0)
            }
            SectionHeader(title: "Effects")
            SectionBody {
                SliderRow(label: "Opacity", value: "100%", fraction: 1)
                SliderRow(label: "Blur", value: "0 pt", fraction: 0)
            }
        }
    }
}

/// The outline switched off, in the model every option shares: the switch and
/// the name stay, the colour and the width go.
struct OffPanel: View {
    var body: some View {
        PanelFrame(caption: "Outline switched off") {
            SectionHeader(title: "Appearance")
            SectionBody {
                ColorRow(label: "Fill", on: true)
                ColorRow(label: "Outline", on: false)
                ColorRow(label: "Shadow", on: false)
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
let prefix = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "parts"

MainActor.assumeIsolated {
    write(BeforePanel(), to: folder.appendingPathComponent("\(prefix)-before.png"))
    write(OptionAPanel(), to: folder.appendingPathComponent("\(prefix)-a.png"))
    write(OptionBPanel(), to: folder.appendingPathComponent("\(prefix)-b.png"))
    write(OptionCPanel(), to: folder.appendingPathComponent("\(prefix)-c.png"))
    write(OffPanel(), to: folder.appendingPathComponent("\(prefix)-off.png"))
}
