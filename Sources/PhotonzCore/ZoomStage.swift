import CoreGraphics
import Foundation

// Where a zoom is aimed: the part of a clip a person can SEE.
//
// The user, 2026-10-06: "The video was cropped. I position the zoom on some
// text. When I play it, rather than zooming in on the rect around text, it
// zooms way too far in, not matching at all what the rect was." The box had
// been measured against the clip's whole frame, and a crop leaves only part of
// that frame on screen: cropping the canvas leaves the frame hanging past its
// edges, and keyed crop edges draw the clip smaller than the frame it was laid
// out with. So the box said one percent and the zoom filled a frame nobody
// could see.
//
// A zoom now has two numbers that mean the same on any clip, cropped or not:
//
// * its SPOT (`ClipZoom.center`) is a point of the recording, as fractions of
//   the whole recording. It is nailed to what was recorded, so cropping the
//   clip afterwards leaves the zoom on the same text, and it is the unit the
//   recorder took the pointer and the clicks down in.
// * its SCALE is how far into the picture you can see it goes: 300% shows a
//   third of what is on screen across the whole of it.
//
// The stage is what turns those into a box at a moment: the part of the
// recording that is drawn (the clip's crop, keyed or not) and the part of that
// which is inside the canvas. The box is the visible picture's own shape, so
// filling the picture with it never stretches anything, exactly the rule an
// uncropped clip has always had.

/// The part of a clip's recording a person can see, at one moment.
public struct ZoomStage: Hashable, Sendable {
    /// The part of the recording the clip's picture holds (its crop), as
    /// fractions of the recording. The unit square for a clip not cropped.
    public var picture: CGRect
    /// The part of the clip's picture inside the canvas, as fractions of the
    /// picture. The unit square for a clip wholly on the canvas.
    public var visible: CGRect
    /// That same part, in document points. What the box is drawn over.
    public var onCanvas: CGRect

    public static let unit = CGRect(x: 0, y: 0, width: 1, height: 1)

    public init(picture: CGRect = ZoomStage.unit, visible: CGRect = ZoomStage.unit,
                onCanvas: CGRect = ZoomStage.unit) {
        self.picture = picture
        self.visible = visible
        self.onCanvas = onCanvas
    }

    /// A clip seen whole: every fraction of the stage is the same fraction of
    /// the recording. What a zoom was always measured against before.
    public static let whole = ZoomStage()

    /// The part of the recording a person can see, as fractions of it.
    public var seen: CGRect {
        CGRect(x: picture.minX + visible.minX * picture.width,
               y: picture.minY + visible.minY * picture.height,
               width: visible.width * picture.width,
               height: visible.height * picture.height)
    }

    /// A point of the recording as fractions of the picture seen.
    public func toStage(_ p: CGPoint) -> CGPoint {
        let s = seen
        guard s.width > 0, s.height > 0 else { return p }
        return CGPoint(x: (p.x - s.minX) / s.width, y: (p.y - s.minY) / s.height)
    }

    /// A point of the picture seen as fractions of the recording.
    public func fromStage(_ p: CGPoint) -> CGPoint {
        let s = seen
        return CGPoint(x: s.minX + p.x * s.width, y: s.minY + p.y * s.height)
    }

    /// A point of the recording as fractions of the clip's own picture, which
    /// is what the clip's frame is filled with.
    public func inPicture(_ p: CGPoint) -> CGPoint {
        guard picture.width > 0, picture.height > 0 else { return p }
        return CGPoint(x: (p.x - picture.minX) / picture.width, y: (p.y - picture.minY) / picture.height)
    }

    /// A point of the picture seen, in document points.
    public func onCanvas(_ p: CGPoint) -> CGPoint {
        let q = toStage(p)
        return CGPoint(x: onCanvas.minX + q.x * onCanvas.width, y: onCanvas.minY + q.y * onCanvas.height)
    }

    /// A box on the picture seen (fractions of it), in document points.
    public func onCanvas(_ box: CGRect) -> CGRect {
        CGRect(x: onCanvas.minX + box.minX * onCanvas.width, y: onCanvas.minY + box.minY * onCanvas.height,
               width: box.width * onCanvas.width, height: box.height * onCanvas.height)
    }

    /// A point of the document as fractions of the picture seen.
    public func stagePoint(fromDocument p: CGPoint) -> CGPoint? {
        guard onCanvas.width > 0, onCanvas.height > 0 else { return nil }
        return CGPoint(x: (p.x - onCanvas.minX) / onCanvas.width, y: (p.y - onCanvas.minY) / onCanvas.height)
    }

