import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A MODE is a named preset of choices the app already has, and it can never
/// become a kind the document is stuck in (study: `docs/design/modes.md`,
/// page `http://127.0.0.1:8791/index.html#modes`).
///
/// The user asked for modes you can swap rather than project types you are
/// locked into: "you can just swap between modes without changing a document
/// type... there's always a way to get back to the thing you had open a second
/// ago". Four claims hold that up, and each one is a fact about code that is
/// already running rather than a promise about code we might write:
///
/// 1. A mode needs no new mechanism. `PanelSectionVisibility.Choices` is
///    already a per-section yes/no you can save and read back, which is exactly
///    what a mode is a named bundle of.
/// 2. No mode can hide what makes this one app. Only `optionalSections` may be
///    turned off, and the layers list, the picked layer's own section,
///    Appearance and Effects are not in it, so every mode shows the same
///    skeleton.
/// 3. Swapping a mode cannot change the document. What automatic says is read
///    off the document alone, so it answers the same under every mode.
/// 4. Nothing a mode hides is lost. Every hidden section is one call from
///    coming back, the panel can say in words that YOU turned it off rather
///    than that the document has nothing for it, and handing the lot back to
///    automatic returns the window you had a second ago.
struct ModeIsAPresetTests {

    // MARK: The two modes used throughout, written as data

    /// Icon: you are drawing a glyph, so the redlining list and the shelf are
    /// folded away and motion stays, because an icon that moves is the point of
    /// the icon epic.
    ///
    /// Read out of the SHIPPED catalog rather than written again here. These
    /// were hand-built fixtures while modes were still a study; now that the
    /// app has them, a fixture that drifted from what ships would pin the wrong
    /// thing, which is the one way a test like this can be worse than nothing.
    private static func iconMode() -> PanelSectionVisibility.Choices {
        WindowModes.mode("icon")?.preset ?? PanelSectionVisibility.Choices()
    }

    /// Redline: you are measuring a capture, so the list of measurements is up
    /// and the things that only matter while building are folded.
    private static func redlineMode() -> PanelSectionVisibility.Choices {
        WindowModes.mode("redline")?.preset ?? PanelSectionVisibility.Choices()
    }

    /// A document with an icon frame, a screen frame and a measurement on it:
    /// the mixed document that made project types impossible, reused here
    /// because a mode has to survive it too.
    private static func mixedSituation() -> PanelSectionVisibility.Situation {
        PanelSectionVisibility.Situation(documentHasMeasurement: true,
                                         documentHasComponent: true,
                                         documentHasContainer: true,
                                         documentHasFrame: true,
                                         isLibraryAskedFor: false)
    }

    // MARK: 1 · a mode is the mechanism that is already there

    @Test("A mode is a bundle of the choices the panel already stores")
    func modeIsJustChoices() {
        let icon = Self.iconMode()
        // It survives a round trip through the same string the settings file
        // holds, so a mode can be written down and shipped as data.
        let reread = PanelSectionVisibility.Choices(stored: icon.stored)
        #expect(reread == icon)
        #expect(icon.stored == "columns=0;library=0;measurements=0")
        #expect(icon.customSections == ["library", "measurements", "columns"])
    }

    // MARK: 2 · one app, not four

