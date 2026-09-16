import Foundation
import PhotonzCore
import Testing

/// A renamed control has to break the build rather than somebody's tour.
///
/// Two rules do it. Every guide in the catalogue is driven by a walk that goes
/// all the way through it, which is checked here against the real walks in
/// `Scripts/playtest`; and every step of a guide that a walk drives has to find
/// its control on screen, which the walk itself reports back and these rules
/// judge.
@Suite("A renamed control breaks the build")
struct TutorialAnchorAuditTests {

    // MARK: - Every guide is really walked

    /// The walk folder, found from this file rather than from the working
    /// directory, which `swift test` does not promise anything about.
    private static var walkDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()          // Tests/PhotonzCoreTests
            .deletingLastPathComponent()          // Tests
            .deletingLastPathComponent()          // repo root
            .appendingPathComponent("Scripts/playtest")
    }

    /// Every walk that drives a guide, reduced to what the rule reads.
    static func walksThatDriveGuides() throws -> [TutorialWalkCoverage.Walk] {
        let files = try FileManager.default
            .contentsOfDirectory(at: walkDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try files.compactMap { file in
            let script = try PlaytestScript.decode(try Data(contentsOf: file))
            var guides: [String] = []
            var waitsOn: [String] = []
            for step in script.steps {
                switch step {
                case .startGuide(let id, _):
                    guides.append(id)
                // The tour has its own way in, because first run offers it by
                // name. It is the same guide either way.
                case .action(.startTour), .action(.takeTheTour), .action(.startTourHere):
                    guides.append(TutorialCatalog.tourID)
                case .waitFor(.tutorialStep(let id), _):
                    waitsOn.append(id)
                default:
                    continue
                }
            }
            guard !guides.isEmpty else { return nil }
            return TutorialWalkCoverage.Walk(name: file.lastPathComponent,
                                             guides: guides, waitsOn: waitsOn)
        }
    }

    @Test("Every guide in the catalogue has a walk that goes all the way through it")
    func everyGuideIsWalked() throws {
        let walks = try Self.walksThatDriveGuides()
        try #require(!walks.isEmpty, "no walks found in \(Self.walkDirectory.path)")
        #expect(TutorialWalkCoverage.problems(walks: walks) == [])
    }

    @Test("A guide nobody walks is caught, by name")
    func aGuideWithNoWalkIsCaught() {
        let guide = TutorialGuide(id: "unwalked", track: .basics, title: "Unwalked",
                                  summary: "Nobody drives this.", minutes: 1, sample: nil,
                                  steps: [TutorialStep(id: "one", anchor: .canvas,
                                                       title: "Look", body: "Look here.")])
        let problems = TutorialWalkCoverage.problems(guides: [guide], walks: [])
        #expect(problems.count == 1)
        #expect(problems[0].contains("unwalked"))
    }

    @Test("A walk that stops part way through a guide leaves its last steps unchecked")
    func aWalkThatStopsPartWayIsCaught() {
        let guide = TutorialGuide(
            id: "three-steps", track: .basics, title: "Three", summary: "Three steps.",
            minutes: 1, sample: nil,
            steps: [TutorialStep(id: "one", anchor: .canvas, title: "One", body: "First."),
                    TutorialStep(id: "two", anchor: .toolBar, title: "Two", body: "Second."),
                    TutorialStep(id: "three", anchor: .panel, title: "Three", body: "Third.")])
        let walk = TutorialWalkCoverage.Walk(name: "half-a-walk.json",
                                             guides: ["three-steps"], waitsOn: ["one"])
        let problems = TutorialWalkCoverage.problems(guides: [guide], walks: [walk])
        #expect(problems.count == 1)
        #expect(problems[0].contains("half-a-walk.json"))
        #expect(problems[0].contains("two"))
        #expect(problems[0].contains("three"))
    }

    @Test("A walk still driving a guide that has been renamed is caught")
    func aWalkDrivingAGuideThatIsGoneIsCaught() {
        let walk = TutorialWalkCoverage.Walk(name: "stale-walk.json",
                                             guides: ["guide-that-moved-on"], waitsOn: [])
        let problems = TutorialWalkCoverage.problems(guides: [], walks: [walk])
        #expect(problems.contains { $0.contains("stale-walk.json") && $0.contains("guide-that-moved-on") })
    }

    // MARK: - Every step really found its control

    @Test("A step whose control never appeared names the guide, the step and the name")
    func aMissingControlIsNamed() {
        let verdicts = [
            TutorialAnchorVerdict(guide: "mark-it-up", step: "pick-the-tool",
                                  anchor: .tool(.arrow), resolved: false, shownSeconds: 3.2),
        ]
        let problems = TutorialAnchorAudit.problems(in: verdicts,
                                                    namesOnScreen: ["canvas", "toolBar", "tool.select"])
        #expect(problems.count == 1)
        let said = problems[0]
        // Everything the person fixing it needs, without opening the framework.
        #expect(said.contains("mark-it-up"))
        #expect(said.contains("pick-the-tool"))
        #expect(said.contains("tool.arrow"))
        #expect(said.contains("tool.select"))
    }

    @Test("A step that found its control says nothing")
    func aResolvedStepIsNotAProblem() {
        let verdicts = [
            TutorialAnchorVerdict(guide: "take-the-tour", step: "the-canvas", anchor: .canvas,
                                  resolved: true, shownSeconds: 4),
        ]
        #expect(TutorialAnchorAudit.problems(in: verdicts) == [])
    }

    @Test("A step gone in a blink is not called a miss")
    func aStepLeftTooFastIsNotJudged() {
        // A panel section that arrives with a selection is a beat behind the
        // callout. A walk that moves on inside that beat has not shown the
        // control missing, it has shown nobody looked, and a check that cries
        // wolf here is a check people switch off.
        let blink = TutorialAnchorVerdict(guide: "override-one-copy", step: "the-name",
                                          anchor: .panelSection("component"),
                                          resolved: false, shownSeconds: 0.05)
        #expect(TutorialAnchorAudit.problems(in: [blink]) == [])
        let waited = TutorialAnchorVerdict(guide: "override-one-copy", step: "the-name",
                                           anchor: .panelSection("component"),
                                           resolved: false,
                                           shownSeconds: TutorialAnchorAudit.grace + 0.1)
        #expect(TutorialAnchorAudit.problems(in: [waited]).count == 1)
    }

    // MARK: - A guide behind a feature flag

    @Test("Every flagged guide is offered with its flag on and gone with it off")
    func theShippingCatalogueAnswersToItsFlags() {
        #expect(TutorialFlagRules.problems() == [])
    }

    @Test("A guide that ignores its own flag is caught")
    func aGuideThatStaysWhenItsFeatureIsOffIsCaught() {
        // A made up catalogue where the rule is broken on purpose: the guide
        // says it needs a flag, and the filter is asked with that flag off.
        let guide = TutorialGuide(id: "needs-lenses", track: .looks, title: "Lenses",
                                  summary: "Teaches a feature that can be switched off.",
                                  minutes: 1, sample: nil, requires: ["lens"],
                                  steps: [TutorialStep(id: "one", anchor: .tool(.lens),
                                                       title: "The lens", body: "Here it is.")])
        // With it on, it is offered.
        #expect(TutorialCatalog.guides(enabled: { _ in true }, from: [guide]).count == 1)
        // With it off, it is not, and the menu is empty rather than holding it.
        let offered = TutorialCatalog.guides(enabled: { $0 != "lens" }, from: [guide])
        #expect(offered.isEmpty)
        #expect(TutorialMenuModel(guides: offered).isEmpty)
        #expect(TutorialFlagRules.problems(in: [guide]) == [])
    }
}
