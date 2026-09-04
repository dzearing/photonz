import Foundation

extension PhotonzDocument {

    /// How many colors the picker's Document row will show. One row, so a
    /// document with a photograph in it does not hand back a wall of swatches.
    public static let colorsInUseLimit = 24

    /// Every color this document is actually painted with, the one used most
    /// first, each written the one canonical way.
    ///
    /// This is what the picker offers under Document: not a palette somebody
    /// curated, but what is already here, so matching something you drew five
    /// minutes ago is one click instead of a hunt with the eyedropper.
    public var colorsInUse: [String] {
        var counts: [String: Int] = [:]
        var order: [String: Int] = [:]
        var next = 0

        func record(_ hex: String?) {
            guard let hex, let canonical = RGBA(hex: hex)?.hexString else { return }
            counts[canonical, default: 0] += 1
            if order[canonical] == nil {
                order[canonical] = next
                next += 1
            }
        }

        for layer in allLayers {
            for slot in ColorSlot.allCases { record(layer.colorHex(for: slot)) }
            record(layer.style.shadow?.colorHex)
            switch layer.content {
            case .measure(let measure):
                record(measure.strokeColorHex)
                record(measure.chipColorHex)
                record(measure.textColorHex)
            case .collage(let collage):
                record(collage.backdropColorHex)
            case .zoomCallout:
                record(layer.style.borderColorHex)
            default:
                break
            }
        }
        // A saved color counts even before anything wears it: it was saved to
        // be used, so it belongs in the row that says what this document is
        // made of.
        for style in colorStyles { record(style.colorHex) }

        return counts.keys
            .sorted {
                counts[$0] == counts[$1]
                    ? (order[$0] ?? 0) < (order[$1] ?? 0)
                    : (counts[$0] ?? 0) > (counts[$1] ?? 0)
            }
            .prefix(PhotonzDocument.colorsInUseLimit)
            .map { $0 }
    }
}
