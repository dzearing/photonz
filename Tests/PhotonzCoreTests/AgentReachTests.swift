import Foundation
import PhotonzCore
import Testing

/// **Nothing a person can click is out of an agent's reach without a written
/// reason** (`agent-api`, success item 1: menus, panels and right-click menus).
///
/// `EveryMenuCommandHasANameTests` counts the menu bar. This counts the other
/// two surfaces, read out of the source by `AgentReachSource`:
///
/// * **the panel**: every control each section draws, for a picture and for a
///   video, known by the words beside it (`SoundInspector.swift › Gain`);
/// * **every right-click menu**: the rows of each one, listed by the menu
///   they are in, the timeline clip's rows by `TimelineMenuRow`.
///
/// Each one is either reached, by an agent tool and the field that sets it or
/// by a command `run_command` runs; LEFT OUT on purpose, with the reason; or
/// NOT YET reached, with what is missing. The not-yet lists may only shrink:
/// their sizes are pinned, so a new control with no way in fails here until it
/// gets one or a reason.
///
/// A right-click row titled with a command's own words (`AppCommandTable`) is
/// reached by that command with nothing written here; so is a panel control
/// labelled with one.
@Suite("An agent can reach every panel control and right-click row")
struct AgentReachTests {

    /// How an agent reaches one control or row.
    enum Reach: Equatable {
        /// A tool, and the field of it that sets this: `set_layer.opacity`.
        case tool(String, String)
        /// Commands `run_command` runs, by name: `normalize_loudness`.
        case commands([String])
        case leftOut(String)
        case notYet(String)

        var isReached: Bool {
            switch self {
            case .tool, .commands: true
            case .leftOut, .notYet: false
            }
        }
    }

    // MARK: Reasons

    /// The reasons several rows share, by a short name the tables use.
    static let reasons: [String: String] = [
        "look": "opens, folds or shows something for a person; it changes nothing in the document",
        "shelf": "browses or searches the Library shelf; list_styles, list_components, list_titles and list_brushes read what it holds",
        "toolInHand": "a setting of the tool in a person's hand for their next drag; an agent makes the thing with its own tools",
        "grid": "a guide drawn for a person's eye, or the snapping of a hand's drag; nothing an agent places is moved by it",
        "panel": "how the panel is laid out for a person; it changes nothing in the document",
        "pick": "picks things in the window for a person; an agent names the layers it acts on",
        "keyStep": "moves the playhead to the next key; set_playhead moves it anywhere and read_document lists the keys",
        "slider box": "the typed box of a slider row, whose own setting is counted at each use",
        "hand": "puts back what a hand dragged on the canvas; an agent places it with set_layer",
        "inLibrary": "opens a saved style in the Library for a person",
        "pointer": "places a point by pointing at the canvas",
        "finder": "shows the file in Finder, outside the app",
        "ask": "Ask's own history and settings; an agent is already the one asking",
        "draw": "draws with a tool; add_text and add_shape draw them",
        "playhead": "moves the playhead for a person; set_playhead moves it anywhere",
        "submenu": "a submenu: its rows are counted one by one",
        "clipRow": "a timeline clip row, counted by its own case in TimelineMenuRow",
    ]

    // MARK: The panel

