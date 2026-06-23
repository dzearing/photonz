import AppKit
import PhotonzCore
import SwiftUI

/// Bespoke, on-brand HSB color picker (13.2): hue/saturation/brightness sliders,
/// a screen eyedropper (`NSColorSampler`), and a hex field. Commits a canonical
/// `#RRGGBB` through `onCommit` only on a deliberate action (slider release, hex
/// submit, eyedropper sample) — never on every drag tick — so the shared recents
/// list isn't spammed mid-gesture.
struct ColorPickerPopover: View {
    /// The color the popover opens on, as the document-model hex.
    let initialHex: String
    /// Called with a canonical `#RRGGBB` when the user commits a color.
    let onCommit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var hue: Double = 0
    @State private var saturation: Double = 1
    @State private var brightness: Double = 1
    @State private var hexField: String = ""
    /// True while the screen sampler is open, to disable the button.
    @State private var isSampling = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            preview
            slider("Hue", value: $hue, range: 0...1,
                   track: LinearGradient(colors: huePalette, startPoint: .leading, endPoint: .trailing))
            slider("Saturation", value: $saturation, range: 0...1,
                   track: LinearGradient(colors: [Color(white: 0.8),
                                                  Color(hue: hue, saturation: 1, brightness: brightness)],
                                         startPoint: .leading, endPoint: .trailing))
            slider("Brightness", value: $brightness, range: 0...1,
                   track: LinearGradient(colors: [.black,
                                                  Color(hue: hue, saturation: saturation, brightness: 1)],
                                         startPoint: .leading, endPoint: .trailing))
            HStack(spacing: 8) {
                hexEntry
                eyedropperButton
            }
        }
        .padding(16)
        .frame(width: 240)
        .onAppear { seed(from: initialHex) }
    }

    // MARK: - Pieces

    private var currentColor: Color {
        // Derive from the same HSB→sRGB math the commit uses, so the preview
        // matches the exact hex we record.
        Color(.sRGB, red: redComponent, green: greenComponent, blue: blueComponent)
    }

    private var currentHex: String {
        RGBA(r: redComponent, g: greenComponent, b: blueComponent).hexString
    }

    private var preview: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(currentColor)
            .frame(height: 36)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.2), lineWidth: 1))
    }

    private func slider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>,
                        track: LinearGradient) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            ZStack {
                Capsule().fill(track).frame(height: 6)
                Slider(value: value, in: range) { editing in
                    if !editing { commit() }
                }
                .controlSize(.small)
                .opacity(0.9)
            }
        }
    }

    private var hexEntry: some View {
        TextField("#RRGGBB", text: $hexField)
            .textFieldStyle(.roundedBorder)
            .font(.system(.callout, design: .monospaced))
            .frame(width: 100)
            .onSubmit {
                if RGBA(hex: hexField) != nil {
                    seed(from: hexField)
                    commit()
                } else {
                    // Reject malformed input by snapping back to the current color.
                    hexField = currentHex
                }
            }
    }

    private var eyedropperButton: some View {
        Button {
            sampleFromScreen()
        } label: {
            Image(systemName: "eyedropper")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 22)
        }
        .buttonStyle(.bordered)
        .disabled(isSampling)
        .help("Pick a color from anywhere on screen")
    }

    // MARK: - HSB → RGB

    private var redComponent: Double { rgb.0 }
    private var greenComponent: Double { rgb.1 }
    private var blueComponent: Double { rgb.2 }

    /// Standard HSB → sRGB conversion in 0...1.
    private var rgb: (Double, Double, Double) {
        let h = (hue * 6).truncatingRemainder(dividingBy: 6)
        let c = brightness * saturation
        let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let m = brightness - c
        let (r1, g1, b1): (Double, Double, Double)
        switch Int(h) {
        case 0: (r1, g1, b1) = (c, x, 0)
        case 1: (r1, g1, b1) = (x, c, 0)
        case 2: (r1, g1, b1) = (0, c, x)
        case 3: (r1, g1, b1) = (0, x, c)
        case 4: (r1, g1, b1) = (x, 0, c)
        default: (r1, g1, b1) = (c, 0, x)
        }
        return (r1 + m, g1 + m, b1 + m)
    }

    private var huePalette: [Color] {
        stride(from: 0.0, through: 1.0, by: 1.0 / 6).map { Color(hue: $0, saturation: 1, brightness: 1) }
    }

    // MARK: - State plumbing

    private func commit() {
        let hex = currentHex
        hexField = hex
        onCommit(hex)
    }

    /// Seeds the HSB sliders + hex field from a hex string (via NSColor so the
    /// HSB decomposition matches what the sliders reproduce).
    private func seed(from hex: String) {
        guard let rgba = RGBA(hex: hex) else { return }
        let nsColor = NSColor(srgbRed: CGFloat(rgba.r), green: CGFloat(rgba.g),
                              blue: CGFloat(rgba.b), alpha: 1)
        if let hsb = nsColor.usingColorSpace(.deviceRGB) {
            hue = Double(hsb.hueComponent)
            saturation = Double(hsb.saturationComponent)
            brightness = Double(hsb.brightnessComponent)
        }
        hexField = rgba.hexString
    }

    /// Opens the system screen sampler (eyedropper). Needs Screen-Recording
    /// permission; if denied or cancelled the callback simply gets nil and we
    /// leave the current color untouched.
    private func sampleFromScreen() {
        isSampling = true
        // NSColorSampler invokes its handler on the main thread once the user
        // clicks (or cancels). The closure is typed `Sendable`, so hop back onto
        // the main actor explicitly to touch this view's @State.
        NSColorSampler().show { picked in
            let hex = picked?.usingColorSpace(.sRGB).map {
                RGBA(r: Double($0.redComponent), g: Double($0.greenComponent),
                     b: Double($0.blueComponent)).hexString
            }
            Task { @MainActor in
                isSampling = false
                guard let hex else { return }
                seed(from: hex)
                commit()
            }
        }
    }
}
