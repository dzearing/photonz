import Foundation
import PhotonzCore
import Testing

/// What a walk's output folder should hold when the walk is over: the pictures
/// this run took, its log, its done.json, and nothing from any run before it.
///
/// Until 2026-09-19 a run only deleted `done.json` before it started, so a walk
/// that stopped at step 17 sat in a folder holding step 20's photograph from a
/// healthier run days earlier, with nothing to say which was which. An audit
/// ships a picture by file name out of that folder, so the picture it shipped
/// could be of an app that no longer worked.
///
/// This is the part of the fix that can be decided without touching a disk:
/// given what is in the folder, what does this run delete before it writes.
@Suite("What a walk clears out of its folder before it runs")
struct PlaytestOutputFolderTests {

    private func scratch(_ walk: String) -> URL {
        URL(fileURLWithPath: PlaytestScript.scratchRoot).appendingPathComponent(walk)
    }

    @Test("A walk's own scratch folder is cleared whole")
    func scratchFolderGoesEntirely() {
        let left = PlaytestOutputFolder.leftovers(
            in: scratch("unique-layer-names"),
            named: ["log.json", "done.json",
                    "names-1-four-shapes.png", "names-1-four-shapes-sc.png",
                    "names-2-after-rename.png", "names-2-after-rename-sc.png",
                    "panel-before.json", "menu-shot.txt", "icon.svg"])
        #expect(Set(left) == Set(["log.json", "done.json",
                                  "names-1-four-shapes.png", "names-1-four-shapes-sc.png",
                                  "names-2-after-rename.png", "names-2-after-rename-sc.png",
                                  "panel-before.json", "menu-shot.txt", "icon.svg"]))
    }

    @Test("A folder a run owns is its own, subfolders and all")
    func subfoldersGoToo() {
        let left = PlaytestOutputFolder.leftovers(in: scratch("redline"), named: ["frames", "a-sc.png"])
        #expect(Set(left) == Set(["frames", "a-sc.png"]))
    }

    @Test("An empty folder leaves nothing to clear")
    func emptyFolderClearsNothing() {
        #expect(PlaytestOutputFolder.leftovers(in: scratch("redline"), named: []).isEmpty)
    }

    @Test("Hidden files are left where they are")
    func hiddenFilesStay() {
        let left = PlaytestOutputFolder.leftovers(in: scratch("redline"),
                                                  named: [".DS_Store", "a-sc.png"])
        #expect(left == ["a-sc.png"])
    }

    @Test("The scratch root itself is never cleared: other walks live in it")
    func scratchRootIsNotOneWalksFolder() {
        let root = URL(fileURLWithPath: PlaytestScript.scratchRoot)
        #expect(PlaytestOutputFolder.isRunsOwn(root) == false)
        // Its children are sibling walks, so nothing but this run's own two
        // files may go.
        let left = PlaytestOutputFolder.leftovers(in: root, named: ["redline", "unique-layer-names", "log.json"])
        #expect(left == ["log.json"])
    }

    @Test("A folder somewhere else keeps everything but this run's own log and verdict")
    func aSharedFolderIsNotWipedOut() {
        // A walk may point `out` at a folder it does not own — beside the walk
        // scripts, say, where wiping would take the other 500 walks with it. So
        // nothing is guessed at there: only the files a run writes under a name
        // it always uses are removed, and the run says the rest may be old.
        let beside = URL(fileURLWithPath: "/Users/someone/git/photonz/Scripts/playtest")
        #expect(PlaytestOutputFolder.isRunsOwn(beside) == false)
        let left = PlaytestOutputFolder.leftovers(
            in: beside,
            named: ["redline-walk.json", "log.json", "done.json", "menu-shot.txt", "a-sc.png"])
        #expect(Set(left) == Set(["log.json", "done.json", "menu-shot.txt"]))
    }

    @Test("Everything a run leaves behind is cleared by the next run")
    func twoRunsInARowLeaveTheSameFiles() {
        // The files a completed walk leaves, from `Scripts/playtest.sh`'s own
        // listing of one.
        let afterARun = ["log.json", "done.json", "names-1-four-shapes.png",
                         "names-1-four-shapes-sc.png", "names-2-after-rename.png",
                         "names-2-after-rename-sc.png"]
        let left = PlaytestOutputFolder.leftovers(in: scratch("unique-layer-names"), named: afterARun)
        #expect(Set(left) == Set(afterARun),
                "a second run starts from an empty folder, so it ends holding exactly what it took")
    }

    @Test("A path with a step up in it is read for where it really lands")
    func pathsAreStandardized() {
        let sneaky = URL(fileURLWithPath: PlaytestScript.scratchRoot + "/redline/../../etc")
        #expect(PlaytestOutputFolder.isRunsOwn(sneaky) == false)
        let honest = URL(fileURLWithPath: PlaytestScript.scratchRoot + "/redline/./shots")
        #expect(PlaytestOutputFolder.isRunsOwn(honest))
    }

    @Test("What the run says it did is plain and counts the files")
    func theRunSaysWhatItCleared() {
        let said = PlaytestOutputFolder.clearedSaid(count: 6, in: scratch("unique-layer-names"))
        #expect(said == "cleared 6 files an earlier run left, so every picture here is this run's")
        #expect(PlaytestOutputFolder.clearedSaid(count: 1, in: scratch("redline"))
                == "cleared 1 file an earlier run left, so every picture here is this run's")
        #expect(PlaytestOutputFolder.clearedSaid(count: 0, in: scratch("redline")) == nil)
    }

    @Test("A folder the run does not own says its pictures may be old")
    func aSharedFolderSaysSo() {
        let beside = URL(fileURLWithPath: "/Users/someone/pictures")
        let said = PlaytestOutputFolder.clearedSaid(count: 2, in: beside)
        #expect(said?.contains("may be from an earlier run") == true)
    }
}