    /// Every panel control that is not labelled with a command's own words,
    /// and how an agent reaches it. One line each: `key | reach`, where reach
    /// is `tool.field`, `command: a, b`, `leftOut: <reason or a name above>`
    /// or `notYet: <what is missing>`.
    static let panelTable = """
        AddKeyControl.swift › Add Key Menu | set_keys.property
        AddKeyControl.swift › Animate a Property | command: animate_property
        AnnotationInspector.swift › Add a caption | set_layer.caption
        AnnotationInspector.swift › body: Button(pinned.count > 1 ? "Reset Label Positions" : "Re) | leftOut: hand
        AnnotationInspector.swift › box: FourSidedButton(isOpen: $cornersOpen) | notYet: each corner's rounding on its own
        AnnotationInspector.swift › Corner Radius | set_layer.cornerRadius
        AnnotationInspector.swift › Head Size | notYet: an arrow's head size
        AnnotationInspector.swift › Label corners | notYet: the rounding of an arrow label's chip
        AnnotationInspector.swift › Label size | notYet: the size of an arrow's label
        AnnotationInspector.swift › Slider | set_layer.cornerRadius
        AnnotationInspector.swift › Thickness | set_layer.strokeWidth
        ArrangeInspector.swift › alignButton: Button() | command: align
        ArrangeInspector.swift › spaceButton: Button() | command: space_evenly
        ArrangementInspector.swift › \\(title) \\(axis.noun) | set_layout.width
        ArrangementInspector.swift › Arrangement | set_layout.arrange
        ArrangementInspector.swift › Clip contents | notYet: whether a box clips what is in it
        ArrangementInspector.swift › Direction | set_layout.direction
        ArrangementInspector.swift › foldHead: Button(action: toggle) | leftOut: look
        ArrangementInspector.swift › Gap | set_layout.gap
        ArrangementInspector.swift › number: PanelNumberField(showing: NumberBox.showing(reading.value, standi) | set_layout.gap
        ArrangementInspector.swift › Padding | set_layout.padding
        ArrangementInspector.swift › padding: FourSidedButton(isOpen: $sidesOpen) | set_layout.padding
        ArrangementInspector.swift › sizeRows: SegmentedControl(axis.field) | set_layout.width
        ArrangementInspector.swift › Spread | set_layout.spread
        ArrangementInspector.swift › Wrap onto more lines | set_layout.wraps
        ArrowStyleTiles.swift › Arrow style \\(style.title) | set_layer.arrowStyle
        BlendModeInspector.swift › Blending | notYet: a layer's blend mode
        BlendModeInspector.swift › row: Button() | notYet: a layer's blend mode
        BrushChooser.swift › body: Button() | set_brush.medium
        BrushChooser.swift › Choose brush | set_brush.medium
        BrushChooser.swift › tile: Button() | set_brush.medium
        BrushSettingControls.swift › body: SegmentedControl(spec.name) | set_brush.settings
        BrushSettingControls.swift › Slider | set_brush.settings
        CalloutInspector.swift › body: Slider(value: Binding( get: { Double(magnification) }, ) | notYet: a zoom callout's magnification
        CalloutInspector.swift › body: Slider(value: Binding(get: { state.calloutToolMagnifica) | leftOut: toolInHand
        CalloutInspector.swift › Shape | notYet: a zoom callout's shape
        CalloutInspector.swift › Slider | notYet: a zoom callout's fill
        CanvasGridSettingsView.swift › body: SegmentedControl(CanvasGridCopy.lines) | leftOut: grid
        CanvasGridSettingsView.swift › body: Toggle(CanvasGridCopy.grid) | leftOut: grid
        CanvasGridSettingsView.swift › body: Toggle(CanvasGridCopy.snap) | leftOut: grid
        CanvasGridSettingsView.swift › cellRow: Picker(CanvasGridCopy.cell) | leftOut: grid
        CanvasGridSettingsView.swift › numberRow: TextField(label) | leftOut: grid
        CanvasInspector.swift › \\(c.slots.count) slots | notYet: a collage's slots, gutter and layout
        CanvasInspector.swift › Backdrop | notYet: the colour behind the canvas
        CanvasInspector.swift › Background fill | leftOut: the colour in a person's hand for Fill with Background; an agent paints a layer with set_layer's fill
        CanvasInspector.swift › body: Stepper(DocumentUnit.text(CGFloat(c.gutter))) | notYet: a collage's slots, gutter and layout
        CanvasInspector.swift › dimensionField: TextField(label) | command: canvas_size
        CanvasInspector.swift › Layout | notYet: a collage's slots, gutter and layout
        CaptionsInspector.swift › Align | notYet: how captions look (font, size, colours, placement)
        CaptionsInspector.swift › Caption background | notYet: how captions look (font, size, colours, placement)
        CaptionsInspector.swift › Caption colour | notYet: how captions look (font, size, colours, placement)
        CaptionsInspector.swift › Caption glow | notYet: how captions look (font, size, colours, placement)
        CaptionsInspector.swift › Caption shadow | notYet: how captions look (font, size, colours, placement)
        CaptionsInspector.swift › Caption stroke | notYet: how captions look (font, size, colours, placement)
        CaptionsInspector.swift › Captions \\(title) | command: add_captions
        CaptionsInspector.swift › Captions language | notYet: the language captions are written in
        CaptionsInspector.swift › Font | notYet: how captions look (font, size, colours, placement)
        CaptionsInspector.swift › Guides | command: caption_safe_areas
        CaptionsInspector.swift › Listening | command: cancel_captions
        CaptionsInspector.swift › Size | notYet: how captions look (font, size, colours, placement)
        CaptionsInspector.swift › Subtitles | command: export_captions
        CaptionsInspector.swift › Weight | notYet: how captions look (font, size, colours, placement)
        CaptionsInspector.swift › Write Captions | command: add_captions
        CaptionStyleInspector.swift › Animation | notYet: how captions look (font, size, colours, placement)
        CaptionStyleInspector.swift › Caption \\(control.title.lowercased()) | notYet: how captions look (font, size, colours, placement)
        CaptionStyleInspector.swift › Caption style \\(name) | notYet: a saved caption style
        CaptionStyleInspector.swift › Current word scale | notYet: how captions look (font, size, colours, placement)
        CaptionStyleInspector.swift › Current word shadow | notYet: how captions look (font, size, colours, placement)
        CaptionStyleInspector.swift › Current word speed | notYet: how captions look (font, size, colours, placement)
        CaptionStyleInspector.swift › Lines | notYet: how captions look (font, size, colours, placement)
        CaptionStyleInspector.swift › Save caption style | notYet: a saved caption style
        CaptionStyleInspector.swift › Show | notYet: how captions look (font, size, colours, placement)
        CaptionStyleInspector.swift › Word colour | notYet: how captions look (font, size, colours, placement)
        CaptionStyleInspector.swift › Word glow | notYet: how captions look (font, size, colours, placement)
        CaptionStyleInspector.swift › Word pill | notYet: how captions look (font, size, colours, placement)
        CaptionStyleInspector.swift › Word stroke | notYet: how captions look (font, size, colours, placement)
        ChartInspector.swift › Add Row | notYet: a chart's numbers and look once it is made
        ChartInspector.swift › Add Set | notYet: a chart's numbers and look once it is made
        ChartInspector.swift › body: TextField(prompt) | notYet: a chart's numbers and look once it is made
        ChartInspector.swift › Chart Kind | notYet: a chart's numbers and look once it is made
        ChartInspector.swift › Chart Unit | notYet: a chart's numbers and look once it is made
        ChartInspector.swift › Decimals | notYet: a chart's numbers and look once it is made
        ChartInspector.swift › Paste Rows | notYet: a chart's numbers and look once it is made
        ChartInspector.swift › Remove Row | notYet: a chart's numbers and look once it is made
        ChartInspector.swift › Row \\(index + 1) | notYet: a chart's numbers and look once it is made
        ChartInspector.swift › Set | notYet: a chart's numbers and look once it is made
        ChipStyleTiles.swift › Chip style \\(style.title) | set_layer.chip
        ChipStyleTiles.swift › Color \\(Self.names[index]) | set_layer.stroke
        ChipStyleTiles.swift › Custom | set_layer.stroke
        ChipStyleTiles.swift › Marker \\(marker.title) | set_layer.marker
        ChipStyleTiles.swift › Reset Colors | set_layer.stroke
        ClickEffectRows.swift › Click Style | notYet: how clicks look on a recording
        ClickEffectRows.swift › Clicks | notYet: how clicks look on a recording
        ClickEffectRows.swift › Color | notYet: how clicks look on a recording
        ClickEffectRows.swift › Size | notYet: how clicks look on a recording
        ColorGradeEffectRows.swift › Grade \\(grade.label) | notYet: a colour grade's settings
        ColorStylePanel.swift › body: Button() | notYet: changing a saved style itself (its colour, what it is for, its name, removing it)
        ColorStylePanel.swift › body: Toggle(role.title) | notYet: changing a saved style itself (its colour, what it is for, its name, removing it)
        ColorStylePanel.swift › Color | set_layer.fill
        ColorStylePanel.swift › Edit \\(style.name) in the Library | leftOut: inLibrary
        ColorStylePanel.swift › lookBody: Button() | apply_style.style
        ColorStylePanel.swift › lookBody: Button(option.label) | apply_style.style
        ColorStylePanel.swift › lookBody: Button(saveTitle(selection)) | add_style.name
        ColorStylePanel.swift › lookBody: Button(unlinkTitle(selection)) | notYet: unlinking a layer from the style it wears
        ColorStylePanel.swift › lookBody: Menu() | apply_style.style
        ColorStylePanel.swift › Remove | notYet: changing a saved style itself (its colour, what it is for, its name, removing it)
        ColorStylePanel.swift › Save | add_style.name
        ColorStylePanel.swift › Select What Uses This | leftOut: pick
        ColorStylePanel.swift › Set What It Is For in the Library | notYet: changing a saved style itself (its colour, what it is for, its name, removing it)
        ColorStylePanel.swift › Style name | add_style.name
        ColorStylePanel.swift › Switch | set_layer.fill
        ColorStylePanel.swift › Unlink | notYet: unlinking a layer from the style it wears
        ComponentPanel.swift › \\(property.name) name | notYet: renaming or removing a component's property
        ComponentPanel.swift › Add Property | add_component.property
        ComponentPanel.swift › Add to Picture | place_component.component
        ComponentPanel.swift › addMenu: Button(ComponentVariantWording.addPropertyRow) | add_component.property
        ComponentPanel.swift › addMenu: Button(ComponentVariantWording(variant.name).addRow(has) | add_component.looks
        ComponentPanel.swift › addMenu: Button(row.label) | add_component.property
        ComponentPanel.swift › addMenu: Button(wording.addRow(hasAny: !variants.isEmpty)) | add_component.looks
        ComponentPanel.swift › body: Button() | notYet: renaming or removing a component's property
        ComponentPanel.swift › body: Button(option.name) | notYet: a placed copy's variant, words, colours and room
        ComponentPanel.swift › body: Button(version.name) | notYet: a placed copy's variant, words, colours and room
        ComponentPanel.swift › body: FourSidedButton(isOpen: $isOpen) | notYet: a placed copy's variant, words, colours and room
        ComponentPanel.swift › body: PanelNumberField(showing: NumberBox.showing(room?.uniform, standi) | notYet: a placed copy's variant, words, colours and room
        ComponentPanel.swift › body: PanelNumberField(showing: NumberBox.showing(value, standingIn: va) | notYet: a placed copy's variant, words, colours and room
        ComponentPanel.swift › body: TextField(index == 0 ? "Property name" : "Property name \\() | add_component.property
        ComponentPanel.swift › body: Toggle("") | notYet: a placed copy's variant, words, colours and room
        ComponentPanel.swift › Color | notYet: a placed copy's variant, words, colours and room
        ComponentPanel.swift › Component name | notYet: renaming a component or a variant
        ComponentPanel.swift › Edit \\(style.name) in the Library | leftOut: inLibrary
        ComponentPanel.swift › field: TextField(isMixed ? "" : property.name) | notYet: a placed copy's variant, words, colours and room
        ComponentPanel.swift › Make \\(name) a Property | add_component.property
        ComponentPanel.swift › Make Its Wording a Property | add_component.property
        ComponentPanel.swift › No saved colors yet | leftOut: look
        ComponentPanel.swift › ownLook: Button() | notYet: a placed copy's variant, words, colours and room
        ComponentPanel.swift › Place a Copy | place_component.component
        ComponentPanel.swift › Property name | add_component.property
        ComponentPanel.swift › Put It Back on the Shelf | notYet: sharing a component across documents
        ComponentPanel.swift › Remove \\(property.name) | notYet: renaming or removing a component's property
        ComponentPanel.swift › Reset Props | notYet: a placed copy's variant, words, colours and room
        ComponentPanel.swift › Revert \\(field.label) | notYet: a placed copy's variant, words, colours and room
        ComponentPanel.swift › Revert Size | notYet: a placed copy's variant, words, colours and room
        ComponentPanel.swift › Revert Type | notYet: a placed copy's variant, words, colours and room
        ComponentPanel.swift › revert: Button() | notYet: a placed copy's variant, words, colours and room
        ComponentPanel.swift › Select Copy | leftOut: pick
        ComponentPanel.swift › Set What It Is For in the Library | notYet: changing a saved style itself (its colour, what it is for, its name, removing it)
        ComponentPanel.swift › Share across documents | notYet: sharing a component across documents
        ComponentPanel.swift › stylesMenu: Button() | notYet: a placed copy's variant, words, colours and room
        ComponentPanel.swift › stylesMenu: Button(option.label) | notYet: a placed copy's variant, words, colours and room
        ComponentPanel.swift › Unlink | notYet: a placed copy's variant, words, colours and room
        ComponentPanel.swift › Variant name | notYet: renaming a component or a variant
        ComponentPanel.swift › versionRow: SegmentedControl(row.name) | notYet: a placed copy's variant, words, colours and room
        ComponentPanel.swift › versionRow: SegmentedControl(variantName) | notYet: a placed copy's variant, words, colours and room
        CompositingInspector.swift › choice: Button() | notYet: masks and chroma keys
        CompositingInspector.swift › Key | notYet: masks and chroma keys
        CompositingInspector.swift › Key It | notYet: masks and chroma keys
        CompositingInspector.swift › Key It Again | notYet: masks and chroma keys
        CompositingInspector.swift › Masked by | notYet: masks and chroma keys
        CompositingInspector.swift › slider: LayerStyleSlider(layerIDs: selection.layerIDs) | notYet: masks and chroma keys
        EffectsListInspector.swift › Amount | notYet: an added effect's settings (set_layer reaches a drop shadow's only)
        EffectsListInspector.swift › Follows | notYet: an added effect's settings (set_layer reaches a drop shadow's only)
        EffectsListInspector.swift › Kind | notYet: an added effect's settings (set_layer reaches a drop shadow's only)
        EffectsListInspector.swift › Offset | set_layer.shadow
        EffectsListInspector.swift › Opacity | set_layer.shadow
        EffectsListInspector.swift › Shutter | notYet: an added effect's settings (set_layer reaches a drop shadow's only)
        EffectsListInspector.swift › Size | notYet: an added effect's settings (set_layer reaches a drop shadow's only)
        EffectsListInspector.swift › Softness | set_layer.shadow
        EffectsListInspector.swift › Width | notYet: an added effect's settings (set_layer reaches a drop shadow's only)
        EffectsListInspector.swift › Zoom | notYet: an added effect's settings (set_layer reaches a drop shadow's only)
        EffectsListRow.swift › Move Down | notYet: the order of a layer's effects
        EffectsListRow.swift › Move Up | notYet: the order of a layer's effects
        EffectsListRow.swift › Remove | command: remove_effect
        EffectsListRow.swift › Switch | notYet: turning one effect off and on
        EffectsListRow.swift › Twist | leftOut: look
        EffectStylePanel.swift › body: Button() | leftOut: shelf
        EffectStylePanel.swift › colorRow: Button() | notYet: changing a saved style itself (its colour, what it is for, its name, removing it)
        EffectStylePanel.swift › Edit \\(style.name) in the Library | leftOut: inLibrary
        EffectStylePanel.swift › lookBody: Button() | command: add_saved_effect
        EffectStylePanel.swift › lookBody: Button(saveTitle(selection)) | notYet: saving an effect as a style
        EffectStylePanel.swift › lookBody: Button(unlinkTitle(selection)) | notYet: unlinking a layer from the style it wears
        EffectStylePanel.swift › picker: SegmentedControl(label) | notYet: changing a saved style itself (its colour, what it is for, its name, removing it)
        EffectStylePanel.swift › Remove | notYet: changing a saved style itself (its colour, what it is for, its name, removing it)
        EffectStylePanel.swift › Save | notYet: saving an effect as a style
        EffectStylePanel.swift › Select What Uses This | leftOut: pick
        EffectStylePanel.swift › Slider | notYet: changing a saved style itself (its colour, what it is for, its name, removing it)
        EffectStylePanel.swift › Style | command: add_saved_effect
        EffectStylePanel.swift › Style name | notYet: saving an effect as a style
        FrameColumnsInspector.swift › body: Toggle(FrameColumnsCopy.show) | command: show_columns
        FrameColumnsInspector.swift › numberRow: TextField(label) | notYet: a screen's columns, gutter and margin
        FrameInspector.swift › body: Menu() | set_layer.width
        FrameInspector.swift › Clip contents | notYet: whether a box clips what is in it
        FrameInspector.swift › sizeButton: Button() | set_layer.width
        GeometryInspector.swift › body: Button(action: explain) | leftOut: look
        GeometryInspector.swift › field: PanelNumberField(showing: selection.reading(field).showing(for: f) | set_layer.x
        GeometryInspector.swift › regionField: PanelNumberField(showing: region.reading(field).showing(for: fiel) | leftOut: the box of a selection a hand drew on the pixels; select_pixels and the layer tools work on layers an agent names
        InspectorControls.swift › box: PanelNumberField(showing: isMixed ? .standIn(LayerStyleSelection.) | leftOut: slider box
        InspectorPanel.swift › \\(section) help | leftOut: look
        LayerEffectsInspector.swift › Blur | notYet: an added effect's settings (set_layer reaches a drop shadow's only)
        LayerEffectsInspector.swift › Border | notYet: an added effect's settings (set_layer reaches a drop shadow's only)
        LayerEffectsInspector.swift › Direction | set_layer.shadow
        LayerEffectsInspector.swift › Distance | set_layer.shadow
        LayerEffectsInspector.swift › Enable Shadow | set_layer.removeShadow
        LayerEffectsInspector.swift › lookBody: LayerStyleSlider(layerIDs: ids) | set_layer.shadow
        LayerEffectsInspector.swift › Opacity | set_layer.opacity
        LayerEffectsInspector.swift › Shadow | set_layer.shadow
        LayerEffectsInspector.swift › Size | set_layer.shadow
        LayersListView.swift › Clear the search | leftOut: look
        LayersListView.swift › Find a layer | leftOut: look
        LayersListView.swift › Out of view | command: bring_into_view
        LayersListView.swift › separationOffer: Button(SeparationLeftover.againLabel) | command: separate_into_layers
        LayersPanelHeaderControls.swift › body: Button() | command: make_component
        LayersPanelHeaderControls.swift › body: Menu() | leftOut: look
        LayersPanelHeaderControls.swift › item: Button() | command: stack_selection, group, mirror_across_center, center_on_artboard, union, outline_stroke, make_component
        LensInspector.swift › body: Slider(value: Binding( get: { Double(amount) }, set: { ) | notYet: a lens's kind and amount
        LensInspector.swift › body: Slider(value: Binding(get: { Double(editorState.lensToo) | leftOut: toolInHand
        LibraryCatalogTiles.swift › \\(count) | command: apply_transition_to_every_cut
        LibraryCatalogTiles.swift › Insert at Playhead | notYet: putting a Library background on the timeline
        LibraryColorDrop.swift › Save | add_style.name
        LibraryColorDrop.swift › Style name | add_style.name
        LibraryPanel.swift › Add at Playhead | command: add_media_at_playhead
        LibraryPanel.swift › Add Selection to Library | command: make_component
        LibraryPanel.swift › Add to Library | command: make_component, import_media
        LibraryPanel.swift › Built for video | leftOut: shelf
        LibraryPanel.swift › From Capture History | leftOut: shelf
        LibraryPanel.swift › Place in Picture | add_photo.frame
        LibraryPanel.swift › Search library | leftOut: shelf
        LibraryPanel.swift › searchField: Button() | leftOut: shelf
        LibraryPanel.swift › Shelf | leftOut: shelf
        LibraryTitleTile.swift › body: Button(label) | command: insert_title
        MeasureInspector.swift › body: Slider(value: Binding( get: { Double(px) }, set: { edit) | notYet: how a measurement looks (role, unit, line, label)
        MeasureInspector.swift › Details | leftOut: look
        MeasureInspector.swift › Measurement name | set_layer.name
        MeasureInspector.swift › Role | notYet: how a measurement looks (role, unit, line, label)
        MeasureInspector.swift › swatchRow: ColorWellButton(hex: hex) | notYet: how a measurement looks (role, unit, line, label)
        MeasureInspector.swift › Thickness | notYet: how a measurement looks (role, unit, line, label)
        MeasureInspector.swift › Unit | notYet: how a measurement looks (role, unit, line, label)
        MeasurementsListView.swift › body: Menu() | leftOut: look
        MeasurementsListView.swift › Measurement name | set_layer.name
        MeasurementsListView.swift › row: Button() | set_layer.visible
        MeasurePartSettings.swift › Role | notYet: how a measurement looks (role, unit, line, label)
        MeasurePartSettings.swift › Slider | notYet: how a measurement looks (role, unit, line, label)
        MeasurePartSettings.swift › Unit | notYet: how a measurement looks (role, unit, line, label)
        MeasurePartSettings.swift › Width | notYet: how a measurement looks (role, unit, line, label)
        MotionListInspector.swift › \\(motion.property.title) \\(label) | notYet: a motion row's settings (start, length, curve, repeat, pivot)
        MotionListInspector.swift › \\(motion.property.title) \\(label) X | notYet: a motion row's settings (start, length, curve, repeat, pivot)
        MotionListInspector.swift › \\(motion.property.title) \\(label) Y | notYet: a motion row's settings (start, length, curve, repeat, pivot)
        MotionListInspector.swift › \\(offer.property.title)    \\(offer.reading) | set_keys.property
        MotionListInspector.swift › Add Motion | set_keys.property
        MotionListInspector.swift › Around | set_keys.pivot
        MotionListInspector.swift › Around X | set_keys.pivot
        MotionListInspector.swift › Around Y | set_keys.pivot
        MotionListInspector.swift › aroundMenu: Button() | set_keys.pivot
        MotionListInspector.swift › aroundMenu: Button(own.title) | set_keys.pivot
        MotionListInspector.swift › aroundMenu: Button(spot.title) | set_keys.pivot
        MotionListInspector.swift › At | set_keys.pivot
        MotionListInspector.swift › body: Button() | notYet: a motion row's settings (start, length, curve, repeat, pivot)
        MotionListInspector.swift › body: Button(choice.title) | notYet: a motion row's settings (start, length, curve, repeat, pivot)
        MotionListInspector.swift › body: ColorWellButton(hex: hex) | set_keys.keys
        MotionListInspector.swift › body: Menu() | notYet: a motion row's settings (start, length, curve, repeat, pivot)
        MotionListInspector.swift › body: MotionNumberField(value: Double(isStart ? motion.timing.startMS : ) | notYet: a motion row's settings (start, length, curve, repeat, pivot)
        MotionListInspector.swift › body: MotionSettingRow(label: isStart ? "Start" : "Over") | notYet: a motion row's settings (start, length, curve, repeat, pivot)
        MotionListInspector.swift › body: MotionSettingRow(label: label) | set_keys.keys
        MotionListInspector.swift › Curve | set_keys.keys
        MotionListInspector.swift › Draw a Curve... | leftOut: a pad a person draws a curve on by hand; set_keys gives a key any named curve or cubic-bezier
        MotionListInspector.swift › Drawn | set_keys.keys
        MotionListInspector.swift › Move the pivot | leftOut: pointer
        MotionListInspector.swift › Name | leftOut: names a curve a person drew by hand, for their own list
        MotionListInspector.swift › Preview | leftOut: plays a motion for a person to watch; video_frame and contact_sheet show any moment
        MotionListInspector.swift › Remove | command: stop_animating
        MotionListInspector.swift › Repeat | set_timing.loop
        MotionListInspector.swift › Save Curve | leftOut: names a curve a person drew by hand, for their own list
        MotionListInspector.swift › Switch | notYet: a motion row's settings (start, length, curve, repeat, pivot)
        MotionListInspector.swift › Twist | leftOut: look
        MotionListInspector.swift › Use This Curve | set_keys.keys
        PanelSectionsFooter.swift › \\(section.title) section switch | leftOut: panel
        PanelSectionsFooter.swift › Sections | leftOut: panel
        PanelSectionsFooter.swift › Use Automatic for All | leftOut: panel
        PartsInspector.swift › Opacity | set_layer.opacity
        PartsInspector.swift › Switch | set_layer.fill
        PlacementInspector.swift › childRows: Button(choiceTitle(choice, resolved, arranges: arranges) | notYet: how the pieces follow when their box is resized
        PlacementInspector.swift › childRows: Button(followTitle(inherited.horizontal.title, isFrame:) | notYet: how the pieces follow when their box is resized
        PlacementInspector.swift › childRows: Button(followTitle(inherited.vertical.title, isFrame: c) | notYet: how the pieces follow when their box is resized
        PlacementInspector.swift › childRows: Menu() | notYet: how the pieces follow when their box is resized
        PlacementInspector.swift › Clear \\(stale) | notYet: how the pieces follow when their box is resized
        PlacementInspector.swift › contentRows: Button(choice.title) | notYet: how the pieces follow when their box is resized
        PlacementInspector.swift › contentRows: Menu() | notYet: how the pieces follow when their box is resized
        PlacementInspector.swift › in \\(exception.groupName) | leftOut: pick
        PlacementInspector.swift › ownedByTheFlow: Button(filling.answer) | command: fill_the_stack
        PlacementInspector.swift › ownedByTheFlow: Button(filling.fill) | command: fill_the_stack
        PlacementInspector.swift › ownedByTheFlow: Menu() | command: fill_the_stack
        PlacementInspector.swift › Role | command: in_front_of_the_rest, surface_behind
        PlacementInspector.swift › surfaceRow: Button(PieceRole.arranged.title) | notYet: putting a piece back into its stack's flow
        PlacementInspector.swift › surfaceRow: Button(PieceRole.inFront.title) | command: in_front_of_the_rest
        PlacementInspector.swift › surfaceRow: Button(PieceRole.surface.title) | command: surface_behind
        PropertyKeysInspector.swift › Animate a property | command: animate_property
        PropertyKeysInspector.swift › body: Button(action: action) | leftOut: look
        PropertyKeysInspector.swift › body: ColorWellButton(hex: hex) | set_keys.keys
        PropertyKeysInspector.swift › body: CurveRow(current: curve ?? PropertyKeys.curve) | command: set_easing
        PropertyKeysInspector.swift › Cancel | leftOut: look
        PropertyKeysInspector.swift › Graph | leftOut: look
        PropertyKeysInspector.swift › head: KeyDiamondButton(property: property) | command: key_at_playhead
        PropertyKeysInspector.swift › numberBox: PanelNumberField(showing: .number(Self.text(value))) | set_keys.keys
        PropertyKeysInspector.swift › Path | command: curve_the_path
        PropertyKeysInspector.swift › Properties Menu | leftOut: look
        PropertyKeysInspector.swift › Remove Keys | remove_keys.property
        PropertyKeysInspector.swift › stepButton: Button() | leftOut: keyStep
        SavedStrokePanel.swift › body: Button() | leftOut: shelf
        SavedStrokePanel.swift › controls: Button() | notYet: saved lines (a line saved as a style)
        SavedStrokePanel.swift › Edit \\(wearing.name) in the Library | leftOut: inLibrary
        SavedStrokePanel.swift › menu: Button(stroke.name) | notYet: saved lines (a line saved as a style)
        SavedStrokePanel.swift › Remove | notYet: saved lines (a line saved as a style)
        SavedStrokePanel.swift › Save | notYet: saved lines (a line saved as a style)
        SavedStrokePanel.swift › Save as Style | notYet: saved lines (a line saved as a style)
        SavedStrokePanel.swift › Select What Uses This | leftOut: pick
        SavedStrokePanel.swift › Slider | notYet: saved lines (a line saved as a style)
        SavedStrokePanel.swift › Style | notYet: saved lines (a line saved as a style)
        SavedStrokePanel.swift › Style name | notYet: saved lines (a line saved as a style)
        SavedStrokePanel.swift › Unlink | notYet: saved lines (a line saved as a style)
        ShapePartSettings.swift › Head Size | notYet: an arrow's head size
        ShapePartSettings.swift › Label corners | notYet: the rounding of an arrow label's chip
        ShapePartSettings.swift › Label size | notYet: the size of an arrow's label
        ShapePartSettings.swift › lookBody: Button(pinned.count > 1 ? "Reset Label Positions" : "Re) | leftOut: hand
        ShapePartSettings.swift › Width | set_layer.strokeWidth
        SoundEffectsInspector.swift › Add Audio Effect | notYet: a sound's EQ and compressor
        SoundEffectsInspector.swift › High | notYet: a sound's EQ and compressor
        SoundEffectsInspector.swift › Low | notYet: a sound's EQ and compressor
        SoundEffectsInspector.swift › Low cut | notYet: a sound's EQ and compressor
        SoundEffectsInspector.swift › Ratio | notYet: a sound's EQ and compressor
        SoundEffectsInspector.swift › Strength | notYet: how strongly noise is cleaned
        SoundEffectsInspector.swift › Threshold | notYet: a sound's EQ and compressor
        SoundInspector.swift › body: TextField(label) | notYet: a sound's volume, gain and fade curve
        SoundInspector.swift › Clean noise | command: normalize_cleans_noise
        SoundInspector.swift › curve: CurveRow(current: editorState.soundLevelInHand.fadeCurve) | notYet: a sound's volume, gain and fade curve
        SoundInspector.swift › Gain | notYet: a sound's volume, gain and fade curve
        SoundInspector.swift › Mute | command: mute_sound
        SoundInspector.swift › Points | command: flatten_level
        SoundInspector.swift › Segment | notYet: a sound's volume, gain and fade curve
        SoundInspector.swift › Solo | command: solo_sound
        SoundInspector.swift › Volume | notYet: a sound's volume, gain and fade curve
        Space3DInspector.swift › \\(title) Value | notYet: the camera's values and keys
        Space3DInspector.swift › body: Button() | notYet: the camera's values and keys
        Space3DInspector.swift › body: CurveRow(current: editorState.cameraStretchCurve) | notYet: the camera's values and keys
        Space3DInspector.swift › body: SpaceValueRow(property: .depth) | set_layer.depth
        Space3DInspector.swift › body: SpaceValueRow(property: .pivotDepth) | notYet: the depth a layer turns about
        Space3DInspector.swift › body: SpaceValueRow(property: .rotationX) | set_layer.tip
        Space3DInspector.swift › body: SpaceValueRow(property: .rotationY) | set_layer.swing
        SpeedInspector.swift › Between stops | notYet: how a speed ramp blends between its stops
        SpeedInspector.swift › Hold | command: freeze_frame
        SpeedInspector.swift › pictureFades: CurveRow(current: fade.shownCurve) | notYet: a picture fade's curve
        SpeedInspector.swift › pictureFades: VideoKit.DropdownRow(label: end.title) | command: set_fade
        SpeedInspector.swift › Speed | command: set_speed
        SpeedInspector.swift › Speed stop | leftOut: look
        TextInspector.swift › Font | notYet: a text layer's font, weight, tracking, leading and alignment once it is made
        TextInspector.swift › Leading | notYet: a text layer's font, weight, tracking, leading and alignment once it is made
        TextInspector.swift › Size | set_layer.fontSize
        TextInspector.swift › Tracking | notYet: a text layer's font, weight, tracking, leading and alignment once it is made
        TextInspector.swift › Weight | notYet: a text layer's font, weight, tracking, leading and alignment once it is made
        TextInspector.swift › Words across the box | notYet: a text layer's font, weight, tracking, leading and alignment once it is made
        TextInspector.swift › Words down the box | notYet: a text layer's font, weight, tracking, leading and alignment once it is made
        TextOnPathInspector.swift › body: KeyDiamondButton(property: keyed) | command: key_at_playhead
        TextOnPathInspector.swift › Path start Value | notYet: where words start along their path
        TextRevealInspector.swift › body: CurveRow(current: reveal.curve) | notYet: how a text layer's words come in
        TextRevealInspector.swift › Reveal By | notYet: how a text layer's words come in
        TextRevealInspector.swift › Reveal Each | notYet: how a text layer's words come in
        TextRevealInspector.swift › Reveal Order | notYet: how a text layer's words come in
        TextRevealInspector.swift › Reveal Preset | notYet: how a text layer's words come in
        TextRevealInspector.swift › Reveal Stagger | notYet: how a text layer's words come in
        TextStylePanel.swift › body: Button() | leftOut: shelf
        TextStylePanel.swift › colorRow: Button() | notYet: changing a saved style itself (its colour, what it is for, its name, removing it)
        TextStylePanel.swift › Edit \\(style.name) in the Library | leftOut: inLibrary
        TextStylePanel.swift › lookBody: Button() | apply_style.style
        TextStylePanel.swift › lookBody: Button(saveTitle(selection)) | add_style.name
        TextStylePanel.swift › lookBody: Button(unlinkTitle(selection)) | notYet: unlinking a layer from the style it wears
        TextStylePanel.swift › lookBody: Menu() | apply_style.style
        TextStylePanel.swift › Remove | notYet: changing a saved style itself (its colour, what it is for, its name, removing it)
        TextStylePanel.swift › Save | add_style.name
        TextStylePanel.swift › Select What Uses This | leftOut: pick
        TextStylePanel.swift › Style name | add_style.name
        TitleBackgroundPicker.swift › tile: Button() | notYet: restyling a title once it is made
        TitleRestyleInspector.swift › Background | notYet: restyling a title once it is made
        TitleRestyleInspector.swift › build: CurveRow(current: build.curve) | notYet: restyling a title once it is made
        TitleRestyleInspector.swift › Energy | notYet: restyling a title once it is made
        TitleRestyleInspector.swift › Intensity | notYet: restyling a title once it is made
        TitleRestyleInspector.swift › Part \\(name) | leftOut: pick
        TitleRestyleInspector.swift › Part \\(row) \\(amount.label) | notYet: restyling a title once it is made
        TitleRestyleInspector.swift › Part \\(row) \\(label) | notYet: restyling a title once it is made
        TitleRestyleInspector.swift › Part \\(row) Direction | notYet: restyling a title once it is made
        TitleRestyleInspector.swift › Part Hold | notYet: restyling a title once it is made
        TitleRestyleInspector.swift › Part In By | notYet: restyling a title once it is made
        TitleRestyleInspector.swift › Replay | command: replay_title
        TitleRestyleInspector.swift › Slider | notYet: restyling a title once it is made
        TitleRestyleInspector.swift › Sounds | notYet: restyling a title once it is made
        TitleRestyleInspector.swift › Theme \\(theme.name) | notYet: restyling a title once it is made
        TitleRestyleInspector.swift › Theme From Recording | notYet: restyling a title once it is made
        TitleRestyleInspector.swift › Title Font Pair | notYet: restyling a title once it is made
        TitleRestyleInspector.swift › Title Part | leftOut: pick
        ToolInspectors.swift › Anti-alias | leftOut: toolInHand
        ToolInspectors.swift › body: Slider(value: Binding(get: { editorState.bucketToleranc) | leftOut: toolInHand
        ToolInspectors.swift › body: Slider(value: Binding(get: { editorState.wandTolerance ) | leftOut: toolInHand
        ToolInspectors.swift › Contiguous | leftOut: toolInHand
        ToolInspectors.swift › Snap | leftOut: toolInHand
        TrackInspector.swift › Hide | command: hide_track
        TrackInspector.swift › Lock | command: lock_track
        TrackInspector.swift › Mute | command: mute_track
        TrackInspector.swift › Solo | command: solo_track
        TransitionInspector.swift › At the cut | notYet: where a transition sits on its cut, its direction, hold and motion blur
        TransitionInspector.swift › body: CurveRow(current: transition.curve) | command: set_transition_curve
        TransitionInspector.swift › Direction | notYet: where a transition sits on its cut, its direction, hold and motion blur
        TransitionInspector.swift › hold: VideoKit.DropdownRow(label: label) | notYet: where a transition sits on its cut, its direction, hold and motion blur
        TransitionInspector.swift › Length | set_transition.lengthSeconds
        TransitionInspector.swift › Motion blur | notYet: where a transition sits on its cut, its direction, hold and motion blur
        TransitionInspector.swift › Or | notYet: where a transition sits on its cut, its direction, hold and motion blur
        TransitionInspector.swift › The overlap sits | notYet: where a transition sits on its cut, its direction, hold and motion blur
        TransitionInspector.swift › Transition Menu | leftOut: look
        TransitionInspector.swift › Type | set_transition.kind
        TransitionsGroup.swift › Search transitions | leftOut: shelf
        TransitionsGroup.swift › searchField: Button() | leftOut: shelf
        TransitionsGroup.swift › Transitions menu | leftOut: look
        ZoomInspector.swift › Curve In | notYet: how a zoom eases in and out
        ZoomInspector.swift › Curve Out | notYet: how a zoom eases in and out
        ZoomInspector.swift › curves: CurveRow(current: reading.curvesApart == nil ? nil : read) | notYet: how a zoom eases in and out
        ZoomInspector.swift › Ease In | notYet: how a zoom eases in and out
        ZoomInspector.swift › Ease Out | notYet: how a zoom eases in and out
        ZoomInspector.swift › Zoom amount | command: set_zoom_amount
        """

