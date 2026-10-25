import PhotonzCore
import SwiftUI

/// The design language's fifth button, `.btn.hero`
/// (`docs/design/mocks/shared/components/button.css`): the one control on a
/// surface that opens the agent, so the only one that does not wear the
/// accent. A capsule filled with a blue to violet spectrum, white words, a
/// gloss along the top and a violet bloom underneath. Hover opens a wider
/// spectrum toward pink, lights the gloss, grows the bloom and sweeps one
/// sheen across; pressed keeps the spectrum open and tucks the bloom in.
///
/// Once per surface, and only for Ask: a second hero makes both ordinary.
///
/// No state takes the spectrum away. The web version once lost it on hover
/// (a generic hover repainted the pill as grey glass), and hover read as "it
/// turned off"; here every state is a layer over the same fill, faded in or
/// out, so nothing ever repaints the fill itself. It is opaque, so it sits on
/// no glass: there is nothing behind an opaque fill to blur.
struct HeroButtonStyle: ButtonStyle {
    /// Whether what the button opens is up: drawn held down, spectrum open.
    var isOpen: Bool = false
    var height: CGFloat = 24
    /// Room either side of the words.
    var padding: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        HeroButtonBody(configuration: configuration, style: self)
    }

    private struct HeroButtonBody: View {
        let configuration: Configuration
        let style: HeroButtonStyle
        @State private var hovering = false
        /// One more each time the pointer arrives: each new value sweeps the
        /// sheen across once.
        @State private var sweeps = 0
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        @Environment(\.shownPointer) private var shown
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let look = HeroButtonLook(enabled: isEnabled,
                                      hovering: hovering || shown == .hovered,
                                      pressed: configuration.isPressed || shown == .pressed,
                                      open: style.isOpen)
            HeroButtonFace(label: configuration.label, look: look, height: style.height,
                           padding: style.padding, focused: isFocused, sweeps: sweeps)
                .opacity(isEnabled ? 1 : 0.55)
                .playtestHover("hero") { inside in
                    hovering = inside
                    if HeroSheen.sweeps(arriving: inside, enabled: isEnabled, reduceMotion: reduceMotion) {
                        sweeps += 1
                    }
                }
                .animation(.easeOut(duration: 0.2), value: look)
        }
    }
}

/// How the hero button is drawn in one pose. The style draws it live; the
/// legibility check and the audit reel draw it at a fixed pose and a fixed
/// moment of the sheen, so the pictures are of the shipped drawing.
struct HeroButtonFace<Label: View>: View {
    let label: Label
    let look: HeroButtonLook
    var height: CGFloat = 24
    var padding: CGFloat = 12
    var focused = false
    /// Live: each new value sweeps the sheen once.
    var sweeps = 0
    /// For a picture: the sheen held at one moment instead of swept.
    var shownSheen: HeroSheen.Frame? = nil

    var body: some View {
        label
            .foregroundStyle(.white)
            .padding(.horizontal, padding)
            .frame(height: height)
            .background { surface }
            .overlay { if focused { ring } }
            .contentShape(.capsule)
    }

