import AppKit
import PhotonzCore

/// Where Preview as Web Page wrote its page, and what it was asked about.
struct WebPreview {
    var url: URL
    /// The layer it was asked about: the frame it is or lives in is what the
    /// page shows, else the whole drawing (`CompositeCopy.svgCopyTarget`).
    var layerID: UUID?
    /// What an agent asked for instead of the drawing's own choice.
    var playback: SVGPlayback?
}

/// **Preview as Web Page**: the drawing as an icon on a small web page, opened
/// in the default browser, so an animated icon can be tried the way it will be
/// used: in a button that plays it on hover, at real sizes, on light and dark
/// (`SVGPreviewPage`). The page is rewritten as the drawing changes, so the
/// page's Refresh shows it as it is now.
extension EditorState {

    /// The same drawings Copy SVG copies: a page of pixels would show nothing
    /// an image viewer does not.
    func canPreviewWebPage(around layerID: UUID?) -> Bool {
        canCopySVG(around: layerID)
    }

    /// Writes the page and opens it. Answers where it went, or nil when there
    /// is no drawing to show.
    @discardableResult
    func previewWebPage(around layerID: UUID?, playback: SVGPlayback? = nil,
                        opening: Bool = true, to path: URL? = nil) -> URL? {
        guard canPreviewWebPage(around: layerID),
              let url = writeWebPreview(around: layerID, playback: playback,
                                        to: path ?? webPreview?.url)
        else { return nil }
        webPreview = WebPreview(url: url, layerID: layerID, playback: playback)
        // A walk never puts a browser in front of the person at the Mac.
        if opening, !Self.webPreviewUnderAWalk { NSWorkspace.shared.open(url) }
        return url
    }

    private static var webPreviewUnderAWalk: Bool {
        #if PHOTONZ_PLAYTEST
        PlaytestHarness.isDrivingAWalk
        #else
        false
        #endif
    }

    /// The page's HTML for the drawing around `layerID`, as the document's
    /// own Export choices say it plays and colours itself.
    func webPreviewHTML(around layerID: UUID?, playback: SVGPlayback? = nil) -> String? {
        guard let document else { return nil }
        let target = CompositeCopy.svgCopyTarget(in: document, around: layerID)
        // The file before the choices, which the page applies itself so it
        // can show the chosen one and a copy going round beside it.
        guard let svg = clipboardSVG(of: target, background: copyBackground, playback: .standard)
        else { return nil }
        return SVGPreviewPage.html(svg: svg, name: webPreviewName(around: layerID),
                                   playback: playback ?? document.svgPlayback)
    }

    private func webPreviewName(around layerID: UUID?) -> String {
        guard let document else { return "Icon" }
        let frame = CompositeCopy.svgCopyName(in: document, around: layerID)
        if !frame.isEmpty { return frame }
        return documentURL?.deletingPathExtension().lastPathComponent ?? "Icon"
    }

    private func writeWebPreview(around layerID: UUID?, playback: SVGPlayback?,
                                 to existing: URL?) -> URL? {
        guard let html = webPreviewHTML(around: layerID, playback: playback) else { return nil }
        let url: URL
        if let existing {
            url = existing
        } else {
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("Photonz Preview", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let safe = webPreviewName(around: layerID)
                .components(separatedBy: CharacterSet(charactersIn: "/:\\\\?%*|\"<>"))
                .joined(separator: "-")
            url = folder.appendingPathComponent("\(safe) \(UUID().uuidString.prefix(6)).html")
        }
        do {
            try Data(html.utf8).write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// Rewrites the open page a moment after the drawing stops changing, so a
    /// drag does not write it sixty times a second.
    func rewriteWebPreviewSoon() {
        webPreviewRewrite?.cancel()
        webPreviewRewrite = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self, let preview = self.webPreview else { return }
            _ = self.writeWebPreview(around: preview.layerID, playback: preview.playback,
                                     to: preview.url)
        }
    }
}
