import Foundation

/// What one walk managed to photograph of the real window, and therefore
/// whether anything it leaves behind may be shown to a person as the app.
///
/// A `snapshot` step writes two pictures. The offscreen drawing, `<name>.png`,
/// is the harness asking the views to draw themselves into a bitmap; it is
/// always available, and it resolves some colours wrong (a plain tool button
/// came out black on the dark bar). The screen capture, `<name>-sc.png`, is the
/// window as the screen actually shows it, shadow, toast, menu bar and all, and
/// it is the only one an audit may ship.
///
/// The capture used to be able to fail in silence. It noted the refusal in the
/// log and the walk carried on green, so a run that photographed nothing looked
/// exactly like a run that photographed everything, and the audit written from
/// it shipped drawings of the window in place of the window. That happened on
/// two consecutive mornings in September 2026.
///
/// So every attempt is recorded here, and the run answers for them at the end:
/// a picture that could have been taken and was not is a FAILURE, while a
/// picture that was never possible is only a fact worth saying out loud. One
/// thing makes it impossible and it is not the app's doing: this copy of the
/// app holds no Screen Recording grant, which only a person can give it.
///
/// A locked screen used to be the other one, and it was wrong. The belief was
/// that macOS refuses every capture while the login window is up, so a locked
/// run's refusals were excused and a locked run that photographed nothing was
/// explained by the lock. Forced past the walk-level refusal on 2026-09-16, a
/// two-snapshot walk on a locked Mac wrote before-sc.png and after-sc.png:
/// different pictures, the second showing the rectangle the walk had just
/// dragged out. The lock stops control NAMES arriving, which is why walks under
/// it are worthless, but it does not stop the camera. What made a locked run
/// look camera-less was the walk dying at a name lookup before it ever reached
/// a snapshot step.
public struct PlaytestCaptureLedger: Sendable, Equatable {

    /// The `<name>-sc.png` files actually written, in the order they were taken.
    public private(set) var written: [String] = []
    /// The steps that asked for a picture and did not get one, by step name.
    public private(set) var refusals: [String] = []
    /// How many steps were skipped for want of a Screen Recording grant.
    public private(set) var ungranted: Int = 0

    public init() {}

    /// Records a picture taken. `name` is the step's name, without the suffix.
    public mutating func photographed(_ name: String) {
        written.append("\(name)-sc.png")
    }

    /// Records a picture asked for and refused.
    public mutating func refused(_ name: String) {
        refusals.append(name)
    }

    /// Records a picture skipped because there is no grant to take it with.
    public mutating func skippedUngranted() {
        ungranted += 1
    }

    /// Why this run failed to photograph the app, or nil when it did not fail.
    ///
    /// Only a refusal that had no excuse counts, and the grant is now the only
    /// excuse there is: hold it and the picture was there to be taken, locked
    /// screen or not.
    public func failure(granted: Bool) -> String? {
        guard !refusals.isEmpty, granted else { return nil }
        let many = refusals.count != 1
        return "\(refusals.count) window capture\(many ? "s" : "") this walk asked for never happened "
            + "(\(refusals.joined(separator: ", "))), so only the offscreen drawings were written. "
            + "This app holds Screen Recording, so a picture was there to be taken: an audit built from "
            + "this run would show a drawing of the window instead of the window. "
            + "Each refusal gives its reason in log.json under \"capture\"."
    }

    /// One line for whoever reads the run: what there is to look at, or why
    /// there is nothing.
    public func report(granted: Bool) -> String {
        if !written.isEmpty {
            let many = written.count != 1
            var line = "\(written.count) real picture\(many ? "s" : "") of the window: "
                + written.joined(separator: ", ")
            if !refusals.isEmpty {
                line += "; \(refusals.count) more \(refusals.count == 1 ? "was" : "were") refused: "
                    + refusals.joined(separator: ", ")
            }
            return line
        }
        if !granted || ungranted > 0 {
            return "none. This app holds no Screen Recording grant, so it may not photograph its own window."
        }
        if !refusals.isEmpty {
            return "none. \(refusals.count) \(refusals.count == 1 ? "was" : "were") refused: "
                + refusals.joined(separator: ", ")
        }
        return "none. This walk never asked for one."
    }
}
