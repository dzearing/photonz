import SwiftUI

/// One entry in a tool's mode list: what it is called, the glyph the tool
/// button wears while it is live, and what a click does in it.
struct ToolMode<Mode: Hashable>: Identifiable {
    let mode: Mode
    let title: String
    let symbol: String
    let help: String

    var id: Mode { mode }
}

/// A tool button that owns its own modes (UX-PATTERNS D15).
///
/// The floating tool bar is a fixed, scarce strip, so its width must not grow
/// with whichever tool happens to be selected. A tool with more than one mode
/// therefore keeps them inside its button rather than spreading chips beside
/// it: the button wears the live mode's glyph, and the modes are one press-and-
/// hold (or one click on the chevron) away.
///
/// This is deliberately built on `Menu(primaryAction:)` rather than a bespoke
/// popover. The tool bar already uses that control for its selection slot
/// (rectangle / ellipse / wand), so a second, hand-rolled "there is more inside
/// me" idiom in the same 300pt strip would read as drift. It also means press-
/// and-hold, dismissal on pick, Escape and outside click, and arrow-key
/// navigation all come from the system instead of from us. Sitting at the foot
/// of the window, the menu opens upward on its own.
///
/// The keyboard is the fast path: the tool's own key picks the tool up, and
/// pressing it again cycles the modes without opening anything. That lives on a
/// separate zero-size button so the visible one stays idempotent, because a
/// click on the tool you already hold must never quietly change what your next
/// click does.
///
/// A tool with exactly one mode renders as a plain tool button: no chevron, no
/// menu. The affordance shows up only when there is a choice.
struct ToolModeButton<Mode: Hashable>: View {
    /// The tool's display name, for the tooltip.
    let toolTitle: String
    /// The tool's key, which both picks the tool up and cycles its modes.
    /// Comes from `Tool.shortcutKey`; nil for a tool whose letter is resolved
    /// by a group rather than by the tool itself.
    let key: KeyEquivalent?
    /// Whether this tool is the one in hand.
    let isActive: Bool
    /// Every mode on offer, in cycle order. One entry means no menu.
    let modes: [ToolMode<Mode>]
    /// The live mode. Writing it switches modes; it is never used to activate.
    @Binding var selection: Mode
    /// The namespace the tool bar's sliding accent circle lives in.
    let namespace: Namespace.ID
    /// Picks this tool up (without touching the mode).
    let activate: () -> Void
    /// Whether pressing the tool's key again walks the modes. True for a tool
    /// whose modes only change what the NEXT click does, so a stray press costs
    /// nothing. False for one where switching mode reshapes work already on the
    /// canvas (Crop refits the rect you just dragged): there the mode has to be
    /// a deliberate pick, and the key stays a plain "pick this tool up". Only
    /// the wording changes here; `pressedKey` is what actually decides.
    var keyCycles: Bool = true
    /// Extra rows at the foot of the list, below the modes: a command that
    /// belongs to the same family but is not a mode (Crop carries Resize
    /// Image, since both change the picture's bounds). Nil for none.
    var footer: AnyView? = nil
    /// What the tool's key does: pick the tool up, or, when it is already in
    /// hand, move to the next mode. The caller decides from LIVE state rather
    /// than from `isActive`, because a keyboard shortcut's action is registered
    /// once and can outlive the snapshot it was built from — a stale `isActive`
    /// would leave the key re-picking a tool that is already in hand and never
    /// cycling.
    let pressedKey: () -> Void

    private var current: ToolMode<Mode>? {
        modes.first { $0.mode == selection } ?? modes.first
    }

    private var keyLabel: String? {
        key.map { String(describing: $0.character).uppercased() }
    }

    /// " (A)", or nothing at all when the tool has no letter of its own.
    private var keySuffix: String {
        keyLabel.map { " (\($0))" } ?? ""
    }

    private var tooltip: String {
        guard let current else { return "\(toolTitle)\(keySuffix)" }
        guard modes.count > 1 else { return "\(current.help)\(keySuffix)" }
        guard let keyLabel else { return "\(current.help)\nPress and hold for the list." }
        guard keyCycles else { return "\(current.help)\(keySuffix)\nPress and hold for the list." }
        return "\(current.help)\n\(keyLabel) cycles modes. Press and hold for the list."
    }

    var body: some View {
        Group {
            if modes.count > 1 {
                modeMenu
            } else {
                plainButton
            }
        }
        .help(tooltip)
        // The label is a bare glyph, so without this the button reaches
        // VoiceOver as an unnamed pop-up. Name the tool AND the live mode,
        // since the mode is the thing the glyph is saying.
        .accessibilityLabel(current.map { "\(toolTitle): \($0.title)" } ?? toolTitle)
        .overlay { cycleKey }
    }

    /// The glyph, wearing the accent circle when this tool is the one in hand,
    /// and a corner marker when it has modes to offer.
    private var glyph: some View {
        Image(systemName: current?.symbol ?? "questionmark")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(isActive ? Color.white : Color.primary)
            .frame(width: 28, height: 28)
            .background {
                if isActive {
                    Circle().fill(Color.accentColor)
                        .matchedGeometryEffect(id: "activeTool", in: namespace)
                }
            }
            .overlay(alignment: .bottomTrailing) { moreMarker }
    }

    /// ONE control, not two. SwiftUI's own menu indicator hangs a second chevron
    /// off the side of the button: at tool-bar scale that reads as a separate
    /// widget sitting next to the tool, and it spends horizontal space the bar
    /// does not have. The marker is a tiny wedge INSIDE the button's own
    /// footprint instead (`ToolBarMoreMarker`, shared with the tool groups),
    /// which is how a pro editor has always flagged a tool group, and it costs
    /// zero extra width.
    @ViewBuilder private var moreMarker: some View {
        if modes.count > 1 {
            ToolBarMoreMarker(isActive: isActive)
        }
    }

    private var plainButton: some View {
        Button(action: activate) { glyph }
    }

    /// Click picks the tool up; press-and-hold or the chevron opens the modes.
    private var modeMenu: some View {
        Menu {
            Picker(toolTitle, selection: $selection) {
                ForEach(modes) { mode in
                    Label(mode.title, systemImage: mode.symbol).tag(mode.mode)
                }
            }
            .pickerStyle(.inline)
            if keyCycles, let keyLabel {
                Divider()
                // One line for the whole list, because every mode shares the
                // tool's key: printing the same letter on four rows would say
                // nothing.
                Text("Press \(keyLabel) to cycle")
            }
            if let footer {
                Divider()
                footer
            }
        } label: {
            glyph
        } primaryAction: {
            activate()
        }
        // Hidden, because the glyph carries its own corner marker: with this
        // visible the button became a glyph AND a detached chevron, two things
        // to look at and two slots wide for one tool.
        .menuIndicator(.hidden)
        .menuStyle(.button)
        // Plain, not borderless: a `Menu` with a primary action under the
        // borderless style draws its label at about two thirds strength, so
        // this button sat in the bar looking disabled beside the plain tool
        // buttons (measured 155 vs 244 on a real capture). The plain style
        // leaves the glyph's own foreground alone and keeps the click and
        // the press-and-hold.
        .buttonStyle(.plain)
        .fixedSize()
    }

    /// The tool's key: picks the tool up, or cycles its modes when it is
    /// already in hand. Invisible and unhittable, so the visible button can
    /// stay a plain "pick this tool up" and nothing else.
    private var cycleKey: some View {
        Button {
            pressedKey()
        } label: {
            Color.clear.frame(width: 0, height: 0)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(key.map { KeyboardShortcut($0, modifiers: []) })
        .frame(width: 0, height: 0)
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
