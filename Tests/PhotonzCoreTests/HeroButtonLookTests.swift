import Foundation
import PhotonzCore
import Testing

/// The hero button is Ask's own: a spectrum pill that no state may take the
/// spectrum away from (`docs/design/mocks/shared/components/button.css`,
/// `.btn.hero`). These pin the states and the one sheen a hover sweeps.
@Suite("The hero button's look")
struct HeroButtonLookTests {

    private func look(hovering: Bool = false, pressed: Bool = false, open: Bool = false,
                      enabled: Bool = true) -> HeroButtonLook {
        HeroButtonLook(enabled: enabled, hovering: hovering, pressed: pressed, open: open)
    }

    @Test("At rest the narrow spectrum shows, with the gloss and the resting bloom")
    func rest() {
        let rest = look()
        #expect(rest.pose == .rest)
        #expect(!rest.spectrumOpen)
        #expect(rest.glow == .resting)
        #expect(rest.gloss == 0.40)
        #expect(rest.tuck == 0)
    }

    @Test("Hover opens the spectrum, lights the gloss and grows the bloom")
    func hovered() {
        let hovered = look(hovering: true)
        #expect(hovered.pose == .hovered)
        #expect(hovered.spectrumOpen)
        #expect(hovered.glow == .lifted)
        #expect(hovered.gloss == 0.58)
        #expect(hovered.glow.strength > HeroGlow.resting.strength)
        #expect(hovered.glow.blur > HeroGlow.resting.blur)
    }

    @Test("Pressed keeps the spectrum open and tucks the bloom back under")
    func pressed() {
        for hovering in [false, true] {
            let pressed = look(hovering: hovering, pressed: true)
            #expect(pressed.pose == .pressed)
            #expect(pressed.spectrumOpen)
            #expect(pressed.glow == .tucked)
            #expect(pressed.tuck == 0.34)
            #expect(pressed.glow.blur < HeroGlow.resting.blur)
        }
    }

    @Test("Open reads as held down, and a pointer on it lifts the bloom one rung")
    func open() {
        let open = look(open: true)
        #expect(open.pose == .open)
        #expect(open.spectrumOpen)
        #expect(open.glow == .tucked)
        #expect(open.tuck == 0.34)
        let pointedAt = look(hovering: true, open: true)
        #expect(pointedAt.pose == .openHovered)
        #expect(pointedAt.spectrumOpen)
        #expect(pointedAt.glow == .resting)
        #expect(pointedAt.tuck == 0.26)
    }

    @Test("No state ever closes the spectrum to nothing: every pose keeps a fill and a bloom")
    func neverGoesDark() {
        for pose in HeroButtonLook.Pose.allCases {
            let shown = HeroButtonLook(pose: pose)
            #expect(shown.glow.strength > 0.5)
        }
    }

    @Test("A disabled hero rests whatever the pointer does")
    func disabled() {
        for hovering in [false, true] {
            for pressed in [false, true] {
                #expect(look(hovering: hovering, pressed: pressed, enabled: false).pose == .rest)
            }
        }
    }

    @Test("The bloom's three rungs are the design's: 4/12/-4 at 55%, 6/16/-6 at 60%, 8/22/-6 at 66%")
    func rungs() {
        #expect(HeroGlow.tucked == HeroGlow(drop: 4, blur: 12, spread: -4, strength: 0.55))
        #expect(HeroGlow.resting == HeroGlow(drop: 6, blur: 16, spread: -6, strength: 0.60))
        #expect(HeroGlow.lifted == HeroGlow(drop: 8, blur: 22, spread: -6, strength: 0.66))
    }
}

@Suite("The hero button's sheen")
struct HeroSheenTests {

    @Test("Parked off the leading edge and unseen before the sweep begins")
    func parked() {
        let start = HeroSheen.frame(at: 0)
        #expect(start.opacity == 0)
        #expect(abs(start.lead - -0.40) < 1e-9)
        // The band's trailing edge sits just inside the button: it is unseen
        // only because it is transparent, as in the design.
        #expect(start.lead + HeroSheen.bandWidth > 0)
    }

    @Test("Fully lit by 22% of the way, then fades as it leaves")
    func lightsThenFades() {
        let lit = HeroSheen.frame(at: 0.22 * HeroSheen.duration)
        #expect(abs(lit.opacity - 1) < 1e-9)
        let late = HeroSheen.frame(at: 0.8 * HeroSheen.duration)
        #expect(late.opacity < 1 && late.opacity > 0)
    }

