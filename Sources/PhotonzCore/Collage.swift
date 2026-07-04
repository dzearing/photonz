import CoreGraphics
import Foundation

/// Page layouts for the collage command (16.9).
public enum CollageTemplate: String, CaseIterable, Hashable, Codable, Sendable {
    /// Near-square grid: `ceil(sqrt(count))` columns; a short last row centers.
    case grid
    /// One horizontal row, left to right.
    case row
    /// One vertical stack, top to bottom.
    case column

    public var label: String {
        switch self {
        case .grid: "Grid"
        case .row: "Row"
        case .column: "Column"
        }
    }
}

/// Pure geometry for arranging image layers into a collage: cell frames for a
/// template, the centered aspect-fill crop, and the document mutation that
/// puts participants into their cells non-destructively (crop + frame only —
/// pixels are never touched, so undo or a cleared crop restores everything).
public enum Collage {

    /// Cell frames for `count` items inside `canvas` (top-left coordinates).
    /// `gutter` pads the outside edges and the space between cells; it is
    /// reduced when the canvas is too small for it, so cells stay positive.
    public static func cellFrames(count: Int, in canvas: CGSize,
                                  template: CollageTemplate, gutter: CGFloat) -> [CGRect] {
        guard count > 0, canvas.width > 0, canvas.height > 0 else { return [] }

        let (cols, rows): (Int, Int) = {
            switch template {
            case .row: (count, 1)
            case .column: (1, count)
            case .grid:
                { c in (c, (count + c - 1) / c) }(Int(Double(count).squareRoot().rounded(.up)))
            }
        }()

        // A gutter that would consume a whole axis collapses cells; cap it so
        // every cell keeps at least 1pt per side.
        let maxGutterX = (canvas.width - CGFloat(cols)) / CGFloat(cols + 1)
        let maxGutterY = (canvas.height - CGFloat(rows)) / CGFloat(rows + 1)
        let g = max(0, min(gutter, maxGutterX, maxGutterY))

        let cellWidth = (canvas.width - g * CGFloat(cols + 1)) / CGFloat(cols)
        let cellHeight = (canvas.height - g * CGFloat(rows + 1)) / CGFloat(rows)

        var frames: [CGRect] = []
        for index in 0..<count {
            let row = index / cols
            let col = index % cols
            // Center a short last row (grid with count not filling the grid).
            let itemsInRow = min(cols, count - row * cols)
            let rowWidth = CGFloat(itemsInRow) * cellWidth + CGFloat(itemsInRow - 1) * g
            let startX = (canvas.width - rowWidth) / 2
            frames.append(CGRect(x: startX + CGFloat(col) * (cellWidth + g),
                                 y: g + CGFloat(row) * (cellHeight + g),
                                 width: cellWidth, height: cellHeight))
        }
        return frames
    }

    /// The largest centered sub-rect of `content` whose aspect matches
    /// `aspect` (width ÷ height) — the crop that fills a cell without
    /// distortion. Composes with an existing crop: pass it as `content` and
    /// the result nests inside it.
    public static func fillCrop(of content: CGRect, matchingAspect aspect: CGFloat) -> CGRect {
        guard aspect > 0, content.width > 0, content.height > 0 else { return content }
        let contentAspect = content.width / content.height
        if contentAspect > aspect {
            let width = content.height * aspect
            return CGRect(x: content.midX - width / 2, y: content.minY,
                          width: width, height: content.height)
        } else {
            let height = content.width / aspect
            return CGRect(x: content.minX, y: content.midY - height / 2,
                          width: content.width, height: height)
        }
    }

    /// Cell rects for a collage layer, in LAYER-LOCAL top-left space. Cells
    /// derive from the frame size on every call — resizing the layer reflows
    /// the layout; nothing is stored.
    public static func slotFrames(for content: CollageContent, in size: CGSize) -> [CGRect] {
        cellFrames(count: content.slots.count, in: size,
                   template: content.template, gutter: content.gutter)
    }

