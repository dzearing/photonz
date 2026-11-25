import Foundation

// How loud a mix gets, kept between edits
// (`the-timeline-of-an-hour-long-edit-scrolls-zooms`).
//
// `AudioHeadroom` is read off every twenty milliseconds of sound there is. The
// player asks after every edit, because an edit can change how loud the mix
// gets, and on an hour of three tracks the whole walk was 12 ms of the main
// thread each time: a blade while it played asked twice and held it 23 ms
// (measured 2026-11-25). So what every bucket adds up to is kept, and an edit
// walks only the stretches whose sounds are not the ones that were there.

/// The loudest a mix gets, worked out again only where it changed.
public struct AudioHeadroomReader: Sendable {

    private var plan: [AudioMixSegment] = []
    private var shapes: [UUID: Waveform] = [:]
    /// What every bucket adds up to, from the document's start.
    private var sums: [Double] = []
    private var reading = AudioHeadroom(peak: 0, atMS: 0, assumedFiles: 0)

    /// How many buckets the last reading worked out again, for tests.
    private(set) var bucketsRead = 0

    public init() {}

    /// The loudest the whole mix ever gets, and where.
    public mutating func reading(of mix: [AudioMixSegment], peaks: [UUID: Waveform]) -> AudioHeadroom {
        bucketsRead = 0
        // Both are cheap where nothing was written since: an array compares
        // equal to itself without looking inside.
        guard mix != plan || peaks != shapes else { return reading }
        let stale = changed(in: mix, peaks: peaks)
        plan = mix
        shapes = peaks
        read(stale)
        var loudest: Double = 0
        var loudestBucket = 0
        sums.withUnsafeBufferPointer { sums in
            for bucket in sums.indices where sums[bucket] > loudest {
                loudest = sums[bucket]
                loudestBucket = bucket
            }
        }
        var assumed: Set<UUID> = []
        for segment in mix where segment.lengthMS > 0 && shape(of: segment) == nil { assumed.insert(segment.sound.id) }
        reading = AudioHeadroom(peak: loudest, atMS: loudestBucket * Waveform.bucketMS, assumedFiles: assumed.count)
        return reading
    }

    // MARK: - What changed

    /// The buckets under every segment that is in one plan and not the other,
    /// or plays a file whose shape is not the one read: in order, none of them
    /// touching.
    private func changed(in mix: [AudioMixSegment], peaks: [UUID: Waveform]) -> [ClosedRange<Int>] {
        // An edit touches a few segments in a list of hundreds, nearly always
        // side by side, so the ends that are the same are passed over first.
        var start = 0
        let shorter = min(mix.count, plan.count)
        while start < shorter, mix[start] == plan[start] { start += 1 }
        var end = 0
        while end < shorter - start, mix[mix.count - 1 - end] == plan[plan.count - 1 - end] { end += 1 }
        var count: [AudioMixSegment: Int] = [:]
        for segment in mix[start..<(mix.count - end)] { count[segment, default: 0] += 1 }
        for segment in plan[start..<(plan.count - end)] { count[segment, default: 0] -= 1 }
        var ranges = count.compactMap { $0.value == 0 ? nil : Self.buckets(of: $0.key) }
        if peaks != shapes {
            let moved = Set(peaks.keys).union(shapes.keys).filter { peaks[$0] != shapes[$0] }
            for segment in mix where moved.contains(segment.sound.id) {
                if let range = Self.buckets(of: segment) { ranges.append(range) }
            }
        }
        ranges.sort { $0.lowerBound < $1.lowerBound }
        var joined: [ClosedRange<Int>] = []
        for range in ranges {
            if let last = joined.last, range.lowerBound <= last.upperBound + 1 {
                joined[joined.count - 1] = last.lowerBound...max(last.upperBound, range.upperBound)
            } else {
                joined.append(range)
            }
        }
        return joined
    }

    /// The buckets a segment sounds in, or nil where it sounds in none.
    private static func buckets(of segment: AudioMixSegment) -> ClosedRange<Int>? {
        guard segment.lengthMS > 0, segment.endMS > 0 else { return nil }
        let first = max(0, segment.startMS) / Waveform.bucketMS
        return first...max(first, (segment.endMS - 1) / Waveform.bucketMS)
    }

    private func shape(of segment: AudioMixSegment) -> Waveform? {
        guard let shape = shapes[segment.sound.id], !shape.isEmpty else { return nil }
        return shape
    }

    // MARK: - Reading it again

    /// Work these buckets out again, from everything in the plan that sounds
    /// in them.
    private mutating func read(_ stale: [ClosedRange<Int>]) {
        guard let last = stale.last else { return }
        if sums.count <= last.upperBound {
            sums.append(contentsOf: repeatElement(0, count: last.upperBound + 1 - sums.count))
        }
        for range in stale {
            bucketsRead += range.count
            for bucket in range { sums[bucket] = 0 }
        }
        for segment in plan {
            guard let sounds = Self.buckets(of: segment) else { continue }
            let shape = shape(of: segment)
            for range in stale where range.overlaps(sounds) {
                add(segment, shape: shape, over: range.clamped(to: sounds))
            }
        }
    }

    /// One segment added to the buckets given: its level at the start of each,
    /// or at its own start in the bucket it begins inside.
    private mutating func add(_ segment: AudioMixSegment, shape: Waveform?, over range: ClosedRange<Int>) {
        let ramps = segment.ramps
        let speed = Double(max(1, segment.speedPercent)) / 100
        // The ramps are in order, so the one a bucket is under is the one
        // before it was under or a later one.
        var ramp = 0
        sums.withUnsafeMutableBufferPointer { sums in
            for bucket in range {
                let ms = max(segment.startMS, bucket * Waveform.bucketMS)
                var gain: Double = 1
                if let first = ramps.first {
                    if ms <= first.fromMS {
                        gain = first.fromGain
                    } else {
                        while ramp + 1 < ramps.count, ramps[ramp + 1].fromMS <= ms { ramp += 1 }
                        gain = ramps[ramp].gain(atMS: ms)
                    }
                }
                guard gain > 0 else { continue }
                guard let shape else {
                    sums[bucket] += gain
                    continue
                }
                let sourceMS = segment.sourceInMS + Int(Double(max(0, ms - segment.startMS)) * speed)
                let level = gain * Double(shape.peak(atSourceMS: sourceMS))
                if level > 0 { sums[bucket] += level }
            }
        }
    }
}
