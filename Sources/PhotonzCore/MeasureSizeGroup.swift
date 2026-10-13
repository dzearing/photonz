import CoreGraphics
import Foundation

/// What Size mode puts down: ONE thing, not two loose calipers. A group named
/// for what it measures ("Size 320 × 48") holding a faint box over the measured
/// area, the width caliper and the height caliper. It moves, hides and deletes
/// as one, and opens in the layers list so each part can be picked and changed.
///
/// Asked for by the user on 2026-10-13: "when i measure the size of a box, i'd
/// like the box to have a semitransparent (10% opacity) red box outlining the
/// space being measured. I'd like the size tool to be one layer group but can
/// be expanded to modify the 3 parts."
///
/// The parts stay the ordinary things they are: the box is a rectangle like
/// any other (its fill and opacity are edited the way any shape's are), and
/// the calipers are the same calipers every other mode produces, so nothing
/// downstream needs a case for them.
public enum MeasureSizeGroup {

    /// The box's row in the layers list.
    public static let boxName = "Box"
    /// How faint a new box is: enough to see the area, never enough to hide
    /// what is under it.
    public static let defaultBoxOpacity: CGFloat = 0.1
    /// The word the group's automatic name starts with, and its row's name in
    /// the Measurements list.
    public static let word = "Size"

    /// The group, built round `rect` from calipers already placed in document
    /// space. Stacked box first, so both calipers draw over the tint.
    ///
    /// Grouped the way the Group command groups: the group's anchor is the top
    /// left of everything inside it and each part is rewritten against it once,
    /// so nothing moves on screen for being grouped.
    public static func group(measuring rect: CGRect, width: Layer, height: Layer,
                             boxColorHex: String, boxOpacity: CGFloat,
                             pixelScale: CGFloat) -> Layer {
        var shape = AnnotationContent(shape: .rectangle, strokeWidth: 0,
                                      start: .zero,
                                      end: CGPoint(x: rect.width, y: rect.height))
        shape.fill = Paint(hex: boxColorHex)
        var box = Layer(name: boxName, content: .annotation(shape), frame: rect)
        box.style.opacity = Double(min(max(boxOpacity, 0), 1))
        // The calipers are named for what they are, so the group opens in the
        // layers list as Box, Width, Height rather than two rows called
        // Measure. The names match what the spec list derives, so its Width
        // and Height lines read exactly as before.
        var width = width, height = height
        if width.name == MeasureBuilder.defaultName, let m = width.measure {
            width.name = MeasureSpecList.derivedName(for: m)
        }
        if height.name == MeasureBuilder.defaultName, let m = height.measure {
            height.name = MeasureSpecList.derivedName(for: m)
        }
        let parts = [box, width, height]
        let union = parts.dropFirst().reduce(box.localBounds) { $0.union($1.localBounds) }
        let origin = union.origin
        let children = parts.map { part -> Layer in
            var part = part
            part.frame = part.frame.offsetBy(dx: -origin.x, dy: -origin.y)
            return part
        }
        var content = GroupContent(children: children)
        content.measuresSize = true
        var group = Layer(name: word, content: .group(content),
                          frame: CGRect(origin: origin, size: .zero))
        group.name = automaticName(of: group, pixelScale: pixelScale) ?? word
        return group
    }

    /// The two calipers inside a size group, width first. Empty for anything
    /// that is not one.
    public static func calipers(of group: Layer) -> [Layer] {
        guard group.isSizeMeasurement else { return [] }
        return group.children.filter { $0.measure != nil }
    }

    /// The tinted box inside a size group, nil for anything that is not one or
    /// a group whose box somebody deleted.
    public static func box(of group: Layer) -> Layer? {
        guard group.isSizeMeasurement else { return nil }
        return group.children.first { $0.annotation != nil }
    }

    /// The two numbers, without a unit: "320 × 48". Nil unless the group still
    /// holds a width and a height.
    public static func numbers(of group: Layer, pixelScale: CGFloat) -> String? {
        let measured = calipers(of: group).compactMap(\.measure)
        guard let width = measured.first(where: { $0.mode == .horizontal }),
              let height = measured.first(where: { $0.mode == .vertical }) else { return nil }
        return "\(number(width, pixelScale)) × \(number(height, pixelScale))"
    }

    /// "Size 320 × 48": what the group is called until somebody calls it
    /// something else.
    public static func automaticName(of group: Layer, pixelScale: CGFloat) -> String? {
        numbers(of: group, pixelScale: pixelScale).map { "\(word) \($0)" }
    }

    /// What its row in the Measurements list reads beside its name, in the
    /// unit the calipers read: "320 × 48 px".
    public static func valueText(of group: Layer, pixelScale: CGFloat) -> String? {
        guard let numbers = numbers(of: group, pixelScale: pixelScale),
              let unit = calipers(of: group).first?.measure?.unit else { return nil }
        return "\(numbers) \(unit.suffix)"
    }

    /// Whether a group's name is still the one the app gave it, so it should
    /// keep following its parts. Read off the shape of the name rather than
    /// compared with the numbers, because the numbers are what just changed.
    public static func isAutomaticName(_ name: String) -> Bool {
        guard name.hasPrefix("\(word) ") else { return false }
        let sides = name.dropFirst(word.count + 1).components(separatedBy: " × ")
        return sides.count == 2 && sides.allSatisfy { Double($0) != nil }
    }

    private static func number(_ content: MeasureContent, _ pixelScale: CGFloat) -> String {
        String(format: "%.\(max(0, content.decimals))f", content.displayDistance(pixelScale: pixelScale))
    }
}

extension Layer {
    /// Whether this is the group a Size measurement lands as.
    public var isSizeMeasurement: Bool { group?.measuresSize == true }

    /// Whether this layer is a measurement: a caliper or alignment guide, or a
    /// Size measurement's group.
    public var isMeasurement: Bool { measure != nil || isSizeMeasurement }
}

extension PhotonzDocument {

    /// Whether `id` is the tinted box inside a Size measurement, so an edit to
    /// its fill or opacity is remembered for the next measurement rather than
    /// for the next rectangle somebody draws.
    public func isSizeMeasureBox(_ id: UUID) -> Bool {
        guard let parent = parentID(of: id), let group = layer(id: parent),
              group.isSizeMeasurement else { return false }
        return MeasureSizeGroup.box(of: group)?.id == id
    }

    /// Every caliper and guide in the document, size groups' included, with
    /// its frame in canvas space: what a new readout dodges and what a dragged
    /// foot lines up with.
    public var canvasMeasureLayers: [Layer] {
        allLayers.filter { $0.measure != nil }.compactMap { canvasLayer(id: $0.id) }
    }

    /// Keeps each Size measurement's automatic name saying what its calipers
    /// read, so dragging a foot from 320 to 300 renames "Size 320 × 48" to
    /// "Size 300 × 48" in the same step. A name somebody chose is never
    /// touched, and neither is a name changed by this very edit.
    public mutating func keepSizeMeasureNamesInStep(since before: PhotonzDocument?) {
        var renames: [UUID: String] = [:]
        forEachLayer { layer in
            guard layer.isSizeMeasurement,
                  MeasureSizeGroup.isAutomaticName(layer.name),
                  let wanted = MeasureSizeGroup.automaticName(of: layer, pixelScale: pixelScale),
                  wanted != layer.name else { return }
            if let was = before?.layer(id: layer.id), was.name != layer.name { return }
            renames[layer.id] = wanted
        }
        for (id, name) in renames { updateLayer(id: id) { $0.name = name } }
    }
}
