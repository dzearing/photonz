import Testing
@testable import PhotonzCore

/// The measuring half of the app's legibility check (`LegibilitySheet`, in the
/// app): given a control drawn three ways (as shipped, with its words left out,
/// and with only its words, as a coverage mask), say how readable every word is
/// against what is actually drawn behind it.
///
/// The user, 2026-09-30: "I do not want white on white or black on black cases
/// EVER." A white word on white is invisible, so it cannot be found by looking
/// for it in the picture; the mask says where the words are whatever colour they
/// were drawn in, which is the whole point of the third drawing.
@Suite("Every word is read against what is drawn behind it")
struct InkReadingTests {
    static let white = RGBA(r: 1, g: 1, b: 1)
    static let black = RGBA(r: 0, g: 0, b: 0)
    static let blue = RGBA(r: 0, g: 0.478, b: 1)
    static let grey = RGBA(r: 0.88, g: 0.89, b: 0.92)

    /// A picture `width` by `height` filled with `ground`.
    static func picture(_ width: Int, _ height: Int, _ ground: RGBA) -> InkPicture {
        InkPicture(width: width, height: height, pixels: Array(repeating: ground, count: width * height))
    }

    /// Paints a solid block of "word" into the shown picture and the mask.
    static func word(x: Int, y: Int, width: Int, height: Int, ink: RGBA,
                     shown: inout InkPicture, mask: inout [Double]) {
        for row in y..<(y + height) {
            for column in x..<(x + width) {
                shown.pixels[row * shown.width + column] = ink
                mask[row * shown.width + column] = 1
            }
        }
    }

    @Test("Black words on white read at 21:1 and pass")
    func blackOnWhite() {
        let bare = Self.picture(40, 20, Self.white)
        var shown = bare
        var mask = [Double](repeating: 0, count: 40 * 20)
        Self.word(x: 5, y: 5, width: 12, height: 8, ink: Self.black, shown: &shown, mask: &mask)
        let readings = InkReading.read(shown: shown, bare: bare, mask: mask)
        #expect(readings.count == 1)
        #expect(abs((readings.first?.contrast ?? 0) - 21) < 0.01)
        #expect(readings.allSatisfy { Legibility.isLegible($0) })
    }

    @Test("A white word on white is still found, and fails at 1:1")
    func whiteOnWhiteIsFound() {
        let bare = Self.picture(40, 20, Self.white)
        var shown = bare
        var mask = [Double](repeating: 0, count: 40 * 20)
        Self.word(x: 5, y: 5, width: 12, height: 8, ink: Self.white, shown: &shown, mask: &mask)
        let readings = InkReading.read(shown: shown, bare: bare, mask: mask)
        #expect(readings.count == 1)
        #expect(abs((readings.first?.contrast ?? 0) - 1) < 0.001)
        #expect(readings.first.map { !Legibility.isLegible($0) } == true)
    }

    @Test("Black on black fails too")
    func blackOnBlack() {
        let bare = Self.picture(40, 20, Self.black)
        var shown = bare
        var mask = [Double](repeating: 0, count: 40 * 20)
        Self.word(x: 5, y: 5, width: 12, height: 8, ink: RGBA(r: 0.1, g: 0.1, b: 0.1),
                  shown: &shown, mask: &mask)
        let readings = InkReading.read(shown: shown, bare: bare, mask: mask)
        #expect(readings.count == 1)
        #expect(readings.first.map { !Legibility.isLegible($0) } == true)
    }

    @Test("Two words apart are read apart, and each knows where it is")
    func twoWords() {
        let bare = Self.picture(80, 20, Self.white)
        var shown = bare
        var mask = [Double](repeating: 0, count: 80 * 20)
        Self.word(x: 4, y: 4, width: 10, height: 8, ink: Self.black, shown: &shown, mask: &mask)
        Self.word(x: 50, y: 4, width: 10, height: 8, ink: Self.white, shown: &shown, mask: &mask)
        let readings = InkReading.read(shown: shown, bare: bare, mask: mask).sorted { $0.minX < $1.minX }
        #expect(readings.count == 2)
        #expect(readings.first?.minX == 4)
        #expect(readings.last?.minX == 50)
        #expect(readings.first.map { Legibility.isLegible($0) } == true)
        #expect(readings.last.map { !Legibility.isLegible($0) } == true)
    }

    @Test("Letters a pixel or two apart are one word, not one reading per letter")
    func lettersJoin() {
        let bare = Self.picture(60, 20, Self.white)
        var shown = bare
        var mask = [Double](repeating: 0, count: 60 * 20)
        for letter in 0..<4 {
            Self.word(x: 4 + letter * 6, y: 4, width: 4, height: 8, ink: Self.black, shown: &shown, mask: &mask)
        }
        #expect(InkReading.read(shown: shown, bare: bare, mask: mask).count == 1)
    }