    /// The part of the clip's picture to fill its frame with, so that `window`
    /// (fractions of the picture SEEN) fills the part of the frame that is
    /// seen.
    ///
    /// The renderer fills the clip's whole frame with the window it is given,
    /// and only the visible part of that frame reaches the screen. So the
    /// window is grown about the visible part's own place in the frame: at
    /// the visible part's position V, a box B of the picture seen is drawn
    /// onto exactly V when the picture is cut at B less V's offset, scaled.
    /// With the whole frame visible this is the window itself.
    public func pictureWindow(forStageWindow window: CGRect) -> CGRect {
        let v = visible
        let inside = CGRect(x: v.minX + window.minX * v.width, y: v.minY + window.minY * v.height,
                            width: window.width * v.width, height: window.height * v.height)
        return CGRect(x: inside.minX - v.minX * window.width,
                      y: inside.minY - v.minY * window.height,
                      width: window.width, height: window.height)
    }

    /// The stage of a clip as it is drawn: `layer` with its motions applied,
    /// `origin` where its parents put it, `canvas` the document's size.
    public static func of(_ layer: Layer, origin: CGPoint = .zero, canvas: CGSize) -> ZoomStage {
        let frame = layer.frame.standardized.offsetBy(dx: origin.x, dy: origin.y)
        guard frame.width > 0, frame.height > 0 else { return .whole }
        var stage = ZoomStage(picture: layer.pictureInRecording, visible: unit, onCanvas: frame)
        let seen = frame.intersection(CGRect(origin: .zero, size: canvas))
        if !seen.isNull, seen.width > 0, seen.height > 0 {
            stage.onCanvas = seen
            stage.visible = CGRect(x: (seen.minX - frame.minX) / frame.width,
                                   y: (seen.minY - frame.minY) / frame.height,
                                   width: seen.width / frame.width, height: seen.height / frame.height)
        }
        return stage
    }
}

extension Layer {
    /// The part of the recording this clip's picture holds, as fractions of
    /// the recording: its crop, or all of it.
    public var pictureInRecording: CGRect {
        guard case .image(let ref) = content, let crop = crop?.standardized,
              ref.pixelSize.width > 0, ref.pixelSize.height > 0, crop.width > 0, crop.height > 0
        else { return ZoomStage.unit }
        return CGRect(x: crop.minX / ref.pixelSize.width, y: crop.minY / ref.pixelSize.height,
                      width: crop.width / ref.pixelSize.width, height: crop.height / ref.pixelSize.height)
    }
}

extension PhotonzDocument {

    /// The part of a clip's recording a person can see: at a moment of the
    /// document when given (keyed crop edges and keyed moves as they are
    /// then), otherwise as the clip is laid out. Nil for no such layer.
    public func zoomStage(ofClip id: UUID, atTimeMS ms: Int? = nil) -> ZoomStage? {
        let source: PhotonzDocument
        if let ms, hasTime {
            var unzoomed = self
            unzoomed.updateLayer(id: id) { $0.zooms = nil }
            source = unzoomed.drawn(atTimeMS: ms)
        } else {
            source = self
        }
        guard let layer = source.layer(id: id), let origin = source.parentOrigin(of: id) else { return nil }
        return ZoomStage.of(layer, origin: origin, canvas: canvasSize)
    }

    /// Every zoom written before zooms were aimed at what is seen, read the way
    /// it was drawn on screen then (`ClipZoom.aimedAtWhatIsSeen`). Its spot was
    /// fractions of the clip's own picture and its scale was against the clip's
    /// whole frame; now its spot is a point of the recording and its scale is
    /// against the part of the clip that is seen, so its box covers what it
    /// covered. A zoom on a clip that is not cropped reads exactly as it did.
    func aimingZoomsAtWhatIsSeen() -> PhotonzDocument {
        var document = self
        for layer in allLayers {
            guard let zooms = layer.zooms, zooms.contains(where: { $0.aimedAtWhatIsSeen != true }) else { continue }
            // What the box was drawn over: the clip as laid out, crop and all.
            let laidOut = zoomStage(ofClip: layer.id) ?? .whole
            let p = laidOut.picture
            let aimed: [ClipZoom] = zooms.map { zoom in
                guard zoom.aimedAtWhatIsSeen != true else { return zoom }
                // ...and what is seen where it plays, keyed crop edges and all.
                let start = layer.timelineSpanMS(of: zoom.id)?.start
                let seen = (start.flatMap { zoomStage(ofClip: layer.id, atTimeMS: $0) } ?? laidOut).seen
                var aimed = zoom
                aimed.center = CGPoint(x: p.minX + zoom.center.x * p.width, y: p.minY + zoom.center.y * p.height)
                // The box was 1/scale of the picture laid out across; it is
                // the same stretch of the recording now, against what is seen.
                if p.width > 0 {
                    aimed.scale = min(max(1, zoom.scale * Double(seen.width / p.width)), ClipZoom.mostScale)
                }
                aimed.aimedAtWhatIsSeen = true
                return aimed
            }
            document.updateLayer(id: layer.id) { $0.zooms = aimed }
        }
        return document
    }
}
