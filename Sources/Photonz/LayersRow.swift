// One row of the layers list: its thumbnail, name, badges and the toggles on its right.

import AppKit
import PhotonzCore
import SwiftUI

struct LayersRow: View, Equatable {
    let display: LayerRowDisplay
    /// The picture beside the name. Compared by identity: the cache hands back
    /// the very same image until the layer itself changes.
    let thumbnail: CGImage?
    /// Whether the list draws a twist column at all — it appears only once the
    /// document HOLDS a group, so a screenshot with a few annotations on it
    /// reads exactly as it always has.
    let showsTwist: Bool
    let componentsEnabled: Bool
    /// The two component menu items, already decided by the list.
    let offersMakeComponent: Bool
    let offersDetachInstance: Bool
    /// Where a drag hovering over THIS row would land, nil when none is.
    let drop: LayerDrop?
    /// What a saved text style held over THIS row would do, nil when none is.
    /// The row is the other obvious place to aim one, so the row has to answer
    /// before the pointer is let go.
    let styleDrop: StyleRowDrop?
    /// The draft name while this row is being renamed, nil the rest of the
    /// time. It is here so the row being typed into redraws on every keystroke
    /// and no other row does.
    let draftName: String?
    let rowHeight: CGFloat

    // Not compared. These are the ways back out to the app and they point at
    // the same state for as long as the list is on screen, so a row still
    // holding last draw's copy behaves exactly like one holding this draw's.
    let editorState: EditorState
    @Binding var renameText: String
    @FocusState.Binding var renameFieldFocused: Bool
    let beginRename: (UUID, String) -> Void
    let commitRename: (UUID) -> Void
    let cancelRename: () -> Void

    nonisolated static func == (a: LayersRow, b: LayersRow) -> Bool {
        a.display == b.display
            && a.thumbnail === b.thumbnail
            && a.showsTwist == b.showsTwist
            && a.componentsEnabled == b.componentsEnabled
            && a.offersMakeComponent == b.offersMakeComponent
            && a.offersDetachInstance == b.offersDetachInstance
            && a.drop == b.drop
            && a.styleDrop == b.styleDrop
            && a.draftName == b.draftName
            && a.rowHeight == b.rowHeight
    }

    private var id: UUID { display.id }
    private var panelRow: LayerPanelRow { display.row }

    /// What a scripted walk sees this row as. The out-of-view mark is part of
    /// it, because a walk that cannot read the mark cannot prove it appeared.
    private var rowDetail: String {
        var parts = [panelRow.isGroup
                     ? (panelRow.isExpanded ? "group, open" : "group, shut")
                     : "layer"]
        if let outOfView = display.outOfView {
            parts.append(outOfView.container.map { "out of view, cut off by \($0)" }
                         ?? "hiding \(outOfView.hiddenInside) out of view")
        }
        // The same words the row prints under its name, so a walk can check
        // which version a row is showing instead of squinting at a picture.
        if componentsEnabled, let version = display.versionName {
            parts.append("showing the \(version) version")
        }
        return parts.joined(separator: ", ")
    }
    private var indent: CGFloat { CGFloat(display.row.depth) * 14 }

    /// One closure for picking this row up, so a scripted walk and a pointer
    /// start the very same drag.
    private var pickUp: @MainActor () -> NSItemProvider {
        {
            editorState.pickUpLayerRow(id)
            return NSItemProvider(object: id.uuidString as NSString)
        }
    }

    var body: some View {
        // Probe-only, and the whole point of it: a walk counts these to prove
        // the list built the rows on screen and not the ninety behind them.
        #if PHOTONZ_PLAYTEST
        let _ = ViewBuildMeter.shared.built(.layersRow)
        #endif
        content
            .onDrag(pickUp)
            // One drop destination for everything a row can be handed, because
            // SwiftUI gives the drag to the innermost target and stops there: a
            // second `onDrop` on the same row would simply hide the first.
            .onDrop(of: LayerRowDropDelegate.acceptedTypes, delegate: LayerRowDropDelegate(
                row: panelRow, rowHeight: rowHeight, editorState: editorState))
            .playtestTarget(display.name, kind: .row,
                            detail: rowDetail,
                            payload: pickUp)
    }

