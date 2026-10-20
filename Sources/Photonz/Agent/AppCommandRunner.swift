import Foundation
import PhotonzCore

/// **What each named command does** (`AppCommandTable`), on whatever is in
/// hand: the one switch the menu bar's rows, the right-click rows and an
/// agent's `run_command` all go through.
///
/// Every case asks the question its menu row's dimming asked and calls the
/// function its menu row called, moved here so the two can never disagree. The
/// switch is exhaustive over `AppCommandID`, so a command added to the table
/// does not build until it does something.
extension EditorState {

    // MARK: Running

    /// Runs a command on what is in hand, the way its menu row does.
    func run(_ id: AppCommandID, _ options: [String: AgentJSON] = [:]) {
        run(AppCommandCall(id, options: options))
    }

    /// Whether a command can run now on what is in hand: what its menu row's
    /// dimming says.
    func canRun(_ id: AppCommandID, _ options: [String: AgentJSON] = [:]) -> Bool {
        canRun(AppCommandCall(id, options: options))
    }

    /// A toggle's state now, or nil for a command that is not one.
    func isOn(_ id: AppCommandID) -> Bool? {
        switch id {
        case .snapInTimeline: isTimelineSnapping
        case .muteTrack: trackInHand?.isMuted ?? false
        case .hideTrack: trackInHand?.isHidden ?? false
        case .soloTrack: trackInHand?.isSolo ?? false
        case .lockTrack: trackInHand?.isLocked ?? false
        case .showClickEffects: clickEffectClip.map { clickEffect(ofClip: $0.id).isOn } ?? false
        case .expandCut: isCutInHandExpanded
        case .fadeInAndOut: fadesInAndOut(pictureFadeTargetsInHand)
        case .normalizeCleansNoise: normalizeCleansNoise
        case .cleanNoise: soundInHandIsCleaned
        case .curveThePath: motionPathShape == .curved
        case .captionSafeAreas: Self.showsSafeAreas
        case .followCursor: !pickedZooms.isEmpty && pickedZoomsReading.followsCursor == true
        case .fillTheStack: flowFillCommand.isOn
        case .surfaceBehind: surfaceCommand.isOn
        case .inFrontOfTheRest: surfaceCommand.isFloating
        case .lockLayer: selectedLayerID.flatMap { document?.layer(id: $0)?.isLocked } ?? false
        case .showColumns: isShowingFrameColumns
        default: nil
        }
    }

    /// Runs `call` and waits for the work it starts in the background (a file
    /// read in or written out, a sound measured, a video copied) before
    /// returning, so an agent's answer comes after the change has landed.
    func runAwaiting(_ call: AppCommandCall) async {
        if let wanted = call.on, let now = isOn(call.id), wanted == now { return }
        let path = call.word("path").map { URL(fileURLWithPath: $0) }
        switch call.id {
        case .importMedia where path != nil:
            if let path { await importMedia([path]) }
        case .addMediaAtPlayhead where path != nil:
            if let path { await addMedia(from: path) }
        case .exportSound where path != nil:
            if let path { await writeMix(to: path) }
        case .normalizePeaks:
            await normalizeSound(layers: soundIDsInHand)
        case .normalizeLoudness:
            if let target = call.word("target").flatMap(AudioNormalize.Target.init(rawValue:)) {
                await normalizeSoundLoudness(layers: soundIDsInHand, to: target)
            }
        case .section where call.word("operation") == SectionOperation.normalizeSection.rawValue:
            await normalizeRangeSection()
        case .copyVideo, .copyAsGIF:
            run(call)
            await videoExportTask?.value
        default:
            run(call)
        }
    }

