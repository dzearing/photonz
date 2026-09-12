import Foundation
import PhotonzCore
import Testing

/// The information architecture on top of the catalogue: what Help ▸ Tutorials
/// holds, and what the Tutorials window shows.
///
/// The point of every test here is that NOTHING is written by hand. A guide
/// added to the catalogue turns up in its track's submenu and in the window on
/// its own, and the menu code never learns a guide's name. So the tests build
/// their own little catalogues and read the models back, exactly the way the
/// app does.
@Suite("Tutorial menu and hub")
struct TutorialMenuTests {

    // MARK: Little catalogues to read back

    private func guide(_ id: String, track: TutorialTrack, title: String,
                       minutes: Int = 2, steps: Int = 3) -> TutorialGuide {
        TutorialGuide(
            id: id, track: track, title: title,
            summary: "What \(title.lowercased()) is for.", minutes: minutes, sample: nil,
            steps: (0..<steps).map { index in
                TutorialStep(id: "step\(index)", anchor: .canvas,
                             title: "Step \(index + 1)", body: "Something to look at.")
            })
    }

    private var twoTracks: [TutorialGuide] {
        [guide("tour", track: .basics, title: "Take the Tour"),
         guide("first-layer", track: .basics, title: "Put a layer down"),
         guide("measure", track: .redlining, title: "Measure a screenshot")]
    }

    // MARK: The menu is tracks, never a flat list

    @Test func theMenuPromotesTheTourAndPutsEverythingElseUnderItsTrack() {
        let menu = TutorialMenuModel(guides: twoTracks, tourID: "tour")
        #expect(menu.tour?.guide.id == "tour")
        #expect(menu.tracks.map(\.track) == [.basics, .redlining])
        #expect(menu.tracks[0].rows.map(\.guide.id) == ["tour", "first-layer"])
        #expect(menu.tracks[1].rows.map(\.guide.id) == ["measure"])
    }

    @Test func thereIsNoFlatListOfEveryGuideAnywhereInTheMenu() {
        let menu = TutorialMenuModel(guides: twoTracks, tourID: "tour")
        // Every guide is reachable, and only ever through its own track.
        let byTrack = menu.tracks.flatMap { track in track.rows.map { ($0.guide.id, track.track) } }
        #expect(byTrack.count == 3)
        for (id, track) in byTrack {
            #expect(twoTracks.first { $0.id == id }?.track == track)
        }
    }

