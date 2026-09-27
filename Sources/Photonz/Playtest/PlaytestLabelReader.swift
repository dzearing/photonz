// Reads the words off a picture of the window, for `labelsWhole`.
//
// A cut label is a fact about pixels: SwiftUI draws "Write Ag…" and nothing in
// the view tree says the words did not fit. So the walk reads the window the
// way a person does, on this Mac with Vision, and `CutLabelRule` decides which
// of the words were cut short.
//
// Probe builds only.
#if PHOTONZ_PLAYTEST
import AppKit
import PhotonzCore
import Vision

enum PlaytestLabelReader {
    /// Every run of words in `rep`, a picture of a view `size` across, in that
    /// view's points, top-left origin. `panel` is the properties panel's frame
    /// in the same points, when it is known.
    ///
    /// Read a piece at a time: Vision reads a whole 3456-pixel window's 10pt
    /// labels badly ("Kewnle" for Rewrite) and the same labels cropped to the
    /// panel exactly. So the panel is one piece and the window is cut into
    /// overlapping columns, each read on its own.
    static func read(_ rep: NSBitmapImageRep, size: CGSize, panel: CGRect?) throws -> [CutLabelRule.Reading] {
        guard let image = rep.cgImage, size.width > 0, size.height > 0 else { return [] }
        let scale = CGFloat(image.width) / size.width
        var pieces: [CGRect] = []
        let panel = panel.flatMap { $0.width > 40 ? $0.intersection(CGRect(origin: .zero, size: size)) : nil }
        if let panel { pieces.append(panel) }
        // The columns cross the whole window, the timeline under the panel
        // included; what they read inside the panel is left to the panel's
        // own, better, reading.
        let column: CGFloat = 560, stride: CGFloat = 420
        var x: CGFloat = 0
        while x < size.width {
            pieces.append(CGRect(x: x, y: 0, width: min(column, size.width - x), height: size.height))
            if x + column >= size.width { break }
            x += stride
        }
        var readings: [CutLabelRule.Reading] = []
        for (index, piece) in pieces.enumerated() {
            let pixels = CGRect(x: piece.minX * scale, y: piece.minY * scale,
                                width: piece.width * scale, height: piece.height * scale).integral
            guard let crop = image.cropping(to: pixels) else { continue }
            let isPanel = panel != nil && index == 0
            for reading in try read(crop, size: piece.size) {
                let frame = reading.frame.offsetBy(dx: piece.minX, dy: piece.minY)
                if !isPanel, let panel, panel.contains(CGPoint(x: frame.midX, y: frame.midY)) { continue }
                // Columns overlap, so the same words can be read twice.
                if readings.contains(where: { $0.text == reading.text
                    && abs($0.frame.midX - frame.midX) < 6 && abs($0.frame.midY - frame.midY) < 6 }) { continue }
                readings.append(CutLabelRule.Reading(text: reading.text, frame: frame))
            }
        }
        return readings
    }

    private static func read(_ image: CGImage, size: CGSize) throws -> [CutLabelRule.Reading] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Correction would "fix" a cut word back into a whole one.
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let box = observation.boundingBox
            return CutLabelRule.Reading(
                text: text,
                frame: CGRect(x: box.minX * size.width, y: (1 - box.maxY) * size.height,
                              width: box.width * size.width, height: box.height * size.height))
        }
    }
}
#endif
