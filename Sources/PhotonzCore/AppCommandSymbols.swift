/// The icon each command wears in Ask's `/` list (`agent-generate-wt.html`,
/// the mock's `ASK_CMDS`: one icon per row, never one per area). Names are SF
/// Symbols, kept here as plain words so the table stays pure; the app draws
/// them. The switch is exhaustive, so a new command cannot land without one.
///
/// Two commands share an icon only when they share their words (the two Clean
/// Noise rows); `AppCommandSymbolTests` holds that.
extension AppCommandID {

    public var symbol: String {
        switch self {
        // Sequence: playing
        case .playPause: "play.fill"
        case .playInToOut: "play.rectangle"
        case .playBackward: "backward.fill"
        case .stop: "stop.fill"
        case .playForward: "forward.fill"
        case .goToPreviousEdit: "backward.end.fill"
        case .goToNextEdit: "forward.end.fill"
        // Sequence: marks and markers
        case .addMarker: "bookmark"
        case .setIn: "chevron.left.to.line"
        case .setOut: "chevron.right.to.line"
        case .markClip: "rectangle.dashed"
        case .goToIn: "arrow.left.to.line"
        case .goToOut: "arrow.right.to.line"
        case .clearIn: "delete.left"
        case .clearOut: "delete.right"
        case .clearInAndOut: "xmark.rectangle"
        case .goToNextMarker: "arrowshape.right"
        case .goToPreviousMarker: "arrowshape.left"
        case .removeMarker: "bookmark.slash"
        case .clearAllMarkers: "bookmark.slash.fill"
        // Sequence: what a range does
        case .extract: "rectangle.compress.vertical"
        case .lift: "rectangle.badge.minus"
        case .splitAtRangeEdges: "rectangle.split.3x1"
        case .mergeIntoOneClip: "arrow.triangle.merge"
        case .addCaptionsForRange: "captions.bubble"
        case .splitEverythingAtPlayhead: "scissors.badge.ellipsis"
        case .snapInTimeline: "arrow.right.and.line.vertical.and.arrow.left"
        case .preview: "eye"
        // Sequence > Track
        case .addVideoTrack: "video.badge.plus"
        case .addAudioTrack: "waveform.badge.plus"
        case .addCaptionsTrack: "text.badge.plus"
        case .addTrackAbove: "arrow.up.square"
        case .addTrackBelow: "arrow.down.square"
        case .muteTrack: "speaker.slash"
        case .hideTrack: "eye.slash"
        case .soloTrack: "s.circle"
        case .muteSound: "speaker.slash.circle"
        case .soloSound: "s.square"
        case .deleteSound: "waveform.slash"
        case .lockTrack: "lock"
        case .groupTrack: "rectangle.stack"
        case .ungroupTracks: "rectangle.stack.badge.minus"
        case .deleteTrack: "minus.rectangle"
        case .deleteEmptyTracks: "rectangle.badge.xmark"
        // Sequence: captions, and the recording itself
        case .addCaptions: "captions.bubble.fill"
        case .cancelCaptions: "xmark.circle"
        case .captionsLater: "forward"
        case .captionsEarlier: "backward"
        case .clearCaptions: "text.badge.xmark"
        case .resetCaptions: "arrow.counterclockwise"
        case .revertToOriginal: "clock.arrow.circlepath"
        case .exportCaptions: "square.and.arrow.up"
        case .renameTrack: "pencil.line"
        case .section: "rectangle.center.inset.filled"
        // Sequence > Caption Word
        case .editCaptionWord: "character.cursor.ibeam"
        case .splitCaptionWord: "text.word.spacing"
        case .mergeCaptionWord: "link"
        case .deleteCaptionWord: "delete.backward"
        case .moveWordToPreviousLine: "arrow.turn.left.up"
        case .moveWordToNextLine: "arrow.turn.right.down"
        case .joinWithNextLine: "text.append"
        case .playFromWord: "play.circle"
        case .goToCaptionStart: "text.cursor"
        // Clip: cutting
        case .splitAtPlayhead: "scissors.circle"
        case .delete: "trash"
        case .rippleDelete: "delete.left.fill"
        case .rippleTrimStart: "arrow.right.to.line.compact"
        case .rippleTrimEnd: "arrow.left.to.line.compact"
        case .nudgeEarlier: "chevron.left"
        case .nudgeLater: "chevron.right"
        case .breakApart: "square.split.2x1"
        // Clip: the clip itself
        case .selectForward: "arrow.forward.circle"
        case .hideClickAtPlayhead: "cursorarrow.slash"
        case .nextClick: "cursorarrow.click"
        case .showClickEffects: "cursorarrow.rays"
        case .addZoom: "plus.viewfinder"
        case .suggestZooms: "sparkle.magnifyingglass"
        case .renameClip: "pencil"
        case .addClick: "cursorarrow.click.badge.clock"
        case .followCursor: "cursorarrow.motionlines"
        case .setZoomAmount: "magnifyingglass"
        case .deleteZoom: "viewfinder.circle"
        case .addMediaAtPlayhead: "photo.badge.plus"
        case .insertTitle: "textformat"
        case .saveTitlePreset: "rectangle.stack.badge.plus"
        case .exportSound: "square.and.arrow.up.on.square"
        // Clip: time
        case .freezeFrame: "snowflake"
        case .showPicture: "photo"
        case .setSpeed: "speedometer"
        case .addSpeedStop: "plus.circle"
        case .deleteSpeedStop: "minus.circle"
        case .resetRamp: "arrow.uturn.backward"
        case .punchIn: "arrow.up.left.and.arrow.down.right"
        case .pullBackOut: "arrow.down.right.and.arrow.up.left"
        case .resetReframe: "crop"
        case .setFade: "circle.lefthalf.filled"
        case .fadeInAndOut: "circle.dotted"
        // Clip > Transition at Cut
        case .setTransition: "rectangle.on.rectangle"
        case .hardCut: "line.diagonal"
        case .resetTransitionLength: "arrow.counterclockwise.circle"
        case .setTransitionLength: "arrow.left.and.right.square"
        case .setTransitionCurve: "point.topleft.down.curvedto.point.bottomright.up"
        case .applyTransitionToEveryCut: "rectangle.3.group"
        case .setDefaultTransition: "star"
        case .applyDefaultTransition: "star.fill"
        case .expandCut: "arrow.left.and.right.circle"
        case .rollEditToPlayhead: "arrow.left.arrow.right"
        case .joinThroughEdit: "bandage"
        // Clip: sound
        case .detachAudio: "waveform.path.badge.minus"
        case .reattachAudio: "waveform.path.badge.plus"
        case .flattenLevel: "chart.line.flattrend.xyaxis"
        case .normalizePeaks: "waveform"
        case .normalizeLoudness: "speaker.wave.3"
        // Both Clean Noise rows wear the same words, so the same icon.
        case .normalizeCleansNoise, .cleanNoise: "wand.and.stars"
        case .resetGain: "slider.vertical.3"
        case .replayTitle: "arrow.clockwise.circle"
        // Clip > Animate
        case .startAtPlayhead: "flag"
        case .endAtPlayhead: "flag.checkered"
        case .animateIn: "arrow.down.forward.circle"
        case .animateOut: "arrow.up.forward.circle"
        case .goToNextKey: "diamond.righthalf.filled"
        case .goToPreviousKey: "diamond.lefthalf.filled"
        case .keyAtPlayhead: "diamond"
        case .curveThePath: "scribble"
        case .removeKeyAtPlayhead: "minus.diamond"
        case .selectAllKeys: "diamond.circle"
        case .setEasing: "chart.line.uptrend.xyaxis"
        case .straightenStretch: "line.diagonal.arrow"
        case .animateProperty: "timeline.selection"
        case .stopAnimating: "pause.circle"
        // File
        case .save: "square.and.arrow.down"
        case .importMedia: "square.and.arrow.down.on.square"
        case .previewWebPage: "safari"
        // Image
        case .resizeImage: "arrow.up.backward.and.arrow.down.forward"
        case .canvasSize: "square.dashed"
        // Edit
        case .cut: "scissors"
        case .copy: "doc.on.doc"
        case .copyMerged: "square.on.square"
        case .copyMergedWithBackground: "square.fill.on.square.fill"
        case .copySVG: "chevron.left.forwardslash.chevron.right"
        case .copyVideo: "film"
        case .copyAsGIF: "photo.stack"
        case .paste: "doc.on.clipboard"
        case .selectAll: "square.dashed.inset.filled"
        case .deselect: "square.slash"
        case .invertSelection: "square.lefthalf.filled"
        case .fillWithForeground: "drop.fill"
        case .fillWithBackground: "drop"
        case .swapFillColors: "arrow.left.arrow.right.circle"
        case .flipHorizontal: "arrow.left.and.right.righttriangle.left.righttriangle.right"
        case .flipVertical: "arrow.up.and.down.righttriangle.up.righttriangle.down"
        case .skew: "skew"
        case .distort: "perspective"
        case .keystone: "trapezoid.and.line.vertical"
        case .turnIn3D: "rotate.3d"
        case .resetSize: "aspectratio"
        case .resetSkewAndDistort: "arrow.uturn.backward.square"
        case .reset3D: "cube.transparent"
        case .resetAllTransforms: "arrow.counterclockwise.square"
        // Layer
        case .newLayer: "plus.square"
        case .newLayerViaCopy: "plus.square.fill.on.square.fill"
        case .newLayerViaCut: "square.on.square.dashed"
        case .blurBehindSelection: "drop.halffull"
        case .duplicateLayer: "plus.rectangle.on.rectangle"
        case .mirrorAcrossCenter: "square.and.line.vertical.and.square"
        case .centerOnArtboard: "scope"
        case .selectPixels: "checkerboard.rectangle"
        case .putOnTimeline: "film.stack"
        case .copyLook: "eyedropper"
        case .pasteLook: "eyedropper.full"
        case .mergeDown: "square.stack.3d.down.right"
        case .combineShapes: "square.on.circle"
        case .union: "circle.circle"
        case .outlineStroke: "circle.dashed"
        case .separateIntoLayers: "square.3.layers.3d"
        case .turnIntoText: "character.textbox"
        case .arrangeInCollage: "rectangle.3.group.fill"
        case .newCollageLayer: "square.grid.2x2"
        case .group: "folder"
        case .ungroup: "folder.badge.minus"
        case .stackSelection: "square.stack"
        case .gridSelection: "square.grid.3x3"
        case .frameSelection: "rectangle.inset.filled"
        case .makeComponent: "puzzlepiece"
        case .makeUnique: "puzzlepiece.extension"
        case .align: "align.horizontal.left"
        case .spaceEvenly: "distribute.horizontal"
        case .bringToFront: "square.3.layers.3d.top.filled"
        case .bringForward: "square.2.layers.3d.top.filled"
        case .sendBackward: "square.2.layers.3d.bottom.filled"
        case .sendToBack: "square.3.layers.3d.bottom.filled"
        case .deleteLayer: "trash.square"
        case .renameLayer: "character.cursor.ibeam.ar"
        case .lockLayer: "lock.square"
        case .showColumns: "rectangle.split.3x1.fill"
        case .addEffect: "sparkles"
        case .addSavedEffect: "sparkles.rectangle.stack"
        case .removeEffect: "minus.square"
        case .setArrowStyle: "arrow.up.right"
        case .reshuffleArrows: "shuffle"
        case .straightenArrows: "arrow.right"
        case .turnIntoPath: "point.bottomleft.forward.to.point.topright.scurvepath"
        case .putTextOnPath: "textformat.characters"
        case .turnIntoPicture: "photo.artframe"
        case .bringIntoView: "viewfinder"
        case .fillTheStack: "rectangle.expand.vertical"
        case .surfaceBehind: "square.stack.3d.up"
        case .inFrontOfTheRest: "square.stack.3d.up.fill"
        case .newFrame: "rectangle.portrait"
        case .addVariant: "plus.square.dashed"
        case .applyToOtherVersions: "square.on.square.squareshape.controlhandles"
        case .makeAlternatives: "square.grid.2x2.fill"
        case .editOriginal: "pencil.circle"
        case .doneEditingOriginal: "checkmark.circle"
        case .reset3DRotation: "rotate.3d.fill"
        case .bringNearer: "arrow.up.left.and.down.right.magnifyingglass"
        case .sendFurther: "arrow.down.forward.and.arrow.up.backward"
        // Measure
        case .showAllMeasurements: "ruler"
        case .hideAllMeasurements: "ruler.fill"
        case .clearMeasurements: "xmark.bin"
        case .copySpecList: "list.bullet.rectangle"
        case .copyMeasurements: "doc.on.clipboard.fill"
        // View
        case .zoomIn: "plus.magnifyingglass"
        case .zoomOut: "minus.magnifyingglass"
        case .zoomToFit: "arrow.up.left.and.arrow.down.right.square"
        case .actualSize: "1.magnifyingglass"
        case .zoomTimelineToFit: "arrow.left.and.right.text.vertical"
        case .compactTracks: "arrow.down.and.line.horizontal.and.arrow.up"
        case .captionSafeAreas: "rectangle.inset.topleft.filled"
        case .resetCamera: "camera.rotate"
        }
    }
}

extension AskCommandEntry {

    /// The icon this row wears: its command's, or, for a row that is one
    /// choice of a command (Align Left, Space Evenly Down), that choice's own when it
    /// has a clearer one.
    public var symbol: String {
        Self.choiceSymbols[call.id]?[choice ?? ""] ?? call.id.symbol
    }

    /// The word this row was made for, when its command takes a choice.
    private var choice: String? {
        call.options.values.lazy.compactMap(\.stringValue).first
    }

    private static let choiceSymbols: [AppCommandID: [String: String]] = [
        .align: [
            LayerAlignment.left.rawValue: "align.horizontal.left",
            LayerAlignment.horizontalCenter.rawValue: "align.horizontal.center",
            LayerAlignment.right.rawValue: "align.horizontal.right",
            LayerAlignment.top.rawValue: "align.vertical.top",
            LayerAlignment.verticalCenter.rawValue: "align.vertical.center",
            LayerAlignment.bottom.rawValue: "align.vertical.bottom"
        ],
        .spaceEvenly: [
            LayerDistribution.horizontal.rawValue: "distribute.horizontal",
            LayerDistribution.vertical.rawValue: "distribute.vertical"
        ]
    ]
}