    /// How many panel controls are not reached yet. Lower it as they get a way
    /// in; never raise it to make room for a new control.
    static let panelNotYetPin = 213

    // MARK: Right-click menus

    /// Every right-click menu, by where its rows are built, and what a person
    /// calls it. A new menu fails until it is named here.
    static let menus: [String: String] = [
        "AgentsSettingsSection.swift › row (right-click)": "A Settings ▸ Agents row",
        "AskHistoryCard.swift › body (right-click)": "An Ask history card",
        "AskViews.swift › waitingRow (right-click)": "Ask's waiting row",
        "CanvasMenuRows.swift › bareCanvasMenuRows": "The canvas, on an empty spot",
        "CanvasSelectionGrips.swift › chipResetMenuRows": "The canvas selection's mode chip",
        "CaptionStyleInspector.swift › body (right-click)": "A saved caption style",
        "ColorGradeEffectRows.swift › body (right-click)": "A colour grade row",
        "ComponentPanel.swift › body (right-click)": "A component tile, and a property chip",
        "EditorState+Annotations.swift › arrowBendMenuRows": "An arrow",
        "EditorState+Annotations.swift › arrowStyleMenuRows": "An arrow ▸ Arrow Style",
        "EditorState+Annotations.swift › chipStyleMenuRows": "An arrow ▸ its label's chip",
        "EditorState+CameraRow.swift › cameraKeyMenuRows": "A camera key on the timeline",
        "EditorState+CaptionWords.swift › captionWordMenuRows": "A caption word",
        "EditorState+ClickEffects.swift › clickTickMenuRows": "A click on a recording's click lane",
        "EditorState+ClipKeys.swift › clipKeyMenuRows": "A key on a clip",
        "EditorState+ClipKeys.swift › titleAnimationMenuRows": "A title ▸ Animate In and Animate Out",
        "EditorState+KeyGraph.swift › segmentCurveRows": "A stretch on a key graph ▸ its curve",
        "EditorState+KeyGraph.swift › segmentMenuRows": "A stretch on a key graph",
        "EditorState+KeyLanes.swift › graphRows": "A key lane ▸ Show Graph",
        "EditorState+KeyLanes.swift › keyLaneMenuRows": "A key lane",
        "EditorState+KeyLanes.swift › keyMenuRows": "A key",
        "EditorState+KeyLanes.swift › pasteKeysRow": "A key lane ▸ Paste Keys",
        "EditorState+MeasureChip.swift › measureChipStyleMenuRows": "A measurement's label chip",
        "EditorState+MotionPath.swift › motionPathMenuRows": "A motion path on the canvas",
        "EditorState+OnlyAnimated.swift › animateMenuRow": "Animate ▸ a value",
        "EditorState+PictureFade.swift › fadeInAndOutMenuRow": "A picture's fade",
        "EditorState+PictureFade.swift › pictureFadeMenuRows": "A picture's fade",
        "EditorState+PictureKeys.swift › addKeyMenuRows": "A picture's key strip",
        "EditorState+RangeClipboard.swift › pasteRangeRow": "A range ▸ Paste",
        "EditorState+RangeSection.swift › rangeSectionMenuRows": "A picked range",
        "EditorState+RangeSection.swift › sectionRow": "A picked range",
        "EditorState+Reframe.swift › punchInMenuRows": "A clip ▸ Punch In",
        "EditorState+RulerRange.swift › rulerRangeMenuRows": "A range on the timeline ruler",
        "EditorState+SoundLine.swift › soundPointMenuRows": "A point on a volume line",
        "EditorState+SoundLine.swift › soundSegmentMenuRows": "A stretch of a volume line",
        "EditorState+TimelineGap.swift › timelineSpaceMenuRows": "Empty space on the timeline",
        "EditorState+TimelineMenus.swift › addCaptionsMenuRow": "A clip ▸ Add Captions",
        "EditorState+TimelineMenus.swift › captionCueMenuRows": "A caption on the captions track",
        "EditorState+TimelineMenus.swift › captionTrackMenuRows": "The captions track",
        "EditorState+TimelineMenus.swift › clipMenuRows": "A clip on the timeline",
        "EditorState+TimelineMenus.swift › cutMenuRows": "A cut between two clips",
        "EditorState+TimelineMenus.swift › cutTransitionMenuRows": "A transition on a cut",
        "EditorState+TimelineMenus.swift › freezeFrameMenuRow": "A clip ▸ Freeze Frame",
        "EditorState+TimelineMenus.swift › soundGainMenuRows": "A clip ▸ Sound ▸ Normalize",
        "EditorState+TimelineMenus.swift › speedStopMenuRows": "A speed stop",
        "EditorState+TimelineMenus.swift › timelineClipMenuRows": "A clip on the timeline",
        "EditorState+TimelineMenus.swift › timelineMenu": "A thing on the timeline ▸ More",
        "EditorState+TimelineMenus.swift › timelineRulerMenuRows": "The timeline ruler",
        "EditorState+TimelineMenus.swift › timelineViewMenuRows": "The timeline's background",
        "EditorState+TitlePresets.swift › titleInsertMenuRows": "Insert Title",
        "EditorState+TitlePresets.swift › titlePresetRows": "Insert Title ▸ a preset",
        "EditorState+TitlePresets.swift › titlePresetSaveMenuRows": "A title ▸ Save as Preset",
        "EditorState+TitleTime.swift › placedLayerFadeRows": "A placed picture ▸ Fade",
        "EditorState+TrackRange.swift › trackThingMenuRows": "A range on a track",
        "EditorState+TransitionClipboard.swift › transitionClipboardMenuRows": "A transition ▸ Copy and Paste",
        "EditorState+TransitionTargets.swift › clipTransitionMenuRows": "A clip ▸ Transition",
        "EditorState+TransitionTargets.swift › transitionPickerMenuRow": "A cut ▸ Transition…",
        "EditorState+Zoom.swift › addZoomMenuRows": "A clip ▸ Add Zoom",
        "EditorState+Zoom.swift › zoomMenuRows": "A zoom on the Zoom lane",
        "LayerCommandMenu.swift › rows": "A layer, in the layers list and on the canvas",
        "LibraryCatalogTiles.swift › body (right-click)": "A Library background or transition tile",
        "LibraryClipTile.swift › body (right-click)": "A Library clip tile",
        "LibraryTitleTile.swift › body (right-click)": "A Library title tile",
        "MeasurementsListView.swift › row (right-click)": "A row of the measurements list",
        "MotionListInspector.swift › body (right-click)": "A motion row",
        "PropertyKeysInspector.swift › body (right-click)": "A row of Properties",
        "Space3DInspector.swift › body (right-click)": "A 3D value row",
        "TimelineCameraRow.swift › lane": "The timeline's camera lane",
        "TimelineTrackRows.swift › header (right-click)": "A track header",
        "TimelineTrackRows.swift › TimelineTrackMenu": "A track header",
        "TransitionPicker.swift › tile (right-click)": "A transition picker tile",
        "TransitionsGroup.swift › tile (right-click)": "A Transitions panel tile",
    ]

