#if PHOTONZ_PLAYTEST
import AppKit
import AVFoundation
import CoreImage
import Darwin
import os
import PhotonzCore
import PhotonzMedia
import QuartzCore
import ScreenCaptureKit
import VideoToolbox

/// Probe-only drill of how true a screen recording's colours and gradients
/// are, and what each way of writing the file costs
/// (`--recording-colour-diag <candidates> [--seconds N] [--out DIR]`).
///
/// It puts a panel the size of the main display BEHIND every other app's
/// windows (so a person working at the Mac is not covered), painted with known
/// swatches (sRGB greys and primaries, Display P3 primaries, the dark purples
/// of a translucent terminal), two slow dark gradients, a dark translucent
/// pane with text, and a strip that moves every frame (scrolling text and a
/// moving picture, the way a person scrolls or plays a video). Only that panel
/// is captured (an including filter), so nothing on the person's screen ends
/// up in a file.
///
/// For each candidate it records `seconds` with one stream, photographs the
/// panel the way a screenshot does, and measures: per swatch the colour the
/// screenshot has, the colour the file decodes to through AVFoundation (what
/// QuickTime shows), and through the editor's own decode; the steps across
/// each gradient; text sharpness; the bytes a minute costs; frames delivered
/// against frames written; and the CPU every process spent while it recorded,
/// with the GPU's busy share. Results go to `<out>/result.json`, and a crop of
/// every candidate's frame to `<out>/<candidate>-*.png`.
@MainActor
enum RecordingColourDiag {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--recording-colour-diag") else { return }
        let names = (i + 1 < args.count ? args[i + 1] : "today").split(separator: ",").map(String.init)
        let seconds = args.firstIndex(of: "--seconds").flatMap { $0 + 1 < args.count ? Double(args[$0 + 1]) : nil } ?? 6
        let out = args.firstIndex(of: "--out").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
            ?? "/tmp/photonz-recording-colour"
        let still = args.contains("--still")
        Task { await run(names: names, seconds: seconds, still: still, out: URL(fileURLWithPath: out)) }
    }

    // MARK: Candidates

    enum Writer { case macOS(AVVideoCodecType), own(AVVideoCodecType, [String: Any], AVFileType), app }

    struct Candidate {
        let name: String
        let writer: Writer
        var pixelFormat: OSType?
        var colorSpace: CFString?
        var matrix: CFString?
        /// Tell the encoder what the stream's frames really hold.
        var retag = true
    }

    /// `today` and `today-hevc` are macOS's own writer, as the app records
    /// today (`today-p3`, `today-srgb` set the stream's colour space). The rest
    /// read `<codec>[-<Mbps>|-q<quality>][-p3|-srgb][-f][-raw]`: codec h264,
    /// hevc, hevc10, prores422 or prores422hq; `f` asks the stream for full
    /// range; `raw` leaves the stream's own tags on its frames.
    static func candidate(_ name: String) -> Candidate? {
        let p3 = CGColorSpace.displayP3, srgb = CGColorSpace.sRGB
        switch name {
        case "today": return Candidate(name: name, writer: .macOS(.h264))
        // What the app records with now: Best, and Smaller files.
        case "app", "app-smaller": return Candidate(name: name, writer: .app)
        case "today-hevc": return Candidate(name: name, writer: .macOS(.hevc))
        case "today-srgb": return Candidate(name: name, writer: .macOS(.h264), colorSpace: srgb)
        case "today-p3": return Candidate(name: name, writer: .macOS(.h264), colorSpace: p3)
        default: break
        }
        let parts = name.split(separator: "-").map(String.init)
        guard let codecName = parts.first else { return nil }
        var props: [String: Any] = [:]
        var space = srgb, full = false, retag = true
        var matrix: CFString?
        var rgb: OSType?
        for t in parts.dropFirst() {
            if let mbps = Double(t) { props[AVVideoAverageBitRateKey] = Int(mbps * 1_000_000) }
            else if t.hasPrefix("q"), let q = Double(t.dropFirst()) { props[AVVideoQualityKey] = q / 100 }
            else if t == "p3" { space = p3 }
            else if t == "srgb" { space = srgb }
            else if t == "f" { full = true }
            else if t == "raw" { retag = false }
            else if t.hasPrefix("cap"), let mbps = Double(t.dropFirst(3)) {
                props[kVTCompressionPropertyKey_DataRateLimits as String] = [mbps * 1_000_000 / 8, 1.0] as [Double]
            }
            else if t == "l10r" { rgb = kCVPixelFormatType_ARGB2101010LEPacked }
            else if t == "bgra" { rgb = kCVPixelFormatType_32BGRA }
            else if t == "m709" { matrix = CGDisplayStream.yCbCrMatrix_ITU_R_709_2 }
            else if t == "m601" { matrix = CGDisplayStream.yCbCrMatrix_ITU_R_601_4 }
            else if t == "m240" { matrix = CGDisplayStream.yCbCrMatrix_SMPTE_240M_1995 }
            else { return nil }
        }
        let codec: AVVideoCodecType, fileType: AVFileType, format: OSType
        switch codecName {
        case "h264":
            codec = .h264; fileType = .mp4
            props[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
            format = full ? kCVPixelFormatType_420YpCbCr8BiPlanarFullRange : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        case "hevc":
            codec = .hevc; fileType = .mp4
            format = full ? kCVPixelFormatType_420YpCbCr8BiPlanarFullRange : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        case "hevc10":
            codec = .hevc; fileType = .mp4
            props[AVVideoProfileLevelKey] = kVTProfileLevel_HEVC_Main10_AutoLevel as String
            format = full ? kCVPixelFormatType_420YpCbCr10BiPlanarFullRange : kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
        case "prores422", "prores422hq":
            codec = codecName == "prores422" ? .proRes422 : .proRes422HQ; fileType = .mov
            format = kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
        default: return nil
        }
        var c = Candidate(name: name, writer: .own(codec, props, fileType), pixelFormat: rgb ?? format, colorSpace: space,
                          matrix: matrix)
        c.retag = retag
        return c
    }

    // MARK: Scene

    struct Swatch { let name: String; let space: CFString; let rgb: [CGFloat] }

    static let swatches: [[Swatch]] = {
        func s(_ n: String, _ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> Swatch {
            Swatch(name: n, space: CGColorSpace.sRGB, rgb: [r / 255, g / 255, b / 255])
        }
        func p(_ n: String, _ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> Swatch {
            Swatch(name: n, space: CGColorSpace.displayP3, rgb: [r, g, b])
        }
        return [
            [s("grey0", 0, 0, 0), s("grey16", 16, 16, 16), s("grey32", 32, 32, 32), s("grey50", 50, 50, 50),
             s("grey76", 76, 76, 76), s("grey128", 128, 128, 128), s("grey192", 192, 192, 192),
             s("grey235", 235, 235, 235), s("grey255", 255, 255, 255), s("termgrey", 60, 57, 62)],
            [s("red", 255, 0, 0), s("green", 0, 255, 0), s("blue", 0, 0, 255), s("sky", 51, 128, 230),
             s("orange", 240, 140, 40), s("purple", 40, 28, 64), s("termbg", 30, 30, 46),
             p("p3red", 1, 0, 0), p("p3green", 0, 1, 0), p("p3violet", 0.6, 0.1, 0.9)],
        ]
    }()

    /// Where things are on the panel, in points from its top left.
    enum Layout {
        static let swatch: CGFloat = 100, gap: CGFloat = 10, left: CGFloat = 40
        static func swatchRect(row: Int, col: Int) -> CGRect {
            CGRect(x: left + CGFloat(col) * (swatch + gap), y: 60 + CGFloat(row) * (swatch + gap),
                   width: swatch, height: swatch)
        }
        static func greyRamp(width: CGFloat) -> CGRect { CGRect(x: left, y: 290, width: width - 2 * left, height: 80) }
        static func purpleRamp(width: CGFloat) -> CGRect { CGRect(x: left, y: 380, width: width - 2 * left, height: 80) }
        static func pane(width: CGFloat) -> CGRect { CGRect(x: left, y: 480, width: width / 2 - left, height: 320) }
        static func text(width: CGFloat) -> CGRect { CGRect(x: width / 2 + 10, y: 480, width: width / 2 - 50, height: 320) }
        static func motion(width: CGFloat, height: CGFloat) -> CGRect {
            CGRect(x: left, y: 820, width: width - 2 * left, height: max(60, height - 860))
        }
    }

    /// Grey ramp: sRGB 16 to 56. Purple ramp: sRGB (30,24,48) to (70,56,100).
    static let greyRampEnds: (CGFloat, CGFloat) = (16, 56)
    static let purpleRampEnds: ([CGFloat], [CGFloat]) = ([30, 24, 48], [70, 56, 100])

    final class SceneView: NSView {
        override var isFlipped: Bool { true }
        override func draw(_ dirtyRect: NSRect) {
            guard let ctx = NSGraphicsContext.current?.cgContext else { return }
            let W = bounds.width
            ctx.setFillColor(CGColor(gray: 0.12, alpha: 1))
            ctx.fill(bounds)
            for (r, row) in RecordingColourDiag.swatches.enumerated() {
                for (c, sw) in row.enumerated() {
                    guard let space = CGColorSpace(name: sw.space),
                          let color = CGColor(colorSpace: space, components: sw.rgb + [1]) else { continue }
                    ctx.setFillColor(color)
                    ctx.fill(Layout.swatchRect(row: r, col: c))
                }
            }
            guard let srgb = CGColorSpace(name: CGColorSpace.sRGB) else { return }
            func ramp(_ rect: CGRect, _ a: [CGFloat], _ b: [CGFloat]) {
                let ca: [CGFloat] = a.map { $0 / 255 }
                let cb: [CGFloat] = b.map { $0 / 255 }
                let components: [CGFloat] = ca + [1] + cb + [1]
                guard let g = CGGradient(colorSpace: srgb, colorComponents: components,
                                         locations: [0, 1], count: 2) else { return }
                ctx.saveGState()
                ctx.clip(to: rect)
                ctx.drawLinearGradient(g, start: CGPoint(x: rect.minX, y: rect.midY),
                                       end: CGPoint(x: rect.maxX, y: rect.midY), options: [])
                ctx.restoreGState()
            }
            let (g0, g1) = RecordingColourDiag.greyRampEnds
            ramp(Layout.greyRamp(width: W), [g0, g0, g0], [g1, g1, g1])
            ramp(Layout.purpleRamp(width: W), RecordingColourDiag.purpleRampEnds.0, RecordingColourDiag.purpleRampEnds.1)
            // Behind the translucent pane: a purple wash, like a terminal over a wallpaper.
            let pane = Layout.pane(width: W)
            ramp(pane, [90, 40, 140], [20, 30, 60])
            // Terminal-like text on the dark purple.
            let text = Layout.text(width: W)
            ctx.setFillColor(CGColor(srgbRed: 30 / 255, green: 30 / 255, blue: 46 / 255, alpha: 1))
            ctx.fill(text)
            let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            let attrs: [NSAttributedString.Key: Any] = [.font: font,
                                                        .foregroundColor: NSColor(srgbRed: 0.85, green: 0.85, blue: 0.9, alpha: 1)]
            NSGraphicsContext.saveGraphicsState()
            for i in 0..<18 {
                let line = "\(String(format: "%02d", i))  let colour = sample(frame: \(i * 7)) // banding check ~ 0xA0B1C2"
                (line as NSString).draw(at: CGPoint(x: text.minX + 12, y: text.minY + 10 + CGFloat(i) * 17),
                                        withAttributes: attrs)
            }
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    static func makePanel(on screen: NSScreen) -> (NSPanel, CALayer) {
        let frame = screen.frame
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = true
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        // Behind every app's windows, above the desktop picture.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        let view = SceneView(frame: CGRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        panel.contentView = view
        // The translucent pane over the purple wash, with text on it.
        let paneRect = Layout.pane(width: frame.width)
        let glass = NSVisualEffectView(frame: paneRect.insetBy(dx: 30, dy: 30))
        glass.material = .hudWindow
        glass.blendingMode = .withinWindow
        glass.state = .active
        glass.appearance = NSAppearance(named: .darkAqua)
        let label = NSTextField(labelWithString: (0..<10).map { "pane line \($0): the quick brown fox 0123456789" }
            .joined(separator: "\n"))
        label.font = .systemFont(ofSize: 13)
        label.textColor = .labelColor
        label.frame = glass.bounds.insetBy(dx: 12, dy: 12)
        glass.addSubview(label)
        view.addSubview(glass)
        // NSView's y runs up in the content view, though the scene draws flipped.
        let motion = Layout.motion(width: frame.width, height: frame.height)
        let strip = NSView(frame: motion)
        strip.wantsLayer = true
        view.addSubview(strip)
        let host = strip.layer ?? CALayer()
        host.masksToBounds = true
        host.backgroundColor = CGColor(gray: 0.05, alpha: 1)
        panel.orderFrontRegardless()
        return (panel, host)
    }

    /// Something that changes every frame: lines of text scrolling up, and a
    /// busy picture sliding across, like a page scrolling beside a playing video.
    static func animate(_ host: CALayer) {
        let size = host.bounds.size
        let text = CATextLayer()
        text.contentsScale = 2
        text.fontSize = 14
        text.foregroundColor = CGColor(gray: 0.9, alpha: 1)
        text.string = (0..<200).map { "scrolling line \($0)  lorem ipsum dolor sit amet, consectetur 0x\(String($0 * 7919, radix: 16))" }
            .joined(separator: "\n")
        text.frame = CGRect(x: 10, y: 0, width: size.width / 2 - 20, height: 200 * 17)
        host.addSublayer(text)
        let scroll = CABasicAnimation(keyPath: "position.y")
        scroll.fromValue = -text.frame.height / 2 + size.height
        scroll.toValue = text.frame.height / 2
        scroll.duration = 20
        scroll.repeatCount = .infinity
        text.add(scroll, forKey: "scroll")
        let picture = CAGradientLayer()
        picture.type = .conic
        picture.colors = [CGColor(srgbRed: 1, green: 0.2, blue: 0.2, alpha: 1), CGColor(srgbRed: 0.2, green: 0.9, blue: 0.3, alpha: 1),
                          CGColor(srgbRed: 0.2, green: 0.3, blue: 1, alpha: 1), CGColor(srgbRed: 1, green: 0.9, blue: 0.2, alpha: 1),
                          CGColor(srgbRed: 1, green: 0.2, blue: 0.2, alpha: 1)]
        picture.startPoint = CGPoint(x: 0.5, y: 0.5)
        picture.endPoint = CGPoint(x: 1, y: 1)
        picture.frame = CGRect(x: size.width / 2, y: 0, width: size.height, height: size.height)
        host.addSublayer(picture)
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = Double.pi * 2
        spin.duration = 3
        spin.repeatCount = .infinity
        picture.add(spin, forKey: "spin")
        let slide = CABasicAnimation(keyPath: "position.x")
        slide.fromValue = size.width / 2
        slide.toValue = size.width - size.height / 2
        slide.duration = 4
        slide.autoreverses = true
        slide.repeatCount = .infinity
        picture.add(slide, forKey: "slide")
    }

    // MARK: Writing

    /// Counts the stream's frames, and when it owns the file, writes them.
    final class Frames: NSObject, SCStreamOutput, @unchecked Sendable {
        static let queue = DispatchQueue(label: "photonz.colour-diag.frames", qos: .userInitiated)
        let lock = NSLock()
        var delivered = 0, appended = 0, notReady = 0, failed = 0
        var firstHost: Double?
        var firstAppendHost: Double?
        var attachments: [String: String] = [:]
        var writer: AVAssetWriter?
        var input: AVAssetWriterInput?
        var appWriter: RecordingFileWriter?
        var started = false
        var stopping = false
        /// The colour tags each frame is given before it is written, when set.
        var tags: [CFString: CFString]?

        func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
            guard type == .screen else { return }
            if let a = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
               let raw = a.first?[.status] as? Int, let status = SCFrameStatus(rawValue: raw), status != .complete { return }
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            lock.lock(); defer { lock.unlock() }
            guard !stopping else { return }
            delivered += 1
            if firstHost == nil {
                firstHost = pts.seconds
                if let buffer = CMSampleBufferGetImageBuffer(sampleBuffer),
                   let all = CVBufferCopyAttachments(buffer, .shouldPropagate) as? [String: Any] {
                    for (k, v) in all where k.contains("Color") || k.contains("Transfer") || k.contains("YCbCr") || k.contains("Gamma") {
                        attachments[k] = "\(v)".prefix(80).description
                    }
                    attachments["pixelFormat"] = fourCC(CVPixelBufferGetPixelFormatType(buffer))
                }
            }
            if let appWriter {
                if appWriter.append(picture: sampleBuffer) { appended += 1 } else { notReady += 1 }
                if firstAppendHost == nil { firstAppendHost = CMClockGetTime(CMClockGetHostTimeClock()).seconds }
                return
            }
            guard let writer, let input else { return }
            if !started {
                guard writer.startWriting() else { failed += 1; return }
                writer.startSession(atSourceTime: pts)
                started = true
                firstAppendHost = CMClockGetTime(CMClockGetHostTimeClock()).seconds
            }
            if let tags, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                for (k, v) in tags { CVBufferSetAttachment(buffer, k, v, .shouldPropagate) }
            }
            if input.isReadyForMoreMediaData {
                if input.append(sampleBuffer) { appended += 1 } else { failed += 1 }
            } else {
                notReady += 1
            }
        }
    }

    nonisolated static func fourCC(_ code: OSType) -> String {
        let bytes = [UInt8((code >> 24) & 0xff), UInt8((code >> 16) & 0xff), UInt8((code >> 8) & 0xff), UInt8(code & 0xff)]
        return String(bytes: bytes, encoding: .ascii) ?? "\(code)"
    }

    final class Started: NSObject, SCRecordingOutputDelegate, @unchecked Sendable {
        var startedHost: Double?
        var finished = false
        var error: String?
        func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
            startedHost = CMClockGetTime(CMClockGetHostTimeClock()).seconds
        }
        func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) { finished = true }
        func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
            self.error = "\(error)"
            finished = true
        }
    }

    // MARK: Load

    struct ProcessTimes { var byName: [String: Double] }

    static func psTimes() -> ProcessTimes {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-A", "-o", "time=,comm="]
        let pipe = Pipe()
        p.standardOutput = pipe
        try? p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        var out: [String: Double] = [:]
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { continue }
            // m:ss.cc or h:mm:ss.cc
            let t = parts[0].split(separator: ":").compactMap { Double($0) }
            let secs = t.reduce(0) { $0 * 60 + $1 }
            let name = (String(parts[1]) as NSString).lastPathComponent
            out[name, default: 0] += secs
        }
        return ProcessTimes(byName: out)
    }

    static func gpuBusy() -> Double? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        p.arguments = ["-r", "-d", "1", "-c", "IOAccelerator"]
        let pipe = Pipe()
        p.standardOutput = pipe
        try? p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        guard let r = text.range(of: "\"Device Utilization %\"=") else { return nil }
        let digits = text[r.upperBound...].prefix { $0.isNumber }
        return Double(digits)
    }

    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    // MARK: Run

    static func run(names: [String], seconds: Double, still: Bool, out: URL) async {
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        var result: [String: Any] = ["seconds": seconds]
        var readings: [[String: Any]] = []
        defer {
            result["readings"] = readings
            if let data = SafeJSON.data(from: result, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: out.appendingPathComponent("result.json"))
            }
            NSLog("[recording-colour-diag] done")
        }
        guard let screen = NSScreen.main else { result["error"] = "no screen"; return }
        guard ScreenCapturer.hasPermission else { result["error"] = "no Screen Recording grant"; return }
        result["screen"] = ["points": [screen.frame.width, screen.frame.height], "scale": screen.backingScaleFactor,
                            "colorSpace": screen.colorSpace?.localizedName ?? "?"]
        let (panel, host) = makePanel(on: screen)
        defer { panel.orderOut(nil) }
        try? await Task.sleep(for: .milliseconds(300))
        if !still { animate(host) }
        result["still"] = still
        try? await Task.sleep(for: .milliseconds(700))
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false),
              let window = content.windows.first(where: { $0.windowID == CGWindowID(panel.windowNumber) }),
              let display = content.displays.first(where: { $0.displayID == displayID(screen) })
        else { result["error"] = "panel not shareable"; return }
        let filter = SCContentFilter(display: display, including: [window])

        // The screenshot: the panel as a still, through the same filter.
        let shotConfig = SCScreenshotConfiguration()
        shotConfig.showsCursor = false
        shotConfig.dynamicRange = .sdr
        shotConfig.width = Int(screen.frame.width * screen.backingScaleFactor)
        shotConfig.height = Int(screen.frame.height * screen.backingScaleFactor)
        var screenshot: CGImage?
        if let shot = try? await SCScreenshotManager.captureScreenshot(contentFilter: filter, configuration: shotConfig) {
            screenshot = shot.sdrImage
        }
        // The WYSIWYG screenshot of the same rectangle as a person's ⇧⌘4 makes it (only the
        // panel's own pixels are compared, where nothing covers them).
        result["screenshotSpace"] = screenshot?.colorSpace?.name as String? ?? "?"
        let scale = screen.backingScaleFactor
        let size = screen.frame.size
        if let screenshot {
            let m = measure(screenshot, scale: scale, size: size)
            result["screenshot"] = m.json
            save(screenshot, scale: scale, size: size, as: out.appendingPathComponent("screenshot"))
        }

        for name in names {
            if name == "idle" {
                let ps0 = psTimes()
                var gpu: [Double] = []
                let end = Date().addingTimeInterval(seconds)
                while Date() < end {
                    try? await Task.sleep(for: .milliseconds(500))
                    if let g = gpuBusy() { gpu.append(g) }
                }
                let ps1 = psTimes()
                var cpu: [String: Double] = [:]
                for k in ["replayd", "WindowServer", "VTEncoderXPCService", "Photonz Probe"] {
                    cpu[k] = (((ps1.byName[k] ?? 0) - (ps0.byName[k] ?? 0)) / seconds * 1000).rounded() / 10
                }
                readings.append(["name": "idle", "cpuPercentOfOneCore": cpu,
                                 "gpuBusyPercent": gpu.isEmpty ? 0 : (gpu.reduce(0, +) / Double(gpu.count) * 10).rounded() / 10])
                continue
            }
            guard let c = candidate(name) else { readings.append(["name": name, "error": "unknown"]); continue }
            NSLog("[recording-colour-diag] \(name)")
            var r: [String: Any] = ["name": name]
            let ext = { if case .own(_, _, .mov) = c.writer { return "mov" } else { return "mp4" } }()
            let url = out.appendingPathComponent("\(name).\(ext)")
            try? FileManager.default.removeItem(at: url)
            let config = SCStreamConfiguration()
            config.width = Int(size.width * scale)
            config.height = Int(size.height * scale)
            config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
            config.showsCursor = true
            if let f = c.pixelFormat { config.pixelFormat = f }
            if let s = c.colorSpace { config.colorSpaceName = s }
            if let m = c.matrix { config.colorMatrix = m }
            if case .app = c.writer { ScreenRecorder.askForTheScreensColours(config) }
            r["streamDefaults"] = ["pixelFormat": fourCC(SCStreamConfiguration().pixelFormat),
                                   "colorSpace": SCStreamConfiguration().colorSpaceName as String,
                                   "matrix": SCStreamConfiguration().colorMatrix as String]
            let frames = Frames()
            let started = Started()
            let stream = SCStream(filter: filter, configuration: config, delegate: nil)
            var recording: SCRecordingOutput?
            switch c.writer {
            case .app:
                guard let made = try? RecordingFileWriter(url: url, pixelSize: CGSize(width: config.width, height: config.height),
                                                          fps: Int(ScreenRecorder.fps), withSound: false,
                                                          quality: name == "app-smaller" ? .smaller : .best)
                else { r["error"] = "no writer"; readings.append(r); continue }
                frames.appWriter = made
            case .macOS(let codec):
                let rc = SCRecordingOutputConfiguration()
                rc.outputURL = url
                rc.outputFileType = .mp4
                rc.videoCodecType = codec
                let output = SCRecordingOutput(configuration: rc, delegate: started)
                do { try stream.addRecordingOutput(output) } catch { r["error"] = "\(error)"; readings.append(r); continue }
                recording = output
            case .own(let codec, let compression, let fileType):
                guard let writer = try? AVAssetWriter(outputURL: url, fileType: fileType) else {
                    r["error"] = "no writer"; readings.append(r); continue
                }
                var props: [String: Any] = compression
                props[AVVideoExpectedSourceFrameRateKey] = 60
                props[kVTCompressionPropertyKey_RealTime as String] = kCFBooleanTrue
                if codec == .h264 || codec == .hevc {
                    props[AVVideoMaxKeyFrameIntervalKey] = 120
                    props[AVVideoAllowFrameReorderingKey] = false
                }
                var settings: [String: Any] = [AVVideoCodecKey: codec, AVVideoWidthKey: config.width,
                                               AVVideoHeightKey: config.height]
                if !(codec == .proRes422 || codec == .proRes422HQ) || !props.isEmpty {
                    if codec == .proRes422 || codec == .proRes422HQ {
                        props.removeValue(forKey: AVVideoExpectedSourceFrameRateKey)
                    }
                    if !props.isEmpty { settings[AVVideoCompressionPropertiesKey] = props }
                }
                settings[AVVideoColorPropertiesKey] = [
                    AVVideoColorPrimariesKey: c.colorSpace == CGColorSpace.displayP3
                        ? AVVideoColorPrimaries_P3_D65 : AVVideoColorPrimaries_ITU_R_709_2,
                    AVVideoTransferFunctionKey: AVVideoTransferFunction_IEC_sRGB,
                    AVVideoYCbCrMatrixKey: c.matrix == CGDisplayStream.yCbCrMatrix_ITU_R_601_4
                        ? AVVideoYCbCrMatrix_ITU_R_601_4 : AVVideoYCbCrMatrix_ITU_R_709_2,
                ]
                let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
                input.expectsMediaDataInRealTime = true
                guard writer.canAdd(input) else { r["error"] = "cannot add input"; readings.append(r); continue }
                writer.add(input)
                frames.writer = writer
                frames.input = input
                if c.retag, c.pixelFormat == kCVPixelFormatType_ARGB2101010LEPacked || c.pixelFormat == kCVPixelFormatType_32BGRA {
                    frames.tags = [
                        kCVImageBufferColorPrimariesKey: c.colorSpace == CGColorSpace.displayP3
                            ? kCVImageBufferColorPrimaries_P3_D65 : kCVImageBufferColorPrimaries_ITU_R_709_2,
                        kCVImageBufferTransferFunctionKey: kCVImageBufferTransferFunction_sRGB,
                    ]
                } else if c.retag {
                    frames.tags = [
                        kCVImageBufferColorPrimariesKey: c.colorSpace == CGColorSpace.displayP3
                            ? kCVImageBufferColorPrimaries_P3_D65 : kCVImageBufferColorPrimaries_ITU_R_709_2,
                        kCVImageBufferTransferFunctionKey: kCVImageBufferTransferFunction_sRGB,
                        kCVImageBufferYCbCrMatrixKey: c.matrix == CGDisplayStream.yCbCrMatrix_ITU_R_601_4
                            ? kCVImageBufferYCbCrMatrix_ITU_R_601_4 : kCVImageBufferYCbCrMatrix_ITU_R_709_2,
                    ]
                }
            }
            do { try stream.addStreamOutput(frames, type: .screen, sampleHandlerQueue: Frames.queue) } catch {
                r["error"] = "\(error)"; readings.append(r); continue
            }
            // Load: before.
            let ps0 = psTimes()
            var self0 = rusage(); getrusage(RUSAGE_SELF, &self0)
            let mem0 = footprintMB()
            let t0 = CMClockGetTime(CMClockGetHostTimeClock()).seconds
            do { try await stream.startCapture() } catch { r["error"] = "start: \(error)"; readings.append(r); continue }
            let tStarted = CMClockGetTime(CMClockGetHostTimeClock()).seconds
            var gpu: [Double] = []
            var memPeak = mem0
            let end = Date().addingTimeInterval(seconds)
            while Date() < end {
                try? await Task.sleep(for: .milliseconds(500))
                if let g = gpuBusy() { gpu.append(g) }
                memPeak = max(memPeak, footprintMB())
            }
            frames.lock.withLock { frames.stopping = true }
            try? await stream.stopCapture()
            if let appWriter = frames.appWriter {
                if !(await appWriter.finish()) { r["writerError"] = "\(appWriter.failure.map { "\($0)" } ?? "no frames")" }
            } else if let writer = frames.writer {
                frames.input?.markAsFinished()
                await writer.finishWriting()
                if writer.status != .completed { r["writerError"] = "\(writer.error.map { "\($0)" } ?? "status \(writer.status.rawValue)")" }
            } else {
                let deadline = Date().addingTimeInterval(10)
                while !started.finished, Date() < deadline { try? await Task.sleep(for: .milliseconds(20)) }
                if let e = started.error { r["writerError"] = e }
                _ = recording
            }
            let ps1 = psTimes()
            var self1 = rusage(); getrusage(RUSAGE_SELF, &self1)
            func secs(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1e6 }
            let selfCPU = secs(self1.ru_utime) - secs(self0.ru_utime) + secs(self1.ru_stime) - secs(self0.ru_stime)
            var cpu: [String: Double] = [:]
            for (k, v) in ps1.byName { let d = v - (ps0.byName[k] ?? 0); if d >= 0.05 { cpu[k] = (d * 100).rounded() / 100 } }
            r["cpuSeconds"] = cpu
            r["cpuPercentOfOneCore"] = [
                "probe": (selfCPU / seconds * 1000).rounded() / 10,
                "allProcesses": ((ps1.byName.values.reduce(0, +) - ps0.byName.values.reduce(0, +)) / seconds * 1000).rounded() / 10,
                "replayd": ((cpu["replayd"] ?? 0) / seconds * 1000).rounded() / 10,
                "WindowServer": ((cpu["WindowServer"] ?? 0) / seconds * 1000).rounded() / 10,
                "VTEncoderXPCService": ((cpu["VTEncoderXPCService"] ?? 0) / seconds * 1000).rounded() / 10,
                "recording": ((selfCPU + (cpu["replayd"] ?? 0) + (cpu["WindowServer"] ?? 0)
                               + (cpu["VTEncoderXPCService"] ?? 0)) / seconds * 1000).rounded() / 10,
            ]
            r["gpuBusyPercent"] = gpu.isEmpty ? nil : (gpu.reduce(0, +) / Double(gpu.count) * 10).rounded() / 10
            r["memoryAddedMB"] = ((memPeak - mem0) * 10).rounded() / 10
            let (counts, attachments, firstFrame, firstAppend) = frames.lock.withLock {
                ([frames.delivered, frames.appended, frames.notReady, frames.failed], frames.attachments,
                 frames.firstHost, frames.firstAppendHost)
            }
            r["framesDelivered"] = counts[0]
            r["framesAppended"] = counts[1]
            r["framesNotReady"] = counts[2]
            r["appendFailed"] = counts[3]
            r["streamAttachments"] = attachments
            r["startToFirstFrameMS"] = firstFrame.map { (($0 - t0) * 10000).rounded() / 10 }
            r["startCaptureReturnedMS"] = ((tStarted - t0) * 10000).rounded() / 10
            r["startToFileBeganMS"] = (started.startedHost ?? firstAppend).map { (($0 - t0) * 10000).rounded() / 10 }
            // The file.
            let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            r["bytes"] = bytes
            let asset = AVURLAsset(url: url)
            let duration = (try? await asset.load(.duration))?.seconds ?? 0
            r["fileSeconds"] = (duration * 100).rounded() / 100
            r["megabytesPerMinute"] = duration > 0 ? (Double(bytes) / duration * 60 / 1_048_576 * 10).rounded() / 10 : nil
            if let track = try? await asset.loadTracks(withMediaType: .video).first {
                let descs = (try? await track.load(.formatDescriptions)) ?? []
                if let d = descs.first {
                    r["codec"] = fourCC(CMFormatDescriptionGetMediaSubType(d))
                    var tags: [String: String] = [:]
                    if let ext = CMFormatDescriptionGetExtensions(d) as? [String: Any] {
                        for (k, v) in ext where k.contains("Color") || k.contains("Transfer") || k.contains("YCbCr")
                            || k.contains("FullRange") || k.contains("Depth") {
                            tags[k] = "\(v)"
                        }
                    }
                    r["fileTags"] = tags
                }
                r["fileFrames"] = await frameGaps(url: url)
                // Colour and banding, a second and a half in.
                let at = CMTime(seconds: min(1.5, max(0, duration - 0.3)), preferredTimescale: 600)
                if let qt = await quickTimeFrame(url: url, at: at) {
                    r["quickTime"] = compare(measure(qt, scale: scale, size: size), screenshot.map { measure($0, scale: scale, size: size) },
                                             image: qt, screenshot: screenshot, scale: scale, size: size)
                    r["quickTimeSpace"] = qt.colorSpace?.name as String? ?? "?"
                    save(qt, scale: scale, size: size, as: out.appendingPathComponent("\(name)-quicktime"))
                }
                if let ed = await editorFrame(url: url, at: at) {
                    r["editor"] = compare(measure(ed, scale: scale, size: size), screenshot.map { measure($0, scale: scale, size: size) },
                                          image: ed, screenshot: screenshot, scale: scale, size: size)
                    r["editorSpace"] = ed.colorSpace?.name as String? ?? "?"
                    save(ed, scale: scale, size: size, as: out.appendingPathComponent("\(name)-editor"))
                }
                if let ed = await editorFrame(url: url, at: at, format: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange) {
                    r["editor10"] = compare(measure(ed, scale: scale, size: size), screenshot.map { measure($0, scale: scale, size: size) },
                                            image: ed, screenshot: screenshot, scale: scale, size: size)
                    save(ed, scale: scale, size: size, as: out.appendingPathComponent("\(name)-editor10"))
                }
            }
            readings.append(r)
            try? await Task.sleep(for: .milliseconds(400))
        }
    }

    static func displayID(_ screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    /// Frames in the file and how many times a gap of more than one and a half
    /// frames at 60 a second opens between two of them.
    nonisolated static func frameGaps(url: URL) async -> [String: Any] {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let reader = try? AVAssetReader(asset: asset) else { return [:] }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        reader.startReading()
        var times: [Double] = []
        while let s = output.copyNextSampleBuffer() {
            if CMSampleBufferGetNumSamples(s) > 0 { times.append(CMSampleBufferGetPresentationTimeStamp(s).seconds) }
        }
        times.sort()
        var late = 0, worst = 0.0
        for (a, b) in zip(times, times.dropFirst()) {
            let gap = b - a
            if gap > 1.5 / 60 { late += 1 }
            worst = max(worst, gap)
        }
        return ["count": times.count, "gapsOverOneAndAHalfFrames": late, "worstGapMS": (worst * 10000).rounded() / 10]
    }

    /// What QuickTime shows: AVFoundation's own decode, colour managed.
    nonisolated static func quickTimeFrame(url: URL, at: CMTime) async -> CGImage? {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = .zero
        gen.appliesPreferredTrackTransform = true
        return try? await gen.image(at: at).image
    }

    /// What the editor shows: its own decode (`MovieFrames.picture(of:)`).
    nonisolated static func editorFrame(url: URL, at: CMTime,
                                        format: OSType = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) async -> CGImage? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let reader = try? AVAssetReader(asset: asset) else { return nil }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: format])
        reader.add(output)
        reader.timeRange = CMTimeRange(start: at, duration: CMTime(seconds: 1, preferredTimescale: 600))
        reader.startReading()
        guard let s = output.copyNextSampleBuffer(), let buffer = CMSampleBufferGetImageBuffer(s) else { return nil }
        reader.cancelReading()
        let image = CIImage(cvPixelBuffer: buffer)
        let colors = CVBufferCopyAttachments(buffer, .shouldPropagate)
            .flatMap { CVImageBufferCreateColorSpaceFromAttachments($0)?.takeRetainedValue() }
            ?? CGColorSpace(name: CGColorSpace.sRGB)
        return CIContext(options: [.cacheIntermediates: false])
            .createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: colors)
    }

    // MARK: Measuring

    struct Measure {
        var swatchLab: [String: [Double]] = [:]
        var swatchSRGB: [String: [Double]] = [:]
        var greyRamp: [Double] = []
        var purpleRamp: [Double] = []
        var json: [String: Any] {
            ["swatchSRGB": swatchSRGB.mapValues { $0.map { ($0 * 10).rounded() / 10 } },
             "greyRamp": rampStats(greyRamp), "purpleRamp": rampStats(purpleRamp)]
        }
    }

    /// The image drawn into Display P3 floats at the panel's size: every source
    /// is colour matched into one space before it is read.
    static func p3Pixels(_ image: CGImage, width: Int, height: Int) -> [Float]? {
        guard let space = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3),
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 32,
                                  bytesPerRow: width * 16, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = ctx.data else { return nil }
        let n = width * height * 4
        return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: n))
    }

    static let p3ToXYZ: [[Double]] = [[0.4865709, 0.2656677, 0.1982173], [0.2289746, 0.6917385, 0.0792869],
                                       [0.0000000, 0.0451134, 1.0439444]]
    static let xyzToSRGB: [[Double]] = [[3.2404542, -1.5371385, -0.4985314], [-0.9692660, 1.8760108, 0.0415560],
                                         [0.0556434, -0.2040259, 1.0572252]]

    static func mul(_ m: [[Double]], _ v: [Double]) -> [Double] {
        (0..<3).map { i in m[i][0] * v[0] + m[i][1] * v[1] + m[i][2] * v[2] }
    }
    static func srgbEncode(_ l: Double) -> Double {
        let c = l <= 0.0031308 ? 12.92 * l : 1.055 * pow(max(0, l), 1 / 2.4) - 0.055
        return c * 255
    }
    static func srgbDecode(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    static func lab(xyz: [Double]) -> [Double] {
        let w = [0.95047, 1.0, 1.08883]
        func f(_ t: Double) -> Double { t > 216.0 / 24389 ? cbrt(t) : (24389.0 / 27 * t + 16) / 116 }
        let fx = f(xyz[0] / w[0]), fy = f(xyz[1] / w[1]), fz = f(xyz[2] / w[2])
        return [116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)]
    }

    /// The truth for a swatch, in Lab.
    static func truthLab(_ s: Swatch) -> [Double] {
        let lin = s.rgb.map { srgbDecode(Double($0)) }
        if s.space == CGColorSpace.displayP3 { return lab(xyz: mul(p3ToXYZ, lin)) }
        let srgbToXYZ: [[Double]] = [[0.4124564, 0.3575761, 0.1804375], [0.2126729, 0.7151522, 0.0721750],
                                     [0.0193339, 0.1191920, 0.9503041]]
        return lab(xyz: mul(srgbToXYZ, lin))
    }

    static func measure(_ image: CGImage, scale: CGFloat, size: CGSize) -> Measure {
        var m = Measure()
        let W = Int(size.width * scale), H = Int(size.height * scale)
        guard let px = p3Pixels(image, width: W, height: H) else { return m }
        // CG's bitmap has row 0 at the top for reading memory.
        func mean(_ rect: CGRect) -> [Double] {
            var sum = [0.0, 0.0, 0.0], n = 0.0
            let x0 = Int(rect.minX * scale), x1 = Int(rect.maxX * scale), y0 = Int(rect.minY * scale), y1 = Int(rect.maxY * scale)
            for y in max(0, y0)..<min(H, y1) {
                for x in max(0, x0)..<min(W, x1) {
                    let i = (y * W + x) * 4
                    sum[0] += Double(px[i]); sum[1] += Double(px[i + 1]); sum[2] += Double(px[i + 2]); n += 1
                }
            }
            return n > 0 ? sum.map { $0 / n } : [0, 0, 0]
        }
        for (r, row) in swatches.enumerated() {
            for (c, sw) in row.enumerated() {
                let lin = mean(Layout.swatchRect(row: r, col: c).insetBy(dx: 25, dy: 25))
                let xyz = mul(p3ToXYZ, lin)
                m.swatchLab[sw.name] = lab(xyz: xyz)
                m.swatchSRGB[sw.name] = mul(xyzToSRGB, xyz).map(srgbEncode)
            }
        }
        // Ramps: per pixel column, the mean sRGB green over the middle rows.
        func ramp(_ rect: CGRect, channel: Int) -> [Double] {
            let inner = rect.insetBy(dx: 0, dy: 20)
            let y0 = Int(inner.minY * scale), y1 = Int(inner.maxY * scale)
            return (Int(inner.minX * scale)..<Int(inner.maxX * scale)).map { x in
                var s = 0.0
                for y in y0..<y1 {
                    let i = (y * W + x) * 4
                    // In the display's own code values (Display P3), which is what the panel shows.
                    let v = srgbEncode(Double(px[i + channel]))
                    s += v
                }
                return s / Double(y1 - y0)
            }
        }
        m.greyRamp = ramp(Layout.greyRamp(width: size.width), channel: 1)
        m.purpleRamp = ramp(Layout.purpleRamp(width: size.width), channel: 2)
        return m
    }

    /// Bands across a ramp: flat runs of at least 12 pixels, the steps between
    /// neighbouring runs, and the biggest single jump over four pixels.
    nonisolated static func rampStats(_ v: [Double]) -> [String: Any] {
        guard v.count > 40 else { return [:] }
        // The ends meet the background, and the encoder smears that edge.
        let v = Array(v.dropFirst(8).dropLast(8))
        var steps: [Double] = []
        var runStart = 0
        var bands = 0
        var lastLevel: Double?
        for x in 1...v.count {
            let flat = x < v.count && abs(v[x] - v[runStart]) < 0.5
            if !flat {
                if x - runStart >= 12 {
                    let level = v[runStart..<x].reduce(0, +) / Double(x - runStart)
                    if let l = lastLevel { steps.append(abs(level - l)) }
                    lastLevel = level
                    bands += 1
                }
                runStart = x
            }
        }
        var jump = 0.0
        for x in 0..<(v.count - 4) { jump = max(jump, abs(v[x + 4] - v[x])) }
        let sorted = steps.sorted()
        return ["bands": bands, "maxStep": ((sorted.last ?? 0) * 100).rounded() / 100,
                "medianStep": ((sorted.isEmpty ? 0 : sorted[sorted.count / 2]) * 100).rounded() / 100,
                "maxJump4px": (jump * 100).rounded() / 100,
                "from": ((v.first ?? 0) * 10).rounded() / 10, "to": ((v.last ?? 0) * 10).rounded() / 10]
    }

    static func deltaE2000(_ a: [Double], _ b: [Double]) -> Double {
        let (L1, a1, b1) = (a[0], a[1], a[2]), (L2, a2, b2) = (b[0], b[1], b[2])
        let C1 = hypot(a1, b1), C2 = hypot(a2, b2), Cb = (C1 + C2) / 2
        let G = 0.5 * (1 - sqrt(pow(Cb, 7) / (pow(Cb, 7) + pow(25, 7))))
        let a1p = (1 + G) * a1, a2p = (1 + G) * a2
        let C1p = hypot(a1p, b1), C2p = hypot(a2p, b2)
        func hue(_ b: Double, _ a: Double) -> Double { let h = atan2(b, a) * 180 / .pi; return h < 0 ? h + 360 : h }
        let h1p = hue(b1, a1p), h2p = hue(b2, a2p)
        let dLp = L2 - L1, dCp = C2p - C1p
        var dhp = h2p - h1p
        if C1p * C2p == 0 { dhp = 0 } else if dhp > 180 { dhp -= 360 } else if dhp < -180 { dhp += 360 }
        let dHp = 2 * sqrt(C1p * C2p) * sin(dhp * .pi / 360)
        let Lbp = (L1 + L2) / 2, Cbp = (C1p + C2p) / 2
        var hbp = h1p + h2p
        if C1p * C2p != 0 { hbp = abs(h1p - h2p) > 180 ? (hbp + 360) / 2 : hbp / 2 }
        let T = 1 - 0.17 * cos((hbp - 30) * .pi / 180) + 0.24 * cos(2 * hbp * .pi / 180)
            + 0.32 * cos((3 * hbp + 6) * .pi / 180) - 0.20 * cos((4 * hbp - 63) * .pi / 180)
        let dTheta = 30 * exp(-pow((hbp - 275) / 25, 2))
        let Rc = 2 * sqrt(pow(Cbp, 7) / (pow(Cbp, 7) + pow(25, 7)))
        let Sl = 1 + 0.015 * pow(Lbp - 50, 2) / sqrt(20 + pow(Lbp - 50, 2))
        let Sc = 1 + 0.045 * Cbp, Sh = 1 + 0.015 * Cbp * T
        let Rt = -sin(2 * dTheta * .pi / 180) * Rc
        return sqrt(pow(dLp / Sl, 2) + pow(dCp / Sc, 2) + pow(dHp / Sh, 2) + Rt * (dCp / Sc) * (dHp / Sh))
    }

    static func compare(_ m: Measure, _ shot: Measure?, image: CGImage, screenshot: CGImage?,
                        scale: CGFloat, size: CGSize) -> [String: Any] {
        var out = m.json
        var vsTruth: [String: Double] = [:], vsShot: [String: Double] = [:]
        for row in swatches {
            for sw in row {
                guard let lab = m.swatchLab[sw.name] else { continue }
                vsTruth[sw.name] = (deltaE2000(truthLab(sw), lab) * 100).rounded() / 100
                if let s = shot?.swatchLab[sw.name] { vsShot[sw.name] = (deltaE2000(s, lab) * 100).rounded() / 100 }
            }
        }
        out["deltaEvsTruth"] = vsTruth
        out["deltaEvsScreenshot"] = vsShot
        out["worstDeltaEvsScreenshot"] = vsShot.values.max()
        out["worstDeltaEvsTruth"] = vsTruth.values.max()
        if let screenshot { out.merge(textAndNoise(image, screenshot, scale: scale, size: size)) { $1 } }
        return out
    }

    /// Text sharpness (edge energy against the screenshot's, 1 is as sharp) in
    /// the terminal text and the glass pane, and PSNR against the screenshot
    /// over everything that does not move.
    static func textAndNoise(_ image: CGImage, _ shot: CGImage, scale: CGFloat, size: CGSize) -> [String: Any] {
        let W = Int(size.width * scale), H = Int(size.height * scale)
        guard let a = p3Pixels(image, width: W, height: H), let b = p3Pixels(shot, width: W, height: H) else { return [:] }
        func luma(_ p: [Float], _ i: Int) -> Double {
            srgbEncode(0.2126 * Double(p[i]) + 0.7152 * Double(p[i + 1]) + 0.0722 * Double(p[i + 2]))
        }
        func edges(_ p: [Float], _ rect: CGRect) -> Double {
            var e = 0.0
            for y in Int(rect.minY * scale)..<Int(rect.maxY * scale) - 1 {
                for x in Int(rect.minX * scale)..<Int(rect.maxX * scale) - 1 {
                    let i = (y * W + x) * 4
                    e += abs(luma(p, i + 4) - luma(p, i)) + abs(luma(p, i + W * 4) - luma(p, i))
                }
            }
            return e
        }
        let text = Layout.text(width: size.width).insetBy(dx: 8, dy: 8)
        let pane = Layout.pane(width: size.width).insetBy(dx: 40, dy: 40)
        // Swatches and ramps: flat, and nothing in them moves or blurs live.
        let still = CGRect(x: Layout.left, y: 60, width: size.width - 2 * Layout.left, height: 400)
        var se = 0.0, n = 0.0
        var y = Int(still.minY * scale)
        while y < Int(still.maxY * scale) {
            var x = 0
            while x < W {
                let i = (y * W + x) * 4
                for c in 0..<3 {
                    let d = srgbEncode(Double(a[i + c])) - srgbEncode(Double(b[i + c]))
                    se += d * d
                }
                n += 3
                x += 2
            }
            y += 2
        }
        let mse = se / max(1, n)
        let et = edges(b, text), ep = edges(b, pane)
        return ["textSharpness": et > 0 ? (edges(a, text) / et * 1000).rounded() / 1000 : 0,
                "paneTextSharpness": ep > 0 ? (edges(a, pane) / ep * 1000).rounded() / 1000 : 0,
                "psnr": mse > 0 ? (10 * log10(255 * 255 / mse) * 100).rounded() / 100 : 99]
    }

    /// Crops for the audit: the ramps and the pane at 100 percent, and the same
    /// with the darks stretched eight times so a band edge is plain to see.
    static func save(_ image: CGImage, scale: CGFloat, size: CGSize, as base: URL) {
        let W = Int(size.width * scale), H = Int(size.height * scale)
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4, space: srgb,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: W, height: H))
        guard let full = ctx.makeImage() else { return }
        let crop = CGRect(x: 0, y: 270 * scale, width: min(CGFloat(W), 1200 * scale), height: 540 * scale)
        if let c = full.cropping(to: crop) { write(c, to: base.appendingPathExtension("png")) }
        let ci = CIImage(cgImage: full).cropped(to: CGRect(x: 0, y: CGFloat(H) - 810 * scale, width: crop.width, height: crop.height))
        // Stretch: out = (in - 0.03) * 8, so sRGB 8 to 40 fills the range.
        let stretched = ci.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 8, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 8, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 8, w: 0), "inputBiasVector": CIVector(x: -0.24, y: -0.24, z: -0.24, w: 0)])
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        if let s = context.createCGImage(stretched, from: stretched.extent, format: .RGBA8, colorSpace: srgb) {
            write(s, to: base.appendingPathExtension("stretched.png"))
        }
    }

    static func write(_ image: CGImage, to url: URL) {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}
#endif
