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

    /// Arranges the layers in `ids` into collage cells: sets `canvasSize`
    /// first when given, then assigns cells in DOCUMENT order (bottom→top =
    /// reading order — the caller's id order is irrelevant), aspect-filling
    /// each image layer via a centered crop (composed with any existing crop)
    /// and clearing rotation. Unknown ids and non-participant layers are
    /// untouched.
    public static func apply(to document: inout PhotonzDocument, ids: [UUID],
                             template: CollageTemplate, gutter: CGFloat,
                             canvasSize: CGSize? = nil) {
        if let canvasSize { document.canvasSize = canvasSize }
        let idSet = Set(ids)
        let participants = document.layers.filter { idSet.contains($0.id) }.map(\.id)
        let frames = cellFrames(count: participants.count, in: document.canvasSize,
                                template: template, gutter: gutter)
        for (id, cell) in zip(participants, frames) {
            document.updateLayer(id: id) { layer in
                if case .image(let ref) = layer.content, cell.height > 0 {
                    let existing = layer.crop ?? CGRect(origin: .zero, size: ref.pixelSize)
                    layer.crop = fillCrop(of: existing, matchingAspect: cell.width / cell.height)
                }
                layer.frame = cell
                layer.transform = .identity
            }
        }
    }
}
