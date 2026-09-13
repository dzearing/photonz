import CoreGraphics
import Foundation

/// How much one Separate into Layers may take out of one picture.
///
/// The feature is worth running on a WHOLE screen, and a whole screen is not a
/// settings pane. Measured on real captures: the settings pane fixture offers
/// eleven pieces, a full screen capture of this app ninety three, and a dense
/// web page three hundred and ninety. The first two are a layers list you can
/// work in. The third is a wall of identical names you scroll rather than read,
/// and a command that hands you one has not helped you.
///
/// So there is a ceiling, and it is deliberately a ceiling rather than a
/// refusal: a picture past it still comes apart, it just comes apart into the
/// pieces worth having.
///
/// - **The biggest come out.** On a dense page the small pieces are the
///   hundredth body-text run — the one nobody was ever going to reach for. The
///   big ones are the headings, the cards and the buttons, which is what a
///   person points at.
/// - **Nothing is lost.** What is left over is left IN the picture, untouched,
///   and counted in the pill. Running the command again takes the next
///   hundred, because the pieces that came out are no longer in the picture to
///   be found.
///
/// Full design: `docs/design/separate-into-layers.md`.
public enum SeparateBudget {

    /// The most runs of text one command takes.
    ///
    /// Set from measurement rather than taste. A 2x capture of this app's
    /// whole window — menu bar, toolbar, two panels, a layers list — offers
    /// 119 runs of text, and taking a whole screen apart in ONE command is the
    /// entire point of the feature, so the limit has to sit above that. A
    /// dense web page offers 400, which is not a layers list at all. Between
    /// those two numbers is where the wall goes.
    public static let maxTextRuns = 150

    /// And the most boxes. Far fewer, because a box is a container: thirty of
    /// them is thirty groups to open, and no real capture of one window offers
    /// anywhere near that many things sitting on its own background.
    public static let maxBoxes = 30

    /// The most levels the layers list may be asked to indent.
    ///
    /// Four is past anything a detector can find today (a box holding its own
    /// words is two), and it is the point at which a row's name starts further
    /// in than the twist that opens it. A piece deeper than this is not thrown
    /// away: it joins the deepest group that holds it, so it still travels
    /// with the thing a person would drag.
    public static let maxDepth = 4

    /// Which pieces a limit lets through.
    public struct Choice: Equatable, Sendable {
        /// Indices into the list handed over, in the ORDER IT CAME IN — which
        /// is reading order, so the names still run down the page rather than
        /// down a size chart.
        public let kept: [Int]
        /// How many were left in the picture because the limit was reached.
        /// Not "unreadable": these are pieces the app read perfectly well and
        /// chose not to take, which is a different sentence and deserves one.
        public let crowdedOut: Int

        public init(kept: [Int], crowdedOut: Int) {
            self.kept = kept
            self.crowdedOut = crowdedOut
        }
    }

    /// The `limit` biggest of `rects`, back in reading order, and how many that
    /// left behind. Ties go to whichever came first, so the answer is the same
    /// every run.
    public static func choose(_ rects: [CGRect], limit: Int) -> Choice {
        guard rects.count > limit else {
            return Choice(kept: Array(rects.indices), crowdedOut: 0)
        }
        guard limit > 0 else { return Choice(kept: [], crowdedOut: rects.count) }
        let areas = rects.map { abs($0.width * $0.height) }
        let kept = rects.indices
            .sorted { areas[$0] == areas[$1] ? $0 < $1 : areas[$0] > areas[$1] }
            .prefix(limit)
            .sorted()
        return Choice(kept: Array(kept), crowdedOut: rects.count - limit)
    }
}
