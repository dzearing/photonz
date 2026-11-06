#!/usr/bin/env swift
// An animated SVG as a browser plays it: the file is opened in WebKit (Safari's
// engine), its clock stopped and moved to each moment, and each moment
// photographed, so what is judged is the file that leaves the app.
//
//   swift Scripts/ask-eval/svg-frames.swift <out.png> <file.svg> <lapSeconds> [--frames 16] [--gif <out.gif>]
//
// Prints one line of JSON: how far the frames differ from each other (moves),
// how far the last moment of the lap is from the first (seam), and how many
// moments are blank.
import AppKit
import ImageIO
import UniformTypeIdentifiers
import WebKit

enum Run {
    static let arguments = CommandLine.arguments
    static func option(_ name: String) -> String? {
        arguments.firstIndex(of: name).flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
    }
    static let out = arguments[1]
    static let lap = Double(arguments[3]) ?? 1
    static let count = Int(option("--frames") ?? "") ?? 16
    static let gif = option("--gif")
    static let side = 240
    static let svg = (try? String(contentsOfFile: arguments[2], encoding: .utf8)) ?? ""
}
guard Run.arguments.count >= 4, !Run.svg.isEmpty else {
    print("usage: svg-frames.swift <out.png> <file.svg> <lapSeconds> [--frames n] [--gif out.gif]")
    exit(2)
}

@MainActor final class Film: NSObject, WKNavigationDelegate {
    let view = WKWebView(frame: NSRect(x: 0, y: 0, width: Run.side, height: Run.side))
    var frames: [CGImage] = []
    var moments: [Double] = []
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: Run.side, height: Run.side), styleMask: [.borderless], backing: .buffered, defer: false)

    func start() {
        // On screen, or WebKit never paints; behind everything and all but
        // see-through, so nobody at the Mac notices it.
        window.contentView = view
        window.level = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 1)
        window.alphaValue = 0.01
        window.ignoresMouseEvents = true
        window.orderBack(nil)
        view.navigationDelegate = self
        let page = """
        <!doctype html><html><body style="margin:0;background:#fff">
        <div style="width:\(Run.side)px;height:\(Run.side)px">\(Run.svg)</div>
        <script>const s=document.querySelector('svg');s.setAttribute('width','\(Run.side)');s.setAttribute('height','\(Run.side)');s.pauseAnimations();</script>
        </body></html>
        """
        view.loadHTMLString(page, baseURL: nil)
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in await self.shoot() }
    }

    func shoot() async {
        // The last moment stands just short of the lap's end: the end itself
        // is the first moment of the next lap.
        moments = (0..<Run.count).map { Run.lap * Double($0) / Double(Run.count - 1) * 0.999 }
        for moment in moments {
            _ = try? await view.evaluateJavaScript("document.querySelector('svg').setCurrentTime(\(moment)); 1")
            try? await Task.sleep(nanoseconds: 60_000_000)
            let settings = WKSnapshotConfiguration()
            settings.afterScreenUpdates = true
            if let picture = try? await view.takeSnapshot(configuration: settings),
               let image = picture.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                frames.append(image)
            }
        }
        finish()
    }

    static func pixels(_ image: CGImage, side: Int = 64) -> [UInt8] {
        var bytes = [UInt8](repeating: 255, count: side * side * 4)
        bytes.withUnsafeMutableBytes { raw in
            let context = CGContext(data: raw.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            context?.setFillColor(.white)
            context?.fill(CGRect(x: 0, y: 0, width: side, height: side))
            context?.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        return bytes
    }

    static func difference(_ a: [UInt8], _ b: [UInt8]) -> Double {
        var sum = 0
        for index in stride(from: 0, to: a.count, by: 4) { sum += abs(Int(a[index]) - Int(b[index])) }
        return Double(sum) / Double(a.count / 4) / 255 * 100
    }

    func finish() {
        guard !frames.isEmpty else { print("{\"error\":\"nothing photographed\"}"); exit(1) }
        let across = 4
        let side = Run.side
        let down = (frames.count + across - 1) / across
        let label = 22
        let width = across * side, height = down * (side + label)
        let sheet = NSImage(size: NSSize(width: width, height: height))
        sheet.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        for (index, frame) in frames.enumerated() {
            let x = (index % across) * side
            let y = height - (index / across + 1) * (side + label)
            NSImage(cgImage: frame, size: NSSize(width: Run.side, height: Run.side)).draw(in: NSRect(x: x, y: y, width: Run.side, height: Run.side))
            NSColor(white: 0.85, alpha: 1).setStroke()
            NSBezierPath(rect: NSRect(x: x, y: y, width: Run.side, height: Run.side + label)).stroke()
            (String(format: "%.2f s", moments[index]) as NSString).draw(at: NSPoint(x: x + 6, y: y + side + 3), withAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), .foregroundColor: NSColor.darkGray,
            ])
        }
        sheet.unlockFocus()
        if let tiff = sheet.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: Run.out))
        }
        if let gif = Run.gif, let file = CGImageDestinationCreateWithURL(URL(fileURLWithPath: gif) as CFURL, UTType.gif.identifier as CFString, frames.count, nil) {
            CGImageDestinationSetProperties(file, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
            let each = Run.lap / Double(max(frames.count - 1, 1))
            for frame in frames {
                CGImageDestinationAddImage(file, frame, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: each]] as CFDictionary)
            }
            CGImageDestinationFinalize(file)
        }
        let seen = frames.map { Self.pixels($0) }
        let steps = zip(seen, seen.dropFirst()).map { Self.difference($0, $1) }
        let ink = seen.map { bytes in stride(from: 0, to: bytes.count, by: 4).filter { bytes[$0] < 200 }.count }
        let answer: [String: Any] = [
            "frames": frames.count,
            "moves": steps.reduce(0, +) / Double(max(steps.count, 1)),
            "most": steps.max() ?? 0,
            "seam": Self.difference(seen[0], seen[seen.count - 1]),
            "blank": ink.filter { $0 == 0 }.count,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: answer), let line = String(data: data, encoding: .utf8) { print(line) }
        exit(0)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
MainActor.assumeIsolated {
    let film = Film()
    objc_setAssociatedObject(app, "film", film, .OBJC_ASSOCIATION_RETAIN)
    film.start()
}
DispatchQueue.main.asyncAfter(deadline: .now() + 60) { print("{\"error\":\"timed out\"}"); exit(1) }
app.run()
