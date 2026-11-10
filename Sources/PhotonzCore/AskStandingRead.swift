import Foundation

/// The part of Ask's first request that is the same every time, saved once
/// so a model that has just loaded does not read it again.
///
/// Ask's request starts with its tools and its rules and ends with the
/// document and the person's words. On Qwen3.8 27B the first part is about
/// 13,000 tokens and the model reads under 200 a second, so a cold Ask spent
/// a minute or more on words it had read the time before (83 s against 14 s
/// warm on 2026-10-24). The built-in server can write what it has read to a
/// file and read it back in a fraction of a second (llama-server's
/// `--slot-save-path` and `/slots/0?action=save|restore`), so that part is
/// read once, saved, and restored on every later first turn.
///
/// The saved read is of the standing part ALONE, never of a whole request:
/// the models Ask runs keep part of what they read as a running state that
/// cannot be wound back to an earlier point, so a file of a longer request
/// would be no use to a request that differs after the rules.
///
/// A file is named by everything that makes it what it is (the model, every
/// file the server loaded for it, the server's own build, the window and the
/// exact tokens), so a changed prompt, model or server never reads a stale
/// one: it simply makes a new file.
public enum AskStandingRead {

    /// What the server read with: a file read with any of these different
    /// holds nothing the server can use.
    public struct Identity: Hashable, Sendable {
        /// The model's id (`AskBuiltInModels.Choice.id`); every file name
        /// starts with it, so a model's files go with it.
        public let model: String
        /// Every file the server loaded, each with its size.
        public let files: [String]
        /// The server's own build, as it says it.
        public let server: String
        /// The window it was started with.
        public let window: Int

        public init(model: String, files: [String], server: String, window: Int) {
            self.model = model
            self.files = files
            self.server = server
            self.window = window
        }
    }

    /// Below this a file costs more than reading it again.
    public static let fewestTokens = 2_048

    /// How many saved reads are kept. Each is about 0.4 GB plus 72 KB a token
    /// on Qwen3.8 27B (1.4 GB for its standing part), so only the ones in use
    /// stay: one for pictures, one for video, one for painting.
    public static let kept = 3

    public static let fileExtension = "bin"

    /// The tokens `request` and `standing` share from the start: the part
    /// saved.
    public static func shared(_ request: [Int], _ standing: [Int]) -> [Int] {
        var count = 0
        while count < request.count, count < standing.count, request[count] == standing[count] { count += 1 }
        return Array(request.prefix(count))
    }

    public static func worthSaving(_ tokens: [Int]) -> Bool { tokens.count >= fewestTokens }

    /// The token list in the server's `/tokenize` answer.
    public static func tokens(fromTokenize json: AgentJSON) -> [Int]? {
        guard let list = json["tokens"]?.arrayValue else { return nil }
        let tokens = list.compactMap { $0.doubleValue.map { Int($0) } }
        return tokens.count == list.count ? tokens : nil
    }

    /// The file the read of `tokens` is saved in: the model's id, then a hash
    /// of everything else.
    public static func fileName(_ identity: Identity, tokens: [Int]) -> String {
        var hash = FNV()
        hash.add(identity.model)
        for file in identity.files { hash.add(file) }
        hash.add(identity.server)
        hash.add(String(identity.window))
        hash.add(String(tokens.count))
        for token in tokens { hash.add(UInt64(bitPattern: Int64(token))) }
        return "\(safe(identity.model))-\(String(format: "%016llx", hash.value)).\(fileExtension)"
    }

    /// Whether `fileName` is a saved read of `model`.
    public static func belongs(_ fileName: String, to model: String) -> Bool {
        let start = "\(safe(model))-"
        guard fileName.hasPrefix(start), fileName.hasSuffix(".\(fileExtension)") else { return false }
        let hex = fileName.dropFirst(start.count).dropLast(fileExtension.count + 1)
        return hex.count == 16 && hex.allSatisfy(\.isHexDigit)
    }

    /// The files to take off the Mac so only the `keeping` most recently
    /// used stay.
    public static func toRemove(_ files: [(name: String, used: Date)], keeping: Int = kept) -> [String] {
        files.sorted { $0.used > $1.used }.dropFirst(keeping).map(\.name)
    }

    /// The model's id as the server takes it in a file name.
    private static func safe(_ model: String) -> String {
        String(model.map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" ? $0 : "_" })
    }

    /// FNV-1a, 64 bits: stable from run to run, unlike `Hasher`.
    private struct FNV {
        var value: UInt64 = 0xcbf2_9ce4_8422_2325

        mutating func add(_ byte: UInt8) {
            value ^= UInt64(byte)
            value = value &* 0x0000_0100_0000_01b3
        }

        mutating func add(_ number: UInt64) {
            for shift in stride(from: 0, to: 64, by: 8) { add(UInt8(truncatingIfNeeded: number >> UInt64(shift))) }
        }

        /// A string and then a separator, so "ab"+"c" is not "a"+"bc".
        mutating func add(_ text: String) {
            for byte in text.utf8 { add(byte) }
            add(UInt8(0))
        }
    }
}
