import PhotonzCore
import Testing

/// A button that cannot be pressed sits still under the pointer: no hover
/// fill, no pressed fill, no shrink. An enabled one answers exactly as before.
@Suite("A button's look under the pointer")
struct ButtonPointerLookTests {

    @Test("A disabled button rests whatever the pointer does")
    func disabledRests() {
        for hovering in [false, true] {
            for pressed in [false, true] {
                for hoverResponse in [false, true] {
                    let look = ButtonPointerLook(enabled: false, hovering: hovering, pressed: pressed,
                                                 answersHover: hoverResponse)
                    #expect(look == .rest)
                    #expect(!look.isLit)
                }
            }
        }
    }

    @Test("An enabled button lights under the pointer and lights harder when pressed")
    func enabledAnswers() {
        #expect(ButtonPointerLook(enabled: true, hovering: false, pressed: false) == .rest)
        #expect(ButtonPointerLook(enabled: true, hovering: true, pressed: false) == .hovered)
        #expect(ButtonPointerLook(enabled: true, hovering: false, pressed: true) == .pressed)
        #expect(ButtonPointerLook(enabled: true, hovering: true, pressed: true) == .pressed)
        #expect(ButtonPointerLook.hovered.isLit)
        #expect(ButtonPointerLook.pressed.isLit)
        #expect(ButtonPointerLook.pressed.isPressed)
        #expect(!ButtonPointerLook.hovered.isPressed)
    }

    @Test("A button told not to answer hover still shows a press")
    func noHoverResponseKeepsPress() {
        #expect(ButtonPointerLook(enabled: true, hovering: true, pressed: false, answersHover: false) == .rest)
        #expect(ButtonPointerLook(enabled: true, hovering: true, pressed: true, answersHover: false) == .pressed)
    }
}
