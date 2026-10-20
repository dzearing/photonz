import Foundation
import PhotonzCore

// Fading a clip's picture in at its start and out at its end
// (`PictureFade.swift`).
//
// One fade for everything on the timeline: a recording, a title, a shape, a
// picture, a component. It is offered where a Final Cut or Premiere editor
// reaches for it: a right click on the bar (Fade In ▸, Fade Out ▸, a few
// lengths each), the Clip menu with a key for each end, and a handle at each
// top corner of the bar to drag to any length (`ClipPiecesBar`).
extension EditorState {

    /// The length the keys fade over: a second, the default transition length
    /// in both Premiere and Final Cut.
    static let pictureFadeKeyMS = 1000

    /// ⌃⌥I and ⌃⌥O: In and Out, the ends Premiere's marks already name, on a
    /// chord nothing else in the app uses.
    static func pictureFadeKey(_ end: FadeEnd) -> MenuShortcut {
        MenuShortcut(key: end == .in ? "i" : "o", modifiers: [.control, .option])
    }

    /// A layer whose picture the timeline's fade verbs may act on, whichever
    /// layer happens to be picked: the one a right click was opened on.
    func pictureFadeLayer(_ id: UUID) -> Layer? {
        guard Experiments.shared.pictureFadesEnabled, documentHasTime, !isClipLocked(id),
              let layer = document?.layer(id: id), layer.canFadePicture else { return nil }
        return layer
    }

    /// What the Clip menu's fade rows act on: the picked layer where it can
    /// fade, else the clip the timeline's edits act on.
    var pictureFadeLayerInHand: Layer? {
        if let id = selectedLayerID, let layer = pictureFadeLayer(id) { return layer }
        return clipInHandID.flatMap { pictureFadeLayer($0) }
    }

    /// ⌃⌥F: Fade In and Out, on the chord beside its two ends.
    static let fadeInAndOutKey = MenuShortcut(key: "f", modifiers: [.control, .option])

    func canSetPictureFade(_ end: FadeEnd, toMS ms: Int, layerID id: UUID) -> Bool {
        pictureFadeLayer(id)?.canSetPictureFade(end, toMS: ms) == true
    }

    // MARK: Every pick, not just the one clicked

    /// What a fade opened on `id` acts on: every picked thing that can fade
    /// when `id` is among the picks, else `id` alone. The rule the sound rows
    /// follow (`soundLayers(actingOn:)`), so three arrows picked and one of
    /// them right clicked all fade.
    func pictureFadeTargets(actingOn id: UUID) -> [UUID] {
        let picked = actionableLayerIDs
        let ids = picked.contains(id) ? orderedPicks(picked) : [id]
        return ids.filter { pictureFadeLayer($0) != nil }
    }

    /// What the Clip menu's fade rows and the panel's act on: every picked
    /// thing that can fade, else the clip the timeline's edits act on.
    var pictureFadeTargetsInHand: [UUID] {
        let picked = orderedPicks(actionableLayerIDs).filter { pictureFadeLayer($0) != nil }
        if !picked.isEmpty { return picked }
        return pictureFadeLayerInHand.map { [$0.id] } ?? []
    }

    /// The picks in the document's order, so a step to undo and a walk read
    /// them the same way every time.
    private func orderedPicks(_ picked: Set<UUID>) -> [UUID] {
        guard let document else { return Array(picked) }
        return document.allLayers.map(\.id).filter(picked.contains)
    }

    /// Fade one end of a layer's picture over `ms`, nought taking it away.
    /// The next thing of its kind drawn arrives with the fade it is left with.
    func setPictureFade(_ end: FadeEnd, toMS ms: Int, layerID id: UUID) {
        guard canSetPictureFade(end, toMS: ms, layerID: id) else { return }
        selectLayer(id)
        perform { $0.setPictureFade(id, end, toMS: ms) }
        rememberPictureFades(of: [id])
        documentMomentChanged()
    }

    /// One end of several at once, as ONE step to undo. A single layer goes
    /// the way it always has, with the pick left as it is.
    func setPictureFade(_ end: FadeEnd, toMS ms: Int, layerIDs ids: [UUID]) {
        guard ids.count > 1 else {
            if let id = ids.first { setPictureFade(end, toMS: ms, layerID: id) }
            return
        }
        perform { $0.setPictureFades(ids, inMS: end == .in ? ms : nil, outMS: end == .out ? ms : nil) }
        rememberPictureFades(of: ids)
        documentMomentChanged()
    }

    /// What a length row does: that length on every target, or, where the
    /// one it was opened on already has it, no fade, so a checked row
    /// unchecks like every other toggle.
    func choosePictureFade(_ end: FadeEnd, ms: Int, layerID id: UUID) {
        let now = document?.layer(id: id)?.pictureFadeMS(end) ?? 0
        setPictureFade(end, toMS: ms == now ? 0 : ms, layerIDs: pictureFadeTargets(actingOn: id))
    }

