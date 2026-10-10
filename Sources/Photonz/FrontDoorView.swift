import AppKit
import PhotonzCore
import SwiftUI

extension EnvironmentValues {
    /// Whether the window being drawn opened as the front door: New Window,
    /// with `next-front-door` on. Read before the window's state has been
    /// seeded, so its very first frame is already the front door.
    @Entry var opensAsFrontDoor = false
}

/// The front door New Window opens (Next, `next-front-door`): the mock's
/// `#homeWin` in `ui-entry-wt.html`, steps 2 to 4.
///
/// A window that holds no document, so no canvas, no tool bar and no panel:
/// Open and the primary button in its title bar, the prompt bar, four starting
/// templates under Start a project, and the newest captures under Recent.
/// Picking a template only names what the primary button will make; pressing
/// it puts the window's mode on the template's (a template is a mode preset,
/// never a document type) and opens the editor in a window of its own, and the
/// front door closes on its own once that window is up.
struct FrontDoorView: View {
    @Environment(EditorState.self) private var editorState
    @Environment(AppCoordinator.self) private var coordinator
    @State private var picked: FrontDoorTemplate?

    /// The window's width, the mock's `min(640px, 92%)`.
    static let width: CGFloat = 640

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleBar
            VStack(alignment: .leading, spacing: 20) {
                promptBar
                templates
                recent
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
        .background(FrontDoorWindowSizer())
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea(.container, edges: .top)
    }

    // MARK: Title bar