    /// Right-click rows not titled with a command's own words: the title as
    /// written, and how an agent reaches it. Same shape as the panel's table.
    static let rowTable = """
        AgentsSettingsSection.swift › row (right-click) :: "Copy Setup Command" | leftOut: ask
        AskHistoryCard.swift › body (right-click) :: AskCopy.selectMade | leftOut: ask
        AskHistoryCard.swift › body (right-click) :: AskCopy.clearHistory | leftOut: ask
        AskViews.swift › waitingRow (right-click) :: AskCopy.cancelWaiting | leftOut: ask
        CanvasSelectionGrips.swift › chipResetMenuRows :: reset.title | command: reset_size, reset_skew_and_distort, reset_3d, reset_all_transforms
        CaptionStyleInspector.swift › body (right-click) :: "Delete Style" | notYet: a saved caption style
        ComponentPanel.swift › body (right-click) :: "Remove \\(property.name)" | notYet: renaming or removing a component's property
        ComponentPanel.swift › body (right-click) :: "Place a Copy" | place_component.component
        ComponentPanel.swift › body (right-click) :: OriginalSpaceCopy.menuEdit | command: edit_original
        EditorState+Annotations.swift › arrowBendMenuRows :: ArrowBend.straightenTitle | command: straighten_arrows
        EditorState+Annotations.swift › arrowStyleMenuRows :: ArrowStyle.menuTitle | command: set_arrow_style
        EditorState+Annotations.swift › arrowStyleMenuRows :: style.title | command: set_arrow_style
        EditorState+Annotations.swift › arrowStyleMenuRows :: ArrowStyle.reshuffleTitle | command: reshuffle_arrows
        EditorState+Annotations.swift › chipStyleMenuRows :: ChipStyle.menuTitle | set_layer.chip
        EditorState+Annotations.swift › chipStyleMenuRows :: style.title | set_layer.chip
        EditorState+Annotations.swift › chipStyleMenuRows :: ChipMarker.menuTitle | set_layer.marker
        EditorState+Annotations.swift › chipStyleMenuRows :: marker.title | set_layer.marker
        EditorState+Annotations.swift › chipStyleMenuRows :: MarkSize.menuTitle | notYet: the size of an arrow's label
        EditorState+Annotations.swift › chipStyleMenuRows :: size.name | notYet: the size of an arrow's label
        EditorState+CameraRow.swift › cameraKeyMenuRows :: ease.title | notYet: the camera's values and keys
        EditorState+CameraRow.swift › cameraKeyMenuRows :: "Show Camera Settings" | leftOut: look
        EditorState+ClipKeys.swift › clipKeyMenuRows :: ease.title | command: set_easing
        EditorState+ClipKeys.swift › clipKeyMenuRows :: refs.count > 1 ? "Copy \\(refs.count) Keys" : "Copy Key" | command: copy
        EditorState+ClipKeys.swift › titleAnimationMenuRows :: kind.title | command: animate_in, animate_out
        EditorState+KeyGraph.swift › segmentCurveRows :: "Draw a Curve\\u{2026}" | leftOut: a pad a person draws a curve on by hand; set_keys gives a key any named curve or cubic-bezier
        EditorState+KeyGraph.swift › segmentCurveRows :: "Copy Ease" | leftOut: carries the curve of a stretch picked on a key graph to others picked there; set_easing names each stretch's curve
        EditorState+KeyGraph.swift › segmentCurveRows :: "Paste Ease" | leftOut: carries the curve of a stretch picked on a key graph to others picked there; set_easing names each stretch's curve
        EditorState+KeyGraph.swift › segmentMenuRows :: points.count > 1 ? "Delete \\(points.count) Points" : "Delete Point" | command: delete
        EditorState+KeyLanes.swift › graphRows :: "Show Graph" | leftOut: look
        EditorState+KeyLanes.swift › keyMenuRows :: ease.title | command: set_easing
        EditorState+KeyLanes.swift › keyMenuRows :: refs.count == 1 ? "Copy Key" : "Copy \\(refs.count) Keys" | command: copy
        EditorState+KeyLanes.swift › keyMenuRows :: refs.count == 1 ? "Delete Key" : "Delete \\(refs.count) Keys" | command: delete
        EditorState+KeyLanes.swift › pasteKeysRow :: count > 1 ? "Paste \\(count) Keys" : "Paste Keys" | command: paste
        EditorState+MeasureChip.swift › measureChipStyleMenuRows :: ChipStyle.menuTitle | notYet: how a measurement looks (role, unit, line, label)
        EditorState+MeasureChip.swift › measureChipStyleMenuRows :: style.title | notYet: how a measurement looks (role, unit, line, label)
        EditorState+MeasureChip.swift › measureChipStyleMenuRows :: ChipMarker.menuTitle | notYet: how a measurement looks (role, unit, line, label)
        EditorState+MeasureChip.swift › measureChipStyleMenuRows :: marker.title | notYet: how a measurement looks (role, unit, line, label)
        EditorState+MeasureChip.swift › measureChipStyleMenuRows :: MarkSize.menuTitle | notYet: how a measurement looks (role, unit, line, label)
        EditorState+MeasureChip.swift › measureChipStyleMenuRows :: size.name | notYet: how a measurement looks (role, unit, line, label)
        EditorState+OnlyAnimated.swift › animateMenuRow :: property.title(on: layer) | command: animate_property
        EditorState+PictureFade.swift › pictureFadeMenuRows :: end.title | command: set_fade
        EditorState+PictureFade.swift › pictureFadeMenuRows :: PictureFade.title(ms) | command: set_fade
        EditorState+RangeSection.swift › sectionRow :: title | command: section
        EditorState+RangeSection.swift › sectionRow :: operation.title | command: section
        EditorState+RangeSection.swift › sectionRow :: String(format: "-%.0f dB", Double(dB)) | command: section
        EditorState+Reframe.swift › punchInMenuRows :: "\\(percent)%" | command: punch_in
        EditorState+RulerRange.swift › rulerRangeMenuRows :: "Export Range…" | leftOut: opens the Export sheet for a person; an agent's export writes the whole video to a path as an MP4
        EditorState+SoundLine.swift › soundPointMenuRows :: inHand.count > 1 ? "Delete \\(inHand.count) Points" : "Delete Point" | command: delete
        EditorState+SoundLine.swift › soundSegmentMenuRows :: points.count > 1 ? "Delete \\(points.count) Points" : "Delete Point" | command: delete
        EditorState+TimelineGap.swift › timelineSpaceMenuRows :: layer.name | command: put_on_timeline
        EditorState+TimelineGap.swift › timelineSpaceMenuRows :: "Add Text" | leftOut: draw
        EditorState+TimelineGap.swift › timelineSpaceMenuRows :: "Add Rectangle" | leftOut: draw
        EditorState+TimelineMenus.swift › captionTrackMenuRows :: format.title + "…" | command: export_captions
        EditorState+TimelineMenus.swift › clipMenuRows :: titled(.split) | command: split_at_playhead
        EditorState+TimelineMenus.swift › clipMenuRows :: titled(.freezeFrame) | command: freeze_frame
        EditorState+TimelineMenus.swift › clipMenuRows :: ClipSpeed.title(percent) | command: set_speed
        EditorState+TimelineMenus.swift › clipMenuRows :: titled(row) | leftOut: clipRow
        EditorState+TimelineMenus.swift › clipMenuRows :: ClipMenuPlan.soundSubmenuTitle | leftOut: submenu
        EditorState+TimelineMenus.swift › clipMenuRows :: titled(.copy) | command: copy
        EditorState+TimelineMenus.swift › clipMenuRows :: titled(.cut) | command: cut
        EditorState+TimelineMenus.swift › clipMenuRows :: title | command: add_click
        EditorState+TimelineMenus.swift › clipMenuRows :: "Reveal in Finder" | leftOut: finder
        EditorState+TimelineMenus.swift › cutMenuRows :: TimelineMenuTable.title(.rollEdit, playheadMS: self.documentTimeMS) ?? "" | command: roll_edit_to_playhead
        EditorState+TimelineMenus.swift › cutMenuRows :: TimelineMenuTable.title(.expandCut, playheadMS: 0) ?? "" | command: expand_cut
        EditorState+TimelineMenus.swift › cutTransitionMenuRows :: ClipTransitionCopy.lengthChoice(ms, of: kind) | command: set_transition_length
        EditorState+TimelineMenus.swift › cutTransitionMenuRows :: curve.title | command: set_transition_curve
        EditorState+TimelineMenus.swift › soundGainMenuRows :: target.title | command: normalize_loudness
        EditorState+TimelineMenus.swift › speedStopMenuRows :: TimelinePointing.atPlayhead(SpeedStopNames.add, ms: documentTimeMS) | command: add_speed_stop
        EditorState+TimelineMenus.swift › speedStopMenuRows :: SpeedStopNames.delete | command: delete_speed_stop
        EditorState+TimelineMenus.swift › speedStopMenuRows :: SpeedStopNames.reset | command: reset_ramp
        EditorState+TimelineMenus.swift › timelineClipMenuRows :: "Reveal in Finder" | leftOut: finder
        EditorState+TimelineMenus.swift › timelineMenu :: title | leftOut: submenu
        EditorState+TitlePresets.swift › titleInsertMenuRows :: "\\(verb) \\(kind.name)" | command: insert_title
        EditorState+TitlePresets.swift › titlePresetRows :: VideoCatalogGroup.moreStyles | leftOut: shelf
        EditorState+TitleTime.swift › placedLayerFadeRows :: "Fade" | command: set_fade
        EditorState+TitleTime.swift › placedLayerFadeRows :: TitleTime.fadeTitle(ms) | command: set_fade
        EditorState+TransitionTargets.swift › transitionPickerMenuRow :: title | command: set_transition
        EditorState+Zoom.swift › zoomMenuRows :: "\\(stop)%" | command: set_zoom_amount
        LayerCommandMenu.swift › rows :: MirrorAcrossCenter.title | command: mirror_across_center
        LayerCommandMenu.swift › rows :: CenterOnArtboard.title | command: center_on_artboard
        LayerCommandMenu.swift › rows :: editorState.turnIntoPathMenuItem(id: id) | command: turn_into_path
        LayerCommandMenu.swift › rows :: PathCombine.menuItem | command: combine_shapes
        LayerCommandMenu.swift › rows :: operation.title | command: combine_shapes
        LayerCommandMenu.swift › rows :: EditorState.putTextOnPathTitle | command: put_text_on_path
        LayerCommandMenu.swift › rows :: PathCombine.unionTitle | command: union
        LayerCommandMenu.swift › rows :: OutlineStroke.title | command: outline_stroke
        LayerCommandMenu.swift › rows :: RasterizePrompt.menuItem | command: turn_into_picture
        LayerCommandMenu.swift › rows :: LayersPanelHeader.MenuRow.stackTitle | command: stack_selection
        LayerCommandMenu.swift › rows :: FlipAxis.horizontal.title | command: flip_horizontal
        LayerCommandMenu.swift › rows :: FlipAxis.vertical.title | command: flip_vertical
        LayerCommandMenu.swift › rows :: "Make \\(container) Fit" | leftOut: grows the box a layer was cut off by; set_layer sizes that box, and bring_into_view moves the layer back
        LayerCommandMenu.swift › rows :: ExactPlacement.menuItem | leftOut: opens fields for a person to type a position and size into; set_layer sets them
        LayerCommandMenu.swift › rows :: OriginalSpaceCopy.menuEdit | command: edit_original
        LayerCommandMenu.swift › rows :: editorState.selectedComponentVariantWording.addCommand | command: add_variant
        LayerCommandMenu.swift › rows :: title | command: apply_to_other_versions
        LayerCommandMenu.swift › rows :: MenuToggleNames.layerVisible | set_layer.visible
        LibraryCatalogTiles.swift › body (right-click) :: "Insert at Playhead" | notYet: putting a Library background on the timeline
        LibraryTitleTile.swift › body (right-click) :: "Insert at Playhead" | command: insert_title
        LibraryTitleTile.swift › body (right-click) :: "Delete Preset" | notYet: removing a saved title preset
        MeasurementsListView.swift › row (right-click) :: MenuToggleNames.layerVisible | set_layer.visible
        TimelineCameraRow.swift › lane :: "Show Camera Settings" | leftOut: look
        TimelineTrackRows.swift › TimelineTrackMenu :: TimelineMenuTable.title(.track, playheadMS: 0) ?? "Track" | leftOut: submenu
        TimelineTrackRows.swift › TimelineTrackMenu :: "Add Rectangle" | leftOut: draw
        TimelineTrackRows.swift › TimelineTrackMenu :: "Add Text" | leftOut: draw
        TimelineTrackRows.swift › TimelineTrackMenu :: layer.name | command: put_on_timeline
        """