    /// The Clip menu's and the keys' version: the same, on what is in hand.
    func choosePictureFadeInHand(_ end: FadeEnd, ms: Int) {
        guard let first = pictureFadeTargetsInHand.first else { return }
        let now = document?.layer(id: first)?.pictureFadeMS(end) ?? 0
        setPictureFade(end, toMS: ms == now ? 0 : ms, layerIDs: pictureFadeTargetsInHand)
    }

    // MARK: Fade In and Out

    /// Whether every one of `ids` already fades at both ends: the tick on
    /// Fade In and Out.
    func fadesInAndOut(_ ids: [UUID]) -> Bool {
        RememberedLooks.fadesAtBothEnds(ids.compactMap { document?.layer(id: $0) })
    }

    /// **Fade In and Out**: both ends of every target in one step, each at
    /// the lengths its kind last faded at (a second where it never has). On
    /// things that already fade at both ends it takes the fades off, so the
    /// ticked row unchecks.
    func fadeInAndOut(_ ids: [UUID]) {
        let targets = ids.filter { pictureFadeLayer($0) != nil }
        guard !targets.isEmpty, let document else { return }
        if fadesInAndOut(targets) {
            perform { $0.setPictureFades(targets, inMS: 0, outMS: 0) }
        } else {
            let lengths = Dictionary(uniqueKeysWithValues: targets.map { id in
                (id, rememberedLooks.bothEnds(for: document.layer(id: id).flatMap { DrawnKind($0) }))
            })
            perform { doc in
                for id in targets {
                    guard let fade = lengths[id] else { continue }
                    doc.setPictureFades([id], inMS: fade.inMS, outMS: fade.outMS)
                }
            }
        }
        rememberPictureFades(of: targets)
        documentMomentChanged()
    }

    /// The row: on the thing right clicked, and every pick it is among.
    func fadeInAndOutMenuRow(layerID id: UUID) -> [MenuRow] {
        let targets = pictureFadeTargets(actingOn: id)
        guard !targets.isEmpty else { return [] }
        return [.toggle("Fade In and Out", isOn: fadesInAndOut(targets), shortcut: Self.fadeInAndOutKey) {
            self.fadeInAndOut(targets)
        }]
    }

    /// The next of each kind arrives faded the way these were left.
    func rememberPictureFades(of ids: [UUID]) {
        guard let document else { return }
        for id in ids {
            if let layer = document.layer(id: id) { rememberedLooks.rememberFade(of: layer) }
        }
        saveRememberedLooks()
    }

    /// Put both of a layer's picture fades on a curve.
    func setPictureFadeCurve(_ curve: EasingCurve, layerID id: UUID) {
        guard pictureFadeLayer(id) != nil, document?.layer(id: id)?.pictureFade?.shownCurve != curve else { return }
        perform { $0.setPictureFadeCurve(id, curve) }
        rememberPictureFades(of: [id])
        documentMomentChanged()
    }

        /// The lengths one end offers on this layer: the one it has, and every
    /// other that leaves the other end its room.
    func pictureFadeStops(_ end: FadeEnd, layer: Layer) -> [Int] {
        let now = layer.pictureFadeMS(end)
        return PictureFade.stopsMS.filter { $0 == now || layer.canSetPictureFade(end, toMS: $0) }
    }

    /// **Fade In ▸** and **Fade Out ▸**, each a few lengths with the one it
    /// has checked. The one-second row prints the key that toggles it.
    func pictureFadeMenuRows(layerID id: UUID) -> [MenuRow] {
        guard let layer = pictureFadeLayer(id) else { return [] }
        return FadeEnd.allCases.map { end in
            let now = layer.pictureFadeMS(end)
            return .submenu(end.title, pictureFadeStops(end, layer: layer).map { ms in
                .toggle(PictureFade.title(ms), isOn: ms == now,
                        shortcut: ms == Self.pictureFadeKeyMS ? Self.pictureFadeKey(end) : nil) {
                    self.choosePictureFade(end, ms: ms, layerID: id)
                }
            })
        }
    }
}

// MARK: - Saved between launches

extension EditorState {
    static let rememberedLooksKey = "rememberedLooks"

    static func loadRememberedLooks() -> RememberedLooks {
        guard let data = UserDefaults.standard.data(forKey: rememberedLooksKey),
              let looks = try? JSONDecoder().decode(RememberedLooks.self, from: data) else {
            return RememberedLooks()
        }
        return looks
    }

    func saveRememberedLooks() {
        if let data = try? JSONEncoder().encode(rememberedLooks) {
            UserDefaults.standard.set(data, forKey: Self.rememberedLooksKey)
        }
    }
}
