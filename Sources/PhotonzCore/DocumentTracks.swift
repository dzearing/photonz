import CoreGraphics
import Foundation

/// **A track**: one row of a document's timeline, holding any number of clips
/// (`docs/design/mocks/pages/video.html`, UX-PATTERNS D18).
///
/// A clip is still a layer. A track is the row it sits on, which a person can
/// add, rename, group, hide, mute, solo and lock, and carry clips between, the
/// way every video editor has them. Which track a clip is on is written on the
/// clip (`Layer.trackID`); the tracks themselves, top to bottom, are written on
/// the document (`PhotonzDocument.tracks`).
///
/// A document nobody has given tracks writes none. Its timeline still has a
/// track per clip, worked out when it is read (`timelineTracks`), and the first
/// thing done to a track writes them all down (`materializeTracks`), so a file
/// nobody edited saves byte for byte as it did before tracks existed.
public struct DocumentTrack: Identifiable, Hashable, Codable, Sendable {

    /// What a track carries, which decides what its header offers: an eye on
    /// a picture track, a speaker on a sound track.
    public enum Kind: String, Hashable, Codable, Sendable, CaseIterable {
        case video, audio, captions

        /// The word the timeline's menus use.
        public var title: String {
            switch self {
            case .video: "Video"
            case .audio: "Audio"
            case .captions: "Captions"
            }
        }

        /// Whether a clip of `clip`'s kind can sit on a track of this one.
        /// Sound goes on sound, picture on picture, and words heard off the
        /// sound go on a captions track or over the picture.
        public func accepts(_ clip: Kind) -> Bool {
            self == clip || (self == .video && clip == .captions)
        }
    }

    public let id: UUID
    public var name: String
    public var kind: Kind
    /// A picture track switched off: its clips are not drawn.
    public var isHidden: Bool
    /// A sound track switched off: its clips are not heard.
    public var isMuted: Bool
    /// Only this track (and any other soloed one of the same sort) is seen, for
    /// a picture track, or heard, for a sound track.
    public var isSolo: Bool
    /// Nothing on it can be moved, trimmed or cut, and nothing lands on it.
    public var isLocked: Bool
    /// The group this track is gathered into, if any (`DocumentTrackGroup`).
    public var groupID: UUID?

    public init(id: UUID = UUID(), name: String, kind: Kind, isHidden: Bool = false,
                isMuted: Bool = false, isSolo: Bool = false, isLocked: Bool = false,
                groupID: UUID? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.isHidden = isHidden
        self.isMuted = isMuted
        self.isSolo = isSolo
        self.isLocked = isLocked
        self.groupID = groupID
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, isHidden, isMuted, isSolo, isLocked, groupID
    }

    /// A switch that is off writes nothing, so a plain track is three keys.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(kind, forKey: .kind)
        if isHidden { try c.encode(true, forKey: .isHidden) }
        if isMuted { try c.encode(true, forKey: .isMuted) }
        if isSolo { try c.encode(true, forKey: .isSolo) }
        if isLocked { try c.encode(true, forKey: .isLocked) }
        try c.encodeIfPresent(groupID, forKey: .groupID)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .video
        isHidden = try c.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
        isMuted = try c.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
        isSolo = try c.decodeIfPresent(Bool.self, forKey: .isSolo) ?? false
        isLocked = try c.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        groupID = try c.decodeIfPresent(UUID.self, forKey: .groupID)
    }
}

/// Tracks gathered under one name, which fold away together under a chevron.
/// Whether a group is folded is how you are looking at it, not what the
/// document is, so it lives with the window rather than here.
public struct DocumentTrackGroup: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var name: String

    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

extension Layer {
    /// The kind of track this layer's clip belongs on.
    public var clipTrackKind: DocumentTrack.Kind {
        if timelineTrackKind == .audio { return .audio }
        if isCaption { return .captions }
        return .video
    }

    /// A clip still carrying its own recording's sound, which the timeline
    /// draws as a linked segment on an audio track under it.
    public var hasLinkedSound: Bool { isClip && !isSoundOnly && sound != nil }

