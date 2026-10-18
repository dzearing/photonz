import Testing
import PhotonzCore

/// What a right click on each kind of thing on the timeline offers, one table
/// (`TimelineMenuTable`, written out in `docs/design/timeline-right-click.md`).
///
/// The user, 2026-10-17: "I right click on a clip, and i get this enormous
/// right click menu which makes nearly no sense to me. It is as if we didn't
/// consider what these things meant in a particular context." A video clip's
/// menu had 21 rows in five groups; a gap's had the whole track header's.
@Suite("A timeline right-click menu is short and about what was clicked")
struct TimelineMenuTableTests {

    typealias Row = TimelineMenuRow

    /// Every kind's top level fits the budget: about ten rows in at most four
    /// groups, More counted as a row.
    @Test(arguments: TimelineMenuThing.allCases)
    func everyKindFitsTheBudget(_ thing: TimelineMenuThing) {
        let groups = TimelineMenuTable.groups(for: thing)
        #expect(groups.count <= TimelineMenuTable.mostGroups, "\(thing) has \(groups.count) groups")
        let rows = groups.flatMap { $0 }
        #expect(rows.count <= TimelineMenuTable.mostTopLevelRows, "\(thing) has \(rows.count) rows")
        #expect(!groups.contains { $0.isEmpty }, "\(thing) has an empty group")
    }

    /// A row is in one place: on top, or one level down, never both.
    @Test(arguments: TimelineMenuThing.allCases)
    func noRowIsOfferedTwice(_ thing: TimelineMenuThing) {
        let all = TimelineMenuTable.groups(for: thing).flatMap { $0 }
            + TimelineMenuTable.moreGroups(for: thing).flatMap { $0 }
        #expect(Set(all).count == all.count, "\(thing) offers a row twice")
    }

    /// A kind with rows one level down says so with exactly one More, last
    /// group, on its own; a kind without them has no More.
    @Test(arguments: TimelineMenuThing.allCases)
    func moreIsTheLastGroupAndOnlyWhenThereIsSomethingInIt(_ thing: TimelineMenuThing) {
        let groups = TimelineMenuTable.groups(for: thing)
        let more = TimelineMenuTable.moreGroups(for: thing)
        let holder = TimelineMenuTable.moreRow(for: thing)
        if more.isEmpty {
            #expect(!groups.flatMap { $0 }.contains(.more) && !groups.flatMap { $0 }.contains(.track))
        } else {
            #expect(groups.last == [holder])
            #expect(groups.dropLast().allSatisfy { !$0.contains(holder) })
        }
    }

