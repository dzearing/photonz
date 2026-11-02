import Foundation

/// What Settings > Ask and Ask's setup dialog say about each model
/// (`docs/design/ask.md`, "Choosing a model"): what it needs, how good and how
/// fast it is, measured rather than guessed, and which set this Mac should get.
///
/// Nothing is downloaded until a person asks for it: a fresh Photonz has no
/// model, and the first Ask opens the setup dialog with `AskModelSetup.plan`.

/// One model's measurement: the held-out eval's total at Next defaults
/// (`Scripts/ask-eval.sh run --engine ask --set held-out`) and the median
/// seconds a request took to a result, on the Mac named.
public struct AskModelMeasure: Sendable, Equatable {
    /// The held-out total, 0 to 100.
    public let heldOut: Double
    /// Median seconds from Send to a result over the held-out set.
    public let medianSeconds: Double
    /// The eval run it comes from.
    public let run: String
    /// The Mac it was measured on.
    public let mac: String

    public init(heldOut: Double, medianSeconds: Double, run: String, mac: String = AskModelMeasure.measuringMac) {
        self.heldOut = heldOut
        self.medianSeconds = medianSeconds
        self.run = run
        self.mac = mac
    }

    public static let measuringMac = "M4 Max, 64 GB"

    /// Quality on a 1 to 5 scale (`AskModelRating`).
    public var quality: Int { AskModelRating.quality(heldOut: heldOut) }
    /// Speed on a 1 to 5 scale.
    public var speed: Int { AskModelRating.speed(medianSeconds: medianSeconds) }
    /// Whether it can do Ask's work at all.
    public var canDoAsksWork: Bool { heldOut >= AskModelRating.floor }

    /// The real numbers, for the rating's help tag.
    public var qualityWords: String { String(format: "Scored %.1f of 100 on Ask's test requests", heldOut) }
    public var speedWords: String { String(format: "%.0f s a request, median, on an %@", medianSeconds, mac) }
}

/// How a measurement becomes the 1 to 5 shown in Settings: fixed bands, so a
/// new model is rated by the same ruler as the old ones.
public enum AskModelRating {
    /// Held-out totals that earn 2, 3, 4 and 5.
    public static let qualityBands: [Double] = [20, 35, 50, 60]
    /// Median seconds a request at or under which a model earns 2, 3, 4 and 5.
    public static let speedBands: [Double] = [180, 90, 45, 20]
    /// Below this held-out total a model cannot do Ask's work, and Settings
    /// says so instead of offering it.
    public static let floor: Double = 20

    public static func quality(heldOut: Double) -> Int { 1 + qualityBands.filter { heldOut >= $0 }.count }
    public static func speed(medianSeconds: Double) -> Int { 1 + speedBands.filter { medianSeconds <= $0 }.count }
}

/// Mac memory sizes as Apple sells them, and the smallest that holds a model.
public enum AskMacSizes {
    /// GB on the box. The Mac reports them in binary gigabytes, so a "16 GB"
    /// Mac has 17.2 GB as `AskModels.gigabytes(ofMemory:)` counts.
    public static let sold: [Int] = [8, 16, 18, 24, 32, 36, 48, 64, 96, 128, 192, 256, 512]

    /// What a Mac sold as `size` GB reports, in the units `memoryGigabytes` uses.
    public static func reported(_ size: Int) -> Double {
        AskModels.gigabytes(ofMemory: UInt64(size) << 30)
    }

    /// The smallest Mac that holds `gigabytes` by the three-fifths rule, or nil.
    public static func smallest(holding gigabytes: Double) -> Int? {
        sold.first { gigabytes <= reported($0) * AskModels.memoryShare }
    }
}

