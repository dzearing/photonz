import CoreGraphics
import Foundation

// The reference edit (task `a-long-reference-edit-opens-in-the-probe-in-one`,
// objective `video-perf`).
//
// Every speed fix for video needs the same long, busy edit to measure against,
// built the same way every time, so a number before a change and a number
// after it mean something. This lays it out: screen recordings at Retina size
// cut onto a main track over a moving background, picture-in-picture b-roll on
// a track above, titles on a track above that, dissolves at most cuts with a
// push and turns in depth among them, zooms, each recording's own sound and a
// music track under it all.
//
// It is a measuring tool and nothing in the app reads it. It is built only out
// of the model's own operations (`land`, `setTransition`, `insertTitle`, the
// shared title shelf and transition catalogue), so it exercises exactly what a
// person's edit does. The recordings themselves are written by
// `ReferenceFootage` (PhotonzMedia), once per machine, to the size, length and
// ids this file names.

/// The reference edit: what it is made of and how it is laid out.
public enum ReferenceEdit {

    /// Bumped whenever what the recordings LOOK or SOUND like changes, so a
    /// machine holding the old ones writes them again. The layout of the edit
    /// is the seed's business and needs no bump.
    public static let recipeVersion = 1

    /// The lengths it is kept at, in minutes.
    public static let lengths = [6, 20, 60]

    /// What a Retina MacBook Pro records its whole screen at.
    public static let pixelSize = CGSize(width: 3456, height: 2234)
    /// The rate a Retina recording is captured at.
    public static let framesPerSecond = 60

    /// The seed every measured run uses.
    public static let defaultSeed: UInt64 = 0x5EED_0006

    /// Every clip on the main track is named from this, so a test or a walk
    /// can tell the cut from the b-roll above it.
    public static let mainClipPrefix = "Take"
    public static let brollPrefix = "B-roll"

    /// Where the recordings are kept, inside whatever folder holds them: the
    /// recipe version is in the name, so a new recipe writes new files.
    public static var footageFolderName: String { "footage v\(recipeVersion)" }

    /// The file a project of this length is written to.
    public static func projectName(minutes: Int) -> String { "Reference Edit \(minutes) min.photonz" }

    // MARK: - The recordings

    /// What one recording shows, which `ReferenceFootage` draws.
    public enum Scene: String, CaseIterable, Hashable, Sendable {
        /// A long document scrolling past in a window, the pointer reading down it.
        case scrollingPage
        /// A code editor with lines being typed and the view scrolling to follow.
        case typingCode
        /// Windows sliding in and out over a desktop, the pointer dragging them.
        case slidingWindows
        /// A dashboard of cards and a chart, the pointer clicking through tabs.
        case dashboard
    }

    /// One generated screen recording.
    public struct Footage: Hashable, Sendable {
        public let index: Int
        public let scene: Scene
        public let movie: MovieRef
        public var fileName: String { "Reference Recording \(index + 1).mov" }
        /// What a clip of it is called on the timeline.
        public var clipName: String { "\(ReferenceEdit.mainClipPrefix) \(index + 1)" }
    }

    /// How long each recording runs: long enough that a clip of up to fourteen
    /// seconds always has spare either side for its transitions.
    public static let footageLengthMS = 60_000

    public static let footage: [Footage] = Scene.allCases.enumerated().map { index, scene in
        Footage(index: index, scene: scene,
                movie: MovieRef(id: mediaID(index), pixelSize: pixelSize,
                                durationMS: footageLengthMS, hasSound: true))
    }

    /// The music under the whole edit.
    public struct Music: Hashable, Sendable {
        public let sound: SoundRef
        public var fileName: String { "Reference Music.m4a" }
    }

    public static let musicLengthMS = 120_000
    public static let music = Music(sound: SoundRef(id: mediaID(15), durationMS: musicLengthMS))

    /// A fixed id per file, so the same recording is the same id in every
    /// build of the edit and on every machine.
    static func mediaID(_ index: Int) -> UUID {
        UUID(uuid: (0x52, 0x45, 0x46, 0x45, 0x44, 0x49, 0x54, UInt8(truncatingIfNeeded: recipeVersion),
                    0x40, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00, UInt8(truncatingIfNeeded: index)))
    }

    // MARK: - Building it

    /// The edit at `minutes` long, laid out from `seed`. Same seed, same
    /// document, ids and all.
    public static func build(minutes: Int, seed: UInt64 = defaultSeed) -> PhotonzDocument {
        var builder = Builder(totalMS: max(1, minutes) * 60_000, seed: seed)
        builder.lay()
        return builder.finished()
    }

