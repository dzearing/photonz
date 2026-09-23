// Draws every piece of the video kit (Sources/Photonz/VideoKit) the way the
// mocks draw it, so each can be put beside its mock and compared.
//
// Run: Scripts/video-kit-gallery.sh [output folder]
//
// This file is compiled TOGETHER WITH the kit's own source files and nothing
// else, so what it draws is the shipped code, not a copy. It is also the kit's
// guard: a piece that starts to lean on the app stops this compiling.
//
// The mock half of the comparison is docs/design/mocks/shared/video-kit/
// index.html, which lays the same data out with the mock's own CSS classes.
import AppKit
import SwiftUI

typealias K = VideoKit

// The kit asks for `kitHover`; in the app it is `playtestHover`, so a walk can
// rest a pointer on it (Sources/Photonz/VideoKitHover.swift). Here, with no
// walks, a plain hover is all it needs.
extension View {
    func kitHover(_ name: String = "", perform: @escaping (Bool) -> Void) -> some View {
        onHover(perform: perform)
    }
}

// MARK: - The sheets, one per piece, with the mock page's data

struct TransportSheet: View {
    var body: some View {
        K.TransportBar(current: "0:04", duration: "0:15") {
            K.TransportButton(symbol: "speaker.wave.2.fill", label: "Volume") {}
        } controls: {
            K.TransportButton(symbol: "backward.end.fill", label: "Skip back") {}
            K.TransportButton(symbol: "play.fill", label: "Play", role: .primary) {}
            K.TransportButton(symbol: "forward.end.fill", label: "Skip forward") {}
        } scrubber: {
            K.Scrubber(fraction: 0.27, marks: [0.04, 0.92]) { _, _ in }
        }
        // The transport is glass; this is the window it sits on.
        .background(K.Palette.panel)
    }
}

/// The shared timeline (`inspector.css`): 58pt upper-case headers, 34pt lanes.
struct TimelineSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: K.Metrics.trackSpacing) {
            K.TrackRow(laneHeight: K.Metrics.rulerHeight) {
                Color.clear.frame(width: K.Metrics.trackHeaderWidth)
            } lane: {
                K.TimeRuler(ticks: stride(from: 0, through: 15, by: 3).map {
                    K.RulerTick(fraction: Double($0) / 15, label: "\($0)s")
                })
            }
            K.TrackRow {
                K.TrackHeader(title: "Title", symbol: "square.on.square")
            } lane: {
                lane { w in
                    K.ClipBar(title: "lower-third", kind: .component, keys: [0.15, 0.8])
                        .frame(width: w * 0.34).offset(x: w * 0.06)
                }
            }
            K.TrackRow {
                K.TrackHeader(title: "V1", symbol: "photo")
            } lane: {
                lane { w in
                    K.ClipBar(title: "intro.mov", kind: .video, isSelected: true, keys: [0.3, 0.7])
                        .frame(width: w * 0.40 - 2)
                    K.ClipBar(title: "demo.mov", kind: .videoAlternate, speed: "2x")
                        .frame(width: w * 0.44).offset(x: w * 0.40 + 2)
                    K.TransitionBand()
                        .frame(width: w * 0.06).offset(x: w * 0.37)
                }
            }
            K.TrackRow {
                K.TrackHeader(title: "Caption", isAutomatic: true)
            } lane: {
                lane { w in
                    K.ClipBar(title: "Capture, design", kind: .text)
                        .frame(width: w * 0.28).offset(x: w * 0.08)
                    K.ClipBar(title: "automate", kind: .text, isTrimming: true)
                        .frame(width: w * 0.34).offset(x: w * 0.44)
                }
            }
            K.TrackRow {
                K.TrackHeader(title: "Audio", symbol: "waveform")
            } lane: {
                lane { w in
                    K.ClipBar(title: "music.wav", kind: .audio,
                              levels: (0..<26).map { Double(24 + ($0 * 37) % 62) / 100 })
                        .frame(width: w * 0.92)
                }
            }
        }
        .overlay(alignment: .topLeading) {
            // The playhead lives in the lanes' column and spans every track.
            K.Playhead(fraction: 4.12 / 15)
                .padding(.leading, K.Metrics.trackHeaderWidth + K.Metrics.trackGap)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background(K.Palette.panel)
    }

    private func lane<C: View>(@ViewBuilder _ content: @escaping (CGFloat) -> C) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) { content(geo.size.width) }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
        }
    }
}

