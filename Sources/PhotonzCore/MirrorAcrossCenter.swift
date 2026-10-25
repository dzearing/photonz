import CoreGraphics
import Foundation

/// Mirror Across Center: copies what is picked, reflected left to right about
/// the vertical middle of the frame it sits on (`icon-draw-wt.html`, step 7).
///
/// Symmetry that comes from a command cannot drift; symmetry that comes from a
/// careful second drag always eventually does, and half a unit of it is what a
/// person sees in a row of icons without being able to say why. So the second
/// half of a drawing is the first half's copy, placed by arithmetic.
///
/// Which middle: the nearest frame ABOVE the layer (a frame mirrored is
/// mirrored about the screen it sits on, never about itself), and the canvas's
/// middle for a layer on no frame at all.
public enum MirrorAcrossCenter {
    /// The command's name in every menu that offers it, in the menu bar's
    /// Title Case of the mock's "Mirror across center".
    public static let title = "Mirror Across Center"

    /// The name a reflected copy of `name` takes when a person put a side in
    /// it: "Shoulder left" makes "Shoulder right", as the mock's layers list
    /// reads after step 7. The side is a whole word, either way round, and
    /// keeps the case it was typed in. Nil where the name says no side, and
    /// the copy is named the way any duplicate is.
    public static func mirroredName(_ name: String) -> String? {
        let pattern = #"(?i)\b(left|right)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
              let range = Range(match.range, in: name) else { return nil }
        let word = String(name[range])
        let other = word.lowercased() == "left" ? "right" : "left"
        let cased: String
        if word == word.uppercased() {
            cased = other.uppercased()
        } else if word.first?.isUppercase == true {
            cased = other.prefix(1).uppercased() + other.dropFirst()
        } else {
            cased = other
        }
        return name.replacingCharacters(in: range, with: cased)
    }
}

extension Layer {

    /// This layer reflected left to right about the vertical line `x = axis`,
    /// with `axis` stated in the same space as `frame` (the parent's). Same
    /// identity: making it a copy is the caller's business. The one case of
    /// `reflected(across:at:)` the mirror needs (`LayerFlip.swift`).
    public func reflected(acrossX axis: CGFloat) -> Layer {
        reflected(across: .horizontal, at: axis)
    }

    /// Whether Mirror Across Center means anything for this layer. A reading
    /// of the picture (a measurement, a magnifier, a lens) is about where it
    /// stands, so a reflected one would measure or magnify something else, and
    /// a sound has nothing to reflect.
    public var canBeMirrored: Bool {
        switch content {
        case .image, .text, .annotation, .path, .paint, .collage, .group: true
        case .zoomCallout, .lens, .measure, .sound: false
        }
    }
}

extension PhotonzDocument {

    /// The vertical line a layer is mirrored about, in canvas coordinates: the
    /// middle of the nearest frame above it, or of the canvas.
    public func mirrorAxis(of id: UUID) -> CGFloat? {
        guard layer(id: id) != nil else { return nil }
        if let parent = parentID(of: id), let frameID = frameID(containing: parent),
           let box = canvasFrame(of: frameID) {
            return box.standardized.midX
        }
        return canvasSize.width / 2
    }

    /// The picked layers that would be mirrored: unlocked, of a kind that can
    /// be, not inside a copy of a component (what is in there belongs to the
    /// original), and not inside another picked layer, which carries it.
    func mirrorTargets(ids: Set<UUID>) -> Set<UUID> {
        let usable = ids.filter { id in
            guard let layer = layer(id: id), !layer.isLocked, layer.canBeMirrored,
                  path(of: id) != nil else { return false }
            if let parent = parentID(of: id), isInsideCopy(parent) { return false }
            return true
        }
        return usable.filter { id in !usable.contains { $0 != id && isDescendant(id, of: $0) } }
    }

    /// Whether Mirror Across Center would do anything.
    public func canMirrorAcrossCenter(ids: Set<UUID>) -> Bool {
        !mirrorTargets(ids: ids).isEmpty
    }

    /// Copies every picked layer, reflected about the middle of its frame,
    /// each directly above its original, in one mutation so it is one undo
    /// step. Returns the copies' ids, bottom-up; the caller picks them.
    @discardableResult
    public mutating func mirrorAcrossCenter(ids: Set<UUID>) -> [UUID] {
        let targets = mirrorTargets(ids: ids)
        guard !targets.isEmpty else { return [] }
        // Each axis moved into the space the layer's frame is written in,
        // worked out before anything moves.
        var axes: [UUID: CGFloat] = [:]
        for id in targets {
            guard let axis = mirrorAxis(of: id), let origin = parentOrigin(of: id) else { continue }
            axes[id] = axis - origin.x
        }
        var made: [(copy: UUID, source: String)] = []
        func walk(_ list: inout [Layer]) {
            var result: [Layer] = []
            result.reserveCapacity(list.count)
            for var layer in list {
                if layer.isGroup, axes[layer.id] == nil { walk(&layer.children) }
                result.append(layer)
                if let axis = axes[layer.id] {
                    let copy = layer.duplicated().reflected(acrossX: axis)
                    made.append((copy.id, layer.name))
                    result.append(copy)
                }
            }
            list = result
        }
        walk(&layers)
        // A side in the name swaps where that name is free; everything else is
        // named the way a duplicate is.
        var plain: [(copy: UUID, source: String)] = []
        var taken = Set(allLayers.map(\.name))
        for entry in made {
            if let name = MirrorAcrossCenter.mirroredName(entry.source), !taken.contains(name) {
                taken.insert(name)
                updateLayer(id: entry.copy) { $0.name = name }
            } else {
                plain.append(entry)
            }
        }
        nameDuplicates(plain)
        return made.map(\.copy)
    }
}