    /// The video clip, as the user asked: what you do at the playhead first,
    /// then what the clip does, then the clipboard and the deletes.
    @Test func aVideoClipLeadsWithThePlayheadAndEndsWithMore() {
        #expect(TimelineMenuTable.groups(for: .videoClip) == [
            [.split, .freezeFrame, .speed],
            [.addTransition, .detachAudio, .audio],
            [.cut, .copy, .delete, .rippleDelete],
            [.more],
        ])
    }

    /// The video clip's long tail is one level down, grouped, and every row the
    /// old menu had is still there.
    @Test func everyRowTheOldVideoMenuHadIsStillOffered() {
        let offered = Set(TimelineMenuTable.groups(for: .videoClip).flatMap { $0 }
            + TimelineMenuTable.moreGroups(for: .videoClip).flatMap { $0 })
        let before: [Row] = [.split, .rippleTrimStart, .rippleTrimEnd, .freezeFrame, .punchIn, .addClick,
                             .addZoom, .suggestZooms, .speed, .fadeIn, .fadeOut, .addTransition, .animate,
                             .addKey, .detachAudio, .audio, .selectForward, .rename, .duplicate,
                             .revealInFinder, .delete, .rippleDelete, .showPicture, .breakApart, .pasteKeys]
        #expect(before.allSatisfy(offered.contains), "missing: \(before.filter { !offered.contains($0) })")
    }

    /// A sound, linked under its video or on its own: the sound's verbs, never
    /// a picture's.
    @Test(arguments: [TimelineMenuThing.linkedSound, .soundClip])
    func aSoundOffersNoPictureRows(_ thing: TimelineMenuThing) {
        let all = Set(TimelineMenuTable.groups(for: thing).flatMap { $0 }
            + TimelineMenuTable.moreGroups(for: thing).flatMap { $0 })
        let picture: Set<Row> = [.freezeFrame, .punchIn, .addZoom, .suggestZooms, .addClick, .addTransition,
                                 .fadeIn, .fadeOut, .animate, .addKey, .animateIn, .animateOut]
        #expect(all.isDisjoint(with: picture))
        #expect(TimelineMenuTable.groups(for: thing)[1].first == .detachAudio)
    }

    /// A title and a picture are placed in time: when they start and end at
    /// the playhead, and how they come in and go out.
    @Test(arguments: [TimelineMenuThing.title, .picture])
    func somethingPlacedInTimeLeadsWithItsStartAndEnd(_ thing: TimelineMenuThing) {
        let groups = TimelineMenuTable.groups(for: thing)
        #expect(groups[0] == [.split, .startAtPlayhead, .endAtPlayhead])
        #expect(groups[1].contains(.animateIn) && groups[1].contains(.animateOut))
    }

    /// The things that are not clips have short menus of their own.
    @Test func theSmallThingsHaveShortMenus() {
        #expect(TimelineMenuTable.groups(for: .zoom) == [[.followCursor, .zoomAmount], [.deleteZoom]])
        #expect(TimelineMenuTable.groups(for: .gap).first == [.closeGap])
        #expect(TimelineMenuTable.groups(for: .caption).first == [.editWords, .joinWithNextLine, .startHere])
        #expect(TimelineMenuTable.groups(for: .join).first?.first == .applyDefaultTransition)
    }

    /// A cut opens into its two clips from its own right-click, beside its
    /// transition, the way the mock's Edit point group puts Expand the cut
    /// under Add transition (`video-transition-wt.html`, `#cmdMenu`).
    @Test func aCutOpensIntoItsTwoClipsFromItsRightClick() {
        let first = TimelineMenuTable.groups(for: .join).first ?? []
        let add = first.firstIndex(of: .addTransition)
        let expand = first.firstIndex(of: .expandCut)
        #expect(add != nil && expand != nil)
        #expect((add ?? 0) < (expand ?? 0))
        #expect(TimelineMenuTable.title(.expandCut, playheadMS: 0) == "Expand the Cut")
    }

    /// Empty space on a track is somewhere to put things; the track's own
    /// settings are one level down, under the track's name, as on its header.
    @Test func emptySpaceOffersWhatToPutThereAndTheTrackOneLevelDown() {
        let groups = TimelineMenuTable.groups(for: .emptySpace)
        #expect(groups.first?.contains(.addTitlePage) == true)
        #expect(groups.last == [.track])
        #expect(TimelineMenuTable.moreRow(for: .emptySpace) == .track)
        #expect(TimelineMenuTable.moreRow(for: .gap) == .track)
        #expect(TimelineMenuTable.moreRow(for: .videoClip) == .more)
    }

    /// Rows that act at the playhead say where it is.
    @Test func playheadRowsSayTheTime() {
        #expect(TimelineMenuTable.title(.split, playheadMS: 2000) == "Split at 0:02.00")
        #expect(TimelineMenuTable.title(.freezeFrame, playheadMS: 61_500) == "Freeze Frame at 1:01.50\u{2026}")
        #expect(TimelineMenuTable.title(.startAtPlayhead, playheadMS: 250) == "Start at 0:00.25")
        #expect(TimelineMenuTable.title(.endAtPlayhead, playheadMS: 4000) == "End at 0:04.00")
        #expect(TimelineMenuTable.title(.rollEdit, playheadMS: 3000) == "Roll Edit to 0:03.00")
        #expect(TimelineMenuTable.title(.cut, playheadMS: 3000) == "Cut")
        #expect(TimelineMenuTable.title(.more, playheadMS: 0) == "More")
    }
}
