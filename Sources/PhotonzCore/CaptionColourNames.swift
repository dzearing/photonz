import Foundation

/// The short lists a caption's colour rows pick from, and the word a colour
/// reads as in its row. A row never shows a hex code: a colour on its list
/// reads that name, and one that is not (a style from an older version, a
/// value typed elsewhere) reads the nearest name with how solid it is,
/// `Black 70%`.
public enum CaptionColourNames {
    public struct Choice: Hashable, Sendable {
        public let name: String
        /// Nil is the list's "none".
        public let hex: String?

        public init(_ name: String, _ hex: String?) {
            self.name = name
            self.hex = hex
        }
    }

    /// The words' own colour.
    public static let inks: [Choice] = [
        Choice("White", "#FFFFFF"), Choice("Yellow", CaptionLook.activeYellow),
        Choice("Black", "#000000"), Choice("Cyan", "#7FE7FF"), Choice("Ice", "#E9FDFF"),
    ]
    /// The plate behind the words, darkest last among the blacks.
    public static let plates: [Choice] = [
        Choice("None", nil), Choice("Dark", CaptionLook.plate), Choice("Darker", "#000000B3"),
        Choice("Black", "#000000"), Choice("White", "#FFFFFFE6"),
    ]
    /// A glow, or the word being said.
    public static let bright: [Choice] = [
        Choice("Yellow", CaptionLook.activeYellow), Choice("Cyan", CaptionLook.karaokeCyan),
        Choice("Pink", "#FF4FD8"), Choice("Green", "#3ECF8E"), Choice("White", "#FFFFFF"),
        Choice("Black", "#000000"),
    ]
    /// An outline.
    public static let edges: [Choice] = [
        Choice("Black", "#000000"), Choice("White", "#FFFFFF"), Choice("Yellow", CaptionLook.activeYellow),
        Choice("Cyan", CaptionLook.karaokeCyan), Choice("Pink", "#FF4FD8"),
    ]

    /// What `hex` reads as in a row choosing among `choices`.
    public static func name(of hex: String?, among choices: [Choice], none: String = "None") -> String {
        guard let hex else { return choices.first { $0.hex == nil }?.name ?? none }
        if let exact = choices.first(where: { $0.hex?.uppercased() == hex.uppercased() }) {
            return exact.name
        }
        guard let colour = RGBA(hex: hex) else { return "Custom" }
        let named = choices.compactMap { choice in
            choice.hex.flatMap(RGBA.init(hex:)).map { (choice.name, $0) }
        }
        guard let nearest = named.min(by: { distance($0.1, colour) < distance($1.1, colour) })
        else { return "Custom" }
        let percent = Int((colour.a * 100).rounded())
        return percent >= 100 ? nearest.0 : "\(nearest.0) \(percent)%"
    }

    /// How far apart two colours look, alpha set aside: the opacity is read
    /// out on its own.
    private static func distance(_ a: RGBA, _ b: RGBA) -> Double {
        let dr = a.r - b.r, dg = a.g - b.g, db = a.b - b.b
        return 0.3 * dr * dr + 0.59 * dg * dg + 0.11 * db * db
    }
}
