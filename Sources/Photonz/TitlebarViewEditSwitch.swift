import AppKit
import PhotonzCore
import SwiftUI

// View | Edit, at the right of the title bar of a window holding a document
// with time (`ViewEditMode`). It rides in the same title bar accessory as the
// panel toggle (`TitlebarPanelToggle`), to that button's left, so the two can
// never swap places whichever was installed first.
//
// The design system's segmented control (`SegmentedControl`), at the small
// size so it stands exactly as tall as the panel toggle beside it. Until
// 2026-09-29 this was a bare NSSegmentedControl, and the user turned it down:
// the switch is the component on `comp-segmented.html`, like every other row
// of side-by-side choices in the app.

extension Animation {
    /// View and Edit coming and going: everything that folds away does it on
    /// this one curve, so nothing lands before anything else.
    static let viewEditMode = Animation.smooth(duration: ViewEditMode.transitionSeconds)
}

/// The switch as it sits in the title bar: the control, plus a marker over
/// each half so a walk can press View Mode or Edit Mode by name.
struct TitlebarViewEditSwitch: View {
    @Environment(EditorState.self) private var editorState

    /// Wide enough for both words at the small size, in equal halves.
    static let width: CGFloat = 96
    /// Between the switch and the panel toggle.
    static let gap: CGFloat = 6

    var body: some View {
        let mode = editorState.viewEditMode
        SegmentedControl("View or Edit", selection: mode,
                         options: ViewEditMode.allCases.map { each in
                             .init(each, each.title, key: "⌘\(each.commandKey)")
                         },
                         size: .small, tipsBelow: true) { editorState.setViewEditMode($0) }
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
