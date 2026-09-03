import CoreGraphics
import Foundation

/// Frames: the thing a screen gets built on.
///
/// A frame is an ordinary group with a size — nothing more. It clips what is
/// inside it, it can paint a surface behind it, and several of them sit side by
/// side on one canvas, which is how a document holds more than one screen
/// without the app growing a pages concept. Everything a group already does
/// (select, move, restack, group, undo, save) a frame does by being one.
/// See `docs/design/ui-building.md`, "One tree, no second document kind".
public struct FramePreset: Hashable, Sendable, Identifiable {
    public let id: String
    /// What the menu shows, without the numbers — every surface prints those
    /// from `size`, so a label and a size can never disagree.
    public let title: String
    public let size: CGSize

    public init(id: String, title: String, size: CGSize) {
        self.id = id
        self.title = title
        self.size = size
    }

    /// The sizes offered, deliberately short: the surfaces interfaces actually
    /// get built for, biggest to smallest, with the desktop first because that
    /// is what most screens in this app start life as.
    public static let all: [FramePreset] = [
        FramePreset(id: "desktop", title: "Desktop", size: CGSize(width: 1440, height: 1024)),
        FramePreset(id: "laptop", title: "Laptop", size: CGSize(width: 1280, height: 800)),
        FramePreset(id: "tablet", title: "Tablet", size: CGSize(width: 1024, height: 768)),
        FramePreset(id: "phone", title: "Phone", size: CGSize(width: 390, height: 844)),
        FramePreset(id: "square", title: "Square", size: CGSize(width: 1000, height: 1000)),
    ]

    /// What the dialog opens on, so Return alone makes a frame.
    public static let `default` = all[3]

    /// The preset a size matches exactly, or nil for a size nobody offered —
    /// which is what makes the menu able to say "Custom" truthfully.
    public static func matching(_ size: CGSize) -> FramePreset? {
        all.first { $0.size == size }
    }

    /// The smallest and largest side a frame may have. The floor keeps a frame
    /// grabbable; the ceiling is the same one a typed layer size answers to.
    public static let minimumSide: CGFloat = 1
    public static let maximumSide: CGFloat = LayerGeometry.maximumSide

    /// A size made safe to build: whole points, inside the legal range, never
    /// NaN.
    public static func normalized(_ size: CGSize) -> CGSize {
        CGSize(width: clamp(size.width), height: clamp(size.height))
    }

    /// Whether a size can be used as typed — a Create button's enablement.
    public static func isValid(_ size: CGSize) -> Bool {
        normalized(size) == size
    }

    private static func clamp(_ side: CGFloat) -> CGFloat {
        guard side.isFinite else { return minimumSide }
        return min(max(side.rounded(), minimumSide), maximumSide)
    }
}

extension Layer {

    /// The surface a new frame paints behind its contents: white, because a
    /// screen you cannot see is a screen you cannot build on.
    public static let defaultFrameBackgroundHex = "#FFFFFF"

    /// A new frame: a box of `size` at `origin`, in the space of whatever will
    /// hold it, with the layers it starts with already inside it.
    public static func frameLayer(name: String, origin: CGPoint, size: CGSize,
                                  children: [Layer] = [],
                                  backgroundHex: String? = defaultFrameBackgroundHex,
                                  clipsContents: Bool = true) -> Layer {
        Layer(name: name,
              content: .group(GroupContent(children: children, isFrame: true,
                                           clipsContents: clipsContents,
                                           backgroundHex: backgroundHex)),
              frame: CGRect(origin: origin, size: FramePreset.normalized(size)))
    }
}

extension PhotonzDocument {

    /// Every frame in the document, groups reached into, outermost first.
    public var frames: [Layer] {
        allLayers.filter(\.isFrame)
    }

    /// Whether anything in this document is a frame. A screenshot with three
    /// annotations on it answers false, which is how every surface that grows
    /// frame furniture knows to stay out of the way.
    public var hasFrames: Bool {
        layers.contains { $0.selfAndDescendants.contains(where: \.isFrame) }
    }

    /// A name no layer is using yet: "Frame", then "Frame 2", "Frame 3"… so
    /// two screens made a minute apart are tellable apart in the layers list
    /// and in the export menu.
    public func freshFrameName(base: String = "Frame") -> String {
        freshGroupName(base: base)
    }