    /// Whether this layer puts anything on the timeline: a stretch of time or
    /// something moving, on itself or anywhere inside it.
    var isOnTheTimeline: Bool {
        selfAndDescendants.contains { $0.occupiesTime || $0.hasMotion }
    }
}

// MARK: - Reading the tracks

extension PhotonzDocument {

    /// The top level layers the timeline lays on tracks, topmost first.
    public var timelineClipLayers: [Layer] {
        guard hasTime else { return [] }
        return layers.reversed().filter(\.isOnTheTimeline)
    }

    /// Every track on the timeline, top to bottom: the ones written down, and
    /// one for every clip that is on none of them.
    ///
    /// A clip on no track gets a track of its own, named the way an editor
    /// names them (V1 at the bottom of the picture, Audio under it), whose id
    /// is the clip's own so it is the same track once it is written down.
    /// Picture ones sit over the written tracks, since a layer added to the
    /// picture lands on top of it, and sound ones under them.
    public var timelineTracks: [DocumentTrack] { trackLayout().tracks }

    /// The clips on a track, topmost first in the stack.
    public func clipIDs(onTrack id: UUID) -> [UUID] { trackLayout().clips[id] ?? [] }

    public func track(id: UUID) -> DocumentTrack? { timelineTracks.first { $0.id == id } }

    /// The track a clip is on. Anything inside a clip is on its clip's track.
    public func trackID(ofClip id: UUID) -> UUID? {
        guard let top = topLevelLayer(containing: id) else { return nil }
        return trackLayout().clips.first { $0.value.contains(top.id) }?.key
    }

    /// Whether this clip sits on a locked track.
    public func isClipOnLockedTrack(_ id: UUID) -> Bool {
        guard let track = trackID(ofClip: id).flatMap({ track(id: $0) }) else { return false }
        return track.isLocked
    }

    func topLevelLayer(containing id: UUID) -> Layer? {
        layers.first { layer in layer.id == id || layer.selfAndDescendants.contains { $0.id == id } }
    }

    /// The tracks, what is on each, and which audio track each clip's own
    /// sound is drawn on.
    struct TrackLayout {
        var tracks: [DocumentTrack] = []
        var clips: [UUID: [UUID]] = [:]
        /// Audio track to the clips whose linked sound sits on it.
        var linked: [UUID: [UUID]] = [:]
    }

