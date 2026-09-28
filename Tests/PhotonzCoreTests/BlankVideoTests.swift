import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// **A new video starts from an empty timeline**
/// (`a-new-video-starts-from-an-empty-timeline`, `video.html` onboarding step
/// 1, New, empty: a blank 1920 x 1080 timeline with an empty V1 and an empty
/// Audio track).
@Suite("Blank video")
struct BlankVideoTests {

    @Test("Next has it at its defaults, and Current never offers it")
    func nextOnly() {
        #expect(FeatureCatalog.defaultSettings(for: .next).isEnabled(FeatureCatalog.blankVideoFlag))
        #expect(!FeatureCatalog.flags(for: .current).contains { $0.name == FeatureCatalog.blankVideoFlag })
    }

    // MARK: - The sizes offered

    @Test("The sheet opens on 1920 by 1080, the mock's blank project")
    func defaultIsFullHD() {
        #expect(BlankVideo.defaultPreset.size == CGSize(width: 1920, height: 1080))
        #expect(BlankVideo.presets.contains(BlankVideo.defaultPreset))
    }

    @Test("A few sizes, not a catalog, each with a unique id and even sides")
    func presetsAreUsable() {
        #expect(BlankVideo.presets.count >= 3)
        #expect(BlankVideo.presets.count <= 6)
        let ids = BlankVideo.presets.map(\.id)
        #expect(Set(ids).count == ids.count)
        for preset in BlankVideo.presets {
            #expect(!preset.title.isEmpty)
            #expect(BlankVideo.normalized(preset.size) == preset.size)
        }
    }

    @Test("A typed size comes out whole, even and inside the range a movie can be written at")
    func typedSizesAreMadeSafe() {
        #expect(BlankVideo.normalized(CGSize(width: 1281, height: 719.4)) == CGSize(width: 1282, height: 720))
        #expect(BlankVideo.normalized(CGSize(width: 0, height: -5)) == CGSize(width: 2, height: 2))
        #expect(BlankVideo.normalized(CGSize(width: 99_999, height: CGFloat.nan)).width == BlankVideo.maximumSide)
        #expect(BlankVideo.isValid(CGSize(width: 1920, height: 1080)))
        #expect(!BlankVideo.isValid(CGSize(width: 1921, height: 1080)))
    }

    // MARK: - The length offered

    @Test("It opens on ten seconds, and a typed length is kept between a second and an hour")
    func lengths() {
        #expect(BlankVideo.defaultLengthSeconds == 10)
        #expect(BlankVideo.lengthMS(seconds: 15) == 15_000)
        #expect(BlankVideo.lengthMS(seconds: 2.5) == 2_500)
        #expect(BlankVideo.lengthMS(seconds: 0) == 1_000)
        #expect(BlankVideo.lengthMS(seconds: .nan) == 1_000)
        #expect(BlankVideo.lengthMS(seconds: 100_000) == 3_600_000)
        #expect(BlankVideo.isValidLength(seconds: 10))
        #expect(!BlankVideo.isValidLength(seconds: 0))
        #expect(!BlankVideo.isValidLength(seconds: 5_000))
    }

    // MARK: - The document it makes

    @Test("An empty video is the size and length chosen, with nothing on it")
    func emptyVideoHoldsNothing() {
        let doc = PhotonzDocument.emptyVideo(size: CGSize(width: 1920, height: 1080), lengthMS: 10_000)
        #expect(doc.canvasSize == CGSize(width: 1920, height: 1080))
        #expect(doc.durationMS == 10_000)
        #expect(doc.hasTime)
        #expect(doc.layers.isEmpty)
        #expect(doc.media.isEmpty)
    }

    @Test("Its timeline is an empty V1 over an empty Audio track")
    func emptyVideoHasV1AndAudio() {
        let doc = PhotonzDocument.emptyVideo(size: CGSize(width: 1920, height: 1080), lengthMS: 10_000)
        let tracks = doc.timelineTracks
        #expect(tracks.map(\.name) == ["V1", "Audio"])
        #expect(tracks.map(\.kind) == [.video, .audio])
        for track in tracks { #expect(doc.clipIDs(onTrack: track.id).isEmpty) }
    }

    @Test("It opens in Edit, on its tracks: there is nothing in it to watch yet")
    func opensOnItsTracks() {
        let doc = PhotonzDocument.emptyVideo(size: CGSize(width: 1920, height: 1080), lengthMS: 10_000)
        #expect(ViewEditMode.opening(doc) == .edit)
    }

    @Test("The two tracks are the person's, not left behind: nothing tidies them away")
    func tracksAreKept() {
        var doc = PhotonzDocument.emptyVideo(size: CGSize(width: 1920, height: 1080), lengthMS: 10_000)
        let before = doc
        let dropped = doc.dropTracksEmptied(since: before)
        #expect(!dropped)
        #expect(doc.timelineTracks.count == 2)
    }

    @Test("It saves and opens again as the same empty video")
    func roundTrips() throws {
        let doc = PhotonzDocument.emptyVideo(size: CGSize(width: 1080, height: 1920), lengthMS: 6_000)
        let data = try JSONEncoder().encode(doc)
        let back = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(back == doc)
        #expect(back.timelineTracks.map(\.name) == ["V1", "Audio"])
    }

    // MARK: - The first clip

    static func recording(seconds: Int) -> Layer {
        ClipLandingTests.clip(MovieRef(pixelSize: CGSize(width: 1920, height: 1080), durationMS: seconds * 1000),
                              name: "intro")
    }

    @Test("A recording dropped on the empty V1 lands there, and the length grows to hold it")
    func firstClipLandsOnV1AndGrowsTheLength() throws {
        var doc = PhotonzDocument.emptyVideo(size: CGSize(width: 1920, height: 1080), lengthMS: 5_000)
        let v1 = try #require(doc.timelineTracks.first)
        let clip = Self.recording(seconds: 8)
        let landing = doc.clipLanding(kind: .video, lengthMS: 8_000, atMS: 0, over: .onto(v1.id), edit: .overwrite)
        #expect(landing.target == .onto(v1.id))
        #expect(landing.allowed)
        let landed = doc.land(clip, at: landing)
        let id = try #require(landed)
        #expect(doc.clipIDs(onTrack: v1.id) == [id])
        #expect(doc.durationMS == 8_000)
        #expect(doc.timelineTracks.map(\.name) == ["V1", "Audio"])
    }

    @Test("A clip shorter than the video leaves the length the person chose")
    func shortClipKeepsTheLength() throws {
        var doc = PhotonzDocument.emptyVideo(size: CGSize(width: 1920, height: 1080), lengthMS: 10_000)
        let v1 = try #require(doc.timelineTracks.first)
        let landing = doc.clipLanding(kind: .video, lengthMS: 4_000, atMS: 1_000, over: .onto(v1.id), edit: .overwrite)
        _ = doc.land(Self.recording(seconds: 4), at: landing)
        #expect(doc.durationMS == 10_000)
    }
}