    @Test("A word half over a blue chip and half over a grey rail is read twice, once on each")
    func wordAcrossTwoGrounds() {
        var bare = Self.picture(60, 20, Self.grey)
        for row in 0..<20 { for column in 30..<60 { bare.pixels[row * 60 + column] = Self.blue } }
        var shown = bare
        var mask = [Double](repeating: 0, count: 60 * 20)
        // White ink all the way across: fine on the chip, unreadable on the rail.
        Self.word(x: 10, y: 5, width: 40, height: 8, ink: Self.white, shown: &shown, mask: &mask)
        let readings = InkReading.read(shown: shown, bare: bare, mask: mask)
        #expect(readings.count == 2)
        let onRail = readings.first { $0.behind == Self.grey }
        let onChip = readings.first { $0.behind == Self.blue }
        #expect(onRail.map { !Legibility.isLegible($0) } == true)
        #expect(onChip.map { Legibility.isLegible($0) } == true)
    }

    @Test("A word's soft edges are not what it is judged by: its cores are")
    func edgesIgnored() {
        let bare = Self.picture(40, 20, Self.white)
        var shown = bare
        var mask = [Double](repeating: 0, count: 40 * 20)
        Self.word(x: 10, y: 6, width: 10, height: 6, ink: Self.black, shown: &shown, mask: &mask)
        // A ring of faint anti-aliasing round it, the ink barely there.
        for column in 9...20 {
            for row in [5, 12] {
                shown.pixels[row * 40 + column] = RGBA(r: 0.95, g: 0.95, b: 0.95)
                mask[row * 40 + column] = 0.1
            }
        }
        let readings = InkReading.read(shown: shown, bare: bare, mask: mask)
        #expect(readings.count == 1)
        #expect((readings.first?.contrast ?? 0) > 20)
    }

    @Test("A specimen with no words gives no readings")
    func noWords() {
        let bare = Self.picture(20, 20, Self.white)
        #expect(InkReading.read(shown: bare, bare: bare, mask: [Double](repeating: 0, count: 400)).isEmpty)
    }

    static func hex(_ value: String) -> RGBA { RGBA(hex: value) ?? RGBA(r: 1, g: 0, b: 1) }

    @Test("3:1 or better is legible whatever the colours: the system's white on its blue passes")
    func theFloor() {
        #expect(Legibility.floor == 3)
        #expect(Legibility.isLegible(ink: Self.white, on: Self.blue))
        #expect(Legibility.isLegible(ink: Self.hex("5C6371"), on: Self.hex("FBFCFE")))
    }

    @Test("White on white, black on black and grey on grey are never legible")
    func sameOnSame() {
        #expect(!Legibility.isLegible(ink: Self.white, on: Self.white))
        #expect(!Legibility.isLegible(ink: Self.hex("1A1A1A"), on: Self.black))
        #expect(!Legibility.isLegible(ink: Self.hex("999999"), on: Self.hex("BFBFBF")))
        // Pale grey words on a pale grey plate, the kind a hover plate makes.
        #expect(!Legibility.isLegible(ink: Self.hex("8B92A1"), on: Self.hex("E8E8E9")))
    }

    @Test("Below 3:1 a word still reads when it is plainly another colour: white on a saturated cyan")
    func colourCarriesIt() {
        #expect(Legibility.isLegible(ink: Self.white, on: Self.hex("34B7EC")))
        // Red words on a light grey plate read by their colour.
        #expect(Legibility.isLegible(ink: Self.hex("FF383C"), on: Self.hex("E0E0E0")))
        #expect(Legibility.sameFamily(Self.white, Self.hex("34B7EC")) == false)
    }

    @Test("Below 3:1 the same colour family is not legible: lavender on pale lavender, red on a pink wash")
    func sameFamilyIsNot() {
        #expect(Legibility.sameFamily(Self.hex("B98CFF"), Self.hex("EEE6FE")))
        #expect(!Legibility.isLegible(ink: Self.hex("B98CFF"), on: Self.hex("EEE6FE")))
        #expect(!Legibility.isLegible(ink: Self.hex("FF383C"), on: Self.hex("FCD5D6")))
    }

    @Test("Colour never rescues a word below 2:1")
    func colourHasALimit() {
        #expect(!Legibility.isLegible(ink: Self.white, on: Self.hex("7FE0FF")))
    }

    @Test("A word that cannot act may read as quietly as the system's own disabled label, and never vanish")
    func disabled() {
        // The system's disabled label (black at 25%) on a light window: about 1.8:1.
        let window = Self.hex("ECECEC")
        let systemDisabled = SegmentInk.over(RGBA(r: 0, g: 0, b: 0, a: 0.25), window)
        #expect(Legibility.isLegible(ink: systemDisabled, on: window, disabled: true))
        #expect(!Legibility.isLegible(ink: Self.hex("E4E4E4"), on: window, disabled: true))
        #expect(!Legibility.isLegible(ink: systemDisabled, on: window))
    }
}
