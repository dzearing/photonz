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
    /// Every other thread's stack at one moment the main thread stood still,
    /// so a pass spent waiting says who it waited for.
    private struct Others { var t: Double; var threads: [(id: UInt64, running: Bool, pcs: [UInt64])] }
    private let lock = OSAllocatedUnfairLock()
    private var ring: [Sample] = []
    private var othersRing: [Others] = []
    private var keptOthers: [(label: String, start: Double, ms: Double, main: [Sample], others: [Others])] = []
    private var othersWritten = false
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
        var last: [UInt64] = []
        while true {
            usleep(500)
            guard let pcs = walk() else { continue }
            let t = CACurrentMediaTime()
            // Standing where it stood half a millisecond ago is a wait: see
            // what every other thread is doing meanwhile.
            let others = pcs == last && !Self.label.isEmpty ? othersNow() : nil
            last = pcs
            lock.withLock {
                ring.append(Sample(t: t, pcs: pcs))
                if ring.count > 8000 { ring.removeFirst(4000) }
                if let others {
                    othersRing.append(Others(t: t, threads: others))
                    if othersRing.count > 400 { othersRing.removeFirst(200) }
                }
            }
        }
    }

    /// Nothing in here may allocate while the main thread is stopped: it may
    /// hold the allocator's lock.
    private let buffer = UnsafeMutablePointer<UInt64>.allocate(capacity: 256)

    private func walk() -> [UInt64]? {
        let n = walk(mainThread, low: stackLow, high: stackHigh, limit: 256)
        return n > 0 ? Array(UnsafeBufferPointer(start: buffer, count: n)) : nil
    }

    /// Fills `buffer` with a thread's return addresses, leaf first, and says
    /// how many.
    private func walk(_ thread: thread_t, low: UInt64, high: UInt64, limit: Int) -> Int {
        let mask: UInt64 = 0x0000_7FFF_FFFF_FFFF
        var state = arm_thread_state64_t()
        var count = mach_msg_type_number_t(MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<natural_t>.size)
        var n = 0
        guard thread_suspend(thread) == KERN_SUCCESS else { return 0 }
        let kr = withUnsafeMutablePointer(to: &state) {
            $0.withMemoryRebound(to: natural_t.self, capacity: Int(count)) {
                thread_get_state(thread, ARM_THREAD_STATE64, $0, &count)
            }
        }
        if kr == KERN_SUCCESS {
            buffer[0] = state.__pc & mask
            buffer[1] = state.__lr & mask
            n = 2
            var fp = state.__fp
            while n < limit, fp >= low, fp + 16 <= high, fp & 7 == 0 {
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
        thread_resume(thread)
        return n
    }

    /// Every thread but this one and the main one, up to 48 frames deep, and
    /// whether it was running. Reads a stack only inside the bounds pthread
    /// gives for it, with the thread stopped.
    private func othersNow() -> [(id: UInt64, running: Bool, pcs: [UInt64])] {
        var list: thread_act_array_t?
        var count: mach_msg_type_number_t = 0
        guard task_threads(mach_task_self_, &list, &count) == KERN_SUCCESS, let list else { return [] }
        let me = pthread_mach_thread_np(pthread_self())
        var out: [(id: UInt64, running: Bool, pcs: [UInt64])] = []
        out.reserveCapacity(Int(count))
        for i in 0 ..< Int(count) {
            let thread = list[i]
            defer { mach_port_deallocate(mach_task_self_, thread) }
            guard thread != mainThread, thread != me, let p = pthread_from_mach_thread_np(thread) else { continue }
            var basic = thread_basic_info()
            var basicCount = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<natural_t>.size)
            let asked = withUnsafeMutablePointer(to: &basic) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(basicCount)) {
                    thread_info(thread, thread_flavor_t(THREAD_BASIC_INFO), $0, &basicCount)
                }
            }
            let running = asked == KERN_SUCCESS && basic.run_state == TH_STATE_RUNNING
            let high = UInt64(UInt(bitPattern: pthread_get_stackaddr_np(p)))
            let low = high - UInt64(pthread_get_stacksize_np(p))
            let n = walk(thread, low: low, high: high, limit: 48)
            if n > 0 { out.append((UInt64(thread), running, Array(UnsafeBufferPointer(start: buffer, count: n)))) }
        }
        vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: list)),
                      vm_size_t(Int(count) * MemoryLayout<thread_act_t>.stride))
        return out
    }

    /// The main thread meter says a pass of 6 ms or more just ended.
    func passEnded(start: Double, end: Double) {
        guard started else { return }
        let label = Self.label
        guard !label.isEmpty else { return }
        lock.withLock {
            let inside = ring.filter { $0.t >= start && $0.t <= end }
            if end - start >= 0.014 {
                keptOthers.append((label, start, (end - start) * 1000, inside,
                                   othersRing.filter { $0.t >= start && $0.t <= end }))
            }
            if kept.count < 40_000 { kept.append((label, start, (end - start) * 1000, inside)) }
        }
    }

    /// Writes what every thread was doing in each pass of 14 ms or more to
    /// `others.txt`, added to by each measure of the walk.
    private func dumpOthers() {
        let taken = lock.withLock { () -> [(label: String, start: Double, ms: Double, main: [Sample], others: [Others])] in
            defer { keptOthers.removeAll() }
            return keptOthers
        }
        func hex(_ pcs: [UInt64]) -> String { pcs.map { String($0, radix: 16) }.joined(separator: " ") }
        var out = ""
        for pass in taken {
            out += String(format: "PASS %@ | %.1f | %.4f | %d\n", pass.label, pass.ms, pass.start, pass.main.count)
            for s in pass.main { out += String(format: "M %.1f ", (s.t - pass.start) * 1000) + hex(s.pcs) + "\n" }
            for look in pass.others {
                for thread in look.threads {
                    out += String(format: "T %.1f %llu %@ ", (look.t - pass.start) * 1000, thread.id,
                                  thread.running ? "run" : "wait") + hex(thread.pcs) + "\n"
                }
            }
        }
        let path = Self.folder + "/others.txt"
        if othersWritten, let file = FileHandle(forWritingAtPath: path) {
            file.seekToEndOfFile()
            file.write(Data(out.utf8))
            try? file.close()
        } else {
            try? out.write(toFile: path, atomically: true, encoding: .utf8)
            othersWritten = true
        }
    }

    /// Writes every kept pass and its samples (return addresses, hex) to
    /// `passes.txt` in the folder, with this process's id on the first line
    /// so the script can name them while the probe is still up.
    func dump() {
        let path = Self.folder + "/passes.txt"
        guard started else { return }
        dumpOthers()
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
