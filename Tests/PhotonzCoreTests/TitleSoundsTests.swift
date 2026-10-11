import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// Titles can play a soft whoosh and tick as they build (task
/// `titles-can-play-a-soft-whoosh-and-tick-as-they-b`,
/// `docs/design/video-titles-polish.md`, step 6).
///
/// Written before the sounds. A switch on a placed title lays one bar of sound
/// under it: a whoosh as its headline comes in and a tick as each small accent
/// lands, timed from the title's own design. The bar belongs to the title, so
/// whatever happens to the title happens to it.
@Suite("Titles play a whoosh and a tick as they build")
struct TitleSoundsTests {

    static let canvas = CGSize(width: 1920, height: 1080)

    static func placed(_ preset: BuiltInTitle, atMS ms: Int = 2_000) throws -> (PhotonzDocument, UUID) {
        var doc = TitleRestyleTests.tenSeconds()
        let landed = doc.insertTitle(preset, atTimeMS: ms)
        let inserted = try #require(landed)
        return (doc, inserted.layerID)
    }

    static func sounds(_ doc: PhotonzDocument) -> [Layer] {
        doc.allLayers.filter { $0.titleSound != nil }
    }

    static func on(_ doc: inout PhotonzDocument, _ id: UUID) {
        let was = doc
        let changed = doc.setTitleSounds(layerID: id, on: true)
        #expect(changed)
        doc.keepTitleSoundsInStep(since: was)
    }

    // MARK: The score

    @Test("A title lands with its sounds off")
    func offByDefault() throws {
        let (doc, id) = try Self.placed(.keynote)
        #expect(doc.titleRecipe(layerID: id)?.playsSounds == false)
        #expect(Self.sounds(doc).isEmpty)
    }

    @Test("The whoosh starts as the headline starts coming in, and lasts about as long")
    func whooshOnTheHeadline() throws {
        let (doc, id) = try Self.placed(.keynote)
        let title = try #require(doc.layer(id: id))
        let recipe = try #require(doc.titleRecipe(layerID: id))
        let score = try #require(TitleSoundScore(title: title, recipe: recipe, canvasSize: Self.canvas))
        let headline = try #require(recipe.compiled.parts.first { $0.role == .headline }?.in)
        let whoosh = try #require(score.cues.first { $0.kind == .whoosh })
        #expect(whoosh.atMS == headline.delayMS)
        #expect(TitleSoundScore.whooshLengthRange.contains(whoosh.lengthMS))
        #expect(score.cues.filter { $0.kind == .whoosh }.count == 1)
    }

    @Test("A small accent ticks as it lands; a big one does not")
    func ticksOnSmallAccents() throws {
        // Editorial Serif draws a rule on under its words.
        let (doc, id) = try Self.placed(.editorial)
        let title = try #require(doc.layer(id: id))
        let recipe = try #require(doc.titleRecipe(layerID: id))
        let score = try #require(TitleSoundScore(title: title, recipe: recipe, canvasSize: Self.canvas))
        let rule = try #require(recipe.compiled.parts.first { $0.path == "Rule" }?.in)
        let tick = try #require(score.cues.first { $0.kind == .tick })
        #expect(tick.atMS > rule.delayMS)
        #expect(tick.atMS <= rule.delayMS + rule.lengthMS)

        // Light Leak's accents are washes of light across the frame.
        let (leakDoc, leakID) = try Self.placed(.lightLeak)
        let leak = try #require(leakDoc.layer(id: leakID))
        let leakRecipe = try #require(leakDoc.titleRecipe(layerID: leakID))
        let leakScore = try #require(TitleSoundScore(title: leak, recipe: leakRecipe, canvasSize: Self.canvas))
        #expect(!leakScore.cues.contains { $0.kind == .tick })
    }