    /// The mock's title bar: the app's name and "· New" beside the traffic
    /// lights, Open and the primary button at the trailing end, "right where
    /// document actions always sit".
    private var titleBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Text(AppInfo.name).fontWeight(.semibold)
                Text("\u{00B7} \(FrontDoor.subtitle)").foregroundStyle(.secondary)
            }
            .font(.system(size: 13))
            // Clear of the traffic lights.
            .padding(.leading, 78)
            Spacer(minLength: 12)
            Button {
                if coordinator.presentOpenPanel() { editorState.closeFrontDoorOnceTheEditorOpens() }
            } label: {
                Label(FrontDoor.openTitle, systemImage: "folder")
            }
            .help("Open a picture, a recording or a Photonz file (\u{2318}O)")
            .playtestControl(FrontDoor.openTitle, detail: "Front door")
            Button { create(picked) } label: {
                Label(FrontDoor.primaryTitle(picked: picked), systemImage: "plus")
            }
            .buttonStyle(FrontDoorProminentButtonStyle())
            .keyboardShortcut(.defaultAction)
            .disabled(!isAvailable(picked))
            .playtestControl(FrontDoor.primaryTitle(picked: picked), detail: "Front door")
        }
        .controlSize(.small)
        .padding(.trailing, 14)
        // Level with the traffic lights, which sit in the middle of the first
        // 32 points of a window with a hidden title bar.
        .frame(height: 32)
        .padding(.bottom, 8)
    }

    // MARK: Prompt bar

    /// The mock's prompt bar for the agent. Drawn, and dimmed: the agent that
    /// answers it is staged later (`agent-drivable`), and a field that took
    /// typing and then did nothing would be worse than one that says it is
    /// not ready.
    private var promptBar: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 9)
                .fill(LinearGradient(colors: [Color(red: 0.43, green: 0.55, blue: 1),
                                              Color(red: 0.77, green: 0.42, blue: 1)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 30, height: 30)
                .overlay {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
            Text(FrontDoor.promptPlaceholder)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(FrontDoor.createTitle) {}
                .buttonStyle(FrontDoorProminentButtonStyle(large: true))
                .disabled(true)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor)))
        .help(FrontDoor.promptTip)
        .accessibilityElement(children: .combine)
    }

    // MARK: Templates

    private var templates: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(FrontDoor.startHeader)
                .help(FrontDoor.startHeaderTip)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                      spacing: 12) {
                ForEach(FrontDoorTemplate.allCases, id: \.self) { template in
                    if isAvailable(template) { tile(template) }
                }
            }
        }
    }

    private func tile(_ template: FrontDoorTemplate) -> some View {
        let isPicked = picked == template
        return Button {
            picked = template
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                RoundedRectangle(cornerRadius: 9)
                    .fill(Self.tint(template).opacity(0.16))
                    .frame(width: 32, height: 32)
                    .overlay {
                        Image(systemName: template.symbol)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Self.tint(template))
                    }
                Text(template.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.primary)
                if let detail = template.detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isPicked ? Color.accentColor : Color(nsColor: .separatorColor),
                                  lineWidth: isPicked ? 1.5 : 1)
            }
            .shadow(color: isPicked ? Color.accentColor.opacity(0.35) : .clear, radius: 8, y: 3)
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        // A double click is pick and go, the way a preset in Photoshop's New
        // Document is: the first click of it has already picked the tile.
        .simultaneousGesture(TapGesture(count: 2).onEnded { create(template) })
        .help(template.tip)
        .accessibilityAddTraits(isPicked ? .isSelected : [])
        .animation(.easeOut(duration: 0.15), value: isPicked)
        .playtestControl(template.title, detail: "Front door template")
    }

    /// The tile's colour, the mock's own: the component purple, the image
    /// coral, the video cyan and the accent for redlining. Drawn only as a
    /// glyph on a wash of itself, so it reads in light and dark alike.
    private static func tint(_ template: FrontDoorTemplate) -> Color {
        switch template {
        case .designUI: Color(red: 0.6, green: 0.36, blue: 1)
        case .editImage: Color(red: 1, green: 0.49, blue: 0.37)
        case .editVideo: Color(red: 0.07, green: 0.63, blue: 0.79)
        case .captureRedline: .accentColor
        }
    }

    // MARK: Recent

    /// The documents you opened and saved among your newest captures, newest
    /// first (`next-recent-documents`; with it off, captures only, the same
    /// entries the history strip shows). Absent when there are none: an empty
    /// state is empty.
    @ViewBuilder private var recent: some View {
        let items = FrontDoor.recent(captures: coordinator.capture.store.entries,
                                     documents: RecentDocumentsStore.shared.documents)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel(FrontDoor.recentHeader)
                HStack(alignment: .top, spacing: 12) {
                    ForEach(items) { item in
                        FrontDoorRecentCard(item: item) { open(item) }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }

    // MARK: Doing it

    /// Whether the app this release ships can make what `template` makes.
    private func isAvailable(_ template: FrontDoorTemplate?) -> Bool {
        switch template {
        case nil: Experiments.shared.blankCanvasEnabled
        case .designUI?: Experiments.shared.designUIStartEnabled
        case .editImage?, .captureRedline?: true
        case .editVideo?: Experiments.shared.blankVideoEnabled
        }
    }

    /// The primary button: put the window in the template's mode, then make
    /// what it names. Each one opens its editor in a window of its own, and
    /// the front door closes once that window is up.
    private func create(_ template: FrontDoorTemplate?) {
        guard isAvailable(template) else { return }
        picked = template
        if let template, Experiments.shared.windowModesEnabled {
            WindowModeStore.shared.swap(to: template.modeID)
        }
        switch template {
        case nil: editorState.isBlankCanvasDialogPresented = true
        case .designUI?: editorState.startUIDesign()
        case .editImage?:
            if coordinator.presentOpenPanel() { editorState.closeFrontDoorOnceTheEditorOpens() }
        case .editVideo?: editorState.isBlankVideoDialogPresented = true
        case .captureRedline?:
            // The capture wants the screen to itself and opens its editor only
            // once a box is drawn, so the front door goes first.
            let capture = coordinator.capture
            editorState.closeFrontDoorNow()
            DispatchQueue.main.async { capture.beginRectCapture() }
        }
    }

    /// A capture opens the way history opens it; a document the way Finder
    /// and File > Open Recent do.
    private func open(_ item: FrontDoorRecent) {
        switch item {
        case .capture(let entry, _):
            if entry.kind == .video {
                coordinator.openRecording(entry.url)
            } else {
                coordinator.editCapture(entry.url)
            }
        case .document(let document):
            coordinator.openFileWindow(document.url)
        }
        editorState.closeFrontDoorOnceTheEditorOpens()
    }
}

/// The front door's primary button and the prompt bar's Create: white on the
/// accent, whatever the window is doing.
///
/// Not the system's prominent style: in a window that is not key it drops its
/// fill and keeps its white label, which on the light window is white on
/// white (seen in `front-door-1-design-ui-picked-sc.png`, 2026-10-09). White
/// on the accent is the system's own pairing, so nothing here alters a
/// system colour. A dimmed one is the plain grey a dimmed control is, with
/// its label in the secondary colour, since white on a faded accent is faint.
private struct FrontDoorProminentButtonStyle: ButtonStyle {
    var large = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: large ? 13 : 12, weight: .medium))
            .foregroundStyle(isEnabled ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            .padding(.horizontal, large ? 14 : 9)
            .frame(height: large ? 30 : 22)
            .background(isEnabled
                            ? AnyShapeStyle(Color.accentColor.opacity(configuration.isPressed ? 0.8 : 1))
                            : AnyShapeStyle(.quaternary),
                        in: .rect(cornerRadius: large ? 9 : 6))
            .contentShape(.rect(cornerRadius: large ? 9 : 6))
    }
}

