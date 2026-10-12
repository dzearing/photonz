import CoreGraphics
import CoreImage
import Foundation
import PhotonzCore

// The moving looks a title's background wears (task
// `title-backgrounds-that-are-alive-auroras-energy`, `LiveBackdrop.swift` in
// PhotonzCore): each one a small Metal program Core Image runs for every pixel
// of every frame, so nothing is a video file and nothing is baked. They are
// compiled once, the first time a look is drawn, from the source below.
//
// Every program works in the frame's own units (its height is one), so the
// same look at a thumbnail and at 4K is the same picture, and in light: the
// lights are added to the ground (or, over a light ground, laid on as tints),
// the brightest a frame may get is held under `LivePalette.limit` so the
// title's words read over every part of it, and only then is the colour put
// back on the sRGB curve, which `matchedToWorkingSpace` hands to whatever
// space the renderer mixes in.

/// Draws a `live` paint at a moment.
public enum LiveBackdropPainter {

    /// The compiled programs, by look, each compiled the first time it is
    /// drawn (about a third of a second, once per launch), and the looks this
    /// Mac could not compile, which then draw their ground flat.
    // Core Image kernels are immutable once made and Apple documents them as
    // safe to apply from any thread; the type is simply not marked Sendable,
    // so the cache is guarded by hand.
    nonisolated(unsafe) private static var compiled: [LiveLook: CIColorKernel] = [:]
    nonisolated(unsafe) private static var failed: Set<LiveLook> = []
    private static let lock = NSLock()

    static func kernel(_ look: LiveLook) -> CIColorKernel? {
        lock.lock()
        defer { lock.unlock() }
        if let made = compiled[look] { return made }
        guard !failed.contains(look) else { return nil }
        guard let made = try? CIKernel.kernels(withMetalString: source(look)),
              let colour = made.first(where: { $0.name == functionName(look) }) as? CIColorKernel
        else {
            failed.insert(look)
            return nil
        }
        compiled[look] = colour
        return colour
    }

    /// Compiles a look ahead of its first frame, off the main thread, so
    /// picking it never stalls a frame.
    public static func prepare(_ looks: [LiveLook] = LiveLook.allCases) {
        DispatchQueue.global(qos: .utility).async {
            for look in looks { _ = kernel(look) }
        }
    }

    /// Whether every look compiled, which is the question a test asks first.
    public static var isAvailable: Bool { LiveLook.allCases.allSatisfy { kernel($0) != nil } }

    static func functionName(_ look: LiveLook) -> String { "live_" + look.rawValue }

    /// How long into a look its still picture is taken, in seconds of its own
    /// clock: far enough that a sketch has drawn itself and bubbles have
    /// bloomed. What a swatch, a still frame and a held look show.
    public static func posterSeconds(_ look: LiveLook) -> Double {
        look == .sketch ? 9 : 2.5
    }

