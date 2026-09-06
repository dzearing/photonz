import AppKit
import PhotonzCore
import SwiftUI

// MARK: - The mark a component wears (Next, `next-components`)

/// The four-diamond glyph the design system spends on "component"
/// (`docs/design/mocks/shared/icons.mjs`, `ic-component`). One concept, one
/// icon: the same shape appears on the canvas, in the layers list and on the
/// Library tile, so a main is recognisable wherever you meet it.
///
/// It is drawn rather than borrowed from a system symbol because no system
/// symbol means this, and a mark that means something else is worse than none.
enum ComponentGlyph {

    /// The violet the mocks paint components in. A fixed color, NOT the theme
    /// accent: the canvas mark sits on top of whatever picture is open, and the
    /// accent is already spoken for by selection.
    static let color = Color(red: 0x9A / 255, green: 0x5C / 255, blue: 0xFF / 255)
    static let cgColor = CGColor(red: 0x9A / 255, green: 0x5C / 255, blue: 0xFF / 255, alpha: 1)

    /// Four diamonds on the compass points of `rect`, each a quarter of its
    /// short side, which is the shape at any size the app asks for.
    static func path(in rect: CGRect) -> CGPath {
        let side = min(rect.width, rect.height)
        let radius = side * 0.22
        let reach = side * 0.28
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let path = CGMutablePath()
        for offset in [CGPoint(x: 0, y: -reach), CGPoint(x: 0, y: reach),
                       CGPoint(x: -reach, y: 0), CGPoint(x: reach, y: 0)] {
            let point = CGPoint(x: center.x + offset.x, y: center.y + offset.y)
            path.move(to: CGPoint(x: point.x, y: point.y - radius))
            path.addLine(to: CGPoint(x: point.x + radius, y: point.y))
            path.addLine(to: CGPoint(x: point.x, y: point.y + radius))
            path.addLine(to: CGPoint(x: point.x - radius, y: point.y))
            path.closeSubpath()
        }
        return path
    }

    /// The mark a COPY wears: one diamond, in the middle of the same box.
    ///
    /// Not the four-diamond glyph drawn hollow. At the sizes this appears —
    /// nine points on a shelf tile, twelve in a layers row, ten on the canvas —
    /// each of the four diamonds is under three points across, and an outline
    /// at that size is a smudge that reads exactly like the filled one. One
    /// diamond against four is a different SHAPE, so it survives being small,
    /// and it is the distinction a design tool user already has in their eye.
    static func instancePath(in rect: CGRect) -> CGPath {
        let side = min(rect.width, rect.height)
        let radius = side * 0.34
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: center.x, y: center.y - radius))
        path.addLine(to: CGPoint(x: center.x + radius, y: center.y))
        path.addLine(to: CGPoint(x: center.x, y: center.y + radius))
        path.addLine(to: CGPoint(x: center.x - radius, y: center.y))
        path.closeSubpath()
        return path
    }
}

/// The glyph as a SwiftUI shape, for the layers list and the Library tile.
struct ComponentGlyphShape: Shape {
    /// One diamond for a copy, four for the original it follows.
    var isInstance = false

    func path(in rect: CGRect) -> Path {
        Path(isInstance ? ComponentGlyph.instancePath(in: rect) : ComponentGlyph.path(in: rect))
    }
}

/// The mark itself, at the size a list row wants it.
///
/// **Four diamonds is the original, one diamond is a copy.** Both are violet
/// and both read as "component" at a glance, and the shapes are far enough
/// apart to tell at nine points, so you never have to open a panel to know
/// which one you are about to edit.
struct ComponentMark: View {
    var size: CGFloat = 12
    var isInstance = false

    var body: some View {
        ComponentGlyphShape(isInstance: isInstance)
            .fill(ComponentGlyph.color)
            .frame(width: size, height: size)
        .help(isInstance
              ? "A copy of a component. It follows the original."
              : "A component. Copies of it come from the Library.")
    }
}

/// Carrying a component from the Library shelf to the canvas
/// (Next, `next-components`).
///
/// Its own pasteboard type, so a dropped file and a dropped component can never
/// be mistaken for each other, and so a component dragged out of Photonz means
/// nothing anywhere else.
enum ComponentDrag {
    /// DECLARED in the app's Info.plist (`Scripts/build-app.sh`,
    /// `UTExportedTypeDeclarations`). It has to be: an identifier the system
    /// has never heard of is accepted onto the drag pasteboard and then carries
    /// zero bytes, so the canvas sees a component arrive and reads nothing out
    /// of it. That is how Library drag and drop looked broken until 2026-09-03,
    /// and a plain `swift build` binary with no bundle around it still behaves
    /// that way.
    static let typeIdentifier = "com.photonz.component-id"
    static let pasteboardType = NSPasteboard.PasteboardType(typeIdentifier)

    /// The drag a Components tile starts.
    static func itemProvider(componentID: UUID) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: typeIdentifier,
                                            visibility: .ownProcess) { completion in
            completion(Data(componentID.uuidString.utf8), nil)
            return nil
        }
        return provider
    }

    /// The component a pasteboard is carrying, nil for anything else.
    static func componentID(on pasteboard: NSPasteboard) -> UUID? {
        guard let data = pasteboard.data(forType: pasteboardType),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return UUID(uuidString: text)
    }
}

// MARK: - The selected main's own section

/// What the dock says about a main component you have selected: its name, and
/// the plain fact that this is the original.
///
/// The Name field is the same string the layers list renames and the Library
/// tile prints, so there is one name in one place and the three can never
/// disagree. Everything the mock puts here beyond that (exposed properties,
/// variants, an instance count) belongs to the steps that create instances,
/// and is deliberately absent rather than shown as a control that does
/// nothing.
struct ComponentInspector: View {
    @Environment(EditorState.self) private var editorState
    let layer: Layer

    @State private var draft = ""
    @FocusState private var nameFocused: Bool

