import Testing
@testable import PhotonzCore

@Suite("The steady name a walk can call a panel row by")
struct PlaytestSteadyNameTests {

    @Test("A name written with the mark in front of it is asking for a steady name")
    func markMeansSteady() {
        #expect(PlaytestSteadyName.isSteady("@border"))
        #expect(!PlaytestSteadyName.isSteady("Border"))
        // The mark on its own names nothing, so it is a word like any other
        // rather than a steady name that matches everything.
        #expect(!PlaytestSteadyName.isSteady("@"))
        #expect(!PlaytestSteadyName.isSteady(""))
    }

    @Test("The mark goes in front when a steady name is written out for a walk to copy")
    func writtenOut() {
        #expect(PlaytestSteadyName.written("border.2") == "@border.2")
    }

    @Test("A steady name reaches the row that carries it")
    func matchesTheRow() {
        #expect(PlaytestSteadyName.matches("@border", steady: ["border", "border.1"]))
        #expect(PlaytestSteadyName.matches("@BORDER.1", steady: ["border", "border.1"]))
        #expect(!PlaytestSteadyName.matches("@shadow", steady: ["border", "border.1"]))
    }

    @Test("A plain word never reaches a steady name, and a steady name never reaches a word")
    func theTwoNamesStayApart() {
        // Otherwise a row whose WORD is Border and a different row whose steady
        // name is border would both answer to the same step, and which one a
        // walk got would be whichever the panel built first.
        #expect(!PlaytestSteadyName.matches("border", steady: ["border"]))
        #expect(!PlaytestSteadyName.matches("Border", steady: ["border"]))
        #expect(!PlaytestSteadyName.matches("@border", steady: []))
    }

    @Test("The only one of its kind answers to the bare kind and to its number")
    func loneEntry() {
        #expect(PlaytestSteadyName.entry(kind: "border", ordinal: 1) == ["border", "border.1"])
    }

    @Test("The second of a kind answers to its number only, so the bare name always means the first")
    func secondEntry() {
        #expect(PlaytestSteadyName.entry(kind: "shadow", ordinal: 2) == ["shadow.2"])
        #expect(!PlaytestSteadyName.matches("@shadow", steady: PlaytestSteadyName.entry(kind: "shadow", ordinal: 2)))
        #expect(PlaytestSteadyName.matches("@shadow", steady: PlaytestSteadyName.entry(kind: "shadow", ordinal: 1)))
    }

    @Test("An entry's steady name does not move when the words on it change")
    func wordsDoNotReachIt() {
        // The row that read Outline and now reads Border is the same border
        // underneath, so the same steady name reaches it before and after.
        let before = PlaytestSteadyName.entry(kind: EffectKind.border.rawValue, ordinal: 1)
        #expect(before.contains("border"))
        #expect(!before.contains(EffectKind.border.title))
    }
}

@Suite("The steady names the panel's two model-driven lists hand a walk")
struct PanelRowSteadyNameTests {

    @Test("An effect row is named by its kind, not by the word on it")
    func effectRow() {
        let row = LayerEffectRow(kind: .border, index: 0, shadowIndex: nil, ordinal: 1,
                                 countOfKind: 1, switchIDs: [], onCount: 0, selectionCount: 1)
        #expect(row.steadyNames == ["border", "border.1"])
        #expect(PlaytestSteadyName.matches("@border", steady: row.steadyNames))
    }

    @Test("Two borders are told apart by number, and the bare name means the top one")
    func twoOfAKind() {
        let first = LayerEffectRow(kind: .border, index: 0, shadowIndex: nil, ordinal: 1,
                                   countOfKind: 2, switchIDs: [], onCount: 0, selectionCount: 1)
        let second = LayerEffectRow(kind: .border, index: 1, shadowIndex: nil, ordinal: 2,
                                    countOfKind: 2, switchIDs: [], onCount: 0, selectionCount: 1)
        // The words on them have moved -- one border became "Border 1" the
        // moment the second arrived -- and the steady name of the first has not.
        #expect(first.title == "Border 1")
        #expect(PlaytestSteadyName.matches("@border", steady: first.steadyNames))
        #expect(!PlaytestSteadyName.matches("@border", steady: second.steadyNames))
        #expect(PlaytestSteadyName.matches("@border.2", steady: second.steadyNames))
    }

    @Test("An effect's steady name does not move when it is dragged up the list")
    func reorderingDoesNotMoveIt() {
        // `index` is where the entry sits among ALL the effects, so it changes
        // the moment a shadow is dropped above a border. The steady name counts
        // only the borders, which is what a walk meant.
        let low = LayerEffectRow(kind: .border, index: 3, shadowIndex: nil, ordinal: 1,
                                 countOfKind: 1, switchIDs: [], onCount: 0, selectionCount: 1)
        let high = LayerEffectRow(kind: .border, index: 0, shadowIndex: nil, ordinal: 1,
                                  countOfKind: 1, switchIDs: [], onCount: 0, selectionCount: 1)
        #expect(low.steadyNames == high.steadyNames)
    }

    @Test("An Appearance row is named by its part, not by the word on it")
    func appearanceRow() {
        let fill = LayerPartRow(part: .fill, colors: [], title: LayerPart.fill.title,
                                switchIDs: [], onCount: 0, widthIDs: [], selectionCount: 1)
        // One name, not two: nothing in Appearance arrives twice, so there is
        // no list for a number to count in.
        #expect(fill.steadyNames == ["fill"])
        #expect(PlaytestSteadyName.matches("@fill", steady: fill.steadyNames))
        #expect(!PlaytestSteadyName.matches("@fill.1", steady: fill.steadyNames))
    }

    @Test("The row whose word changes with the selection keeps one steady name")
    func aRowThatRenamesItself() {
        // This row reads "Line" when everything picked is a line and "Color"
        // otherwise, so its word is not something a walk can rely on at all.
        let asLine = LayerPartRow(part: nil, colors: [PartColor(slot: .stroke, layerIDs: [])],
                                  title: "Line", switchIDs: [], onCount: 0,
                                  widthIDs: [], selectionCount: 1)
        let asColor = LayerPartRow(part: nil, colors: [PartColor(slot: .stroke, layerIDs: [])],
                                   title: ColorSlot.stroke.title, switchIDs: [], onCount: 0,
                                   widthIDs: [], selectionCount: 1)
        #expect(asLine.title != asColor.title)
        #expect(asLine.steadyNames == asColor.steadyNames)
        #expect(PlaytestSteadyName.matches("@color.stroke", steady: asLine.steadyNames))
    }
}

@Suite("Adding an effect by steady name")
struct AddableEffectSteadyNameTests {

    @Test("The plus row that makes a border answers to the same name the row will")
    func plusRow() {
        #expect(AddableEffect.steadyNamed("@border") == .border)
        #expect(AddableEffect.steadyNamed("@blur") == .blur)
        #expect(AddableEffect.steadyNamed("@shadow") == .shadow)
        #expect(AddableEffect.steadyNamed("@glow") == .glow)
    }

    @Test("A plain word is not a steady name, so it never resolves here")
    func plainWords() {
        #expect(AddableEffect.steadyNamed("Border") == nil)
        #expect(AddableEffect.steadyNamed("border") == nil)
    }

    @Test("There is no second border to add, so the numbered name means nothing to the plus")
    func noSecondToAdd() {
        #expect(AddableEffect.steadyNamed("@border.2") == nil)
        #expect(AddableEffect.steadyNamed("@nothing") == nil)
    }
}