    struct Builder {
        let totalMS: Int
        var random: SplitMix
        var doc: PhotonzDocument
        var titleTrack = UUID()
        var brollTrack = UUID()
        var mainTrack = UUID()
        var backgroundTrack = UUID()
        var musicTrack = UUID()

        init(totalMS: Int, seed: UInt64) {
            self.totalMS = totalMS
            self.random = SplitMix(seed: seed)
            var doc = PhotonzDocument(canvasSize: ReferenceEdit.pixelSize, pixelScale: 2)
            doc.durationMS = totalMS
            self.doc = doc
        }

        mutating func lay() {
            // Bottom to top: each new picture track lands over the last.
            backgroundTrack = doc.addTrack(.video, named: "Background")
            mainTrack = doc.addTrack(.video)
            brollTrack = doc.addTrack(.video)
            titleTrack = doc.addTrack(.video, named: DocumentTrack.titleTrackName)
            musicTrack = doc.addTrack(.audio, named: "Music")
            for footage in ReferenceEdit.footage {
                doc.rememberMedia(.recording(footage.movie), named: footage.fileName)
            }
            doc.rememberMedia(.sound(ReferenceEdit.music.sound), named: ReferenceEdit.music.fileName)

            // The titles go through the shelf's own insert while the document
            // is still small; everything after is placed straight on its track
            // and the stack put in track order once at the end. Landing each
            // clip one at a time reads the whole timeline every time, which at
            // an hour long took over a minute (2026-11-12).
            layTitles()
            layBackground()
            let main = layMainClips()
            layTransitions(main)
            layZooms(on: main)
            layBroll()
            layMusic()
            doc.restackByTracks()
        }

        // MARK: The moving background

        /// A liquid gradient filling the frame for the whole edit, the way a
        /// screen recording is shown on a backdrop with the picture inset.
        mutating func layBackground() {
            var fill = Paint(hex: "#14123A", kind: .live,
                             stops: [GradientStop(hex: "#14123A", position: 0),
                                     GradientStop(hex: "#3B2C8F", position: 0.5),
                                     GradientStop(hex: "#0E5A7A", position: 1)],
                             live: LiveBackdrop(look: .liquidGradient, speed: 60))
            fill.drift = 0
            let size = ReferenceEdit.pixelSize
            var content = AnnotationContent(shape: .rectangle, strokeWidth: 0, colorHex: fill.hex,
                                            start: .zero, end: CGPoint(x: size.width, y: size.height))
            content.fill = fill
            var layer = Layer(name: "Moving Background", content: .annotation(content),
                              frame: CGRect(origin: .zero, size: size))
            layer.time = LayerTime(inMS: 0, outMS: totalMS)
            place(layer, on: backgroundTrack)
        }

        // MARK: The main track

        /// Where the recording sits over the background: inset, rounded, with
        /// a shadow under it.
        static var insetFrame: CGRect {
            let size = ReferenceEdit.pixelSize
            return CGRect(x: size.width * 0.06, y: size.height * 0.06,
                          width: size.width * 0.88, height: size.height * 0.88)
        }

        static let spareMS = 1500

        mutating func layMainClips() -> [UUID] {
            var placed: [UUID] = []
            var at = 0
            var previous = -1
            while at < totalMS {
                var length = random.int(in: 6000...13_000, step: 100)
                let left = totalMS - at
                // The last clip takes what is left, rather than leaving a
                // sliver too short to cut to.
                if left < length + 6000 { length = left }
                length = min(length, ReferenceEdit.footageLengthMS - 2 * Self.spareMS)
                var pick = random.int(in: 0...(ReferenceEdit.footage.count - 1))
                if pick == previous { pick = (pick + 1) % ReferenceEdit.footage.count }
                previous = pick
                let footage = ReferenceEdit.footage[pick]
                let latest = ReferenceEdit.footageLengthMS - Self.spareMS - length
                let sourceIn = random.int(in: Self.spareMS...max(Self.spareMS, latest), step: 100)
                var layer = clipLayer(footage, name: footage.clipName, frame: Self.insetFrame,
                                      inMS: at, lengthMS: length, sourceInMS: sourceIn)
                layer.style.cornerRadius = 36
                layer.style.effects.append(.shadow(ShadowStyle(radius: 60, offset: CGSize(width: 0, height: 24),
                                                               colorHex: "#000000", opacity: 0.45)))
                placed.append(place(layer, on: mainTrack))
                at += length
            }
            return placed
        }

