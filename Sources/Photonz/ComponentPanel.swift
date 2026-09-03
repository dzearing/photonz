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
                    .onSubmit(commit)
                    .onChange(of: nameFocused) { _, focused in if !focused { commit() } }
            }
            HStack(spacing: 6) {
                ComponentMark(size: 11)
                Text(standing)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let componentID { ComponentPropertyList(componentID: componentID) }
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
                Text(inside(main) + copies(componentID))
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
        .onDrag {
            editorState.selectLibraryItem(entry.id)
            guard let componentID = layer.componentID else { return NSItemProvider() }
            return ComponentDrag.itemProvider(componentID: componentID)
        }
        .help(helpText)
    }

    /// The same picture the layers list draws for this layer, at the same size
    /// and out of the same cache, so a component looks like itself wherever it
    /// is listed.
    private var thumbnail: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(.quaternary)
            .frame(height: LibraryShelfLayout.thumbnailHeight)
            .overlay {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFit()
                        .padding(3)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.primary.opacity(0.12)))
            .overlay(alignment: .topLeading) {
                ComponentMark(size: 9).padding(3)
            }
    }

    private var image: CGImage? {
        if let starter { return editorState.starterThumbnail(starter) }
        return editorState.thumbnail(for: layer)
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
    let layer: Layer

    private var componentID: UUID? { editorState.document?.layer(id: layer.id)?.instanceOf }
    private var main: Layer? { componentID.flatMap { editorState.document?.mainComponent(componentID: $0) } }

    var body: some View {
        if let componentID, let main {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    ComponentMark(size: 12, isInstance: true)
                    Text(main.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                Text("A copy. Editing the original changes this one too.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ComponentInstanceProperties(instance: layer.id, componentID: componentID)
                HStack(spacing: 6) {
                    Button("Edit Original") {
                        editorState.selectComponentOnCanvas(componentID: componentID)
                    }
                    .controlSize(.small)
                    .help("Selects the original, which is where a change to every copy is made")
                    // Detach is here as well as in the Layer menu, because a
                    // command that lives only in a menu is a command nobody
                    // finds. It is not destructive styling: nothing is deleted,
                    // the copy simply stops following, and undo is the way back.
                    Button("Detach") { editorState.detachInstance() }
                        .controlSize(.small)
                        .disabled(!editorState.canDetachInstance)
                        .help("Turns this copy into ordinary layers that no longer follow the original")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
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

    private var properties: [ComponentProperty] {
        editorState.componentProperties(of: componentID)
    }

    private var candidates: [ComponentPropertyCandidate] {
        editorState.componentPropertyCandidates(componentID: componentID)
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
                    ComponentPropertyRow(componentID: componentID, property: property)
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
                            Button(candidate.pathLabel) {
                                editorState.addComponentProperty(componentID: componentID,
                                                                 target: candidate.layerID,
                                                                 kind: kind)
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
                .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            Text(property.kind.chip)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(.quaternary))
            Button {
                editorState.removeComponentProperty(componentID: componentID, propertyID: property.id)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Stop letting copies change this. Copies go back to showing what the original shows")
        }
        .onAppear { draft = property.name }
        .onChange(of: property.name) { _, name in if !focused { draft = name } }
    }

    private func commit() {
        guard let name = ComponentNaming.normalized(draft) else {
            draft = property.name   // ...a blank name is refused, so put it back
            return
        }
        guard name != property.name else { return }
        editorState.renameComponentProperty(componentID: componentID, propertyID: property.id, to: name)
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
    let instance: UUID
    let componentID: UUID

    private var properties: [ComponentProperty] {
        editorState.componentProperties(of: componentID)
    }

    private var overridden: Set<UUID> { editorState.instanceOverrides(instance: instance) }

    var body: some View {
        if properties.isEmpty {
            Text("The original has not made anything adjustable yet. Select it and add a knob there.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Divider().padding(.vertical, 2)
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

    @ViewBuilder private func control(for property: ComponentProperty) -> some View {
        switch property.kind {
        case .text:
            InstanceTextKnob(instance: instance, property: property)
        case .visible:
            Toggle("", isOn: Binding(
                get: { editorState.instanceValue(instance: instance, property: property.id)?.boolValue ?? true },
                set: { editorState.setInstanceOverride(instance: instance, property: property.id,
                                                       value: .visible($0)) }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
            Spacer(minLength: 0)
        case .variant:
            // Labels rather than raw names: two rectangles drawn in a row are
            // both called "Rectangle", and a menu of identical rows is a menu
            // nobody can choose from.
            let options = editorState.componentVariantOptionLabels(componentID: componentID,
                                                                   propertyID: property.id)
            Picker("", selection: Binding(
                get: { editorState.instanceValue(instance: instance, property: property.id)?.optionValue
                        ?? options.first?.id ?? UUID() },
                set: { editorState.setInstanceOverride(instance: instance, property: property.id,
                                                       value: .variant($0)) })) {
                ForEach(options, id: \.id) { option in
                    Text(option.label).tag(option.id)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .help("Only the shapes the original holds. A copy can never show something it does not define")
        }
    }

    /// The way back. Without it a copy that was set once can only be put right
    /// by undoing, and an override made ten edits ago is out of undo's reach.
    @ViewBuilder private func revert(_ property: ComponentProperty) -> some View {
        Button {
            editorState.clearInstanceOverride(instance: instance, property: property.id)
        } label: {
            Image(systemName: "arrow.uturn.backward")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .opacity(overridden.contains(property.id) ? 1 : 0)
        .disabled(!overridden.contains(property.id))
        .help("Follow the original again for this one")
    }
}

/// A wording knob on a copy: a field that lands its text the way every other
/// field in the dock does, on Return and on clicking away, so typing a label
/// is not one undo step per keystroke.
private struct InstanceTextKnob: View {
    @Environment(EditorState.self) private var editorState
    let instance: UUID
    let property: ComponentProperty

    @State private var draft = ""
    @FocusState private var focused: Bool

    private var live: String {
        editorState.instanceValue(instance: instance, property: property.id)?.textValue ?? ""
    }

    var body: some View {
        // The knob's own name is the placeholder, so an emptied field still
        // says what it is, and a scripted playtest can reach the field by name.
        TextField(property.name, text: $draft)
            .textFieldStyle(.roundedBorder)
            .font(.caption)
            .focused($focused)
            .onSubmit(commit)
            .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            .onAppear { draft = live }
            .onChange(of: live) { _, value in if !focused { draft = value } }
            .onChange(of: instance) { _, _ in draft = live }
    }

    private func commit() {
        guard draft != live else { return }
        editorState.setInstanceOverride(instance: instance, property: property.id, value: .text(draft))
    }
}