    private var content: some View {
        HStack(spacing: 8) {
            if showsTwist { twistControl }
            thumbnailView
            nameBlock
            // The mark that says the box this layer lives in has cut it off,
            // so a layer dragged too far is never lost with nothing anywhere
            // saying where it went.
            if let outOfView = display.outOfView {
                OutOfViewMark(outOfView: outOfView, name: display.name,
                              place: place, press: { pressOutOfViewMark(outOfView) })
            }
            Spacer(minLength: 4)
            // A shut group says how much it is hiding, so the row is not a
            // dead end you have to open to understand.
            if panelRow.isGroup, !panelRow.isExpanded, showsTwist {
                Text("\(panelRow.childCount)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .panelHelp(panelRow.childCount == 1 ? "1 layer inside" : "\(panelRow.childCount) layers inside")
            }
            Button {
                editorState.toggleLayerLock(id: id)
            } label: {
                Image(systemName: display.isLocked ? "lock.fill" : "lock.open")
                    .font(.system(size: 11))
                    .foregroundStyle(display.isLocked ? .primary : .tertiary)
            }
            .panelHelp(display.isLocked ? "Unlock Layer" : "Lock Layer")
            .playtestControl("Lock", detail: place(display.isLocked ? "locked" : "unlocked"))
            // The slot is what keeps the padlock still: shut and open are two
            // drawings of different widths, and without it locking a layer
            // slid the icon 2pt sideways.
            .panelEdgeIcon("lock", of: display.name)
            Button {
                editorState.toggleLayerVisibility(id: id)
            } label: {
                Image(systemName: display.isVisible ? "eye" : "eye.slash")
                    .font(.system(size: 11))
                    .foregroundStyle(display.isVisible ? .primary : .tertiary)
            }
            .panelHelp(display.isVisible ? "Hide Layer" : "Show Layer")
            .playtestControl("Visibility", detail: place(display.isVisible ? "shown" : "hidden"))
            .panelEdgeIcon("eye", of: display.name)
        }
        .buttonStyle(.borderless)
        .padding(.leading, 6)
        .panelEdgeRowPadding()
        .padding(.vertical, 4)
        .padding(.leading, indent)
        .background {
            if display.isSelected {
                RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.25))
            }
        }
        .background(GeometryReader { proxy in
            Color.clear.preference(key: LayerRowHeightKey.self, value: proxy.size.height)
        })
        .overlay(alignment: .top) { dropLine(.above(id)) }
        .overlay(alignment: .bottom) { dropLine(.below(id)) }
        .overlay {
            // Dropping INSIDE outlines the group itself, so the promise is
            // "this one swallows what you are carrying", never a line that
            // could be read as "next to it".
            if drop == .inside(id) {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
        // A saved style held over this row. The two answers are drawn so they
        // are told apart at a glance rather than read: the accent ring the list
        // already uses for "this one takes it", and the red dashes the panel
        // already uses for "this cannot use what you are holding". The WHY is
        // one line at the foot of the panel, since a sentence will not fit in a
        // row this narrow.
        .overlay {
            if let styleDrop {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(styleDrop.lands ? Color.accentColor : Color.red.opacity(0.55),
                                  style: StrokeStyle(lineWidth: 2,
                                                     dash: styleDrop.lands ? [] : [5, 4]))
                    .background {
                        if styleDrop.lands {
                            RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.12))
                        }
                    }
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        // One tap gesture reads the modifiers itself: shift ranges from the
        // anchor row, command toggles the row, plain selects it. The
        // thumbnail's own command gesture (Select Pixels) sits above this.
        .onTapGesture {
            editorState.clickRow(id, RowClick(modifiers: NSEvent.modifierFlags),
                                 in: editorState.panelRows.map(\.id))
        }
        .contextMenu { menu }
    }

    /// What the row SAYS it is: the name, with the component mark beside it,
    /// and under it the version this drawing is when its component holds more
    /// than one.
    ///
    /// The version sits UNDER the name because side by side the two do not
    /// both fit. At the dock's own width a "Save button" with a "Disabled"
    /// chip after it left the name about 30pt, and the row read as a single
    /// ellipsis: two rows called nothing (2026-09-07). Stacked, the name has
    /// the whole width and so does the version, and the row is no taller for
    /// it, since both lines together are shorter than the thumbnail beside
    /// them and the thumbnail is what sets the row's height.
    private var nameBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if draftName != nil {
                    TextField("Layer name", text: $renameText)
                        .textFieldStyle(.plain)
                        .font(.callout)
                        .focused($renameFieldFocused)
                        .onSubmit { commitRename(id) }
                        // The field does not just close on Return, it hands the
                        // keyboard to the picture. Closing alone leaves the
                        // keyboard on the window, where a tool letter does nothing
                        // at all — a quieter version of the same trap.
                        .nameFieldKeys(commit: { commitRename(id) }, revert: cancelRename)
                        .onChange(of: renameFieldFocused) { _, focused in
                            if !focused { commitRename(id) }
                        }
                } else {
                    Text(display.name)
                        .font(.callout)
                        .lineLimit(1)
                        .foregroundStyle(display.isVisible ? .primary : .tertiary)
                        .onTapGesture(count: 2) { beginRename(id, display.name) }
                }
                // The mark that says this group is a component. It sits with the
                // name rather than out at the edge, because it is part of what the
                // row IS, not one more thing you can do to it. Filled is the
                // original, outlined is a copy that follows it.
                if componentsEnabled, display.isMainComponent || display.isComponentInstance {
                    ComponentMark(isInstance: display.isComponentInstance)
                }
            }
            // Every version of a component carries the component's name, so
            // without this line a button with a Disabled version is two rows
            // both called Button and there is no telling which one you are
            // about to edit.
            if componentsEnabled, let version = display.versionName {
                Text(version)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .panelHelp("This is the \(version) version of \(display.name)")
            }
        }
    }

    /// The twist-open control, in a fixed slot so every row's thumbnail lines
    /// up whether or not the row is a group.
    @ViewBuilder
    private var twistControl: some View {
        if panelRow.isGroup {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(panelRow.isExpanded ? 90 : 0))
                .frame(width: 12, height: 12)
                .contentShape(Rectangle())
                // High priority so the twist wins over the row's own tap: a
                // click on the chevron opens the group, it does not also
                // reselect the row under the pointer.
                .highPriorityGesture(TapGesture().onEnded {
                    withAnimation(.spring(duration: 0.2)) {
                        editorState.toggleGroupExpanded(id: id)
                    }
                })
                .panelHelp(panelRow.isExpanded ? "Hide what is inside" : "Show what is inside")
                // The only way a walk has of opening a group: every row inside
                // a shut one is unbuilt, so nothing below it can be named until
                // this has been pressed.
                .playtestControl("Twist", detail: place(panelRow.isExpanded ? "open" : "shut"))
        } else {
            Color.clear.frame(width: 12, height: 12)
        }
    }

    /// Where a control on this row lives, in the words a walk names it by: the
    /// list, this row, and what the control is saying right now.
    ///
    /// The NAME of an eye stays "Visibility" whichever way it is pointing, so a
    /// walk can press the same thing twice; the part that changes under it goes
    /// here, the way a picker segment says "already on Fixed". It is also what
    /// a press step's `in` matches, so `in: "Label"` reaches this row's eye and
    /// no other row's.
    private func place(_ state: String) -> String {
        "Layers, \(display.name), \(state)"
    }

    /// The mark keeps its own promise. A layer the box around it swallowed
    /// comes back; a shut group that is speaking for something it is hiding
    /// opens, so the row wearing the real mark is on screen to be pressed in
    /// turn. Two presses at the very worst, from a mark somebody noticed
    /// without going looking.
    private func pressOutOfViewMark(_ outOfView: RowOutOfView) {
        if outOfView.container != nil {
            // The layer's own move first, always: moving one layer is a smaller
            // change than resizing the box around it, and only where the layer
            // has no position of its own does the container grow instead.
            if outOfView.canReturn {
                editorState.bringLayerIntoView(id: id)
            } else {
                editorState.makeRoomForLayer(id: id)
            }
        } else {
            withAnimation(.spring(duration: 0.2)) { editorState.toggleGroupExpanded(id: id) }
        }
    }

    private var thumbnailView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(.quaternary)
            if let thumbnail {
                Image(decorative: thumbnail, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .padding(1)
            }
        }
        .frame(width: 40, height: 30)
        .contentShape(Rectangle())
        // ⌘-click on the THUMBNAIL loads the layer's opaque pixels as a
        // selection (Photoshop's load-transparency lives on the thumbnail
        // too); on the rest of the row command-click toggles the row instead.
        .highPriorityGesture(
            TapGesture().modifiers(.command).onEnded { editorState.selectLayerPixels(id: id) }
        )
        .panelHelp("Command-click to select the layer's pixels")
    }

    /// The line that says a drop will land beside a row rather than inside it.
    /// It starts at that row's indent, which is how it names the list the
    /// layers are about to join: a line at the far left means back out on the
    /// canvas.
    @ViewBuilder
    private func dropLine(_ wanted: LayerDrop) -> some View {
        if drop == wanted {
            Capsule()
                .fill(Color.accentColor)
                .frame(height: 2)
                .padding(.leading, indent + 6)
                .padding(.trailing, 6)
        }
    }

    @ViewBuilder
    private var menu: some View {
        Button("Duplicate") { editorState.duplicateLayer(id: id) }
            .keyboardShortcut("d", modifiers: .command)
        Button("Select Pixels") { editorState.selectLayerPixels(id: id) }
        Button("Merge Down") { editorState.mergeDown(id: id) }
            .keyboardShortcut("e", modifiers: .command)
        if display.isRasterizable {
            Button(RasterizePrompt.menuItem) { editorState.rasterizeLayer(id: id) }
        }
        Divider()
        Button("Bring to Front") { editorState.bringLayerToFront(id: id) }
            .keyboardShortcut("]", modifiers: [.command, .shift])
        Button("Bring Forward") { editorState.bringLayerForward(id: id) }
            .keyboardShortcut("]", modifiers: .command)
        Button("Send Backward") { editorState.sendLayerBackward(id: id) }
            .keyboardShortcut("[", modifiers: .command)
        Button("Send to Back") { editorState.sendLayerToBack(id: id) }
            .keyboardShortcut("[", modifiers: [.command, .shift])
        // Only on a row that IS out of view, which is the only row where it
        // would do anything. Same move as the mark on the row, named, for
        // anybody who goes to the menu before they go to a small orange glyph.
        if display.outOfView?.canReturn == true {
            Divider()
            Button("Bring into View") { editorState.bringLayerIntoView(id: id) }
        } else if let container = display.outOfView?.container,
                  display.outOfView?.growsContainer != nil {
            // The same move as the mark on the row, named, for anybody who goes
            // to the menu before they go to a small orange glyph. It names the
            // container because that is the thing that changes.
            Divider()
            Button("Make \(container) Fit") { editorState.makeRoomForLayer(id: id) }
        }
        Divider()
        Button("Rename") { beginRename(id, display.name) }
        if offersMakeComponent {
            Button("Make Component") { editorState.makeComponent() }
                .keyboardShortcut("k", modifiers: [.command, .option])
        }
        if offersDetachInstance {
            Button("Detach Instance") { editorState.detachInstance() }
                .keyboardShortcut("b", modifiers: [.command, .option])
        }
        // Only on an original, and only when it would work: a row that means
        // nothing on the layer you right-clicked is a row people hunt the
        // reason for.
        if display.isMainComponent, editorState.canAddComponentVersion {
            Button("Add Version") { editorState.addComponentVersion() }
        }
        // Only on a piece of an original that has other versions, and it names
        // them, so the row answers "what would this touch" before it is
        // pressed. Same rule as the Layer menu.
        if let title = editorState.applyToOtherComponentVersionsTitle {
            Button(title) { editorState.applyToOtherComponentVersions() }
                .disabled(!editorState.canApplyToOtherComponentVersions)
        }
        // Settings, not actions: the row says what it IS and wears a checkmark,
        // so the menu reads the same whichever state the layer is in and the
        // Delete below it never shifts under the pointer (MenuToggleNames).
        Toggle(MenuToggleNames.layerVisible, isOn: Binding(
            get: { display.isVisible },
            set: { _ in editorState.toggleLayerVisibility(id: id) }))
        Toggle(MenuToggleNames.layerLocked, isOn: Binding(
            get: { display.isLocked },
            set: { _ in editorState.toggleLayerLock(id: id) }))
        Divider()
        // Dimmed on a locked layer, with the Locked toggle right above it: the
        // way out of the greyed row is the line you just read.
        Button("Delete", role: .destructive) { editorState.deleteLayer(id: id) }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(display.isLocked)
    }
}
