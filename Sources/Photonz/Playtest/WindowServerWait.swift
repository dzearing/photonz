// Time the main thread spends waiting for the window server to take a frame,
// so the main thread meter can leave it out of a pass.
//
// At the end of a pass Core Animation hands the frame to the window server,
// and when the window server is behind (another app keeping it busy), that
// hand-over blocks until it catches up. The main thread does no work in that
// time: it sits in a `mach_msg` called from QuartzCore. Found 2026-11-21 on
// `history-filter-switch-speed-walk`, red every run on a Mac whose window
// server sat at 45% CPU with the probe not even running: its one long pass,
// 24.8 ms, was all `CA::Context::commit_transaction` blocked in
// `mach_msg2_trap` (Scripts/perf/pass-profile.sh), while the filter switch's
// own work was a 6 ms pass before it. A walk's budget is for the app's main
// thread WORK, so that wait is left out and said in the note, the way the
// menu bar's answer to a resting pointer is (`takeWalkMouseDown`).
//
// Narrow on purpose: only a wait whose stack goes straight from the kernel's
// message call into QuartzCore counts. A wait on a file, a lock, a queue or
// an XPC reply is the app's and still counts in full.
//
// Probe builds only.
#if PHOTONZ_PLAYTEST
import Darwin
import Foundation
import MachO
import QuartzCore
import os

/// Samples the main thread every millisecond while a pass is open and adds
/// up the time it found it blocked handing a frame to the window server.
/// `@unchecked Sendable`: its counters are behind `lock`; the image ranges
/// are written once before the thread starts and only read after.
final class WindowServerWait: @unchecked Sendable {
    static let shared = WindowServerWait()

    private struct State {
        var passOpen = false
        var waited: Double = 0
    }
    private let lock = OSAllocatedUnfairLock(initialState: State())
    private var mainThread: thread_t = 0
    private var stackLow: UInt64 = 0
    private var stackHigh: UInt64 = 0
    private var kernel: Range<UInt64> = 0..<0
    private var quartzCore: Range<UInt64> = 0..<0
    private var started = false

    /// Starts watching, once. Called on the main thread, which is the thread
    /// it watches.
    @MainActor func start() {
        guard !started else { return }
        guard let kernel = Self.text(of: "/libsystem_kernel.dylib"),
              let quartzCore = Self.text(of: "/QuartzCore") else { return }
        started = true
        self.kernel = kernel
        self.quartzCore = quartzCore
        mainThread = mach_thread_self()
        let me = pthread_self()
        stackHigh = UInt64(UInt(bitPattern: pthread_get_stackaddr_np(me)))
        stackLow = stackHigh - UInt64(pthread_get_stacksize_np(me))
        let thread = Thread { [self] in self.run() }
        thread.qualityOfService = .userInteractive
        thread.name = "photonz.window-server-wait"
        thread.start()
    }

    /// The main thread meter says whether a pass is open: only then is the
    /// main thread worth looking at, since between passes it is asleep in
    /// the run loop's own wait.
    func passIsOpen(_ open: Bool) {
        lock.withLock { $0.passOpen = open }
    }

    /// The waiting found since this was last asked, and the count starts
    /// again.
    func take() -> Double {
        lock.withLock { state in
            defer { state.waited = 0 }
            return state.waited
        }
    }

    private func run() {
        var last = CACurrentMediaTime()
        while true {
            usleep(1000)
            let now = CACurrentMediaTime()
            defer { last = now }
            guard lock.withLock({ $0.passOpen }), isWaitingOnTheWindowServer() else { continue }
            // A late wake of this thread is not a longer wait: at most a few
            // samples' worth is put down for one sighting.
            let spent = min(now - last, 0.003)
            lock.withLock { state in
                if state.passOpen { state.waited += spent }
            }
        }
    }

    /// Room for the frames read while the main thread is stopped: nothing
    /// may allocate then, since it may hold the allocator's lock.
    private let frames = UnsafeMutablePointer<UInt64>.allocate(capacity: 12)

    private func isWaitingOnTheWindowServer() -> Bool {
        // Asking a thread's run state does not stop it, so a running main
        // thread costs nothing more than this.
        var info = thread_basic_info()
        var infoCount = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<natural_t>.size)
        let read = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) {
                thread_info(mainThread, thread_flavor_t(THREAD_BASIC_INFO), $0, &infoCount)
            }
        }
        guard read == KERN_SUCCESS, info.run_state == TH_STATE_WAITING else { return false }

        let mask: UInt64 = 0x0000_7FFF_FFFF_FFFF
        var state = arm_thread_state64_t()
        var count = mach_msg_type_number_t(MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<natural_t>.size)
        var n = 0
        guard thread_suspend(mainThread) == KERN_SUCCESS else { return false }
        let kr = withUnsafeMutablePointer(to: &state) {
            $0.withMemoryRebound(to: natural_t.self, capacity: Int(count)) {
                thread_get_state(mainThread, ARM_THREAD_STATE64, $0, &count)
            }
        }
        if kr == KERN_SUCCESS {
            frames[0] = state.__pc & mask
            frames[1] = state.__lr & mask
            n = 2
            var fp = state.__fp
            while n < 12, fp >= stackLow, fp + 16 <= stackHigh, fp & 7 == 0 {
                guard let p = UnsafePointer<UInt64>(bitPattern: UInt(fp)) else { break }
                let next = p[0]
                let ret = p[1] & mask
                if ret == 0 { break }
                frames[n] = ret
                n += 1
                if next <= fp { break }
                fp = next
            }
        }
        thread_resume(mainThread)
        // Stopped in the kernel's message call, and the first caller out of
        // the kernel's own library is QuartzCore.
        guard n > 1, kernel.contains(frames[0]) else { return false }
        for i in 1..<n where !kernel.contains(frames[i]) {
            return quartzCore.contains(frames[i])
        }
        return false
    }

    /// Where a loaded library's code lies in memory.
    private static func text(of suffix: String) -> Range<UInt64>? {
        for i in 0..<_dyld_image_count() {
            guard let name = _dyld_get_image_name(i), String(cString: name).hasSuffix(suffix),
                  let header = _dyld_get_image_header(i) else { continue }
            var size: UInt = 0
            let start = header.withMemoryRebound(to: mach_header_64.self, capacity: 1) {
                getsegmentdata($0, "__TEXT", &size)
            }
            guard let start, size > 0 else { return nil }
            let low = UInt64(UInt(bitPattern: start))
            return low..<(low + UInt64(size))
        }
        return nil
    }
}
#endif
