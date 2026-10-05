#if DEBUG
import AppKit
import PhotonzCore
import SwiftUI

/// Every specimen the legibility check draws (`LegibilitySheet`): the shared
/// controls that carry words or an icon, each in the states it can be drawn
/// in. A new shared control that carries words gets its specimens here.
///
/// A specimen draws the SHIPPED control, never a copy of its colours: a copy
/// would pass while the control drifted. Hover and press are told from
/// outside through `shownPointer`, which the app's hover seam and the button
/// styles answer; states a control takes as a value (selected, open, picked,
/// disabled) are passed the way the app passes them.
@MainActor
enum LegibilityCatalogue {
    typealias Specimen = LegibilitySheet.Specimen
    private typealias Kit = VideoKit

    static var specimens: [Specimen] {
        segmented + buttons + panel + timeline + transport + tiles + overlays + captions
    }

    /// The pointer states every button style is drawn in.
    private static let pointers: [(String, Kit.ShownPointer)] =
        [("rest", .live), ("hovered", .hovered), ("pressed", .pressed)]

    private static func symbol(_ name: String) -> Image { Image(systemName: name) }

    // MARK: - The segmented control

    private static func segments(_ words: [String], on: Int?, size: SegmentedControl<Int>.Size = .regular,
                                 form: SegmentedControl<Int>.Form = .fill, width: CGFloat = 240,
                                 hovered: Int? = nil, unavailable: Int? = nil, focused: Bool = false,
                                 travel: CGFloat? = nil, pictures: [String]? = nil) -> AnyView {
        let control = DesignedSegments<Int>(
            label: "Specimen",
            options: words.indices.map { index in
                .init(index, words[index],
                      image: pictures.flatMap { NSImage(systemSymbolName: $0[index],
                                                        accessibilityDescription: words[index]) },
                      disabledReason: index == unavailable ? "Not now" : nil)
            },
            selection: on, size: size, form: form, showsTitles: pictures == nil, tipsBelow: false,
            shownHovered: hovered, shownFocused: focused, shownTravel: travel, glassAsPaint: true) { _ in }
        return AnyView(control
            .frame(width: form == .fill ? width : nil)
            .fixedSize(horizontal: form == .natural, vertical: false))
    }

    private static var segmented: [Specimen] {
        let fillFitCrop = ["Fill", "Fit", "Crop"], lcr = ["Left", "Center", "Right"]
        let name = "Segmented control"
        return [
            Specimen(control: name, state: "rest", ground: .glass, inks: 3) { segments(fillFitCrop, on: 1) },
            Specimen(control: name, state: "hovered", ground: .glass, inks: 3) {
                segments(fillFitCrop, on: 1, hovered: 0) },
            Specimen(control: name, state: "one unavailable", ground: .glass, inks: 3) {
                segments(["Fill", "Fit", "Stretch"], on: 0, unavailable: 2) },
            Specimen(control: name, state: "disabled", ground: .glass, disabled: true, inks: 3) {
                AnyView(segments(fillFitCrop, on: 1).disabled(true)) },
            Specimen(control: name, state: "focused", ground: .glass, inks: 3) {
                segments(fillFitCrop, on: 0, focused: true) },
            Specimen(control: name, state: "nothing picked", ground: .glass, inks: 2) {
                segments(["Hug", "Fixed"], on: nil) },
            Specimen(control: name, state: "chip a third of the way", ground: .glass, inks: 3) {
                segments(lcr, on: 2, travel: 0.33) },
            Specimen(control: name, state: "chip half way", ground: .glass, inks: 3) {
                segments(lcr, on: 2, travel: 0.5) },
            Specimen(control: name, state: "chip most of the way", ground: .glass, inks: 3) {
                segments(lcr, on: 2, travel: 0.8) },
            Specimen(control: name, state: "small", ground: .glass, inks: 3) {
                segments(["All", "Text", "Shapes"], on: 2, size: .small, form: .natural) },
            Specimen(control: name, state: "large", ground: .glass, inks: 3) {
                segments(["All", "Text", "Shapes"], on: 0, size: .large, form: .natural) },
            Specimen(control: "Title bar View | Edit", state: "Edit picked", ground: .glass, inks: 2) {
                segments(["View", "Edit"], on: 1, size: .small, width: 96) },
            Specimen(control: "Title bar View | Edit", state: "View picked, Edit hovered", ground: .glass,
                     inks: 2) { segments(["View", "Edit"], on: 0, size: .small, width: 96, hovered: 1) },
            Specimen(control: "History filter", state: "All picked", ground: .glass, inks: 3) {
                segments(["All", "Screenshots", "Videos"], on: 0, form: .natural) },
            Specimen(control: "Segmented pictures", state: "rest", ground: .glass, inks: 3) {
                segments(["Left", "Centre", "Right"], on: 0, form: .natural,
                         pictures: ["text.alignleft", "text.aligncenter", "text.alignright"]) },
        ]
    }