        func clipLayer(_ footage: Footage, name: String, frame: CGRect,
                       inMS: Int, lengthMS: Int, sourceInMS: Int) -> Layer {
            let movie = footage.movie
            var layer = Layer(name: name, content: .image(movie.frameRef(atSourceMS: sourceInMS)), frame: frame)
            layer.movie = movie
            layer.time = LayerTime(inMS: inMS, outMS: inMS + lengthMS, sourceInMS: sourceInMS,
                                   sourceLengthMS: movie.durationMS)
            return layer
        }

        // MARK: Transitions

        /// Dissolves at most cuts. In every run of twelve cuts there is a
        /// push, a cube, a flip and a hard cut or two, so every stretch of the
        /// edit has a turn in depth to draw.
        mutating func layTransitions(_ clips: [UUID]) {
            for (n, pair) in zip(clips, clips.dropFirst()).enumerated() {
                let kind: ClipTransitionKind?
                switch n % 12 {
                case 2: kind = .push
                case 5: kind = .cube
                case 8: kind = .flip
                case 10: kind = random.int(in: 0...1) == 0 ? nil : .dissolve
                default: kind = .dissolve
                }
                guard let kind, var transition = fitted(kind, from: pair.0, to: pair.1) else { continue }
                if kind.hasDirection {
                    transition.direction = [TitleDirection.left, .right, .up][random.int(in: 0...2)]
                }
                doc.updateLayer(id: pair.1) { $0.arrivalTransition = transition }
            }
        }

        /// What the cut between two clips can take of `kind`, asked of the
        /// two clips alone on a track of their own: the model's own arithmetic
        /// (`DocumentCut.cut.fitted`), without reading the whole timeline for
        /// every cut. Neither kind used here holds on a colour, so writing it
        /// on the arriving clip is all `setTransition` would do.
        func fitted(_ kind: ClipTransitionKind, from outgoing: UUID, to incoming: UUID) -> ClipTransition? {
            guard var out = doc.layer(id: outgoing), var into = doc.layer(id: incoming) else { return nil }
            let track = UUID()
            out.trackID = track
            into.trackID = track
            var pair = PhotonzDocument(canvasSize: doc.canvasSize, layers: [out, into])
            pair.durationMS = doc.durationMS
            pair.tracks = [DocumentTrack(id: track, name: "V1", kind: .video)]
            return pair.documentCut(at: .edit(outgoing: outgoing, incoming: incoming))?.cut.fitted(kind)
        }

        // MARK: Zooms

        /// A zoom on every third clip, eased in and out inside it, on a spot
        /// somewhere in the picture.
        mutating func layZooms(on clips: [UUID]) {
            for (n, id) in clips.enumerated() where n % 3 == 1 {
                guard let time = doc.layer(id: id)?.time, time.lengthMS >= 5000 else { continue }
                let length = min(time.lengthMS - 1500, random.int(in: 3000...4500, step: 100))
                let start = time.sourceInMS + random.int(in: 500...max(500, time.lengthMS - length - 500), step: 100)
                let zoom = ClipZoom(startMS: start, endMS: start + length,
                                    scale: Double(random.int(in: 15...22)) / 10,
                                    center: CGPoint(x: Double(random.int(in: 25...75)) / 100,
                                                    y: Double(random.int(in: 25...75)) / 100))
                doc.updateLayer(id: id) { $0.zooms = ($0.zooms ?? []) + [zoom] }
            }
        }

        // MARK: B-roll

        /// Every forty to sixty seconds, a few seconds of another recording in
        /// a small window in the corner, silent, coming and going with a fade.
        mutating func layBroll() {
            let size = ReferenceEdit.pixelSize
            let frame = CGRect(x: size.width * 0.62, y: size.height * 0.58,
                               width: size.width * 0.32, height: size.height * 0.32)
            var at = random.int(in: 20_000...30_000, step: 100)
            var n = 0
            while at + 8000 < totalMS - 8000 {
                let length = random.int(in: 5000...8000, step: 100)
                let footage = ReferenceEdit.footage[random.int(in: 0...(ReferenceEdit.footage.count - 1))]
                let sourceIn = random.int(in: 0...(ReferenceEdit.footageLengthMS - length), step: 100)
                n += 1
                var layer = clipLayer(footage, name: "\(ReferenceEdit.brollPrefix) \(n)", frame: frame,
                                      inMS: at, lengthMS: length, sourceInMS: sourceIn)
                layer.style.cornerRadius = 24
                layer.soundDetached = true
                let id = place(layer, on: brollTrack)
                _ = doc.fadePicture(id, .in, toMS: 400)
                _ = doc.fadePicture(id, .out, toMS: 400)
                at += length + random.int(in: 35_000...55_000, step: 100)
            }
        }

