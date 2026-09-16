import Foundation

// Where a step's control really is when the bar is not showing it.
//
// A guide names the control it is TEACHING: "pick the Ellipse" points at
// `tool.ellipse`. The tool bar does not always have that button on it.
//
//  * Three shapes share ONE slot, and the slot wears whichever member you
//    reached for last. On a machine nobody has drawn on that is the Line, so
//    the Ellipse's button is not on the bar at all: it is one press and hold
//    away, inside the slot.
//  * On a narrow window the last slots slide into a More menu, so even a tool
//    that stands alone can be off the bar.
//
// Before this, a step naming either of those pointed at nothing, and the card
// fell to the middle of the window with no ring: honest, and useless as a
// lesson. A guide that wanted to teach the Ellipse therefore had to name the
// SLOT instead, which rings a button wearing the wrong glyph and says nothing
// about why.
//
// So a step keeps naming the tool, and when that tool is not on the bar the
// ring lands on the thing it is INSIDE and the card adds one line saying so.
// The line always asks the person to open it. Nothing here opens anything: a
// step that says "pick the Ellipse" and then opens the list itself has done the
// lesson for them, which is the same lie as a step that advances on a timer.

/// Why a step's control is not on the bar in its own right.
public enum TutorialConcealment: Hashable, Sendable, Codable {
    /// It is a member of a family slot that is wearing a different member.
    case behindFamilySlot(ToolGroup)
    /// It has slid into the bar's More menu, which a narrow window does to the
    /// last slots.
    case inMoreMenu

    /// The one line the card adds, with `subject` the name of the thing the
    /// step is really about ("Ellipse", "Shapes button").
    ///
    /// Product copy, so it lives beside the rule rather than in the view: it is
    /// the same sentence wherever it is shown, and it is checked by a test.
    public func sentence(for subject: String) -> String {
        switch self {
        case .behindFamilySlot(let group):
            "The \(subject) is inside the \(group.title) button. Press and hold the button to reach it."
        case .inMoreMenu:
            "The \(subject) is in the More menu at the end of the tool bar. Open the menu to reach it."
        }
    }
}

/// One place a step's control might be found, and what that place means.
public struct TutorialStandIn: Hashable, Sendable {
    /// The name to look for on screen.
    public let anchor: TutorialAnchor
    /// Nil when this IS the control the step named. Otherwise what is hiding
    /// it, which is what the card's extra line is written from.
    public let concealment: TutorialConcealment?

    public init(anchor: TutorialAnchor, concealment: TutorialConcealment? = nil) {
        self.anchor = anchor
        self.concealment = concealment
    }
}

/// The order the app looks for a step's control in.
public enum TutorialAnchorStandIns {
    /// Everywhere `wanted` could be, nearest first: the control itself, then
    /// the family slot holding it, then the More menu at the end of the bar.
    ///
    /// The app walks this and takes the first one that is really on screen, so
    /// a tool on the bar is rung directly and the stand-ins only ever come up
    /// when the tool is not there. Anything that is not a tool has nowhere else
    /// to be and gets a list of one: a panel section does not hide inside a
    /// tool bar slot, and offering it a stand-in would be inventing a place.
    public static func chain(for wanted: TutorialAnchor) -> [TutorialStandIn] {
        var chain = [TutorialStandIn(anchor: wanted)]
        if let tool = wanted.tool {
            if let group = ToolGroup.containing(tool) {
                chain.append(TutorialStandIn(anchor: .toolGroup(group),
                                             concealment: .behindFamilySlot(group)))
            }
            chain.append(TutorialStandIn(anchor: .moreTools, concealment: .inMoreMenu))
        } else if wanted.toolGroup != nil {
            chain.append(TutorialStandIn(anchor: .moreTools, concealment: .inMoreMenu))
        }
        return chain
    }
}
