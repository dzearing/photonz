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
        + "blur an address, pixelate a name, grey out a region, or magnify it."
    /// Said once, where somebody hiding something can read it. Not a second
    /// mechanism: export and copy already flatten. This is the LONG wording,
    /// which is what the Does picker says on hover.
    static let safety = "What you export or copy is flattened, so a pixelated "
        + "region really is gone from the picture that leaves the app. The saved "
        + "document still holds the original underneath, so you can change your mind."

    /// The same as the line under the section: one short sentence carrying the
    /// half somebody covering an address actually needs. That it is reversible
    /// in the saved document is reassurance rather than safety, so it stays on
    /// the tip above (UX-PATTERNS §4, "How much a section may say", 2026-09-14).
    static let safetyCaption = "What you export is flattened, so this really hides it."
}

extension EditorState {

    static let lensToolKey = "tool.lens.content"

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

    static let lensToolKindKey = "tool.lens.kind"

    /// What the NEXT thing the Lens tool draws will be: one of the five
    /// adjustments, or Magnify (`LensKind`).
    ///
    /// Kept apart from `lensToolAdjustment` rather than replacing it, so
    /// switching to Magnify and back hands your blur strength back instead of
    /// forgetting which adjustment you were on. The same reason each adjustment
    /// keeps its own number.
    ///
    /// Magnify's own two settings are the callout's — `calloutToolMagnification`
    /// and `calloutToolShape` — rather than copies, so the number you set here
    /// is the number the callout is drawn at, with nothing to keep in step.
    /// The stored kind with no editor to hand, for the capsule's static policy
    /// call. Falls back to the first of the six rather than to the remembered
    /// adjustment, which is a detail only reachable from an instance.
    static var lensToolKindSetting: LensKind {
        UserDefaults.standard.string(forKey: lensToolKindKey)
            .flatMap(LensKind.init(rawValue:)) ?? .blur
    }

    var lensToolKind: LensKind {
        get {
            guard let raw = UserDefaults.standard.string(forKey: Self.lensToolKindKey),
                  let kind = LensKind(rawValue: raw) else { return LensKind(lensToolAdjustment) }
            return kind
        }
        set {
            guard lensToolKind != newValue else { return }
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.lensToolKindKey)
            // Picking an adjustment from the Lens picker is also picking it as
            // THE adjustment, so the amount slider beside it is that one's.
            if let adjustment = newValue.adjustment { lensToolAdjustment = adjustment }
            lensToolRevision &+= 1
        }
    }

    /// Whether the Lens tool in your hand is set to magnify, which is the one
    /// kind whose drag marks a region somewhere else on the picture rather than
    /// the box the layer lands in.
    var lensToolMagnifies: Bool { lensToolKind.magnifies }

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

    /// Completed drag from the Lens tool, whichever of the six kinds it is set
    /// to. Magnify draws the zoom callout it has always drawn — the box you
    /// dragged is the region magnified, and the magnified copy flies out beside
    /// it — and the other five draw a lens the size of the box.
    func addLensDrag(from start: CGPoint, to end: CGPoint) {
        if lensToolMagnifies {
            addZoomCallout(from: start, to: end)
        } else {
            addLens(from: start, to: end)
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
        let moment = documentTimeMS
        perform { $0.addLayerDrawn(layer, atTimeMS: moment) }
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
        setLensKind(LensKind(adjustment))
    }

    /// What the picked layer does to the picture underneath it, nil when what
    /// is picked does nothing to it. A magnifier answers Magnify.
    var selectedLensKind: LensKind? {
        guard let id = selectedLayerID else { return nil }
        return document?.layer(id: id)?.lensKind
    }

    /// Switches the picked lens or magnifier to another of the six kinds. One
    /// undo step.
    ///
    /// Between the five adjustments this is what it has always been: the number
    /// that adjustment was last set to comes back with it and the box does not
    /// move. Crossing to or from Magnify is a bigger change and
    /// `LensConversion` decides it — the short version is that a magnifier
    /// switched to Blur keeps its box exactly where it is, and a lens switched
    /// to Magnify magnifies the region it was covering with the box placed
    /// clear of it, the way a freshly drawn callout is.
    func setLensKind(_ kind: LensKind) {
        guard let id = selectedLayerID, let document,
              let was = document.layer(id: id)?.lensKind, was != kind else { return }
        let canvas = document.canvasSize
        let settings = lensToolContent
        let magnification = calloutToolMagnification
        let shape = calloutToolShape
        // Only the lens-to-Magnify direction reads this, and a lens is never in
        // the list, so there is nothing of this layer's own to leave out.
        let occupied = document.placedZoomCalloutRects
        perform { document in
            document.updateLayer(id: id) { layer in
                layer = LensConversion.layer(layer, becoming: kind, canvas: canvas,
                                             lensSettings: settings,
                                             magnification: magnification, shape: shape,
                                             avoiding: occupied)
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
