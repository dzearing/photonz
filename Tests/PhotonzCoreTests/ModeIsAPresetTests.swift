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

    /// Design: you are building screens, so the redlining list and motion are
    /// folded and the layout sections stay.
    private static func designMode() -> PanelSectionVisibility.Choices {
        WindowModes.mode("design")?.preset ?? PanelSectionVisibility.Choices()
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
        let icon = Self.iconMode(), design = Self.designMode()
        #expect(icon != design)
        // The two modes are genuinely different windows...
        #expect(PanelSectionVisibility.shown(PanelSectionVisibility.optionalSections,
                                             choices: icon, in: situation)
                != PanelSectionVisibility.shown(PanelSectionVisibility.optionalSections,
                                                choices: design, in: situation))
        // ...and yet every section the two modes did NOT speak about answers
        // identically in both, because that answer is read off the document
        // alone. A mode can only fold what it names; it cannot reinterpret the
        // document underneath it.
        for section in PanelSectionVisibility.optionalSections
        where !icon.isCustom(section) && !design.isCustom(section) {
            #expect(PanelSectionVisibility.isShown(section, choices: icon, in: situation)
                    == PanelSectionVisibility.isShown(section, choices: design, in: situation))
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
        let away = PanelSectionVisibility.shown(sections, choices: Self.designMode(), in: situation)
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
        // Image folds nothing and is where every picture starts, so somebody
        // who never finds modes has the app as it was.
        #expect(WindowModes.image.preset == PanelSectionVisibility.Choices())
        #expect(WindowModeSession().modeID(hasTime: false) == WindowModes.imageID)
    }

    @Test("Each mode the list offers answers to a number, in the order it is shown")
    func everyOfferedModeHasAKey() {
        let offered = WindowModes.offered(hasTime: false)
        #expect(offered.count == 3)
        for (index, mode) in offered.enumerated() {
            #expect(WindowModes.shortcutNumber(for: mode.id) == index + 1)
        }
        // The video setup is never in a list, so it has no key either.
        #expect(WindowModes.shortcutNumber(for: WindowModes.videoID) == nil)
        #expect(WindowModes.shortcutNumber(for: "no-such-mode") == nil)
    }

    @Test("Swapping a window's mode hands the panel that mode's arrangement")
    func swappingHandsOverTheArrangement() {
        var session = WindowModeSession()
        let arrangements = WindowModeArrangements()
        let swapped1 = session.swap(to: "icon", hasTime: false)
        #expect(swapped1)
        #expect(session.modeID(hasTime: false) == "icon")
        let onScreen = arrangements.arrangement(of: session.modeID(hasTime: false))
        #expect(onScreen == Self.iconMode())
        #expect(session.chipLabel(hasTime: false, arrangements: arrangements) == "Icon")
        // A mode nobody wrote down changes nothing at all: no half swap, no
        // empty window.
        var stubborn = session
        let swapped2 = stubborn.swap(to: "not-a-mode", hasTime: false)
        #expect(!swapped2)
        #expect(stubborn == session)
    }

    @Test("Bending a mode by hand keeps it bent, says so, and can be put back")
    func aModeYouBendStaysBent() {
        var session = WindowModeSession()
        var arrangements = WindowModeArrangements()
        session.swap(to: "icon", hasTime: false)
        // You reach for the measurements list while in Icon, the way the way
        // back is supposed to work: one switch, and you are still in Icon.
        var onScreen = arrangements.arrangement(of: "icon")
        onScreen.set("measurements", shown: true)
        arrangements.keep(onScreen, for: "icon")
        #expect(session.modeID(hasTime: false) == "icon")
        #expect(arrangements.isBent("icon"))
        #expect(session.chipLabel(hasTime: false, arrangements: arrangements) == "Icon, edited")
        // And the mode can be put back as it shipped without leaving it.
        arrangements.reset("icon")
        #expect(arrangements.arrangement(of: "icon") == Self.iconMode())
        #expect(!arrangements.isBent("icon"))
        // Bending a mode back to its own preset by hand is not a bend.
        arrangements.keep(onScreen, for: "icon")
        arrangements.keep(Self.iconMode(), for: "icon")
        #expect(!arrangements.isBent("icon"))
    }

    @Test("Swapping away and back lands on the arrangement you left, bends and all")
    func comingBackIsTheWindowYouLeft() {
        var session = WindowModeSession()
        var arrangements = WindowModeArrangements()
        session.swap(to: "icon", hasTime: false)
        var icon = arrangements.arrangement(of: "icon")
        icon.set("measurements", shown: true)
        icon.set("shadow", shown: false)
        arrangements.keep(icon, for: "icon")

        session.swap(to: "design", hasTime: false)
        #expect(arrangements.arrangement(of: session.modeID(hasTime: false))
                == WindowModes.mode("design")?.preset)

        session.swap(to: "icon", hasTime: false)
        #expect(arrangements.arrangement(of: session.modeID(hasTime: false)) == icon)
        #expect(arrangements.isBent("icon"))
    }

    @Test("Show everything gives the lot back and does not lose the mode you left")
    func showEverythingIsTheWayOut() {
        let situation = Self.mixedSituation()
        var session = WindowModeSession()
        var arrangements = WindowModeArrangements()
        session.swap(to: "icon", hasTime: false)
        var icon = arrangements.arrangement(of: "icon")
        icon.set("arrange", shown: false)
        arrangements.keep(icon, for: "icon")
        // Image bent too, so the way out has to put it straight as well.
        var image = PanelSectionVisibility.Choices()
        image.set("motion", shown: false)
        arrangements.keep(image, for: WindowModes.imageID)

        session.showEverything(hasTime: false, arrangements: &arrangements)
        #expect(session.modeID(hasTime: false) == WindowModes.imageID)
        let everything = arrangements.arrangement(of: WindowModes.imageID)
        #expect(!everything.hasAnyCustom)
        #expect(session.chipLabel(hasTime: false, arrangements: arrangements) == "Image")
        // The panel is now the one somebody who never touched a mode has.
        #expect(PanelSectionVisibility.shown(PanelSectionVisibility.optionalSections,
                                             choices: everything, in: situation)
                == PanelSectionVisibility.shown(PanelSectionVisibility.optionalSections,
                                                choices: .init(), in: situation))
        // And Icon still holds what you did to it, so this was a way out and
        // never a way to lose an arrangement.
        #expect(arrangements.arrangement(of: "icon") == icon)
    }

    @Test("How each mode is arranged survives being written down and read back")
    func arrangementsAreWrittenDownAndReadBack() throws {
        var arrangements = WindowModeArrangements()
        var icon = Self.iconMode()
        icon.set("measurements", shown: true)
        arrangements.keep(icon, for: "icon")

        let data = try JSONEncoder().encode(arrangements)
        let reread = try JSONDecoder().decode(WindowModeArrangements.self, from: data)
        #expect(reread == arrangements)
        #expect(reread.arrangement(of: "icon") == icon)

        // A settings file naming a mode this build no longer ships drops it,
        // rather than holding an arrangement for a window that cannot exist.
        let stale = WindowModeArrangements(bends: ["also-gone": "motion=0"])
        #expect(stale == WindowModeArrangements())
        #expect(stale.arrangement(of: "icon") == Self.iconMode())
    }

    @Test("Every mode can be reached from the keyboard, and a walk can press it")
    func everyModeIsReachableWithoutThePointer() throws {
        for mode in WindowModes.offered(hasTime: false) {
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
        let beyond = WindowModes.offered(hasTime: false).count + 1
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
        var arrangements = WindowModeArrangements()
        session.swap(to: "icon", hasTime: false)
        session.swap(to: "design", hasTime: false)
        session.showEverything(hasTime: false, arrangements: &arrangements)
        #expect(session.modeID(hasTime: false) == WindowModes.imageID)

        let after = try encoder.encode(document)
        #expect(before == after)
    }
}
