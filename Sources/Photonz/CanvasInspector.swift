// The settings for the canvas itself and for a collage: size, background and how the pieces are laid out.

import PhotonzCore
import SwiftUI

// MARK: - Canvas inspector (the Canvas pseudo-layer)

struct CanvasInspector: View {
    @Environment(EditorState.self) private var editorState
    @State private var width: Double = 0
    @State private var height: Double = 0

    private var canvasSize: CGSize { editorState.document?.canvasSize ?? .zero }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                dimensionField("W", $width)
                dimensionField("H", $height)
                Spacer()
                Button("Canvas Size…") { editorState.isCanvasSizeDialogPresented = true }
                    .controlSize(.small)
                    .panelHelp("Numeric resize with a content-anchor picker")
            }
            Text("Drag the canvas edges to add or trim space; content stays put on the side you didn't move. Fields grow to the right/bottom.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            newSpaceRow
            if Experiments.shared.canvasGridEnabled {
                Divider().padding(.vertical, 2)
                gridSection
            }
        }
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.vertical, 8)
        .onAppear { syncFields() }
        .onChange(of: canvasSize) { syncFields() }
    }

    /// Which colour the space a canvas grows into arrives in.
    ///
    /// It is the background fill, the same colour ⌫ clears a locked background
    /// to, and its only other home on screen is the paint bucket's swatches.
    /// Adding space is the one place that colour lands on the picture without
    /// anyone typing a shortcut, so it belongs beside the sentence that
    /// explains how to add it: what happens next is stated where the doing is,
    /// and it can be changed there rather than by picking up a tool you did not
    /// want. The canvas paints the same colour into the proposed space while an
    /// edge is being dragged, so this row and the picture agree.
    @ViewBuilder private var newSpaceRow: some View {
        HStack(spacing: 8) {
            Text("New space").font(.caption).foregroundStyle(.secondary)
            ColorWellButton(hex: editorState.backgroundFillHex, name: "Background fill",
                            wellKey: "canvas.background") { editorState.backgroundFillHex = $0 }
            Spacer()
        }
        .padding(.top, 2)
    }

    // MARK: The grid you build against (Next, `next-canvas-grid`)

    /// The grid's numbers, on the Canvas, because that is what the grid
    /// belongs to. They are ALSO on the chip in the tool bar and on View ▸
    /// Grid Settings, because "click the Canvas row first" is not how anyone
    /// looks for them — see `CanvasGridControls`, which is the one copy of
    /// these controls that all three places draw.
    ///
    /// Nothing here is saved in the document: it is a view preference the app
    /// remembers between launches, and every window shows the same one.
    @ViewBuilder private var gridSection: some View {
        // The panel column is narrower than the popover, so the labels get
        // less of it and the controls keep their room.
        CanvasGridControls(labelWidth: 78)
    }

    private func syncFields() {
        width = Double(canvasSize.width)
        height = Double(canvasSize.height)
    }

    private func dimensionField(_ label: String, _ value: Binding<Double>) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, value: value,
                      format: .number.precision(.fractionLength(0)).grouping(.never))
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .multilineTextAlignment(.trailing)
                .frame(width: 58)
                .onSubmit { applyDimensions() }
                // The same two finishing keys the layer's own numbers answer:
                // a canvas size typed and finished with lets go of the keyboard
                // so the next letter picks a tool.
                .numberFieldKeys(
                    commit: { applyDimensions() },
                    revert: { syncFields() },
                    step: { direction, coarse in
                        let stepped = LayerGeometry.stepped(value.wrappedValue,
                                                            direction: direction, coarse: coarse)
                        value.wrappedValue = max(1, Double(stepped))
                        applyDimensions()
                    })
        }
    }

    private func applyDimensions() {
        let size = CGSize(width: max(1, width.rounded()), height: max(1, height.rounded()))
        guard size != canvasSize else { return }
        editorState.setCanvasSize(to: size, anchor: .topLeft)
    }
}

// MARK: - Collage inspector (16.9)

struct CollageInspector: View {
    @Environment(EditorState.self) private var editorState
    let layer: Layer

    private var content: CollageContent? {
        editorState.document?.layer(id: layer.id)?.collage
    }

    var body: some View {
        if let c = content {
            VStack(alignment: .leading, spacing: 8) {
                field("Layout") {
                    Picker("Layout", selection: Binding(
                        get: { c.template },
                        set: { value in editorState.updateCollage(layerID: layer.id) { $0.template = value } })) {
                        ForEach(CollageTemplate.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.segmented).controlSize(.small)
                }
                field("Photos") {
                    Stepper("\(c.slots.count) slots", value: Binding(
                        get: { c.slots.count },
                        set: { value in editorState.updateCollage(layerID: layer.id) { $0.setSlotCount(value) } }),
                        in: 1...12)
                        .font(.caption).controlSize(.small)
                }
                field("Spacing") {
                    Stepper(DocumentUnit.text(CGFloat(c.gutter)), value: Binding(
                        get: { Int(c.gutter) },
                        set: { value in editorState.updateCollage(layerID: layer.id) { $0.gutter = CGFloat(value) } }),
                        in: 0...200, step: 4)
                        .font(.caption).controlSize(.small)
                }
                HStack {
                    Toggle("Backdrop", isOn: Binding(
                        get: { c.backdropColorHex != nil },
                        set: { on in
                            editorState.updateCollage(layerID: layer.id) {
                                $0.backdropColorHex = on ? "#FFFFFF" : nil
                            }
                        }))
                        .font(.caption).controlSize(.small)
                    Spacer()
                    if let hex = c.backdropColorHex {
                        ColorWellButton(hex: hex, name: "Backdrop") { newHex in
                            editorState.updateCollage(layerID: layer.id) { $0.backdropColorHex = newHex }
                            editorState.recordRecentColor(hex: newHex)
                        }
                    }
                }
                Text("Drop photos from the history or Finder into a cell; drag a photo layer onto a cell to absorb it; drag between cells to swap.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder private func field<Content: View>(_ label: String,
                                                   @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            content()
        }
        .playtestField(label)
    }
}