    /// The slot under a DOCUMENT-space point, or nil on a gutter / outside
    /// the layer. Inverts the layer transform the same way `contains` does.
    public static func slotIndex(at point: CGPoint, in layer: Layer) -> Int? {
        guard let content = layer.collage else { return nil }
        var p = point
        if !layer.transform.isIdentity {
            let center = CGPoint(x: layer.frame.midX, y: layer.frame.midY)
            p = point.applying(layer.transform.affineTransform(around: center).inverted())
        }
        let local = CGPoint(x: p.x - layer.frame.minX, y: p.y - layer.frame.minY)
        return slotFrames(for: content, in: layer.frame.size).firstIndex { $0.contains(local) }
    }

    /// A collage layer with the given content.
    public static func layer(content: CollageContent, frame: CGRect, name: String = "Collage") -> Layer {
        Layer(name: name, content: .collage(content), frame: frame)
    }

    /// Seeds a collage from existing photo layers: one slot per image layer in
    /// the given (document bottom→top = reading) order, frame = the union of
    /// their frames. Non-image layers are skipped; nil when nothing remains.
    /// Source-layer crops don't carry over — slots aspect-fill at render time.
    public static func layer(absorbing layers: [Layer], name: String = "Collage") -> Layer? {
        let photos = layers.filter { $0.imageRef != nil }
        guard !photos.isEmpty else { return nil }
        let union = photos.dropFirst().reduce(photos[0].frame) { $0.union($1.frame) }
        let content = CollageContent(slots: photos.map { CollageSlot(imageRef: $0.imageRef) })
        return layer(content: content, frame: union, name: name)
    }
}

/// One cell of a collage layer. Empty (nil ref) slots render transparent and
/// draw as drop wells in the editor.
public struct CollageSlot: Hashable, Codable, Sendable {
    public var imageRef: ImageRef?

    public init(imageRef: ImageRef? = nil) {
        self.imageRef = imageRef
    }
}

/// A collage layer's content: the template, spacing, backdrop, and photo
/// slots. Cell geometry is NOT stored — it derives from the layer frame via
/// `Collage.slotFrames`, so the layout reflows on resize and photos aspect-
/// fill their cells at render time (fully non-destructive).
public struct CollageContent: Hashable, Codable, Sendable {
    public var template: CollageTemplate
    /// Outer margin and inter-cell spacing, in document pixels.
    public var gutter: CGFloat
    public var slots: [CollageSlot]
    /// Fill behind the cells; nil renders transparent.
    public var backdropColorHex: String?

    public init(template: CollageTemplate = .grid, gutter: CGFloat = 24,
                slots: [CollageSlot] = [], backdropColorHex: String? = "#FFFFFF") {
        self.template = template
        self.gutter = gutter
        self.slots = slots
        self.backdropColorHex = backdropColorHex
    }

    /// Puts `ref` into the slot (replacing any occupant). Out-of-range no-ops.
    public mutating func fill(slot index: Int, with ref: ImageRef) {
        guard slots.indices.contains(index) else { return }
        slots[index].imageRef = ref
    }

    /// Exchanges two slots' photos. Out-of-range no-ops.
    public mutating func swapSlots(_ i: Int, _ j: Int) {
        guard slots.indices.contains(i), slots.indices.contains(j), i != j else { return }
        slots.swapAt(i, j)
    }

    /// Grows with empty slots or truncates (dropping trailing photos); the
    /// count floors at 1.
    public mutating func setSlotCount(_ count: Int) {
        let target = max(1, count)
        if target < slots.count {
            slots.removeLast(slots.count - target)
        } else {
            slots.append(contentsOf: Array(repeating: CollageSlot(), count: target - slots.count))
        }
    }
}

extension Layer {
    /// The collage content, when this is a collage layer.
    public var collage: CollageContent? {
        if case .collage(let content) = content { return content }
        return nil
    }
}