        // MARK: Titles

        /// An opening page on a moving background, a name card and a chapter
        /// card in every six minutes, and an end card. Real presets from the
        /// title shelf, laid on the Title track over the picture.
        mutating func layTitles() {
            insert(.softGlass, at: 0)
            let block = 360_000
            var start = 0
            var chapter = 0
            while start < totalMS {
                let nameCardAt = start + (start == 0 ? 20_000 : random.int(in: 15_000...60_000, step: 100))
                if nameCardAt + 5000 < totalMS - 10_000 {
                    insert(chapter % 2 == 0 ? .splitWipe : .pill, at: nameCardAt)
                }
                let chapterAt = start + random.int(in: 150_000...220_000, step: 100)
                if chapterAt + 4000 < totalMS - 10_000 {
                    insert([.chapterCard, .kinetic, .sessionTitle][chapter % 3], at: chapterAt)
                }
                chapter += 1
                start += block
            }
            insert(.endCard, at: totalMS - BuiltInTitle.endCard.kind.lengthMS)
        }

        mutating func insert(_ preset: BuiltInTitle, at ms: Int) {
            let landing = landing(on: titleTrack, DocumentTrack.titleTrackName, at: ms,
                                  length: preset.kind.lengthMS)
            _ = doc.insertTitle(preset, atTimeMS: ms, landing: landing)
        }

        // MARK: Music

        /// Music under the whole edit, cut from different places in the track
        /// and played quietly under the voices.
        mutating func layMusic() {
            var at = 0
            while at < totalMS {
                let length = min(totalMS - at, random.int(in: 45_000...90_000, step: 100))
                let sourceIn = random.int(in: 0...(ReferenceEdit.musicLengthMS - length), step: 100)
                var layer = Layer.sound(ReferenceEdit.music.sound, name: "Music",
                                        time: LayerTime(inMS: at, outMS: at + length, sourceInMS: sourceIn,
                                                        sourceLengthMS: ReferenceEdit.musicLengthMS))
                layer.soundLevel = AudioLevel(gain: 0.3)
                place(layer, on: musicTrack)
                at += length
            }
        }

        /// A clip straight onto a track, where the builder already knows
        /// nothing is in its way.
        @discardableResult
        mutating func place(_ layer: Layer, on track: UUID) -> UUID {
            var layer = layer
            layer.trackID = track
            doc.layers.append(layer)
            return layer.id
        }

        func landing(on track: UUID, _ name: String, at ms: Int, length: Int) -> ClipLanding {
            ClipLanding(target: .onto(track), startMS: ms, lengthMS: length, edit: .overwrite,
                        trackName: name, allowed: true)
        }

        // MARK: Ids

        /// The document with every id the model minted at random replaced,
        /// in the order it first appears, by one drawn from the seed. The
        /// recordings' and the music's own ids, and the frame references
        /// folded out of them, are fixed already and kept.
        mutating func finished() -> PhotonzDocument {
            doc.durationMS = totalMS
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            guard let data = try? encoder.encode(doc) else { return doc }
            let text = String(decoding: data, as: UTF8.self)
            let fixed = Set(ReferenceEdit.footage.map { prefix($0.movie.id) } + [prefix(ReferenceEdit.music.sound.id)])
            var mapped: [String: String] = [:]
            var out = ""
            out.reserveCapacity(text.utf8.count)
            var rest = text[...]
            let pattern = /[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}/
            while let match = rest.firstMatch(of: pattern) {
                out += rest[..<match.range.lowerBound]
                let found = String(rest[match.range])
                if let id = UUID(uuidString: found), fixed.contains(prefix(id)) {
                    out += found
                } else if let known = mapped[found] {
                    out += known
                } else {
                    let made = random.uuid().uuidString
                    mapped[found] = made
                    out += made
                }
                rest = rest[match.range.upperBound...]
            }
            out += rest
            return (try? JSONDecoder().decode(PhotonzDocument.self, from: Data(out.utf8))) ?? doc
        }

        func prefix(_ id: UUID) -> UInt64 {
            let u = id.uuid
            return [u.0, u.1, u.2, u.3, u.4, u.5, u.6, u.7].reduce(0) { $0 << 8 | UInt64($1) }
        }
    }

