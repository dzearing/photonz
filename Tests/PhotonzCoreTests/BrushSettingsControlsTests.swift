import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// The brush's own settings as controls (`docs/design/brushes.md`, decision 7):
/// what the tool options capsule carries, what kind of control each setting
/// is, how [ and ] step the size, and each medium remembering its own values.
@Suite("Brush settings controls")
struct BrushSettingsControlsTests {

    // MARK: - The capsule over the tool bar

    @Test("The brush puts its chooser, Mode, Size, Opacity and two of its own settings over the tool bar")
    func capsule() {
        #expect(ToolSettingsBar.settings(for: .brush, availability: .all)
                == [.brushMedium, .brushMode, .brushSize, .brushOpacity, .brushOwnFirst, .brushOwnSecond])
        #expect(ToolSetting.brushSize.title == "Size")
        #expect(ToolSetting.brushOpacity.title == "Opacity")
    }

    @Test("The capsule carries each medium's first two own settings")
    func capsuleOwn() {
        #expect(BrushMedium.pencil.toolOptionSettings.map(\.id) == ["hardness", "grain"])
        #expect(BrushMedium.charcoal.toolOptionSettings.map(\.id) == ["grain", "smudge"])
        #expect(BrushMedium.marker.toolOptionSettings.map(\.id) == ["tip", "flow"])
        #expect(BrushMedium.airbrush.toolOptionSettings.map(\.id) == ["flow", "spread"])
        #expect(BrushMedium.oil.toolOptionSettings.map(\.id) == ["load", "smear"])
        #expect(BrushMedium.watercolour.toolOptionSettings.map(\.id) == ["wetness", "bleed"])
    }

    @Test("Every medium has at least two settings of its own, after Size and Opacity")
    func ownSettings() {
        for medium in BrushMedium.allCases {
            #expect(medium.ownSettings.count >= 2, "\(medium)")
            #expect(medium.settings.map(\.id).prefix(2) == ["size", "opacity"])
            #expect(medium.ownSettings == Array(medium.settings.dropFirst(2)))
            for spec in medium.settings {
                #expect(!spec.name.isEmpty)
                // A capsule label is chrome: a word or two, never a sentence.
                #expect(spec.name.count <= 14, "\(spec.name)")
            }
        }
    }

    // MARK: - What kind of control a setting is

    @Test("A number is a slider, two or three choices a segmented control, more a dropdown")
    func controlKinds() {
        func kind(_ medium: BrushMedium, _ id: String) -> BrushSettingSpec.Control? {
            medium.settings.first { $0.id == id }?.control
        }
        #expect(kind(.charcoal, "grain") == .slider)
        #expect(kind(.charcoal, "size") == .slider)
        #expect(kind(.marker, "tip") == .segmented)
        #expect(kind(.pencil, "hardness") == .dropdown)
    }

    @Test("A setting reads as a choice's word, Size in points and the rest as a percentage")
    func readings() {
        let pencil = BrushMedium.pencil
        let hardness = pencil.settings[2]
        #expect(hardness.reading(2) == "HB")
        #expect(hardness.reading(6) == "8B")
        #expect(pencil.settings[0].reading(16.4) == "16 pt")
        #expect(pencil.settings[1].reading(60) == "60%")
        #expect(BrushMedium.marker.settings[2].reading(1) == "Chisel")
    }

    // MARK: - [ and ]

    @Test("] grows and [ shrinks the brush in Photoshop's steps")
    func bracketSteps() {
        #expect(BrushSize.stepped(3, larger: true) == 4)
        #expect(BrushSize.stepped(4, larger: false) == 3)
        #expect(BrushSize.stepped(10, larger: true) == 15)
        #expect(BrushSize.stepped(10, larger: false) == 9)
        #expect(BrushSize.stepped(50, larger: true) == 60)
        #expect(BrushSize.stepped(50, larger: false) == 45)
        #expect(BrushSize.stepped(100, larger: true) == 125)
        #expect(BrushSize.stepped(200, larger: true) == 250)
        #expect(BrushSize.stepped(300, larger: true) == 400)
        // The ends hold.
        #expect(BrushSize.stepped(1, larger: false) == 1)
        #expect(BrushSize.stepped(500, larger: true) == 500)
        #expect(BrushSize.stepped(450, larger: true) == 500)
        // An odd size between steps lands on the next step, not past it.
        #expect(BrushSize.stepped(12, larger: true) == 15)
        #expect(BrushSize.stepped(12, larger: false) == 10)
        #expect(BrushSize.stepped(7.6, larger: true) == 8)
    }

    @Test("Growing then shrinking from a step comes back to it")
    func bracketRoundTrip() {
        var size = 1.0
        var seen: [Double] = [size]
        while size < 500 {
            size = BrushSize.stepped(size, larger: true)
            seen.append(size)
        }
        for (smaller, larger) in zip(seen, seen.dropFirst()) {
            #expect(BrushSize.stepped(larger, larger: false) == smaller, "\(larger)")
        }
    }

    // MARK: - Each medium remembers its own

    @Test("Each medium remembers its own values, and one never used starts at its own defaults")
    func memory() {
        var styles = AnnotationStyles()
        var charcoal = styles.armedBrush
        #expect(charcoal.medium == .charcoal)
        charcoal.set("size", to: 40)
        charcoal.set("grain", to: 10)
        styles.setArmedBrush(charcoal)

        styles.armBrush(.marker)
        #expect(styles.armedBrush.medium == .marker)
        // Never used: the marker's own size, not the charcoal's 40.
        #expect(styles.armedBrush.size == BrushSettings(medium: .marker).size)
        var marker = styles.armedBrush
        marker.set("size", to: 30)
        marker.set("tip", to: 1)
        styles.setArmedBrush(marker)

        styles.armBrush(.charcoal)
        #expect(styles.armedBrush.size == 40)
        #expect(styles.armedBrush.value("grain") == 10)
        #expect(styles.brush(for: .marker).size == 30)
        #expect(styles.brush(for: .marker).value("tip") == 1)
        #expect(styles.brush(for: .airbrush) == BrushSettings(medium: .airbrush))
    }

    @Test("Switching medium keeps the brush smudging")
    func memoryKeepsMode() {
        var styles = AnnotationStyles()
        var brush = styles.armedBrush
        brush.mode = .smudge
        styles.setArmedBrush(brush)
        styles.armBrush(.chalk)
        #expect(styles.armedBrush.mode == .smudge)
        #expect(styles.brush(for: .oil).mode == .smudge)
    }

    @Test("What each medium remembers survives a relaunch, and untouched prefs write nothing new")
    func memoryCodable() throws {
        let fresh = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AnnotationStyles())) as? [String: Any]
        #expect(fresh?["brushes"] == nil)

        var styles = AnnotationStyles()
        var charcoal = styles.armedBrush
        charcoal.set("size", to: 40)
        styles.setArmedBrush(charcoal)
        styles.armBrush(.watercolour)
        var wet = styles.armedBrush
        wet.set("bleed", to: 90)
        styles.setArmedBrush(wet)

        let again = try JSONDecoder().decode(AnnotationStyles.self, from: JSONEncoder().encode(styles))
        #expect(again == styles)
        #expect(again.armedBrush.medium == .watercolour)
        #expect(again.armedBrush.value("bleed") == 90)
        #expect(again.brush(for: .charcoal).size == 40)
    }

    @Test("Prefs written before the memory keep their armed brush")
    func memoryMigrates() throws {
        let old = #"{"shapes":{},"brush":{"medium":"chalk","values":{"size":33}}}"#
        let decoded = try JSONDecoder().decode(AnnotationStyles.self, from: Data(old.utf8))
        #expect(decoded.armedBrush.medium == .chalk)
        #expect(decoded.armedBrush.size == 33)
        #expect(decoded.brush(for: .chalk).size == 33)
    }
}
