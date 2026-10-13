import CoreGraphics
import Foundation

/// A measurement is named for the mode that made it: "Gap 16", "Distance 240",
/// and a Size measurement's "Size 320 × 48" group (`MeasureSizeGroup`) holding
/// a Width and a Height.
///
/// Asked for by the user on 2026-10-13: "when I measure with size, the layer
/// should be size. when i measure with gap, the layer should be gap." Until
/// then every caliper landed in the layers list as "Measure", and the
/// Measurements list named one by its ROLE, so a Distance drawn in the Size
/// role read "Width".
///
/// The name follows the reading the way a Size group's does: drag a foot from
/// 16 to 24 and "Gap 16" becomes "Gap 24" in the same step. A name somebody
/// chose is never touched.
public enum MeasureNaming {

    /// The words the modes give. Size's is `MeasureSizeGroup.word`.
    public static let gapWord = "Gap"
    public static let distanceWord = "Distance"

    /// What a loose caliper is called until somebody calls it something else:
    /// "Gap 16" or "Distance 240" in the caliper's own unit, "Width" or
    /// "Height" for the parts of a Size measurement. Nil for a caliper that
    /// does not know its mode (an older document, or a release without mode
    /// names) and for an alignment guide: those keep the name they have.
    public static func automaticName(for content: MeasureContent, pixelScale: CGFloat) -> String? {
        guard content.alignment == nil else { return nil }
        switch content.madeBy {
        case .gap, .distance:
            return "\(MeasureSpecList.derivedName(for: content)) \(number(content, pixelScale))"
        case .size:
            return MeasureSpecList.derivedName(for: content)
        case .alignment, nil:
            return nil
        }
    }

    /// Whether `name` is still one the app gave, so it should keep following
    /// the reading: the stock "Measure", the bare word, or the word and a
    /// number. Read off the shape of the name rather than compared with the
    /// reading, because the reading is what just changed.
    public static func isAutomaticName(_ name: String, for content: MeasureContent) -> Bool {
        guard content.alignment == nil, content.madeBy != nil else { return false }
        if name == MeasureBuilder.defaultName || name.isEmpty { return true }
        let word = MeasureSpecList.derivedName(for: content)
        if name == word { return true }
        guard name.hasPrefix("\(word) ") else { return false }
        return Double(name.dropFirst(word.count + 1)) != nil
    }

    /// The reading without its unit, the way the chip prints it.
    static func number(_ content: MeasureContent, _ pixelScale: CGFloat) -> String {
        String(format: "%.\(max(0, content.decimals))f", content.displayDistance(pixelScale: pixelScale))
    }
}

extension PhotonzDocument {

    /// Keeps every measurement's automatic name saying what it reads: a Size
    /// group's "Size 320 × 48" and a loose caliper's "Gap 16". Run on every
    /// edit, so the step that adds a caliper is the step that names it. A name
    /// somebody chose is never touched, and neither is a name changed by this
    /// very edit.
    public mutating func keepMeasureNamesInStep(since before: PhotonzDocument?) {
        keepSizeMeasureNamesInStep(since: before)
        var renames: [UUID: String] = [:]
        forEachLayer { layer in
            guard let content = layer.measure,
                  MeasureNaming.isAutomaticName(layer.name, for: content),
                  let wanted = MeasureNaming.automaticName(for: content, pixelScale: pixelScale),
                  wanted != layer.name else { return }
            if let was = before?.layer(id: layer.id), was.name != layer.name { return }
            renames[layer.id] = wanted
        }
        for (id, name) in renames { updateLayer(id: id) { $0.name = name } }
    }

    /// The layers Appearance reads a measurement's look from: a picked Size
    /// measurement stands for its two calipers, so the Caliper and Chip rows
    /// are there for it exactly as for any other caliper (the user,
    /// 2026-10-13: "makes no sense why i click on a size caliper and can't
    /// change the color"). Everything else is itself. Order kept, each once.
    public func measureLookIDs(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        var out: [UUID] = []
        for id in ids {
            guard let layer = layer(id: id) else { continue }
            let reached = layer.isSizeMeasurement
                ? MeasureSizeGroup.calipers(of: layer).map(\.id) : [id]
            for each in reached where seen.insert(each).inserted { out.append(each) }
        }
        return out
    }
}
