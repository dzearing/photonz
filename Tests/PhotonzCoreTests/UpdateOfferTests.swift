import Testing
@testable import PhotonzCore

/// The website's `version.json` can name a release minutes before its DMG is
/// published (on 2026-10-25 the site said 0.19.0 for about 20 minutes while
/// releases/download/v0.19.0/Photonz.dmg answered 404, and Update & Restart
/// failed with "the server returned an unexpected response"). So a newer
/// version is offered only once its download answers.
@Suite("UpdateOffer")
struct UpdateOfferTests {

    private let current = SemanticVersion("0.20.0")!
    private let newer = SemanticVersion("0.21.0")!

    @Test func newerVersionWhoseDownloadAnswersIsOffered() async {
        let outcome = await UpdateOffer.decide(current: current, latest: newer) { _ in .answers }
        #expect(outcome == .updateAvailable(newer))
    }

    @Test func newerVersionWhoseDownloadIsMissingIsUpToDate() async {
        let outcome = await UpdateOffer.decide(current: current, latest: newer) { _ in .missing }
        #expect(outcome == .upToDate)
    }

    @Test func networkErrorReachingTheDownloadIsTheFailureMessage() async {
        let outcome = await UpdateOffer.decide(current: current, latest: newer) { _ in
            .unreachable("The Internet connection appears to be offline.")
        }
        #expect(outcome == .failed("The Internet connection appears to be offline."))
    }

    @Test func theDownloadAskedAboutIsTheNewerVersion() async {
        var asked: [SemanticVersion] = []
        _ = await UpdateOffer.decide(current: current, latest: newer) { version in
            asked.append(version)
            return .answers
        }
        #expect(asked == [newer])
    }

    @Test func noNewerVersionNeverAsksAboutADownload() async {
        var asked = 0
        let same = await UpdateOffer.decide(current: newer, latest: newer) { _ in
            asked += 1
            return .answers
        }
        let older = await UpdateOffer.decide(current: newer, latest: current) { _ in
            asked += 1
            return .answers
        }
        #expect(same == .upToDate)
        #expect(older == .upToDate)
        #expect(asked == 0)
    }

    @Test func onlyASuccessStatusMeansTheDownloadAnswers() {
        #expect(UpdateDownloadProbe(httpStatus: 200) == .answers)
        #expect(UpdateDownloadProbe(httpStatus: 204) == .answers)
        #expect(UpdateDownloadProbe(httpStatus: 404) == .missing)
        #expect(UpdateDownloadProbe(httpStatus: 403) == .missing)
        #expect(UpdateDownloadProbe(httpStatus: 302) == .missing)  // a redirect not followed is not a download
        #expect(UpdateDownloadProbe(httpStatus: 503) == .missing)
    }
}

/// What a person reads when the DMG download itself is refused.
@Suite("UpdateDownloadFailure")
struct UpdateDownloadFailureTests {

    @Test func aMissingDownloadSaysTheUpdateIsNotReadyYet() {
        #expect(UpdateDownloadFailure.message(httpStatus: 404)
                == "This update isn't ready to download yet. Try again in a few minutes.")
    }

    @Test func aServerErrorSaysTryAgainLater() {
        #expect(UpdateDownloadFailure.message(httpStatus: 503)
                == "The download server isn't answering right now. Try again in a few minutes.")
        #expect(UpdateDownloadFailure.message(httpStatus: 500)
                == UpdateDownloadFailure.message(httpStatus: 503))
    }

    @Test func noMessageEverSaysUnexpectedResponseOrUsesAnEmDash() {
        for status in [300, 302, 400, 401, 403, 404, 410, 429, 500, 502, 503, 504] {
            let message = UpdateDownloadFailure.message(httpStatus: status)
            #expect(!message.lowercased().contains("unexpected"))
            #expect(!message.contains("\u{2014}"))
            #expect(message.hasSuffix("."))
        }
    }
}
