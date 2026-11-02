import Foundation
import Testing
@testable import PhotonzCore

/// A button you can press never looks disabled
/// (`a-button-you-can-press-never-looks-disabled-the`, the user, 2026-10-24:
/// "the remove x button on effects seems disabled but it is not. buttons which
/// are active should not look diminished. look at the eye visibility icon
/// button next to it").
@Suite("An icon button's tone")
struct IconButtonToneTests {

    static let enabledTones: [IconButtonTone] = [.rest, .hovered, .pressed, .off]

    @Test("Disabled is the only state drawn faint")
    func onlyDisabledIsFaint() {
        for tone in Self.enabledTones {
            #expect(tone.ink >= IconButtonTone.disabled.ink + IconButtonTone.enabledMargin,
                    "\(tone) is drawn within \(IconButtonTone.enabledMargin) of the disabled tone")
        }
        #expect(IconButtonTone.enabledMargin >= 0.25)
    }

    @Test("At rest a button wears the system's label ink, the eye's own tone")
    func restIsTheLabelInk() {
        #expect(IconButtonTone.rest.ink == IconButtonTone.labelInk)
        #expect(IconButtonTone.labelInk == 0.85)
        // The system's tertiary label, which is what the faint x wore.
        #expect(IconButtonTone.disabled.ink == 0.25)
    }

    @Test("Under the pointer a button comes up a little, and a press holds it there with a stronger wash")
    func hoverBrightens() {
        #expect(IconButtonTone.hovered.ink > IconButtonTone.rest.ink)
        #expect(IconButtonTone.hovered.wash > IconButtonTone.rest.wash)
        #expect(IconButtonTone.pressed.ink >= IconButtonTone.hovered.ink)
        #expect(IconButtonTone.pressed.wash > IconButtonTone.hovered.wash)
        #expect(IconButtonTone.rest.wash == 0)
        #expect(IconButtonTone.off.wash == 0)
        #expect(IconButtonTone.disabled.wash == 0)
    }

    @Test("A switch that is off is quieter than one that is on, and still louder than disabled")
    func offSitsBetween() {
        #expect(IconButtonTone.off.ink < IconButtonTone.rest.ink)
        #expect(IconButtonTone.off.ink > IconButtonTone.disabled.ink)
    }

    @Test("The tone follows the button's state")
    func fromState() {
        #expect(IconButtonTone(enabled: true, look: .rest) == .rest)
        #expect(IconButtonTone(enabled: true, look: .hovered) == .hovered)
        #expect(IconButtonTone(enabled: true, look: .pressed) == .pressed)
        #expect(IconButtonTone(enabled: true, isOn: false, look: .rest) == .off)
        // An off switch under the pointer lights like any other button.
        #expect(IconButtonTone(enabled: true, isOn: false, look: .hovered) == .hovered)
        for look in [ButtonPointerLook.rest, .hovered, .pressed] {
            for isOn in [true, false] {
                #expect(IconButtonTone(enabled: false, isOn: isOn, look: look) == .disabled)
            }
        }
    }
}

/// The check that stops a faint icon button coming back: any icon-only
/// control in the app that sets a faint ink of its own (`.tertiary`,
/// `.quaternary`, a low opacity) is named, unless it says why on the line
/// before or on the control itself.
@Suite("No icon button sets a faint ink of its own")
struct FaintIconScanTests {

    @Test("The faint cross on an effect row is caught")
    func catchesTheEffectCross() {
        let source = """
        private var removeButton: some View {
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .panelHelp("Remove this \\(kindWord)")
        }
        """
        let found = FaintIconScan.findings(inSwift: source)
        #expect(found.map(\.line) == [8])
    }

    @Test("A faint ink inside the label, or a switch that goes faint when off, is caught")
    func catchesInsideTheLabel() {
        let source = """
        Button {
            toggle()
        } label: {
            Image(systemName: isOn ? "eye" : "eye.slash")
                .font(.system(size: 11))
                .foregroundStyle(isOn ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
        }
        .buttonStyle(.plain)
        """
        #expect(FaintIconScan.findings(inSwift: source).map(\.line) == [6])
    }

