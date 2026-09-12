import AppKit
import PhotonzCore
import SwiftUI

// MARK: - Lenses (Next flag `next-lens`)

/// The words this feature uses, in one place, so the tool bar, the capsule, the
/// panel and the menu row never drift from one another.
enum LensCopy {
    /// The glyph on the tool. Three overlapping circles is the standard
    /// "filters" mark, and a lens is exactly that: what is underneath, seen
    /// through something.
    static let symbol = "camera.filters"
    static let toolTitle = "Lens"
    static let sectionTitle = "Lens"
    static let toolHelp = "Drag a box over anything to change what is underneath it: "
        + "blur an address, pixelate a name, grey out a region."
    /// Said once, where somebody hiding something can read it. Not a second
    /// mechanism: export and copy already flatten.
    static let safety = "What you export or copy is flattened, so a pixelated "
        + "region really is gone from the picture that leaves the app. The saved "
        + "document still holds the original underneath, so you can change your mind."
}

extension EditorState {

    private static let lensToolKey = "tool.lens.content"

    /// The lens tool's own memory: what the NEXT lens you draw does, and how
    /// hard it does it. The same shape as the layer's content, so a setting
    /// changed here is the setting the drawn layer arrives with.
    ///
    /// Written only from the tool's own controls, never from a picked lens, the
    /// same rule the callout's magnification follows: the tool must not quietly
    /// absorb whatever the last thing you tuned happened to be.
    var lensToolContent: LensContent {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.lensToolKey),
                  let content = try? JSONDecoder().decode(LensContent.self, from: data) else {
                return LensContent()
            }
            return content
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: Self.lensToolKey)
        }
    }

    var lensToolAdjustment: LensAdjustment {
        get { lensToolContent.adjustment }
        set {
            var content = lensToolContent
            guard content.adjustment != newValue else { return }
            content.adjustment = newValue
            lensToolContent = content
            // The bar's capsule and the panel's tool section both read this,
            // and neither observes UserDefaults.
            lensToolRevision &+= 1
        }
    }

    var lensToolAmount: CGFloat {
        get { lensToolContent.amount }
        set {
            var content = lensToolContent
            guard content.amount != newValue else { return }
            content.amount = newValue
            lensToolContent = content
            lensToolRevision &+= 1
        }
    }

    /// Completed drag from the lens tool: one undo step adds a lens the size of
    /// the box you drew, doing whatever the tool is set to do, and the editor
    /// hands back to Select with it picked, like every other drawing tool.
    func addLens(from start: CGPoint, to end: CGPoint) {
        guard let document,
              let layer = LensBuilder.layer(from: start, to: end, canvas: document.canvasSize,
                                            adjustment: lensToolAdjustment,
                                            content: lensToolContent) else { return }
        perform { $0.addLayerDrawnOnFrame(layer) }
        finishCreating(layer.id)
    }

    /// The picked lens, nil when what is picked is not one.
    var selectedLens: (id: UUID, content: LensContent)? {
        guard let id = selectedLayerID, let lens = document?.layer(id: id)?.lens else { return nil }
        return (id, lens)
    }

    /// Switches what the picked lens does. One undo step, and the number that
    /// adjustment was last set to comes back with it.
    func setLensAdjustment(_ adjustment: LensAdjustment) {
        guard let picked = selectedLens, picked.content.adjustment != adjustment else { return }
        perform { document in
            document.updateLayer(id: picked.id) { layer in
                guard var lens = layer.lens else { return }
                lens.adjustment = adjustment
                layer.content = .lens(lens)
                // The row in the layers list is named after what the lens does,
                // unless somebody has named it themselves.
                if LensAdjustment.allCases.contains(where: { $0.title == layer.name }) {
                    layer.name = adjustment.title
                }
            }
        }
    }

    /// What the panel's slider shows: where the pull has got to while one is
    /// live, and what the document says the rest of the time.
    var selectedLensAmount: CGFloat? {
        guard let picked = selectedLens else { return nil }
        if let preview = lensAmountPreview, preview.id == picked.id { return preview.amount }
        return picked.content.amount
    }

    /// Live while the slider is under a finger: rendered straight away and kept
    /// out of history, so the picture follows the pull and the whole pull is
    /// one step to undo rather than forty.
    func previewLensAmount(_ amount: CGFloat) {
        guard let picked = selectedLens, var doc = document else { return }
        if lensAmountBeforeDrag == nil { lensAmountBeforeDrag = picked.content.amount }
        var clamped = picked.content
        clamped.amount = amount
        lensAmountPreview = (picked.id, clamped.amount)
        doc.updateLayer(id: picked.id) { layer in
            guard var lens = layer.lens else { return }
            lens.amount = clamped.amount
            layer.content = .lens(lens)
        }
        submit(doc)
    }

    /// Slider release: one undo step from where the pull started to where it
    /// ended. A pull that went nowhere is a History no-op.
    func commitLensAmount() {
        guard let preview = lensAmountPreview else { return }
        lensAmountPreview = nil
        lensAmountBeforeDrag = nil
        perform { document in
            document.updateLayer(id: preview.id) { layer in
                guard var lens = layer.lens else { return }
                lens.amount = preview.amount
                layer.content = .lens(lens)
            }
        }
    }
}
