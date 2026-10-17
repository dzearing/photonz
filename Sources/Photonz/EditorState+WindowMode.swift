import Foundation
import PhotonzCore

/// What this window is set up for (Next, `next-window-modes`;
/// `docs/design/modes.md`).
///
/// The mode is the WINDOW's: a picture's window starts in Image and offers
/// Image, Icon and Design; a document with time is always in the video setup,
/// offers nothing and draws no chip. How each mode is arranged is the app's
/// (`WindowModeStore`), so the panel this window draws is the arrangement of
/// the mode it is in, and a section ticked in the Sections list is kept for
/// that mode.
///
/// With modes off the panel's choices are the one app-wide set they always
/// were (`PanelSectionVisibilityStore`), and nothing here is consulted.
extension EditorState {

    private var modesOn: Bool { Experiments.shared.windowModesEnabled }

    /// The mode this window is in for what it holds.
    var windowMode: WindowMode { windowModeSession.mode(hasTime: documentHasTime) }

    /// The mode, only when modes are running: what the tool bar and the tool
    /// memory read, so nothing changes in a release without them.
    var activeWindowMode: WindowMode? { modesOn ? windowMode : nil }

    /// The modes this window offers: Image, Icon and Design for a picture,
    /// none for a document with time.
    var offeredWindowModes: [WindowMode] { WindowModes.offered(hasTime: documentHasTime) }

    /// Whether the title bar draws the chip: a document open, and more than
    /// one mode to be in.
    var showsWindowModeChip: Bool {
        modesOn && hasDocument && WindowModeSession.showsChip(hasTime: documentHasTime)
    }

    /// What the chip reads: the mode's name, and whether you have bent it.
    var windowModeLabel: String {
        windowModeSession.chipLabel(hasTime: documentHasTime,
                                    arrangements: WindowModeStore.shared.arrangements)
    }

    var isWindowModeBent: Bool { WindowModeStore.shared.isBent(windowMode.id) }

    /// Move this window into another mode. Does nothing for a mode this
    /// document is not offered: Video on a picture, anything on a recording.
    @discardableResult
    func swapWindowMode(to id: String) -> Bool {
        guard modesOn else { return false }
        var next = windowModeSession
        guard next.swap(to: id, hasTime: documentHasTime) else { return false }
        windowModeSession = next
        return true
    }

    /// Put this window's mode back the way it shipped, without leaving it.
    func resetWindowMode() {
        WindowModeStore.shared.reset(windowMode.id)
    }

    /// Hand the lot back: a picture lands in Image with nothing folded, a
    /// recording unfolds its own setup.
    func showEverythingInWindow() {
        var next = windowModeSession
        WindowModeStore.shared.showEverything(&next, hasTime: documentHasTime)
        windowModeSession = next
    }

    // MARK: The panel's choices, for this window

    /// The optional sections this window's panel has been told yes or no to.
    var panelChoices: PanelSectionVisibility.Choices {
        modesOn ? WindowModeStore.shared.arrangement(of: windowMode.id)
                : PanelSectionVisibilityStore.shared.choices
    }

    private func setPanelChoices(_ choices: PanelSectionVisibility.Choices) {
        if modesOn {
            WindowModeStore.shared.keep(choices, for: windowMode.id)
        } else {
            PanelSectionVisibilityStore.shared.choices = choices
        }
    }

    func setPanelSection(_ section: InspectorSectionID, shown: Bool) {
        var next = panelChoices
        next.set(section.rawValue, shown: shown)
        setPanelChoices(next)
    }

    func useAutomaticPanelSection(_ section: InspectorSectionID) {
        var next = panelChoices
        next.useAutomatic(for: section.rawValue)
        setPanelChoices(next)
    }

    /// Every section back to automatic. With modes running that is the same
    /// act as Show Everything: a panel with nothing folded while the chip
    /// still claimed Icon would be a window that has quietly stopped being
    /// what it says it is.
    func useAutomaticForAllPanelSections() {
        if modesOn {
            showEverythingInWindow()
        } else {
            PanelSectionVisibilityStore.shared.useAutomaticForAll()
        }
    }
}
