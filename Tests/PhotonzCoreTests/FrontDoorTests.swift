import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// The window File > New opens: two things to make, an Image or a Video, each
/// with its sizes, and a primary button that says which one it will make
/// (the user, 2026-10-22: "have Image or Video in the new dialog", "new
/// should not have load image in it").
@Suite("The New window")
struct FrontDoorTests {

    @Test("Two choices, Image then Video, and nothing else")
    func theChoices() {
        #expect(FrontDoorKind.allCases.map(\.title) == ["Image", "Video"])
        #expect(FrontDoorKind.default == .image)
    }

    @Test("The primary button names what it makes")
    func primaryTitles() {
        #expect(FrontDoorKind.image.createTitle == "New Image")
        #expect(FrontDoorKind.video.createTitle == "New Video")
    }

    @Test("An image offers the blank canvas sizes, a video the blank video sizes")
    func sizes() {
        #expect(FrontDoorKind.image.sizes.map(\.id) == BlankCanvas.presets.map(\.id))
        #expect(FrontDoorKind.image.sizes.map(\.size) == BlankCanvas.presets.map(\.size))
        #expect(FrontDoorKind.video.sizes.map(\.id) == BlankVideo.presets.map(\.id))
        #expect(FrontDoorKind.video.sizes.map(\.size) == BlankVideo.presets.map(\.size))
        #expect(FrontDoorKind.image.defaultSize == BlankCanvas.defaultPreset.size)
        #expect(FrontDoorKind.video.defaultSize == BlankVideo.defaultPreset.size)
    }

    @Test("Only a video asks for a length")
    func length() {
        #expect(!FrontDoorKind.image.hasLength)
        #expect(FrontDoorKind.video.hasLength)
    }

    @Test("A typed size is held to the kind's own rules")
    func typedSizes() {
        // A picture may be odd sized; a movie is written in pairs of pixels.
        #expect(FrontDoorKind.image.isValid(CGSize(width: 801, height: 601)))
        #expect(!FrontDoorKind.video.isValid(CGSize(width: 801, height: 601)))
        #expect(FrontDoorKind.video.isValid(CGSize(width: 800, height: 600)))
        #expect(!FrontDoorKind.image.isValid(CGSize(width: 0, height: 600)))
    }

    @Test("Each kind opens in its own mode")
    func modes() {
        #expect(FrontDoorKind.image.modeID == WindowModes.imageID)
        #expect(FrontDoorKind.video.modeID == WindowModes.videoID)
        for kind in FrontDoorKind.allCases {
            #expect(WindowModes.mode(kind.modeID) != nil, "\(kind) names no mode")
        }
    }

    @Test("The empty window's card offers the same two choices")
    func emptyCard() {
        #expect(FrontDoorKind.allCases.map(\.cardTitle) == ["New image", "New video"])
    }

    @Test("Nothing about opening, capturing or designing UI is offered as something new")
    func nothingButNew() {
        let words = FrontDoorKind.allCases.flatMap { [$0.title, $0.createTitle, $0.cardTitle] }
            + [FrontDoor.subtitle, FrontDoor.sizeHeader]
        for word in words {
            for banned in ["Open", "Capture", "Design", "Recent", "Edit"] {
                #expect(!word.contains(banned), "\(word) mentions \(banned)")
            }
        }
    }

    @Test("Every word the New window draws is a label inside the chrome budget")
    func everyDrawnWordIsALabel() {
        let commands = [FrontDoor.createTitle] + FrontDoorKind.allCases.map(\.createTitle)
        var words = [FrontDoor.subtitle, FrontDoor.sizeHeader, FrontDoor.customTitle,
                     FrontDoor.lengthTitle, FrontDoor.promptPlaceholder]
        words += FrontDoorKind.allCases.flatMap { kind in [kind.title] + kind.sizes.map(\.title) }
        for text in commands + words {
            #expect(CopyBudget.chromeFaults(text).isEmpty, "\(text): \(CopyBudget.chromeFaults(text))")
        }
        for text in words {
            #expect(NoticeCopy.instructions(in: text).isEmpty, "\(text) tells you how")
        }
    }

    @Test("A size reads as its width by its height")
    func dimensions() {
        #expect(FrontDoor.dimensions(CGSize(width: 1440, height: 1024)) == "1440 \u{00D7} 1024")
    }

    @Test("The New window is on by default in Next and absent from Current")
    func flag() {
        #expect(FeatureCatalog.defaultSettings(for: .next).isEnabled(FeatureCatalog.frontDoorFlag))
        #expect(!FeatureCatalog.flags(for: .current).contains { $0.name == FeatureCatalog.frontDoorFlag })
    }
}
