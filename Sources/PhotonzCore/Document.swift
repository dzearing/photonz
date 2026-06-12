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
    /// invisible and locked layers never hit.
    public func hitTest(_ point: CGPoint) -> Layer? {
        layers.reversed().first { layer in
            layer.isVisible && !layer.isLocked && layer.contains(canvasPoint: point)
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