    // MARK: - What it holds

    /// A count of what an edit holds, for the list in the video-perf
    /// objective.
    public struct Census: Hashable, Sendable {
        public var lengthMS = 0
        public var pictureTracks = 0
        public var soundTracks = 0
        /// Every clip on the timeline: recordings, titles, sounds, the background.
        public var clips = 0
        /// Clips that play a recording.
        public var recordingClips = 0
        /// Places on a picture track where one shot meets the next.
        public var cuts = 0
        public var transitions: [ClipTransitionKind: Int] = [:]
        public var titles = 0
        public var titlesOnAMovingBackground = 0
        public var zooms = 0
        /// Full-frame moving looks that are not a title's own background.
        public var movingBackgrounds = 0
        /// The one size every recording is, nil when they differ.
        public var recordingSize: CGSize?
        public var clipsWithSound = 0
        public var musicClips = 0
        /// How much of the edit has music under it.
        public var musicCoverageMS = 0
    }

    public static func census(of doc: PhotonzDocument) -> Census {
        var census = Census()
        census.lengthMS = doc.documentDurationMS
        let tracks = doc.timelineTracks
        census.pictureTracks = tracks.filter { $0.kind == .video }.count
        census.soundTracks = tracks.filter { $0.kind == .audio }.count
        let clips = doc.timelineClipLayers
        census.clips = clips.count
        var sizes = Set<String>()
        var music: [Range<Int>] = []
        for layer in clips {
            if let movie = layer.movie {
                census.recordingClips += 1
                sizes.insert("\(movie.pixelSize.width)x\(movie.pixelSize.height)")
                census.zooms += layer.zooms?.count ?? 0
                if layer.hasLinkedSound { census.clipsWithSound += 1 }
                if census.recordingSize == nil { census.recordingSize = movie.pixelSize }
            }
            if let recipe = layer.group?.titleRecipe {
                census.titles += 1
                if recipe.showsBackground, let background = recipe.background,
                   ![.solid, .gradient, .glass].contains(background) {
                    census.titlesOnAMovingBackground += 1
                }
            }
            if case .annotation(let shape) = layer.content, shape.fill?.kind == .live,
               layer.frame.size == doc.canvasSize {
                census.movingBackgrounds += 1
            }
            if case .sound = layer.content, let time = layer.time, layer.movie == nil {
                census.musicClips += 1
                music.append(time.inMS..<time.outMS)
            }
        }
        if sizes.count != 1 { census.recordingSize = nil }
        // The cuts `transitionCuts` lists, read a track at a time: asking it
        // cut by cut lays the whole timeline out again for every one.
        let byID = Dictionary(clips.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func count(_ kind: ClipTransitionKind?) {
            census.cuts += 1
            if let kind { census.transitions[kind, default: 0] += 1 }
        }
        for track in tracks where track.kind == .video {
            for point in doc.editPoints(onTrack: track.id) {
                count(byID[point.incoming]?.arrivalTransition?.kind)
            }
        }
        for layer in clips where layer.movie != nil {
            for cut in layer.clipCuts { count(cut.transition?.kind) }
        }
        census.musicCoverageMS = Self.covered(music, upTo: census.lengthMS)
        return census
    }

    static func covered(_ spans: [Range<Int>], upTo end: Int) -> Int {
        var total = 0
        var reach = 0
        for span in spans.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            let from = max(span.lowerBound, reach)
            let to = min(span.upperBound, end)
            if to > from { total += to - from }
            reach = max(reach, span.upperBound)
        }
        return total
    }

    /// Every line of the video-perf objective's list (and this task's) that
    /// an edit of `minutes` falls short of, in words. Empty is a reference
    /// edit.
    public static func shortfalls(_ census: Census, minutes: Int) -> [String] {
        var short: [String] = []
        let blocks = max(1, minutes / 6)
        func need(_ ok: Bool, _ line: String) { if !ok { short.append(line) } }
        need(census.lengthMS >= minutes * 60_000, "at least \(minutes) minutes long")
        need(census.pictureTracks >= 3, "3 or more picture tracks")
        need(census.cuts >= 30 * blocks, "\(30 * blocks) or more cuts")
        let dissolves = census.transitions[.dissolve] ?? 0
        need(dissolves * 2 > census.cuts, "dissolves at most cuts")
        need((census.transitions[.push] ?? 0) >= blocks, "a push in every six minutes")
        let inDepth = census.transitions.filter { $0.key.isInDepth }.values.reduce(0, +)
        need(inDepth >= blocks, "a transition in depth in every six minutes")
        need(census.titles >= 4, "4 or more titles")
        need(census.titlesOnAMovingBackground >= 1, "a title on a moving background")
        need(census.zooms >= 6 * blocks, "\(6 * blocks) or more zooms")
        need(census.movingBackgrounds >= 1, "a moving background behind the recording")
        need(census.recordingSize == pixelSize, "every recording at Retina size, \(Int(pixelSize.width)) x \(Int(pixelSize.height))")
        need(census.clipsWithSound >= census.cuts, "the recordings' own sound")
        need(census.musicClips >= 1 && census.musicCoverageMS >= census.lengthMS, "music under the whole edit")
        return short
    }
}