    /// The look across a box of `size` pixels, origin at nought, in Core
    /// Image's bottom-left space, `ms` into the clip (nil for its still
    /// picture). Nil for a paint that is not a live look.
    public static func image(_ paint: Paint, size: CGSize, atMS ms: Int?) -> CIImage? {
        guard paint.kind == .live, let look = paint.live, size.width >= 1, size.height >= 1 else { return nil }
        let palette = LivePalette(paint)
        guard let kernel = kernel(look.look) else {
            return CIImage(color: ciColour(palette.ground)).cropped(to: CGRect(origin: .zero, size: size))
        }
        let seconds = ms.map { look.seconds(atMS: $0) } ?? posterSeconds(look.look)
        // A soft look is worked out at half size and enlarged: nothing in a
        // glow changes across two pixels.
        let half = look.look.drawnAtHalfSize && min(size.width, size.height) >= 64
        let worked = half ? CGSize(width: (size.width / 2).rounded(.up), height: (size.height / 2).rounded(.up))
                          : CGSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
        let extent = CGRect(origin: .zero, size: worked)
        let lights = palette.lights.map(linear)
        let arguments: [Any] = [
            linear(palette.ground),
            lights[0], lights[1], lights[2],
            CIVector(x: CGFloat(seconds), y: CGFloat(look.strength / 100),
                     z: CGFloat(look.scale / 100), w: CGFloat(look.shape / 100)),
            CIVector(x: worked.width, y: worked.height, z: palette.lightGround ? 1 : 0,
                     w: CGFloat(palette.limit)),
        ]
        guard var image = kernel.apply(extent: extent, arguments: arguments) else { return nil }
        image = image.matchedToWorkingSpace(from: CGColorSpace(name: CGColorSpace.sRGB)
                                            ?? CGColorSpaceCreateDeviceRGB()) ?? image
        if half {
            image = image.clampedToExtent().samplingLinear()
                .transformed(by: CGAffineTransform(scaleX: size.width / worked.width,
                                                   y: size.height / worked.height))
        }
        return image.cropped(to: CGRect(origin: .zero, size: size))
    }

    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// The look as a picture, row 0 at the top: a still frame, a swatch, a
    /// tile in the Background picker. Nil for a paint that is not a live look.
    public static func cgImage(_ paint: Paint, size: CGSize, atMS ms: Int? = nil) -> CGImage? {
        guard let image = image(paint, size: size, atMS: ms) else { return nil }
        return context.createCGImage(image, from: CGRect(origin: .zero, size: size),
                                     format: .RGBA8,
                                     colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    }

    private static func ciColour(_ colour: RGBA) -> CIColor {
        CIColor(red: colour.r, green: colour.g, blue: colour.b, alpha: 1,
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB())
            ?? CIColor(red: colour.r, green: colour.g, blue: colour.b)
    }

    /// A colour as light, for the programs.
    private static func linear(_ colour: RGBA) -> CIVector {
        func off(_ c: Double) -> CGFloat {
            CGFloat(c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4))
        }
        return CIVector(x: off(colour.r), y: off(colour.g), z: off(colour.b))
    }

    // MARK: - The programs

    /// Every look takes the same arguments: the ground and three lights as
    /// light, then `k` (seconds, strength, scale, the look's own knob, each
    /// strength and scale as a multiple of Normal and the knob nought to one)
    /// and `f` (the worked size in pixels, 1 over a light ground, and the
    /// palette's limit).
    /// What every look shares: the noise, the colours round a loop, the
    /// finish that holds a frame legible, and the shapes a sketch is drawn
    /// from.
    static let common = #"""
    #include <CoreImage/CoreImage.h>
    using namespace metal;

    namespace live {

    constant float3 lum = float3(0.2126, 0.7152, 0.0722);

    inline float hash1(float n) { return fract(sin(n * 12.9898) * 43758.5453); }

    inline float hash2(float2 p) {
        float3 q = fract(float3(p.xyx) * 0.1031);
        q += dot(q, q.yzx + 33.33);
        return fract((q.x + q.y) * q.z);
    }

    inline float noise(float2 p) {
        float2 i = floor(p);
        float2 f = fract(p);
        float2 u = f * f * (3.0 - 2.0 * f);
        return mix(mix(hash2(i), hash2(i + float2(1, 0)), u.x),
                   mix(hash2(i + float2(0, 1)), hash2(i + float2(1, 1)), u.x), u.y);
    }

    inline float fbm(float2 p) {
        float v = 0.0;
        float a = 0.5;
        for (int i = 0; i < 4; i++) {
            v += a * noise(p);
            p = p * 2.03 + float2(17.1, 9.7);
            a *= 0.5;
        }
        return v;
    }

    // A noise that changes smoothly in time as well as in place.
    inline float fbmT(float2 p, float t) {
        float a = fbm(p + float2(0.0, floor(t) * 7.31));
        float b = fbm(p + float2(0.0, (floor(t) + 1.0) * 7.31));
        float f = fract(t);
        return mix(a, b, f * f * (3.0 - 2.0 * f));
    }

    // The three lights round a loop, blended smoothly.
    inline float3 lights(float s, float3 c1, float3 c2, float3 c3) {
        s = fract(s) * 3.0;
        float f = fract(s);
        f = f * f * (3.0 - 2.0 * f);
        if (s < 1.0) { return mix(c1, c2, f); }
        if (s < 2.0) { return mix(c2, c3, f); }
        return mix(c3, c1, f);
    }

    inline float encode(float c) {
        c = clamp(c, 0.0, 1.0);
        return c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1.0 / 2.4) - 0.055;
    }

