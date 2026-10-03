import AppKit
import PhotonzCore
import SwiftUI

/// Builds the editor once, out of sight, while the app launches, so the first
/// window somebody opens is as quick as the ones after it.
///
/// The first editor window of a run used to show its picture about 300 ms
/// later than the next one (450 to 600 ms after Stop for a recording opened at
/// Stop, against 160 to 190). Time Profiler put most of it in Swift working out
/// the editor's view types for the first time (`swift_getTypeByMangledName`
/// under SwiftUI's first build of the tree), and the rest in the first render
/// of that tree into a window: its layers, glass, symbols and canvas. All of
/// that is done once per process, whoever asks for it, so it is asked for here,
/// at launch, where the app is a menu-bar icon with nothing on screen.
///
/// The editor is built in a window that is never ordered in, the way a window
/// opening on a recording is built: empty first, then holding a recording.
/// Then the window is emptied and dropped. Nothing is shown: no window, no
/// panel, and the activation policy is never touched, so no Dock icon. The
/// throwaway editor is never seeded and its canvas never adopts the window
/// (`EditorState.isWarmUp`), so nothing that lists open editors ever sees it.
///
/// What it does not buy back: a window opened while no other editor window is
/// open still pays for the app turning from a menu-bar agent into a Dock app,
/// about 100 ms more than opening one beside a window already open, and that
/// is the same for the first window of a run and any later one.
@MainActor
enum EditorWarmUp {
    private static var done = false

    /// Once per launch, before anything else can ask for a window. Costs about
    /// a third of a second of launch.
    static func run(coordinator: AppCoordinator) {
        guard !done else { return }
        done = true
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = NSRect(x: screen.minX, y: screen.minY,
                           width: min(1200, screen.width), height: min(800, screen.height))
        let editor = EditorState()
        editor.isWarmUp = true
        let window = NSWindow(contentRect: frame,
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isExcludedFromWindowsMenu = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.contentView = NSHostingView(rootView: EditorView()
            .equatable()
            .environment(editor)
            .environment(coordinator))
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        editor.holdWarmUpRecording()
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        window.contentView = nil
    }
}

extension EditorState {
    /// What the warm-up editor holds: a recording, the heaviest thing a window
    /// opens on, standing in for a file the way a recording opened at Stop
    /// does (`EditorState+ClosingRecording`), with one small frame to draw. No
    /// recording URL, so nothing is ever remembered about where its playhead
    /// was.
    fileprivate func holdWarmUpRecording() {
        let movie = MovieRef(id: UUID(), pixelSize: CGSize(width: 1920, height: 1080),
                             durationMS: 3000, hasSound: true)
        var document = PhotonzDocument.recording(movie, name: "Recording")
        document.rememberMedia(.recording(movie), named: "Recording.mov")
        installDocument(document, url: nil)
        markSaved()
        guard let frame = Self.warmUpFrame() else { return }
        for request in document.movieFrames(atTimeMS: 0) { movieFrames.hold(frame, for: request) }
    }

    private static func warmUpFrame() -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: 192, height: 108, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(gray: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 192, height: 108))
        return context.makeImage()
    }
}
