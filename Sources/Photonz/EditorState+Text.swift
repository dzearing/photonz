import AppKit
import CoreGraphics
import Observation
import PhotonzCore
import PhotonzRender
import SwiftUI
import UniformTypeIdentifiers

// Text layers: styling them, aligning them, and the inline edit that puts a
// caret on the canvas.
//
// Split out of EditorState.swift; nothing here changed on the way over.
extension EditorState {
    // MARK: - Text styling & inline editing

    /// Styled (empty) content for the current text style; the canvas's inline
    /// editor mirrors it so what you type matches what commit rasterizes.
    var activeTextContent: TextContent {
        var content = textStyles.content()
        // NEW text types in the current foreground color; re-edits keep the
        // layer's own color (the session seeds the styles).
        if editingTextLayerID == nil { content.colorHex = foregroundFillHex }
        return content
    }

    /// The selected text layer when the select tool is active — the properties
    /// panel edits its font face/size/weight/color (13.1) instead of only the
    /// new-text defaults. Mirrors `selectedAnnotationLayer`.
    var selectedTextLayer: Layer? {
        guard activeTool == .select, let id = selectedLayerID,
              let layer = document?.layer(id: id),
              case .text = layer.content else { return nil }
        return layer
    }

    /// The picked text layer, as the list `setTextStyle` takes. Empty when the
    /// pick is not text, which still remembers the choice as the new-text
    /// default without touching the document.
    private var restyleTargets: [UUID] { selectedTextLayer.map { [$0.id] } ?? [] }

    /// The font popover and the docked inspector restyle through the ONE
    /// path (`setTextStyle`), so a label re-measures the same way whichever
    /// control you reach for. It also remembers the choice as the new-text
    /// default.
    func setTextFont(_ name: String) {
        setTextStyle(ids: restyleTargets, fontName: name)
    }

    func setTextFontSize(_ size: CGFloat) {
        setTextStyle(ids: restyleTargets, fontSize: size)
    }

    func setTextWeight(_ weight: TextWeight) {
        setTextStyle(ids: restyleTargets, weight: weight)
    }

    func setTextColor(_ hex: String) {
        setTextStyle(ids: restyleTargets, colorHex: hex)
        foregroundFillHex = hex // text color picks update the current color too
    }

    // MARK: - Docked text inspector (targets a specific layer, independent of
    // the active tool — so editing a selected text element's font from the
    // docked panel always reaches the document and updates the new-text default).

    /// Restyles `layerID` if it's a text layer, re-measuring its frame. One undo
    /// step. Also updates the new-text default so the next block inherits it.
    func setTextStyle(layerID: UUID, fontName: String? = nil, fontSize: CGFloat? = nil,
                      weight: TextWeight? = nil, colorHex: String? = nil) {
        setTextStyle(ids: [layerID], fontName: fontName, fontSize: fontSize,
                     weight: weight, colorHex: colorHex)
    }

