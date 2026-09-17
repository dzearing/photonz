import PhotonzCore
import SwiftUI

/// The one row at the foot of the right hand panel that says which sections it
/// is showing, and lets you say otherwise (Next, `next-panel-sections`).
///
/// It is a ROW, not a section. It has no chevron, no grip, nothing to collapse
/// and nothing to reorder, and it sits OUTSIDE the dock's scroller so it is on
/// screen whatever the panel is scrolled to. That matters more than it sounds:
/// it is the way back to anything automatic has left out, and a way back you
/// have to scroll to find is not a way back.
///
/// It says nothing at all when the panel is showing everything it could, which
/// is the common case for somebody who never changes any of this. The moment a
/// section is out, it says how many, because "where did Measurements go" is the
/// whole risk of hiding anything.
struct PanelSectionsFooter: View {
    /// The sections the panel could be showing, as the release has them: the
    /// optional list with the ones this release does not build at all left out.
    let offered: [InspectorSectionID]
    /// What the document and the window look like, which is everything the
    /// automatic rule may read.
    let situation: PanelSectionVisibility.Situation

    @State private var isOpen = false
    @State private var store = PanelSectionVisibilityStore.shared
    @State private var escapeWatch = PanelSectionsEscapeWatch()

    /// The lines of the list, in the panel's own order.
    private var rows: [PanelSectionVisibility.Row] {
        PanelSectionVisibility.rows(for: offered.map(\.rawValue),
                                    choices: store.choices, in: situation)
    }

    private var hiddenCount: Int { rows.filter { !$0.isShown }.count }

    /// What the row reads. "Sections" alone while everything is on screen,
    /// because a number that is always zero is noise; the count as soon as
    /// there is one, because that is the only cue that anything is missing.
    private var label: String {
        hiddenCount == 0 ? "Sections"
            : "Sections · \(hiddenCount) hidden"
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.4)
            Button { isOpen.toggle() } label: {
                HStack(spacing: 5) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 9, weight: .semibold))
                    Text(label)
                        .font(.caption)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up")
                        .font(.system(size: 8, weight: .semibold))
                }
                // Quiet ink: it is furniture, not a control competing with the
                // settings above it.
                .foregroundStyle(.secondary)
                .padding(.leading, EditorChromeLayout.panelStartInset)
                .panelEdgePadding()
                .frame(height: Self.rowHeight)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .panelHelp("Choose which sections the panel shows")
            .playtestControl("Sections", detail: "the panel's section list")
            .popover(isPresented: $isOpen, arrowEdge: .bottom) {
                PanelSectionsList(offered: offered, situation: situation, store: store)
            }
            // Escape takes the list down, the way Escape takes down anything
            // that pops up, and it does NOT go on to the canvas behind it.
            .onChange(of: isOpen) { _, open in
                if open { escapeWatch.start { isOpen = false } } else { escapeWatch.stop() }
            }
            .onDisappear { escapeWatch.stop() }
        }
    }

    /// How tall the row is. The dock has to know, because every point here is a
    /// point the sections above do not get.
    static let rowHeight: CGFloat = 26
}

/// Escape, for as long as the Sections list is up.
///
/// A key WATCH rather than a key binding or `.onExitCommand`, for the reason
/// the dock's carried section and the timing strip's dragged bar both have one:
/// nothing in this list holds the keyboard, so there is no responder for a key
/// binding to hang off. The list is a popover, which is a WINDOW of its own,
/// and a window nothing has focused inside.
///
/// That is measured, not assumed. A probe run on 2026-09-17 printed the windows
/// standing over the editor with the list open:
///
///     SwiftUI.AppKitWindow|canKey=true|child=false|fr=Photonz.CanvasNSView
///     _NSPopoverWindow    |canKey=true|child=true |fr=Photonz.CanvasNSView
///
/// The popover window is there and could take the keyboard, and the first
/// responder is the CANVAS either way. So an Escape went to the canvas, which
/// cleared the selection, and the list stayed on screen: the press did the one
/// thing nobody wanted and none of the thing they asked for. Watching for the
/// key and swallowing it makes the press mean "close this list" and nothing
/// else, whoever happens to hold the keyboard.
@MainActor final class PanelSectionsEscapeWatch {
    private var monitor: Any?

    func start(_ close: @escaping () -> Void) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53 else { return event }
            close()
            // Swallowed: the press closed the list and must not go on to clear
            // the selection behind it.
            return nil
        }
    }

    func stop() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }
}

/// The list the Sections row opens: every section you are allowed to say no to,
/// what it is doing right now, and why.
///
/// The "why" is the part that earns its place. Without it there is no way to
/// tell a section you turned off from one the document simply has nothing for
/// yet, and the two need different actions from you: one you turn back on, the
/// other arrives on its own the moment you make a measurement.
struct PanelSectionsList: View {
    let offered: [InspectorSectionID]
    let situation: PanelSectionVisibility.Situation
    @Bindable var store: PanelSectionVisibilityStore

    private var rows: [PanelSectionVisibility.Row] {
        PanelSectionVisibility.rows(for: offered.map(\.rawValue),
                                    choices: store.choices, in: situation)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sections")
                .font(.subheadline.weight(.semibold))
            Text("Everything else follows the document: a section arrives when "
                 + "you start doing the thing it is for.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(zip(offered, rows)), id: \.0) { section, row in
                    line(section, row)
                }
            }
            Divider()
            Button("Use Automatic For All") { store.useAutomaticForAll() }
                .font(.caption)
                .buttonStyle(.link)
                .disabled(!store.choices.hasAnyCustom)
                .playtestControl("Use Automatic For All",
                                 detail: "hands every section back to the automatic rule")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 272)
    }

    @ViewBuilder private func line(_ section: InspectorSectionID,
                                  _ row: PanelSectionVisibility.Row) -> some View {
        // The words and the switch are laid out side by side rather than as a
        // Toggle's own label, because a switch sizes itself to its label and
        // these labels are not the same height: "Automatic" is one line and
        // "Automatic, not needed in this document yet" wraps onto two. Inside a
        // Toggle that put Motion's and Arrange's switches half way across the
        // row while everybody else's sat at the right edge, which a capture of
        // the list on 2026-09-16 shows plainly. Held apart by a Spacer, every
        // switch lands in the same column whatever its row says.
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(section.title)
                    .font(.callout)
                Text(Self.reason(row.reason))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            Toggle(section.title, isOn: Binding(
                get: { row.isShown },
                set: { store.set(section, shown: $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .playtestControl("\(section.title) section switch",
                             detail: "shows or hides that section of the panel")
            // Only a row you have answered for offers the way back, because
            // only that row has anything to go back to.
            if store.choices.isCustom(row.section) {
                Button {
                    store.useAutomatic(for: section)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .panelHelp("Back to automatic")
                .playtestControl("\(section.title) back to automatic",
                                 detail: "lets the automatic rule decide this section again")
            }
        }
    }

    /// Why this section is where it is, in the fewest words that still say it.
    private static func reason(_ reason: PanelSectionVisibility.Reason) -> String {
        switch reason {
        case .automaticallyIn: "Automatic"
        case .automaticallyOut: "Automatic, not needed in this document yet"
        case .turnedOn: "Always shown"
        case .turnedOff: "Always hidden"
        }
    }
}
