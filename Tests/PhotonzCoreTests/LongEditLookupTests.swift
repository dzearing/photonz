import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// What an edit of a long timeline has to look up again, read off clips where
/// they stand (`the-timeline-of-an-hour-long-edit-scrolls-zooms`).
@Suite("A long edit's lookups say what reading every clip would")
struct LongEditLookupTests {

    /// The twenty minute reference edit: three tracks, a transition every few cuts.
    static let document = ReferenceEdit.build(minutes: 20)

    @Test("Every transition is found once, in layer order, with the cut its two clips make")
    func transitions() throws {
        let document = Self.document
        let found = document.editPointTransitions()
        #expect(found.map(\.incoming) == document.layers.filter { $0.arrivalTransition != nil }.map(\.id))
        #expect(found.count > 20)
        for one in found {
            let cut = try #require(document.editPointCut(outgoing: one.outgoing, incoming: one.incoming))
            #expect(one.cut == cut)
            #expect(one.drawn == cut.drawnTransition)
            let drawn = try #require(one.drawn)
            #expect(one.spanMS == (cut.atMS - drawn.beforeMS)..<(cut.atMS + drawn.holdMS + drawn.afterMS))
        }
    }

    @Test("A moment is mid-transition from its first frame to the one before its last, and no longer")
    func moments() throws {
        let document = Self.document
        let first = try #require(document.editPointTransitions().first)
        #expect(!document.editPointMoments(atMS: first.spanMS.lowerBound - 1).contains { $0.onScreen == first.outgoing })
        #expect(document.editPointMoments(atMS: first.spanMS.lowerBound).contains { $0.onScreen == first.outgoing || $0.onScreen == first.incoming })
        #expect(document.editPointMoments(atMS: first.spanMS.upperBound - 1).contains { $0.onScreen == first.incoming || $0.onScreen == first.outgoing })
        #expect(!document.editPointMoments(atMS: first.spanMS.upperBound).contains { $0.onScreen == first.incoming })
    }

    @Test("A cut pulled apart stops being one, and a track that is not picture shows none")
    func cutsComeAndGo() throws {
        var document = Self.document
        let incoming = try #require(document.editPointTransitions().first?.incoming)
        document.updateLayer(id: incoming) { $0.time = $0.time.map { $0.moved(toInMS: $0.inMS + 100) } }
        #expect(!document.editPointTransitions().contains { $0.incoming == incoming })
        for index in document.layers.indices { document.layers[index].arrivalTransition = nil }
        #expect(!document.hasEditPointTransitions)
        #expect(document.editPointTransitions().isEmpty)
    }

    @Test("What the tree holds is what a walk of it finds")
    func facts() {
        var document = Self.document
        #expect(document.treeFacts.arrivals && document.hasEditPointTransitions)
        #expect(!document.treeFacts.mattes)
        document.layers[2].style.matte = .shape
        #expect(document.treeFacts.mattes)
        #expect(document.topLevelIndex.count == document.layers.count)
        #expect(document.topLevelIndex[document.layers[2].id] == 2)
    }

    @Test("Any layer in the tree, however deep, is found without a list of them all")
    func containsALayer() {
        var document = Self.document
        let inner = Layer(name: "Inner", content: .image(ImageRef(pixelSize: CGSize(width: 4, height: 4))),
                          frame: CGRect(x: 0, y: 0, width: 4, height: 4))
        func group(_ child: Layer) -> Layer {
            Layer(name: "Box", content: .group(GroupContent(children: [child])), frame: .zero)
        }
        document.layers.append(group(group(inner)))
        #expect(document.containsLayer { $0.id == inner.id })
        #expect(!document.containsLayer { $0.name == "Nobody" })
    }