    @Test("No mode can hide the parts that make every mode the same app")
    func noModeCanHideTheSkeleton() {
        // The layers list, the section named after what you picked, Appearance
        // and Effects are not optional, so no preset can take them away.
        for section in ["layers", "appearance", "effects", "selection"] {
            #expect(!PanelSectionVisibility.isOptional(section))
        }
        var greedy = PanelSectionVisibility.Choices()
        greedy.set("layers", shown: false)
        greedy.set("appearance", shown: false)
        #expect(!greedy.hasAnyCustom)
        #expect(PanelSectionVisibility.isShown("layers", choices: greedy,
                                               in: Self.mixedSituation()))
        #expect(PanelSectionVisibility.isShown("appearance", choices: greedy,
                                               in: Self.mixedSituation()))
    }

    // MARK: 3 · swapping a mode cannot change the document

    @Test("What the document says is the same under every mode")
    func theDocumentAnswersTheSameInEveryMode() {
        let situation = Self.mixedSituation()
        let icon = Self.iconMode(), redline = Self.redlineMode()
        #expect(icon != redline)
        // The two modes are genuinely different windows...
        #expect(PanelSectionVisibility.shown(PanelSectionVisibility.optionalSections,
                                             choices: icon, in: situation)
                != PanelSectionVisibility.shown(PanelSectionVisibility.optionalSections,
                                                choices: redline, in: situation))
        // ...and yet every section the two modes did NOT speak about answers
        // identically in both, because that answer is read off the document
        // alone. A mode can only fold what it names; it cannot reinterpret the
        // document underneath it.
        for section in PanelSectionVisibility.optionalSections
        where !icon.isCustom(section) && !redline.isCustom(section) {
            #expect(PanelSectionVisibility.isShown(section, choices: icon, in: situation)
                    == PanelSectionVisibility.isShown(section, choices: redline, in: situation))
        }
        // The document is untouched by either: it still holds its measurement
        // and its component, and automatic still says so.
        #expect(situation.documentHasMeasurement)
        #expect(PanelSectionVisibility.isShownAutomatically("measurements", in: situation))
        #expect(PanelSectionVisibility.isShownAutomatically("component", in: situation))
    }

    // MARK: 4 · nothing a mode hides is lost

    @Test("A section a mode folded says YOU turned it off, not that there is nothing for it")
    func theWindowCanSayWhereItWent() {
        let empty = PanelSectionVisibility.Situation()
        let icon = Self.iconMode()
        let hidden = PanelSectionVisibility.rows(for: ["measurements"],
                                                 choices: icon, in: Self.mixedSituation())
        #expect(hidden == [.init(section: "measurements", isShown: false, reason: .turnedOff)])
        // The other way a section can be absent reads differently, which is the
        // whole point: an empty document has no measurements to list, and that
        // is not somebody hiding anything.
        let nothingToShow = PanelSectionVisibility.rows(for: ["measurements"],
                                                        choices: .init(), in: empty)
        #expect(nothingToShow == [.init(section: "measurements", isShown: false,
                                        reason: .automaticallyOut)])
    }

    @Test("Turning a folded section back on takes one move and does not leave the mode")
    func theWayBackIsOneMove() {
        let situation = Self.mixedSituation()
        var icon = Self.iconMode()
        #expect(!PanelSectionVisibility.isShown("measurements", choices: icon, in: situation))
        icon.set("measurements", shown: true)
        #expect(PanelSectionVisibility.isShown("measurements", choices: icon, in: situation))
        #expect(PanelSectionVisibility.rows(for: ["measurements"], choices: icon, in: situation)
                    .first?.reason == .turnedOn)
        // Everything else the mode folded is still folded: you got your one
        // thing back without being thrown out of the arrangement.
        #expect(!PanelSectionVisibility.isShown("library", choices: icon, in: situation))
    }

    @Test("Swapping to another mode and back lands on exactly the window you left")
    func noModeIsATrap() {
        let situation = Self.mixedSituation()
        let sections = PanelSectionVisibility.optionalSections
        let before = PanelSectionVisibility.shown(sections, choices: Self.iconMode(), in: situation)
        let away = PanelSectionVisibility.shown(sections, choices: Self.redlineMode(), in: situation)
        #expect(before != away)
        let back = PanelSectionVisibility.shown(sections, choices: Self.iconMode(), in: situation)
        #expect(back == before)
        // And the way out of modes altogether is the same one move: hand the
        // lot back to automatic and the panel is the one somebody who never
        // touched a mode has.
        var custom = Self.iconMode()
        custom.useAutomaticForAll()
        #expect(PanelSectionVisibility.shown(sections, choices: .init(), in: situation)
                == PanelSectionVisibility.shown(sections, choices: custom, in: situation))
    }

    // MARK: 5 · the modes the app ships, and the way in and out of them

    @Test("Every shipped mode folds only what a mode is allowed to fold")
    func noShippedModeReachesPastTheOptionalList() {
        #expect(!WindowModes.all.isEmpty)
        for mode in WindowModes.all {
            for section in mode.preset.customSections {
                #expect(PanelSectionVisibility.isOptional(section),
                        "\(mode.id) names \(section), which no mode may touch")
            }
            #expect(!mode.title.isEmpty)
            #expect(!mode.summary.isEmpty)
            #expect(!mode.symbol.isEmpty)
        }
        // Ids are stable and unique, because they are what settings holds.
        #expect(Set(WindowModes.all.map(\.id)).count == WindowModes.all.count)
        // The one that folds nothing is the default, so somebody who never
        // finds modes has the app as it was.
        #expect(WindowModes.everything.preset == PanelSectionVisibility.Choices())
        #expect(WindowModeSession().modeID == WindowModes.everythingID)
    }

    @Test("Each mode the list offers answers to a number, in the order it is shown")
    func everySwappableModeHasAKey() {
        let swappable = WindowModes.swappable
        #expect(swappable.count >= 3)
        #expect(!swappable.contains { $0.id == WindowModes.everythingID })
        for (index, mode) in swappable.enumerated() {
            #expect(WindowModes.shortcutNumber(for: mode.id) == index + 1)
        }
        #expect(WindowModes.shortcutNumber(for: WindowModes.everythingID) == nil)
        #expect(WindowModes.shortcutNumber(for: "no-such-mode") == nil)
    }

    @Test("Swapping to a mode hands the panel that mode's arrangement")
    func swappingHandsOverTheArrangement() {
        var session = WindowModeSession()
        let onScreen = session.swap(to: "icon", leaving: PanelSectionVisibility.Choices())
        #expect(session.modeID == "icon")
        #expect(onScreen == Self.iconMode())
        #expect(!session.isBent(with: onScreen))
        #expect(session.chipLabel(with: onScreen) == "Icon")
        // A mode nobody wrote down changes nothing at all: no half swap, no
        // empty window.
        var stubborn = session
        let unchanged = stubborn.swap(to: "not-a-mode", leaving: onScreen)
        #expect(stubborn == session)
        #expect(unchanged == onScreen)
    }

    @Test("Bending a mode by hand keeps it bent, says so, and can be put back")
    func aModeYouBendStaysBent() {
        var session = WindowModeSession()
        var onScreen = session.swap(to: "icon", leaving: PanelSectionVisibility.Choices())
        // You reach for the measurements list while in Icon, the way the way
        // back is supposed to work: one switch, and you are still in Icon.
        onScreen.set("measurements", shown: true)
        #expect(session.modeID == "icon")
        #expect(session.isBent(with: onScreen))
        #expect(session.chipLabel(with: onScreen) == "Icon, edited")
        // And the mode can be put back as it shipped without leaving it.
        let reset = session.resetCurrent()
        #expect(reset == Self.iconMode())
        #expect(session.modeID == "icon")
        #expect(!session.isBent(with: reset))
    }

    @Test("Swapping away and back lands on the arrangement you left, bends and all")
    func comingBackIsTheWindowYouLeft() {
        var session = WindowModeSession()
        var icon = session.swap(to: "icon", leaving: PanelSectionVisibility.Choices())
        icon.set("measurements", shown: true)
        icon.set("shadow", shown: false)
        let bent = icon

        let redline = session.swap(to: "redline", leaving: bent)
        #expect(redline == Self.redlineMode())
        #expect(session.modeID == "redline")

        let back = session.swap(to: "icon", leaving: redline)
        #expect(back == bent)
        #expect(session.isBent(with: back))
        // A mode you never bent is still the mode as shipped.
        var untouched = WindowModeSession()
        _ = untouched.swap(to: "video", leaving: PanelSectionVisibility.Choices())
        let awayAndBack = untouched.swap(to: "video",
                                         leaving: untouched.swap(to: "icon",
                                                                 leaving: WindowModes.mode("video")!.preset))
        #expect(awayAndBack == WindowModes.mode("video")?.preset)
    }

    @Test("Show everything gives the lot back and does not lose the mode you left")
    func showEverythingIsTheWayOut() {
        let situation = Self.mixedSituation()
        var session = WindowModeSession()
        var icon = session.swap(to: "icon", leaving: PanelSectionVisibility.Choices())
        icon.set("arrange", shown: false)
        let bent = icon

        let everything = session.showEverything(leaving: bent)
        #expect(session.modeID == WindowModes.everythingID)
        #expect(!everything.hasAnyCustom)
        #expect(session.chipLabel(with: everything) == "Everything")
        // The panel is now the one somebody who never touched a mode has.
        #expect(PanelSectionVisibility.shown(PanelSectionVisibility.optionalSections,
                                             choices: everything, in: situation)
                == PanelSectionVisibility.shown(PanelSectionVisibility.optionalSections,
                                                choices: .init(), in: situation))
        // And Icon still holds what you did to it, so this was a way out and
        // never a way to lose an arrangement.
        #expect(session.swap(to: "icon", leaving: everything) == bent)
    }

    @Test("A mode survives being written down and read back, and a stale one is dropped")
    func aSessionIsWrittenDownAndReadBack() throws {
        var session = WindowModeSession()
        var icon = session.swap(to: "icon", leaving: PanelSectionVisibility.Choices())
        icon.set("measurements", shown: true)
        _ = session.swap(to: "redline", leaving: icon)

        let data = try JSONEncoder().encode(session)
        let reread = try JSONDecoder().decode(WindowModeSession.self, from: data)
        #expect(reread == session)
        #expect(reread.modeID == "redline")

        // A settings file naming a mode this build no longer ships falls back
        // to the one that folds nothing, rather than to a window with no name
        // and no sections.
        let stale = WindowModeSession(modeID: "pixel-art-that-was-removed",
                                      bends: ["also-gone": "motion=0"])
        #expect(stale.modeID == WindowModes.everythingID)
        #expect(stale.arrangement(of: "icon") == Self.iconMode())
    }

    @Test("Every mode can be reached from the keyboard, and a walk can press it")
    func everyModeIsReachableWithoutThePointer() throws {
        for mode in WindowModes.swappable {
            let number = try #require(WindowModes.shortcutNumber(for: mode.id))
            let key = try #require(PlaytestKey(String(number)))
            // The chord the View menu carries has a stand-in, so a scripted
            // walk pressing it drives the mode rather than reporting the
            // probe's frozen menu bar back at itself.
            #expect(PlaytestMenuStandIn.action(for: key, modifiers: [.control]) != nil,
                    "no stand-in for ⌃\(number), which is View ▸ Mode ▸ \(mode.title)")
        }
        // And nothing claims a chord for a mode that does not exist, which is
        // the failure the slice that makes modes editable data would introduce.
        let beyond = WindowModes.swappable.count + 1
        if let key = PlaytestKey(String(beyond)), beyond <= 9 {
            #expect(PlaytestMenuStandIn.action(for: key, modifiers: [.control]) == nil)
        }
    }

    @Test("No mode can be stored in a document, because a document has nowhere to put one")
    func nothingAboutAModeReachesTheDocument() throws {
        // The strongest form of the claim: swap modes as much as you like and
        // the bytes of the file do not move, because `Document` has no field
        // for a mode and never gains one. Anything else in this file would be a
        // promise; this is the file.
        var document = PhotonzDocument(canvasSize: CGSize(width: 64, height: 64))
        document.layers = [Layer(name: "Note", content: .text(TextContent(string: "S")),
                                 frame: CGRect(x: 0, y: 0, width: 10, height: 10))]
        // Sorted keys, so the comparison is about the document's CONTENTS and
        // not about the order a dictionary happened to come out in twice.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let before = try encoder.encode(document)

        var session = WindowModeSession()
        var choices = session.swap(to: "icon", leaving: PanelSectionVisibility.Choices())
        choices = session.swap(to: "video", leaving: choices)
        choices = session.showEverything(leaving: choices)
        #expect(session.modeID == WindowModes.everythingID)

        let after = try encoder.encode(document)
        #expect(before == after)
    }
}
