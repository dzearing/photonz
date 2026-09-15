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
    private static func iconMode() -> PanelSectionVisibility.Choices {
        var choices = PanelSectionVisibility.Choices()
        choices.set("measurements", shown: false)
        choices.set("library", shown: false)
        choices.set("columns", shown: false)
        return choices
    }

    /// Redline: you are measuring a capture, so the list of measurements is up
    /// and the things that only matter while building are folded.
    private static func redlineMode() -> PanelSectionVisibility.Choices {
        var choices = PanelSectionVisibility.Choices()
        choices.set("measurements", shown: true)
        choices.set("motion", shown: false)
        choices.set("component", shown: false)
        return choices
    }

    /// A document with an icon frame, a screen frame and a measurement on it:
    /// the mixed document that made project types impossible, reused here
    /// because a mode has to survive it too.
    private static func mixedSituation() -> PanelSectionVisibility.Situation {
        PanelSectionVisibility.Situation(documentHasMeasurement: true,
                                         documentHasComponent: true,
                                         documentHasContainer: true,
                                         documentHasColumns: true,
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
}
