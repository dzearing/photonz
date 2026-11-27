// Which of the window's Core Animation layers come, go and change size from
// one frame to the next, by kind, for a speed walk's timeline measure.
//
// A drawn SwiftUI layer (RenderBox's `RBLayer`: a Canvas, drawn text, a
// shape) takes a piece of a surface it shares with others when it first
// draws or changes size, and gives it back when it goes. Both ask the window
// server whether an earlier frame is on screen yet, and a window server that
// is slow to answer holds the main thread for as long (task
// `no-frame-of-a-50-track-zoom-is-held-up-by-the-sy`, 2026-11-26). This
// counts how often a frame does either.
//
// Switched on by a file, like `PassSampler`:
//   mkdir -p /tmp/photonz-layer-census && touch /tmp/photonz-layer-census/on
// and written to /tmp/photonz-layer-census/census.txt.
//
// Probe builds only.
#if PHOTONZ_PLAYTEST
import AppKit
import ImageIO
import QuartzCore
import ScreenCaptureKit

@MainActor
final class LayerCensus {
    static let folder = "/tmp/photonz-layer-census"
    static var isOn: Bool { FileManager.default.fileExists(atPath: folder + "/on") }
    /// Film the timeline measure's zooms, for comparing what they drew
    /// before and after a change: `touch /tmp/photonz-layer-census/film`.
    /// Frames go to `<folder>/frames/<measure>-<n>.png`, a frame in four.
    static var films: Bool { FileManager.default.fileExists(atPath: folder + "/film") }