    /// The same over EVERY picked text layer, in ONE undo step: three labels
    /// made 14pt is one trip round the panel and one press of undo, not three.
    ///
    /// Each label keeps its own wrap width while its words are re-set, so one
    /// dragged wide stays wide. The re-measure needs CoreText, which is why it
    /// happens here rather than in the core, and why several layers means
    /// several measurements inside the one step.
    func setTextStyle(ids: [UUID], fontName: String? = nil, fontSize: CGFloat? = nil,
                      weight: TextWeight? = nil, colorHex: String? = nil) {
        let targets = ids.filter { id in
            guard let layer = document?.layer(id: id), !layer.isLocked,
                  case .text(let words) = layer.content else { return false }
            // Only the labels this actually changes. Picking 14pt when they are
            // all already 14pt is a menu closing, not an undo step.
            if let fontName, words.fontName != fontName { return true }
            if let fontSize, words.fontSize != fontSize { return true }
            if let weight, words.weight != weight { return true }
            if let colorHex, words.colorHex != colorHex { return true }
            return false
        }
        guard !targets.isEmpty else {
            // Nothing to change in the document, but this is still what the
            // next block of text should start at.
            rememberTextDefaults(fontName: fontName, fontSize: fontSize,
                                 weight: weight, colorHex: colorHex)
            return
        }
        // The box each label lands in at the new type. A box somebody made
        // bigger than its words — a paragraph, or a label told to stretch —
        // keeps the room it was given, so restyling re-wraps in place. A box
        // still hugging its words re-hugs them, however short they are, instead
        // of wrapping the moment bold makes them a few points wider than the
        // box they just fitted. (Current has no stretching, so it keeps its old
        // rule untouched: every box at least the minimum width.)
        //
        // Measured up front, outside the mutation, because it needs CoreText
        // and `TextBuilder.restyled` is pure: the same restyling runs twice,
        // once to measure and once to store.
        let hugsShortWords = Experiments.shared.placementEnabled
        let sizes: [UUID: CGSize] = targets.reduce(into: [:]) { sizes, id in
            guard let layer = document?.layer(id: id), let was = layer.text else { return }
            let restyled = TextBuilder.restyled(layer: layer, fontName: fontName,
                                                fontSize: fontSize, weight: weight,
                                                colorHex: colorHex)
            guard let words = restyled.text else { return }
            guard hugsShortWords else {
                sizes[id] = TextRasterizer.naturalSize(words, maxWidth: layer.frame.width,
                                                       minWidth: TextRasterizer.minimumTextWidth)
                return
            }
            let room = TextBlockMetrics.roomyBox(for: was, frame: layer.frame)
            // A box with no room to keep goes back on one line at the new type.
            sizes[id] = TextBlockMetrics.frameSize(for: words, maxWidth: .greatestFiniteMagnitude,
                                                   roomyWidth: room.width,
                                                   roomyHeight: room.height,
                                                   hugsShortWords: true)
        }
        discardDragPreview()
        perform { document in
            for id in targets {
                document.updateLayer(id: id) { l in
                    l = TextBuilder.restyled(layer: l, fontName: fontName, fontSize: fontSize,
                                             weight: weight, colorHex: colorHex)
                    if let size = sizes[id] {
                        l.frame = CGRect(origin: l.frame.origin, size: size)
                    }
                }
            }
        }
        rememberTextDefaults(fontName: fontName, fontSize: fontSize,
                             weight: weight, colorHex: colorHex)
    }

    /// What the next block of text starts at.
    private func rememberTextDefaults(fontName: String?, fontSize: CGFloat?,
                                      weight: TextWeight?, colorHex: String?) {
        if let fontName { textStyles.fontName = fontName }
        if let fontSize { textStyles.fontSize = fontSize }
        if let weight { textStyles.weight = weight }
        if let colorHex { textStyles.colorHex = colorHex }
        saveTextStyles()
        if let colorHex { recordRecentColor(hex: colorHex) }
    }

    /// Moves a text layer's words across their box. One undo step, and the box
    /// itself never moves: alignment says where the words sit in the room they
    /// already have, so a label dragged wide or told to stretch stays that
    /// wide. It is not a new-text default either — a fresh block starts at the
    /// left, where text has always started.
    func setTextAlignment(layerID: UUID, _ alignment: TextAlign) {
        setTextAlignment(ids: [layerID], alignment)
    }

    /// The same, down the box.
    func setTextAlignment(layerID: UUID, _ alignment: TextVerticalAlign) {
        setTextAlignment(ids: [layerID], alignment)
    }

    /// Every picked label's words move across their boxes together, in one
    /// undo step.
    func setTextAlignment(ids: [UUID], _ alignment: TextAlign) {
        let targets = textAlignmentTargets(ids)
        guard !targets.isEmpty else { return }
        discardDragPreview()
        perform { document in
            for id in targets { document.setTextAlignment(id: id, alignment) }
        }
    }

    /// And down them.
    func setTextAlignment(ids: [UUID], _ alignment: TextVerticalAlign) {
        let targets = textAlignmentTargets(ids)
        guard !targets.isEmpty else { return }
        discardDragPreview()
        perform { document in
            for id in targets { document.setTextAlignment(id: id, alignment) }
        }
    }

    private func textAlignmentTargets(_ ids: [UUID]) -> [UUID] {
        ids.filter { document?.layer(id: $0).map { $0.text != nil && !$0.isLocked } == true }
    }

    /// An inline edit began. Re-editing an existing layer adopts its style (so
    /// the font picker edits what's on screen) and hides the layer until
    /// commit/cancel — the editor overlay visually replaces it.
    func beginTextEdit(layerID: UUID?) {
        guard let layerID, let layer = document?.layer(id: layerID),
              case .text(let content) = layer.content else { return }
        textStyles.adopt(content)
        saveTextStyles()
        editingTextLayerID = layerID
        if let document { submit(document) }
    }