    // MARK: - Buttons

    private static var buttons: [Specimen] {
        var all: [Specimen] = []
        for (state, pointer) in pointers {
            all.append(Specimen(control: "Pill button", state: state, ground: .glass) {
                AnyView(Button("Clear All") {}.buttonStyle(PillActionButtonStyle())
                    .environment(\.shownPointer, pointer))
            })
            all.append(Specimen(control: "Pill button, prominent", state: state, ground: .glass) {
                AnyView(Button("Edit") {}.buttonStyle(PillActionButtonStyle(prominent: true))
                    .environment(\.shownPointer, pointer))
            })
            all.append(Specimen(control: "Pill button, destructive", state: state, ground: .glass) {
                AnyView(Button("Delete", role: .destructive) {}.buttonStyle(PillActionButtonStyle())
                    .environment(\.shownPointer, pointer))
            })
            all.append(Specimen(control: "Icon button", state: state, ground: .glass, inks: 2) {
                AnyView(HStack {
                    Button {} label: { symbol("square.and.arrow.up") }
                    Button(role: .destructive) {} label: { symbol("trash") }
                }
                .buttonStyle(IconActionButtonStyle())
                .environment(\.shownPointer, pointer))
            })
            all.append(Specimen(control: "Tool bar button", state: state, ground: .glass, inks: 2) {
                AnyView(HStack(spacing: 2) {
                    Button {} label: { symbol("cursorarrow").font(.system(size: 15, weight: .medium)) }
                        .buttonStyle(.tool(isActive: false))
                    Button {} label: { symbol("textformat").font(.system(size: 15, weight: .medium)) }
                        .buttonStyle(.tool(isActive: true))
                }
                .environment(\.shownPointer, pointer))
            })
            all.append(Specimen(control: "Caption bar button", state: state, ground: .panel, inks: 2) {
                AnyView(HStack {
                    Button {} label: { Label("Listen", systemImage: "waveform") }
                        .buttonStyle(CaptionBarButtonStyle())
                    Button {} label: { Label("Style", systemImage: "textformat") }
                        .buttonStyle(CaptionBarButtonStyle(filled: true))
                }
                .environment(\.shownPointer, pointer))
            })
            all.append(Specimen(control: "Transport button", state: state, ground: .panel, inks: 2) {
                AnyView(HStack {
                    Kit.TransportButton(symbol: "backward.end.fill", label: "Back") {}
                    Kit.TransportButton(symbol: "play.fill", label: "Play", role: .primary) {}
                }
                .environment(\.shownPointer, pointer))
            })
        }
        all += [
            Specimen(control: "Pill button", state: "disabled", ground: .glass, disabled: true) {
                AnyView(Button("Clear All") {}.buttonStyle(PillActionButtonStyle()).disabled(true))
            },
            Specimen(control: "Icon button", state: "disabled", ground: .glass, disabled: true) {
                AnyView(Button {} label: { symbol("trash") }.buttonStyle(IconActionButtonStyle()).disabled(true))
            },
            Specimen(control: "Caption bar button", state: "disabled", ground: .panel, disabled: true) {
                AnyView(Button {} label: { Label("Listen", systemImage: "waveform") }
                    .buttonStyle(CaptionBarButtonStyle()).disabled(true))
            },
        ]
        return all
    }

    /// Every shared button style that answers the pointer, for the check that
    /// a disabled one does not (`LegibilitySheet.stillUnderThePointer`). The
    /// sheet disables each and draws it at rest, hovered and pressed.
    static var pointerStill: [(String, (VideoKit.ShownPointer) -> AnyView)] {
        [
            ("Icon button", { pointer in
                AnyView(Button {} label: { symbol("trash") }.buttonStyle(IconActionButtonStyle())
                    .environment(\.shownPointer, pointer)) }),
            ("Tool bar button", { pointer in
                AnyView(Button {} label: { symbol("cursorarrow").font(.system(size: 15, weight: .medium)) }
                    .buttonStyle(.tool(isActive: false))
                    .environment(\.shownPointer, pointer)) }),
            ("Pill button", { pointer in
                AnyView(Button("Clear All") {}.buttonStyle(PillActionButtonStyle())
                    .environment(\.shownPointer, pointer)) }),
            ("Pill button, prominent", { pointer in
                AnyView(Button("Edit") {}.buttonStyle(PillActionButtonStyle(prominent: true))
                    .environment(\.shownPointer, pointer)) }),
            ("Caption bar button", { pointer in
                AnyView(Button {} label: { Label("Listen", systemImage: "waveform") }
                    .buttonStyle(CaptionBarButtonStyle())
                    .environment(\.shownPointer, pointer)) }),
        ]
    }