    private var live: Layer? { editorState.document?.layer(id: layer.id) }
    private var componentID: UUID? { live?.componentID }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Name")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                TextField("Component name", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
                    .focused($nameFocused)
                    // Tab still lands the name and walks on; Return and Escape
                    // go through the name-field rule so they can hand the
                    // keyboard back to the picture as well.
                    .onSubmit(commit)
                    .nameFieldKeys(commit: commit,
                                   revert: { draft = live?.name ?? layer.name })
                    .onChange(of: nameFocused) { _, focused in if !focused { commit() } }
            }
            HStack(spacing: 6) {
                ComponentMark(size: 11)
                Text(standing)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let componentID {
                ComponentVersionList(componentID: componentID, layerID: layer.id)
                ComponentPropertyList(componentID: componentID,
                                      version: live?.componentVersionID)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .onAppear {
            draft = live?.name ?? layer.name
            claimNameIfJustMade()
        }
        // The command that made this component asks for the field: it arrives
        // already named, with the name selected, so typing replaces it and
        // ignoring it leaves a component called "Component".
        .onChange(of: editorState.componentAwaitingName) { _, _ in claimNameIfJustMade() }
        // A rename from the layers list has to show up here too, or the two
        // fields start disagreeing about a name that only exists once.
        .onChange(of: live?.name ?? "") { _, name in
            if !nameFocused { draft = name }
        }
    }

    /// Takes the focus the command handed over, once, and selects the text so
    /// the first keystroke replaces the placeholder name.
    private func claimNameIfJustMade() {
        guard let componentID, editorState.componentAwaitingName == componentID else { return }
        editorState.componentAwaitingName = nil
        draft = live?.name ?? layer.name
        nameFocused = true
        DispatchQueue.main.async { NSApp.keyWindow?.firstResponder?.trySelectAllText() }
    }

    /// What the original says about itself. Once copies exist it says how many,
    /// because "editing this changes eleven other things" is the one fact
    /// somebody about to edit an original needs before they start.
    private var standing: String {
        guard let componentID,
              let count = editorState.document?.instanceCount(of: componentID), count > 0 else {
            return "This is the original. Copies you place will follow it."
        }
        return count == 1
            ? "This is the original. 1 copy follows it."
            : "This is the original. \(count) copies follow it."
    }

    private func commit() {
        guard let componentID else { return }
        guard let name = ComponentNaming.normalized(draft) else {
            draft = live?.name ?? layer.name   // ...a blank name is refused, so put it back
            return
        }
        guard name != live?.name else { return }
        editorState.renameComponent(componentID: componentID, to: name)
    }
}

// MARK: - The picked Components tile's section

/// The section that opens when you pick a component off the shelf. It answers
/// the two questions a tile raises: what is it called, and where is it?
struct LibraryComponentInspector: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        if let main = editorState.selectedComponentLayer, let componentID = main.componentID {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    ComponentMark(size: 12)
                    Text(main.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                Text(inside(main) + versions(componentID) + copies(componentID))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    // Place first: the shelf exists to hand you copies, and the
                    // way back to the original is the secondary errand.
                    Button("Place a Copy") {
                        editorState.insertPickedComponent()
                    }
                    .controlSize(.small)
                    .help("Puts a copy in the middle of the canvas. Dragging the tile places one where you drop it")
                    Button("Select Original") {
                        editorState.selectComponentOnCanvas(componentID: componentID)
                    }
                    .controlSize(.small)
                    .help("Selects the original on the canvas")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
        }
    }

    private func inside(_ main: Layer) -> String {
        main.children.count == 1 ? "1 layer inside" : "\(main.children.count) layers inside"
    }

    /// How many drawings this component holds, when it holds more than one.
    private func versions(_ componentID: UUID) -> String {
        let count = editorState.componentVersions(of: componentID).count
        return count > 1 ? " • \(count) versions" : ""
    }

    private func copies(_ componentID: UUID) -> String {
        let count = editorState.document?.instanceCount(of: componentID) ?? 0
        guard count > 0 else { return "" }
        return count == 1 ? " • 1 copy placed" : " • \(count) copies placed"
    }
}

/// The section that opens when you pick one of the app's own components off
/// the shelf, before it is in the document (Next, `next-starter-components`).
///
/// It says what the thing is for and offers the one useful act. Deliberately
/// short: everything else about it, its name, its knobs, its copies, becomes
/// true the moment it is in the picture, and that is the section that says so.
struct StarterComponentInspector: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        if let starter = editorState.selectedStarterComponent {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    ComponentMark(size: 12)
                    Text(starter.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                Text(starter.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Comes with the app. Adding it puts it in this picture, along with the colors it is painted from.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Add to Picture") {
                    editorState.insertStarterComponent(starter, at: editorState.visibleCanvasCentre)
                }
                .controlSize(.small)
                .help("Puts it in the middle of the canvas. Dragging the tile puts it where you drop it")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
        }
    }
}

// MARK: - One tile on the Components shelf

/// A component on the shelf: a picture of itself, its name, and the word that
/// says it is the original. Click picks it, which is the app's one selection,
/// and double click selects it on the canvas so the shelf is a way back to the
/// thing as well as a list of it.
struct LibraryComponentTile: View {
    @Environment(EditorState.self) private var editorState
    let entry: LibraryEntry
    let layer: Layer
    /// Set when this tile is one of the app's own, still on the shelf rather
    /// than in the document. Everything else about the tile is the same: it is
    /// the same picture, the same drag and the same double click, because the
    /// moment it lands it is an ordinary component.
    var starter: StarterComponent?
    /// How wide the grid made this tile, measured rather than assumed.
    @State private var wellWidth: CGFloat = 0

    private var isSelected: Bool { editorState.selectedLibraryItemID == entry.id }

    var body: some View {
        VStack(spacing: LibraryShelfLayout.captionSpacing) {
            thumbnail
            Text(entry.name)
                .font(.system(size: LibraryShelfLayout.captionFontSize))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        }
        .frame(maxWidth: .infinity)
        .padding(LibraryShelfLayout.tilePadding)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        // Double click PLACES, the way it already does on a Media tile: one
        // gesture for "give me one of these" everywhere on the shelf. Finding
        // the original is the Select Original button in the section below.
        .onTapGesture(count: 2) { place() }
        .onTapGesture { editorState.selectLibraryItem(entry.id) }
        // A picture of the component itself follows the pointer, so picking a
        // tile up looks like picking anything up on a Mac. Nothing in here
        // touches the app's state: a change made while the drag is being handed
        // over redraws the tile and SwiftUI asks for the item all over again.
        .onDrag(dragItem, preview: {
            thumbnail.frame(width: max(wellWidth, LibraryShelfLayout.tileMinimumWidth),
                            height: LibraryShelfLayout.thumbnailHeight)
        })
        .help(helpText)
        // The same closure a walk picks the tile up with, so an unmanned run
        // can never drag something the pointer would not.
        .playtestTarget(entry.name, kind: .tile, detail: "Components", payload: dragItem)
    }

    /// What dragging this tile hands over: the component itself, so the canvas
    /// places a copy where it lands. Nothing in here touches the app's state, so
    /// a change made while the drag is being handed over redraws the tile and
    /// SwiftUI asks for the item all over again.
    private func dragItem() -> NSItemProvider {
        guard let componentID = layer.componentID else { return NSItemProvider() }
        return ComponentDrag.itemProvider(componentID: componentID)
    }