    @Test func aTrackWithNothingOnItShowsNoEmptySubmenu() {
        let menu = TutorialMenuModel(guides: [guide("a", track: .video, title: "Trim a clip")],
                                     tourID: "nothing")
        #expect(menu.tracks.map(\.track) == [.video])
        #expect(menu.tour == nil)
        for track in menu.tracks { #expect(!track.rows.isEmpty) }
    }

    @Test func oneTrackHoldingOneGuideStillReadsAsATrack() {
        // The state the app really ships in until the seven track tasks land.
        let menu = TutorialMenuModel(guides: TutorialCatalog.guides, tourID: TutorialCatalog.tourID)
        #expect(menu.tracks.count >= 1)
        #expect(menu.tracks.allSatisfy { !$0.rows.isEmpty })
        #expect(menu.tour != nil)
    }

    @Test func tracksAreAlwaysInLearningOrderNotCatalogueOrder() {
        let scrambled = [guide("v", track: .video, title: "Trim a clip"),
                         guide("b", track: .basics, title: "Take the Tour"),
                         guide("c", track: .components, title: "Make a component")]
        let menu = TutorialMenuModel(guides: scrambled, tourID: "b")
        #expect(menu.tracks.map(\.track) == [.basics, .components, .video])
    }

    // MARK: Adding a guide adds its rows, with no menu code touched

    @Test func addingAGuideToTheCatalogueAddsItsMenuRowAndItsWindowEntry() {
        let before = TutorialMenuModel(guides: twoTracks, tourID: "tour")
        let added = guide("looks", track: .looks, title: "Add a shadow")
        let after = TutorialMenuModel(guides: twoTracks + [added], tourID: "tour")

        // A new track appeared, in its place, holding exactly the new guide.
        #expect(before.tracks.map(\.track) == [.basics, .redlining])
        #expect(after.tracks.map(\.track) == [.basics, .redlining, .looks])
        #expect(after.tracks.last?.rows.map(\.guide.id) == ["looks"])

        // And the window picked it up from the same data.
        let hub = TutorialHubModel(guides: twoTracks + [added], progress: TutorialProgress())
        #expect(hub.tracks.map(\.track) == [.basics, .redlining, .looks])
        #expect(hub.tracks.last?.rows.first?.title == "Add a shadow")
        #expect(hub.tracks.last?.rows.first?.length == "2 min")
    }

    @Test func addingAGuideToAnExistingTrackLandsInThatSubmenuInCatalogueOrder() {
        let added = guide("spec", track: .redlining, title: "Hand off a spec")
        let menu = TutorialMenuModel(guides: twoTracks + [added], tourID: "tour")
        #expect(menu.tracks.last?.rows.map(\.guide.id) == ["measure", "spec"])
    }

    // MARK: A menu row says its name, and nothing that could go stale

    /// A command menu bakes its item titles in when it is built, so a row that
    /// carried where you got to still said "step 3 of 6" after the guide was
    /// finished. Measured with Scripts/playtest/tutorial-hub-walk.json on
    /// 2026-09-12, and the reason every word a menu row says is true whatever
    /// you have done before. Where you got to lives in the window.
    @Test func aRowSaysItsNameWhateverYouHaveDoneBefore() {
        let row = TutorialMenuModel(guides: twoTracks, tourID: "tour").tracks[1].rows[0]
        #expect(row.title == "Measure a screenshot")
        #expect(row.help.contains("2 minutes"))
        #expect(!row.help.contains("step"))
    }

    @Test func aRowsWordsDoNotDependOnAnyStoredProgress() {
        // The model is not even handed progress: there is nothing to go stale.
        let fresh = TutorialMenuModel(guides: twoTracks, tourID: "tour")
        let again = TutorialMenuModel(guides: twoTracks, tourID: "tour")
        #expect(fresh == again)
    }

    @Test func theTourRowAtTheTopAndTheOneInItsTrackAreTheSameGuide() {
        let menu = TutorialMenuModel(guides: twoTracks, tourID: "tour")
        #expect(menu.tour?.guide == menu.tracks[0].rows[0].guide)
    }

    @Test func everyWordTheMenuGeneratesObeysTheCopyRules() {
        let menu = TutorialMenuModel(guides: twoTracks, tourID: "tour")
        var words = [TutorialMenuModel.menuTitle, TutorialMenuModel.hubRowTitle]
        words += menu.tracks.flatMap { $0.rows.flatMap { [$0.title, $0.help] } }
        words += [menu.tour?.title, menu.tour?.help].compactMap { $0 }
        for word in words {
            #expect(TutorialCopyRules.problems(in: word, label: word) == [])
        }
    }

    // MARK: The window

    @Test func theWindowShowsEveryTrackWithItsGuidesAndHowLongEachTakes() {
        let hub = TutorialHubModel(guides: twoTracks, progress: TutorialProgress())
        #expect(hub.tracks.map(\.title) == ["Basics", "Redlining"])
        #expect(hub.tracks[0].blurb == TutorialTrack.basics.blurb)
        #expect(hub.tracks[0].rows.map(\.title) == ["Take the Tour", "Put a layer down"])
        #expect(hub.tracks[0].rows.allSatisfy { $0.length == "2 min" })
        #expect(hub.tracks[0].rows.allSatisfy { !$0.summary.isEmpty })
    }

    @Test func aGuideThatTakesOneMinuteDoesNotSayMinutes() {
        let hub = TutorialHubModel(guides: [guide("a", track: .basics, title: "Quick one", minutes: 1)],
                                   progress: TutorialProgress())
        #expect(hub.tracks[0].rows[0].length == "1 min")
    }

    @Test func aTrackSaysHowFarThroughItYouAre() {
        var progress = TutorialProgress()
        progress.complete("tour")
        let hub = TutorialHubModel(guides: twoTracks, progress: progress)
        #expect(hub.tracks[0].finished == 1)
        #expect(hub.tracks[0].total == 2)
        #expect(hub.tracks[0].progressLine == "1 of 2 finished")
        #expect(hub.tracks[1].progressLine == "None finished yet")
    }

    @Test func aTrackYouHaveFinishedSaysSoRatherThanCountingItself() {
        var progress = TutorialProgress()
        progress.complete("measure")
        let hub = TutorialHubModel(guides: twoTracks, progress: progress)
        #expect(hub.tracks[1].progressLine == "All finished")
        #expect(hub.tracks[1].fraction == 1)
    }

    @Test func aFinishedGuideIsMarkedFinishedAndOffersToRunItAgain() {
        var progress = TutorialProgress()
        progress.complete("measure")
        let hub = TutorialHubModel(guides: twoTracks, progress: progress)
        let row = hub.tracks[1].rows[0]
        #expect(row.state == .finished)
        #expect(row.actionTitle == "Again")
        #expect(row.statusLine == "Finished")
        #expect(row.hasProgress)
    }

    @Test func aGuideLeftPartWaySaysWhereYouStoppedAndOffersToCarryOn() {
        var progress = TutorialProgress()
        progress.record(guide: "measure", step: 1)
        let hub = TutorialHubModel(guides: twoTracks, progress: progress)
        let row = hub.tracks[1].rows[0]
        #expect(row.state == .inProgress(step: 2, of: 3))
        #expect(row.actionTitle == "Continue")
        #expect(row.statusLine == "Stopped at step 2 of 3")
        #expect(row.hasProgress)
    }

    @Test func aGuideNobodyHasStartedOffersToStartAndHasNothingToForget() {
        let hub = TutorialHubModel(guides: twoTracks, progress: TutorialProgress())
        let row = hub.tracks[1].rows[0]
        #expect(row.state == .notStarted)
        #expect(row.actionTitle == "Start")
        #expect(row.statusLine == nil)
        #expect(!row.hasProgress)
    }

    @Test func theWindowOnlyOffersToResetEverythingWhenThereIsSomethingToReset() {
        #expect(!TutorialHubModel(guides: twoTracks, progress: TutorialProgress()).anyProgress)
        var progress = TutorialProgress()
        progress.record(guide: "measure", step: 1)
        #expect(TutorialHubModel(guides: twoTracks, progress: progress).anyProgress)
    }

    @Test func everyWordTheWindowGeneratesObeysTheCopyRules() {
        var progress = TutorialProgress()
        progress.complete("tour")
        progress.record(guide: "measure", step: 1)
        let hub = TutorialHubModel(guides: twoTracks, progress: progress)
        var words = [TutorialHubModel.windowTitle, TutorialHubModel.blurb, TutorialHubModel.emptyLine]
        for track in hub.tracks {
            words += [track.title, track.blurb, track.progressLine]
            words += track.rows.flatMap { [$0.title, $0.summary, $0.length, $0.actionTitle] }
            words += track.rows.compactMap(\.statusLine)
        }
        for word in words {
            #expect(TutorialCopyRules.problems(in: word, label: word) == [])
        }
    }

    @Test func aCatalogueWithNothingInItSaysSoRatherThanShowingAnEmptyWindow() {
        let hub = TutorialHubModel(guides: [], progress: TutorialProgress())
        #expect(hub.isEmpty)
        #expect(hub.tracks.isEmpty)
        let menu = TutorialMenuModel(guides: [], tourID: "tour")
        #expect(menu.isEmpty)
        #expect(menu.tour == nil)
    }

    // MARK: Forgetting

    @Test func forgettingOneGuideClearsItsTickAndItsPlaceAndLeavesTheRestAlone() {
        var progress = TutorialProgress()
        progress.complete("tour")
        progress.record(guide: "measure", step: 1)
        progress.forget("tour")
        #expect(!progress.isCompleted("tour"))
        #expect(progress.startIndex(for: twoTracks[0]) == 0)
        #expect(progress.isResumable(twoTracks[2]))
    }

    @Test func forgettingEverythingLeavesNothingBehind() {
        var progress = TutorialProgress()
        progress.complete("tour")
        progress.record(guide: "measure", step: 1)
        #expect(!progress.isEmpty)
        progress.forgetAll()
        #expect(progress.isEmpty)
        #expect(!progress.isCompleted("tour"))
        #expect(!progress.isResumable(twoTracks[2]))
    }

    @Test func aGuideYouAlreadyFinishedStartsAtTheTopWhenYouRunItAgain() {
        var progress = TutorialProgress()
        progress.complete("measure")
        // Finishing clears the place, so running it again begins at step one
        // rather than dropping you on the last step it remembers.
        #expect(progress.startIndex(for: twoTracks[2]) == 0)
        #expect(!progress.isResumable(twoTracks[2]))
        // And it is still marked finished while it runs again.
        #expect(progress.isCompleted("measure"))
    }
}
