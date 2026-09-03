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
}

/// The glyph as a SwiftUI shape, for the layers list and the Library tile.
struct ComponentGlyphShape: Shape {
    func path(in rect: CGRect) -> Path { Path(ComponentGlyph.path(in: rect)) }
}

/// The mark itself, at the size a list row wants it.
struct ComponentMark: View {
    var size: CGFloat = 12

    var body: some View {
        ComponentGlyphShape()
            .fill(ComponentGlyph.color)
            .frame(width: size, height: size)
            .help("A component. Copies of it come from the Library.")
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
                Text("This is the main. Copies you place will follow it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
                Text("\(main.children.count == 1 ? "1 layer" : "\(main.children.count) layers") inside")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Select on Canvas") {
                    editorState.selectComponentOnCanvas(componentID: componentID)
                }
                .controlSize(.small)
                .help("Selects the original on the canvas")
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

    private var isSelected: Bool { editorState.selectedLibraryItemID == entry.id }

    var body: some View {
        VStack(spacing: 3) {
            thumbnail
            Text(entry.name)
                .font(.system(size: 10))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        }
        .frame(maxWidth: .infinity)
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { selectOnCanvas() }
        .onTapGesture { editorState.selectLibraryItem(entry.id) }
        .help("\(entry.name), a component. Double click to select the original.")
    }

    /// The same picture the layers list draws for this layer, at the same size
    /// and out of the same cache, so a component looks like itself wherever it
    /// is listed.
    private var thumbnail: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(.quaternary)
            .frame(height: 44)
            .overlay {
                if let image = editorState.thumbnail(for: layer) {
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

    private func selectOnCanvas() {
        guard let componentID = layer.componentID else { return }
        editorState.selectComponentOnCanvas(componentID: componentID)
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
