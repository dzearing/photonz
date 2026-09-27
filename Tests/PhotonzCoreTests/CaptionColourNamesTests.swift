import Testing
@testable import PhotonzCore

/// Every caption colour row reads a word, never a hex code: a value on its own
/// list reads that name, and anything else reads the nearest name on the list
/// with how solid it is.
struct CaptionColourNamesTests {
    @Test func aColourOnTheListReadsItsName() {
        #expect(CaptionColourNames.name(of: "#000000B3", among: CaptionColourNames.plates) == "Darker")
        #expect(CaptionColourNames.name(of: "#ffd76a", among: CaptionColourNames.inks) == "Yellow")
        #expect(CaptionColourNames.name(of: nil, among: CaptionColourNames.plates) == "None")
        #expect(CaptionColourNames.name(of: nil, among: CaptionColourNames.bright, none: "Text colour")
                == "Text colour")
    }

    @Test func aColourOffTheListReadsTheNearestNameNeverAHexCode() {
        #expect(CaptionColourNames.name(of: "#FEFEFE", among: CaptionColourNames.inks) == "White")
        #expect(CaptionColourNames.name(of: "#00000040", among: CaptionColourNames.inks) == "Black 25%")
        #expect(CaptionColourNames.name(of: "#FF4FD880", among: CaptionColourNames.bright) == "Pink 50%")
        #expect(CaptionColourNames.name(of: "not a colour", among: CaptionColourNames.inks) == "Custom")
    }

    /// The named styles only ever wear colours their own rows can name, so
    /// picking Lower third or Neon reads words in every row.
    @Test func everyNamedStyleWearsColoursFromItsOwnLists() {
        func onList(_ hex: String?, _ list: [CaptionColourNames.Choice]) -> Bool {
            guard let hex else { return true }
            return list.contains { $0.hex?.uppercased() == hex.uppercased() }
        }
        for preset in CaptionLook.Preset.allCases {
            let look = CaptionLook.preset(preset)
            #expect(onList(look.colorHex, CaptionColourNames.inks), "\(preset) colour")
            #expect(onList(look.backgroundHex, CaptionColourNames.plates), "\(preset) background")
            #expect(onList(look.glowHex, CaptionColourNames.bright), "\(preset) glow")
            #expect(onList(look.strokeHex, CaptionColourNames.edges), "\(preset) stroke")
            #expect(onList(look.word.colorHex, CaptionColourNames.bright), "\(preset) word colour")
            #expect(onList(look.word.pillHex, CaptionColourNames.bright), "\(preset) word pill")
            #expect(onList(look.word.glowHex, CaptionColourNames.bright), "\(preset) word glow")
            #expect(onList(look.word.strokeHex, CaptionColourNames.edges), "\(preset) word stroke")
        }
    }

    @Test func noTwoChoicesOnAListShareAName() {
        for list in [CaptionColourNames.inks, CaptionColourNames.plates,
                     CaptionColourNames.bright, CaptionColourNames.edges] {
            #expect(Set(list.map(\.name)).count == list.count)
        }
    }
}
