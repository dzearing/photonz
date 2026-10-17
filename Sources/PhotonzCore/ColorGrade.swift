import CoreGraphics
import Foundation

/// A colour grade on a layer's own picture (`EffectKind.colorGrade`): the five
/// controls an editor reaches for first, the ones Premiere's Lumetri Color puts
/// at the top of Basic Correction.
///
/// Every value has a MIDDLE, and a grade with all five at their middles is no
/// grade at all: the picture is drawn exactly as it would be without one, not
/// passed through five filters that each happen to do nearly nothing. So a
/// clip with its sliders put back is the clip, byte for byte.
///
/// Like a key or a crop, it is done to what the layer is made of rather than
/// laid over it, so a shadow is thrown by the graded picture and a border
/// drawn round it is the colour it was set to (`DocumentRenderer`).
public struct ColorGradeEffect: Hashable, Codable, Sendable {
    /// Cooler below nought, warmer above, on Lumetri's -100 to 100.
    public var temperature: Double
    /// Greener below nought, more magenta above.
    public var tint: Double
    /// Darker or brighter, in stops.
    public var exposure: Double
    /// Flatter below nought, punchier above.
    public var contrast: Double
    /// How colourful, as a percent: nought is grey, 100 is as recorded, 300
    /// is the mock's top.
    public var saturation: Double
    /// Whether it grades at all. Off keeps every value on it.
    public var isOn: Bool

    public static let temperatureRange: ClosedRange<Double> = -100...100
    public static let tintRange: ClosedRange<Double> = -100...100
    public static let exposureRange: ClosedRange<Double> = -4...4
    public static let contrastRange: ClosedRange<Double> = -100...100
    public static let saturationRange: ClosedRange<Double> = 0...300

    /// Every value at its middle: the picture as it is.
    public static let neutral = ColorGradeEffect()

    /// What a grade looks like the moment it is added: the mock's Warm grade,
    /// a little warmer, a little punchier and a little more colourful than
    /// the recording, so the press visibly did something and the next thing
    /// you do is tune it.
    public static let starting = ColorGradeEffect(temperature: 20, contrast: 10, saturation: 110)

    public init(temperature: Double = 0, tint: Double = 0, exposure: Double = 0,
                contrast: Double = 0, saturation: Double = 100, isOn: Bool = true) {
        self.temperature = Self.held(temperature, Self.temperatureRange)
        self.tint = Self.held(tint, Self.tintRange)
        self.exposure = Self.held(exposure, Self.exposureRange)
        self.contrast = Self.held(contrast, Self.contrastRange)
        self.saturation = Self.held(saturation, Self.saturationRange)
        self.isOn = isOn
    }

    static func held(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return range.contains(0) ? 0 : range.lowerBound }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    /// Whether every value is at its middle.
    public var isNeutral: Bool {
        temperature == 0 && tint == 0 && exposure == 0 && contrast == 0 && saturation == 100
    }

    /// Whether it changes the picture at all.
    public var paints: Bool { isOn && !isNeutral }

    private enum CodingKeys: String, CodingKey {
        case temperature, tint, exposure, contrast, saturation, isOn
    }

    /// A value left out reads as its middle, so a grade is written with only
    /// what it changes and opens with the rest as they were.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(temperature: try c.decodeIfPresent(Double.self, forKey: .temperature) ?? 0,
                  tint: try c.decodeIfPresent(Double.self, forKey: .tint) ?? 0,
                  exposure: try c.decodeIfPresent(Double.self, forKey: .exposure) ?? 0,
                  contrast: try c.decodeIfPresent(Double.self, forKey: .contrast) ?? 0,
                  saturation: try c.decodeIfPresent(Double.self, forKey: .saturation) ?? 100,
                  isOn: try c.decodeIfPresent(Bool.self, forKey: .isOn) ?? true)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if temperature != 0 { try c.encode(temperature, forKey: .temperature) }
        if tint != 0 { try c.encode(tint, forKey: .tint) }
        if exposure != 0 { try c.encode(exposure, forKey: .exposure) }
        if contrast != 0 { try c.encode(contrast, forKey: .contrast) }
        if saturation != 100 { try c.encode(saturation, forKey: .saturation) }
        if !isOn { try c.encode(isOn, forKey: .isOn) }
    }

    /// One of the five values, by the key that moves it. Nil for anything
    /// that is not a grade's.
    public func value(of property: MotionProperty) -> Double? {
        switch property {
        case .gradeTemperature: temperature
        case .gradeTint: tint
        case .gradeExposure: exposure
        case .gradeContrast: contrast
        case .gradeSaturation: saturation
        default: nil
        }
    }

    /// Sets one of the five values, held inside its range. Anything that is
    /// not a grade's value changes nothing.
    public mutating func set(_ property: MotionProperty, to value: Double) {
        switch property {
        case .gradeTemperature: temperature = Self.held(value, Self.temperatureRange)
        case .gradeTint: tint = Self.held(value, Self.tintRange)
        case .gradeExposure: exposure = Self.held(value, Self.exposureRange)
        case .gradeContrast: contrast = Self.held(value, Self.contrastRange)
        case .gradeSaturation: saturation = Self.held(value, Self.saturationRange)
        default: break
        }
    }
}

extension MotionProperty {
    /// The five values of a colour grade, in the order its section lists them.
    public static let gradeProperties: [MotionProperty] =
        [.gradeTemperature, .gradeTint, .gradeExposure, .gradeContrast, .gradeSaturation]

    /// One of a colour grade's values.
    public var isGrade: Bool { Self.gradeProperties.contains(self) }

    /// Where a grade's value sits when the picture is as recorded.
    public var gradeMiddle: Double? {
        guard isGrade else { return nil }
        return self == .gradeSaturation ? 100 : 0
    }

    /// The range a grade's value is held to.
    public var gradeRange: ClosedRange<Double>? {
        switch self {
        case .gradeTemperature: ColorGradeEffect.temperatureRange
        case .gradeTint: ColorGradeEffect.tintRange
        case .gradeExposure: ColorGradeEffect.exposureRange
        case .gradeContrast: ColorGradeEffect.contrastRange
        case .gradeSaturation: ColorGradeEffect.saturationRange
        default: nil
        }
    }
}

extension LayerStyle {
    /// The grade at a place in the list, or nil when the entry there is
    /// something else.
    public func colorGradeEffect(at index: Int) -> ColorGradeEffect? { effect(at: index)?.colorGrade }

    /// Changes one grade in place, and does nothing at all when the entry
    /// there is not a grade.
    public mutating func updateColorGradeEffect(at index: Int, _ mutate: (inout ColorGradeEffect) -> Void) {
        guard var grade = colorGradeEffect(at: index) else { return }
        mutate(&grade)
        effects[index] = .colorGrade(grade)
    }

    /// The grade that changes the picture, or nil when there is none, it is
    /// off, or every value is at its middle.
    public var colorGrade: ColorGradeEffect? {
        effects.compactMap(\.colorGrade).first(where: \.paints)
    }
}