    // MARK: - The panel

    private static var panel: [Specimen] {
        [
            Specimen(control: "Panel row", state: "label and value", ground: .panel, inks: 2) {
                AnyView(PanelFieldRow("Opacity") { Kit.ValueFace(value: "100%") }.frame(width: 260))
            },
            Specimen(control: "Panel row label", state: "rest", ground: .panel) {
                AnyView(PanelRowLabel(text: "Corner radius"))
            },
            Specimen(control: "Kit field row", state: "rest", ground: .panel, inks: 2) {
                AnyView(Kit.FieldRow(label: "Speed") { Kit.ValueFace(value: "1x") }.frame(width: 260))
            },
            Specimen(control: "Dropdown face", state: "rest", ground: .panel) {
                AnyView(Kit.SelectFace(value: "Cross dissolve").frame(width: 180))
            },
            Specimen(control: "Dropdown face", state: "hovered", ground: .panel) {
                AnyView(Kit.SelectFace(value: "Cross dissolve").frame(width: 180)
                    .environment(\.shownPointer, .hovered))
            },
            Specimen(control: "Dropdown face", state: "open", ground: .panel) {
                AnyView(Kit.SelectFace(value: "Cross dissolve", isOpen: true).frame(width: 180))
            },
            Specimen(control: "Dropdown face", state: "component, small", ground: .panel) {
                AnyView(Kit.SelectFace(value: "Pulse", size: .small, isComponent: true).frame(width: 140))
            },
            Specimen(control: "Dropdown face", state: "mixed, small", ground: .panel) {
                AnyView(Kit.SelectFace(value: LayerStyleSelection.mixedText, size: .small,
                                       valueStyle: MixedLook.style).frame(width: 140))
            },
            Specimen(control: "Section header", state: "rest", ground: .panel) {
                AnyView(section(collapsed: false))
            },
            Specimen(control: "Section header", state: "hovered", ground: .panel) {
                AnyView(section(collapsed: false).environment(\.shownPointer, .hovered))
            },
            Specimen(control: "Section header", state: "folded", ground: .panel) {
                AnyView(section(collapsed: true))
            },
            Specimen(control: "Header chip", state: "rest", ground: .panel) {
                AnyView(DockHeaderChip(content: .init(text: "Text layer", field: "Properties Kind")))
            },
            Specimen(control: "Style drop note", state: "lands", ground: .panel) {
                AnyView(StyleRowDropNote(drop: StyleRowDrop(rowID: UUID(), lands: true,
                                                            note: "Wears Heading", layerIDs: []))
                    .frame(width: 220))
            },
            Specimen(control: "Style drop note", state: "refused", ground: .panel) {
                AnyView(StyleRowDropNote(drop: StyleRowDrop(rowID: UUID(), lands: false,
                                                            note: "Not text", layerIDs: []))
                    .frame(width: 220))
            },
        ]
    }

    private static func section(collapsed: Bool) -> some View {
        CollapsibleSection(title: "Appearance", isCollapsed: collapsed, onToggle: {},
                           onReorder: { _, _ in }, onReorderEnd: {}) {
            PanelRowLabel(text: "Fill")
        }
        .frame(width: 260)
    }

    // MARK: - The timeline