    /// The picture of the component itself.
    ///
    /// A shape that reads whole is drawn whole, inset a little so the tile has
    /// air in it. A shape too long to read that way, which is every nav bar
    /// and every text field, is blown up until it reads and cut off at its far
    /// edge instead: the first half of a nav bar at a size you can see tells
    /// you far more than the whole of one drawn as a nine point grey line.
    private var thumbnail: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(.quaternary)
            .frame(height: LibraryShelfLayout.thumbnailHeight)
            .overlay(alignment: alignment) {
                if let image, placement.size.width > 0 {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .frame(width: placement.size.width, height: placement.size.height)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.primary.opacity(0.12)))
            .overlay(alignment: .topLeading) {
                ComponentMark(size: 9).padding(3)
            }
            // The tile's own width, which is whatever the adaptive grid handed
            // it. How much of a long component fits depends on it, so the tile
            // has to know rather than assume.
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { wellWidth = $0 }
    }

    /// How big the component itself is, which is all that is needed to place
    /// its picture — and is known before the picture has been drawn, so the
    /// tile asks for the right one the first time.
    private var componentSize: CGSize { layer.localBounds.size }

    /// The width of the picture well. Falls back to the narrowest a tile can
    /// be until the grid has said, so the first frame draws something sensible
    /// rather than nothing.
    private var measuredWellWidth: CGFloat {
        wellWidth > 0 ? wellWidth : LibraryShelfLayout.tileMinimumWidth - LibraryShelfLayout.tilePadding * 2
    }

    /// Where the picture sits. Decided against the inset well, because a
    /// picture drawn whole keeps its breathing room; one that has to be cut
    /// off gives that up and goes edge to edge, the way a Media tile does.
    private var placement: LibraryShelfLayout.TilePicture {
        let air = LibraryShelfLayout.picturePadding
        let inset = CGSize(width: measuredWellWidth - air * 2,
                           height: LibraryShelfLayout.thumbnailHeight - air * 2)
        let fitted = LibraryShelfLayout.picture(componentSize, in: inset)
        guard fitted.crop != .none else { return fitted }
        return LibraryShelfLayout.picture(componentSize,
                                          in: CGSize(width: measuredWellWidth,
                                                     height: LibraryShelfLayout.thumbnailHeight))
    }

    /// A cut picture is anchored at the edge it is NOT cut on, so what you see
    /// is the start of the component and reading order does the rest.
    private var alignment: Alignment {
        switch placement.crop {
        case .none: return .center
        case .trailing: return .leading
        case .bottom: return .top
        }
    }

    private var image: CGImage? {
        let pixels = LibraryShelfLayout.pictureSourceDimension(for: placement.size)
        if let starter { return editorState.starterThumbnail(starter, dimension: pixels) }
        return editorState.shelfThumbnail(for: layer, dimension: pixels)
    }

    private var helpText: String {
        guard let starter else {
            return "\(entry.name), \(entry.detail). Drag it onto the canvas, or double click to place one."
        }
        return "\(starter.summary) Drag it onto the canvas, or double click to place one."
    }

    private func place() {
        guard let componentID = layer.componentID else { return }
        editorState.selectLibraryItem(entry.id)
        editorState.placeComponent(componentID: componentID, at: editorState.visibleCanvasCentre)
    }
}


// MARK: - A copy's own section

/// What the dock says about a copy you have selected: which component it
/// follows, and the way back to that original.
///
/// It deliberately offers nothing to change inside the copy. Its contents
/// belong to the original, so a control here that edited a piece would be a
/// control whose effect the next edit of the original silently undoes. Reaching
/// in on purpose is what exposed properties and detach are for, and they are
/// the next step.
struct ComponentInstanceInspector: View {
    @Environment(EditorState.self) private var editorState
    /// The copies this section speaks for. One or five, it is the same value
    /// and the same rows: picking a second copy changes what a row ANSWERS FOR,
    /// never whether the section is on screen.
    let selection: ComponentKnobSelection

    private var main: Layer? {
        selection.componentID.flatMap { editorState.document?.mainComponent(componentID: $0) }
    }
    /// The one copy picked, when exactly one is. What only makes sense for a
    /// single copy hangs off this.
    private var only: UUID? { selection.count == 1 ? selection.instances.first : nil }

