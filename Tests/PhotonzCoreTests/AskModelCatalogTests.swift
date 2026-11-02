import Foundation
@testable import PhotonzCore
import Testing

/// Settings > Ask lists several models with what each needs and how good and
/// fast it is, and the first Ask on a Mac with none offers the right set
/// (`docs/design/ask.md`, "Choosing a model").
@Suite("Ask: choosing and setting up a model")
struct AskModelCatalogTests {

    static let gb: Int64 = 1_000_000_000

    // MARK: Ratings

    @Test("Ratings come from fixed bands over the measured numbers, 1 to 5")
    func ratingBands() {
        #expect(AskModelRating.quality(heldOut: 0) == 1)
        #expect(AskModelRating.quality(heldOut: 19.9) == 1)
        #expect(AskModelRating.quality(heldOut: 20) == 2)
        #expect(AskModelRating.quality(heldOut: 49.9) == 3)
        #expect(AskModelRating.quality(heldOut: 57.8) == 4)
        #expect(AskModelRating.quality(heldOut: 60.2) == 5)
        #expect(AskModelRating.quality(heldOut: 100) == 5)
        #expect(AskModelRating.speed(medianSeconds: 10) == 5)
        #expect(AskModelRating.speed(medianSeconds: 31) == 4)
        #expect(AskModelRating.speed(medianSeconds: 49.1) == 3)
        #expect(AskModelRating.speed(medianSeconds: 141.9) == 2)
        #expect(AskModelRating.speed(medianSeconds: 600) == 1)
    }

    @Test("A rating's help tag carries the real numbers and where they were measured")
    func ratingWords() {
        let measure = AskModelMeasure(heldOut: 57.8, medianSeconds: 141.9, run: "r")
        #expect(measure.qualityWords == "Scored 57.8 of 100 on Ask's test requests")
        #expect(measure.speedWords == "142 s a request, median, on an M4 Max, 64 GB")
        #expect(measure.canDoAsksWork)
        #expect(!AskModelMeasure(heldOut: 12, medianSeconds: 10, run: "r").canDoAsksWork)
    }

    @Test("Every offered chat model and the picture model carry a measurement and a one-line blurb")
    func everyOfferIsMeasured() {
        for choice in AskBuiltInModels.ranked where choice.offered {
            #expect(choice.measured != nil, "\(choice.id) is offered without being measured")
            #expect(!choice.blurb.isEmpty && choice.blurb.count <= 60, "\(choice.id): \(choice.blurb)")
            #expect(!choice.blurb.contains("\u{2014}"))
        }
        #expect(AskPictureModelPlan.measured.canDoAsksWork)
        #expect(!AskPictureModelPlan.blurb.isEmpty && AskPictureModelPlan.blurb.count <= 60)
    }

    // MARK: Mac sizes

    @Test("A model's memory need is the smallest Mac sold that holds it")
    func smallestMac() throws {
        #expect(AskMacSizes.reported(16) > 17.1 && AskMacSizes.reported(16) < 17.2)
        #expect(AskMacSizes.smallest(holding: 24.4) == 48)
        #expect(AskMacSizes.smallest(holding: 21.7) == 36)
        #expect(AskMacSizes.smallest(holding: 18.5) == 32)
        #expect(AskMacSizes.smallest(holding: 7.5) == 16)
        #expect(AskMacSizes.smallest(holding: 4.5) == 8)
        #expect(AskMacSizes.smallest(holding: 10_000) == nil)
    }

    @Test("Every Mac size sold is offered a model that can do Ask's work, or told it has too little memory")
    func everyMacIsAnswered() {
        for size in AskMacSizes.sold {
            let plan = AskModelSetup.plan(memoryGigabytes: AskMacSizes.reported(size), freeBytes: 1_000 * Self.gb,
                                          downloaded: [], pictureInstalled: false)
            if let chat = plan.chat {
                #expect(AskModelSetup.offerable(chat), "\(size) GB")
                #expect(AskModelSetup.fits(chat, memoryGigabytes: AskMacSizes.reported(size)), "\(size) GB")
            } else {
                #expect(plan.short == .memory, "\(size) GB")
            }
        }
    }

    // MARK: The list

    @Test("Settings lists every offered model, and one no longer offered only on a Mac that has it")
    func listed() {
        let offered = AskBuiltInModels.ranked.filter(\.offered).map(\.id)
        #expect(AskModelSetup.listed(downloaded: []).map(\.id) == offered)
        #expect(!offered.contains("qwen3.6-27b"))
        #expect(AskModelSetup.listed(downloaded: ["qwen3.6-27b"]).map(\.id).contains("qwen3.6-27b"))
    }

    // MARK: The set a Mac gets

    static let roomy: Int64 = 500 * gb

    @Test("The set each Mac size gets, with room on the disk",
          arguments: [(8, nil, false), (16, nil, false), (24, nil, false), (32, nil, false),
                      (36, "qwen3.6-35b-a3b", false), (48, "qwen3.8-27b", false), (64, "qwen3.8-27b", true)])
    func setBySize(size: Int, chat: String?, picture: Bool) throws {
        let plan = AskModelSetup.plan(memoryGigabytes: AskMacSizes.reported(size), freeBytes: Self.roomy,
                                      downloaded: [], pictureInstalled: false)
        #expect(plan.chat?.id == chat, "\(size) GB")
        #expect(plan.uses?.id == chat)
        #expect(plan.picture == picture, "\(size) GB")
        #expect(plan.short == (chat == nil ? .memory : nil))
        let expected = (plan.chat?.downloadBytes ?? 0) + (picture ? AskPictureModelPlan.downloadBytes : 0)
        #expect(plan.bytes == expected)
    }

