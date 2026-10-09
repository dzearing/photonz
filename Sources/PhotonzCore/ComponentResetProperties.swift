import Foundation

/// The variants mock's Reset props (`docs/design/mocks/pages/ui-variants.html`,
/// `#reset2`): one press puts every answer a copy gave itself back to the
/// original's, and puts it back on the component's first variant.
///
/// It reaches the PROPERTIES and nothing else. A size, a look or a type the
/// copy was given for itself each has its own way back on its own row, because
/// those are not answers to anything the original asked.
extension PhotonzDocument {

    /// Whether this copy has anything Reset would put back: an answer of its
    /// own, or a variant other than the first. A locked copy never does.
    public func canResetInstanceProperties(instance: UUID) -> Bool {
        guard let copy = layer(id: instance), let componentID = copy.instanceOf, !copy.isLocked
        else { return false }
        if !copy.componentOverrides.isEmpty { return true }
        if copy.group?.instanceAnswers.isEmpty == false { return true }
        let first = componentVersions(of: componentID).first?.id
        return first != nil && instanceVersion(of: instance) != first
    }

    /// Whether any of these copies has something to put back.
    public func canResetInstanceProperties(instances: [UUID]) -> Bool {
        instances.contains { canResetInstanceProperties(instance: $0) }
    }

    /// Puts every copy given back to what its original says, in one step.
    /// Returns how many copies it changed.
    @discardableResult
    public mutating func resetInstanceProperties(instances: [UUID]) -> Int {
        var count = 0
        for id in instances where canResetInstanceProperties(instance: id) {
            guard let componentID = layer(id: id)?.instanceOf else { continue }
            let first = componentVersions(of: componentID).first?.id
            updateLayer(id: id) { layer in
                guard var group = layer.group else { return }
                group.overrides.removeAll()
                group.instanceAnswers.removeAll()
                layer.content = .group(group)
            }
            if let first, instanceVersion(of: id) != first {
                setInstanceVersion(instance: id, to: first)
            }
            count += 1
        }
        return count
    }
}