    /// The frame a layer belongs to: itself if it is one, otherwise the
    /// nearest frame above it in the tree. Nil for a layer sitting loose on
    /// the canvas, which is every layer in a document that has no frames.
    public func frameID(containing id: UUID) -> UUID? {
        var current: UUID? = id
        while let this = current {
            if layer(id: this)?.isFrame == true { return this }
            current = parentID(of: this)
        }
        return nil
    }

    /// Drops a new frame on the canvas, above everything, and returns it.
    @discardableResult
    public mutating func addFrame(name: String? = nil, origin: CGPoint, size: CGSize,
                                  backgroundHex: String? = Layer.defaultFrameBackgroundHex) -> Layer {
        let made = Layer.frameLayer(name: name ?? freshFrameName(), origin: origin,
                                    size: size, backgroundHex: backgroundHex)
        addLayer(made)
        return made
    }

    /// Adds a layer, and puts it ON the frame it was drawn on.
    ///
    /// Drawing a button inside a screen should put the button on that screen —
    /// otherwise a frame is a picture of a boundary rather than a thing that
    /// holds anything, and the only way in would be dragging rows in the layers
    /// list. The frame is the topmost one whose box holds the new layer's
    /// CENTRE, so a shape drawn a little over the edge still joins the screen
    /// it was mostly drawn on, and its position is rewritten into that frame's
    /// space, so it does not move on screen.
    ///
    /// Everything else is unchanged: with no frames in the document this is
    /// exactly `addLayer`.
    @discardableResult
    public mutating func addLayerOnFrame(_ layer: Layer) -> UUID? {
        let centre = CGPoint(x: layer.localBounds.midX, y: layer.localBounds.midY)
        guard let frameID = frameID(under: centre) else {
            addLayer(layer)
            return nil
        }
        var child = layer
        let origin = canvasBounds(of: frameID)?.origin ?? .zero
        child.frame = child.frame.offsetBy(dx: -origin.x, dy: -origin.y)
        updateLayer(id: frameID) { $0.children.append(child) }
        return frameID
    }

    /// `addLayerOnFrame` where frames exist, plain `addLayer` where they do
    /// not — the one call every drawing tool makes, so a document without a
    /// frame in it takes exactly the path it always took.
    public mutating func addLayerDrawnOnFrame(_ layer: Layer) {
        guard hasFrames else {
            addLayer(layer)
            return
        }
        addLayerOnFrame(layer)
    }

    /// The frame a canvas point lands on: the topmost one that is visible,
    /// unlocked and holds the point. Nil when the point is on bare canvas.
    public func frameID(under point: CGPoint) -> UUID? {
        func search(_ list: [Layer], _ point: CGPoint) -> UUID? {
            for layer in list.reversed() {
                guard layer.isVisible, !layer.isLocked else { continue }
                guard layer.isGroup else { continue }
                let local = CGPoint(x: point.x - layer.frame.origin.x,
                                    y: point.y - layer.frame.origin.y)
                // A frame inside a frame wins, the way the innermost room you
                // are standing in is the one you are in.
                if let inner = search(layer.children, local) { return inner }
                if layer.isFrame, layer.localBounds.contains(point) { return layer.id }
            }
            return nil
        }
        return search(layers, point)
    }

    /// Whether Layer ▸ Frame Selection would do anything: one unlocked layer
    /// is enough, unlike ⌘G, because putting a single thing on a screen of its
    /// own is a normal way to start.
    public func canFrameSelection(ids: Set<UUID>) -> Bool {
        !groupableMembers(ids: ids).isEmpty
    }

    /// Wraps the selection in a frame that fits it exactly: the same one
    /// mutation ⌘G runs, with the resulting group given the box its contents
    /// make. Nothing moves on screen and nothing is hidden, so the frame comes
    /// out clipping exactly at the edge of what was selected.
    ///
    /// The frame paints no surface: this is a boundary drawn around work that
    /// already exists, not a fresh screen, and a white sheet appearing behind a
    /// screenshot would be a surprise.
    @discardableResult
    public mutating func frameSelection(ids: Set<UUID>, name: String? = nil,
                                        clipsContents: Bool = true) -> Layer? {
        let title = name ?? freshFrameName()
        guard let group = groupLayers(ids: ids, name: title) else { return nil }
        updateLayer(id: group.id) { layer in
            let box = layer.localBounds
            layer.content = .group(GroupContent(children: layer.children, isFrame: true,
                                                clipsContents: clipsContents,
                                                backgroundHex: nil))
            layer.frame = CGRect(origin: box.origin,
                                 size: FramePreset.normalized(box.size))
        }
        return layer(id: group.id)
    }