    @Test("A Mac too small for any model is told so, not offered one")
    func tooLittleMemory() {
        let plan = AskModelSetup.plan(memoryGigabytes: 4, freeBytes: Self.roomy, downloaded: [], pictureInstalled: false)
        #expect(plan.chat == nil && !plan.picture)
        #expect(plan.short == .memory)
    }

    @Test("A full disk steps down to a model that fits it, and says how much is missing when none does")
    func diskDecides() throws {
        let best = try #require(AskBuiltInModels.recommended(memoryGigabytes: AskMacSizes.reported(64)))
        // Room for the best but not the picture model beside it.
        let tight = best.downloadBytes + AskModelSetup.diskMargin + 1 * Self.gb
        let plan = AskModelSetup.plan(memoryGigabytes: AskMacSizes.reported(64), freeBytes: tight,
                                      downloaded: [], pictureInstalled: false)
        #expect(plan.chat == best)
        #expect(!plan.picture)
        // Room only for a smaller one: it steps down.
        let small = AskModelSetup.plan(memoryGigabytes: AskMacSizes.reported(64), freeBytes: 20 * Self.gb,
                                       downloaded: [], pictureInstalled: false)
        #expect(small.chat?.id == "gemma-4-26b-a4b")
        // Room for nothing.
        let none = AskModelSetup.plan(memoryGigabytes: AskMacSizes.reported(64), freeBytes: 1 * Self.gb,
                                      downloaded: [], pictureInstalled: false)
        #expect(none.chat == nil)
        guard case .disk(let needed) = none.short else {
            Issue.record("expected a disk shortfall, got \(String(describing: none.short))")
            return
        }
        #expect(needed > 0)
    }

    @Test("A chat model already on the Mac is kept; only the picture model is offered, when it fits")
    func keepsWhatItHas() {
        let plan = AskModelSetup.plan(memoryGigabytes: AskMacSizes.reported(64), freeBytes: Self.roomy,
                                      downloaded: ["qwen3.6-35b-a3b"], pictureInstalled: false)
        #expect(plan.chat == nil)
        #expect(plan.uses?.id == "qwen3.6-35b-a3b")
        #expect(plan.picture)
        let done = AskModelSetup.plan(memoryGigabytes: AskMacSizes.reported(64), freeBytes: Self.roomy,
                                      downloaded: ["qwen3.6-35b-a3b"], pictureInstalled: true)
        #expect(done.isEmpty)
    }

    @Test("The small models measured too weak are listed, marked, and never offered")
    func smallOnesAreTooWeak() throws {
        for id in ["gemma-4-e4b", "gemma-4-e2b", "qwen3.5-4b", "qwen3.5-9b"] {
            let choice = try #require(AskBuiltInModels.choice(id: id))
            #expect(choice.measured?.canDoAsksWork == false, "\(id)")
            #expect(AskModelSetup.listed(downloaded: []).contains(choice))
            #expect(!AskModelSetup.offerable(choice))
        }
    }

    @Test("A model too weak for Ask's work is never offered or recommended")
    func weakIsNotOffered() {
        for choice in AskBuiltInModels.ranked where choice.measured?.canDoAsksWork == false {
            #expect(!AskModelSetup.offerable(choice))
            for size in AskMacSizes.sold {
                #expect(AskBuiltInModels.recommended(memoryGigabytes: AskMacSizes.reported(size)) != choice)
            }
        }
    }

    @Test("Deleting the model in use falls back to the next downloaded one, then to nothing")
    func deleteFallsBack() {
        let both = ["qwen3.8-27b", "qwen3.6-35b-a3b"]
        #expect(AskBuiltInModels.resolve(chosen: "qwen3.8-27b", downloaded: both, memoryGigabytes: 68.7)?.id == "qwen3.8-27b")
        #expect(AskBuiltInModels.resolve(chosen: "qwen3.8-27b", downloaded: ["qwen3.6-35b-a3b"], memoryGigabytes: 68.7)?.id
                == "qwen3.6-35b-a3b")
        #expect(AskBuiltInModels.resolve(chosen: "qwen3.8-27b", downloaded: [], memoryGigabytes: 68.7) == nil)
    }

    // MARK: Walks

    @Test("A walk can plan for a Mac of another size, one sold, and nothing else")
    func walkMacSize() throws {
        #expect(try PlaytestSetup(fields: ["askMac": 8]).askMac == 8)
        #expect(try PlaytestSetup(fields: ["askMac": 8]).isEmpty == false)
        #expect(try PlaytestSetup(fields: [:]).askMac == nil)
        #expect(throws: PlaytestScriptError.self) { try PlaytestSetup(fields: ["askMac": 7]) }
        #expect(throws: PlaytestScriptError.self) { try PlaytestSetup(fields: ["askMac": true]) }
        #expect(throws: PlaytestScriptError.self) { try PlaytestSetup(fields: ["askMac": 8.5]) }
    }
}