/// One card under Recent: its picture, its name and how long ago it was
/// taken or last used, the history strip's filmcard. A click opens it.
private struct FrontDoorRecentCard: View {
    let item: FrontDoorRecent
    let open: () -> Void
    @Environment(AppCoordinator.self) private var coordinator
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            picture
                .frame(width: 136, height: 84)
                .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 8))
                .clipShape(.rect(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                // Under the pointer the time gives way to the history strip's
                // own actions, in the same slot, so the row never reflows.
                ZStack(alignment: .leading) {
                    Text(RelativeTime.string(from: item.date, to: .now))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .opacity(hovered ? 0 : 1)
                    if hovered { actions.transition(.opacity) }
                }
                .frame(height: 24, alignment: .leading)
                .animation(.easeOut(duration: 0.12), value: hovered)
            }
        }
        .frame(width: 136, alignment: .leading)
        .contentShape(Rectangle())
        .playtestHover("front door recent card") { hovered = $0 }
        .help(tip)
        .contextMenu { menu }
        .playtestControl(item.url.lastPathComponent, detail: "Front door recent")
    }

    @ViewBuilder private var picture: some View {
        switch item {
        case .capture(let entry, _):
            CaptureThumbnailView(entry: entry, store: coordinator.capture.store,
                                 ringed: hovered, onActivate: open)
        case .document(let document):
            // A button, so the first click on a window that is not in front
            // opens it too, the way the template tiles take theirs.
            Button(action: open) {
                RecentDocumentThumbnail(url: document.url, ringed: hovered)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var tip: String {
        switch item {
        case .capture(let entry, _): entry.kind == .video ? "Open this recording" : "Open this capture"
        case .document: "Open \(item.url.lastPathComponent)"
        }
    }
}

extension FrontDoorRecentCard {
    /// The history strip's actions for one capture: Copy, Edit, Show in
    /// Finder and Delete (`HistoryOverlay`). A recording copies as its file.
    /// A document you opened is yours wherever it lives, so its row never
    /// deletes it: it opens, shows in Finder, or comes off the list.
    fileprivate var actions: some View {
        let store = coordinator.capture.store
        return HStack(spacing: 2) {
            switch item {
            case .capture(let entry, _):
                if entry.kind == .image {
                    iconButton("Copy", "doc.on.doc") { store.copyToPasteboard(entry) }
                }
                iconButton("Edit", "square.and.pencil") { open() }
                iconButton("Show in Finder", "folder") { coordinator.revealInFinder(entry.url) }
                iconButton("Delete", "trash", role: .destructive) { store.remove(entry) }
            case .document(let document):
                iconButton("Edit", "square.and.pencil") { open() }
                iconButton("Show in Finder", "folder") { coordinator.revealInFinder(document.url) }
                iconButton(FrontDoor.removeFromRecentTitle, "xmark") {
                    RecentDocumentsStore.shared.remove(document.url)
                }
            }
        }
        .buttonStyle(IconActionButtonStyle(diameter: 24))
    }

    /// The same verbs on a right click, where a Mac hand looks for them.
    @ViewBuilder fileprivate var menu: some View {
        Button("Open") { open() }
        Button("Show in Finder") { coordinator.revealInFinder(item.url) }
        switch item {
        case .capture(let entry, _):
            if entry.kind == .image {
                Button("Copy") { coordinator.capture.store.copyToPasteboard(entry) }
            }
            Divider()
            Button("Delete", role: .destructive) { coordinator.capture.store.remove(entry) }
        case .document(let document):
            Divider()
            Button(FrontDoor.removeFromRecentTitle) { RecentDocumentsStore.shared.remove(document.url) }
        }
    }

    private func iconButton(_ title: String, _ systemImage: String, role: ButtonRole? = nil,
                            action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) { Image(systemName: systemImage) }
            .toolTip(title, below: true)
            .accessibilityLabel(title)
            .playtestControl("\(title) \(item.url.lastPathComponent)", detail: "Front door recent")
    }
}

/// A document's picture under Recent: the small preview a saved package
/// keeps, or what Quick Look draws for a picture or a recording. A plain card
/// with the file's kind on it while it loads, and for a package saved before
/// it kept one.
private struct RecentDocumentThumbnail: View {
    let url: URL
    var ringed = false
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .clipShape(.rect(cornerRadius: 4))
                    .overlay {
                        if ringed {
                            RoundedRectangle(cornerRadius: 4).strokeBorder(Color.accentColor, lineWidth: 2)
                        }
                    }
                    .padding(4)
            } else {
                Image(systemName: url.pathExtension.lowercased() == "photonz" ? "doc.richtext" : "doc")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: url) { image = await RecentDocumentPreview.image(for: url) }
    }
}

/// Fits the window round the front door: the mock's width, and as tall as
/// what it holds, centred on the screen the first time.
private struct FrontDoorWindowSizer: NSViewRepresentable {
    func makeNSView(context: Context) -> SizerView { SizerView() }
    func updateNSView(_ view: SizerView, context: Context) {
        DispatchQueue.main.async { view.fit() }
    }

    final class SizerView: NSView {
        private var centred = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            fit()
        }

        override func layout() {
            super.layout()
            DispatchQueue.main.async { [weak self] in self?.fit() }
        }

        /// The window's content to the size of the front door, which this
        /// view is the background of.
        func fit() {
            guard let window, bounds.height > 0 else { return }
            let wanted = CGSize(width: max(FrontDoorView.width, window.contentMinSize.width),
                                height: max(bounds.height.rounded(), window.contentMinSize.height))
            let content = window.contentRect(forFrameRect: window.frame).size
            if abs(content.width - wanted.width) > 0.5 || abs(content.height - wanted.height) > 0.5 {
                let top = window.frame.maxY
                window.setContentSize(wanted)
                // Grow and shrink from the top, the way a window does.
                if centred {
                    var frame = window.frame
                    frame.origin.y = top - frame.height
                    window.setFrame(frame, display: true)
                }
            }
            if !centred {
                centred = true
                window.center()
            }
        }
    }
}