    /// Runs `call` on what is in hand. A toggle told `on` that is already so
    /// does nothing.
    func run(_ call: AppCommandCall) {
        if let wanted = call.on, let now = isOn(call.id), wanted == now { return }
        switch call.id {
        // Sequence: playing
        case .playPause: toggleDocumentPlayback()
        case .playInToOut: playInToOut()
        case .playBackward: shuttle(.reverse)
        case .stop: shuttle(.stop)
        case .playForward: shuttle(.forward)
        case .goToPreviousEdit: goToEditPoint(forward: false)
        case .goToNextEdit: goToEditPoint(forward: true)
        // Sequence: marks and markers
        case .addMarker: addMarker(atMS: documentTimeMS)
        case .setIn: setMarkIn(atMS: documentTimeMS)
        case .setOut: setMarkOut(atMS: documentTimeMS)
        case .markClip: markClipAtPlayhead()
        case .goToIn: goToMark(in: true)
        case .goToOut: goToMark(in: false)
        case .clearIn: clearMarkIn()
        case .clearOut: clearMarkOut()
        case .clearInAndOut: clearMarkInOut()
        case .goToNextMarker: goToMarker(forward: true)
        case .goToPreviousMarker: goToMarker(forward: false)
        case .removeMarker: if let marker = markerAtPlayhead { removeMarker(marker) }
        case .clearAllMarkers: removeAllMarkers()
        // Sequence: ranges
        case .extract: extractMarkedStretch()
        case .lift: liftMarkedStretch()
        case .splitAtRangeEdges: if trackRangeHeld != nil { splitTrackRangeEdges() } else { splitAtRangeEdges() }
        case .mergeIntoOneClip: mergeRangeIntoOneClip()
        case .addCaptionsForRange: addCaptionsInRange()
        case .splitEverythingAtPlayhead: splitEverything(atMS: documentTimeMS)
        case .snapInTimeline: toggleTimelineSnapping()
        // Sequence > Track
        case .addVideoTrack: addTrack(.video)
        case .addAudioTrack: addTrack(.audio)
        case .addCaptionsTrack: addTrack(.captions)
        case .addTrackAbove: if let track = trackInHand, let index = trackInHandIndex { addTrack(track.kind, at: index) }
        case .addTrackBelow:
            if let track = trackInHand, let index = trackInHandIndex { addTrack(track.kind, at: index + 1) }
        case .muteTrack: if let track = trackInHand { toggleTrackMuted(track.id) }
        case .hideTrack: if let track = trackInHand { toggleTrackHidden(track.id) }
        case .soloTrack: if let track = trackInHand { toggleTrackSolo(track.id) }
        case .lockTrack: if let track = trackInHand { toggleTrackLocked(track.id) }
        case .groupTrack: if let track = trackInHand { groupTracks(from: track.id) }
        case .ungroupTracks: if let group = trackInHand?.groupID { ungroupTracks(group) }
        case .deleteTrack:
            if !tracksInHand.isEmpty { deleteTracksInHand() } else if let track = trackInHand { deleteTrack(track.id) }
        case .deleteEmptyTracks: deleteEmptyTracks()
        // Sequence: captions, and the recording
        case .addCaptions: writeCaptions()
        case .cancelCaptions: stopWritingCaptions()
        case .captionsLater: nudgeCaptions(byMS: Self.captionNudgeMS)
        case .captionsEarlier: nudgeCaptions(byMS: -Self.captionNudgeMS)
        case .clearCaptions: clearCaptions()
        case .resetCaptions: resetCaptions()
        case .revertToOriginal: revertToOriginal()
        case .exportCaptions:
            let format = call.word("format").flatMap(CaptionFileFormat.init(rawValue:)) ?? .srt
            if let path = call.word("path") { writeCaptionsFile(as: format, to: URL(fileURLWithPath: path)) }
            else { exportCaptions(as: format) }
        case .renameTrack:
            if let name = call.word("name"), let id = trackInHandID { renameTrack(id, to: name) }
            else { renameTrackInHand() }
        case .section: if let operation = call.word("operation").flatMap(SectionOperation.init(rawValue:)) {
            doSection(operation, db: call.integer("db"), percent: call.integer("percent"))
        }
        // Sequence > Caption Word
        case .editCaptionWord:
            if let word = captionWordInHand {
                if let text = call.word("text") { setCaptionWord(word, to: text) }
                else { beginEditingCaptionWord(word, place: .canvas) }
            }
        case .splitCaptionWord: if let word = captionWordInHand { splitCaptionWord(word, atMS: documentTimeMS) }
        case .mergeCaptionWord: if let word = captionWordInHand { mergeCaptionWordWithNext(word) }
        case .deleteCaptionWord: if let word = captionWordInHand { deleteCaptionWord(word) }
        case .moveWordToPreviousLine: if let word = captionWordInHand { moveCaptionWordToPreviousLine(word) }
        case .moveWordToNextLine: if let word = captionWordInHand { moveCaptionWordToNextLine(word) }
        case .joinWithNextLine: if let word = captionWordInHand { joinCaptionWithNextLine(word.cueID) }
        case .playFromWord: if let word = captionWordInHand { playFromCaptionWord(word) }
        case .goToCaptionStart: goToStartOfCaptionInHand()
        // Clip: cutting
        case .splitAtPlayhead: splitClipAtPlayhead()
        case .delete: deleteWhatIsInHand()
        case .rippleDelete: rippleDeleteInHand()
        case .rippleTrimStart: rippleTrimToPlayhead(.start)
        case .rippleTrimEnd: rippleTrimToPlayhead(.end)
        case .nudgeEarlier: nudgeClips(byFrames: -1)
        case .nudgeLater: nudgeClips(byFrames: 1)
        case .breakApart: breakApartInHand()
        // Clip: the clip itself
        case .selectForward: if let clip = clipInHandID { selectClipsForward(from: clip, onItsTrackOnly: false) }
        case .hideClickAtPlayhead:
            if let click = clickAtPlayhead {
                setClickHidden(!click.mark.isHidden, clickID: click.mark.id, onClip: click.clip)
            }
        case .nextClick: if let next = nextClickMS { moveDocumentPlayhead(toMS: next) }
        case .showClickEffects:
            if let clip = clickEffectClip?.id { setClickEffectOn(!clickEffect(ofClip: clip).isOn, onClip: clip) }
        case .addZoom: if let clip = clipToAddZoom(atMS: documentTimeMS) { addZoom(toClip: clip, atMS: documentTimeMS) }
        case .suggestZooms: if let clip = clipToSuggestZooms { suggestZooms(onClip: clip) }
        case .renameClip:
            if let clip = clipInHandID {
                if let name = call.word("name") { renameClip(clip, to: name) } else { beginRenamingClip(clip) }
            }
        case .addClick:
            if let clip = clipToAddClickTo {
                if let x = call.amount("x"), let y = call.amount("y") {
                    addClick(toClip: clip, at: CGPoint(x: x, y: y))
                } else {
                    beginPlacingClick(onClip: clip)
                }
            }
        case .followCursor: setZoomFollowsCursor(pickedZooms, !(isOn(.followCursor) ?? false))
        case .setZoomAmount: if let percent = call.integer("percent") { setZoomScale(pickedZooms, percent: percent) }
        case .deleteZoom: removeZoomInHand()
        case .addMediaAtPlayhead:
            if let path = call.word("path") { Task { await addMedia(from: URL(fileURLWithPath: path)) } }
            else { addMediaFromFile() }
        case .insertTitle:
            if let preset = titlePreset(call) { insertTitle(preset, onTrack: call.track.flatMap(UUID.init(uuidString:))) }
        case .saveTitlePreset:
            if let name = call.word("name") { saveTitlePresetInHand(named: name) } else { beginSavingTitlePreset() }
        case .exportSound:
            if let path = call.word("path") { Task { await writeMix(to: URL(fileURLWithPath: path)) } }
            else { exportSound() }
        // Clip: time
        case .freezeFrame:
            if let ms = call.integer("milliseconds") { freezeFrameInHand(ms: ms, everyTrack: call.flag("everyTrack")) }
            else { openFreezeFrame() }
        case .showPicture:
            if let hidden = hiddenPictureInHand { showPicture(layerID: hidden.layerID, piece: hidden.piece) }
        case .setSpeed: if let percent = call.integer("percent") { setClipSpeedInHand(percent) }
        case .addSpeedStop: addSpeedStopInHand()
        case .deleteSpeedStop: deleteSpeedStopInHand()
        case .resetRamp: resetRampInHand()
        case .punchIn: punchInOnRegion()
        case .pullBackOut: pullReframeBackOut()
        case .resetReframe: resetReframeInHand()
        case .setFade:
            if let end = call.word("end").flatMap(FadeEnd.init(rawValue:)), let ms = call.integer("milliseconds") {
                choosePictureFadeInHand(end, ms: ms)
            }
        case .fadeInAndOut: fadeInAndOut(pictureFadeTargetsInHand)
        // Clip > Transition at Cut
        case .setTransition:
            if let kind = call.word("kind").flatMap(ClipTransitionKind.init(rawValue:)) { setClipTransitionInHand(kind) }
        case .hardCut: setClipTransitionInHand(nil)
        case .resetTransitionLength: resetClipTransitionLength()
        case .setTransitionLength: if let ms = call.integer("milliseconds") { setClipTransitionLength(ms) }
        case .setTransitionCurve: if let curve = transitionCurve(named: call.word("curve")) { setClipTransitionCurve(curve) }
        case .applyTransitionToEveryCut: putTransitionOnEveryCut(transitionKindInHand)
        case .setDefaultTransition: setDefaultTransition(transitionKindInHand)
        case .applyDefaultTransition: applyDefaultTransition()
        case .expandCut: toggleExpandedCut()
        case .rollEditToPlayhead: rollCutInHand()
        case .joinThroughEdit: joinThroughEditInHand()
        // Clip: sound
        case .detachAudio: detachSound()
        case .reattachAudio: reattachSound()
        case .flattenLevel: clearSoundLevelPoints()
        case .normalizePeaks:
            let ids = soundIDsInHand
            Task { await normalizeSound(layers: ids) }
        case .normalizeLoudness:
            let ids = soundIDsInHand
            if let target = call.word("target").flatMap(AudioNormalize.Target.init(rawValue:)) {
                Task { await normalizeSoundLoudness(layers: ids, to: target) }
            }
        case .normalizeCleansNoise: normalizeCleansNoise.toggle()
        case .cleanNoise:
            let ids = soundIDsInHand
            if soundInHandIsCleaned { removeNoiseCleaning(layers: ids) }
            else { setSoundNoiseReduction(.standard, layers: ids) }
        case .resetGain: setSoundClipGain(Dictionary(uniqueKeysWithValues: soundIDsInHand.map { ($0, 0.0) }))
        case .replayTitle: replayTitle()
        // Clip > Animate
        case .startAtPlayhead: if let placed = placedLayerInHand { startPlacedLayerHere(placed.id) }
        case .endAtPlayhead: if let placed = placedLayerInHand { endPlacedLayerHere(placed.id) }
        case .animateIn, .animateOut:
            if let placed = placedLayerInHand, let kind = call.word("kind").flatMap(TitleAnimation.init(rawValue:)) {
                animate(kind, isIn: call.id == .animateIn, layerID: placed.id)
            }
        case .goToNextKey: goToKey(forward: true)
        case .goToPreviousKey: goToKey(forward: false)
        case .keyAtPlayhead: keyAtPlayhead()
        case .curveThePath: setMotionPathShape(motionPathShape == .curved ? .straight : .curved)
        case .removeKeyAtPlayhead: removeKeyAtPlayhead()
        case .selectAllKeys: selectAllKeysInHand()
        case .setEasing: if let curve = easingCurve(named: call.word("curve")) { curveBetweenKeys(curve) }
        case .straightenStretch: straightenStretchInHand()
        case .animateProperty:
            if let layer = layerToAnimate, let property = propertyToAnimate(named: call.word("property")) {
                animate(property, layerID: layer.id)
            }
        case .stopAnimating: if let property = propertyAnimating(named: call.word("property")) { toggleKeying(property) }
        // File
        case .save: performSave { _ in }
        case .importMedia:
            if let path = call.word("path") { Task { await importMedia([URL(fileURLWithPath: path)]) } }
            else { importMediaFromPanel() }
        // Image
        case .resizeImage:
            if let width = call.amount("width"), let height = call.amount("height") {
                resizeDocument(to: CGSize(width: width.rounded(), height: height.rounded()))
            } else {
                isResizeDialogPresented = true
            }
        case .canvasSize:
            if let width = call.amount("width"), let height = call.amount("height") {
                setCanvasSize(to: CGSize(width: width.rounded(), height: height.rounded()),
                              anchor: call.word("anchor").flatMap(CanvasAnchor.init(rawValue:)) ?? .center)
            } else {
                isCanvasSizeDialogPresented = true
            }
        // Edit
        case .cut: cutWhatIsInHand()
        case .copy: copyWhatIsInHand()
        case .copyMerged: copyMerged()
        case .copySVG: copySVG(around: pickedLayerID)
        case .copyVideo: copyVideo(as: .mp4)
        case .copyAsGIF: copyVideo(as: .gif)
        case .paste:
            if let track = call.track.flatMap(UUID.init(uuidString:)), call.layers.isEmpty { paste(onTrack: track) }
            else { pasteWhatIsOnTheClipboard() }
        case .selectAll: selectAll()
        case .deselect: deselect()
        case .invertSelection: invertSelection()
        case .fillWithForeground: fillSelectedLayer(useBackground: false)
        case .fillWithBackground: fillSelectedLayer(useBackground: true)
        case .swapFillColors: swapFillColors()
        // Layer
        case .newLayer: newEmptyLayer()
        case .newLayerViaCopy: newLayerViaCopy()
        case .newLayerViaCut: newLayerViaCut()
        case .blurBehindSelection: blurBehindSelection()
        case .duplicateLayer: duplicateSelectedLayers()
        case .mirrorAcrossCenter: mirrorSelectionAcrossCenter()
        case .centerOnArtboard: centerSelectionOnArtboard()
        case .selectPixels: if let id = selectedLayerID { selectLayerPixels(id: id) }
        case .putOnTimeline: if let id = selectedLayerID { putLayerOnTimeline(id) }
        case .copyLook: copyLook()
        case .pasteLook: pasteLook()
        case .mergeDown: mergeDown()
        case .combineShapes:
            if let operation = call.word("operation").flatMap(PathCombine.Operation.init(rawValue:)) {
                combineSelection(operation)
            }
        case .union: unionSelection()
        case .outlineStroke: outlineSelectionStroke()
        case .separateIntoLayers: if let id = selectedLayerID { separateIntoLayers(id: id) }
        case .turnIntoText: turnIntoTextForSelection()
        case .arrangeInCollage: arrangeSelectionAsCollage()
        case .newCollageLayer: newEmptyCollageLayer()
        case .group: groupSelection()
        case .ungroup: ungroupSelection()
        case .stackSelection: stackSelection(.stack)
        case .gridSelection: stackSelection(.grid)
        case .frameSelection: frameSelection()
        case .makeComponent: makeComponent()
        case .makeUnique: detachInstance()
        case .align:
            if let edge = call.word("edge").flatMap(LayerAlignment.init(rawValue:)) { alignSelection(edge) }
        case .spaceEvenly:
            if let axis = call.word("axis").flatMap(LayerDistribution.init(rawValue:)) { distributeSelection(axis) }
        case .bringToFront: restackSelectedLayers(.toFront)
        case .bringForward: restackSelectedLayers(.forward)
        case .sendBackward: restackSelectedLayers(.backward)
        case .sendToBack: restackSelectedLayers(.toBack)
        case .deleteLayer: deleteSelectedLayers()
        case .renameLayer:
            if let name = call.word("name"), let id = selectedLayerID { renameLayer(id: id, to: name) }
            else { renameLayerInHand() }
        case .lockLayer: if let id = selectedLayerID { toggleLayerLock(id: id) }
        case .showColumns: toggleFrameColumns()
        case .addEffect: if let kind = call.word("kind").flatMap(AddableEffect.init(rawValue:)) { addEffect(kind) }
        case .addSavedEffect: if let style = savedEffect(named: call.word("style")) { addEffectStyle(styleID: style.id) }
        case .removeEffect: if let row = effectRow(call.integer("index")) { removeEffect(row: row) }
        case .setArrowStyle:
            if let style = call.word("style").flatMap(ArrowStyle.init(rawValue:)) { setArrowStyle(ids: pickedArrowIDs, style) }
        case .reshuffleArrows: reshuffleArrows(ids: pickedArrowIDs)
        case .straightenArrows: straightenArrows(ids: pickedArrowIDs)
        case .turnIntoPath: turnSelectionIntoPath()
        case .putTextOnPath: putSelectionTextOnPath()
        case .turnIntoPicture: rasterizeSelection()
        case .bringIntoView: bringSelectionIntoView()
        case .fillTheStack: toggleFillsTheFlow()
        case .surfaceBehind: toggleSurface()
        case .inFrontOfTheRest: toggleFloating()
        case .newFrame:
            if let width = call.amount("width"), let height = call.amount("height") {
                addFrameInView(size: CGSize(width: width.rounded(), height: height.rounded()))
            } else {
                isNewFrameDialogPresented = true
            }
        case .addVariant:
            _ = addComponentVersion()
            // The new variant's name opens for a person to type over; an
            // agent named nothing, and that field would land a step of its own.
            if agentIsRunning { componentVersionAwaitingName = nil }
        case .applyToOtherVersions: applyToOtherComponentVersions()
        case .makeAlternatives: makeChoice()
        case .editOriginal: editPickedOriginal()
        case .doneEditingOriginal: finishEditingOriginal()
        case .reset3DRotation: resetSpaceRotation()
        case .bringNearer: pushDepth(nearer: true)
        case .sendFurther: pushDepth(nearer: false)
        // Measure
        case .showAllMeasurements: setAllMeasurementsVisible(true)
        case .hideAllMeasurements: setAllMeasurementsVisible(false)
        case .clearMeasurements: clearAllMeasurements()
        case .copySpecList: copyMeasureSpecList()
        case .copyMeasurements: copySelectedMeasurements()
        // View
        case .zoomIn: zoomIn()
        case .zoomOut: zoomOut()
        case .zoomToFit: zoomToFit()
        case .actualSize: zoomToActualSize()
        case .zoomTimelineToFit: fitTimeline()
        case .compactTracks: resetTimelineRows()
        case .captionSafeAreas: toggleSafeAreas()
        case .resetCamera: resetCamera()
        }
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func canRun(_ call: AppCommandCall) -> Bool {
        let hasDocument = document != nil
        let timed = documentHasTime
        let track = trackInHand
        let placed = placedLayerInHand
        let word = captionWordInHand
        switch call.id {
        case .playPause, .playBackward, .playForward: return timed
        case .playInToOut: return canPlayInToOut
        case .stop: return isDocumentPlaying
        case .goToPreviousEdit: return canGoToEditPoint(forward: false)
        case .goToNextEdit: return canGoToEditPoint(forward: true)
        case .addMarker, .setIn, .setOut: return timed
        case .markClip: return canMarkClipAtPlayhead
        case .goToIn, .clearIn: return document?.markInMS != nil
        case .goToOut, .clearOut: return document?.markOutMS != nil
        case .clearInAndOut: return canClearMarkInOut
        case .goToNextMarker: return canGoToMarker(forward: true)
        case .goToPreviousMarker: return canGoToMarker(forward: false)
        case .removeMarker: return markerAtPlayhead != nil
        case .clearAllMarkers: return !(document?.markers.isEmpty ?? true)
        case .extract, .lift: return canTakeOutMarkedStretch
        case .splitAtRangeEdges: return trackRangeHeld != nil ? canSplitTrackRangeEdges : canSplitAtRangeEdges
        case .mergeIntoOneClip: return canMergeRange
        case .addCaptionsForRange: return canAddCaptionsInRange
        case .splitEverythingAtPlayhead: return canSplitEverythingAtPlayhead
        case .snapInTimeline, .addVideoTrack, .addAudioTrack, .addCaptionsTrack: return timed
        case .addTrackAbove, .addTrackBelow, .soloTrack, .lockTrack, .deleteTrack: return track != nil
        case .muteTrack: return track?.kind == .audio
        case .hideTrack: return track != nil && track?.kind != .audio
        case .groupTrack: return track != nil && track?.groupID == nil
        case .ungroupTracks: return track?.groupID != nil
        case .deleteEmptyTracks: return hasEmptyTracks
        case .addCaptions: return !isWritingCaptions && canWriteCaptions
        case .cancelCaptions: return isWritingCaptions
        case .captionsLater, .captionsEarlier: return canNudgeCaptions
        case .clearCaptions: return canClearCaptions
        case .resetCaptions: return canResetCaptions
        case .revertToOriginal: return canRevertToOriginal
        case .exportCaptions: return canExportCaptions
        case .renameTrack: return track != nil && call.word("name").map { !$0.isEmpty } != false
        case .section:
            guard let operation = call.word("operation").flatMap(SectionOperation.init(rawValue:)) else {
                return rangeSection != nil && call.options.isEmpty
            }
            return canDoSection(operation, db: call.integer("db"), percent: call.integer("percent"))
        case .editCaptionWord: return word != nil
        case .splitCaptionWord: return (word.flatMap { captionWord($0) }?.text.count ?? 0) >= 2
        case .mergeCaptionWord: return word.map { canMergeCaptionWord($0) } ?? false
        case .deleteCaptionWord, .moveWordToNextLine, .playFromWord, .goToCaptionStart: return word != nil
        case .moveWordToPreviousLine: return word.map { canMoveCaptionWordToPreviousLine($0) } ?? false
        case .joinWithNextLine: return word.map { canJoinCaptionWithNextLine($0.cueID) } ?? false
        case .splitAtPlayhead: return canSplitClipAtPlayhead
        case .delete: return canDeleteWhatIsInHand
        case .rippleDelete: return canRippleDeleteInHand
        case .rippleTrimStart: return canRippleTrimToPlayhead(.start)
        case .rippleTrimEnd: return canRippleTrimToPlayhead(.end)
        case .nudgeEarlier, .nudgeLater: return canNudgeClips
        case .breakApart: return canBreakApartInHand
        case .selectForward: return clipInHandID != nil
        case .hideClickAtPlayhead: return clickAtPlayhead != nil
        case .nextClick: return nextClickMS != nil
        case .showClickEffects: return clickEffectClip.map { hasClicksToShow(onClip: $0.id) } ?? false
        case .addZoom: return clipToAddZoom(atMS: documentTimeMS) != nil
        case .suggestZooms: return clipToSuggestZooms.map { canSuggestZooms(onClip: $0) } ?? false
        case .renameClip: return clipInHandID != nil && call.word("name").map { !$0.isEmpty } != false
        case .addClick: return clipToAddClickTo != nil
        case .followCursor: return !pickedZooms.isEmpty && canFollowCursor(pickedZooms)
        case .setZoomAmount, .deleteZoom: return !pickedZooms.isEmpty
        case .addMediaAtPlayhead: return timed
        case .insertTitle:
            guard canInsertTitle else { return false }
            return call.options.isEmpty || titlePreset(call) != nil
        case .saveTitlePreset: return titlePresetLayerInHand != nil && call.word("name").map { !$0.isEmpty } != false
        case .exportSound: return documentHasAudio
        case .freezeFrame:
            return canHoldFrameAtPlayhead || (clipInHandID != nil && clipPieceInHandPiece?.isHeld == true)
        case .showPicture: return hiddenPictureInHand != nil
        case .setSpeed: return call.integer("percent").map { canSetClipSpeed($0) } ?? (clipSpeedInHand != nil)
        case .addSpeedStop: return canAddSpeedStopInHand
        case .deleteSpeedStop: return canDeleteSpeedStopInHand
        case .resetRamp: return canResetRampInHand
        case .punchIn: return canPunchIn
        case .pullBackOut: return canPullBackOut
        case .resetReframe: return canResetReframe
        case .setFade:
            guard let layer = pictureFadeLayerInHand,
                  let end = call.word("end").flatMap(FadeEnd.init(rawValue:)),
                  let ms = call.integer("milliseconds") else { return pictureFadeLayerInHand != nil && call.options.isEmpty }
            return pictureFadeStops(end, layer: layer).contains(ms)
        case .fadeInAndOut: return !pictureFadeTargetsInHand.isEmpty
        case .setTransition:
            guard canWorkWithClipTransitions else { return false }
            guard let kind = call.word("kind").flatMap(ClipTransitionKind.init(rawValue:)) else {
                return call.options.isEmpty && cutInHand != nil
            }
            return cutInHand?.cut.canAfford(kind) ?? false
        case .hardCut: return cutInHand?.cut.transition != nil
        case .resetTransitionLength: return canResetClipTransitionLength
        case .setTransitionLength:
            guard cutInHand?.cut.drawnTransition != nil else { return false }
            return call.integer("milliseconds").map { clipTransitionLengthOffers.contains($0) } ?? call.options.isEmpty
        case .setTransitionCurve:
            guard cutInHand?.cut.drawnTransition != nil else { return false }
            return call.word("curve").map { transitionCurve(named: $0) != nil } ?? true
        case .applyTransitionToEveryCut: return canWorkWithClipTransitions
        case .setDefaultTransition:
            return canWorkWithClipTransitions && defaultTransitionKind != transitionKindInHand
        case .applyDefaultTransition: return canApplyDefaultTransition()
        case .expandCut: return canExpandCut
        case .rollEditToPlayhead: return canRollCutInHand
        case .joinThroughEdit: return canJoinThroughEditInHand
        case .detachAudio: return canDetachSound
        case .reattachAudio: return canReattachSound
        case .flattenLevel: return !soundLevelInHand.points.isEmpty
        case .normalizePeaks, .normalizeLoudness, .normalizeCleansNoise, .cleanNoise: return !soundIDsInHand.isEmpty
        case .resetGain:
            return soundIDsInHand.contains { (document?.layer(id: $0)?.soundLevel?.clipGainDB ?? 0) != 0 }
        case .replayTitle: return titleInHandID != nil
        case .startAtPlayhead: return placed.map { canStartPlacedLayerHere($0.id) } ?? false
        case .endAtPlayhead: return placed.map { canEndPlacedLayerHere($0.id) } ?? false
        case .animateIn, .animateOut: return placed.map { !isClipLocked($0.id) } ?? false
        case .goToNextKey: return canGoToKey(forward: true)
        case .goToPreviousKey: return canGoToKey(forward: false)
        case .keyAtPlayhead: return canKeyAtPlayhead
        case .curveThePath: return motionPathShape != nil
        case .removeKeyAtPlayhead: return canRemoveKeyAtPlayhead
        case .selectAllKeys: return canSelectAllKeys
        case .setEasing:
            guard betweenKeysCurve != nil else { return false }
            return call.word("curve").map { easingCurve(named: $0) != nil } ?? true
        case .straightenStretch: return curvedStretchInHand != nil
        case .animateProperty:
            guard let layer = layerToAnimate, !isClipLocked(layer.id), !animateGroups(layerID: layer.id).isEmpty else {
                return false
            }
            return call.word("property").map { propertyToAnimate(named: $0) != nil } ?? true
        case .stopAnimating: return propertyAnimating(named: call.word("property")) != nil
        case .save: return saveAffordance.isSaveEnabled && !saveAsksWhere
        case .importMedia: return canImportMedia
        case .resizeImage, .canvasSize, .newFrame: return hasDocument
        case .cut, .copy, .paste: return hasDocument
        case .copyMerged: return hasDocument
        case .copySVG: return canCopySVG(around: pickedLayerID)
        case .copyVideo, .copyAsGIF: return canCopyVideo
        case .selectAll, .newLayer, .newCollageLayer: return hasDocument
        case .swapFillColors: return true
        case .deselect, .invertSelection, .blurBehindSelection: return selection != nil
        case .fillWithForeground, .fillWithBackground: return canFillWithFillColors
        case .newLayerViaCopy: return selection != nil || hasLayerSelection
        case .newLayerViaCut: return canCutSelectionToLayer
        case .duplicateLayer, .bringToFront, .bringForward, .sendBackward, .sendToBack: return hasLayerSelection
        case .mirrorAcrossCenter: return canMirrorSelectionAcrossCenter
        case .centerOnArtboard: return canCenterSelectionOnArtboard
        case .selectPixels: return selectedLayerID != nil
        case .putOnTimeline: return selectedLayerID.map { canPutOnTimeline($0) } ?? false
        case .copyLook: return canCopyLook
        case .pasteLook: return canPasteLook
        case .mergeDown: return canMergeDown
        case .combineShapes: return canCombineSelection
        case .union: return canUnionSelection
        case .outlineStroke: return canOutlineSelectionStroke
        case .separateIntoLayers: return selectedLayerID.map { canSeparateIntoLayers(id: $0) } ?? false
        case .turnIntoText: return canTurnIntoTextSelection
        case .arrangeInCollage: return canArrangeCollage
        case .group: return canGroupSelection
        case .ungroup: return canUngroupSelection
        case .stackSelection, .gridSelection: return canStackSelection
        case .frameSelection: return canFrameSelection
        case .makeComponent: return canMakeComponent
        case .makeUnique: return canDetachInstance
        case .align:
            return call.word("edge").flatMap(LayerAlignment.init(rawValue:)).map { canAlignSelection($0) }
                ?? canAlignSelection
        case .spaceEvenly: return canDistributeSelection
        case .deleteLayer: return canDeleteSelectedLayers
        case .renameLayer: return selectedLayerID != nil && call.word("name").map { !$0.isEmpty } != false
        case .lockLayer: return selectedLayerID != nil
        case .showColumns: return columnsTargetFrameID != nil
        case .addEffect:
            guard hasRestylableSelection else { return false }
            guard let kind = call.word("kind").flatMap(AddableEffect.init(rawValue:)) else { return call.options.isEmpty }
            return addableEffects.contains(kind) && canAddEffect(kind)
        case .addSavedEffect:
            guard hasRestylableSelection, !namedEffectStyles.isEmpty else { return false }
            return call.word("style").map { savedEffect(named: $0) != nil } ?? true
        case .removeEffect:
            guard hasRestylableSelection, !layerEffectRows.isEmpty else { return false }
            return call.integer("index").map { effectRow($0) != nil } ?? true
        case .setArrowStyle: return !pickedArrowIDs.isEmpty
        case .reshuffleArrows: return !reshufflableArrows(pickedArrowIDs).isEmpty
        case .straightenArrows: return !straightenableArrows(pickedArrowIDs).isEmpty
        case .turnIntoPath: return canTurnSelectionIntoPath
        case .putTextOnPath: return canPutTextOnPath
        case .turnIntoPicture: return canRasterizeSelection
        case .bringIntoView: return canBringSelectionIntoView
        case .fillTheStack: return flowFillCommand.isEnabled
        case .surfaceBehind, .inFrontOfTheRest: return surfaceCommand.isEnabled
        case .addVariant: return canAddComponentVersion
        case .applyToOtherVersions: return canApplyToOtherComponentVersions
        case .makeAlternatives: return canMakeChoice
        case .editOriginal: return canEditPickedOriginal
        case .doneEditingOriginal: return isEditingOriginal
        case .reset3DRotation: return canResetSpaceRotation
        case .bringNearer, .sendFurther: return canPushDepth
        case .showAllMeasurements: return visibleMeasurementCount != measurementCount
        case .hideAllMeasurements: return visibleMeasurementCount > 0
        case .clearMeasurements: return measurementCount > 0
        case .copySpecList: return visibleMeasurementCount > 0
        case .copyMeasurements: return !selectedMeasureLayerIDs.isEmpty
        case .zoomIn, .zoomOut, .zoomToFit, .actualSize: return hasDocument
        case .zoomTimelineToFit: return isTimelineOpenedOut
        case .compactTracks: return !timelineRowZoom.isCompact
        case .captionSafeAreas: return hasCaptions
        case .resetCamera: return canResetCamera
        }
    }

    // MARK: What the rows share

    /// The sounds the sound rows act on: the one in hand and the ones it is
    /// picked with.
    var soundIDsInHand: [UUID] {
        soundLayerInHand.map { soundLayers(actingOn: $0.id) } ?? []
    }

    /// Whether noise cleaning is on any of them, which turns Clean Noise into
    /// Remove Noise Cleaning.
    var soundInHandIsCleaned: Bool {
        soundIDsInHand.contains {
            document?.layer(id: $0)?.soundLevel?.noiseReduction != nil
                || document?.layer(id: $0)?.hasSectionNoiseCleaning == true
        }
    }

    /// What Suggest Zooms acts on: the clip in hand, else the recording under
    /// the playhead.
    var clipToSuggestZooms: UUID? { clipInHandID ?? clipToAddZoom(atMS: documentTimeMS) }

    private func transitionCurve(named name: String?) -> EasingCurve? {
        guard let name else { return nil }
        return EasingCurve.named.prefix(EasingCurve.standardCount).first { $0.title == name }
    }

    // MARK: ⌫ on the timeline

    /// What ⌫ takes on the timeline, in the order it looks: keys (or points on
    /// a sound's line) picked on a lane, a transition, a range's section of a
    /// clip, a range on the ruler, a range on some tracks or pieces a box
    /// picked, a gap, else the piece in hand. The Clip menu's ⌫ row is titled
    /// from it.
    enum DeleteInHand {
        case points, keys, transition, section, range, trackRange, pieces, gap, piece
    }

    var deleteInHand: DeleteInHand {
        let keysPicked = canDeletePickedKeys
        let rangeHeld = rulerRangeHeld != nil
        let trackHeld = !rangeHeld && (trackRangeHeld != nil || timelinePicksHeld != nil)
        let gapHeld = !rangeHeld && !trackHeld && timelineGapHeld != nil
        if keysPicked { return canDeletePickedSoundPoints ? .points : .keys }
        if !rangeHeld && !trackHeld && !gapHeld && transitionHeldForDelete != nil { return .transition }
        if sectionTakesTheDelete { return .section }
        if rangeHeld { return .range }
        if trackHeld { return trackRangeHeld != nil ? .trackRange : .pieces }
        if gapHeld { return .gap }
        return .piece
    }

    var canDeleteWhatIsInHand: Bool {
        guard documentHasTime else { return false }
        switch deleteInHand {
        case .points, .keys, .transition, .section: return true
        case .range: return canTakeOutMarkedStretch || canDeleteClipPieceInHand
        case .trackRange, .pieces: return canTakeOutTrackThing || canDeleteClipPieceInHand
        case .gap: return canCloseGapInHand || canDeleteClipPieceInHand
        case .piece: return canDeleteClipPieceInHand
        }
    }

    func deleteWhatIsInHand() {
        switch deleteInHand {
        case .points, .keys: deletePickedKeys()
        case .transition: _ = deleteTransitionInHand()
        case .section: deleteRangeSection()
        case .range: liftMarkedStretch()
        case .trackRange, .pieces: liftTrackThing()
        case .gap: closeGapInHand()
        case .piece: deleteClipPieceInHand()
        }
    }
}
