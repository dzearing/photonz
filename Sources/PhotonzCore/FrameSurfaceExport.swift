import CoreGraphics
import Foundation

public extension SVGExport {

    /// What an export set to a background takes out of a document.
    struct LeftOut: Hashable, Sendable {
        /// The canvas layer that goes, if there is one.
        public var layerID: UUID?
        /// The frames that lose their surface and keep everything else.
        public var surfaces: Set<UUID> = []
    }

    /// How many moments of a lap are asked where a moving shape has got to.
    /// Enough to catch a swing at its widest in a lap of a few seconds.
    internal static let momentsAskedAboutPerLap = 64

    /// The one answer to what leaves the file, for the writer and the picture
    /// path alike, so an SVG and a PNG of the same pick agree.
    ///
    /// Nothing goes from a document with no backdrop: a screenshot, a
    /// photograph or a screen comes out whole. Otherwise the canvas goes and so
    /// does every icon frame's untouched white, because on an icon that white
    /// is the artboard. Only frames lying on the canvas count: an icon inside a
    /// screen has the screen behind it, and taking its white away would change
    /// how the screen looks.
    static func leftOut(of document: PhotonzDocument, flatImages: [UUID: RGBA],
                        background: Background) -> LeftOut {
        guard background != .keep,
              let found = backdrop(in: document, flatImages: flatImages) else { return LeftOut() }
        var gone = LeftOut(layerID: found.isFrameSurface ? nil : found.layerID)
        gone.surfaces = Set(document.layers.filter(surfaceIsUndrawn).map(\.id))
        if background == .dropChosen, found.isFrameSurface { gone.surfaces.insert(found.layerID) }
        return gone
    }

    /// The surface of an icon frame filling the canvas, as something Export can
    /// offer to leave out. Nil for a screen, whose surface is part of the
    /// screen, and for a frame you can see straight through.
    internal static func frameBackdrop(_ frame: Layer, canvas: CGSize) -> Backdrop? {
        guard IconPreviews.isIconSize(frame.frame.size),
              let surface = frame.group?.background,
              let colour = RGBA(hex: surface.hex), colour.a > 0,
              frame.transform.isIdentity,
              covers(canvas, frame.frame) else { return nil }
        return Backdrop(layerID: frame.id, color: colour, isFrameSurface: true,
                        isChosen: !surfaceIsUndrawn(frame))
    }

    /// Whether this frame's surface is one nobody drew: an icon frame still
    /// wearing the white every new frame starts with, and nothing else.
    ///
    /// White picked by hand reads the same as white left alone, since a frame
    /// keeps only its colour. Anything done to the frame says somebody meant
    /// it: rounded corners on a white tile are the icon's own shape, so that
    /// counts as chosen, and so does a shadow, a fade or a frame that moves. A
    /// component's frame belongs to the component.
    internal static func surfaceIsUndrawn(_ layer: Layer) -> Bool {
        guard let group = layer.group, group.isFrame, group.componentID == nil,
              IconPreviews.isIconSize(layer.frame.size),
              let surface = group.background, surface.kind == .solid,
              let colour = RGBA(hex: surface.hex),
              colour == RGBA(hex: Layer.defaultFrameBackgroundHex) else { return false }
        return layer.style.opacity >= 1
            && layer.style.blendMode == .normal
            && !layer.style.cornerRadii.isRound
            && !layer.style.effects.contains(where: { $0.isOn })
            && layer.transform.isIdentity
            && !layer.hasMotion
    }
}
