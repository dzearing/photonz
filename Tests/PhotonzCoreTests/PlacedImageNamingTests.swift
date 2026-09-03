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