    @Test("Tracks laid out off the clips in place are the tracks a save and a reopening lay out")
    func layout() throws {
        let document = Self.document
        let again = try JSONDecoder().decode(PhotonzDocument.self, from: JSONEncoder().encode(document))
        #expect(document.timelineTracks == again.timelineTracks)
        for track in document.timelineTracks {
            #expect(document.clipIDs(onTrack: track.id) == again.clipIDs(onTrack: track.id))
            for id in document.clipIDs(onTrack: track.id) { #expect(document.trackID(ofClip: id) == track.id) }
        }
    }

    @Test("A clip read in place is the clip, and one an edit left alone is told from one it did not")
    func clipsInPlace() throws {
        let before = Self.document
        var after = before
        let edited = before.layers[7].id, alone = before.layers[8].id
        after.updateLayer(id: edited) { $0.name = "Renamed" }
        #expect(after.readingClip(edited, \.name) == "Renamed")
        #expect(after.readingClip(alone, \.name) == before.layers[8].name)
        #expect(after.readingClip(UUID(), \.name) == nil)
        #expect(!after.clipIsUnchanged(edited, since: before))
        #expect(after.clipIsUnchanged(alone, since: before))
        #expect(!after.clipIsUnchanged(UUID(), since: before))
    }

    @Test("A layer by its path is the one there, at the top, inside a group, and nowhere")
    func byPath() throws {
        var document = Self.document
        let inner = Layer(name: "Inner", content: .image(ImageRef(pixelSize: CGSize(width: 4, height: 4))),
                          frame: CGRect(x: 0, y: 0, width: 4, height: 4))
        document.layers.append(Layer(name: "Box", content: .group(GroupContent(children: [inner])), frame: .zero))
        let last = document.layers.count - 1
        #expect(document.layer(atPath: [last, 0])?.id == inner.id)
        #expect(document.layer(atPath: [last])?.name == "Box")
        #expect(document.layer(atPath: []) == nil)
        #expect(document.layer(atPath: [last, 1]) == nil)
        #expect(document.layer(atPath: [0, 0]) == nil)
    }

    @Test("What a moment hides is what is off screen then, a group's parts with it")
    func hidden() {
        let document = Self.document
        for moment in [0, 61_000, 600_500] {
            let shown = document.hidingWhatIsOffScreen(atTimeMS: moment)
            for (layer, now) in zip(document.layers, shown.layers) {
                #expect(now.isVisible == (layer.isVisible && layer.isOnScreen(atTimeMS: moment)))
                for (part, partNow) in zip(layer.children, now.children) where now.isVisible {
                    #expect(partNow.isVisible == (part.isVisible && part.isOnScreen(atTimeMS: moment)))
                }
            }
        }
    }

    @Test("The rings of clips pushed in past the frame are the ones asked of each clip by itself")
    func rings() throws {
        var document = Self.document
        let clip = try #require(document.layers.first { $0.takesAReframe && $0.time?.contains(ms: 2000) == true })
        document.punchIn(layerID: clip.id, onRegion: CGRect(x: 40, y: 40, width: 300, height: 200), atTimeMS: 2000)
        let shown = document.posedForCanvas(atTimeMS: 2000).hidingWhatIsOffScreen(atTimeMS: 2000)
        var one: [UUID: CGRect] = [:]
        for layer in document.allLayers where layer.takesAReframe {
            guard let posed = shown.layer(id: layer.id) else { continue }
            one[layer.id] = document.frameRing(layerID: layer.id, drawnBox: posed.drawnBounds())
        }
        #expect(document.frameRings(shown: shown) == one)
        #expect(one[clip.id] != nil)
    }

    @Test("The bars are kept with the document and go with any change to a layer")
    func bars() throws {
        var document = Self.document
        let was = document.motionStrip()
        let id = try #require(was.first { $0.bar != nil }?.layerID)
        document.updateLayer(id: id) { $0.time = $0.time.map { $0.moved(toInMS: $0.inMS + 1234) } }
        let now = document.motionStrip()
        #expect(now.count == was.count)
        #expect(now.first { $0.layerID == id }?.bar?.inMS == (was.first { $0.layerID == id }?.bar?.inMS ?? 0) + 1234)
    }
}

extension LongEditLookupTests {

    @Test("What an edit asks next is kept where it was worked out, whoever worked it out")
    func workedOutAhead() async {
        var document = Self.document
        let id = document.layers[4].id
        document.updateLayer(id: id) { $0.name = "Changed" }
        #expect(document.derived.keptAudioMix == nil)
        let copy = document
        await Task.detached { copy.workOutWhatAnEditAsksNext() }.value
        #expect(document.derived.keptAudioMix != nil)
        var fresh = document
        fresh.layers = Array(document.layers)
        #expect(document.audioMix() == fresh.audioMix())
        #expect(document.motionStrip() == fresh.motionStrip())
    }
}

extension LongEditLookupTests {

    @Test("What one walk of the tree notes is what asking every layer says")
    func everyFact() throws {
        var document = Self.document
        func check(_ d: PhotonzDocument) {
            let all = d.allLayers
            #expect(d.hasMotionBlur == all.contains { $0.style.motionBlur?.smears == true })
            #expect(d.hasCaptions == all.contains(where: \.isCaption))
            #expect(d.treeFacts.measures == all.contains(where: \.isMeasurement))
            #expect(d.holdsMainInPicture == all.contains(where: \.isMainComponent))
            #expect(d.holdsComponentInstance == all.contains(where: \.isComponentInstance))
            #expect(d.panelFacts.measurement == all.contains { $0.measure != nil })
            #expect(d.panelFacts.component == all.contains(where: \.isComponentRoot))
            #expect(d.panelFacts.container == all.contains(where: \.isGroup))
            #expect(d.panelFacts.frame == all.contains(where: \.isFrame))
        }
        check(document)
        let inner = Layer(name: "Inner", content: .image(ImageRef(pixelSize: CGSize(width: 4, height: 4))),
                          frame: CGRect(x: 0, y: 0, width: 4, height: 4))
        var main = GroupContent(children: [inner])
        main.componentID = UUID()
        document.layers.append(Layer(name: "Main", content: .group(main), frame: .zero))
        #expect(document.holdsMainInPicture)
        check(document)
        var copy = GroupContent(children: [])
        copy.instanceOf = main.componentID
        let holder = GroupContent(children: [Layer(name: "Copy", content: .group(copy), frame: .zero)])
        document.layers.append(Layer(name: "Holder", content: .group(holder), frame: .zero))
        #expect(document.holdsComponentInstance)
        check(document)
        var size = GroupContent(children: [])
        size.measuresSize = true
        document.layers.append(Layer(name: "Size", content: .group(size), frame: .zero))
        #expect(document.treeFacts.measures)
        check(document)
    }

    @Test("A closed title shows rows only for a part picked inside it")
    func childRows() throws {
        let document = Self.document
        let title = try #require(document.layers.first { $0.isGroup && !document.timelineChildIDs(of: $0.id).isEmpty })
        let part = try #require(document.timelineChildIDs(of: title.id).first)
        let other = try #require(document.layers.first { !$0.isGroup })
        #expect(document.timelineChildRows(of: title.id, open: [], picked: nil).isEmpty)
        #expect(document.timelineChildRows(of: title.id, open: [], picked: other.id).isEmpty)
        #expect(document.timelineChildRows(of: title.id, open: [], picked: title.id).isEmpty)
        #expect(document.timelineChildRows(of: title.id, open: [], picked: part).map(\.layerID) == [part])
        #expect(document.timelineChildRows(of: title.id, open: [title.id], picked: nil).map(\.layerID)
                == document.timelineChildIDs(of: title.id))
    }
}
