import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A logo or a picture brought into a video's Library (`video-title-wt.html`,
/// steps 6 to 8: "Flat art lives here beside your footage: svg, png, a logo").
/// It comes in like any other media, waits on the shelf, and goes onto the
/// picture or a track as a layer with an in and an out.
struct LibraryPictureTests {

    private let logo = ImageRef(pixelSize: CGSize(width: 480, height: 192))
    private let photo = ImageRef(pixelSize: CGSize(width: 4032, height: 3024))
    private let music = SoundRef(durationMS: 14_000)

    private func doc() -> PhotonzDocument {
        var document = PhotonzDocument(canvasSize: CGSize(width: 1280, height: 800), layers: [])
        document.durationMS = 8_000
        return document
    }

    private func picture(_ ref: ImageRef, _ name: String) -> DocumentMediaSource {
        DocumentMediaSource(media: .picture(ref), name: name)
    }

    // MARK: - Which files are pictures

    @Test func picturesAreReadOffTheirNames() {
        for name in ["logo.png", "photo.JPG", "shot.jpeg", "IMG_0001.heic", "scan.tiff", "art.heif"] {
            #expect(MediaFiles.isPicture(URL(fileURLWithPath: "/tmp/\(name)")), "\(name)")
        }
        for name in ["clip.mov", "music.wav", "notes.txt", "logo.svg", "doc.photonz"] {
            #expect(!MediaFiles.isPicture(URL(fileURLWithPath: "/tmp/\(name)")), "\(name)")
        }
    }

    @Test func anSVGIsAVectorAndNotAPicture() {
        #expect(MediaFiles.isVector(URL(fileURLWithPath: "/tmp/Logo.svg")))
        #expect(MediaFiles.isVector(URL(fileURLWithPath: "/tmp/Logo.SVG")))
        // A compressed SVG is not one macOS can draw, so it is not taken.
        #expect(!MediaFiles.isVector(URL(fileURLWithPath: "/tmp/Logo.svgz")))
        #expect(!MediaFiles.isVector(URL(fileURLWithPath: "/tmp/Logo.png")))
        // Neither is a sound or a recording, so nothing that asks that changes.
        #expect(MediaFiles.kind(of: URL(fileURLWithPath: "/tmp/Logo.svg")) == nil)
        #expect(MediaFiles.kind(of: URL(fileURLWithPath: "/tmp/Logo.png")) == nil)
    }

    // MARK: - On the shelf

    @Test func aPictureBroughtInIsATileOnTheShelfAndNothingElse() {
        var document = doc()
        let outcome = document.bringIntoLibrary([picture(logo, "Acme Logo.png")])
        #expect(document.layers.isEmpty)
        let tiles = DocumentMedia.items(in: document)
        #expect(tiles.map(\.name) == ["Acme Logo.png"])
        #expect(tiles.first?.image == logo)
        #expect(tiles.first?.uses == 0)
        #expect(tiles.first?.detail == "not used yet")
        #expect(outcome.added == ["Acme Logo.png"])
        #expect(outcome.firstNewID == logo.id)
        #expect(outcome.detail == "Acme Logo.png is in the Library")
    }

    /// A picture is not a recording or a sound: the clip list never shows it.
    @Test func aPictureIsNotAClip() {
        var document = doc()
        document.bringIntoLibrary([picture(logo, "Acme Logo.png"),
                                   DocumentMediaSource(media: .sound(music), name: "music.wav")])
        #expect(DocumentMedia.clips(in: document).map(\.name) == ["music.wav"])
        #expect(DocumentMedia.items(in: document).map(\.name) == ["Acme Logo.png"])
    }

    @Test func thePictureBroughtInLastIsTheFirstTile() {
        var document = doc()
        document.bringIntoLibrary([picture(logo, "Acme Logo.png")])
        document.bringIntoLibrary([picture(photo, "Beach.heic")])
        #expect(DocumentMedia.items(in: document).map(\.name) == ["Beach.heic", "Acme Logo.png"])
    }

    @Test func theSamePictureTwiceIsOneTile() {
        var document = doc()
        document.bringIntoLibrary([picture(logo, "Acme Logo.png")])
        let again = document.bringIntoLibrary([picture(logo, "Acme Logo.png")])
        #expect(DocumentMedia.items(in: document).count == 1)
        #expect(again.added.isEmpty)
        #expect(again.alreadyThere == ["Acme Logo.png"])
        #expect(again.revealID == logo.id)
    }

