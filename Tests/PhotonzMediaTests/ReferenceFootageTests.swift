import AVFoundation
import CoreGraphics
import Foundation
import PhotonzCore
import PhotonzMedia
import Testing

/// **The recordings the reference edit is cut from** (`ReferenceFootage`,
/// task `a-long-reference-edit-opens-in-the-probe-in-one`).
///
/// Written small and short here; the real ones are the same drawing at
/// 3456 x 2234 and a minute long. What matters is that they are real files a
/// recording would be: the size and rate asked for, a picture that moves the
/// way a screen recording's does, a sound track the length of the picture,
/// and written once and kept.
@Suite("The reference edit's recordings")
struct ReferenceFootageTests {

    static let small = ReferenceFootage.Spec(size: CGSize(width: 432, height: 280), framesPerSecond: 60,
                                             recordingMS: 2000, musicMS: 3000)

    @Test("A recording is the size and rate asked for, with sound the length of its picture")
    func aRecordingIsWhatWasAskedFor() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReferenceFootage-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("one.mov")
        try await ReferenceFootage.writeRecording(ReferenceEdit.footage[0], spec: Self.small, to: url)

        let asset = AVURLAsset(url: url)
        let video = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let size = try await video.load(.naturalSize)
        #expect(size == Self.small.size)
        let rate = try await video.load(.nominalFrameRate)
        #expect(abs(rate - 60) < 1)
        let length = try await asset.load(.duration).seconds
        #expect(abs(length - 2) < 0.05)
        let audio = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        let heard = try await audio.load(.timeRange).duration.seconds
        #expect(abs(heard - 2) < 0.1)
    }

    @Test("Every scene moves the way a screen recording does: its picture half a second apart differs")
    func everySceneMoves() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReferenceFootage-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for footage in ReferenceEdit.footage {
            let a = ReferenceFootage.frame(footage, spec: Self.small, atMS: 500)
            let b = ReferenceFootage.frame(footage, spec: Self.small, atMS: 1000)
            let first = try #require(a)
            let second = try #require(b)
            let difference = Self.meanDifference(first, second)
            #expect(difference > 0.5, "\(footage.scene) moved \(difference)")
        }
        // ...and the four scenes are four different pictures.
        let firsts = ReferenceEdit.footage.compactMap { ReferenceFootage.frame($0, spec: Self.small, atMS: 0) }
        #expect(firsts.count == ReferenceEdit.footage.count)
        for i in firsts.indices {
            for j in firsts.indices where j > i {
                #expect(Self.meanDifference(firsts[i], firsts[j]) > 2)
            }
        }
    }

    @Test("Everything is written once and kept: a second ask writes nothing")
    func writtenOnceAndKept() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReferenceFootage-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let files = try await ReferenceFootage.ensure(in: folder, spec: Self.small)
        #expect(files.count == ReferenceEdit.footage.count + 1)
        let music = try #require(files[ReferenceEdit.music.sound.id])
        #expect(music.lastPathComponent == ReferenceEdit.music.fileName)
        let heard = try await AVURLAsset(url: music).load(.duration).seconds
        #expect(abs(heard - 3) < 0.1)
        for footage in ReferenceEdit.footage {
            let url = try #require(files[footage.movie.id])
            #expect(url.lastPathComponent == footage.fileName)
            #expect(url.deletingLastPathComponent().lastPathComponent == ReferenceEdit.footageFolderName)
        }
        let before = try files.values.map { try $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
        let again = try await ReferenceFootage.ensure(in: folder, spec: Self.small)
        #expect(again == files)
        let after = try files.values.map { try $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
        #expect(before == after)
    }

    @Test("A project names every file it plays, where it was written")
    func aProjectNamesItsFiles() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReferenceFootage-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let project = try await ReferenceFootage.project(minutes: 6, in: folder, spec: Self.small)
        #expect(project.url.lastPathComponent == "Reference Edit 6 min.photonz")
        #expect(project.document.documentDurationMS == 360_000)
        #expect(Set(project.media.map(\.id))
                == Set(ReferenceEdit.footage.map(\.movie.id) + [ReferenceEdit.music.sound.id]))
        for file in project.media {
            #expect(FileManager.default.fileExists(atPath: file.path))
            #expect(file.relativePath?.hasPrefix(ReferenceEdit.footageFolderName) == true)
        }
    }

    /// Mean absolute difference of two pictures' bytes, 0 to 255.
    static func meanDifference(_ a: CGImage, _ b: CGImage) -> Double {
        func bytes(_ image: CGImage) -> [UInt8] {
            var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
            let space = CGColorSpaceCreateDeviceRGB()
            data.withUnsafeMutableBytes { raw in
                let context = CGContext(data: raw.baseAddress, width: image.width, height: image.height,
                                        bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            }
            return data
        }
        let x = bytes(a), y = bytes(b)
        guard x.count == y.count, !x.isEmpty else { return 0 }
        var total = 0
        for i in x.indices { total += abs(Int(x[i]) - Int(y[i])) }
        return Double(total) / Double(x.count)
    }
}
