// A profile of each long main thread pass on its own, for when Instruments
// will not connect (developer mode off on the walk Mac, 2026-11-21). Probe
// only, and off unless `Scripts/perf/pass-profile.sh` has made its folder: it
// samples the main thread's stack every half millisecond and keeps the samples
// that fall inside each pass of 6 ms or more the main thread meter reports,
// labelled with the speed walk's edit, so an edit's three or four passes can
// be told apart (`a-long-edit-with-transitions-plays-scrubs-and-ed`, pass 24).
#if PHOTONZ_PLAYTEST
import Darwin
import Foundation
import QuartzCore
import os

/// Samples the main thread's stack by frame pointers from a thread of its
/// own. `@unchecked Sendable`: its buffers are behind `lock`, apart from the
/// stack buffer, which only the sampling thread touches.
final class PassSampler: @unchecked Sendable {
    static let shared = PassSampler()
    /// The folder `pass-profile.sh` makes for the run and reads afterwards.
    static let folder = "/tmp/photonz-pass-sampler"
    static var isOn: Bool { FileManager.default.fileExists(atPath: folder + "/on") }

    private struct Sample { var t: Double; var pcs: [UInt64] }
    private let lock = OSAllocatedUnfairLock()
    private var ring: [Sample] = []
    private var kept: [(label: String, start: Double, ms: Double, samples: [Sample])] = []
    private var mainThread: thread_t = 0
    private var stackLow: UInt64 = 0
    private var stackHigh: UInt64 = 0
    private var started = false
    /// What the walk is timing now; a pass is kept only while there is one.
    /// Written and read on the main thread only.
    nonisolated(unsafe) static var label = ""
    /// Every pass is kept, not only those of 6 ms or more: a frame of the
    /// timeline's speed measure is several shorter passes (2026-11-21).
    nonisolated(unsafe) static var keepsEveryPass = false

    /// Starts sampling, once, when the folder says to. Called on the main
    /// thread, which is the thread it samples.
    @MainActor func startIfOn() {
        guard Self.isOn, !started else { return }
        started = true
        mainThread = mach_thread_self()
        let me = pthread_self()
        stackHigh = UInt64(UInt(bitPattern: pthread_get_stackaddr_np(me)))
        stackLow = stackHigh - UInt64(pthread_get_stacksize_np(me))
        let thread = Thread { [self] in self.run() }
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    private func run() {
        while true {
            usleep(500)
            guard let pcs = walk() else { continue }
            let t = CACurrentMediaTime()
            lock.withLock {
                ring.append(Sample(t: t, pcs: pcs))
                if ring.count > 8000 { ring.removeFirst(4000) }
            }
        }
    }

    /// Nothing in here may allocate while the main thread is stopped: it may
    /// hold the allocator's lock.
    private let buffer = UnsafeMutablePointer<UInt64>.allocate(capacity: 256)

    private func walk() -> [UInt64]? {
        let mask: UInt64 = 0x0000_7FFF_FFFF_FFFF
        var state = arm_thread_state64_t()
        var count = mach_msg_type_number_t(MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<natural_t>.size)
        var n = 0
        guard thread_suspend(mainThread) == KERN_SUCCESS else { return nil }
        let kr = withUnsafeMutablePointer(to: &state) {
            $0.withMemoryRebound(to: natural_t.self, capacity: Int(count)) {
                thread_get_state(mainThread, ARM_THREAD_STATE64, $0, &count)
            }
        }
        if kr == KERN_SUCCESS {
            buffer[0] = state.__pc & mask
            buffer[1] = state.__lr & mask
            n = 2
            var fp = state.__fp
            while n < 256, fp >= stackLow, fp + 16 <= stackHigh, fp & 7 == 0 {
                guard let p = UnsafePointer<UInt64>(bitPattern: UInt(fp)) else { break }
                let next = p[0]
                let ret = p[1] & mask
                if ret == 0 { break }
                buffer[n] = ret
                n += 1
                if next <= fp { break }
                fp = next
            }
        }
        thread_resume(mainThread)
        guard n > 0 else { return nil }
        return Array(UnsafeBufferPointer(start: buffer, count: n))
    }

    /// The main thread meter says a pass of 6 ms or more just ended.
    func passEnded(start: Double, end: Double) {
        guard started else { return }
        let label = Self.label
        guard !label.isEmpty else { return }
        lock.withLock {
            let inside = ring.filter { $0.t >= start && $0.t <= end }
            if kept.count < 12_000 { kept.append((label, start, (end - start) * 1000, inside)) }
        }
    }

    /// Writes every kept pass and its samples (return addresses, hex) to
    /// `passes.txt` in the folder, with this process's id on the first line
    /// so the script can name them while the probe is still up.
    func dump() {
        let path = Self.folder + "/passes.txt"
        guard started else { return }
        let taken = lock.withLock { () -> [(label: String, start: Double, ms: Double, samples: [Sample])] in
            defer { kept.removeAll() }
            return kept
        }
        var out = "pid \(getpid())\n"
        for pass in taken {
            out += String(format: "PASS %@ | %.1f | %.4f | %d\n", pass.label, pass.ms, pass.start, pass.samples.count)
            for s in pass.samples { out += s.pcs.map { String($0, radix: 16) }.joined(separator: " ") + "\n" }
        }
        try? out.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
#endif
