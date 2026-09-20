import PhotonzCore
import SwiftUI

/// **Motion**: a layer told to change one of its properties over time
/// (`next-motion`, `LayerMotion.swift`).
///
/// It sits directly under Effects and is read the same way, because it IS the
/// same shape: a header with a plus, a list that starts empty, a row with a
/// switch and a name and a summary, settings that unfold under it. Learning to
/// add a border teaches you how to add a rotation.
///
/// The one difference is what a row MEANS. An Effects row is something the
/// layer paints. A Motion row is something about the layer that CHANGES: where
/// it sits, how big it is, how far it is turned, how see-through it is, what it
/// is painted, how thick its line is.
///
/// There is no menu of canned motions, and there was never going to be. The
/// user rejected "Pulse, Wiggle, Bounce, Spin" on 2026-09-15 as "super weird
/// and proprietary", and they were right: a bell does not pulse, it SWINGS. A
/// preset is a combination of these, and combinations are what you make.
struct MotionListInspector: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if editorState.motionNeedsOneLayer {
                oneLayerOnly
            } else if editorState.motionRows.isEmpty {
                empty
            } else {
                ForEach(editorState.motionRows) { motion in
                    MotionRowView(motion: motion)
                }
            }
        }
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.vertical, 8)
    }

    /// One line, saying where the gesture is. The same line the Effects list
    /// shows for the same reason: an empty section with nothing in it at all
    /// reads as broken, and the plus on the header is small enough to be missed
    /// the first time.
    private var empty: some View {
        Text(Self.nothingYet)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .playtestField("Motion Empty")
            // Said out loud, or a walk cannot tell this line from a Motion
            // section that failed to draw anything at all: `expect field` reads
            // typing boxes and readouts, and a line of prose is neither until
            // it says so (`PanelReadoutProbe`).
            .panelReadout(Self.nothingYet)
            .panelStartProbe(.row, owner: "Motion empty")
    }

    private static let nothingYet = "Nothing moves yet. Add one with the plus above."

    /// The line for a selection of two or more. The section above this one
    /// speaks for everything picked, so a Motion section that simply left the
    /// panel read as the second click having broken something. It stays and
    /// says what to do instead.
    private var oneLayerOnly: some View {
        Text(Self.oneAtATime)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .playtestField("Motion One Layer")
            .panelReadout(Self.oneAtATime)
            .panelStartProbe(.row, owner: "Motion one layer")
    }

    private static let oneAtATime = "Motion is set on one layer at a time, because the numbers it "
        + "animates are that layer's own. Pick a single layer to add one."
}

/// One entry: a switch, the property's name, its curve drawn small, the
/// summary, and the cross that takes it out. The settings unfold under it
/// behind the same rule the Effects list hangs its settings from.
///
/// There is NO grip. The mock gave the row the Effects row's drag handle, but
/// an Effects row is ordered because the order is what paints over what, and
/// two motions are on two different properties: nothing about the picture
/// changes if you swap them. A grip that changes nothing is a grip that lies.
private struct MotionRowView: View {
    @Environment(EditorState.self) private var editorState
    let motion: LayerMotion