// MARK: - Moments worth a look

extension ReferenceEdit {

    /// One moment of the edit picked for its contact sheet, and what is on
    /// screen then.
    public struct Moment: Hashable, Sendable {
        public let ms: Int
        public let what: String
    }

    /// Twelve moments that show what the edit is made of: the opening title,
    /// the middle of a push, a cube, a flip and two dissolves, a zoom, the
    /// b-roll, a name card, a chapter card, a plain stretch and the end card.
    /// In time order; fewer where a short edit lacks one.
    public static func sheetMoments(of doc: PhotonzDocument) -> [Moment] {
        var moments: [Moment] = []
        let clips = doc.timelineClipLayers
        func add(_ ms: Int?, _ what: String) {
            guard let ms, !moments.contains(where: { abs($0.ms - ms) < 1000 }) else { return }
            moments.append(Moment(ms: ms, what: what))
        }
        func middle(of name: (Layer) -> Bool, _ what: String) {
            guard let time = clips.first(where: name)?.time else { return }
            add(time.inMS + time.lengthMS / 2, what)
        }
        add(1500, "opening title")
        let byID = Dictionary(clips.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var wanted: [ClipTransitionKind: Int] = [.push: 1, .cube: 1, .flip: 1, .dissolve: 2]
        for track in doc.timelineTracks where track.kind == .video {
            for point in doc.editPoints(onTrack: track.id) {
                guard let transition = byID[point.incoming]?.arrivalTransition,
                      let left = wanted[transition.kind], left > 0,
                      // Past the opening title, so the transition is what is seen.
                      point.atMS > 10_000 else { continue }
                let half = transition.lengthMS / 2
                let mid: Int
                switch transition.alignment {
                case .before: mid = point.atMS - half
                case .across: mid = point.atMS
                case .after: mid = point.atMS + half
                }
                add(mid, "mid-\(transition.kind.title.lowercased())")
                wanted[transition.kind] = left - 1
            }
        }
        if let zoomed = clips.first(where: { ($0.zooms?.isEmpty == false) && ($0.time?.inMS ?? 0) > 10_000 }),
           let zoom = zoomed.zooms?.first, let time = zoomed.time {
            add(time.inMS + (zoom.startMS + zoom.endMS) / 2 - time.sourceInMS, "zoomed in")
        }
        middle(of: { $0.name.hasPrefix(brollPrefix) }, "b-roll in the corner")
        let titles = clips.filter { $0.group?.titleRecipe != nil }.sorted { ($0.time?.inMS ?? 0) < ($1.time?.inMS ?? 0) }
        for title in titles.dropFirst() {
            if let time = title.time { add(time.inMS + time.lengthMS / 2, title.name.lowercased()) }
        }
        add(doc.documentDurationMS / 3, "a plain stretch")
        add(doc.documentDurationMS * 2 / 3 + 3000, "another plain stretch")
        return Array(moments.sorted { $0.ms < $1.ms }.prefix(12))
    }
}

// MARK: - A seeded generator

/// SplitMix64: small, fast, and the same numbers from the same seed on every
/// machine, which `SystemRandomNumberGenerator` is not.
struct SplitMix {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A whole number in `range`, on multiples of `step` from its start.
    mutating func int(in range: ClosedRange<Int>, step: Int = 1) -> Int {
        let step = max(1, step)
        let count = (range.upperBound - range.lowerBound) / step + 1
        guard count > 1 else { return range.lowerBound }
        return range.lowerBound + Int(next() % UInt64(count)) * step
    }

    mutating func uuid() -> UUID {
        let a = next(), b = next()
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 {
            bytes[i] = UInt8(truncatingIfNeeded: a >> (56 - 8 * i))
            bytes[8 + i] = UInt8(truncatingIfNeeded: b >> (56 - 8 * i))
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
