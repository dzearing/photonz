import Foundation
import Testing
@testable import PhotonzCore

/// The window New Window opens (`ui-entry-wt.html`, steps 2 to 4): four
/// starting templates, and a primary button that says what it will make.
@Suite("The front door")
struct FrontDoorTests {

    @Test("Four templates, in the mock's order")
    func theTemplates() {
        #expect(FrontDoorTemplate.allCases.map(\.title)
                == ["Design UI", "Edit an image", "Edit video", "Capture & redline"])
    }

    @Test("With nothing picked the primary button makes a plain canvas")
    func nothingPicked() {
        #expect(FrontDoor.primaryTitle(picked: nil) == "New canvas")
    }

    @Test("Picking Design UI makes the primary button read New UI canvas")
    func designUIPicked() {
        #expect(FrontDoor.primaryTitle(picked: .designUI) == "New UI canvas")
    }

    @Test("Every template's primary button names a different thing to make")
    func everyPrimaryIsItsOwn() {
        let titles = FrontDoorTemplate.allCases.map { FrontDoor.primaryTitle(picked: $0) }
        #expect(Set(titles).count == titles.count)
        #expect(!titles.contains(FrontDoor.primaryTitle(picked: nil)))
    }

    @Test("A template is a mode preset: each names a mode the app ships")
    func templatesAreModes() {
        for template in FrontDoorTemplate.allCases {
            #expect(WindowModes.mode(template.modeID) != nil, "\(template) names no mode")
        }
        #expect(FrontDoorTemplate.designUI.modeID == "design")
        #expect(FrontDoorTemplate.editVideo.modeID == "video")
        #expect(FrontDoorTemplate.captureRedline.modeID == "redline")
        #expect(FrontDoorTemplate.editImage.modeID == WindowModes.everythingID)
    }

    @Test("Every word the front door draws is a label inside the chrome budget")
    func everyDrawnWordIsALabel() {
        // A button is named by the command it is, so only the words that
        // are not on a button are held to never saying how.
        var commands = [FrontDoor.openTitle, FrontDoor.createTitle, FrontDoor.primaryTitle(picked: nil)]
        var words = [FrontDoor.subtitle, FrontDoor.startHeader, FrontDoor.recentHeader,
                     FrontDoor.promptPlaceholder]
        for template in FrontDoorTemplate.allCases {
            words.append(template.title)
            commands.append(FrontDoor.primaryTitle(picked: template))
            if let detail = template.detail { words.append(detail) }
        }
        for text in commands + words {
            #expect(CopyBudget.chromeFaults(text).isEmpty, "\(text): \(CopyBudget.chromeFaults(text))")
        }
        for text in words {
            #expect(NoticeCopy.instructions(in: text).isEmpty, "\(text) tells you how")
        }
    }

    @Test("A mock line over the budget moves into the tile's tip in the mock's words")
    func longMockLinesMoveIntoTheTip() {
        for template in FrontDoorTemplate.allCases {
            #expect(template.tip.contains(template.mockDetail))
            if template.mockDetail.count <= CopyBudget.chromeLine {
                #expect(template.detail == template.mockDetail)
            } else {
                #expect(template.detail == nil)
            }
        }
        #expect(FrontDoorTemplate.designUI.mockDetail == "Components, tokens, auto-layout")
        #expect(FrontDoorTemplate.editImage.detail == "Adjust, mask, retouch, effects")
    }

    @Test("Recent shows the newest few captures and nothing when there are none")
    func recent() {
        let now = Date()
        let entries = (0..<9).map {
            CaptureEntry(url: URL(fileURLWithPath: "/tmp/\($0).png"),
                         createdAt: now.addingTimeInterval(TimeInterval(-$0)), kind: .image)
        }
        #expect(FrontDoor.recent(entries).map(\.fileName) == ["0.png", "1.png", "2.png", "3.png"])
        #expect(FrontDoor.recent([]).isEmpty)
    }

    @Test("The front door is on by default in Next and absent from Current")
    func flag() {
        #expect(FeatureCatalog.defaultSettings(for: .next).isEnabled(FeatureCatalog.frontDoorFlag))
        #expect(!FeatureCatalog.flags(for: .current).contains { $0.name == FeatureCatalog.frontDoorFlag })
    }
}
