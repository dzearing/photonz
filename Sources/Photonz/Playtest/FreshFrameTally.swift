// The canvas's picture against the same document drawn from scratch, read on
// every move of a drag (`drag` with `expectFresh`). The canvas patches its
// picture in place as things move, so a part it forgets to draw again keeps
// what an earlier frame put there: a lens dragged over a screenshot left a
// stair-stepped grey trail behind it on 2026-10-12. A fresh render has no
// earlier frame, so anything left behind reads as pixels that differ.
//
// Probe builds only.
#if PHOTONZ_PLAYTEST
import AppKit
import PhotonzCore
import PhotonzRender

@MainActor
final class FreshFrameTally {
    private struct Kept {
        let moment: String
        let shown: CGImage
        let drawn: PhotonzDocument
        let pictures: ImageStore
        let scale: CGFloat
        let colors: CGColorSpace?
    }

    private struct Look {
        let moment: String
        let share: Double
        let shown: CGImage
        let fresh: CGImage
    }

    /// Frames kept while the hand moves, compared once it has let go: drawing
    /// a fresh copy on every move would slow the hand down to the renderer's
    /// pace, and the frames a quick hand makes the canvas skip are part of
    /// what is being checked.
    private var kept: [Kept] = []
    private var looks: [Look] = []
    /// Frames already kept, so a move that brought no new frame is not
    /// counted twice.
    private var seen: Set<ObjectIdentifier> = []
    private var worst: Look?
    /// Enough to cover a drag without holding a recording's worth of frames.
    private let most = 40

    /// Keeps the frame the canvas has now, with the very document and
    /// pictures it was drawn from.
    func sample(_ editor: EditorState, moment: String) {
        guard kept.count < most, let shown = editor.renderedImage, let drawn = editor.shownDrawnDocument,
              let full = editor.document?.canvasSize, full.width > 0 else { return }
        guard seen.insert(ObjectIdentifier(shown)).inserted else { return }
        // A recording is composited at the size it is shown, and the document
        // that frame was drawn from already carries that size.
        kept.append(Kept(moment: moment, shown: shown, drawn: drawn, pictures: editor.store.snapshot(),
                         scale: drawn.canvasSize.width / full.width, colors: editor.canvasColorSpace))
    }

    /// Draws every kept frame's document again from scratch and compares.
    func compare() async {
        for frame in kept {
            let fresh = await Task.detached(priority: .userInitiated) {
                DocumentRenderer().renderInteractive(frame.drawn, store: frame.pictures,
                                                     contentScale: frame.scale, colorSpace: frame.colors)
            }.value
            guard let fresh else { continue }
            let share = FrameAgreement.differingShare(Self.bytes(frame.shown), Self.bytes(fresh))
            let look = Look(moment: frame.moment, share: share, shown: frame.shown, fresh: fresh)
            looks.append(look)
            if share > (worst?.share ?? -1) { worst = look }
        }
        kept = []
    }

    /// Nil when every frame read stayed within `bound` (a share, 0 to 1).
    func failure(bound: Double) -> String? {
        guard !looks.isEmpty else {
            return "no frame came in while this drag ran, so nothing was compared with a fresh render"
        }
        let over = looks.filter { $0.share > bound }
        guard !over.isEmpty else { return nil }
        let named = over.prefix(6).map { "\($0.moment) \(Self.percent($0.share))" }.joined(separator: ", ")
        return "\(over.count) of \(looks.count) frames differ from the same document drawn from scratch "
            + "by more than \(Self.percent(bound)): \(named). The worst is written as -shown.png and "
            + "-fresh.png beside this walk's pictures"
    }

    var reading: String {
        let worstShare = looks.map(\.share).max() ?? 0
        return "\(looks.count) frames compared with a fresh render, worst \(Self.percent(worstShare)) differing"
    }

    func writeWorst(to directory: URL, name: String) throws {
        guard let worst else { return }
        for (image, suffix) in [(worst.shown, "shown"), (worst.fresh, "fresh")] {
            guard let data = ImageCodec.encode(image, format: .png) else { continue }
            try data.write(to: directory.appendingPathComponent("\(name)-\(suffix).png"))
        }
    }

    private static func percent(_ share: Double) -> String { String(format: "%.2f%%", share * 100) }

    /// Four bytes a pixel in sRGB, so frames written in the window's colours
    /// and frames written in sRGB compare like for like.
    private static func bytes(_ image: CGImage) -> [UInt8] {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        data.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return data
    }
}
#endif