    /// Starts filming the window, or nil when it cannot.
    static func startFilm(_ host: NSWindow?) async -> (PlaytestWindowFilm, NSWindow, Bool)? {
        guard films, CGPreflightScreenCaptureAccess(), let host, let content = host.contentView else { return nil }
        let frame = host.frame
        let scale: CGFloat = 0.5
        let below = content.bounds.height - content.safeAreaInsets.top
        let crop = CGRect(x: 0, y: (frame.height - below) * scale, width: frame.width * scale,
                          height: below * scale).integral
        guard let shareable = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false),
              let window = shareable.windows.first(where: { $0.windowID == CGWindowID(host.windowNumber) })
        else { return nil }
        let hidden = host.alphaValue == 0
        if hidden { host.alphaValue = 1 }
        let camera = PlaytestWindowFilm(crop: crop)
        guard (try? await camera.start(window, size: CGSize(width: frame.width * scale, height: frame.height * scale))) != nil
        else { if hidden { host.alphaValue = 0 }; return nil }
        return (camera, host, hidden)
    }

    /// Stops it and writes a frame in four.
    static func endFilm(_ film: (PlaytestWindowFilm, NSWindow, Bool)?, label: String) async {
        guard let (camera, host, hidden) = film else { return }
        await camera.stop()
        if hidden { host.alphaValue = 0 }
        let dir = URL(fileURLWithPath: folder + "/frames")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let every = FileManager.default.fileExists(atPath: folder + "/film-all") ? 1 : 4
        for (n, frame) in camera.frames.enumerated() where n % every == 0 {
            guard let destination = CGImageDestinationCreateWithURL(
                dir.appendingPathComponent(String(format: "%@-%03d.png", label.replacingOccurrences(of: " ", with: "-"), n))
                    as CFURL, "public.png" as CFString, 1, nil) else { continue }
            CGImageDestinationAddImage(destination, frame.image, nil)
            CGImageDestinationFinalize(destination)
        }
    }

    private struct Seen {
        let kind: String
        let size: CGSize
        let owner: String
        let place: CGRect
    }
    private var shapes: [String: Int] = [:]
    private var last: [ObjectIdentifier: Seen] = [:]
    private var held: [CALayer] = []
    private var added: [String: Int] = [:]
    private var removed: [String: Int] = [:]
    private var resized: [String: Int] = [:]
    private var frames = 0
    private var framesWithDrawnChurn = 0
    private var drawnCount = 0

    /// What the window holds now, weighed against the last look.
    func look(_ window: NSWindow?) {
        guard let root = window?.contentView?.layer else { return }
        var now: [ObjectIdentifier: Seen] = [:]
        var keep: [CALayer] = []
        var drawn = 0
        func walk(_ layer: CALayer, owner: String) {
            let kind = String(describing: type(of: layer))
            var owner = owner
            if let view = layer.delegate as? NSView {
                var names: [String] = []
                var v: NSView? = view
                while let at = v, names.count < 4 {
                    let n = String(describing: type(of: at))
                    if !n.hasPrefix("_") || names.isEmpty { names.append(n) }
                    v = at.superview
                }
                owner = names.joined(separator: "<")
            }
            let place = layer.convert(layer.bounds, to: root)
            now[ObjectIdentifier(layer)] = Seen(kind: kind, size: layer.bounds.size, owner: owner, place: place)
            keep.append(layer)
            DrawnDisplays.watch(layer)
            if kind.contains("RB") { drawn += 1 }
            layer.sublayers?.forEach { walk($0, owner: owner) }
        }
        walk(root, owner: "root")
        defer {
            last = now
            held = keep
            drawnCount = drawn
        }
        guard !last.isEmpty else { return }
        frames += 1
        var churn = false
        for (id, seen) in now {
            let name = seen.kind + " in " + seen.owner
            let isDrawn = seen.kind.contains("RB") || seen.kind.contains("CGDrawing")
            if isDrawn, last[id] == nil || last[id]?.size != seen.size {
                let p = seen.place
                shapes[String(format: "%@%@ %.0fx%.0f at y %.0f", last[id] == nil ? "+" : "~", seen.kind,
                              seen.size.width.rounded(), seen.size.height.rounded(), p.minY.rounded()), default: 0] += 1
            }
            if let before = last[id] {
                if before.size != seen.size {
                    resized[name, default: 0] += 1
                    if seen.kind.contains("RB") { churn = true }
                }
            } else {
                added[name, default: 0] += 1
                if seen.kind.contains("RB") { churn = true }
            }
        }
        for (id, seen) in last where now[id] == nil {
            removed[seen.kind + " in " + seen.owner, default: 0] += 1
            if seen.kind.contains("RB") { churn = true }
        }
        if churn { framesWithDrawnChurn += 1 }
    }

    /// The tree of layers between two heights of the window, written once.
    func dump(_ window: NSWindow?, fromY: CGFloat, toY: CGFloat, name: String) {
        guard let root = window?.contentView?.layer else { return }
        var lines: [String] = []
        func walk(_ layer: CALayer, depth: Int) {
            let p = layer.convert(layer.bounds, to: root)
            if p.maxY >= fromY && p.minY <= toY {
                let contents = layer.contents.map { String(describing: type(of: $0 as AnyObject)) } ?? "-"
                lines.append(String(repeating: " ", count: depth) + String(format: "%@ %.0f,%.0f %.0fx%.0f subs %d contents %@ %@",
                    String(describing: type(of: layer)), p.minX, p.minY, p.width, p.height,
                    layer.sublayers?.count ?? 0, contents, layer.delegate.map { String(describing: type(of: $0)) } ?? ""))
            }
            layer.sublayers?.forEach { walk($0, depth: depth + 1) }
        }
        walk(root, depth: 0)
        try? lines.joined(separator: "\n").write(toFile: Self.folder + "/" + name, atomically: true, encoding: .utf8)
    }

    init() {
        WindowServerAsks.install()
        _ = WindowServerAsks.take()
        _ = DrawnDisplays.take()
    }

    /// A line for the measure, and the counts start again.
    func take(_ label: String) -> String {
        let asks = WindowServerAsks.take()
        func top(_ d: [String: Int]) -> String {
            d.sorted { $0.value > $1.value }.prefix(6).map { "\($0.key) \($0.value)" }.joined(separator: ", ")
        }
        let line = String(format: "%@: asked the window server %d times (%d on the main thread, %d over 4 ms, worst %.1f ms, %.0f ms in all); ",
                          label, asks.asks, asks.onMain, asks.slow, asks.worstMS, asks.totalMS)
            + DrawnDisplays.take() + "; \(frames) frames, \(framesWithDrawnChurn) with a drawn layer added, removed or resized; "
            + "\(drawnCount) drawn layers; added [\(top(added))]; removed [\(top(removed))]; resized [\(top(resized))]; shapes [\(shapes.sorted { $0.value > $1.value }.prefix(25).map { "\($0.key): \($0.value)" }.joined(separator: ", "))]"
        shapes = [:]
        added = [:]; removed = [:]; resized = [:]; frames = 0; framesWithDrawnChurn = 0
        last = [:]; held = []
        if let data = (line + "\n").data(using: .utf8) {
            let url = URL(fileURLWithPath: Self.folder + "/census.txt")
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
        return line
    }
}
#endif

#if PHOTONZ_PLAYTEST
import ObjectiveC
import os

