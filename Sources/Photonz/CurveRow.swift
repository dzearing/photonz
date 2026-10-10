import PhotonzCore
import SwiftUI

/// **Curve**: the one row every transition in the app is tuned with (task
/// `every-transition-can-be-picked-from-presets-and`): a zoom's way in and
/// out, a transition at a cut, the stretch between two keys (which is how a
/// title animates in and out), and a sound's fades.
///
/// Same control, same words, same menu everywhere: the key mock's menu
/// (`curve.js`), the six standard curves and the four shaped ones each with
/// its shape beside its name, then the curves kept under a name, then the one
/// you drew, then Draw a Curve. A kind whose own default is not one of the
/// eight (a zoom's Smooth) offers it at the end of the shaped ones, so the
/// default is always one pick away.
struct CurveRow: View {
    var label = "Curve"
    /// What it runs on now, or nil where several picked disagree (Mixed).
    let current: EasingCurve?
    /// The kind's own default where it is not on the shared list.
    var ownDefault: EasingCurve?
    /// A curve of your own the row can go back to (`CustomChoice`), beside the
    /// one showing when that is drawn.
    var kept: EasingCurve?
    /// Rows of the kind's own, after Draw a Curve.
    var extra: [VideoKit.Choice] = []
    let help: String
    /// The row's name for a walk where two Curve rows share a panel (a
    /// clip's picture fades and its sound's), so `in` can tell them apart.
    var row: String?
    let pick: @MainActor (EasingCurve) -> Void

    @State private var isDrawing = false

    var body: some View {
        let saved = SavedCurveStore.shared.curves
        let value = Self.value(current, saved: saved)
        VideoKit.DropdownRow(label: label, value: value, choices: choices(saved))
            .frame(minHeight: 24)
            .panelReadout(value)
            .panelHelp(help)
            .playtestField(row ?? label)
            .popover(isPresented: $isDrawing, arrowEdge: .leading) {
                CurveEditor(curve: current ?? kept ?? .easeInOut, saves: true) { drawn in
                    pick(drawn)
                    isDrawing = false
                }
            }
    }

    /// What the row says: Mixed, a saved curve's name, Custom for one drawn
    /// and not kept, or the curve's own name.
    static func value(_ curve: EasingCurve?, saved: SavedCurves) -> String {
        guard let curve else { return MixedValue.text }
        if let name = saved.name(of: curve) { return name }
        return StretchCurve.title(curve)
    }

    private func choices(_ saved: SavedCurves) -> [VideoKit.Choice] {
        var rows: [VideoKit.Choice] = [.heading("Standard")]
        rows += EasingCurve.named.prefix(EasingCurve.standardCount).map(item)
        rows.append(.heading("Shaped"))
        rows += EasingCurve.named.dropFirst(EasingCurve.standardCount).map(item)
        if let ownDefault, !EasingCurve.named.contains(ownDefault) { rows.append(item(ownDefault)) }
        if !saved.items.isEmpty {
            rows.append(.heading("Saved"))
            rows += saved.items.map { kept in
                .item(kept.name, isOn: current == kept.curve, image: CurveMenuImage.image(for: kept.curve)) {
                    pick(kept.curve)
                }
            }
        }
        rows.append(.divider)
        // The row reads Custom for a curve of your own, so the menu offers it:
        // ticked while it is on one, and the one it last left otherwise.
        let own = current.flatMap { $0.isDrawn && saved.name(of: $0) == nil ? $0 : nil }
            ?? kept.flatMap { saved.name(of: $0) == nil ? $0 : nil }
        if let own {
            rows.append(.item(StretchCurve.title(own), isOn: current == own,
                              image: CurveMenuImage.image(for: own)) { pick(own) })
        }
        rows.append(.item("Draw a Curve\u{2026}") { isDrawing = true })
        // A saved curve showing can be let go of from the list it is in. What
        // runs on it keeps it, and reads Custom from then on.
        if let current, let name = saved.name(of: current) {
            rows.append(.item("Forget \u{201C}\(name)\u{201D}") { SavedCurveStore.shared.remove(named: name) })
        }
        return rows + extra
    }

    private func item(_ curve: EasingCurve) -> VideoKit.Choice {
        .item(curve.title, isOn: current == curve, image: CurveMenuImage.image(for: curve)) { pick(curve) }
    }
}