    @State private var isFolded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: ColorPartLayout.spacing) {
                foldControl
                Spacer(minLength: 0)
                // The curve, DRAWN. Nobody can tell ease out back from ease out
                // quint by reading, which is why the shape is on the row and
                // not just in the menu.
                CurveThumbnail(curve: motion.curve)
                    .frame(height: ColorPartLayout.rowHeight)
                    .panelHelp("This motion runs on the \(motion.curve.title.lowercased()) curve")
                motionSwitch
                removeButton
            }
            // The row, read back as a sentence about the drawing. Under the
            // name rather than fighting the right hand edge for room, which is
            // what made it wrap raggedly in the mock.
            Text(motion.summary)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(motion.isOn ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, ColorPartLayout.nameLeading)
                .playtestField("\(motion.property.title) Summary")
                // The sentence, said out loud to a walk. It is a SwiftUI Text,
                // which publishes nothing a walk can read, so without this the
                // one line that says what the motion DOES was invisible to
                // every walk that tried to claim it.
                .panelReadout(motion.summary)
            if !isFolded {
                OwnedSettings(owner: motion.property.title) { settings }
                    .compositingGroup()
                    .opacity(motion.isOn ? 1 : PanelSectionLook.EffectRow.offSettingsOpacity)
            }
        }
        .playtestField(motion.property.title)
        .panelStartProbe(.row, owner: motion.property.title)
        .contextMenu {
            Button("Remove") { editorState.removeMotion(id: motion.id) }
        }
    }

    // MARK: The heading

    private var foldControl: some View {
        Button {
            withAnimation(.spring(duration: 0.2)) { isFolded.toggle() }
        } label: {
            HStack(alignment: .top, spacing: ColorPartLayout.spacing) {
                PanelFoldChevron(isFolded: isFolded)
                Text(motion.property.title)
                    .font(PanelSectionLook.EffectRow.titleFont)
                    .foregroundStyle(motion.isOn ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(width: ColorPartLayout.labelWidth,
                           height: ColorPartLayout.rowHeight, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .panelHelp(isFolded ? "Show what this motion does" : "Hide what this motion does")
        .accessibilityLabel(motion.property.title)
        .playtestControl("Twist", detail: isFolded ? "shut" : "open")
    }

    /// The switch, drawn as the eye every other list in this panel wears: the
    /// app has one picture for "this one is not doing anything", and a motion
    /// is not the place to invent a second.
    private var motionSwitch: some View {
        Button {
            editorState.setMotionEnabled(id: motion.id, on: !motion.isOn)
        } label: {
            Image(systemName: motion.isOn ? "eye" : "eye.slash")
                .font(.system(size: 11))
                .foregroundStyle(motion.isOn ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                .frame(height: ColorPartLayout.rowHeight)
                .panelEdgeIcon("eye", of: motion.property.title)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .panelHelp("Stops it moving, and keeps every number on it")
        .accessibilityLabel(motion.isOn ? "Stop \(motion.property.title) moving"
                                        : "Let \(motion.property.title) move")
        .playtestControl("Switch", detail: motion.isOn ? "moving" : "still")
    }

    private var removeButton: some View {
        Button {
            editorState.removeMotion(id: motion.id)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .semibold))
                .frame(height: ColorPartLayout.rowHeight)
                .panelEdgeIcon("remove", of: motion.property.title)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tertiary)
        .panelHelp("Stop this property moving at all")
        .playtestControl("Remove", detail: "takes the motion out of the list")
    }

    // MARK: The settings

    /// Five questions, and the first one is what it goes from and to. Start and
    /// Over are the same two numbers the timing strip carries, so they are one
    /// type in the model and moving either will move both.
    @ViewBuilder private var settings: some View {
        if case .color = motion.from {
            MotionColorSetting(motion: motion, isFrom: true)
            MotionColorSetting(motion: motion, isFrom: false)
        } else {
            MotionValueSetting(motion: motion, isFrom: true)
            MotionValueSetting(motion: motion, isFrom: false)
        }
        if motion.property == .rotation {
            MotionPivotSetting(motion: motion, isNumbers: false)
            MotionPivotSetting(motion: motion, isNumbers: true)
        }
        MotionMillisecondSetting(motion: motion, isStart: true)
        MotionMillisecondSetting(motion: motion, isStart: false)
        MotionCurveSetting(motion: motion)
        MotionRepeatSetting(motion: motion)
    }
}

// MARK: - The curve, drawn

/// A curve's SHAPE, small. The name is not the thing: nobody can tell ease out
/// back from ease out quint by reading one, so every place a curve is offered
/// or shown draws it.
struct CurveThumbnail: View {
    let curve: EasingCurve
    var side: CGFloat = 18

    var body: some View {
        Canvas { context, size in
            var path = Path()
            // Padded in, because back and elastic go past the top and a curve
            // clipped at the edge of its own box reads as a straight line.
            let inset: CGFloat = 3
            let width = size.width - inset * 2
            let height = size.height - inset * 2
            let steps = 40
            for step in 0...steps {
                let t = Double(step) / Double(steps)
                let value = min(max(curve.value(at: t), -0.25), 1.25)
                let point = CGPoint(x: inset + width * t,
                                    y: inset + height * (1 - (value + 0.25) / 1.5))
                if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            context.stroke(path, with: .color(.accentColor), lineWidth: 1.5)
        }
        .frame(width: side, height: side)
        .background(RoundedRectangle(cornerRadius: 4).fill(.quaternary.opacity(0.4)))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.quaternary, lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}

// MARK: - One setting

/// The shell every setting on a motion row wears: a caption on the left, the
/// control on the right, at the width the rest of the dock uses.
private struct MotionSettingRow<Content: View>: View {
    let label: String
    let help: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            Spacer(minLength: 4)
            content
        }
        .panelHelp(help)
    }
}

/// From and To, for everything that is a number or a place.
private struct MotionValueSetting: View {
    @Environment(EditorState.self) private var editorState
    let motion: LayerMotion
    let isFrom: Bool

    private var value: MotionValue { isFrom ? motion.from : motion.to }
    private var label: String { isFrom ? "From" : "To" }

    var body: some View {
        MotionSettingRow(label: label,
                         help: isFrom ? "What this property is at the start of the motion"
                                      : "What it has become by the end") {
            switch value {
            case let .number(number):
                MotionNumberField(value: number,
                                  label: "\(motion.property.title) \(label)",
                                  suffix: MotionEntry.suffix(motion.property)) { typed in
                    editorState.updateMotion(id: motion.id) { edited in
                        if isFrom { edited.from = .number(typed) } else { edited.to = .number(typed) }
                    }
                }
            case let .point(point):
                HStack(spacing: 4) {
                    MotionNumberField(value: Double(point.x),
                                      label: "\(motion.property.title) \(label) X", suffix: nil) { typed in
                        editorState.updateMotion(id: motion.id) { edited in
                            let moved = CGPoint(x: typed, y: point.y)
                            if isFrom { edited.from = .point(moved) } else { edited.to = .point(moved) }
                        }
                    }
                    MotionNumberField(value: Double(point.y),
                                      label: "\(motion.property.title) \(label) Y", suffix: nil) { typed in
                        editorState.updateMotion(id: motion.id) { edited in
                            let moved = CGPoint(x: point.x, y: typed)
                            if isFrom { edited.from = .point(moved) } else { edited.to = .point(moved) }
                        }
                    }
                }
            case .color:
                EmptyView()
            }
        }
    }
}

/// From and To for a colour, which is a well rather than a number.
///
/// The same well every other colour in the app is chosen from
/// (`ColorPickerEntry`), so the colours you have saved are on offer here too.
/// It used to raise the Mac's own colour window, which was the one place in the
/// panel where your own styles were not offered — and the one place you most
/// need them, since a motion's two colours have to match the rest of the icon.
private struct MotionColorSetting: View {
    @Environment(EditorState.self) private var editorState
    let motion: LayerMotion
    let isFrom: Bool

    private var hex: String {
        if case let .color(hex) = (isFrom ? motion.from : motion.to) { return hex }
        return "#000000"
    }
    private var label: String { isFrom ? "From" : "To" }

    var body: some View {
        MotionSettingRow(label: label,
                         help: isFrom ? "The colour this layer starts out"
                                      : "The colour it has become by the end") {
            // Two wells sit in one row, so each needs a key of its own or
            // pressing To would open the popover hanging off From.
            HStack(alignment: .center, spacing: ColorPartLayout.styleGap) {
                ColorWellButton(hex: hex,
                                name: label,
                                wellKey: "motion-\(motion.id.uuidString)-\(isFrom ? "from" : "to")",
                                // The loop keeps playing while the picker is
                                // open, so the swing is painted as you slide
                                // and the whole pick is still one step to undo.
                                onPreview: { picked in
                    editorState.previewMotionValue(id: motion.id, isFrom: isFrom, .color(picked))
                }, onCommit: pick)
                .frame(minWidth: ColorPartLayout.readoutWidth, alignment: .leading)
                MotionColorStylesMenu(current: hex, onPick: pick)
            }
            // The colour itself, said out loud, so a walk can read back what
            // landed: a swatch draws a colour and publishes no words at all.
            .panelReadout(hex)
            // The row named, so the two wells and the two menus in this one
            // section can be told apart: `press "Color" in "From"`.
            .playtestField(label)
        }
    }

    private func pick(_ picked: String) {
        editorState.commitMotionValue(id: motion.id, isFrom: isFrom, .color(picked))
        editorState.recordRecentColor(hex: picked)
    }
}

/// The saved colours, offered beside a motion's From and To.
///
/// The same glyph and the same place every other colour row keeps its styles
/// menu, so the one column of swatchpalette marks down the panel does not skip
/// these two rows. What it does is deliberately the SHORTER half of what that
/// menu does elsewhere: it paints the colour and hands over no name.
///
/// A motion endpoint cannot wear a style today — the model has nowhere to write
/// "this From follows Brand", and what a running animation should do the moment
/// Brand is repainted is a question worth asking before answering. So this is
/// the copy-a-colour half, which the app already has words for, rather than a
/// link that half works.
private struct MotionColorStylesMenu: View {
    @Environment(EditorState.self) private var editorState
    let current: String
    let onPick: (String) -> Void

    var body: some View {
        let styles = editorState.colorStyles
        // Nothing saved yet is no menu rather than an empty one: a mark that
        // opens onto nothing is a control that appears not to work.
        if !styles.isEmpty {
            Menu {
                Section("Copy a saved color") {
                    ForEach(styles) { style in
                        Button {
                            onPick(style.colorHex)
                        } label: {
                            Label {
                                Text(style.name)
                            } icon: {
                                Image(systemName: style.colorHex.caseInsensitiveCompare(current) == .orderedSame
                                      ? "checkmark.circle.fill" : "circle.fill")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "swatchpalette")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            // A menu drawn as a glyph has no words of its own, so a walk reads
            // it by this (`PlaytestPanelMenu.title`).
            .accessibilityLabel("Saved colors")
            .panelHelp("Paints this with a color you have saved. The color comes over, the name does not.")
        }
    }
}

/// What a turn turns AROUND, in words and in numbers.
///
/// The same point the crosshair on the canvas is sitting on, said three ways:
/// the menu for the spots worth a name, the two fields for the times a number
/// is what you want, and the handle on the picture for every other time, which
/// is nearly always. The drag is the one that matters — the right pivot is a
/// point on YOUR drawing and nobody but you knows where it is — and these are
/// here so that "the top of it, exactly" does not need a steady hand.
private struct MotionPivotSetting: View {
    @Environment(EditorState.self) private var editorState
    let motion: LayerMotion
    /// The two fields, rather than the menu.
    let isNumbers: Bool

    private var box: CGRect { editorState.motionPivotHandle?.box ?? .zero }
    private var point: CGPoint { editorState.motionPivotPoint ?? .zero }

    /// What the menu reads: the spot's name where the pivot is on one, and
    /// "Custom" where it is somewhere of its own.
    ///
    /// It used to print the two numbers instead, on the grounds that "Custom"
    /// says nothing about where the pivot went. What it actually said was the
    /// SAME two numbers the At row prints an inch below it, so one value was
    /// stated twice and neither reading told you anything the other did not.
    /// Only one door is the readout ("One setting, two doors" in
    /// UX-PATTERNS.md), and here that door is At: a menu of three spots cannot
    /// set 142, so where it has no name to offer it says so in its own terms
    /// and leaves the position to the row that exists to state it.
    private var reading: String { (editorState.motionPivot ?? motion.turnsAbout).title }

    var body: some View {
        if isNumbers {
            MotionSettingRow(label: "At",
                             help: "The same point as two numbers on the canvas, for when a "
                                 + "number is what you want rather than a drag") {
                HStack(spacing: 4) {
                    MotionNumberField(value: Double(point.x),
                                      label: "Around X", suffix: nil) { typed in
                        editorState.setMotionPivot(
                            MotionPivot(at: CGPoint(x: typed, y: point.y), in: box), of: motion.id)
                    }
                    MotionNumberField(value: Double(point.y),
                                      label: "Around Y", suffix: nil) { typed in
                        editorState.setMotionPivot(
                            MotionPivot(at: CGPoint(x: point.x, y: typed), in: box), of: motion.id)
                    }
                }
            }
        } else {
            MotionSettingRow(label: "Around",
                             help: "The point this layer turns about. A bell hangs from its "
                                 + "mount, not from its middle: drag the crosshair on the "
                                 + "picture to where yours hangs from.") {
                Menu {
                    ForEach(MotionPivot.Named.allCases, id: \.self) { spot in
                        Button(spot.title) {
                            editorState.setMotionPivot(spot.pivot, of: motion.id)
                        }
                    }
                } label: {
                    Text(reading).lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                .controlSize(.small)
                .fixedSize()
                .accessibilityLabel("Around")
                .playtestControl("Around", detail: reading)
            }
        }
    }
}

/// Start and Over: when it begins, measured from the top of the loop, and how
/// long it takes. Both in milliseconds, which is the ruler the whole cycle is
/// measured on.
private struct MotionMillisecondSetting: View {
    @Environment(EditorState.self) private var editorState
    let motion: LayerMotion
    let isStart: Bool

    var body: some View {
        MotionSettingRow(label: isStart ? "Start" : "Over",
                         help: isStart
                            ? "How long after the top of the loop this starts, in milliseconds. "
                              + "That gap is how one part of an icon lags behind another."
                            : "How long the change takes, in milliseconds") {
            // A lap starts at nought at the earliest and a change takes at
            // least a millisecond, so the box holds those two floors itself
            // and shows what was TAKEN. It used to show -5 over a start of 0.
            MotionNumberField(value: Double(isStart ? motion.timing.startMS : motion.timing.durationMS),
                              label: "\(motion.property.title) \(isStart ? "Start" : "Over")",
                              suffix: "ms",
                              floor: isStart ? 0 : 1,
                              wholeNumbers: true) { typed in
                editorState.updateMotion(id: motion.id) { edited in
                    if isStart { edited.timing.setStart(Int(typed.rounded())) }
                    else { edited.timing.setDuration(Int(typed.rounded())) }
                }
            }
        }
    }
}

/// The curve, picked from one named list with each shape drawn beside its name,
/// plus one you draw yourself.
private struct MotionCurveSetting: View {
    @Environment(EditorState.self) private var editorState
    let motion: LayerMotion
    @State private var isDrawing = false

    var body: some View {
        MotionSettingRow(label: "Curve",
                         help: "How the change is paced between its two values. "
                             + "The shape beside each name is the curve itself.") {
            Menu {
                ForEach(Array(EasingCurve.named.enumerated()), id: \.offset) { _, curve in
                    Button { choose(curve) } label: {
                        Label { Text(curve.title) } icon: { CurveThumbnail(curve: curve, side: 14) }
                    }
                }
                Divider()
                Button("Draw a curve...") { isDrawing = true }
            } label: {
                HStack(spacing: 5) {
                    CurveThumbnail(curve: motion.curve, side: 14)
                    Text(motion.curve.isDrawn ? "Drawn" : motion.curve.title)
                        .lineLimit(1)
                }
            }
            .menuStyle(.borderlessButton)
            .controlSize(.small)
            .fixedSize()
            .accessibilityLabel("Curve")
            .playtestControl("Curve", detail: motion.curve.title)
            .popover(isPresented: $isDrawing, arrowEdge: .bottom) {
                CurveEditor(curve: motion.curve) { drawn in choose(drawn) }
            }
        }
    }

    private func choose(_ curve: EasingCurve) {
        editorState.updateMotion(id: motion.id) { $0.curve = curve }
    }
}

/// What happens after it has played.
///
/// The mock offered Once, 3 times and Forever, and its own bell swung out and
/// back inside one cycle, which none of those three can say. A one way repeat
/// snaps the bell home every 900ms, which is a jump cut. So the menu answers
/// both here, because both are answers to the same question.
private struct MotionRepeatSetting: View {
    @Environment(EditorState.self) private var editorState
    let motion: LayerMotion

    var body: some View {
        MotionSettingRow(label: "Repeat",
                         help: "What happens once it has played. There and back goes out "
                             + "and comes home inside one loop, which is what an icon "
                             + "nearly always wants: a loop that does not come back is a jump cut.") {
            Menu {
                ForEach(Array(MotionRepeat.choices.enumerated()), id: \.offset) { _, choice in
                    Button(choice.title) {
                        editorState.updateMotion(id: motion.id) { $0.repeats = choice }
                    }
                }
            } label: {
                Text(motion.repeats.title).lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .controlSize(.small)
            .fixedSize()
            .accessibilityLabel("Repeat")
            .playtestControl("Repeat", detail: motion.repeats.title)
        }
    }
}

// MARK: - The plus, and the play button

/// The plus on the Motion header, built out of the layer in front of you: every
/// item names something that layer actually HAS and shows the value it is
/// wearing right now, because that is what you would be animating away from.
struct AddMotionButton: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        Menu {
            ForEach(editorState.motionOffers, id: \.property) { offer in
                Button {
                    editorState.addMotion(offer.property)
                } label: {
                    Text("\(offer.property.title)    \(offer.reading)")
                }
                .disabled(offer.isAlreadyMoving)
                .panelHelp(offer.isAlreadyMoving
                           ? "\(offer.property.title) is already moving on this layer"
                           : "Now \(offer.reading). Animate it away from there.")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(editorState.motionLayer == nil)
        .accessibilityLabel("Add Motion")
        .panelHelp("Animate a property of this layer: where it sits, how big it is, "
                   + "how far it is turned, how see-through it is, what colour it is")
        .playtestControl("Add Motion", detail: "the plus on the Motion header")
    }
}

/// Play and pause, on the header beside the plus. Stopped is the picture AS
/// DRAWN, which is what you edit against: a canvas quietly animating under a
/// layer you are trying to drag would be a canvas you cannot work on.
struct MotionPreviewButton: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        Button {
            editorState.toggleMotionPreview()
        } label: {
            Image(systemName: editorState.isMotionPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 10, weight: .medium))
        }
        .buttonStyle(.plain)
        .foregroundStyle(editorState.isMotionPlaying ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .disabled(!editorState.canPlayMotion)
        .accessibilityLabel(editorState.isMotionPlaying ? "Pause the preview" : "Play the preview")
        .panelHelp(editorState.isMotionPlaying
                   ? "Stop the preview and put the picture back to the one you drew"
                   : "Play what the picture has been told to do")
        .playtestControl("Preview", detail: editorState.isMotionPlaying ? "playing" : "stopped")
    }
}

// MARK: - Typing a number on a motion row

/// How the fields on a motion row write and read their numbers.
enum MotionEntry {
    /// The number, as the field shows it: no trailing zeroes, because a row of
    /// "12.00" reads as a spreadsheet rather than as a drawing.
    static func text(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(format: "%g", rounded)
    }

    /// The unit printed after the box, so the number in it means something on
    /// its own.
    static func suffix(_ property: MotionProperty) -> String? {
        switch property {
        case .rotation: "°"
        case .scale, .opacity: "%"
        // The app's ONE word for a length (`DocumentUnit`), not a second one
        // of this panel's own: a thickness on a motion row and a thickness in
        // Appearance are the same distance.
        case .strokeWidth: DocumentUnit.word
        case .position, .color: nil
        }
    }
}

/// One number on a motion row.
///
/// It is a `PanelNumberField`, the one number box every panel types into, with
/// the motion panel's own spelling on it: no trailing zeroes, because a row of
/// "12.00" reads as a spreadsheet rather than as a drawing. Everything else —
/// Return landing the number, Escape putting it back, both handing the
/// keyboard to the picture, the arrow keys, and showing what was TAKEN when a
/// floor holds the number — is decided once, over there.
///
/// Shared with the timing strip's own lap-length readout, so the two number
/// fields that mean milliseconds behave identically.
struct MotionNumberField: View {
    let value: Double
    let label: String
    let suffix: String?
    /// The smallest this number may be, for the two that have a floor.
    var floor: CGFloat?
    var wholeNumbers = false
    let land: (Double) -> Void

    var body: some View {
        PanelNumberField(showing: .number(MotionEntry.text(value)),
                         label: label,
                         suffix: suffix,
                         floor: floor,
                         wholeNumbers: wholeNumbers,
                         playtest: (label, "Motion"),
                         spell: { MotionEntry.text(Double($0)) },
                         land: { typed in
                             land(Double(typed))
                             return nil
                         })
    }
}

// MARK: - Drawing a curve

/// The curve you draw yourself: two handles you drag, and the
/// `cubic-bezier(a, b, c, d)` they add up to.
///
/// It is the last item on the curve menu rather than a mode, because the named
/// curves cover nearly everything and this is for the time they do not.
private struct CurveEditor: View {
    let curve: EasingCurve
    let done: (EasingCurve) -> Void

    @State private var first = CGPoint(x: 0.4, y: 0)
    @State private var second = CGPoint(x: 0.2, y: 1)

    private var drawn: EasingCurve {
        .custom(x1: Double(first.x), y1: Double(first.y),
                x2: Double(second.x), y2: Double(second.y))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            board
            Text(drawn.title)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            HStack {
                Spacer()
                Button("Use this curve") { done(drawn) }
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
                    .playtestControl("Use this curve", detail: drawn.title)
            }
        }
        .padding(12)
        .frame(width: 220)
        .onAppear {
            if case let .custom(x1, y1, x2, y2) = curve {
                first = CGPoint(x: x1, y: y1)
                second = CGPoint(x: x2, y: y2)
            }
        }
    }

    /// The whole board is 0...1 in x and -0.25...1.25 in y, so a handle pulled
    /// past the end has somewhere to go: overshoot is the point of drawing your
    /// own curve.
    private func place(_ point: CGPoint, side: CGFloat) -> CGPoint {
        CGPoint(x: point.x * side, y: (1 - (point.y + 0.25) / 1.5) * side)
    }

    private func read(_ point: CGPoint, side: CGFloat) -> CGPoint {
        CGPoint(x: min(max(point.x / side, 0), 1),
                y: min(max((1 - point.y / side) * 1.5 - 0.25, -0.25), 1.25))
    }

    private var board: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.3))
                Path { path in
                    path.move(to: place(CGPoint(x: 0, y: 0), side: side))
                    path.addCurve(to: place(CGPoint(x: 1, y: 1), side: side),
                                  control1: place(first, side: side),
                                  control2: place(second, side: side))
                }
                .stroke(Color.accentColor, lineWidth: 2)
                handle(at: place(CGPoint(x: 0, y: 0), side: side), to: place(first, side: side))
                handle(at: place(CGPoint(x: 1, y: 1), side: side), to: place(second, side: side))
                grip(place(first, side: side), name: "First handle") { first = read($0, side: side) }
                grip(place(second, side: side), name: "Second handle") { second = read($0, side: side) }
            }
            .frame(width: side, height: side)
        }
        .frame(height: 196)
    }

    private func handle(at anchor: CGPoint, to point: CGPoint) -> some View {
        Path { path in
            path.move(to: anchor)
            path.addLine(to: point)
        }
        .stroke(.secondary, lineWidth: 1)
    }

    private func grip(_ point: CGPoint, name: String,
                      moved: @escaping (CGPoint) -> Void) -> some View {
        Circle()
            .fill(Color.accentColor)
            .overlay(Circle().strokeBorder(.background, lineWidth: 1.5))
            .frame(width: 11, height: 11)
            .position(point)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { moved($0.location) })
            .accessibilityLabel(name)
    }
}