    private var surface: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                bloom(size)
                Capsule().fill(gradient(HeroSpectrum.resting, size))
                Capsule().fill(gradient(HeroSpectrum.open, size))
                    .opacity(look.spectrumOpen ? 1 : 0)
                sheen(width: size.width)
                    .clipShape(.capsule)
                gloss
                tuck
            }
        }
    }

    /// The violet bloom: a narrower capsule below the button, blurred. The
    /// design's blur is a CSS length, twice the Gaussian's deviation.
    private func bloom(_ size: CGSize) -> some View {
        let glow = look.glow
        return Capsule()
            .fill(Color(HeroSpectrum.violet).opacity(glow.strength))
            .padding(.horizontal, -glow.spread)
            .padding(.vertical, min(-glow.spread, size.height / 2 - 1))
            .offset(y: glow.drop)
            .blur(radius: glow.blur / 2)
            .allowsHitTesting(false)
    }

    /// A CSS 120 degree gradient on this size, so the angle is the design's in
    /// points, not a diagonal of the unit square.
    private func gradient(_ spectrum: HeroSpectrum, _ size: CGSize) -> LinearGradient {
        let line = HeroSpectrum.line(width: size.width, height: size.height, degrees: 120)
        var stops: [Gradient.Stop] = [.init(color: Color(spectrum.first), location: 0)]
        if let violetAt = spectrum.violetAt {
            stops.append(.init(color: Color(HeroSpectrum.violet), location: violetAt))
        }
        stops.append(.init(color: Color(spectrum.last), location: 1))
        return LinearGradient(stops: stops,
                              startPoint: UnitPoint(x: line.start.x, y: line.start.y),
                              endPoint: UnitPoint(x: line.end.x, y: line.end.y))
    }

    /// A soft white band a little over half the button wide, swept once from
    /// off the leading edge to past the trailing one. Only opacity and offset
    /// change while it moves, so nothing is laid out again.
    @ViewBuilder private func sheen(width: CGFloat) -> some View {
        let band = LinearGradient(stops: [.init(color: .white.opacity(0), location: 0),
                                          .init(color: .white.opacity(0.5), location: 0.5),
                                          .init(color: .white.opacity(0), location: 1)],
                                  startPoint: UnitPoint(x: 0, y: 0.41), endPoint: UnitPoint(x: 1, y: 0.59))
        let bandWidth = width * HeroSheen.bandWidth
        if let shownSheen {
            Rectangle().fill(band)
                .frame(width: bandWidth)
                .offset(x: shownSheen.lead * width)
                .opacity(shownSheen.opacity)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Rectangle().fill(band)
                .frame(width: bandWidth)
                .keyframeAnimator(initialValue: HeroSheen.duration, trigger: sweeps) { band, elapsed in
                    let frame = HeroSheen.frame(at: elapsed)
                    band.offset(x: frame.lead * width).opacity(frame.opacity)
                } keyframes: { _ in
                    // A new trigger plays the track from wherever the last
                    // one left the value, which is the end of a sweep, so
                    // every sweep starts by going back to its beginning: without
                    // this only the first hover swept (the user, 2026-10-24).
                    // Parked at the end until then, so nothing shows at rest.
                    KeyframeTrack {
                        MoveKeyframe(0.0)
                        LinearKeyframe(HeroSheen.duration, duration: HeroSheen.duration)
                    }
                }
                // The hover's own colour change animates the face; the band
                // moves only by its keyframes, never eased back from where
                // the last sweep left it.
                .transaction { $0.animation = nil }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The white line along the inside of the top edge: the capsule less
    /// itself moved down a point (`inset 0 1px 0`).
    private var gloss: some View {
        Capsule().fill(.white.opacity(look.gloss))
            .mask {
                Capsule()
                    .overlay(Capsule().offset(y: 1).blendMode(.destinationOut))
                    .compositingGroup()
            }
            .allowsHitTesting(false)
    }

    /// Held down: a deep violet shadow pressed in along the top
    /// (`inset 0 1px 3px rgba(38,16,72,.34)`).
    private var tuck: some View {
        // Everything outside the pill moved down a point, softened, and seen
        // only through the pill: dark along the top, nothing at the bottom.
        Rectangle()
            .fill(Color(.sRGB, red: 38 / 255, green: 16 / 255, blue: 72 / 255))
            .padding(-8)
            .mask {
                Rectangle().padding(-8)
                    .overlay(Capsule().offset(y: 1).blendMode(.destinationOut))
                    .compositingGroup()
            }
            .blur(radius: 1.5)
            .clipShape(.capsule)
            .opacity(look.tuck)
            .allowsHitTesting(false)
    }

    /// Keyboard focus: a violet ring round the pill (`--ring` in the hero's
    /// own colour).
    private var ring: some View {
        Capsule()
            .strokeBorder(Color(HeroSpectrum.violet).opacity(0.38), lineWidth: 3)
            .padding(-3)
            .allowsHitTesting(false)
    }
}

extension Color {
    init(_ rgba: RGBA) {
        self.init(.sRGB, red: rgba.r, green: rgba.g, blue: rgba.b, opacity: rgba.a)
    }
}