    @Test("Sweeps left to right, past the trailing edge, and never comes back")
    func sweepsOnce() {
        var previous = -Double.infinity
        for step in 0...66 {
            let lead = HeroSheen.frame(at: Double(step) / 100).lead
            #expect(lead >= previous - 1e-9)
            previous = lead
        }
        let end = HeroSheen.frame(at: HeroSheen.duration)
        #expect(end.opacity == 0)
        // 260% of a 55% band from -40%: the band ends wholly past the button.
        #expect(abs(end.lead - (-0.40 + 2.6 * 0.55)) < 1e-9)
        #expect(end.lead > 1)
        let after = HeroSheen.frame(at: HeroSheen.duration * 3)
        #expect(after == end)
    }

    @Test("Moves on the design's curve: most of the travel early, a soft landing")
    func eased() {
        let half = HeroSheen.frame(at: HeroSheen.duration / 2)
        let travelled = (half.lead - -0.40) / (2.6 * 0.55)
        // cubic-bezier(.32,.72,.3,1) at half time is well past half way.
        #expect(travelled > 0.75)
        #expect(HeroSheen.duration == 0.66)
    }
}

@Suite("The hero button's spectrum")
struct HeroSpectrumTests {

    private func close(_ a: RGBA, _ b: RGBA, within: Double = 0.002) -> Bool {
        abs(a.r - b.r) < within && abs(a.g - b.g) < within && abs(a.b - b.b) < within
    }

    @Test("The three stops are the design's: #6E8BFF, #c56cff, #ff7ab8")
    func stops() {
        #expect(close(HeroSpectrum.blue, RGBA(r: 0x6E / 255.0, g: 0x8B / 255.0, b: 1)))
        #expect(close(HeroSpectrum.violet, RGBA(r: 0xC5 / 255.0, g: 0x6C / 255.0, b: 1)))
        #expect(close(HeroSpectrum.pink, RGBA(r: 1, g: 0x7A / 255.0, b: 0xB8 / 255.0)))
    }

    @Test("At rest it runs blue to violet end to end")
    func resting() {
        #expect(close(HeroSpectrum.resting.first, HeroSpectrum.blue))
        #expect(close(HeroSpectrum.resting.last, HeroSpectrum.violet))
        #expect(HeroSpectrum.resting.violetAt == nil)
    }

    @Test("Open, it is the design's -12% / 46% / 112% spectrum cut to the button")
    func open() {
        let open = HeroSpectrum.open
        // -12% blue to 46% violet: the leading edge is 12/58 of the way.
        let lead = HeroSpectrum.mix(HeroSpectrum.blue, HeroSpectrum.violet, 0.12 / 0.58)
        // 46% violet to 112% pink: the trailing edge is 54/66 of the way.
        let trail = HeroSpectrum.mix(HeroSpectrum.violet, HeroSpectrum.pink, 0.54 / 0.66)
        #expect(close(open.first, lead))
        #expect(close(open.last, trail))
        #expect(open.violetAt == 0.46)
        // Never grey: every end keeps more blue or red than green.
        for color in [open.first, open.last] {
            #expect(max(color.r, color.b) - color.g > 0.25)
        }
    }

    @Test("A 120 degree line on a wide pill runs from the top left to the bottom right through the middle")
    func gradientLine() {
        let line = HeroSpectrum.line(width: 80, height: 24, degrees: 120)
        // Through the middle.
        #expect(abs((line.start.x + line.end.x) / 2 - 0.5) < 1e-9)
        #expect(abs((line.start.y + line.end.y) / 2 - 0.5) < 1e-9)
        // Left to right, top to bottom.
        #expect(line.start.x < 0 + 0.5 && line.end.x > 0.5)
        #expect(line.start.y < 0.5 && line.end.y > 0.5)
        // In points the direction is the angle's: 30 degrees below level.
        let dx = (line.end.x - line.start.x) * 80, dy = (line.end.y - line.start.y) * 24
        #expect(abs(atan2(dy, dx) * 180 / .pi - 30) < 1e-6)
        // The corners sit on the ends of the line, as in CSS: the top left
        // corner projects onto the start.
        let length = (80 * sin(120 * Double.pi / 180)) + (24 * abs(cos(120 * Double.pi / 180)))
        #expect(abs(hypot(dx, dy) - length) < 1e-6)
    }
}
