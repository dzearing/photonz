import Foundation
import PhotonzCore
import Testing

@Suite("Placed image naming")
struct PlacedImageNamingTests {

    // MARK: A file someone named

    @Test func keepsAFileNameWithoutItsExtension() {
        #expect(PlacedImageNaming.layerName(fileName: "login-screen.png") == "login-screen")
        #expect(PlacedImageNaming.layerName(fileName: "Sign up flow v2.jpeg") == "Sign up flow v2")
    }

    @Test func keepsDotsInsideTheName() {
        #expect(PlacedImageNaming.layerName(fileName: "logo.v2.final.png") == "logo.v2.final")
    }

    @Test func keepsANameThatHasNoExtension() {
        #expect(PlacedImageNaming.layerName(fileName: "Hero") == "Hero")
    }

    @Test func ignoresThePathAroundTheName() {
        #expect(PlacedImageNaming.layerName(fileName: "/Users/me/Pictures/hero.png") == "hero")
    }

    // MARK: Captures the app named itself

    /// A capture's file name is all prefix and date, and every one of them
    /// starts the same way, so the full name truncates to something identical
    /// in a 220pt panel. The clock time is the part that tells two apart.
    @Test func shortensACaptureNameToTheTimeItWasTaken() {
        #expect(PlacedImageNaming.layerName(fileName: "Screenshot 2026-06-21 at 10.30.45.png")
                == "Screenshot 10.30.45")
        #expect(PlacedImageNaming.layerName(fileName: "Recording 2026-06-21 at 09.02.11.mov")
                == "Recording 09.02.11")
    }

    @Test func keepsTheCopySuffixMacOSAddsToADuplicate() {
        #expect(PlacedImageNaming.layerName(fileName: "Screenshot 2026-06-21 at 10.30.45 (2).png")
                == "Screenshot 10.30.45 (2)")
    }

    @Test func leavesACaptureSomeoneRenamedAlone() {
        #expect(PlacedImageNaming.layerName(fileName: "Screenshot of the empty state.png")
                == "Screenshot of the empty state")
        #expect(PlacedImageNaming.layerName(fileName: "Screenshotty.png") == "Screenshotty")
        // Only a real date after the prefix means the app named this file.
        #expect(PlacedImageNaming.layerName(fileName: "Screenshot of the cat at night.png")
                == "Screenshot of the cat at night")
    }

    // MARK: Two copies of the same file

    /// Dropping one file in twice used to leave two rows reading the exact
    /// same word, and the only way out was to rename one by hand. The second
    /// one takes the next free number, the way a second drawn rectangle does.
    @Test func numbersASecondCopyOfTheSameFile() {
        #expect(PlacedImageNaming.layerName(fileName: "hero.png", taken: []) == "hero")
        #expect(PlacedImageNaming.layerName(fileName: "hero.png", taken: ["hero"]) == "hero 2")
        #expect(PlacedImageNaming.layerName(fileName: "hero.png",
                                            taken: ["hero", "hero 2"]) == "hero 3")
    }

    /// Nothing is numbered until there is something to tell apart, so a file
    /// nobody else in the document shares keeps its plain name.
    @Test func leavesTheOnlyCopyOfAFileAlone() {
        #expect(PlacedImageNaming.layerName(fileName: "hero.png",
                                            taken: ["login-screen", "Card"]) == "hero")
    }

    /// The picture arriving is the one that moves aside: a layer somebody
    /// named themselves is never renumbered behind their back.
    @Test func stepsAsideRatherThanRenamingWhatIsAlreadyThere() {
        #expect(PlacedImageNaming.layerName(fileName: "hero.png", taken: ["hero"]) == "hero 2")
    }

    /// A capture is numbered by the short name it actually wears in the list,
    /// not by the long file name behind it.
    @Test func numbersACaptureByItsShortenedName() {
        #expect(PlacedImageNaming.layerName(fileName: "Screenshot 2026-06-21 at 10.30.45.png",
                                            taken: ["Screenshot 10.30.45"])
                == "Screenshot 10.30.45 2")
    }

    @Test func numbersRepeatedClipboardPastes() {
        #expect(PlacedImageNaming.layerName(fileName: nil, taken: ["Pasted Image"])
                == "Pasted Image 2")
    }

    // MARK: Nothing to name it after

    @Test func fallsBackToPastedImageWithNoFile() {
        #expect(PlacedImageNaming.layerName(fileName: nil) == "Pasted Image")
        #expect(PlacedImageNaming.clipboardName == "Pasted Image")
    }

    @Test func fallsBackToPastedImageWhenTheNameIsBlank() {
        #expect(PlacedImageNaming.layerName(fileName: "") == "Pasted Image")
        #expect(PlacedImageNaming.layerName(fileName: "   ") == "Pasted Image")
    }

    @Test func trimsSurroundingSpace() {
        #expect(PlacedImageNaming.layerName(fileName: "  hero .png") == "hero")
    }
}