/// Every time anything in the app asks the window server whether a frame is
/// on screen yet (`-[CAContext waitForCommitId:timeout:]`, which RenderBox
/// calls when a drawn layer takes or gives back a piece of its shared
/// surface), counted and timed, for `LayerCensus`. Probe builds only, and
/// only while the census is on.
enum WindowServerAsks {
    struct Tally: Sendable {
        var asks = 0
        var onMain = 0
        var slow = 0
        var worstMS: Double = 0
        var totalMS: Double = 0
    }
    private static let tally = OSAllocatedUnfairLock(initialState: Tally())
    private static let installed = OSAllocatedUnfairLock(initialState: false)

    static func install() {
        guard installed.withLock({ was in defer { was = true }; return !was }) else { return }
        let selector = NSSelectorFromString("waitForCommitId:timeout:")
        guard let type = NSClassFromString("CAContext"),
              let method = class_getInstanceMethod(type, selector) else { return }
        typealias Wait = @convention(c) (AnyObject, Selector, UInt32, Double) -> Bool
        let original = unsafeBitCast(method_getImplementation(method), to: Wait.self)
        let block: @convention(block) (AnyObject, UInt32, Double) -> Bool = { context, id, timeout in
            let began = CACurrentMediaTime()
            let answer = original(context, selector, id, timeout)
            let ms = (CACurrentMediaTime() - began) * 1000
            let main = Thread.isMainThread
            tally.withLock { t in
                t.asks += 1
                if main { t.onMain += 1 }
                if ms > 4 { t.slow += 1 }
                t.worstMS = max(t.worstMS, ms)
                t.totalMS += ms
            }
            if main { DrawnDisplays.asked(ms: ms) }
            return answer
        }
        method_setImplementation(method, imp_implementationWithBlock(block))
    }

    static func take() -> Tally {
        tally.withLock { t in defer { t = Tally() }; return t }
    }
}
#endif

#if PHOTONZ_PLAYTEST
/// Each drawn layer's display, by what it is and where, with the window
/// server asks made inside it, for `LayerCensus`.
enum DrawnDisplays {
    struct Count: Sendable {
        var displays = 0
        var asks = 0
        var askMS: Double = 0
    }
    struct State: Sendable {
        var current: String?
        var byLayer: [String: Count] = [:]
        var swizzled: Set<String> = []
    }
    static let state = OSAllocatedUnfairLock(initialState: State())

    /// Counts the displays of this layer's class from now on.
    static func watch(_ layer: CALayer) {
        guard let type = object_getClass(layer) else { return }
        let name = NSStringFromClass(type)
        guard name.contains("RB") || name.contains("CGDrawing") else { return }
        guard state.withLock({ s in s.swizzled.insert(name).inserted }) else { return }
        let selector = #selector(CALayer.display)
        guard let method = class_getInstanceMethod(type, selector),
              let types = method_getTypeEncoding(method) else { return }
        typealias Display = @convention(c) (AnyObject, Selector) -> Void
        let original = unsafeBitCast(method_getImplementation(method), to: Display.self)
        let block: @convention(block) (AnyObject) -> Void = { object in
            guard let layer = object as? CALayer, Thread.isMainThread else {
                original(object, selector)
                return
            }
            let outer = state.withLock { s in s.current == nil }
            if outer {
                var root = layer
                while let up = root.superlayer { root = up }
                let place = layer.convert(layer.bounds, to: root)
                let key = String(format: "%@ %.0fx%.0f at y %.0f", NSStringFromClass(object_getClass(layer) ?? CALayer.self),
                                 place.width, place.height, place.minY)
                state.withLock { s in
                    s.current = key
                    s.byLayer[key, default: Count()].displays += 1
                }
            }
            original(object, selector)
            if outer { state.withLock { s in s.current = nil } }
        }
        class_replaceMethod(type, selector, imp_implementationWithBlock(block), types)
    }

    /// An ask made on the main thread, put down to the layer displaying.
    static func asked(ms: Double) {
        state.withLock { s in
            guard let key = s.current else { return }
            s.byLayer[key, default: Count()].asks += 1
            s.byLayer[key, default: Count()].askMS += ms
        }
    }

    static func take() -> String {
        let byLayer = state.withLock { s in defer { s.byLayer = [:] }; return s.byLayer }
        let total = byLayer.values.reduce(0) { $0 + $1.displays }
        return "\(total) drawn displays [" + byLayer.sorted { ($0.value.asks, $0.value.displays) > ($1.value.asks, $1.value.displays) }
            .prefix(20).map { String(format: "%@: %d shown, %d asks %.0fms", $0.key, $0.value.displays, $0.value.asks, $0.value.askMS) }
            .joined(separator: ", ") + "]"
    }
}
#endif
