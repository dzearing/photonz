import CoreGraphics
import Foundation

// Putting a picked text on a picked path, reshaping the curve after, and
// setting where along it the words start (`TextOnPath.swift`).

extension Layer {

    /// The curve a press on the canvas reshapes on this layer: a path's own
    /// outline, or the curve words are set along. Nil for everything else.
    ///
    /// The one place the canvas asks, so the points, the levers, a point
    /// added on the line and a point taken away all work on words on a curve
    /// exactly as they work on a path, with nothing in the canvas knowing
    /// which of the two it has hold of.
    public var reshapablePath: PathContent? {
        if let path { return path }
        return text?.onPath?.guide
    }

    /// Words on a curve with their box made `frame`: the curve scales into
    /// the new box the way a path does, and the type keeps its size, the way
    /// Illustrator resizes type on a path.
    func resizedOnPath(to frame: CGRect) -> Layer {
        guard var words = text, var onPath = words.onPath else { return self }
        let box = frame.standardized
        let was = self.frame.standardized
        let sx = was.width > 0 ? box.width / was.width : 1
        let sy = was.height > 0 ? box.height / was.height : 1
        onPath.guide = onPath.guide.scaled(x: sx, y: sy)
        words.onPath = onPath
        var resized = self
        resized.content = .text(words)
        resized.frame = box
        return resized
    }
}

extension PhotonzDocument {

    /// The one text and the one path in `ids`, when that is exactly what is
    /// picked and both can be changed. Nil for any other pick, which is what
    /// keeps Put Text on a Path dimmed until it has the two things it needs.
    public func textAndPath(in ids: Set<UUID>) -> (text: UUID, path: UUID)? {
        guard ids.count == 2 else { return nil }
        let layers = ids.compactMap { layer(id: $0) }
        guard layers.count == 2, layers.allSatisfy({ !$0.isLocked }),
              let text = layers.first(where: { $0.text != nil }),
              let path = layers.first(where: { $0.path != nil }),
              text.id != path.id,
              let content = path.path, content.anchors.count >= 2 else { return nil }
        return (text.id, path.id)
    }

    /// Sets the words of `textID` along the curve of `pathID`, in one change.
    ///
    /// The curve goes INTO the text, the way Photoshop's type on a path owns
    /// its path: the path layer is gone afterwards and its points are the
    /// text's to reshape. The words keep their font, colour, effects and slot
    /// in the stack; the text's box becomes the curve's box, so the selection
    /// sits round the curve the words are on. A turned path is put on as it
    /// looks, its turn baked into the curve, and the words then stand upright
    /// to that curve rather than carrying a turn of their own.
    @discardableResult
    public mutating func putTextOnPath(textID: UUID, pathID: UUID) -> Bool {
        guard textAndPath(in: [textID, pathID]) != nil,
              let pathLayer = layer(id: pathID), let content = pathLayer.path,
              let pathOrigin = parentOrigin(of: pathID),
              let textOrigin = parentOrigin(of: textID) else { return false }
        // The curve on the canvas: its own corner, its parents' corners, and
        // any turn or flip it wears.
        var curve = content.offsetBy(dx: pathLayer.frame.origin.x + pathOrigin.x,
                                     dy: pathLayer.frame.origin.y + pathOrigin.y)
        if !pathLayer.transform.isIdentity {
            let frame = pathLayer.frame.offsetBy(dx: pathOrigin.x, dy: pathOrigin.y)
            curve = curve.transformed(by: pathLayer.transform.affineTransform(
                around: CGPoint(x: frame.midX, y: frame.midY)))
        }
        // Only the line matters: nothing of the path's paint is ever drawn.
        curve.fill = nil
        curve.trim = nil
        let box = curve.bounds
        let guide = curve.offsetBy(dx: -box.minX, dy: -box.minY)
        let start = layer(id: textID)?.text?.onPath?.startPercent ?? 0
        updateLayer(id: textID) { edited in
            guard var words = edited.text else { return }
            words.onPath = TextOnPath(guide: guide, startPercent: start)
            edited.content = .text(words)
            edited.frame = CGRect(x: box.minX - textOrigin.x, y: box.minY - textOrigin.y,
                                  width: box.width, height: box.height)
            edited.transform = .identity
        }
        removeLayers(ids: [pathID])
        return true
    }

    /// Where along its curve a text's words start at `ms`, as a percent of
    /// the curve's length, or nil for words not on a curve.
    public func textPathStart(layerID: UUID, atDocumentTimeMS ms: Int) -> Double? {
        guard let layer = layer(id: layerID), let onPath = layer.text?.onPath else { return nil }
        if layer.keyedMotion(.pathStart) != nil,
           case let .number(number)? = keyedValue(layerID: layerID, .motion(.pathStart), atDocumentTimeMS: ms) {
            return number
        }
        return onPath.startPercent
    }

    /// Sets Start on each of `ids` that is on a curve: a key at `ms` where
    /// Start is keyed, the text's own value otherwise.
    public mutating func setTextPathStart(_ value: Double, layerIDs ids: [UUID],
                                          atDocumentTimeMS ms: Int, ease: KeyEase? = nil) {
        guard value.isFinite else { return }
        let start = min(max(value, TextOnPath.startRange.lowerBound), TextOnPath.startRange.upperBound)
        for id in ids {
            guard let layer = layer(id: id), !layer.isLocked, layer.text?.onPath != nil else { continue }
            if hasTime, layer.keyedMotion(.pathStart) != nil {
                setKeyedValue(.number(start), layerID: id, .motion(.pathStart), atDocumentTimeMS: ms, ease: ease)
            } else {
                updateLayer(id: id) { $0.setKeyStill(.pathStart, .number(start)) }
            }
        }
    }
}