    /// Put down, it is still the one tile, still under the name it came in
    /// with, now counting the layer that draws it.
    @Test func placingAShelvedPictureKeepsItsTileAndItsName() {
        var document = doc()
        document.bringIntoLibrary([picture(logo, "Acme Logo.png")])
        document.addLayer(Layer(name: "Acme Logo", content: .image(logo),
                                frame: CGRect(x: 10, y: 10, width: 240, height: 96)))
        let tiles = DocumentMedia.items(in: document)
        #expect(tiles.count == 1)
        #expect(tiles.first?.name == "Acme Logo.png")
        #expect(tiles.first?.uses == 1)
    }

    /// The tile says the file; the layer it puts down says the picture, the
    /// way a picture dropped from the Finder is named.
    @Test func aShelvedPictureIsPutDownUnderItsNameWithoutTheExtension() {
        #expect(DocumentMediaItem(image: logo, name: "Acme Logo.png", uses: 0).layerName == "Acme Logo")
        #expect(DocumentMediaItem(image: logo, name: "Beach.HEIC", uses: 0).layerName == "Beach")
        // A caption that only looks like it has an extension keeps all of it.
        #expect(DocumentMediaItem(image: logo, name: "Screenshot 16.22.12", uses: 1).layerName
                == "Screenshot 16.22.12")
    }

    /// ...and once every layer drawing it is gone the tile stays: the shelf is
    /// what the document can place, not only what it is placing.
    @Test func aShelvedPictureOutlivesItsLastLayer() {
        var document = doc()
        document.bringIntoLibrary([picture(logo, "Acme Logo.png")])
        let layer = Layer(name: "Acme Logo", content: .image(logo),
                          frame: CGRect(x: 10, y: 10, width: 240, height: 96))
        document.addLayer(layer)
        _ = document.removeLayer(id: layer.id)
        #expect(DocumentMedia.items(in: document).map(\.uses) == [0])
    }

    /// The picture's pixels are in the saved package, not out on disk, so a
    /// project's table of files to find again never lists one.
    @Test func aPictureIsNoFileForAProjectToFindAgain() {
        var document = doc()
        document.bringIntoLibrary([picture(logo, "Acme Logo.png"),
                                   DocumentMediaSource(media: .sound(music), name: "music.wav")])
        #expect(ProjectMedia.references(in: document) == [.sound(music)])
    }

    @Test func aDocumentHoldingAShelvedPictureSurvivesSaving() throws {
        var document = doc()
        document.bringIntoLibrary([picture(logo, "Acme Logo.png")])
        let data = try JSONEncoder().encode(document)
        let back = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(back.media == document.media)
        #expect(DocumentMedia.items(in: back).map(\.name) == ["Acme Logo.png"])
    }

    @Test func everyPictureHeldOnTheShelfIsListed() {
        var document = doc()
        document.bringIntoLibrary([picture(logo, "Acme Logo.png"),
                                   DocumentMediaSource(media: .sound(music), name: "music.wav")])
        #expect(DocumentMedia.shelvedPictures(in: document) == [logo])
    }

    // MARK: - A tile's two lines

    /// `video-title-wt.html`, the Media shelf: an art tile is its name over
    /// its kind ("Sparkle / svg"), so a logo reads as a logo and the shelf
    /// says which ones are drawings that stay sharp at any size.
    @Test func aPictureFileIsCaptionedWithItsNameOverItsKind() throws {
        var document = doc()
        let sparkle = ImageRef(pixelSize: CGSize(width: 64, height: 64))
        document.bringIntoLibrary([picture(logo, "Acme Logo.png"), picture(sparkle, "Sparkle.SVG")])
        let tiles = DocumentMedia.items(in: document)
        let art = try #require(tiles.first { $0.image == sparkle })
        #expect(art.caption == "Sparkle")
        #expect(art.kind == "svg")
        let png = try #require(tiles.first { $0.image == logo })
        #expect(png.caption == "Acme Logo")
        #expect(png.kind == "png")
        // The name the file came in under is kept: it is what a notice says.
        #expect(png.name == "Acme Logo.png")
        #expect(DocumentMedia.entries(in: document).map(\.name) == ["Sparkle", "Acme Logo"])
        #expect(LibraryTileCaption.meta(of: art) == "svg")
    }

    /// Placed on the picture it is still the logo: the tile keeps the file's
    /// caption and kind once something draws it.
    @Test func aPlacedPictureFileKeepsItsKind() throws {
        var document = doc()
        document.bringIntoLibrary([picture(logo, "Acme Logo.png")])
        let landing = document.titleLanding(lengthMS: PictureClip.lengthMS, atMS: 0, over: nil)
        #expect(document.landPicture(logo, named: "Acme Logo", at: landing) != nil)
        let tile = try #require(DocumentMedia.items(in: document).first)
        #expect(tile.uses == 1)
        #expect(tile.kind == "png")
        #expect(tile.caption == "Acme Logo")
    }

    /// A picture that came in as a layer (a screenshot, a paste) has no file
    /// and so no kind: its tile still says how big it is.
    @Test func aPictureWithNoFileSaysItsSize() throws {
        var document = doc()
        document.addLayer(Layer(name: "Screenshot 16.22.12", content: .image(photo),
                                frame: CGRect(x: 0, y: 0, width: 400, height: 300)))
        let tile = try #require(DocumentMedia.items(in: document).first)
        #expect(tile.kind == nil)
        #expect(tile.caption == "Screenshot 16.22.12")
        #expect(LibraryTileCaption.meta(of: tile) == "4032 × 3024")
    }

    /// An SVG is put down named like any picture file: without its extension.
    @Test func anSVGIsPlacedUnderItsNameAlone() {
        let item = DocumentMediaItem(image: logo, name: "Acme Logo.svg", uses: 0, kind: "svg")
        #expect(item.layerName == "Acme Logo")
    }

    // MARK: - Onto a track

    /// A still is laid over the picture the way a title is: on the track under
    /// the pointer when it is free, for five seconds (Premiere's still length),
    /// sized to fit the frame and centred.
    @Test func aPictureLetGoOnTheTimelineLandsForFiveSeconds() throws {
        var document = doc()
        let landing = document.titleLanding(lengthMS: PictureClip.lengthMS, atMS: 2_000, over: nil)
        let landed = document.landPicture(logo, named: "Acme Logo", at: landing)
        let id = try #require(landed)
        let layer = try #require(document.layer(id: id))
        #expect(layer.name == "Acme Logo")
        #expect(layer.time?.inMS == 2_000)
        #expect(layer.time?.outMS == 7_000)
        #expect(layer.content == .image(logo))
        #expect(layer.frame.size == CGSize(width: 480, height: 192))
        #expect(layer.frame.midX == 640)
        #expect(layer.frame.midY == 400)
    }

    @Test func aPictureRunningPastTheEndStretchesTheVideo() throws {
        var document = doc()
        let landing = document.titleLanding(lengthMS: PictureClip.lengthMS, atMS: 6_000, over: nil)
        let landed = document.landPicture(logo, named: "Acme Logo", at: landing)
        #expect(landed != nil)
        #expect(document.durationMS == 11_000)
    }

    /// `video-title-wt.html` step 7: "A Gfx track appears under the Title
    /// track carrying its clip". A picture let go on a new track makes a
    /// track called Gfx, then Gfx 2, and the ghost says the same name.
    @Test func aPictureOnANewTrackLandsOnATrackCalledGfx() throws {
        var document = doc()
        let landing = document.pictureLanding(atMS: 2_000, over: nil)
        #expect(landing.trackName == "Gfx")
        #expect(landing.lengthMS == PictureClip.lengthMS)
        let firstLanded = document.landPicture(logo, named: "Acme Logo", at: landing)
        let first = try #require(firstLanded)
        let track = try #require(document.trackID(ofClip: first))
        #expect(document.track(id: track)?.name == "Gfx")
        // Over the busy Gfx track at the same moment: a second one above.
        let second = document.pictureLanding(atMS: 2_000, over: .onto(track))
        #expect(second.trackName == "Gfx 2")
        let againLanded = document.landPicture(logo, named: "Acme Logo 2", at: second)
        let again = try #require(againLanded)
        let secondTrack = try #require(document.trackID(ofClip: again))
        #expect(document.track(id: secondTrack)?.name == "Gfx 2")
        #expect(secondTrack != track)
    }

    /// A landing worked out before something else took its name still lands,
    /// on the next numbered one rather than a second track called the same.
    @Test func aNewTrackWhoseNameWasTakenMeanwhileIsNumbered() throws {
        var document = doc()
        let landing = document.pictureLanding(atMS: 0, over: nil)
        let firstLanded = document.landPicture(logo, named: "Acme Logo", at: landing)
        #expect(firstLanded != nil)
        let againLanded = document.landPicture(logo, named: "Acme Logo 2", at: landing)
        let again = try #require(againLanded)
        let names = document.timelineTracks.map(\.name)
        #expect(Set(names).count == names.count)
        #expect(document.trackID(ofClip: again).flatMap { document.track(id: $0)?.name } == "Gfx 2")
    }

    /// A picture bigger than the frame is fitted into it, never left hanging
    /// past every edge.
    @Test func aBigPhotoIsFittedToTheFrame() throws {
        var document = doc()
        let landing = document.titleLanding(lengthMS: PictureClip.lengthMS, atMS: 0, over: nil)
        let landed = document.landPicture(photo, named: "Beach", at: landing)
        let id = try #require(landed)
        let frame = try #require(document.layer(id: id)?.frame)
        #expect(frame.width <= 1280 && frame.height <= 800)
        #expect(abs(frame.width / frame.height - 4032.0 / 3024.0) < 0.01)
    }
}
