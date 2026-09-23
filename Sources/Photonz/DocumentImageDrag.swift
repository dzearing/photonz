import AppKit
import CoreGraphics
import Foundation
import ImageIO
import PhotonzCore
import UniformTypeIdentifiers

/// A picture dragged off the Library's Media shelf, which is a picture the
/// document is already holding (`DocumentMedia`).
///
/// It travels two ways at once, and the order matters.
///
/// * **The app's own type carries the picture's id.** Letting go over this
///   document's canvas puts the SAME picture down again: one more layer
///   pointing at one bitmap, never a second copy of it.
/// * **PNG bytes ride along** so the same tile can be dragged out to the
///   Finder, a message, a browser — anywhere that takes a picture. Those are
///   written only if somebody asks for them, so an ordinary drag onto the
///   canvas never encodes anything.
enum DocumentImageDrag {
    static let typeIdentifier = "com.photonz.document-image"
    static let pasteboardType = NSPasteboard.PasteboardType(typeIdentifier)

    /// The drag a Media tile starts. `png` is called at most once, and only if
    /// something outside the app asks for the bytes.
    static func itemProvider(id: UUID, name: String,
                             png: @escaping @Sendable () -> Data?) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = "\(name).png"
        let payload = Data(id.uuidString.utf8)
        provider.registerDataRepresentation(forTypeIdentifier: typeIdentifier,
                                            visibility: .ownProcess) { completion in
            completion(payload, nil)
            return nil
        }
        provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier,
                                            visibility: .all) { completion in
            completion(png(), nil)
            return nil
        }
        return provider
    }

    /// PNG bytes for one picture, for the drag above.
    static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// The picture a pasteboard is carrying, nil for anything that is not one
    /// of this document's own pictures on the move.
    static func imageID(on pasteboard: NSPasteboard) -> UUID? {
        guard let data = pasteboard.data(forType: pasteboardType),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return UUID(uuidString: text)
    }

    /// The picture on the drag pasteboard right now, for the reason
    /// `ComponentDrag.payloadInFlight` gives: a surface has to answer on the
    /// frame the pointer arrives, and the carrier a drop hands over gives up
    /// its bytes too late for that.
    @MainActor static func idInFlight() -> UUID? {
        imageID(on: dragPasteboard())
    }

    /// The board a drag in flight is written on. A scripted walk cannot start a
    /// real drag session — AppKit only begins one from an event that came off a
    /// real device — so a probe build lets the harness stand a board in its
    /// place, which is the same board the destination would have read.
    @MainActor private static func dragPasteboard() -> NSPasteboard {
        #if PHOTONZ_PLAYTEST
        if let board = playtestPasteboard { return board }
        #endif
        return NSPasteboard(name: .drag)
    }

    #if PHOTONZ_PLAYTEST
    /// Set by the harness for the length of one scripted tile drag, and put
    /// back to nil the moment it ends.
    @MainActor static var playtestPasteboard: NSPasteboard?
    #endif
}
