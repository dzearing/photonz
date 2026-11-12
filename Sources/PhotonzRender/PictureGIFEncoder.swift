import CoreGraphics
import Foundation
import ImageIO
import PhotonzCore
import UniformTypeIdentifiers

/// **Writes a moving picture as a GIF** (task `an-animated-picture-exports-as-a-gif`).
///
/// Every moment `PictureGIF` names is drawn the way the canvas draws it while
/// the picture plays (`PhotonzDocument.moved(toMotionTimeMS:)`), so the file
/// and the timeline play the same loop. A GIF that goes round for ever says so
/// in the file; one that plays once has no loop block, which every reader
/// (Safari, Chrome, Preview, Quick Look) takes as "play once and hold".
public enum PictureGIFEncoder {

    /// The file, or nil for a picture with nothing moving in it.
    ///
    /// `background` is the Export sheet's Include the background, exactly as a
    /// PNG takes it: leaving the canvas out writes a GIF whose empty pixels are
    /// see-through.
    public static func data(of document: PhotonzDocument, frameID: UUID?, scale: CGFloat,
                            background: SVGExport.Background,
                            renderer: DocumentRenderer, store: ImageStore,
                            onFrame: ((Int) -> Void)? = nil) -> Data? {
        // The same scoping a still export uses, so a frame on its own is that
        // frame's box and nothing else.
        let scoped = document.exportTarget(frameID: frameID)
        guard let plan = PictureGIF.plan(for: scoped) else { return nil }
        // Reading which bitmaps are flat walks their pixels, so it is done
        // once for the whole file rather than once a frame: a motion moves
        // layers, never what is inside a bitmap.
        let flat = background != .keep ? FlatBitmap.colors(in: scoped, store: store) : [:]
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.gif.identifier as CFString, plan.timesMS.count, nil) else { return nil }
        if plan.loops {
            CGImageDestinationSetProperties(destination, [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
            ] as CFDictionary)
        }
        var wroteAny = false
        var owed = 0
        for (index, ms) in plan.timesMS.enumerated() {
            // A moment that could not be drawn hands its time to the next, so
            // the file still runs as long as the loop.
            owed += plan.delaysInHundredths[index]
            onFrame?(index)
            let moved = scoped.moved(toMotionTimeMS: ms)
            let drawn = background != .keep ? moved.drawn(with: background, flatImages: flat) : moved
            guard let picture = renderer.render(drawn, store: store, scale: scale) else { continue }
            CGImageDestinationAddImage(destination, picture, [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFUnclampedDelayTime: Double(owed) / 100,
                    kCGImagePropertyGIFDelayTime: Double(owed) / 100,
                ]
            ] as CFDictionary)
            owed = 0
            wroteAny = true
        }
        guard wroteAny, CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