struct TilesSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            K.TileGrid {
                K.Tile(name: "intro.mov", detail: "0:06 · 1080p", isSelected: true) {
                    LinearGradient(colors: [K.rgb(0x12C2E9), K.rgb(0x7C4DFF)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                K.Tile(name: "demo.mov", detail: "0:08 · 1080p") {
                    LinearGradient(colors: [K.rgb(0x7C4DFF), K.rgb(0xFF5D8F)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                K.Tile(name: "Lower-third", detail: "component", emphasis: .component) {
                    LinearGradient(colors: [K.rgb(0x9A5CFF), K.rgb(0xC56CFF)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            .frame(width: 240)
            K.TileGrid(columns: 2) {
                ForEach(Array(zip(["Cross dissolve", "Dip to black", "Slide", "Push"],
                                  [K.TransitionThumbnail.Style.dissolve, .dipToBlack, .slide, .push])),
                        id: \.0) { name, style in
                    K.Tile(name: name, detail: "0.5s", isSelected: style == .dissolve,
                           isDisabled: style == .push, emphasis: .cut, thumbnailHeight: 30) {
                        K.TransitionThumbnail(style: style)
                    }
                }
            }
            .frame(width: 240)
        }
        .padding(12)
        .background(K.Palette.panel)
    }
}

struct ControlsSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                K.KeyDiamond(state: .dormant)
                K.KeyDiamond(state: .armed)
                K.KeyDiamond(state: .onKey)
                K.KeyDiamond(state: .dormant, isHovering: true)
            }
            K.FieldRow(label: "Easing") { K.SelectFace(value: "Ease in out", size: .small) }
            K.FieldRow(label: "Style") {
                K.SelectFace(value: "Caption / Bold",
                             swatch: AnyShapeStyle(LinearGradient(colors: [K.rgb(0x7C4DFF), K.rgb(0xFF5D8F)],
                                                                  startPoint: .topLeading,
                                                                  endPoint: .bottomTrailing)))
            }
            K.FieldRow(label: "Variant") { K.SelectFace(value: "Name + role", isComponent: true) }
        }
        .padding(12)
        .frame(width: 260, alignment: .leading)
        .background(K.Palette.panel)
    }
}

/// The dropdown row with its REAL menu. ImageRenderer cannot draw an AppKit
/// menu button, so this one goes through a hosting view, which proves the face
/// survives being a menu's label.
struct LiveDropdownSheet: View {
    var body: some View {
        K.DropdownRow(label: "Easing", value: "Ease in out") {
            Button("Linear") {}
            Button("Ease in out") {}
        }
        .padding(12)
        .frame(width: 260, alignment: .leading)
        .background(K.Palette.panel)
    }
}

// MARK: - Writing them out

@MainActor
func write(_ view: some View, width: CGFloat, to url: URL) {
    let renderer = ImageRenderer(content: view.frame(width: width).environment(\.colorScheme, .dark))
    renderer.scale = 2
    guard let image = renderer.cgImage else {
        FileHandle.standardError.write(Data("could not render \(url.lastPathComponent)\n".utf8))
        exit(1)
    }
    save(NSBitmapImageRep(cgImage: image), to: url)
}

@MainActor
func writeHosted(_ view: some View, size: CGSize, to url: URL) {
    let host = NSHostingView(rootView: view.environment(\.colorScheme, .dark))
    host.appearance = NSAppearance(named: .darkAqua)
    host.frame = CGRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { exit(1) }
    host.cacheDisplay(in: host.bounds, to: rep)
    save(rep, to: url)
}

func save(_ rep: NSBitmapImageRep, to url: URL) {
    guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
    do { try png.write(to: url) } catch {
        FileHandle.standardError.write(Data("could not write \(url.path): \(error)\n".utf8))
        exit(1)
    }
    print("wrote \(url.path) \(rep.pixelsWide)x\(rep.pixelsHigh)")
}

@main
struct Gallery {
    @MainActor static func main() {
        let args = CommandLine.arguments
        let out = URL(fileURLWithPath: args.count > 1 ? args[1] : "docs/design/mocks/shared/video-kit")
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        _ = NSApplication.shared
        write(TransportSheet(), width: 640, to: out.appendingPathComponent("kit-transport.png"))
        write(TimelineSheet(), width: 640, to: out.appendingPathComponent("kit-timeline.png"))
        write(TilesSheet(), width: 264, to: out.appendingPathComponent("kit-tiles.png"))
        write(ControlsSheet(), width: 260, to: out.appendingPathComponent("kit-controls.png"))
        writeHosted(LiveDropdownSheet(), size: CGSize(width: 260, height: 48),
                    to: out.appendingPathComponent("kit-dropdown-live.png"))
    }
}