    static let rowNotYetPin = 13

    // MARK: Reading the tables

    static func parse(_ table: String) -> [String: Reach] {
        var found: [String: Reach] = [:]
        for line in table.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let bar = trimmed.range(of: " | ", options: .backwards) else { continue }
            let key = String(trimmed[..<bar.lowerBound])
            let value = String(trimmed[bar.upperBound...])
            found[key] = reach(value)
        }
        return found
    }

    static func reach(_ value: String) -> Reach {
        if value.hasPrefix("command: ") {
            return .commands(value.dropFirst(9).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        }
        if value.hasPrefix("leftOut: ") {
            let why = String(value.dropFirst(9))
            return .leftOut(reasons[why] ?? why)
        }
        if value.hasPrefix("notYet: ") { return .notYet(String(value.dropFirst(8))) }
        let parts = value.split(separator: ".", maxSplits: 1).map(String.init)
        return .tool(parts.first ?? value, parts.count > 1 ? parts[1] : "")
    }

    static let panelReach = parse(panelTable)
    static let rowReach = parse(rowTable)

    /// The command whose own words a title is.
    static func command(titled words: String) -> AppCommand? {
        let words = words.replacingOccurrences(of: "\\u{2026}", with: "\u{2026}")
        return AppCommandTable.all.first { $0.titles.contains(words) || $0.titles.contains(words + "\u{2026}") }
    }

    /// A panel control: its table line, or the command its label is.
    static func reach(of control: AgentReachSource.Control) -> Reach? {
        if let reach = panelReach[control.key] { return reach }
        if let command = command(titled: control.label) { return .commands([command.name]) }
        return nil
    }

    /// Where an agent finds a tool's field: its top level properties.
    static func fields(of tool: String) -> Set<String>? {
        guard let found = AgentTools.all.first(where: { $0.name == tool }) else { return nil }
        guard case .object(let schema) = found.inputSchema, case .object(let properties)? = schema["properties"] else {
            return []
        }
        return Set(properties.keys)
    }

    static func check(_ reach: Reach, for what: String) {
        switch reach {
        case .tool(let tool, let field):
            guard let fields = fields(of: tool) else {
                Issue.record("\(what) is reached by \(tool), which is not an agent tool")
                return
            }
            #expect(fields.contains(field), "\(what) is reached by \(tool).\(field), and \(tool) has no field \(field)")
        case .commands(let names):
            for name in names {
                #expect(AppCommandID(rawValue: name) != nil, "\(what) runs \(name), which is not a command")
            }
        case .leftOut(let why), .notYet(let why):
            #expect(!why.isEmpty, "\(what) has no reason")
        }
    }

    // MARK: The panel checks

    @Test("Every panel control is reached by an agent tool or command, or says why not")
    func everyPanelControlIsPlaced() throws {
        let controls = try Self.panelControls
        #expect(controls.count > 400, "the source reader found only \(controls.count) panel controls")
        for control in controls {
            guard let reach = Self.reach(of: control) else {
                Issue.record("""
                    \(control.file):\(control.line) "\(control.label)" has no way in for an agent. Add it to \
                    panelTable with the agent tool and field that set it, the command that does it, or why not.
                    """)
                continue
            }
            Self.check(reach, for: control.key)
        }
    }

    @Test("The panel table names only controls that are still drawn")
    func panelTableIsLive() throws {
        let keys = Set(try Self.panelControls.map(\.key))
        for key in Self.panelReach.keys {
            #expect(keys.contains(key), "\(key) is no longer a panel control; take it off panelTable")
        }
    }

    @Test("The panel's not-yet list only shrinks")
    func panelNotYetOnlyShrinks() {
        let count = Self.panelReach.values.filter { if case .notYet = $0 { true } else { false } }.count
        #expect(count == Self.panelNotYetPin, """
            \(count) panel controls are not reached yet against a pin of \(Self.panelNotYetPin): give a new \
            control a way in rather than raising the pin, and lower it when one is reached
            """)
    }

    // MARK: The right-click checks

    /// A right-click row: its own command words (or a `MenuToggleNames`
    /// constant that is), the menu bar row the other test says it is, or its
    /// line in `rowTable`.
    static func reach(of row: AgentReachSource.MenuRowRef, toggles: [String: String]) -> Reach? {
        if let reach = rowReach["\(row.menu) :: \(row.title)"] { return reach }
        var words: [String] = EveryCommandIsInTheMenuBarTests.literals(in: row.title[...])
        if let constant = row.title.firstMatch(of: /^MenuToggleNames\.(\w+)$/), let title = toggles[String(constant.output.1)] {
            words = [title]
        }
        guard !words.isEmpty else { return nil }
        var names: [String] = []
        for word in words {
            let said = EveryCommandIsInTheMenuBarTests.sameCommand[word]
                ?? EveryCommandIsInTheMenuBarTests.sameCommand[word.replacingOccurrences(of: "\u{2026}", with: "\\u{2026}")]
            guard let command = command(titled: word) ?? said.flatMap({ command(titled: $0) }) else { return nil }
            names.append(command.name)
        }
        return .commands(names)
    }

    static var rightClickRows: [AgentReachSource.MenuRowRef] {
        get throws { try cached.rows() }
    }

    @Test("Every right-click menu is named")
    func everyMenuIsNamed() throws {
        let menus = Set(try Self.rightClickRows.map(\.menu))
        #expect(menus.count > 40, "the source reader found only \(menus.count) right-click menus")
        for menu in menus.sorted() where Self.menus[menu] == nil {
            Issue.record("The right-click menu built in \(menu) has no name. Name it in menus.")
        }
        for menu in Self.menus.keys where !menus.contains(menu) {
            Issue.record("\(menu) builds no right-click rows any more; take it off menus")
        }
    }

    @Test("Every right-click row is reached by a command or a tool, or says why not")
    func everyRowIsPlaced() throws {
        let toggles = try AgentReachSource.toggleNames()
        let rows = try Self.rightClickRows
        #expect(rows.count > 250, "the source reader found only \(rows.count) right-click rows")
        for row in rows {
            guard let reach = Self.reach(of: row, toggles: toggles) else {
                Issue.record("""
                    \(row.menu):\(row.line) the row \(row.title) has no way in for an agent. Title it with a \
                    command's words, or add it to rowTable.
                    """)
                continue
            }
            Self.check(reach, for: "\(row.menu) \(row.title)")
        }
        for row in TimelineMenuRow.allCases {
            if case .notYet(let why) = EveryMenuCommandHasANameTests.reach(row) {
                Issue.record("The timeline clip's \(row) is not reached yet: \(why)")
            }
        }
    }

    @Test("The row table names only rows that are still offered")
    func rowTableIsLive() throws {
        let titles = Set(try Self.rightClickRows.map { "\($0.menu) :: \($0.title)" })
        for key in Self.rowReach.keys {
            #expect(titles.contains(key), "\(key) is no longer a right-click row; take it off rowTable")
        }
    }

    @Test("The right-click not-yet list only shrinks")
    func rowNotYetOnlyShrinks() {
        let count = Self.rowReach.values.filter { if case .notYet = $0 { true } else { false } }.count
        #expect(count == Self.rowNotYetPin, """
            \(count) right-click rows are not reached yet against a pin of \(Self.rowNotYetPin): give a new \
            row a way in rather than raising the pin, and lower it when one is reached
            """)
    }

    // MARK: The count

    struct Tally {
        var named = 0, leftOut = 0, notYet = 0, missing = 0
        var total: Int { named + leftOut + notYet + missing }
        mutating func add(_ reach: Reach?) {
            switch reach {
            case .tool?, .commands?: named += 1
            case .leftOut?: leftOut += 1
            case .notYet?: notYet += 1
            case nil: missing += 1
            }
        }
        static func + (a: Tally, b: Tally) -> Tally {
            Tally(named: a.named + b.named, leftOut: a.leftOut + b.leftOut,
                  notYet: a.notYet + b.notYet, missing: a.missing + b.missing)
        }
        var line: String { "\(total): named \(named), left out \(leftOut), not yet \(notYet), missing \(missing)" }
    }

    /// The panel by the file that draws each section, every right-click menu
    /// by its name, and the totals the audit and `docs/design/agent-mcp.md`
    /// report. A control drawn twice under the same words counts once.
    static func tallies() throws -> (panel: [String: Tally], menus: [String: Tally]) {
        var panel: [String: Tally] = [:]
        var seen = Set<String>()
        for control in try panelControls where seen.insert(control.key).inserted {
            panel[control.file, default: Tally()].add(reach(of: control))
        }
        var menus: [String: Tally] = [:]
        let toggles = try AgentReachSource.toggleNames()
        var seenRows = Set<String>()
        for row in try rightClickRows where seenRows.insert("\(row.menu) :: \(row.title)").inserted {
            menus[Self.menus[row.menu] ?? row.menu, default: Tally()].add(reach(of: row, toggles: toggles))
        }
        for row in TimelineMenuRow.allCases {
            let reach: Reach? = switch EveryMenuCommandHasANameTests.reach(row) {
            case .command(let id): .commands([id.rawValue])
            case .holds: nil
            case .leftOut(let why): .leftOut(why)
            case .notYet(let why): .notYet(why)
            }
            if case .holds = EveryMenuCommandHasANameTests.reach(row) { continue }
            menus["A clip on the timeline (its rows by name)", default: Tally()].add(reach)
        }
        return (panel, menus)
    }

    /// The files whose sections only a document with time shows: a clip's
    /// time, sound and transitions, a track, a zoom, captions and titles.
    static let videoOnlyFiles: Set<String> = [
        "SpeedInspector.swift", "SoundInspector.swift", "SoundEffectsInspector.swift", "CaptionsInspector.swift",
        "CaptionStyleInspector.swift", "TransitionInspector.swift", "TransitionsGroup.swift", "ZoomInspector.swift",
        "TrackInspector.swift", "ClickEffectRows.swift", "TitleRestyleInspector.swift", "TitleBackgroundPicker.swift",
        "LibraryTitleTile.swift", "LibraryCatalogTiles.swift",
    ]

    @Test("The count the audit reports")
    func count() throws {
        let (panel, menus) = try Self.tallies()
        let panelTotal = panel.values.reduce(Tally(), +)
        let menuTotal = menus.values.reduce(Tally(), +)
        let video = panel.filter { Self.videoOnlyFiles.contains($0.key) }.values.reduce(Tally(), +)
        let picture = panel.filter { !Self.videoOnlyFiles.contains($0.key) }.values.reduce(Tally(), +)
        var report = "Panel controls \(panelTotal.line)\n"
        report += "  in sections a picture shows too \(picture.line)\n"
        report += "  in sections only a video shows \(video.line)\n"
        for (file, tally) in panel.sorted(by: { $0.key < $1.key }) { report += "  \(file) \(tally.line)\n" }
        report += "Right-click rows, \(menus.count) menus, \(menuTotal.line)\n"
        for (menu, tally) in menus.sorted(by: { $0.key < $1.key }) { report += "  \(menu) \(tally.line)\n" }
        print(report)
        #expect(panelTotal.missing == 0 && menuTotal.missing == 0)
    }

    static var panelControls: [AgentReachSource.Control] {
        get throws { try cached.controls() }
    }

    /// The source is read once per run, however many tests ask.
    final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var controlsRead: [AgentReachSource.Control]?
        private var rowsRead: [AgentReachSource.MenuRowRef]?

        func controls() throws -> [AgentReachSource.Control] {
            lock.lock(); defer { lock.unlock() }
            if let controlsRead { return controlsRead }
            let read = try AgentReachSource.panelControls()
            controlsRead = read
            return read
        }

        func rows() throws -> [AgentReachSource.MenuRowRef] {
            lock.lock(); defer { lock.unlock() }
            if let rowsRead { return rowsRead }
            let read = try AgentReachSource.rightClickRows()
            rowsRead = read
            return read
        }
    }

    static let cached = Cache()
}