    // The look's light over its ground, held legible, back on the sRGB curve.
    // `glow` is the lights weighted, `weight` how much light there is in all.
    inline float4 finish(float3 ground, float3 glow, float weight, float4 f) {
        float3 col;
        if (f.z < 0.5) {
            col = ground + glow;
            float l = dot(col, lum);
            float knee = f.w * 0.5;
            if (l > knee) {
                float room = f.w - knee;
                float held = knee + room * (1.0 - exp(-(l - knee) / room));
                col *= held / l;
            }
        } else {
            float3 tint = weight > 1e-4 ? glow / weight : ground;
            float a = 1.0 - exp(-weight);
            col = mix(ground, tint, a * 0.85);
            float l = dot(col, lum);
            if (l < f.w && l > 1e-5) { col = min(col * (f.w / l), float3(1.0)); }
        }
        return float4(encode(col.r), encode(col.g), encode(col.b), 1.0);
    }

    // Where a pixel is, in frame heights from the top-left corner.
    inline float2 place(coreimage::destination d, float4 f) {
        float2 p = d.coord();
        return float2(p.x / f.y, 1.0 - p.y / f.y);
    }

    inline float segment(float2 p, float2 a, float2 b) {
        float2 ab = b - a;
        float h = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-8), 0.0, 1.0);
        return length(p - a - ab * h);
    }

    }

    // Fine lines following the wind: the streamlines of a slowly turning
    // flow, with streaks of light running along them.
    inline float windPotential(float2 p, float t) {
        return p.y * 1.15 + 0.55 * live::fbmT(p * 1.1 + float2(-t * 0.10, 0.0), t * 0.07);
    }

    // A two point perspective sketch of a building, drawn line by line with
    // its construction lines running off to the horizon, then held with a
    // slow drift, over a faint blueprint grid and a light passing over it.
    inline float4 sketchSegment(int i, float aspect, thread float &faint) {
        float hz = 0.60;
        float2 vl = float2(-0.95, hz);
        float2 vr = float2(aspect + 0.95, hz);
        float cx = aspect * 0.5 + 0.08;
        float2 top = float2(cx, 0.20);
        float2 bottom = float2(cx, 0.86);
        float xl = cx - aspect * 0.30;
        float xr = cx + aspect * 0.26;
        faint = 0.0;
        float2 ltop = top + (vl - top) * ((xl - cx) / (vl.x - cx));
        float2 lbot = bottom + (vl - bottom) * ((xl - cx) / (vl.x - cx));
        float2 rtop = top + (vr - top) * ((xr - cx) / (vr.x - cx));
        float2 rbot = bottom + (vr - bottom) * ((xr - cx) / (vr.x - cx));
        if (i == 0) { faint = 1.0; return float4(-0.1, hz, aspect + 0.1, hz); }
        if (i == 1) { return float4(bottom, top); }
        if (i == 2) { return float4(top, ltop); }
        if (i == 3) { return float4(top, rtop); }
        if (i == 4) { return float4(bottom, lbot); }
        if (i == 5) { return float4(bottom, rbot); }
        if (i == 6) { return float4(lbot, ltop); }
        if (i == 7) { return float4(rbot, rtop); }
        if (i == 8) { faint = 1.0; return float4(ltop, vl); }
        if (i == 9) { faint = 1.0; return float4(rtop, vr); }
        if (i == 10) { faint = 1.0; return float4(lbot, vl); }
        if (i == 11) { faint = 1.0; return float4(rbot, vr); }
        // Floors, left face then right, from the corner out.
        if (i < 22) {
            int n = i - 12;
            float level = float(n / 2 + 1) / 6.0;
            float2 at = mix(bottom, top, level);
            if (n % 2 == 0) { return float4(at, at + (vl - at) * ((xl - cx) / (vl.x - cx))); }
            return float4(at, at + (vr - at) * ((xr - cx) / (vr.x - cx)));
        }
        // Window columns, left face then right.
        if (i < 30) {
            int n = i - 22;
            float share = float(n % 4 + 1) / 5.0;
            if (n < 4) {
                float x = mix(cx, xl, share);
                float s = (x - cx) / (vl.x - cx);
                return float4(bottom + (vl - bottom) * s, top + (vl - top) * s);
            }
            float x = mix(cx, xr, share);
            float s = (x - cx) / (vr.x - cx);
            return float4(bottom + (vr - bottom) * s, top + (vr - top) * s);
        }
        // A dimension line over the roof, with its two ticks.
        if (i == 30) { faint = 0.5; return float4(ltop.x, 0.10, rtop.x, 0.10); }
        if (i == 31) { faint = 0.5; return float4(ltop.x, 0.08, ltop.x, 0.12); }
        faint = 0.5;
        return float4(rtop.x, 0.08, rtop.x, 0.12);
    }

    """#

    /// Each look's own program. Every look is compiled ON ITS OWN with the
    /// shared part: Core Image hands back the last function for every kernel
    /// of one source whose arguments match (measured 2026-10-12, two kernels
    /// returning red and green both drew green), and all ten take the same
    /// arguments.
    static func source(_ look: LiveLook) -> String {
        switch look {
        case .aurora:
            return common + #"""
        // Ribbons of light rippling across a night, each a curtain with a bright
        // lower edge and rays rising off it, sliding along and turning colour.
        extern "C" float4 live_aurora(float3 ground, float3 c1, float3 c2, float3 c3,
                                      float4 k, float4 f, coreimage::destination d) [[stitchable]] {
            float2 uv = live::place(d, f);
            float t = k.x;
            float x = uv.x / k.z;
            float3 glow = float3(0.0);
            float weight = 0.0;
            float height = 0.05 + 0.25 * k.w;
            for (int i = 0; i < 3; i++) {
                float fi = float(i);
                float edge = 0.50 - 0.12 * fi
                    + 0.16 * (live::fbm(float2(x * 1.1 + fi * 7.3 + t * 0.16, fi * 3.1 - t * 0.07)) - 0.5) * 2.0
                    + 0.05 * sin(x * 3.2 + t * 1.0 + fi * 2.1);
                float above = edge - uv.y;
                float curtain = above > 0.0 ? exp(-above / height) : exp(-(above * above) / 0.004);
                float rays = 0.4 + 0.6 * live::noise(float2(x * 34.0 + fi * 13.0 - t * 0.6, t * 0.8 + fi));
                float band = smoothstep(0.35, 0.75, live::fbm(float2(x * 0.9 - t * 0.2 + fi * 5.0, fi * 2.0 + t * 0.08)));
                float w = curtain * rays * band * (1.0 - 0.18 * fi) * k.y * 1.1;
                float3 c = live::lights(x * 0.18 + t * 0.035 + fi * 0.33, c1, c2, c3);
                glow += c * w;
                weight += w;
            }
            // A faint glow of the sky behind the curtains.
            float sky = 0.10 * k.y * exp(-abs(uv.y - 0.45) * 3.0);
            glow += c2 * sky;
            weight += sky;
            return live::finish(ground, glow, weight, f);
        }
        """#
        case .energyStreams:
            return common + #"""
        // Glowing lines flowing across the frame like wind or data, each with
        // bright packets running along it and a trail behind them.
        extern "C" float4 live_energyStreams(float3 ground, float3 c1, float3 c2, float3 c3,
                                             float4 k, float4 f, coreimage::destination d) [[stitchable]] {
            float2 uv = live::place(d, f);
            float t = k.x;
            float x = uv.x / k.z;
            float px = 1.0 / f.y;
            float3 glow = float3(0.0);
            float weight = 0.0;
            float trail = mix(18.0, 2.2, k.w);
            for (int i = 0; i < 10; i++) {
                float fi = float(i);
                float h = live::hash1(fi + 1.3);
                float h2 = live::hash1(fi + 7.9);
                float y0 = 0.12 + 0.76 * h
                    + 0.07 * sin(x * (1.4 + 2.0 * h2) + t * (0.45 + 0.5 * h) + fi * 1.7) * k.z
                    + 0.05 * (live::noise(float2(x * 1.3 + t * 0.25, fi * 9.1)) - 0.5) * 2.0;
                float dist = abs(uv.y - y0);
                float width = max((0.0010 + 0.0016 * h2) * k.z, 0.8 * px);
                float core = exp(-(dist * dist) / (width * width));
                float halo = 0.22 * exp(-dist / (width * 14.0));
                float phase = fract(x * (0.45 + 0.3 * h2) - t * (0.30 + 0.35 * h) + h * 7.0);
                float pulse = exp(-(1.0 - phase) * trail) * smoothstep(1.0, 0.96, phase);
                float w = (core + halo) * (0.10 + 1.4 * pulse) * k.y * 1.1;
                float3 c = live::lights(h + 0.1 * fi, c1, c2, c3);
                glow += c * w;
                weight += w;
            }
            return live::finish(ground, glow, weight, f);
        }
        """#
        case .colorBubbles:
            return common + #"""
        // Large soft circles of colour drifting, blooming and overlapping, each
        // with the faint bright rim of an out of focus light.
        extern "C" float4 live_colorBubbles(float3 ground, float3 c1, float3 c2, float3 c3,
                                            float4 k, float4 f, coreimage::destination d) [[stitchable]] {
            float2 uv = live::place(d, f);
            float t = k.x;
            float aspect = f.x / f.y;
            float3 glow = float3(0.0);
            float weight = 0.0;
            for (int i = 0; i < 14; i++) {
                float fi = float(i);
                float h1 = live::hash1(fi * 3.1 + 0.7);
                float h2 = live::hash1(fi * 5.3 + 1.1);
                float h3 = live::hash1(fi * 7.7 + 2.9);
                float h4 = live::hash1(fi * 2.3 + 4.4);
                float2 c = float2(aspect * (0.08 + 0.84 * h1) + 0.16 * sin(t * 0.30 * (0.6 + h3) + fi),
                                  0.10 + 0.80 * h2 + 0.12 * cos(t * 0.26 * (0.6 + h4) + fi * 1.7));
                float period = 5.0 + 4.0 * h3;
                float age = fract(t / period + h4);
                float life = sin(age * 3.14159265);
                float r = (0.07 + 0.13 * h3) * k.z * (0.7 + 0.45 * life);
                float dd = length(uv - c);
                float soft = mix(0.04, 0.75, k.w) * r;
                float disc = 1.0 - smoothstep(r - soft, r, dd);
                float rim = 0.35 * (1.0 - k.w) * exp(-pow((dd - (r - soft * 0.5)) / (soft * 0.3 + 0.004), 2.0));
                float w = (disc * 0.55 + rim * disc) * life * k.y * 0.65;
                float3 col = live::lights(h1 + h2, c1, c2, c3);
                glow += col * w;
                weight += w;
            }
            return live::finish(ground, glow, weight, f);
        }
        """#
        case .lightRays:
            return common + #"""
        // Beams of light falling from above through haze, sweeping slowly.
        extern "C" float4 live_lightRays(float3 ground, float3 c1, float3 c2, float3 c3,
                                         float4 k, float4 f, coreimage::destination d) [[stitchable]] {
            float2 uv = live::place(d, f);
            float t = k.x;
            float aspect = f.x / f.y;
            float2 source = float2(mix(-0.15, aspect + 0.15, k.w), -0.30);
            float2 v = uv - source;
            float angle = atan2(v.x, v.y) + 0.22 * sin(t * 0.40) + 0.06 * sin(t * 1.10);
            float dist = length(v);
            float r1 = live::noise(float2(angle * 13.0 / k.z, t * 0.35));
            float r2 = live::noise(float2(angle * 29.0 / k.z + 4.0, t * 0.55));
            float rays = pow(r1 * 0.65 + r2 * 0.35, 2.2) * 2.4;
            float fall = exp(-dist * 1.05);
            float haze = 0.35 + 0.65 * live::fbm(uv * 2.4 / k.z + float2(t * 0.10, t * 0.04));
            float w1 = rays * fall * haze * k.y * 0.95;
            float w2 = 0.18 * fall * k.y;
            float3 beam = live::lights(angle * 0.25 + t * 0.03, c1, c2, c1);
            float3 glow = beam * w1 + c3 * w2;
            return live::finish(ground, glow, w1 + w2, f);
        }
        """#
        case .lightLeaks:
            return common + #"""
        // Warm film leaks: big soft washes of orange and rose sliding across the
        // frame and flickering, the way light gets into a camera.
        extern "C" float4 live_lightLeaks(float3 ground, float3 c1, float3 c2, float3 c3,
                                          float4 k, float4 f, coreimage::destination d) [[stitchable]] {
            float2 uv = live::place(d, f);
            float t = k.x;
            float aspect = f.x / f.y;
            float3 warm[3] = { float3(1.0, 0.32, 0.08), float3(1.0, 0.62, 0.16), float3(0.95, 0.16, 0.24) };
            float3 own[3] = { c1, c2, c3 };
            float3 glow = float3(0.0);
            float weight = 0.0;
            for (int i = 0; i < 5; i++) {
                float fi = float(i);
                float h = live::hash1(fi * 4.7 + 0.3);
                float h2 = live::hash1(fi * 8.1 + 2.2);
                float period = 6.0 + 3.0 * h;
                float age = fract(t / period + h2);
                float2 c = float2(mix(-0.7, aspect + 0.7, age),
                                  0.15 + 0.7 * h2 + 0.15 * sin(t * 0.35 + fi * 2.0));
                float2 q = uv - c;
                q.x /= (0.40 + 0.35 * h) * k.z;
                q.y /= (0.20 + 0.18 * h2) * k.z;
                float blob = exp(-dot(q, q) * 2.2);
                float flicker = 0.75 + 0.25 * live::noise(float2(t * 2.2 + fi * 5.0, fi));
                float w = blob * flicker * sin(age * 3.14159265) * k.y * 0.8;
                float3 col = mix(own[i % 3], warm[i % 3], k.w);
                glow += col * w;
                weight += w;
            }
            // A leak breathing in from the left edge.
            float edge = exp(-uv.x * 5.0) * (0.5 + 0.5 * sin(t * 0.8)) * 0.5 * k.y;
            glow += mix(c1, warm[0], k.w) * edge;
            weight += edge;
            return live::finish(ground, glow, weight, f);
        }
        """#
        case .windStreams:
            return common + #"""
        extern "C" float4 live_windStreams(float3 ground, float3 c1, float3 c2, float3 c3,
                                           float4 k, float4 f, coreimage::destination d) [[stitchable]] {
            float2 uv = live::place(d, f);
            float t = k.x;
            float px = 1.0 / f.y;
            float zoom = 2.4 / k.z;
            float2 p = uv * zoom;
            float e = 0.004;
            float psi = windPotential(p, t);
            float gx = (windPotential(p + float2(e, 0.0), t) - psi) / e;
            float gy = (windPotential(p + float2(0.0, e), t) - psi) / e;
            float g = max(length(float2(gx, gy)), 0.05);
            float lines = 10.0;
            float s = psi * lines;
            float across = min(fract(s), 1.0 - fract(s)) / (lines * g) / zoom;
            float width = max(mix(0.0005, 0.0040, k.w), 0.7 * px);
            float line = exp(-(across * across) / (width * width));
            float id = floor(s + 0.5);
            float h = live::hash1(id * 1.37);
            float dash = smoothstep(0.30, 0.85, live::noise(float2(p.x * 1.4 - t * (0.9 + 0.7 * h), id * 3.7)));
            float w = line * (0.08 + 1.1 * dash) * k.y * 0.9;
            float haze = 0.06 * k.y * live::fbmT(p * 0.6, t * 0.1);
            float3 glow = live::lights(h, c1, c2, c3) * w + c3 * haze;
            return live::finish(ground, glow, w + haze, f);
        }
        """#
        case .sketch:
            return common + #"""
        extern "C" float4 live_sketch(float3 ground, float3 c1, float3 c2, float3 c3,
                                      float4 k, float4 f, coreimage::destination d) [[stitchable]] {
            float2 uv = live::place(d, f);
            float t = k.x;
            float px = 1.0 / f.y;
            float aspect = f.x / f.y;
            // The held drawing drifts slowly, like a camera breathing.
            float2 middle = float2(aspect * 0.5, 0.5);
            float2 q = middle + (uv - middle) / (k.z * (1.0 + 0.02 * sin(t * 0.21)))
                + float2(0.018 * sin(t * 0.17), 0.010 * sin(t * 0.13));
            float width = max(mix(0.0006, 0.0034, k.w), 0.8 * px);
            float3 glow = float3(0.0);
            float weight = 0.0;
            for (int i = 0; i < 33; i++) {
                float faint;
                float4 s = sketchSegment(i, aspect, faint);
                float start = 0.3 + float(i) * 0.17;
                float progress = clamp((t - start) / 0.55, 0.0, 1.0);
                if (progress <= 0.0) { continue; }
                progress = 1.0 - pow(1.0 - progress, 3.0);
                float2 a = s.xy;
                float2 dir = normalize(s.zw - s.xy + float2(1e-6));
                // A sketcher's line runs a little past both of its ends.
                float2 from = a - dir * 0.012;
                float2 to = a + (s.zw + dir * 0.012 - a) * progress;
                float dist = live::segment(q, from, to);
                float line = exp(-(dist * dist) / (width * width));
                float strength = faint > 0.9 ? 0.35 : (faint > 0.4 ? 0.6 : 1.0);
                float w = line * strength * k.y;
                // The pen's tip glows while it draws.
                float tip = progress < 1.0 ? 0.9 * exp(-length(q - to) / (width * 5.0)) : 0.0;
                float3 col = faint > 0.9 ? c2 : c1;
                glow += col * w + c3 * tip * k.y;
                weight += w + tip * k.y;
            }
            // The blueprint grid, faint, and a soft light passing over the sheet.
            float cell = 0.05;
            float2 g = abs(fract(q / cell + 0.5) - 0.5) * cell;
            float grid = exp(-pow(min(g.x, g.y) / max(0.6 * px, 0.0005), 2.0)) * 0.10 * k.y;
            float2 lamp = float2(aspect * (0.5 + 0.38 * sin(t * 0.35)), 0.45 + 0.12 * cos(t * 0.27));
            float light = 0.22 * k.y * exp(-dot(uv - lamp, uv - lamp) * 3.0);
            glow += c2 * grid + c3 * light;
            weight += grid + light;
            return live::finish(ground, glow, weight, f);
        }
        """#
        case .particles:
            return common + #"""
        // Dust and sparks at three depths: the near ones bigger, softer, faster.
        extern "C" float4 live_particles(float3 ground, float3 c1, float3 c2, float3 c3,
                                         float4 k, float4 f, coreimage::destination d) [[stitchable]] {
            float2 uv = live::place(d, f);
            float t = k.x;
            float px = 1.0 / f.y;
            float3 glow = float3(0.0);
            float weight = 0.0;
            for (int layer = 0; layer < 3; layer++) {
                float depth = float(layer) / 2.0;        // nought far, one near
                float near = mix(0.5, 1.0, k.w) * depth + (1.0 - k.w * 0.5) * (1.0 - depth) * 0.3;
                float cell = mix(0.045, 0.14, depth) * k.z;
                float2 velocity = float2(0.025, -0.05) * (0.4 + 1.8 * depth * mix(0.6, 1.4, k.w));
                float2 q = uv - velocity * t + float2(float(layer) * 3.7, float(layer) * 1.3);
                float2 id = floor(q / cell);
                float2 within = fract(q / cell);
                float h = live::hash2(id + float(layer) * 17.0);
                float h2 = live::hash2(id * 1.7 + 3.0);
                float2 at = 0.25 + 0.5 * float2(h, h2)
                    + 0.08 * float2(sin(t * (0.6 + h) + h * 6.0), cos(t * (0.5 + h2) + h2 * 6.0));
                float r = mix(0.0016, 0.0065, near) * (0.6 + 0.8 * h2);
                float soft = r * mix(0.4, 1.6, near * k.w);
                float dist = length((within - at) * cell);
                float spot = 1.0 - smoothstep(max(r - soft, 0.0), r + soft + px, dist);
                float halo = 0.35 * exp(-dist / (r * 3.0 + px));
                float twinkle = 0.55 + 0.45 * sin(t * (2.0 + 3.0 * h) + h * 40.0);
                float shown = step(0.5, h2);
                float w = (spot + halo) * twinkle * shown * mix(0.45, 1.0, depth) * k.y;
                float3 col = live::lights(h * 0.7 + float(layer) * 0.3, c1, c2, c3);
                glow += col * w;
                weight += w;
            }
            float fog = 0.10 * k.y * live::fbm(uv * 1.8 + float2(t * 0.05, -t * 0.03));
            glow += c3 * fog;
            weight += fog;
            return live::finish(ground, glow, weight, f);
        }
        """#
        case .liquidGradient:
            return common + #"""
        // A glossy liquid of the theme's colours, folding over itself and
        // flowing, with a soft sheen where it crests.
        extern "C" float4 live_liquidGradient(float3 ground, float3 c1, float3 c2, float3 c3,
                                              float4 k, float4 f, coreimage::destination d) [[stitchable]] {
            float2 uv = live::place(d, f);
            float t = k.x;
            float2 p = uv * 1.5 / k.z;
            float2 q = float2(live::fbm(p + float2(0.0, t * 0.14)),
                              live::fbm(p + float2(5.2, 1.3) - t * 0.11));
            float2 r = float2(live::fbm(p + 3.2 * q + float2(1.7, 9.2) + t * 0.16),
                              live::fbm(p + 3.2 * q + float2(8.3, 2.8) - t * 0.13));
            float v = live::fbm(p + 3.0 * r);
            float a1 = smoothstep(0.25, 0.85, v);
            float a2 = smoothstep(0.2, 0.9, length(q));
            float a3 = smoothstep(0.3, 0.8, r.x);
            float3 col = c1 * a1 * 0.5 + c2 * a2 * 0.35 * (1.0 - a1) + c3 * a3 * a3 * 0.45;
            float w = (a1 * 0.5 + a2 * 0.35 + a3 * 0.45) * k.y;
            float sheen = pow(clamp(1.0 - abs(v - 0.58) * 7.0, 0.0, 1.0), 3.0) * k.w * 0.9 * k.y;
            float3 glow = col * k.y + float3(1.0) * sheen * 0.3;
            return live::finish(ground, glow, w + sheen, f);
        }
        """#
        case .gridHorizon:
            return common + #"""
        // A glowing grid on the ground racing toward you under a horizon glow.
        extern "C" float4 live_gridHorizon(float3 ground, float3 c1, float3 c2, float3 c3,
                                           float4 k, float4 f, coreimage::destination d) [[stitchable]] {
            float2 uv = live::place(d, f);
            float t = k.x;
            float px = 1.0 / f.y;
            float aspect = f.x / f.y;
            float hz = mix(0.30, 0.70, k.w);
            float3 glow = float3(0.0);
            float weight = 0.0;
            // The glow along the horizon, both sides of it.
            float band = exp(-abs(uv.y - hz) * 9.0) * 0.55 * k.y;
            float shimmer = 0.85 + 0.15 * sin(uv.x * 6.0 + t * 1.3);
            glow += c2 * band * shimmer;
            weight += band;
            if (uv.y > hz) {
                float dy = uv.y - hz;
                float height = 0.32;
                float z = height / dy;
                float wx = (uv.x - aspect * 0.5) * z;
                float spacing = 0.45 * k.z;
                float fx = wx / spacing;
                float across = abs(fract(fx + 0.5) - 0.5) * spacing / z;
                float fz = (z + t * 1.6) / spacing;
                float dzdy = height / (dy * dy);
                float along = abs(fract(fz + 0.5) - 0.5) * spacing / dzdy;
                float width = max(0.0011, 0.8 * px);
                // Lines closer together than a few pixels near the horizon fade
                // out rather than shimmer.
                float rowGap = spacing / dzdy;
                float rows = smoothstep(3.0 * px, 9.0 * px, rowGap);
                float cols = smoothstep(3.0 * px, 9.0 * px, spacing / z);
                float lineX = (exp(-pow(across / width, 2.0)) + 0.25 * exp(-across / (width * 7.0))) * cols;
                float lineZ = (exp(-pow(along / width, 2.0)) + 0.25 * exp(-along / (width * 7.0))) * rows;
                float fade = exp(-z * 0.10);
                float w = max(lineX, lineZ) * fade * k.y;
                glow += c1 * w;
                weight += w;
            } else {
                // A low sun sitting on the horizon, slowly breathing.
                float2 sun = float2(aspect * 0.5, hz - 0.02);
                float r = length((uv - sun) * float2(1.0, 1.0));
                float disc = (1.0 - smoothstep(0.16, 0.17, r)) * 0.35 * k.y * (0.85 + 0.15 * sin(t * 0.9));
                glow += c3 * disc;
                weight += disc;
            }
            return live::finish(ground, glow, weight, f);
        }
        """#
        }
    }
}