/// What the setup dialog offers a Mac with no model: one chat model, and the
/// picture model when it fits beside it, by the Mac's memory and free disk.
public struct AskSetupPlan: Sendable, Equatable {
    public enum Short: Sendable, Equatable {
        /// No model Ask can use fits in this Mac's memory.
        case memory
        /// One fits in memory, but the disk lacks this many bytes for the smallest.
        case disk(needed: Int64)
    }

    /// The chat model to download, or nil when one is already on the Mac or none fits.
    public let chat: AskBuiltInModels.Choice?
    /// The chat model Ask will use once the plan is done.
    public let uses: AskBuiltInModels.Choice?
    /// Whether the picture model comes too.
    public let picture: Bool
    /// Why nothing could be offered.
    public let short: Short?

    public init(chat: AskBuiltInModels.Choice?, uses: AskBuiltInModels.Choice?, picture: Bool, short: Short?) {
        self.chat = chat
        self.uses = uses
        self.picture = picture
        self.short = short
    }

    /// Everything the plan brings down.
    public var bytes: Int64 {
        (chat?.downloadBytes ?? 0) + (picture ? AskPictureModelPlan.downloadBytes : 0)
    }

    public var isEmpty: Bool { chat == nil && !picture }
}

public enum AskModelSetup {

    /// Room kept free on the disk beyond what a download brings down; the
    /// same margin the download itself checks (`AskModelDownload`).
    public static let diskMargin: Int64 = 2_000_000_000

    /// The chat models Settings lists: every one offered, plus any other this
    /// Mac already has (so it can be used or deleted).
    public static func listed(downloaded: [String]) -> [AskBuiltInModels.Choice] {
        AskBuiltInModels.ranked.filter { $0.offered || downloaded.contains($0.id) }
    }

    /// Whether a Mac can hold `choice` (`AskModels.memoryShare`).
    public static func fits(_ choice: AskBuiltInModels.Choice, memoryGigabytes: Double) -> Bool {
        choice.gigabytes <= memoryGigabytes * AskModels.memoryShare
    }

    /// Whether Settings and the dialog may offer `choice` at all: listed and
    /// able to do Ask's work.
    public static func offerable(_ choice: AskBuiltInModels.Choice) -> Bool {
        choice.offered && (choice.measured?.canDoAsksWork ?? true)
    }

    /// The set for this Mac: the best offerable chat model it can hold whose
    /// download fits the free disk, then the picture model when it fits
    /// beside it in memory and on disk. A chat model already on the Mac that
    /// it can hold is kept, and only the picture model is offered.
    public static func plan(memoryGigabytes: Double, freeBytes: Int64,
                            downloaded: [String], pictureInstalled: Bool) -> AskSetupPlan {
        let spare = freeBytes - diskMargin
        let have = AskBuiltInModels.ranked.first { downloaded.contains($0.id) && fits($0, memoryGigabytes: memoryGigabytes) }
        let chat: AskBuiltInModels.Choice?
        let uses: AskBuiltInModels.Choice
        if let have {
            chat = nil
            uses = have
        } else {
            let fitting = AskBuiltInModels.ranked.filter { offerable($0) && fits($0, memoryGigabytes: memoryGigabytes) }
            guard let smallest = fitting.min(by: { $0.downloadBytes < $1.downloadBytes }) else {
                return AskSetupPlan(chat: nil, uses: nil, picture: false, short: .memory)
            }
            guard let pick = fitting.first(where: { $0.downloadBytes <= spare }) else {
                return AskSetupPlan(chat: nil, uses: nil, picture: false,
                                    short: .disk(needed: smallest.downloadBytes + diskMargin - freeBytes))
            }
            chat = pick
            uses = pick
        }
        let left = spare - (chat?.downloadBytes ?? 0)
        let picture = !pictureInstalled
            && AskPictureModelPlan.fits(memoryGigabytes: memoryGigabytes, beside: uses)
            && AskPictureModelPlan.downloadBytes <= left
        return AskSetupPlan(chat: chat, uses: uses, picture: picture, short: nil)
    }
}