    private static var timeline: [Specimen] {
        var all: [Specimen] = [
            Specimen(control: "Track header", state: "rest", ground: .panel, inks: 2) {
                AnyView(Kit.TrackHeader(title: "Video", symbol: "film"))
            },
            Specimen(control: "Track header", state: "selected", ground: .panel, inks: 2) {
                AnyView(Kit.TrackHeader(title: "Video", symbol: "film", isSelected: true))
            },
            Specimen(control: "Track header", state: "automatic", ground: .panel, inks: 2) {
                AnyView(Kit.TrackHeader(title: "Caption", isAutomatic: true))
            },
            Specimen(control: "Time ruler", state: "rest", ground: .panel, inks: 3) {
                AnyView(Kit.TimeRuler(ticks: [.init(fraction: 0, label: "0:00"), .init(fraction: 0.5, label: "0:05"),
                                              .init(fraction: 1, label: "0:10")])
                    .frame(width: 300))
            },
        ]
        for kind in Kit.ClipKind.allCases where kind != .audio {
            for (state, selected, pointer) in [("rest", false, Kit.ShownPointer.live),
                                               ("selected", true, .live), ("hovered", false, .hovered)] {
                all.append(Specimen(control: "Clip \(kind)", state: state, ground: .panel) {
                    AnyView(Kit.ClipBar(title: "Intro take", kind: kind, isSelected: selected)
                        .frame(width: 180)
                        .environment(\.shownPointer, pointer))
                })
            }
        }
        all.append(Specimen(control: "Clip speed badge", state: "retimed", ground: .panel, inks: 2) {
            AnyView(Kit.ClipBar(title: "Intro take", kind: .video, speed: "2x").frame(width: 180))
        })
        all.append(Specimen(control: "Timeline time capsule", state: "rest", ground: .panel) {
            AnyView(ClipPiecesBar.capsule("0:04.20", x: 0, laneWidth: 300).frame(width: 300, alignment: .leading))
        })
        return all
    }

    // MARK: - The transport

    private static var transport: [Specimen] {
        [
            Specimen(control: "Transport", state: "rest", ground: .panel, inks: 5) {
                AnyView(Kit.TransportBar(current: "0:04", duration: "0:12") {
                    Kit.TransportButton(symbol: "speaker.wave.2.fill", label: "Volume") {}
                } controls: {
                    Kit.TransportButton(symbol: "backward.end.fill", label: "Back") {}
                    Kit.TransportButton(symbol: "play.fill", label: "Play", role: .primary) {}
                } scrubber: {
                    Kit.Scrubber(fraction: 0.35) { _, _ in }
                }
                .frame(width: 520))
            },
        ]
    }

    // MARK: - Picker tiles

    private static var tiles: [Specimen] {
        var all: [Specimen] = []
        let thumbnail = { AnyView(Rectangle().fill(Color(white: 0.3))) }
        for (state, selected, disabled, pointer) in [("rest", false, false, Kit.ShownPointer.live),
                                                     ("hovered", false, false, .hovered),
                                                     ("selected", true, false, .live),
                                                     ("disabled", false, true, .live)] {
            for emphasis in [Kit.Tile<AnyView>.Emphasis.accent, .component, .cut] {
                all.append(Specimen(control: "Picker tile, \(emphasis)", state: state, ground: .panel,
                                    disabled: disabled, inks: 2) {
                    AnyView(Kit.Tile(name: "Dissolve", detail: "0.5s", isSelected: selected, isDisabled: disabled,
                                     emphasis: emphasis, thumbnailHeight: 30, thumbnail: thumbnail)
                        .frame(width: 120)
                        .environment(\.shownPointer, pointer))
                })
            }
        }
        return all
    }

    // MARK: - Tooltips, toasts, badges

    private static var overlays: [Specimen] {
        [
            Specimen(control: "Tooltip", state: "label and key", ground: .own, inks: 2) {
                AnyView(HintTooltipView(label: "Blade", key: "B", side: .top, beakX: 30).fixedSize())
            },
            Specimen(control: "Tooltip", state: "with a line of help", ground: .own, inks: 3) {
                AnyView(HintTooltipView(label: "Blade", key: "B", detail: "Click a clip to cut it",
                                        side: .bottom, beakX: 30).fixedSize())
            },
            Specimen(control: "Note toast", state: "rest", ground: .glass, inks: 3) {
                AnyView(NoteToastView(title: "Saved to Desktop", detail: "Recording 12.mp4",
                                      symbol: "checkmark", onDismiss: {}, holdSeconds: 60, fadeSeconds: 1))
            },
            Specimen(control: "Progress toast", state: "part way", ground: .glass, inks: 2) {
                let progress = ToastProgress(title: "Preparing GIF")
                progress.update(fraction: 0.4)
                return AnyView(ProgressToastView(progress: progress))
            },
            Specimen(control: "Video badge", state: "on a picture", ground: .anything, inks: 2) {
                AnyView(VideoBadgeOverlay(duration: 83).frame(width: 160, height: 100))
            },
            Specimen(control: "Title bar mode chip", state: "rest", ground: .panel, inks: 2) {
                AnyView(TitlebarModeChip().fixedSize())
            },
        ]
    }

    // MARK: - Caption previews

    private static var captions: [Specimen] {
        CaptionLook.Preset.allCases.map { preset in
            Specimen(control: "Caption preview, \(preset.title)", state: "still", ground: .own) {
                AnyView(CaptionStylePreview(look: CaptionLook.preset(preset)).frame(width: 150, height: 84))
            }
        }
    }
}
#endif