    /// Inline edit finished. Empty text adds nothing (new block) or deletes the
    /// layer (re-edit); otherwise one undo step adds/updates the layer with its
    /// frame hugging the re-measured text. `maxWidth` is the wrap width the
    /// editor used (document points), so layout doesn't shift on commit.
    func commitTextEdit(layerID: UUID?, origin: CGPoint, string: String, maxWidth: CGFloat) {
        editingTextLayerID = nil
        // A piece inside a copy is not the thing that was edited: its words
        // come from the original, so they land on the copy's own answer to the
        // wording knob instead. Written onto the piece they would be gone by
        // the next redraw, which is the whole reason this branch exists.
        if let layerID, case .knob = wordingEdit(of: layerID) {
            commitPieceWording(of: layerID, to: string)
            return
        }
        let isEmpty = string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        var content = textStyles.content(string: string)
        // Where the words sit belongs to the layer, not to the new-text style,
        // so re-wording a centred label keeps it centred instead of dropping it
        // back to the left edge.
        let edited = layerID.flatMap { document?.layer(id: $0) }
        if let existing = edited?.text {
            content.alignment = existing.alignment
            content.verticalAlignment = existing.verticalAlignment
        }
        // A box somebody made bigger than its words — a paragraph, or a label
        // told to stretch — keeps the room it was given, so re-wording it
        // re-wraps in place instead of collapsing back around the words and
        // pulling centred text off centre. A box still hugging its words
        // re-hugs them.
        var roomyWidth: CGFloat?
        var roomyHeight: CGFloat?
        // Next only, with the rest of placement: Current has no Align, so no
        // text in it can be pulled off centre by a box that re-hugs. The same
        // flag carries the rule that a box nobody has narrowed is as wide as
        // its words, however short they are.
        let hugsShortWords = Experiments.shared.placementEnabled
        if hugsShortWords, let layer = edited, let words = layer.text {
            (roomyWidth, roomyHeight) = TextBlockMetrics.roomyBox(for: words, frame: layer.frame)
        }
        if let layerID {
            if isEmpty {
                perform { $0.removeLayer(id: layerID) }
            } else {
                // The same measurer the inline editor sized its field with, so
                // the words land in the box they were typed in.
                let size = TextBlockMetrics.frameSize(for: content, maxWidth: maxWidth,
                                                      roomyWidth: roomyWidth,
                                                      roomyHeight: roomyHeight,
                                                      hugsShortWords: hugsShortWords)
                // `origin` is where the editor sat on the CANVAS. A label
                // inside a group stores its box relative to that group, so the
                // document does the conversion: written straight in, the words
                // land a whole group's origin away from where they were typed,
                // which is how a label typed inside a button ended up off the
                // button and looked like it had been thrown away.
                perform { document in
                    document.commitTextEdit(id: layerID, content: content,
                                            canvasFrame: CGRect(origin: origin, size: size))
                }
            }
        } else {
            guard !isEmpty else { return }
            // New text commits in the current foreground color (16.12).
            var content = content
            content.colorHex = foregroundFillHex
            let size = TextBlockMetrics.frameSize(for: content, maxWidth: maxWidth,
                                                  hugsShortWords: hugsShortWords)
            let layer = TextBuilder.layer(content: content, at: origin, naturalSize: size)
            perform { $0.addLayerDrawnOnFrame(layer) }
            // Re-editing existing text already runs with Select active, so only
            // the new-block path hands the editor back.
            finishCreating(layer.id)
        }
    }

    /// Inline edit abandoned (Esc): a hidden re-edited layer comes back as-is.
    func cancelTextEdit() {
        editingTextLayerID = nil
        rerender()
    }

    static let textStylesKey = "textStyles"

    static func loadTextStyles() -> TextStyles {
        guard let data = UserDefaults.standard.data(forKey: textStylesKey),
              let styles = try? JSONDecoder().decode(TextStyles.self, from: data) else {
            return TextStyles()
        }
        return styles
    }

    private func saveTextStyles() {
        if let data = try? JSONEncoder().encode(textStyles) {
            UserDefaults.standard.set(data, forKey: Self.textStylesKey)
        }
    }
}
