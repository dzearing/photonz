import CoreGraphics
import Foundation

// The documents the Video track's guides open on.
//
// The app writes the recordings (it is the part that can make an MP4) and opens
// the first one the way any recording opens: one clip on V1, remembered on the
// Library's Media shelf. What a guide needs on top of that is here, as plain
// document edits, so it is the same document a person would have made by hand
// and the guide's claims about it are tested rather than hoped for.

public enum TutorialVideoSample {

    /// What the second recording is called on the shelf, and so on its tile
    /// and its clip: the name the mocks give it.
    public static let brollFileName = "b-roll.mp4"

    /// How much each clip holds back on the side of the cut in the transition
    /// guide's sample. A dissolve is paid for with frames a clip is not using,
    /// and a second either side pays for any length the picker offers.
    public static let spareMS = 1000

    /// How long b-roll plays for in the transition guide's sample. Short, so
    /// the cut sits well to the right of the timeline: the tiles open AT the
    /// cut, and a cut in the middle opened them straight over the guide's own
    /// card, hiding the line that says which tile to pick.
    public static let twoClipsBrollMS = 2000

    /// The folder each sample's files are written into. One per sample, so a
    /// guide starting on one never rewrites a file another open window is
    /// playing.
    public static func folderName(for sample: TutorialSample) -> String {
        sample.rawValue
    }

    /// `document`, which is the first recording as it opened, made into what
    /// `sample` promises. `broll` is the second recording; without it there is
    /// nothing to add and the document comes back as it was.
    public static func shaped(_ document: PhotonzDocument, for sample: TutorialSample,
                              broll: MovieRef?) -> PhotonzDocument {
        guard let broll else { return document }
        var shaped = document
        switch sample {
        case .videoRecording:
            // On the shelf and nowhere else: bringing it onto the timeline is
            // what the second clip guide teaches.
            shaped.rememberMedia(.recording(broll), named: brollFileName)
        case .videoTwoClips:
            guard let recording = shaped.layers.first(where: { $0.movie != nil }),
                  let movie = recording.movie else { return document }
            // The recording stops a second short of its end, so it has frames
            // to give past the cut...
            let keptMS = movie.durationMS - spareMS
            shaped.updateLayer(id: recording.id) {
                $0.time = LayerTime(inMS: 0, outMS: keptMS, sourceInMS: 0,
                                    sourceLengthMS: movie.durationMS)
            }
            // ...and b-roll starts a second into its own, so it has frames to
            // give before it.
            let brollLengthMS = min(twoClipsBrollMS, broll.durationMS - 2 * spareMS)
            guard let track = shaped.timelineTracks.first(where: { $0.kind == .video })?.id,
                  brollLengthMS > 0 else { return document }
            var clip = Layer(name: (brollFileName as NSString).deletingPathExtension,
                             content: .image(broll.frameRef(atSourceMS: spareMS)),
                             frame: shaped.placementForIncomingImage(size: broll.pixelSize))
            clip.movie = broll
            clip.time = LayerTime(inMS: 0, outMS: brollLengthMS, sourceInMS: spareMS,
                                  sourceLengthMS: broll.durationMS)
            let landing = shaped.clipLanding(kind: .video, lengthMS: brollLengthMS, atMS: keptMS,
                                             over: .onto(track), edit: .overwrite)
            guard shaped.land(clip, at: landing) != nil else { return document }
            shaped.rememberMedia(.recording(broll), named: brollFileName)
        default:
            return document
        }
        return shaped
    }
}
