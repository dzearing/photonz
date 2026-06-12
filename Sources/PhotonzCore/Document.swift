import CoreGraphics
import Foundation

/// The photonz document: a canvas plus an ordered stack of layers.
/// Index 0 renders at the bottom. Pure value type — all mutation goes
/// through methods so commands/undo can wrap them uniformly.
public struct PhotonzDocument: Hashable, Codable, Sendable {
    public var canvasSize: CGSize
    public var layers: [Layer]

    public init(canvasSize: CGSize, layers: [Layer] = []) {
        self.canvasSize = canvasSize
        self.layers = layers
    }

    /// A new document built around a base image, which becomes the bottom layer.
    /// The background is born locked (Photoshop convention): clicks on it fall
    /// through to the marquee instead of dragging the whole image around.
    public static func withBaseImage(_ ref: ImageRef) -> PhotonzDocument {
        let layer = Layer(name: "Background", content: .image(ref),
                          frame: CGRect(origin: .zero, size: ref.pixelSize),
                          isLocked: true)
        return PhotonzDocument(canvasSize: ref.pixelSize, layers: [layer])
    }

    // MARK: - Layer access

    public func layer(id: UUID) -> Layer? {
        layers.first { $0.id == id }
    }

    public func index(of id: UUID) -> Int? {
        layers.firstIndex { $0.id == id }
    }

    /// The topmost editable layer under a canvas point. Top-down order;
    /// invisible and locked layers never hit. `zoom` keeps stroke hit slop
    /// constant in screen points.
    public func hitTest(_ point: CGPoint, zoom: CGFloat = 1) -> Layer? {
        layers.reversed().first { layer in
            layer.isVisible && !layer.isLocked && layer.contains(canvasPoint: point, zoom: zoom)
        }
    }

    // MARK: - Layer mutation

    public mutating func addLayer(_ layer: Layer, at index: Int? = nil) {
        layers.insert(layer, at: index.map { min(max(0, $0), layers.count) } ?? layers.count)
    }

    @discardableResult
    public mutating func removeLayer(id: UUID) -> Layer? {
        guard let idx = index(of: id) else { return nil }
        return layers.remove(at: idx)
    }

    public mutating func moveLayer(id: UUID, to newIndex: Int) {
        guard let idx = index(of: id) else { return }
        let layer = layers.remove(at: idx)
        layers.insert(layer, at: min(max(0, newIndex), layers.count))
    }

    public mutating func updateLayer(id: UUID, _ mutate: (inout Layer) -> Void) {
        guard let idx = index(of: id) else { return }
        mutate(&layers[idx])
    }

    /// Reorders layers from the layers panel, which lists them top-down
    /// (visual index 0 = topmost = last in `layers`). Source offsets and the
    /// destination use SwiftUI `onMove` semantics: the destination indexes the
    /// visual array *before* the moved rows are removed.
    public mutating func moveLayers(visualSources: IndexSet, visualDestination: Int) {
        var visual = Array(layers.reversed())
        let moved = visualSources.compactMap { visual.indices.contains($0) ? visual[$0] : nil }
        guard !moved.isEmpty else { return }
        let movedIDs = Set(moved.map(\.id))
        var destination = visualDestination - visualSources.count { $0 < visualDestination }
        visual.removeAll { movedIDs.contains($0.id) }
        destination = min(max(0, destination), visual.count)
        visual.insert(contentsOf: moved, at: destination)
        layers = visual.reversed()
    }

    /// Duplicates a layer directly above the original (panel context menu, ⌘V
    /// of a copied layer reuses `Layer.duplicated`). Returns the copy.
    @discardableResult
    public mutating func duplicateLayer(id: UUID, offsetBy offset: CGPoint = .zero) -> Layer? {
        guard let idx = index(of: id) else { return nil }
        let copy = layers[idx].duplicated(offsetBy: offset)
        layers.insert(copy, at: idx + 1)
        return copy
    }

    /// Copies a region of the canvas into a new layer placed directly on top
    /// ("promote selection to layer"). The caller supplies the ImageRef for the
    /// rasterized region (rendering lives outside the core model).
    @discardableResult
    public mutating func promoteRegionToLayer(region: CGRect, rasterized ref: ImageRef, name: String = "Promoted Layer") -> Layer {
        let clamped = Geometry.clampCrop(region, toCanvas: canvasSize)
        let layer = Layer(name: name, content: .image(ref), frame: clamped)
        layers.append(layer)
        return layer
    }

    /// The one-click blur-behind recipe: stacks a blurred full-canvas copy of
    /// the composite, then a sharp copy cropped to `selection` on top — the
    /// selection stays crisp while everything around it blurs. Both layers
    /// share `ref` (one full-canvas rasterization); both stay fully
    /// non-destructive (the blur is a style, the cutout a stored crop).
    @discardableResult
    public mutating func blurBehind(selection: CGRect, rasterized ref: ImageRef,
                                    blurRadius: CGFloat = 16) -> (blur: Layer, focus: Layer) {
        let canvasRect = CGRect(origin: .zero, size: canvasSize)
        var blur = Layer(name: "Blur Behind", content: .image(ref), frame: canvasRect)
        blur.style.blurRadius = blurRadius
        var focus = Layer(name: "Focus", content: .image(ref), frame: canvasRect)
        focus.cropContent(to: Geometry.clampCrop(selection, toCanvas: canvasSize))
        layers.append(blur)
        layers.append(focus)
        return (blur, focus)
    }

    // MARK: - Canvas operations

    /// Crops the whole document. Layer frames are re-expressed relative to the
    /// new canvas origin; layers entirely outside the crop are removed.
    public mutating func crop(to rect: CGRect) {
        let r = Geometry.clampCrop(rect, toCanvas: canvasSize)
        canvasSize = r.size
        layers = layers.compactMap { layer in
            var l = layer
            l.frame.origin.x -= r.origin.x
            l.frame.origin.y -= r.origin.y
            let canvasRect = CGRect(origin: .zero, size: r.size)
            guard l.frame.intersects(canvasRect) else { return nil }
            return l
        }
    }

    /// Resizes the canvas, scaling all layer frames proportionally.
    public mutating func resize(to newSize: CGSize) {
        let scale = Geometry.resizeScale(from: canvasSize, to: newSize)
        canvasSize = newSize
        for i in layers.indices {
            let f = layers[i].frame
            layers[i].frame = CGRect(x: f.origin.x * scale.x, y: f.origin.y * scale.y,
                                     width: f.width * scale.x, height: f.height * scale.y)
        }
    }
}