    @Test("Every title in the set has a whoosh, no more than three ticks, and none bunched together",
          arguments: BuiltInTitle.allCases.filter { !$0.isRetired })
    func everyTitleHasAScore(_ preset: BuiltInTitle) throws {
        let (doc, id) = try Self.placed(preset)
        let title = try #require(doc.layer(id: id))
        let recipe = try #require(doc.titleRecipe(layerID: id))
        let score = try #require(TitleSoundScore(title: title, recipe: recipe, canvasSize: Self.canvas))
        #expect(score.cues.filter { $0.kind == .whoosh }.count == 1)
        let ticks = score.cues.filter { $0.kind == .tick }.map(\.atMS).sorted()
        #expect(ticks.count <= TitleSoundScore.mostTicks)
        for (a, b) in zip(ticks, ticks.dropFirst()) { #expect(b - a >= TitleSoundScore.tickSpacingMS) }
        #expect(score.lengthMS > 0)
    }

    @Test("Punchy is a shorter, brighter whoosh than Calm, and a different sound")
    func energyChangesTheWhoosh() throws {
        let (doc, id) = try Self.placed(.keynote)
        let title = try #require(doc.layer(id: id))
        var recipe = try #require(doc.titleRecipe(layerID: id))
        recipe.energy = .calm
        let calm = try #require(TitleSoundScore(title: title, recipe: recipe, canvasSize: Self.canvas))
        recipe.energy = .punchy
        let punchy = try #require(TitleSoundScore(title: title, recipe: recipe, canvasSize: Self.canvas))
        let calmWhoosh = try #require(calm.cues.first { $0.kind == .whoosh })
        let punchyWhoosh = try #require(punchy.cues.first { $0.kind == .whoosh })
        #expect(punchyWhoosh.lengthMS < calmWhoosh.lengthMS)
        #expect(punchy.energy == .punchy)
        #expect(punchy.soundID != calm.soundID)
    }

    @Test("The same score is the same sound, every time it is worked out")
    func stableIdentity() throws {
        let (doc, id) = try Self.placed(.pill)
        let title = try #require(doc.layer(id: id))
        let recipe = try #require(doc.titleRecipe(layerID: id))
        let a = try #require(TitleSoundScore(title: title, recipe: recipe, canvasSize: Self.canvas))
        let b = try #require(TitleSoundScore(title: title, recipe: recipe, canvasSize: Self.canvas))
        #expect(a.soundID == b.soundID)
        #expect(a.soundRef == SoundRef(id: a.soundID, durationMS: a.lengthMS))
        let decoded = try JSONDecoder().decode(TitleSoundScore.self, from: JSONEncoder().encode(a))
        #expect(decoded == a)
        #expect(decoded.soundID == a.soundID)
    }

    // MARK: On the timeline

    @Test("Sounds on lays one bar under the title, from its start, playing the score")
    func switchOnLaysABar() throws {
        var (doc, id) = try Self.placed(.keynote)
        Self.on(&doc, id)
        let bars = Self.sounds(doc)
        #expect(bars.count == 1)
        let bar = try #require(bars.first)
        let title = try #require(doc.layer(id: id))
        let link = try #require(bar.titleSound)
        #expect(link.titleID == id)
        #expect(bar.time?.inMS == title.time?.inMS)
        #expect(bar.sound == link.score.soundRef)
        #expect(bar.name == TitleSoundScore.barName)
        // ...and it is heard.
        #expect(doc.audioMix().contains { $0.layerID == bar.id && $0.startMS == 2_000 })
    }

    @Test("Sounds off takes the bar away again")
    func switchOffTakesItAway() throws {
        var (doc, id) = try Self.placed(.keynote)
        Self.on(&doc, id)
        let was = doc
        let changed = doc.setTitleSounds(layerID: id, on: false)
        #expect(changed)
        doc.keepTitleSoundsInStep(since: was)
        #expect(Self.sounds(doc).isEmpty)
        #expect(doc.titleRecipe(layerID: id)?.playsSounds == false)
    }

    @Test("Sliding the title carries its sounds")
    func slideCarries() throws {
        var (doc, id) = try Self.placed(.keynote)
        Self.on(&doc, id)
        let was = doc
        let changed = doc.moveClip(id, toInMS: 5_000)
        #expect(changed)
        doc.keepTitleSoundsInStep(since: was)
        let bar = try #require(Self.sounds(doc).first)
        #expect(bar.time?.inMS == 5_000)
        #expect(Self.sounds(doc).count == 1)
    }

    @Test("Trimming the title short trims its sounds with it; its start keeps them on the beat")
    func trimCarries() throws {
        var (doc, id) = try Self.placed(.keynote)
        Self.on(&doc, id)
        var was = doc
        let changed = doc.moveLayerEnd(id, toMS: 2_300)
        #expect(changed)
        doc.keepTitleSoundsInStep(since: was)
        let short = try #require(Self.sounds(doc).first)
        #expect((short.time?.outMS ?? .max) <= 2_300)

        was = doc
        let longer = doc.moveLayerEnd(id, toMS: 8_000)
        #expect(longer)
        let later = doc.moveLayerStart(id, toMS: 3_000)
        #expect(later)
        doc.keepTitleSoundsInStep(since: was)
        let moved = try #require(Self.sounds(doc).first)
        #expect(moved.time?.inMS == 3_000)
    }

    @Test("A sound bar dragged off on its own goes back under its title")
    func strayBarComesBack() throws {
        var (doc, id) = try Self.placed(.keynote)
        Self.on(&doc, id)
        let bar = try #require(Self.sounds(doc).first)
        let was = doc
        let changed = doc.moveClip(bar.id, toInMS: 7_000)
        #expect(changed)
        doc.keepTitleSoundsInStep(since: was)
        #expect(Self.sounds(doc).first?.time?.inMS == 2_000)
    }

    @Test("A restyle at another energy changes the sound the bar plays, on the same bar")
    func restyleRescores() throws {
        var (doc, id) = try Self.placed(.keynote)
        Self.on(&doc, id)
        let before = try #require(Self.sounds(doc).first)
        let was = doc
        let restyled = doc.restyleTitle(layerID: id) { $0.energy = .punchy }
        #expect(restyled)
        doc.keepTitleSoundsInStep(since: was)
        let after = try #require(Self.sounds(doc).first)
        #expect(after.id == before.id)
        #expect(after.sound != before.sound)
        #expect(doc.titleRecipe(layerID: id)?.playsSounds == true)
    }

    @Test("Deleting the title deletes its sounds")
    func deleteTitleDeletesSounds() throws {
        var (doc, id) = try Self.placed(.keynote)
        Self.on(&doc, id)
        let was = doc
        doc.removeLayers(ids: [id])
        doc.keepTitleSoundsInStep(since: was)
        #expect(Self.sounds(doc).isEmpty)
    }

    @Test("Deleting the sound bar by hand turns the title's sounds off rather than putting it back")
    func deleteBarTurnsOff() throws {
        var (doc, id) = try Self.placed(.keynote)
        Self.on(&doc, id)
        let bar = try #require(Self.sounds(doc).first)
        let was = doc
        doc.removeLayers(ids: [bar.id])
        doc.keepTitleSoundsInStep(since: was)
        #expect(Self.sounds(doc).isEmpty)
        #expect(doc.titleRecipe(layerID: id)?.playsSounds == false)
    }

    @Test("A copy of the title gets sounds of its own, and copied sounds never double up")
    func copiesGetTheirOwn() throws {
        var (doc, id) = try Self.placed(.keynote)
        Self.on(&doc, id)
        let title = try #require(doc.layer(id: id))
        let bar = try #require(Self.sounds(doc).first)
        let was = doc
        var copy = title.duplicated()
        copy.time = title.time?.moved(toInMS: 6_000)
        let copyID = copy.id
        doc.addLayer(copy)
        doc.addLayer(bar.duplicated())
        doc.keepTitleSoundsInStep(since: was)
        let bars = Self.sounds(doc)
        #expect(bars.count == 2)
        #expect(Set(bars.compactMap { $0.titleSound?.titleID }) == [id, copyID])
        #expect(bars.first { $0.titleSound?.titleID == copyID }?.time?.inMS == 6_000)
    }

    @Test("A document with no title sounds is left exactly as it was")
    func untouchedOtherwise() throws {
        let (doc, _) = try Self.placed(.keynote)
        var after = doc
        after.keepTitleSoundsInStep(since: doc)
        #expect(after == doc)
    }

    @Test("The switch and the bar survive a save")
    func survivesASave() throws {
        var (doc, id) = try Self.placed(.keynote)
        Self.on(&doc, id)
        let data = try JSONEncoder().encode(doc)
        let read = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(read.titleRecipe(layerID: id)?.playsSounds == true)
        #expect(Self.sounds(read).first?.titleSound == Self.sounds(doc).first?.titleSound)
    }
}