    @Test("A grip drawn faint and dragged by a gesture is caught")
    func catchesAGrip() {
        let source = """
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 10))
            .foregroundStyle(.quaternary)
            .gesture(DragGesture().onChanged { _ in })
        """
        #expect(FaintIconScan.findings(inSwift: source).map(\.line) == [3])
    }

    @Test("A low opacity on an icon button is caught, a hover reveal is not")
    func opacity() {
        let low = """
        Button { go() } label: { Image(systemName: "plus") }
            .opacity(0.4)
        """
        #expect(FaintIconScan.findings(inSwift: low).map(\.line) == [2])
        let reveal = """
        Button { go() } label: { Image(systemName: "xmark") }
            .opacity(isHovering ? 1 : 0.001)
        """
        #expect(FaintIconScan.findings(inSwift: reveal).isEmpty)
    }

    @Test("Buttons with words, quiet text beside a button and faint strokes are not icon inks")
    func ignoresWhatIsNotAnIconInk() {
        let source = """
        Button("Remove") { remove() }
            .foregroundStyle(.tertiary)
        Button { go() } label: {
            HStack { Image(systemName: "plus"); Text("Add").foregroundStyle(.tertiary) }
        }
        Text("3").foregroundStyle(.tertiary)
        Button(action: toggle) {
            ZStack {
                bracket.stroke(.tertiary, lineWidth: 1)
                Image(systemName: "link")
            }
        }
        .popover(isPresented: $open) { Text(help).foregroundStyle(.tertiary) }
        Button { pick() } label: {
            Swatch().overlay(Circle().strokeBorder(.primary.opacity(0.25), lineWidth: 1))
            Image(systemName: "swatchpalette")
        }
        """
        #expect(FaintIconScan.findings(inSwift: source).isEmpty)
    }

    @Test("A control that says why it is quiet is let through, an empty reason is not")
    func quietOnPurpose() {
        let reasoned = """
        Button { query = "" } label: {
            // quiet on purpose: the Mac's own search field draws its clear button this way
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.tertiary)
        }
        """
        #expect(FaintIconScan.findings(inSwift: reasoned).isEmpty)
        let bare = """
        Button { query = "" } label: {
            // quiet on purpose:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.tertiary)
        }
        """
        #expect(FaintIconScan.findings(inSwift: bare).map(\.line) == [4])
    }

    @Test("Braces and brackets in comments and strings do not throw the reading off")
    func commentsAndStrings() {
        let source = """
        Button { go("}") } label: {
            // a stray ) and { in a comment
            Image(systemName: "xmark")
        }
        .foregroundStyle(.tertiary)
        """
        #expect(FaintIconScan.findings(inSwift: source).map(\.line) == [5])
    }

    // MARK: The app itself

    static var appSources: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Photonz")
    }

    static var appFiles: [String] {
        let root = appSources
        let walker = FileManager.default.enumerator(atPath: root.path)
        var files: [String] = []
        while let next = walker?.nextObject() as? String {
            if next.hasSuffix(".swift") { files.append(next) }
        }
        return files.sorted()
    }

    @Test("The app's sources are found")
    func sourcesFound() {
        let files = Self.appFiles
        #expect(files.contains("EffectsListRow.swift"))
        #expect(files.contains("LayersRow.swift"))
        #expect(files.contains { $0.hasPrefix("Agent/") })
        #expect(files.count > 200)
    }

    @Test("No icon button in the app is drawn faint while it can be pressed")
    func theAppHasNone() throws {
        var offenders: [String] = []
        for file in Self.appFiles {
            let text = try String(contentsOf: Self.appSources.appendingPathComponent(file), encoding: .utf8)
            for finding in FaintIconScan.findings(inSwift: text) {
                offenders.append("\(file):\(finding.line): \(finding.text)")
            }
        }
        #expect(offenders.isEmpty, """
        These icon buttons set a faint ink of their own, which makes a button you can \
        press look disabled. Give them `.buttonStyle(.panelIcon())` (or `.panelIconTone()` \
        for a control that is not a Button), or say why they are quiet with a \
        `\(FaintIconScan.quietMarker) <reason>` comment on the control:
        \(offenders.joined(separator: "\n"))
        """)
    }
}
