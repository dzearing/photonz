#if DEBUG
import AppKit
import PhotonzCore
import SwiftUI

/// Films the hero button's hover sheen, frame by frame, from the shipped
/// drawing (`HeroButtonFace`): the sweep is a keyframe animation the window
/// server plays, and the walk harness's film steps leave the title bar out,
/// so this is how an audit gets a reel of it.
///
/// Run: `swift build && .build/debug/Photonz --hero-reel [out folder]`. Writes
/// `rest.png`, then `sweep-NN.png` every 1/60 s across the sweep in the hovered
/// pose, then `hovered.png`, `open.png` and `focused.png`, each over a dark and
/// a light title bar.
@MainActor
enum HeroReel {
    static let argument = "--hero-reel"

    static func runIfAsked() {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: argument) else { return }
        let out = URL(fileURLWithPath: flag + 1 < arguments.count ? arguments[flag + 1]
                      : NSTemporaryDirectory() + "photonz-hero-reel")
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        _ = NSApplication.shared
        var written = 0
        for (scheme, ground) in [("dark", Color(white: 0.16)), ("light", Color(white: 0.93))] {
            func shoot(_ name: String, _ look: HeroButtonLook, sheen: HeroSheen.Frame? = nil,
                       focused: Bool = false) {
                let face = HeroButtonFace(label: AskTitlebarButton.label, look: look,
                                          height: AskTitlebarButton.height, focused: focused,
                                          shownSheen: sheen ?? HeroSheen.frame(at: 0))
                    .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 24)
                    .background(ground)
                let renderer = ImageRenderer(content: face)
                renderer.scale = 3
                guard let image = renderer.cgImage else { return }
                let rep = NSBitmapImageRep(cgImage: image)
                let url = out.appendingPathComponent("\(scheme)-\(name).png")
                if (try? rep.representation(using: .png, properties: [:])?.write(to: url)) != nil { written += 1 }
            }
            shoot("rest", HeroButtonLook(pose: .rest))
            let frames = Int((HeroSheen.duration * 60).rounded())
            for step in 0...frames {
                shoot(String(format: "sweep-%02d", step), HeroButtonLook(pose: .hovered),
                      sheen: HeroSheen.frame(at: Double(step) / 60))
            }
            shoot("hovered", HeroButtonLook(pose: .hovered))
            shoot("pressed", HeroButtonLook(pose: .pressed))
            shoot("open", HeroButtonLook(pose: .open))
            shoot("focused", HeroButtonLook(pose: .rest), focused: true)
        }
        print("hero reel: \(written) frames in \(out.path)")
        exit(written > 0 ? 0 : 1)
    }
}
#endif