    private func trackLayout() -> TrackLayout {
        let clipLayers = timelineClipLayers
        guard !clipLayers.isEmpty || !tracks.isEmpty else { return TrackLayout() }
        let written = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var clips: [UUID: [UUID]] = [:]
        var loosePicture: [Layer] = []
        var looseSound: [Layer] = []
        for layer in clipLayers {
            if let id = layer.trackID, let track = written[id], track.kind.accepts(layer.clipTrackKind) {
                clips[id, default: []].append(layer.id)
            } else if let own = written[layer.id], own.kind.accepts(layer.clipTrackKind) {
                // The track this clip was given when the tracks were first
                // written down carries its id; it goes home rather than making
                // a second track with the same id.
                clips[own.id, default: []].append(layer.id)
            } else if layer.clipTrackKind == .audio {
                looseSound.append(layer)
            } else {
                loosePicture.append(layer)
            }
        }
        var used = Set(tracks.map(\.name))
        // Picture is numbered from the BOTTOM, the way V1 is the bottom track
        // in every editor, so name them bottom first and put them back.
        var picture: [DocumentTrack] = []
        for layer in loosePicture.reversed() {
            let kind = layer.clipTrackKind
            let name = Self.freeTrackName(kind, used: used)
            used.insert(name)
            picture.insert(DocumentTrack(id: layer.id, name: name, kind: kind), at: 0)
            clips[layer.id] = [layer.id]
        }
        var ids = Set(tracks.map(\.id)).union(looseSound.map(\.id)).union(picture.map(\.id))

        // A clip's own sound, on an audio track under the picture. The bottom
        // picture's sound gets the first audio track, and a sound that would
        // overlap something already on a track goes down to the next, the way
        // V1's clips land on A1 and a picture-in-picture's on A2.
        let order = (picture + tracks).map(\.id)
        let layerByID = Dictionary(clipLayers.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var pictureTrack: [UUID: Int] = [:]
        for (track, members) in clips {
            let place = order.firstIndex(of: track) ?? 0
            for id in members { pictureTrack[id] = place }
        }
        let speakers = clipLayers.filter(\.hasLinkedSound).sorted { a, b in
            let ta = pictureTrack[a.id] ?? 0, tb = pictureTrack[b.id] ?? 0
            if ta != tb { return ta > tb }
            return (a.time?.inMS ?? 0) < (b.time?.inMS ?? 0)
        }
        var taken: [UUID: [Range<Int>]] = [:]
        for track in tracks where track.kind == .audio {
            taken[track.id] = (clips[track.id] ?? []).compactMap { layerByID[$0].map { clipSpan($0, movedTo: nil) } }
        }
        var linkedTracks: [DocumentTrack] = []
        var linked: [UUID: [UUID]] = [:]
        for clip in speakers {
            let span = clipSpan(clip, movedTo: nil)
            let candidates = tracks.filter { $0.kind == .audio } + linkedTracks
            let fits = candidates.first { track in
                !(taken[track.id] ?? []).contains { $0.lowerBound < span.upperBound && span.lowerBound < $0.upperBound }
            }
            let track: DocumentTrack
            if let fits {
                track = fits
            } else {
                let name = Self.freeTrackName(.audio, used: used)
                used.insert(name)
                track = DocumentTrack(id: Self.linkedSoundTrackID(forClip: clip.id, avoiding: ids),
                                      name: name, kind: .audio)
                ids.insert(track.id)
                linkedTracks.append(track)
            }
            taken[track.id, default: []].append(span)
            linked[track.id, default: []].append(clip.id)
        }

        var sound: [DocumentTrack] = []
        for layer in looseSound {
            let name = Self.freeTrackName(.audio, used: used)
            used.insert(name)
            sound.append(DocumentTrack(id: layer.id, name: name, kind: .audio))
            clips[layer.id] = [layer.id]
        }
        var all = picture + tracks + linkedTracks + sound
        // A video with no sound anywhere still has an Audio track waiting
        // under its picture, the way the mock's blank project does, so there is
        // somewhere to put the music before there is any.
        if !all.contains(where: { $0.kind == .audio }), clipLayers.contains(where: \.isClip) {
            all.append(DocumentTrack(id: Self.waitingAudioTrackID,
                                     name: Self.freeTrackName(.audio, used: used), kind: .audio))
        }
        // Each clip's linked sound, in the stack's order, topmost first.
        let stackOrder = Dictionary(clipLayers.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        for key in linked.keys {
            linked[key]?.sort { (stackOrder[$0] ?? 0) < (stackOrder[$1] ?? 0) }
        }
        return TrackLayout(tracks: all, clips: clips, linked: linked)
    }

    /// The empty Audio track a video with no sound shows under its picture.
    /// One fixed id, since a document only ever has one of it.
    public static let waitingAudioTrackID = UUID(uuid: (0x0A, 0xD1, 0x00, 0x00, 0x00, 0x00, 0x40, 0x00,
                                                        0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01))

    /// The id of the audio track a clip's sound is given when it needs one of
    /// its own: the clip's id with its first byte turned, so it is the same
    /// every time the timeline is read, and so it is the same track once the
    /// tracks are written down.
    static func linkedSoundTrackID(forClip id: UUID, avoiding used: Set<UUID>) -> UUID {
        var bytes = id.uuid
        let first = bytes.0
        for salt in UInt8(0x5A)...UInt8(0xFF) {
            bytes.0 = first ^ salt
            let candidate = UUID(uuid: bytes)
            if !used.contains(candidate) { return candidate }
        }
        return UUID()
    }

    // MARK: A clip's own sound

    /// Every audio track's linked clips at once, for drawing the whole timeline
    /// off one reading.
    public var linkedSoundsByTrack: [UUID: [UUID]] { trackLayout().linked }

    /// The clips whose own sound is drawn on this audio track, linked to them.
    public func linkedSoundClipIDs(onTrack id: UUID) -> [UUID] { trackLayout().linked[id] ?? [] }

    /// Whether a clip's own sound on this track runs anywhere in `span`.
    public func linkedSound(onTrack id: UUID, overlapsMS span: Range<Int>) -> Bool {
        linkedSoundClipIDs(onTrack: id).contains { clip in
            guard let layer = layers.first(where: { $0.id == clip }) else { return false }
            let theirs = clipSpan(layer, movedTo: nil)
            return theirs.lowerBound < span.upperBound && span.lowerBound < theirs.upperBound
        }
    }

    /// The audio track this clip's own sound is drawn on, or nil for a clip
    /// with no sound on it (none recorded, or taken off with Detach Audio).
    public func linkedSoundTrackID(ofClip id: UUID) -> UUID? {
        trackLayout().linked.first { $0.value.contains(id) }?.key
    }

    /// V1, V2...; Audio, Audio 2...; Captions, Captions 2...
    static func freeTrackName(_ kind: DocumentTrack.Kind, used: Set<String>) -> String {
        switch kind {
        case .video:
            var n = 1
            while used.contains("V\(n)") { n += 1 }
            return "V\(n)"
        case .audio, .captions:
            let base = kind.title
            if !used.contains(base) { return base }
            var n = 2
            while used.contains("\(base) \(n)") { n += 1 }
            return "\(base) \(n)"
        }
    }

    // MARK: Seen and heard

    /// The top level layers a switched off or outsoloed track takes out of the
    /// picture. Empty for a document whose tracks were never written down,
    /// since nobody can have switched one off.
    func layersOffScreenByTrack() -> Set<UUID> {
        guard !tracks.isEmpty else { return [] }
        let layout = trackLayout()
        let picture = layout.tracks.filter { $0.kind != .audio }
        let soloing = picture.contains(where: \.isSolo)
        var off: Set<UUID> = []
        for track in picture where track.isHidden || (soloing && !track.isSolo) {
            off.formUnion(layout.clips[track.id] ?? [])
        }
        return off
    }

    /// Every layer a muted or outsoloed track silences, whole subtrees
    /// included. A recording's own sound rides on its picture track, which is
    /// silenced only by a sound track being soloed.
    func layersSilencedByTrack() -> Set<UUID> {
        guard !tracks.isEmpty else { return [] }
        let layout = trackLayout()
        let soloing = layout.tracks.contains { $0.kind == .audio && $0.isSolo }
        // A clip's own sound is heard or not by the audio track it is drawn
        // on, never by its picture's track.
        let linkedClips = Set(layout.linked.values.joined())
        var silenced: Set<UUID> = []
        for track in layout.tracks {
            let off = track.kind == .audio
                ? track.isMuted || (soloing && !track.isSolo)
                : soloing
            guard off else { continue }
            for id in layout.clips[track.id] ?? [] where !linkedClips.contains(id) {
                guard let layer = layers.first(where: { $0.id == id }) else { continue }
                silenced.formUnion(layer.selfAndDescendants.map(\.id))
            }
            if track.kind == .audio { silenced.formUnion(layout.linked[track.id] ?? []) }
        }
        return silenced
    }
}

// MARK: - Changing the tracks

extension PhotonzDocument {

    /// Write down every track the timeline is showing, and every clip's track,
    /// so a change to one of them has something to change. Nothing moves and
    /// nothing is renamed: the timeline looks exactly as it did.
    public mutating func materializeTracks() {
        let layout = trackLayout()
        guard tracks != layout.tracks || layout.clips.contains(where: { track, ids in
            ids.contains { layer(id: $0)?.trackID != track }
        }) else { return }
        tracks = layout.tracks
        for (track, ids) in layout.clips {
            for id in ids where layer(id: id)?.trackID != track {
                updateLayer(id: id) { $0.trackID = track }
            }
        }
    }

    /// A new empty track. Picture and captions tracks land on top, sound at
    /// the bottom, unless a place is given.
    @discardableResult
    public mutating func addTrack(_ kind: DocumentTrack.Kind, at index: Int? = nil) -> UUID {
        materializeTracks()
        let track = DocumentTrack(name: Self.freeTrackName(kind, used: Set(tracks.map(\.name))),
                                  kind: kind)
        let place = index ?? (kind == .audio ? tracks.count : 0)
        tracks.insert(track, at: min(max(0, place), tracks.count))
        return track.id
    }

    /// Give a track a new name. Blank words are not a name.
    @discardableResult
    public mutating func renameTrack(_ id: UUID, to name: String) -> Bool {
        let words = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty, track(id: id) != nil else { return false }
        materializeTracks()
        guard let index = tracks.firstIndex(where: { $0.id == id }), tracks[index].name != words
        else { return false }
        tracks[index].name = words
        return true
    }

    /// Change one of a track's switches.
    public mutating func updateTrack(_ id: UUID, _ change: (inout DocumentTrack) -> Void) {
        guard track(id: id) != nil else { return }
        materializeTracks()
        guard let index = tracks.firstIndex(where: { $0.id == id }) else { return }
        change(&tracks[index])
    }

    /// Take a track away, and the clips on it with it.
    public mutating func deleteTrack(_ id: UUID) {
        guard track(id: id) != nil else { return }
        materializeTracks()
        let clips = Set(clipIDs(onTrack: id))
        // A clip whose sound is on this track keeps its picture and loses its
        // sound, the way deleting A1 takes a clip's audio and not its video.
        for clip in linkedSoundClipIDs(onTrack: id) {
            updateLayer(id: clip) { $0.soundDetached = true }
        }
        tracks.removeAll { $0.id == id }
        removeLayers(ids: clips)
        dropEmptyTrackGroups()
        refreshDuration()
    }

    // MARK: Clips between tracks

    /// Whether a clip may be put on a track, landing at `atInMS` (or where it
    /// already starts): the right kind of track, nothing locked, and nothing
    /// already there at that time.
    public func canPlace(_ clipID: UUID, onTrack trackID: UUID, atInMS: Int? = nil) -> Bool {
        guard let clip = layers.first(where: { $0.id == clipID }),
              let target = track(id: trackID), !target.isLocked,
              target.kind.accepts(clip.clipTrackKind),
              !isClipOnLockedTrack(clipID) else { return false }
        let span = clipSpan(clip, movedTo: atInMS)
        return !clipIDs(onTrack: trackID).contains { other in
            guard other != clipID, let layer = layers.first(where: { $0.id == other }) else { return false }
            let theirs = clipSpan(layer, movedTo: nil)
            return span.lowerBound < theirs.upperBound && theirs.lowerBound < span.upperBound
        }
    }

    /// The stretch a clip covers; a layer with no time of its own covers the
    /// whole document.
    private func clipSpan(_ layer: Layer, movedTo inMS: Int?) -> Range<Int> {
        guard let time = layer.time else { return 0..<max(1, documentDurationMS) }
        let moved = inMS.map { time.moved(toInMS: $0) } ?? time
        return moved.inMS..<max(moved.inMS + 1, moved.outMS)
    }

    /// Carry a clip onto another track.
    @discardableResult
    public mutating func moveClip(_ clipID: UUID, toTrack trackID: UUID) -> Bool {
        guard self.trackID(ofClip: clipID) != trackID, canPlace(clipID, onTrack: trackID) else { return false }
        materializeTracks()
        updateLayer(id: clipID) { $0.trackID = trackID }
        restackByTracks()
        return true
    }

    /// Carry a clip onto a new track of its kind, made at `index` in the
    /// timeline's list, which is what a drop between two tracks does.
    @discardableResult
    public mutating func moveClipToNewTrack(_ clipID: UUID, at index: Int) -> UUID? {
        guard let clip = layers.first(where: { $0.id == clipID }), trackID(ofClip: clipID) != nil,
              !isClipOnLockedTrack(clipID) else { return nil }
        let track = addTrack(clip.clipTrackKind, at: index)
        updateLayer(id: clipID) { $0.trackID = track }
        restackByTracks()
        return track
    }

    /// Put the stack in the order the tracks say: a clip on a lower track is
    /// further back in the picture, and clips on one track keep the order they
    /// had between them. Layers that are not on the timeline keep their places.
    mutating func restackByTracks() {
        let order = timelineTracks.map(\.id)
        let layout = trackLayout()
        var rank: [UUID: Int] = [:]
        for (track, ids) in layout.clips {
            let place = order.firstIndex(of: track) ?? 0
            for id in ids { rank[id] = place }
        }
        let slots = layers.indices.filter { rank[layers[$0].id] != nil }
        let moving = slots.map { layers[$0] }
        let sorted = moving.enumerated().sorted { a, b in
            let ra = rank[a.element.id] ?? 0, rb = rank[b.element.id] ?? 0
            return ra != rb ? ra > rb : a.offset < b.offset
        }.map(\.element)
        for (slot, layer) in zip(slots, sorted) { layers[slot] = layer }
    }

    // MARK: Groups

    /// Gather tracks into a new group, next to the topmost of them.
    @discardableResult
    public mutating func groupTracks(_ ids: [UUID]) -> UUID? {
        materializeTracks()
        let chosen = Set(ids)
        let picked = tracks.filter { chosen.contains($0.id) }
        guard let first = tracks.firstIndex(where: { chosen.contains($0.id) }) else { return nil }
        var used = Set(trackGroups.map(\.name))
        var n = 1
        while used.contains("Group \(n)") { n += 1 }
        used.insert("Group \(n)")
        let group = DocumentTrackGroup(name: "Group \(n)")
        trackGroups.append(group)
        var rest = tracks.filter { !chosen.contains($0.id) }
        let gathered = picked.map { track -> DocumentTrack in
            var track = track
            track.groupID = group.id
            return track
        }
        rest.insert(contentsOf: gathered, at: min(first, rest.count))
        tracks = rest
        dropEmptyTrackGroups()
        restackByTracks()
        return group.id
    }

    /// Let a group's tracks go. They stay where they are.
    public mutating func ungroupTracks(_ groupID: UUID) {
        for index in tracks.indices where tracks[index].groupID == groupID {
            tracks[index].groupID = nil
        }
        trackGroups.removeAll { $0.id == groupID }
    }

    /// Give a group a new name. Blank words are not a name.
    @discardableResult
    public mutating func renameTrackGroup(_ id: UUID, to name: String) -> Bool {
        let words = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty, let index = trackGroups.firstIndex(where: { $0.id == id }),
              trackGroups[index].name != words else { return false }
        trackGroups[index].name = words
        return true
    }

    private mutating func dropEmptyTrackGroups() {
        let inUse = Set(tracks.compactMap(\.groupID))
        trackGroups.removeAll { !inUse.contains($0.id) }
    }
}

// MARK: - Where a dragged clip lands

/// A track's row on screen, top to bottom, for working out a drop.
public struct TrackDropRow: Hashable, Sendable {
    public var trackID: UUID
    public var minY: CGFloat
    public var maxY: CGFloat

    public init(trackID: UUID, minY: CGFloat, maxY: CGFloat) {
        self.trackID = trackID
        self.minY = minY
        self.maxY = maxY
    }
}

/// Where a clip carried up or down the timeline lands: on a track, or on a new
/// one made between two (or past either end), the way a drop in the empty space
/// over the top track makes one in every editor.
public enum TrackDrop: Hashable, Sendable {
    case onto(UUID)
    case newTrack(at: Int)

    /// How close to the edge of a row counts as between two.
    public static let edgeBand: CGFloat = 4

    public static func resolve(y: CGFloat, rows: [TrackDropRow], edge: CGFloat = edgeBand) -> TrackDrop? {
        guard let first = rows.first, let last = rows.last else { return nil }
        if y < first.minY + edge { return .newTrack(at: 0) }
        if y > last.maxY - edge { return .newTrack(at: rows.count) }
        for (index, row) in rows.enumerated() {
            if y < row.minY { return .newTrack(at: index) }
            guard y <= row.maxY else { continue }
            if y < row.minY + edge { return .newTrack(at: index) }
            if y > row.maxY - edge { return .newTrack(at: index + 1) }
            return .onto(row.trackID)
        }
        return .newTrack(at: rows.count)
    }
}
