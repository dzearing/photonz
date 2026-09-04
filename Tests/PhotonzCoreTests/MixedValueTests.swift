import Testing
@testable import PhotonzCore

/// One word for the whole app.
///
/// Every kind of control in the inspector has to answer the same question —
/// the picked layers do not agree, so what goes where the value would be — and
/// before this each type answered it with a string literal of its own. Nothing
/// stopped one of them drifting to "Multiple" or "—", and a panel that says the
/// same thing three ways reads as three panels.
struct MixedValueTests {

    @Test func theWordIsMixed() {
        #expect(MixedValue.text == "Mixed")
    }

    /// Every selection type that can answer Mixed answers with THE word, not a
    /// copy of it that happens to match today.
    @Test func everySelectionTypeSaysTheSameWord() {
        #expect(LayerStyleSelection.mixedText == MixedValue.text)
        #expect(LayerGeometrySelection.mixedText == MixedValue.text)
        #expect(ColorStyleSelection.mixedText == MixedValue.text)
    }
}
