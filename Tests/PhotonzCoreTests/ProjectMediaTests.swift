import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

@Suite("Project media")
struct ProjectMediaTests {

    private let talk = MovieRef(pixelSize: CGSize(width: 640, height: 360), durationMS: 8_000,
                                hasSound: true)
    private let broll = MovieRef(pixelSize: CGSize(width: 640, height: 360), durationMS: 4_000)
    private let music = SoundRef(durationMS: 14_000)

    /// The talk recording, its own sound taken off it, the b-roll inside a
    /// group, and a piece of music, with the b-roll also remembered on the shelf.
    private func editedVideo() -> PhotonzDocument {
        var doc = PhotonzDocument.recording(talk, name: "talk")
        doc.rememberMedia(.recording(talk), named: "talk.mov")
        doc.rememberMedia(.recording(broll), named: "b-roll.mov")
        doc.rememberMedia(.sound(music), named: "music.wav")
        var brollClip = Layer(name: "b-roll", content: .image(broll.frameRef(atSourceMS: 0)),
                              frame: CGRect(x: 0, y: 0, width: 640, height: 360))
        brollClip.movie = broll
        doc.addLayer(Layer(name: "Group", content: .group(GroupContent(children: [brollClip])),
                           frame: CGRect(x: 0, y: 0, width: 640, height: 360)))
        // The recording's own sound on a layer of its own: same id as the picture.
        if let talkSound = talk.soundRef {
            doc.addLayer(Layer(name: "talk sound", content: .sound(talkSound), frame: .zero))
        }
        doc.addLayer(Layer(name: "music", content: .sound(music), frame: .zero))
        return doc
    }

    @Test func everyRecordingAndSoundIsListedOnceWithTheRecordingWinning() {
        let media = ProjectMedia.references(in: editedVideo())
        #expect(media.count == 3)
        #expect(media.contains(.recording(talk)))
        #expect(media.contains(.recording(broll)))
        #expect(media.contains(.sound(music)))
        // The talk's sound layer shares its id and never shows up as a sound.
        #expect(!media.contains(.sound(SoundRef(id: talk.id, durationMS: talk.durationMS))))
    }

    @Test func aRecordingOnlyOnTheShelfIsStillListed() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 10, height: 10))
        doc.rememberMedia(.recording(broll), named: "b-roll.mov")
        #expect(ProjectMedia.references(in: doc) == [.recording(broll)])
    }

    @Test func aPictureHasNoMedia() {
        let doc = PhotonzDocument(canvasSize: CGSize(width: 10, height: 10))
        #expect(ProjectMedia.references(in: doc).isEmpty)
    }

    @Test func theTableRecordsWhereEachFileIsAndSkipsWhatCannotBeFound() {
        let doc = editedVideo()
        let project = URL(fileURLWithPath: "/Users/me/Projects/Talk.photonz")
        let located: [UUID: URL] = [
            talk.id: URL(fileURLWithPath: "/Users/me/Movies/talk.mov"),
            music.id: URL(fileURLWithPath: "/Users/me/Projects/audio/music.wav"),
        ]
        let table = ProjectMedia.table(for: doc, project: project) { located[$0] }
        #expect(table.count == 2)
        let talkEntry = table.first { $0.id == talk.id }
        #expect(talkEntry?.kind == .recording)
        #expect(talkEntry?.name == "talk.mov")
        #expect(talkEntry?.path == "/Users/me/Movies/talk.mov")
        #expect(talkEntry?.relativePath == "../Movies/talk.mov")
        let musicEntry = table.first { $0.id == music.id }
        #expect(musicEntry?.kind == .sound)
        #expect(musicEntry?.relativePath == "audio/music.wav")
    }

    @Test func aFileWhereItWasSavedIsFound() {
        let entry = ProjectMediaFile(id: talk.id, kind: .recording, name: "talk.mov",
                                     path: "/Users/me/Movies/talk.mov",
                                     relativePath: "../Movies/talk.mov")
        let project = URL(fileURLWithPath: "/Users/me/Projects/Talk.photonz")
        let found = ProjectMedia.resolve([entry], project: project) {
            $0.path == "/Users/me/Movies/talk.mov"
        }
        #expect(found.located[talk.id]?.path == "/Users/me/Movies/talk.mov")
        #expect(found.missing.isEmpty)
    }

    @Test func aFileThatMovedWithTheProjectIsFoundBesideIt() {
        // The whole folder went to another disk: the old full path is gone,
        // the same place relative to the project is not.
        let entry = ProjectMediaFile(id: music.id, kind: .sound, name: "music.wav",
                                     path: "/Users/me/Projects/audio/music.wav",
                                     relativePath: "audio/music.wav")
        let project = URL(fileURLWithPath: "/Volumes/Backup/Projects/Talk.photonz")
        let found = ProjectMedia.resolve([entry], project: project) {
            $0.path == "/Volumes/Backup/Projects/audio/music.wav"
        }
        #expect(found.located[music.id]?.path == "/Volumes/Backup/Projects/audio/music.wav")
        #expect(found.missing.isEmpty)
    }

    @Test func aFileThatIsNowhereIsNamedAsMissing() {
        let entry = ProjectMediaFile(id: talk.id, kind: .recording, name: "talk.mov",
                                     path: "/Users/me/Movies/talk.mov",
                                     relativePath: "../Movies/talk.mov")
        let project = URL(fileURLWithPath: "/Users/me/Projects/Talk.photonz")
        let found = ProjectMedia.resolve([entry], project: project) { _ in false }
        #expect(found.located.isEmpty)
        #expect(found.missing.map(\.name) == ["talk.mov"])
    }

    @Test func theMissingMessageNamesTheFiles() {
        #expect(ProjectMedia.missingMessage(names: []) == nil)
        #expect(ProjectMedia.missingMessage(names: ["talk.mov"])
                == "Can’t find “talk.mov”. It was moved or deleted since this project was saved.")
        #expect(ProjectMedia.missingMessage(names: ["talk.mov", "music.wav"])
                == "Can’t find “talk.mov” and “music.wav”. They were moved or deleted since this project was saved.")
        #expect(ProjectMedia.missingMessage(names: ["a.mov", "b.mov", "c.wav"])
                == "Can’t find “a.mov”, “b.mov” and “c.wav”. They were moved or deleted since this project was saved.")
    }

    @Test func theAdviceFollowsHowManyAreMissing() {
        #expect(ProjectMedia.missingAdvice(count: 1)
                == "The project is open without it. Put the file back where it was, or beside the project, and open the project again.")
        #expect(ProjectMedia.missingAdvice(count: 3)
                == "The project is open without them. Put the files back where they were, or beside the project, and open the project again.")
    }

    @Test func theTableRoundTripsThroughJSON() throws {
        let entry = ProjectMediaFile(id: talk.id, kind: .recording, name: "talk.mov",
                                     path: "/a/talk.mov", relativePath: nil)
        let data = try JSONEncoder().encode([entry])
        #expect(try JSONDecoder().decode([ProjectMediaFile].self, from: data) == [entry])
    }
}
