import PhotonzCore
import SwiftUI

/// **Key** and **Masked by**: the two compositing rules that sit directly under
/// Opacity and Blending (Next, `next-layers-combine`).
///
/// Four rows, one question between them. Opacity says how much of what is below
/// shows through; Blending says how the two are mixed once it does; Key says
/// which of this layer's own pixels are there at all; Masked by says what shape
/// it is allowed to be. Anywhere else in the panel they would read as effects
/// somebody added, which is exactly what they are not — nothing is added to the
/// layer, the layer is laid down differently.
///
/// The model and the maths are `PhotonzCore/LayerCompositing.swift`.
struct KeyRows: View {
    @Environment(EditorState.self) private var editorState

    /// Said out loud when Key it found no wall, so a button that did nothing
    /// never looks like a button that is broken.
    @State private var noWall = false

    private var selection: LayerStyleSelection { editorState.keyableSelection }

    var body: some View {
        if !selection.isEmpty { rows }
    }

    private var key: StyleReading<ChromaKey?> { selection.reading { $0.key } }

    private var isOn: Bool {
        guard let value = key.value, let key = value else { return false }
        return key.isOn
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Key").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 6)
                if key.value ?? nil == nil {
                    // Nothing keyed yet, so the whole row is one button. The
                    // colour is read off the picture rather than asked for,
                    // which is the difference between keying a green screen in
                    // one click and keying it with an eyedropper and a guess.
                    Button("Key it") { keyIt() }
                        .controlSize(.small)
                        .playtestControl("Key it", detail: "Key")
                        .panelHelp("Make the colour behind the subject transparent. "
                                   + "The colour is read off the edges of the picture.")
                } else {
                    Toggle("", isOn: Binding(get: { isOn },
                                             set: { editorState.setKeyIsOn($0, ids: selection.layerIDs) }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .playtestControl("Key", detail: isOn ? "on" : "off")
                }
            }
            if let current = key.value ?? nil {
                HStack(spacing: 8) {
                    ColorWellButton(hex: current.colorHex, name: "Key", wellKey: "key") { hex in
                        editorState.setLayerStyle(ids: selection.layerIDs) { $0.key?.colorHex = hex }
                    }
                    Text(current.colorHex)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .panelReadout(current.colorHex)
                    Spacer(minLength: 0)
                    Button("Key it again") { keyIt() }
                        .controlSize(.small)
                        .buttonStyle(.link)
                        .font(.caption2)
                        .playtestControl("Key it again", detail: "Key")
                }
                .opacity(isOn ? 1 : 0.45)
                slider("Tolerance", help: "How much of the colour goes",
                       read: { $0.key?.tolerance ?? 0 }) { $0.key?.tolerance = $1 }
                slider("Softness", help: "How gently the edge fades",
                       read: { $0.key?.softness ?? 0 }) { $0.key?.softness = $1 }
                slider("Spill", help: "Pulls the colour back out of what is left, which takes a green rim off a shoulder",
                       read: { $0.key?.spill ?? 0 }) { $0.key?.spill = $1 }
            }
            if noWall {
                Text("Nothing to key here. Scrub to the backdrop.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .panelReadout("nothing to key")
                    .panelHelp("The edges of this picture are not one colour. Scrub to a moment where the backdrop shows and key it again.")
            }
        }
        .playtestField("Key")
        .panelStartProbe(.row, owner: "Key")
    }

    private func keyIt() {
        noWall = !editorState.keyOutTheWall(ids: selection.layerIDs)
    }

    private func slider(_ label: String, help: String,
                        read: @escaping (LayerStyle) -> Double,
                        apply: @escaping (inout LayerStyle, Double) -> Void) -> some View {
        LayerStyleSlider(layerIDs: selection.layerIDs, label: label,
                         reading: selection.reading(read), range: 0...1,
                         typing: .percent, apply: apply)
            .panelHelp(help)
            .opacity(isOn ? 1 : 0.45)
            .disabled(!isOn)
    }
}

/// **Masked by**: this layer cut to the shape, or the brightness, of the layer
/// directly under it.
///
/// A button that opens a list, not a pop-up menu, for the reason the Blending
/// row gives: a macOS pop-up is an `NSMenu`, and a menu tells nobody what its
/// words mean. Three choices, each with a plain sentence beside it, and the
/// sentence names the layer it would borrow from rather than saying "the layer
/// below" — which is a thing you would then have to go and find.
struct MaskedByRow: View {
    @Environment(EditorState.self) private var editorState

    @State private var isOpen = false

    private var selection: LayerStyleSelection { editorState.maskableSelection }

    var body: some View {
        if !selection.isEmpty { rows }
    }

    private var reading: StyleReading<LayerMatte?> { selection.reading { $0.matte } }

    private var words: String {
        if reading.isMixed { return LayerStyleSelection.mixedText }
        return (reading.value ?? nil)?.title ?? MaskedByRow.nothing
    }

    static let nothing = "Nothing"

    private var rows: some View {
        let matte = reading.value ?? nil
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Masked by").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            Button {
                isOpen = true
            } label: {
                HStack(spacing: 4) {
                    Text(words)
                        .foregroundStyle(MixedLook.style(reading.isMixed, otherwise: .primary))
                        .panelReadout(words)
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .controlSize(.small)
            .playtestControl("Masked by", detail: words)
            .panelHelp("Cut this layer to the shape, or the brightness, of the layer directly "
                       + "under it in the layers list. That layer stops drawing and becomes "
                       + "the shape instead.")
            .popover(isPresented: $isOpen, arrowEdge: .bottom) { list }
            if let matte {
                Text(sentence(for: matte))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .playtestField("Masked by")
        .panelStartProbe(.row, owner: "Masked by")
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            choice(nil, title: MaskedByRow.nothing,
                   explanation: "Draws all of this layer, and the layer under it too.")
            ForEach(LayerMatte.allCases, id: \.self) { kind in
                choice(kind, title: kind.title, explanation: sentence(for: kind))
            }
        }
        .padding(6)
        .frame(width: 300)
    }

    private func choice(_ kind: LayerMatte?, title: String, explanation: String) -> some View {
        let current = reading.value ?? nil
        return Button {
            editorState.setMatte(kind, ids: selection.layerIDs)
            isOpen = false
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.semibold))
                    .opacity(!reading.isMixed && current == kind ? 1 : 0)
                    .frame(width: 11, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.callout)
                    Text(explanation)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .playtestControl(title, detail: "Masked by")
    }

    /// The explanation with the layer's own name in it where there is one to
    /// use: "Shows this layer only where Matte shape has something drawn" beats
    /// "the layer below", because the layer below is a thing you then have to
    /// go and find.
    private func sentence(for matte: LayerMatte) -> String {
        guard let name = editorState.matteSourceName else { return matte.explanation }
        switch matte {
        case .shape:
            return "Shows this layer only where \(name) is drawn."
        case .brightness:
            return "Shows this layer where \(name) is light."
        }
    }
}
