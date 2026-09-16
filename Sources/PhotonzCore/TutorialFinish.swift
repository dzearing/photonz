import Foundation

// The other end of a guide.
//
// A guide used to simply stop. The card vanished on Done and you were left
// sitting in the little made-up picture the guide had opened to teach in, with
// nothing saying what had just happened, whether the picture was yours, or
// where your own work goes. Somebody who has just been shown round should come
// out of it ready to start, not parked in a sample they never asked for.
//
// So the guide ends on a card rather than on nothing, and this is that card
// written as data: the words, and the two things worth offering. It is a value
// because every rule about it — which guide comes next, when a window is
// practice and when it is somebody's own work — is a rule that can be wrong,
// and a rule that can be wrong belongs somewhere it can be tested.

/// One thing the finish card offers.
public enum TutorialFinishChoice: Hashable, Sendable {
    /// The guide after this one on the same track.
    case nextGuide(id: String, title: String)
    /// Leave the practice picture behind and open an empty window, which is
    /// the one place in the app where getting a picture IN is a row you can
    /// press rather than a key you have to know.
    case startYourOwn
    /// The Tutorials window, offered once a track has nothing left on it.
    case moreGuides

    /// The words on the row.
    public var label: String {
        switch self {
        case .nextGuide(_, let title): "Next: \(title)"
        case .startYourOwn: "Start your own picture"
        case .moreGuides: "See the other guides"
        }
    }

    /// The symbol on the row, in the same family the empty window's own card
    /// uses for the ways in.
    public var symbol: String {
        switch self {
        case .nextGuide: "arrow.right.circle"
        case .startYourOwn: "photo.badge.plus"
        case .moreGuides: "book"
        }
    }

    /// A stable name that survives rewording, so a walk can press one of these
    /// by what it DOES rather than by what it currently says.
    public var name: String {
        switch self {
        case .nextGuide: "next"
        case .startYourOwn: "startYourOwn"
        case .moreGuides: "moreGuides"
        }
    }
}

/// What the app puts up the moment a guide finishes.
public struct TutorialFinish: Hashable, Sendable {
    /// The guide that just finished.
    public let guideID: String
    public let title: String
    public let message: String
    /// In the order they are offered, first one first. Never empty: there is
    /// always something to press, because a card that only closes is the
    /// nothing this replaced.
    public let choices: [TutorialFinishChoice]

    public init(guideID: String, title: String, message: String,
                choices: [TutorialFinishChoice]) {
        self.guideID = guideID
        self.title = title
        self.message = message
        self.choices = choices
    }

    /// Works out the card for a guide that has just finished.
    ///
    /// `offered` is the guides this app is really offering, which is the
    /// catalogue less anything teaching a switched-off feature: pointing
    /// somebody at a guide that is not in their menu would be worse than
    /// pointing them at nothing.
    ///
    /// `inSampleWindow` is whether the window the guide taught in is one the
    /// guide opened for itself. Only then is there anywhere to move somebody
    /// on FROM, and only then is it honest to call what is on screen practice.
    public static func make(after guide: TutorialGuide,
                            offered: [TutorialGuide],
                            inSampleWindow: Bool) -> TutorialFinish {
        let next = nextOnTrack(after: guide, offered: offered)
        var choices: [TutorialFinishChoice] = []
        if let next {
            // While the track has more on it, carrying on with it is the
            // thing somebody who chose to be taught most likely wants.
            choices.append(.nextGuide(id: next.id, title: next.title))
            if inSampleWindow { choices.append(.startYourOwn) }
        } else {
            // The track is finished. Going and doing the real thing is the
            // point of having been taught, so it leads.
            if inSampleWindow { choices.append(.startYourOwn) }
            choices.append(.moreGuides)
        }
        return TutorialFinish(guideID: guide.id,
                              title: "Finished: \(guide.title)",
                              message: message(hasNext: next != nil,
                                               inSampleWindow: inSampleWindow),
                              choices: choices)
    }

    /// The guide after this one on the same track, among the ones on offer.
    private static func nextOnTrack(after guide: TutorialGuide,
                                    offered: [TutorialGuide]) -> TutorialGuide? {
        let track = offered.filter { $0.track == guide.track }
        guard let here = track.firstIndex(where: { $0.id == guide.id }),
              track.indices.contains(here + 1) else { return nil }
        return track[here + 1]
    }

    private static func message(hasNext: Bool, inSampleWindow: Bool) -> String {
        switch (inSampleWindow, hasNext) {
        case (true, true):
            "This window holds a practice picture, not your work. Carry on with the track, "
                + "or start something of your own."
        case (true, false):
            "That is the whole track. This window holds a practice picture, not your work, "
                + "so start something of your own whenever you are ready."
        case (false, true):
            "Your picture is exactly as you left it. There is another guide on this track "
                + "when you want it."
        case (false, false):
            "That is the whole track, and your picture is exactly as you left it."
        }
    }
}