    var body: some View {
        if selection.hasDifferentComponents {
            // Every picked copy has knobs, so the section applies; they just
            // have none in COMMON. A panel that silently went blank here would
            // read as a fault, so it says which it is.
            Text(ComponentKnobSelection.differentComponentsNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
        } else if let componentID = selection.componentID, let main {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    ComponentMark(size: 12, isInstance: true)
                    Text(main.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                // How many of the picked layers these rows reach, when it is
                // not all of them: a locked copy, or something picked
                // alongside that is not a copy at all.
                if let reach = selection.reachNote {
                    Text(reach)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ComponentInstanceProperties(selection: selection)
                offer
                ownSize
                ownLook
                HStack(spacing: 6) {
                    Button("Edit Original") {
                        // The version this copy is SHOWING, or the button takes
                        // you to a drawing you were not looking at.
                        editorState.selectComponentOnCanvas(componentID: componentID,
                                                            version: selection.version)
                    }
                    .controlSize(.small)
                    .help("Selects the drawing this copy shows, which is where a change to every copy of it is made")
                    // Detach is here as well as in the Layer menu, because a
                    // command that lives only in a menu is a command nobody
                    // finds. It is not destructive styling: nothing is deleted,
                    // the copy simply stops following, and undo is the way back.
                    Button("Detach") { editorState.detachInstance() }
                        .controlSize(.small)
                        .disabled(!editorState.canDetachInstance)
                        .help(selection.count == 1
                              ? "Turns this copy into ordinary layers that no longer follow the original"
                              : "Turns all \(selection.count) copies into ordinary layers that no longer follow the original")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
        }
    }

    /// What the section says the selection IS, in the same place for one copy
    /// and for five.
    private var summary: String {
        selection.count == 1
            ? "A copy. Editing the original changes this one too."
            : "\(selection.count) copies. Editing the original changes them all."
    }

    /// The way out of a refused edit, on the copy you were trying to edit.
    ///
    /// Double clicking words the original never made adjustable says so in a
    /// notice, and the notice would be advice with nowhere to act on it: the
    /// piece is not selectable, so the Adjustable list on the ORIGINAL is the
    /// only way in and it is two selections away. This is that press, here,
    /// while it is still what you were doing.
    @ViewBuilder private var offer: some View {
        if let only, let piece = editorState.wordingOffer(for: only) {
            let name = editorState.document?.componentPieceName(of: piece) ?? "that piece"
            Button("Make \(name) Adjustable") { editorState.takeWordingOffer(piece) }
                .controlSize(.small)
                .help("Adds a Wording knob for \(name) on the original, so every copy can say something different")
                .playtestControl("Make \(name) Adjustable")
        }
    }

    /// The size this copy was given for itself, and the one way back to the
    /// original's.
    ///
    /// A copy takes a width and a height like any other layer now, one axis at
    /// a time, so the same nav bar is 1200 wide on a desktop screen and 375 on
    /// a phone without either one leaving the family. That is worth saying out
    /// loud somewhere: a copy that quietly ignores the original's width is a
    /// copy nobody can explain, and the W and H boxes look the same whether the
    /// number in them is the copy's answer or the original's.
    ///
    /// It is one row and one press rather than a way back on each of W and H,
    /// because "make it the size the original is" is the whole errand, and the
    /// row above the button already says which sides are the copy's.
    @ViewBuilder private var ownSize: some View {
        if let own = editorState.instanceOwnSizeLabel(instances: selection.instances) {
            Divider().padding(.vertical, 2)
            HStack(spacing: 6) {
                Text("Its own size")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 74, alignment: .leading)
                Text(own)
                    .font(.caption)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button {
                    editorState.clearInstanceSize(instances: selection.instances)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Be the size of the original again")
                .playtestControl("Revert Size")
            }
        }
    }

    /// What this copy has styled for itself, and one way back to the original's
    /// look.
    ///
    /// The Effects and Shadow rows carry their own way back, which is where the
    /// person who just dragged a slider is looking. This says the same thing
    /// where a copy answers about itself, because Effects is a different
    /// section and may be collapsed or scrolled away: without it, a copy you
    /// faded weeks ago is a copy that mysteriously ignores the original.
    @ViewBuilder private var ownLook: some View {
        if let own = editorState.instanceOwnLookLabel(instances: selection.instances) {
            Divider().padding(.vertical, 2)
            HStack(spacing: 6) {
                Text("Its own look")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 74, alignment: .leading)
                Text(own)
                    .font(.caption)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button {
                    editorState.clearInstanceStyleOverrides(instances: selection.instances)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Follow the original's look again, every part of it")
            }
        }
    }
}

/// What the dock says about a PIECE inside a copy: the copy it belongs to, the
/// knobs that copy can set, and the two ways out if the piece you want is not
/// one of them.
///
/// Clicking into a copy lands you here, and before this section existed the
/// panel had nothing to say: it showed the piece's own Text and Color rows,
/// every one of which is written over the moment the copy is put back in step
/// with its original. The piece has nothing of its own, so the section answers
/// for the copy instead.
struct ComponentPieceInspector: View {
    @Environment(EditorState.self) private var editorState
    let piece: ComponentPiece

    private var main: Layer? { editorState.document?.mainComponent(componentID: piece.componentID) }
    private var pieceName: String { editorState.document?.componentPieceName(of: piece) ?? "This piece" }

    /// Whether the piece you clicked into could be made typeable in one press.
    private var canExposeWording: Bool { editorState.canExposePieceWording(of: piece.layer) }

    var body: some View {
        if let main {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    ComponentMark(size: 12, isInstance: true)
                    Text(main.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                Text("\(pieceName) is part of a copy. What it shows comes from the original, so it is set with the knobs below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ComponentInstanceProperties(
                    selection: editorState.componentKnobSelection(instances: [piece.instance]))
                if canExposeWording {
                    Button("Make Its Wording Adjustable") {
                        editorState.exposePieceWording(of: piece.layer)
                    }
                    .controlSize(.small)
                    .help("Adds a Wording knob for \(pieceName) on the original, so every copy can say something different")
                    .playtestControl("Make Its Wording Adjustable")
                }
                HStack(spacing: 6) {
                    Button("Select Copy") { editorState.selectEnclosingCopy(of: piece) }
                        .controlSize(.small)
                        .help("Picks the whole copy, which is what moves, resizes and detaches")
                        .playtestControl("Select Copy")
                    Button("Edit Original") {
                        editorState.selectComponentOnCanvas(componentID: piece.componentID)
                    }
                    .controlSize(.small)
                    .help("Selects the original, which is where a change to every copy is made")
                    Button("Detach") { editorState.detachEnclosingCopy(of: piece) }
                        .controlSize(.small)
                        .help("Turns this copy into ordinary layers, so every piece of it can be edited directly")
                        .playtestControl("Detach")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
        }
    }
}

/// The way back on ONE part of a copy's look, on the control that sets it.
///
/// It is there only when this layer is a copy and that part is its own, so an
/// ordinary layer's Effects section is exactly what it always was, and a copy
/// that follows the original shows nothing to put back.
struct InstanceStyleRevert: View {
    @Environment(EditorState.self) private var editorState
    let layerID: UUID
    let field: LayerStyleField

    var body: some View {
        if editorState.isInstanceStyleOwn(instance: layerID, field: field) {
            Button {
                editorState.clearInstanceStyleOverride(instance: layerID, field: field)
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("This copy's own \(field.label.lowercased()). Follow the original again")
            // Named for what it puts back, so the three or four that can be on
            // screen at once are told apart by their own words rather than by
            // which row a walk remembered to say.
            .playtestControl("Revert \(field.label)")
        }
    }
}

extension NSResponder {
    /// Selects everything in a text field that has just taken focus. SwiftUI
    /// gives a `TextField` focus with the caret at the end, and a placeholder
    /// name you have to select by hand is a placeholder you retype by hand.
    func trySelectAllText() {
        (self as? NSText)?.selectAll(nil)
    }
}

// MARK: - The versions a component holds (Next, `next-components`)

/// The versions of the selected original: which drawing you are looking at,
/// what the others are called, and the one press that makes another
/// (`ComponentVersions`).
///
/// A button has a normal look, a hover look and a disabled look, and before
/// this those were three components that drifted apart the first time anybody
/// edited one. A version is a second complete drawing under the same name, and
/// it is an ORDINARY drawing on the canvas: every tool already works on it,
/// which is why the row that takes you to one simply selects it.
///
/// A component with one version says so in a sentence rather than showing a
/// list of one, because a list of one is a control that looks like it is
/// missing something.
struct ComponentVersionList: View {
    @Environment(EditorState.self) private var editorState
    let componentID: UUID
    /// The drawing that is selected, so the list can say which one you are on.
    let layerID: UUID

    private var versions: [ComponentVersion] { editorState.componentVersions(of: componentID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().padding(.vertical, 2)
            HStack(spacing: 6) {
                Text("Versions")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button {
                    editorState.addComponentVersion(componentID: componentID,
                                                    from: editorState.document?
                                                        .layer(id: layerID)?.componentVersionID)
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(.borderless)
                .fixedSize()
                .help("Copies this drawing into a second version of the same component, so a copy can show either")
                .playtestControl("Add Version")
            }
            if versions.count > 1 {
                ForEach(versions) { version in
                    ComponentVersionRow(componentID: componentID, version: version,
                                        isShown: version.layerID == layerID)
                }
            } else {
                Text("One drawing. Adding a version copies it, so this component can hold a second look, like Disabled, under the same name.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// One version on the original's section: the one you are looking at wears an
/// editable name, and every other one is a press that takes you to it.
///
/// The name is a field only on the drawing you are ON. A field for a drawing
/// somewhere else would let you rename a thing you cannot see, and the press
/// beside it is the honest way there: it selects that drawing, which is what
/// editing a version means.
private struct ComponentVersionRow: View {
    @Environment(EditorState.self) private var editorState
    let componentID: UUID
    let version: ComponentVersion
    let isShown: Bool

    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            ComponentMark(size: 10)
                .opacity(isShown ? 1 : 0.35)
            if isShown {
                TextField("Version name", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .focused($focused)
                    .onSubmit(commit)
                    .nameFieldKeys(commit: commit, revert: { draft = version.name })
                    .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
                Text("showing")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.quaternary))
            } else {
                Button(version.name) {
                    editorState.selectComponentVersion(componentID: componentID, version: version.id)
                }
                .buttonStyle(.link)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .help("Selects this version on the canvas, which is where it is edited")
                .playtestControl(version.name)
                Spacer(minLength: 0)
            }
        }
        .onAppear {
            draft = version.name
            claimNameIfJustAdded()
        }
        .onChange(of: editorState.componentVersionAwaitingName) { _, _ in claimNameIfJustAdded() }
        .onChange(of: version.name) { _, name in if !focused { draft = name } }
    }

    /// Takes the focus Add Version handed over, once, and selects the name so
    /// the first keystroke replaces it. A version arrives called "Version 2",
    /// which is honest and says nothing; "Disabled" is one word of typing.
    private func claimNameIfJustAdded() {
        guard isShown, editorState.componentVersionAwaitingName == version.id else { return }
        editorState.componentVersionAwaitingName = nil
        draft = version.name
        focused = true
        DispatchQueue.main.async { NSApp.keyWindow?.firstResponder?.trySelectAllText() }
    }

    private func commit() {
        guard let name = ComponentNaming.normalized(draft) else {
            draft = version.name   // ...a blank name is refused, so put it back
            return
        }
        guard name != version.name else { return }
        editorState.renameComponentVersion(componentID: componentID, version: version.id, to: name)
    }
}

// MARK: - What the original makes adjustable (Next, `next-components`)

/// The knobs an original exposes, on the original's own section
/// (`docs/design/ui-building.md`, step C6).
///
/// This is the half of "override safely" that belongs to the author: they
/// decide, once, which parts of the thing they drew are adjustable, and every
/// copy gets exactly those and nothing else. The list is deliberately on the
/// ORIGINAL and not on a copy, because that is where the decision is made and
/// where it applies to every copy at once.
struct ComponentPropertyList: View {
    @Environment(EditorState.self) private var editorState
    let componentID: UUID
    /// Which version's knobs these are. Each version of a component is a
    /// drawing of its own and carries its own knobs, pointed at its own layers,
    /// so the list belongs to the drawing you have selected and not to the
    /// component as a whole (`ComponentVersions`).
    var version: UUID?

    private var properties: [ComponentProperty] {
        editorState.componentProperties(of: componentID, version: version)
    }

    private var candidates: [ComponentPropertyCandidate] {
        editorState.componentPropertyCandidates(componentID: componentID, version: version)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().padding(.vertical, 2)
            HStack(spacing: 6) {
                Text("Adjustable")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                addMenu
            }
            if properties.isEmpty {
                Text("Nothing yet. Anything you add here is a knob every copy can set on its own.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(properties) { property in
                    ComponentPropertyRow(componentID: componentID, version: version,
                                         property: property)
                }
            }
        }
    }

    /// The Add menu, grouped by KIND rather than by layer.
    ///
    /// The mock lists every layer with every knob it could make; on a component
    /// of eight layers that is a menu of twenty-four rows, most of them
    /// meaningless. Here the three kinds are the headings, and under each one
    /// sit only the layers that knob makes sense for: wording under a text
    /// layer, a choice under a group with alternatives in it. A layer already
    /// exposed one way does not appear that way twice.
    ///
    /// A row for a text layer nobody has named shows what it says, because
    /// otherwise two of them are two rows both reading "Text". That is the only
    /// place the words belong: read once while choosing, never kept as a name.
    @ViewBuilder private var addMenu: some View {
        Menu {
            if candidates.isEmpty {
                Text("Nothing left to expose")
            }
            ForEach(ComponentPropertyKind.allCases, id: \.self) { kind in
                let rows = candidates.filter { $0.kinds.contains(kind) }
                if !rows.isEmpty {
                    Section(kind.label) {
                        ForEach(rows, id: \.layerID) { candidate in
                            if kind == .color {
                                // A colour row names the PART, because one box
                                // has both a fill and an outline and a row
                                // reading "Box" would not say which you were
                                // about to hand to every copy.
                                ForEach(candidate.colorSlots, id: \.self) { slot in
                                    Button("\(candidate.pathLabel) \u{00B7} \(slot.selectionTitle)") {
                                        editorState.addComponentProperty(componentID: componentID,
                                                                         version: version,
                                                                         target: candidate.layerID,
                                                                         kind: kind, slot: slot)
                                    }
                                }
                            } else if kind == .number {
                                // And a number row names WHICH number, for the
                                // same reason: one box has a rounding and a
                                // thickness.
                                ForEach(candidate.numberSlots, id: \.self) { slot in
                                    Button("\(candidate.pathLabel) \u{00B7} \(slot.title)") {
                                        editorState.addComponentProperty(componentID: componentID,
                                                                         version: version,
                                                                         target: candidate.layerID,
                                                                         kind: kind,
                                                                         numberSlot: slot)
                                    }
                                }
                            } else {
                                Button(candidate.menuLabel) {
                                    editorState.addComponentProperty(componentID: componentID,
                                                                     version: version,
                                                                     target: candidate.layerID,
                                                                     kind: kind)
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            Label("Add", systemImage: "plus")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(candidates.isEmpty)
        .help("Choose a piece of this component and how copies may change it")
    }
}

/// One knob on the original: what it is called, what kind it is, and a way to
/// take it away again.
private struct ComponentPropertyRow: View {
    @Environment(EditorState.self) private var editorState
    let componentID: UUID
    var version: UUID?
    let property: ComponentProperty

    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            TextField("Knob name", text: $draft)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .focused($focused)
                .onSubmit(commit)
                .nameFieldKeys(commit: commit, revert: { draft = property.name })
                .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            Text(property.kind.chip)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(.quaternary))
            Button {
                editorState.removeComponentProperty(componentID: componentID, version: version,
                                                    propertyID: property.id)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Stop letting copies change this. Copies go back to showing what the original shows")
        }
        .onAppear {
            draft = property.name
            claimNameIfJustAdded()
        }
        .onChange(of: editorState.componentPropertyAwaitingName) { _, _ in claimNameIfJustAdded() }
        .onChange(of: property.name) { _, name in if !focused { draft = name } }
    }

    /// Takes the focus the Add menu handed over, once, and selects the name so
    /// the first keystroke replaces it.
    ///
    /// A knob arrives named for what it does ("Wording"), which is honest but
    /// says nothing about WHICH wording. Landing in the field means the author
    /// types "Label" while they are still thinking about it, and ignoring the
    /// field leaves a name that is at least never wrong.
    private func claimNameIfJustAdded() {
        guard editorState.componentPropertyAwaitingName == property.id else { return }
        editorState.componentPropertyAwaitingName = nil
        draft = property.name
        focused = true
        DispatchQueue.main.async { NSApp.keyWindow?.firstResponder?.trySelectAllText() }
    }

    private func commit() {
        guard let name = ComponentNaming.normalized(draft) else {
            draft = property.name   // ...a blank name is refused, so put it back
            return
        }
        guard name != property.name else { return }
        editorState.renameComponentProperty(componentID: componentID, version: version,
                                            propertyID: property.id, to: name)
    }
}

// MARK: - Setting a knob on one copy

/// The knobs a copy can set, on the copy's own section.
///
/// Only what the original exposed appears here, so a copy can be adjusted
/// without any way to drift: there is no control for anything else inside it,
/// and a choice offers only the shapes the original holds.
struct ComponentInstanceProperties: View {
    @Environment(EditorState.self) private var editorState
    /// The copies these rows speak for, and what each knob reads across them.
    let selection: ComponentKnobSelection

    private var properties: [ComponentProperty] { selection.properties }
    private var instances: [UUID] { selection.instances }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if selection.hasVersions || !properties.isEmpty {
                Divider().padding(.vertical, 2)
            }
            versionRow
            if properties.isEmpty {
                Text("The original has not made anything adjustable yet. Select it and add a knob there.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(properties) { property in
                    HStack(spacing: 6) {
                        Text(property.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(width: 74, alignment: .leading)
                        control(for: property)
                        revert(property)
                    }
                }
            }
        }
    }

    /// Which version of its component this copy shows (`ComponentVersions`).
    ///
    /// It sits above the knobs because it is the biggest thing about a copy:
    /// a knob changes one fact, a version changes the whole drawing. It is only
    /// here at all while the component holds more than one, so a component with
    /// one drawing shows exactly the panel it always did.
    ///
    /// Copies showing different versions read Mixed in the closed menu, the way
    /// every other row on this panel does, and choosing a version puts all of
    /// them on it.
    @ViewBuilder private var versionRow: some View {
        if selection.hasVersions {
            HStack(spacing: 6) {
                Text("Version")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 74, alignment: .leading)
                Picker("", selection: Binding(
                    get: { selection.version ?? Self.mixedOption },
                    set: { chosen in
                        guard chosen != Self.mixedOption else { return }
                        editorState.setInstanceVersion(instances: instances, to: chosen)
                    })) {
                    if selection.hasMixedVersions {
                        Text(MixedValue.text)
                            .foregroundStyle(MixedLook.style)
                            .tag(Self.mixedOption)
                    }
                    ForEach(selection.versions) { version in
                        Text(version.name).tag(version.id)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .help("Which drawing of this component the copy shows. Everything you have set on the copy comes with it")
            }
        }
    }

    @ViewBuilder private func control(for property: ComponentProperty) -> some View {
        let reading = selection.reading(property.id)
        let isMixed = reading == .mixed
        switch property.kind {
        case .text:
            InstanceTextKnob(instances: instances, property: property,
                             live: reading.textValue ?? "", isMixed: isMixed)
        case .visible:
            InstanceShowKnob(name: property.name, isOn: reading.boolValue ?? true,
                             isMixed: isMixed) { on in
                editorState.setInstanceOverride(instances: instances, property: property.id,
                                                value: .visible(on))
            }
            Spacer(minLength: 0)
        case .variant:
            // Labels rather than raw names: two rectangles drawn in a row are
            // both called "Rectangle", and a menu of identical rows is a menu
            // nobody can choose from.
            let options = editorState.componentVariantOptionLabels(
                componentID: selection.componentID ?? UUID(), version: selection.version,
                propertyID: property.id)
            // The closed title is where a menu shows its value, so that is
            // where Mixed goes: a row the copies disagree on offers the word
            // rather than picking one copy's shape and printing it as if it
            // were everybody's. The word is a row of the menu's own, drawn one
            // step quieter, which is what the closed title then wears —
            // measured against a real value in the same shot on 2026-09-05.
            Picker("", selection: Binding(
                get: {
                    isMixed ? Self.mixedOption
                        : (reading.optionValue ?? options.first?.id ?? Self.mixedOption)
                },
                set: { chosen in
                    // Mixed is a report about the selection, not a state
                    // anybody can set, so landing back on it does nothing.
                    guard chosen != Self.mixedOption else { return }
                    editorState.setInstanceOverride(instances: instances, property: property.id,
                                                    value: .variant(chosen))
                })) {
                if isMixed {
                    Text(MixedValue.text)
                        .foregroundStyle(MixedLook.style)
                        .tag(Self.mixedOption)
                }
                ForEach(options, id: \.id) { option in
                    Text(option.label).tag(option.id)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .help("Only the shapes the original holds. A copy can never show something it does not define")
        case .color:
            InstanceColorKnob(instances: instances, property: property)
        case .number:
            InstanceNumberKnob(instances: instances, property: property,
                               value: isMixed ? nil : reading.numberValue)
            Spacer(minLength: 0)
        }
    }

    /// The row the menu shows while the copies disagree. It is never an answer
    /// anybody can land on: choosing it is ignored.
    private static let mixedOption = UUID()

    /// The way back. Without it a copy that was set once can only be put right
    /// by undoing, and an override made ten edits ago is out of undo's reach.
    /// It reaches every picked copy, in one step, like every other control here.
    @ViewBuilder private func revert(_ property: ComponentProperty) -> some View {
        let own = selection.isOverridden(property.id)
        Button {
            editorState.clearInstanceOverride(instances: instances, property: property.id)
        } label: {
            Image(systemName: "arrow.uturn.backward")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .opacity(own ? 1 : 0)
        .disabled(!own)
        .help(selection.count == 1
              ? "Follow the original again for this one"
              : "Every picked copy follows the original again for this one")
    }
}

/// A show-or-hide knob over the picked copies.
///
/// A Mac switch has on and off and nothing else, so this is the one control the
/// look rule cannot simply be dropped into. The answer, from
/// `UX-PATTERNS.md` §4: it stays a switch, it wears the word beside it, it is
/// drawn one step quieter while it has no position to show, and the first press
/// resolves to ON for every picked copy. It never returns to Mixed, because
/// Mixed is a report about the selection rather than a state anybody can set.
private struct InstanceShowKnob: View {
    /// The knob's own name, so the switch answers to it: a control with no
    /// words in it is a control nothing can name otherwise.
    let name: String
    let isOn: Bool
    let isMixed: Bool
    let set: (Bool) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Toggle("", isOn: Binding(get: { isMixed ? false : isOn },
                                     set: { set(isMixed ? true : $0) }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .accessibilityLabel(name)
                // Named for the knob, said to be one: a document can hold a
                // LAYER called Picture too, and two controls with one name is
                // a walk that cannot say which it meant.
                .playtestControl(name, detail: "a knob on the copies")
                // Off is a true answer — none of them have it — so a
                // disagreeing selection may not borrow it at full strength.
                .opacity(isMixed ? MixedLook.controlOpacity : 1)
            // The word goes beside the switch rather than inside it: there is
            // no room in the control, and this row has no trailing column for
            // it to collide with.
            if isMixed { MixedWord() }
        }
    }
}

/// A number knob on a copy: the same typed field every number in the inspector
/// is, speaking for the copies it is given rather than for a layer.
///
/// It is a `LayoutNumberField`, the same control the Gap and Padding rows on the
/// canvas are, so the arrow keys, Return landing the number and handing the
/// keyboard back to the picture, the rounding and the word Mixed are all decided
/// in one place and the two can never drift apart.
private struct InstanceNumberKnob: View {
    @Environment(EditorState.self) private var editorState
    /// The copies this row answers for. Mixed is what it says when they differ.
    let instances: [UUID]
    let property: ComponentProperty
    /// The number they all wear, or nil while they disagree.
    let value: CGFloat?

    var body: some View {
        LayoutNumberField(
            title: property.name,
            value: value,
            // Mixed is a report about the selection, so it stands in the
            // field's own place, drawn the one strength every other Mixed in
            // the dock is drawn at.
            placeholder: value == nil ? MixedValue.text : "",
            help: property.numberSlot?.help ?? ""
        ) { number in
            editorState.setInstanceOverride(instances: instances, property: property.id,
                                            value: .number(number))
        }
        .playtestField(property.name)
    }
}

/// A colour knob on a copy: the same swatch, the same picker and the same list
/// of saved colours every other colour in the app gets, speaking for the copies
/// it is given rather than for a layer.
///
/// Two controls and no more. The swatch IS the readout and the button: click it
/// and the app's own picker opens on the colour this copy is wearing. Beside it
/// is the palette menu, which is where a saved colour becomes the answer, so a
/// copy can be "the danger one" rather than "the #CC2222 one" and stays right
/// when that colour is edited later.
///
/// There is deliberately no Save as Style here. The picker this opens already
/// offers it, and a second way to save inside a 264pt dock is a crowded row for
/// an errand you do once.
private struct InstanceColorKnob: View {
    @Environment(EditorState.self) private var editorState
    /// The copies this row answers for. One today; the shape is plural because
    /// the reading already is, and Mixed is what it says when they differ.
    let instances: [UUID]
    let property: ComponentProperty

    @State private var isHovering = false

    private var slot: ColorSlot { property.slot ?? .fill }
    private var selection: ColorStyleSelection {
        editorState.componentColorSelection(instances: instances, property: property.id)
    }
    /// Only the saved colours kept for the part this knob paints, scoped the
    /// same way the canvas row scopes them.
    private var styles: [ColorStyle] {
        editorState.componentColorStyles(instances: instances, property: property.id)
    }
    /// What this well answers to, so only one picker is ever open and a walk
    /// can open this one without a pointer.
    private var wellKey: String { "knob.\(property.id.uuidString)" }

    var body: some View {
        let selection = self.selection
        if selection.isEmpty {
            // The original has no colour in that part any more, so there is
            // nothing for this copy to follow and nothing to set.
            Text("No color")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .help("The original has no \(property.name.lowercased()) any more, "
                      + "so there is nothing for this copy to change")
            Spacer(minLength: 0)
        } else {
            well(selection)
            if editorState.colorStylesEnabled { stylesMenu(selection) }
            Spacer(minLength: 0)
        }
    }

    private func well(_ selection: ColorStyleSelection) -> some View {
        Button { editorState.openColorWell = wellKey } label: { label(selection) }
            .buttonStyle(.plain)
            // A readout and a control look alike sitting still, so the hairline
            // firms up under the pointer: that is what says this one is worth
            // clicking.
            .onHover { isHovering = $0 }
            .help(help(selection))
            .accessibilityLabel("\(property.name) color")
            // The same word every colour well in the panel answers to, its own
            // knob saying which one: `press "Color" in "Fill"`.
            .playtestControl("Color", detail: property.name)
            .popover(isPresented: editorState.colorWellBinding(wellKey), arrowEdge: .top) {
                ColorPickerContent(editorState: editorState,
                                   paint: openingPaint(selection),
                                   name: property.name,
                                   slot: slot,
                                   supportsOpacity: true,
                                   supportsGradient: slot.acceptsGradient,
                                   onClose: { editorState.openColorWell = nil },
                                   // Live while the pointer is down, so the
                                   // copy follows the drag; ONE step, and one
                                   // recents entry, when it is let go of.
                                   onPreview: { paint in
                    editorState.previewInstanceColor(instances: instances,
                                                     property: property.id, paint: paint)
                }) { paint in
                    editorState.setInstanceColor(instances: instances,
                                                 property: property.id, paint: paint)
                }
            }
    }

    @ViewBuilder private func label(_ selection: ColorStyleSelection) -> some View {
        if selection.reading == .mixed {
            // A chip rather than bare text: the same height and hairline as the
            // swatch it replaces, so a row that says Mixed still looks like a
            // row with something to press.
            Text(ColorStyleSelection.mixedText)
                .font(.caption)
                .foregroundStyle(isHovering ? AnyShapeStyle(.primary) : MixedLook.style)
                .padding(.horizontal, 6)
                .frame(height: 18)
                .background(RoundedRectangle(cornerRadius: 4).fill(.quaternary))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(edge, lineWidth: 1))
        } else {
            PaintFill(paint: shownPaint(selection))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                // Under a colour that can be see-through, so a translucent fill
                // reads as translucent rather than as a paler one.
                .background(CheckerBoard(square: 4).clipShape(RoundedRectangle(cornerRadius: 4)))
                .frame(width: 18, height: 18)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(edge, lineWidth: 1))
        }
    }

    /// The saved-colour menu, the same three states the canvas row has: wearing
    /// a name, wearing several, or wearing none.
    @ViewBuilder private func stylesMenu(_ selection: ColorStyleSelection) -> some View {
        let style = selection.boundStyleID.flatMap { id in
            editorState.colorStyles.first { $0.id == id }
        }
        Menu {
            if let style {
                Section("Using \(style.name)") {
                    Button("Edit \(style.name) in the Library") {
                        editorState.selectLibraryItem(style.id.uuidString)
                    }
                    Button("Unlink") {
                        editorState.unlinkInstanceColorStyle(instances: instances,
                                                             property: property.id)
                    }
                }
            }
            if !styles.isEmpty {
                Section(offerTitle) {
                    ForEach(styles) { option in
                        Button {
                            editorState.setInstanceColorStyle(instances: instances,
                                                              property: property.id,
                                                              styleID: option.id)
                        } label: {
                            Label {
                                Text(option.name)
                            } icon: {
                                Image(systemName: option.id == style?.id
                                      ? "checkmark.circle.fill" : "circle.fill")
                            }
                        }
                    }
                }
            } else if !editorState.colorStyles.isEmpty {
                // There ARE saved colours, they are just kept for other parts.
                Section("Your saved colors are for other parts") {
                    Button("Change what one is for in the Library") {
                        editorState.showColorStyleShelf()
                    }
                }
            } else {
                Text("No saved colors yet")
            }
        } label: {
            if let style {
                HStack(spacing: 3) {
                    Image(systemName: "swatchpalette")
                    Text(style.name)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } else {
                Image(systemName: "swatchpalette")
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(style.map { "This copy uses the saved color \($0.name)" }
              ?? "Use a saved color for this, so editing that color moves every copy that points at it")
    }

    /// What the list of saved colours is headed. It names the part, so a short
    /// list reads as scoped rather than as colours having gone missing.
    private var offerTitle: String {
        let noun = property.name.lowercased()
        return noun == "color" ? "Saved colors" : "Saved colors for \(noun)"
    }

    /// The paint the swatch draws: whatever is in flight during a drag, else
    /// what the copies are wearing.
    private func shownPaint(_ selection: ColorStyleSelection) -> Paint {
        editorState.previewedInstanceColor(instances: instances, property: property.id)
            ?? selection.members.first?.paint ?? Paint(hex: "#FFFFFF")
    }

    /// The colour the picker opens on: the one they share, so opening a
    /// gradient shows you the gradient rather than flattening it on the click.
    private func openingPaint(_ selection: ColorStyleSelection) -> Paint {
        selection.savablePaint ?? selection.members.first?.paint ?? Paint(hex: "#FFFFFF")
    }

    private var edge: Color { .primary.opacity(isHovering ? 0.55 : 0.25) }

    private func help(_ selection: ColorStyleSelection) -> String {
        guard selection.count > 1 else {
            return "Sets this copy\u{2019}s \(property.name.lowercased()). "
                + "The original, and every copy that has not been given one, keeps following it"
        }
        return "Sets the \(property.name.lowercased()) of all \(selection.count) of them, in one step"
    }
}

/// A wording knob on a copy: a field that lands its text the way every other
/// field in the dock does, on Return and on clicking away, so typing a label
/// is not one undo step per keystroke.
private struct InstanceTextKnob: View {
    @Environment(EditorState.self) private var editorState
    /// The copies this field answers for. Typing lands on every one of them, in
    /// one undo step.
    let instances: [UUID]
    let property: ComponentProperty
    /// The words they share, empty while they differ.
    let live: String
    let isMixed: Bool

    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        // The knob's own name is the placeholder, so an emptied field still
        // says what it is, and a scripted playtest can reach the field by name.
        // While the copies differ the box holds the word instead: a field that
        // went blank would say "they differ" and "nothing is set here" in
        // exactly the same way, and those are different answers.
        TextField(isMixed ? "" : property.name, text: $draft)
            .textFieldStyle(.roundedBorder)
            .font(.caption)
            .focused($focused)
            // The knob's name, whatever is in the box. While the copies differ
            // the placeholder is gone (the word is there instead), and a field
            // that stopped answering to its own name would be a field neither
            // a screen reader nor a scripted walk could find.
            .accessibilityLabel(property.name)
            .overlay(alignment: .leading) { mixedWord }
            .onSubmit(commit)
            // Naming a copy's wording is a moment, not a mode: Return lands it
            // and hands the keyboard back, so the next tool letter picks a tool
            // instead of landing in the label.
            .nameFieldKeys(commit: commit, revert: { draft = live })
            .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            .onAppear { draft = live }
            .onChange(of: live) { _, value in if !focused { draft = value } }
            .onChange(of: instances) { _, _ in draft = live }
    }

    /// Mixed in the value's own place, one step quieter, and out of the way the
    /// moment there is anything typed to read.
    @ViewBuilder private var mixedWord: some View {
        if isMixed, draft.isEmpty {
            Text(MixedValue.text)
                .font(.caption)
                .foregroundStyle(MixedLook.style)
                .padding(.leading, 5)
                .allowsHitTesting(false)
        }
    }

    private func commit() {
        guard draft != live else { return }
        editorState.setInstanceOverride(instances: instances, property: property.id,
                                        value: .text(draft))
    }
}

// MARK: - Which picture a shelf tile is asking for

/// A shelf picture is cached per component AND per size: the same component
/// can be wanted small in a narrow dock and sharp in a wide one, and a tile
/// that has been blown up needs far more pixels than one drawn whole.
struct ShelfPictureKey: Hashable {
    let id: UUID
    let dimension: Int
}
