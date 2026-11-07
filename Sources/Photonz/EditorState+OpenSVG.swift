import AppKit
import Foundation
import PhotonzCore
import PhotonzRender

// File ▸ Open, the app icon and the Finder's Open With on an SVG
// (`SVGOpening`): a document at the drawing's own size, its shapes on layers.
// ImageIO reads no SVG, so until this the file came back as nothing and the
// window stayed empty without a word.
extension EditorState {

    /// What the last file turned down was and why: what the alert said, kept
    /// so a walk, which gets no alert, can read it.
    @MainActor static var lastOpenRefusal: (file: String, message: String)?

    /// Opens the SVG at `url` here, or says why not.
    ///
    /// `keepingTheWindow` is for a window somebody already had: one opened for
    /// this file goes again with the file, rather than staying up empty.
    func openSVG(at url: URL, keepingTheWindow: Bool = false) {
        guard let data = try? Data(contentsOf: url) else {
            return refuseOpening(url, because: SVGOpening.missingMessage, keepingTheWindow: keepingTheWindow)
        }
        let name = url.deletingPathExtension().lastPathComponent
        switch SVGOpening.read(data, named: name) {
        case .success(let opening) where opening.leftOut.isEmpty:
            installSVG(opening, from: url) { opening.document(on: $0) }
        case .success(let opening):
            // Shapes alone would lose part of it, so it comes in whole.
            if let art = VectorArt.read(data) {
                installPicture(of: art, opening.knowsItsSize ? opening : SVGOpening(pictureOfSize: art.size),
                               named: name, from: url)
            } else if opening.layers.isEmpty {
                refuseOpening(url, because: SVGOpening.unreadableMessage, keepingTheWindow: keepingTheWindow)
            } else {
                installSVG(opening, from: url) { opening.document(on: $0) }
                raiseCanvasNotice(.svgOpenedInPart)
            }
        case .failure(let error):
            // Broken as this reader sees it, and macOS may still draw it: an
            // Illustrator file's entities are the usual case.
            if error.message != SVGOpening.nothingDrawnMessage, let art = VectorArt.read(data) {
                installPicture(of: art, SVGOpening(pictureOfSize: art.size), named: name, from: url)
            } else {
                refuseOpening(url, because: error.message, keepingTheWindow: keepingTheWindow)
            }
        }
    }

    private func installPicture(of art: VectorArt, _ opening: SVGOpening, named name: String, from url: URL) {
        guard let picture = store.register(art) else {
            return refuseOpening(url, because: SVGOpening.unreadableMessage, keepingTheWindow: true)
        }
        installSVG(opening, from: url) { opening.pictureDocument(of: picture, named: name, on: $0) }
        raiseCanvasNotice(.svgOpenedAsAPicture)
    }

    /// The document on the white a blank canvas has, which Export leaves out
    /// of a file unless it is asked to keep it.
    private func installSVG(_ opening: SVGOpening, from url: URL, _ make: (ImageRef) -> PhotonzDocument) {
        guard let white = SolidImage.make(size: opening.canvasSize, hex: Self.blankCanvasBackgroundHex) else {
            return refuseOpening(url, because: SVGOpening.missingMessage, keepingTheWindow: true)
        }
        installDocument(make(store.register(white)), url: nil)
        // Never `documentURL`: Save writes a Photonz document, not over the SVG.
        openedFileURL = url
    }

    /// Says in plain words why `url` did not open, and takes away the window
    /// that was opened for it. The window exists before the file is read, and
    /// a person looking at an empty one has nothing to tell them it failed.
    private func refuseOpening(_ url: URL, because why: String, keepingTheWindow: Bool) {
        let file = url.lastPathComponent
        Task { @MainActor [weak self] in
            // A beat, for SwiftUI to finish the window this is being read in.
            try? await Task.sleep(for: .milliseconds(150))
            Self.lastOpenRefusal = (file, why)
            if !Self.isDrivingAWalk {
                AppFront.activate()
                let alert = NSAlert()
                alert.messageText = "“\(file)” could not be opened"
                alert.informativeText = why
                alert.runModal()
            }
            guard let self, !keepingTheWindow, self.document == nil else { return }
            self.hostWindow?.close()
        }
    }

    /// Nothing can answer an alert under a walk, so one would hang it.
    private static var isDrivingAWalk: Bool {
        #if PHOTONZ_PLAYTEST
        PlaytestHarness.isDrivingAWalk
        #else
        false
        #endif
    }
}
