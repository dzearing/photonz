import AppKit
import PhotonzCore
import SwiftUI

// View | Edit, at the right of the title bar of a window holding a document
// with time (`ViewEditMode`). It rides in the same title bar accessory as the
// panel toggle (`TitlebarPanelToggle`), to that button's left, so the two can
// never swap places whichever was installed first.
//
// A real NSSegmentedControl rather than a drawn one: a switch in a Mac title
// bar is the system's own control, with the system's glass and the system's
// press, the way Finder's view switcher and Xcode's editor switcher are.

extension Animation {
    /// View and Edit coming and going: everything that folds away does it on
    /// this one curve, so nothing lands before anything else.
    static let viewEditMode = Animation.smooth(duration: ViewEditMode.transitionSeconds)
}

/// The switch as it sits in the title bar: the control, plus a marker over
/// each half so a walk can press View or Edit by name.
struct TitlebarViewEditSwitch: View {
    @Environment(EditorState.self) private var editorState

    /// Wide enough for both words at the system's size, and no wider.
    static let width: CGFloat = 108
    /// Between the switch and the panel toggle.
    static let gap: CGFloat = 6

    var body: some View {
        let mode = editorState.viewEditMode
        ViewEditSegmentedControl(mode: mode) { editorState.setViewEditMode($0) }
            .frame(width: Self.width)
            .overlay {
                HStack(spacing: 0) {
                    ForEach(ViewEditMode.allCases, id: \.self) { each in
                        Color.clear
                            .playtestControl(each.menuTitle,
                                             detail: mode == each ? "the title bar's switch, on"
                                                                  : "the title bar's switch")
                    }
                }
                .allowsHitTesting(false)
            }
            .panelReadout("\(mode.title) mode")
    }
}

/// The system's segmented control, two segments, one picked.
struct ViewEditSegmentedControl: NSViewRepresentable {
    let mode: ViewEditMode
    let pick: (ViewEditMode) -> Void

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: ViewEditMode.allCases.map(\.title),
                                         trackingMode: .selectOne,
                                         target: context.coordinator,
                                         action: #selector(Coordinator.changed(_:)))
        control.segmentStyle = .automatic
        control.controlSize = .small
        control.segmentDistribution = .fillEqually
        control.setAccessibilityLabel("View or Edit")
        for (index, each) in ViewEditMode.allCases.enumerated() {
            control.setToolTip("\(each.title) (⌘\(each.commandKey))", forSegment: index)
        }
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.pick = pick
        let index = ViewEditMode.allCases.firstIndex(of: mode) ?? 0
        if control.selectedSegment != index { control.selectedSegment = index }
    }

    func makeCoordinator() -> Coordinator { Coordinator(pick: pick) }

    @MainActor
    final class Coordinator: NSObject {
        var pick: (ViewEditMode) -> Void
        init(pick: @escaping (ViewEditMode) -> Void) { self.pick = pick }

        @objc func changed(_ control: NSSegmentedControl) {
            let all = ViewEditMode.allCases
            guard all.indices.contains(control.selectedSegment) else { return }
            pick(all[control.selectedSegment])
        }
    }
}