    /// Turns a frame back into an ordinary group, or an ordinary group into a
    /// frame the size of its contents. What Ungroup does to structure, this
    /// does to the box.
    public mutating func setFrame(id: UUID, isFrame: Bool) {
        guard let existing = layer(id: id), let group = existing.group,
              group.isFrame != isFrame else { return }
        let box = existing.localBounds
        updateLayer(id: id) { layer in
            var group = group
            group.isFrame = isFrame
            group.children = layer.children
            layer.content = .group(group)
            layer.frame = isFrame
                ? CGRect(origin: box.origin, size: FramePreset.normalized(box.size))
                : CGRect(origin: box.origin, size: .zero)
        }
    }

    /// Resizes a frame's box. The layers inside stay exactly where they are —
    /// a frame's size says where it clips, it does not stretch its contents.
    public mutating func setFrameSize(id: UUID, size: CGSize) {
        guard layer(id: id)?.isFrame == true else { return }
        updateLayer(id: id) { $0.frame.size = FramePreset.normalized(size) }
    }

    /// Whether a frame hides what sticks out past its box.
    public mutating func setFrameClips(id: UUID, _ clips: Bool) {
        guard let group = layer(id: id)?.group, group.isFrame else { return }
        updateLayer(id: id) { layer in
            var group = group
            group.children = layer.children
            group.clipsContents = clips
            layer.content = .group(group)
        }
    }

    /// The surface a frame paints behind its contents; nil clears it.
    public mutating func setFrameBackground(id: UUID, hex: String?) {
        guard let group = layer(id: id)?.group, group.isFrame else { return }
        updateLayer(id: id) { layer in
            var group = group
            group.children = layer.children
            group.backgroundHex = hex
            layer.content = .group(group)
        }
    }

    /// The gutter between two frames placed side by side: wide enough that
    /// their name labels never touch, narrow enough that both stay on screen.
    public static let frameGutter: CGFloat = 80

    /// Where a new frame of `size` should land.
    ///
    /// The first frame lands in the middle of what the person is looking at.
    /// Every one after that lines up to the RIGHT of the frames already on the
    /// canvas, along their top edge, so a document of several screens reads as
    /// a row rather than a pile — and a new screen never lands on top of one
    /// that is already there.
    ///
    /// `visible` is the part of the canvas on screen, in document points; pass
    /// the whole canvas when that is not known.
    public func placementForNewFrame(size: CGSize, visible: CGRect) -> CGPoint {
        let boxes = frames.compactMap { canvasBounds(of: $0.id) }
        if let rightmost = boxes.max(by: { $0.maxX < $1.maxX }) {
            let top = boxes.map(\.minY).min() ?? rightmost.minY
            return CGPoint(x: (rightmost.maxX + Self.frameGutter).rounded(), y: top.rounded())
        }
        let room = visible.isNull || visible.isEmpty
            ? CGRect(origin: .zero, size: canvasSize) : visible
        return CGPoint(x: (room.midX - size.width / 2).rounded(),
                       y: (room.midY - size.height / 2).rounded())
    }

    /// One frame as a document of its own: the canvas is the frame's box and
    /// the frame sits at its origin, so rendering it produces the frame's
    /// contents and nothing else — not the canvas behind it, not the layer
    /// overlapping it from outside. This is what Export means by a frame.
    public func frameDocument(id: UUID) -> PhotonzDocument? {
        guard var frame = layer(id: id), frame.isFrame else { return nil }
        let box = frame.localBounds
        guard box.width >= 1, box.height >= 1 else { return nil }
        frame.frame = CGRect(origin: .zero, size: box.size)
        frame.isVisible = true
        frame.isLocked = false
        return PhotonzDocument(canvasSize: box.size, layers: [frame], pixelScale: pixelScale)
    }
}
