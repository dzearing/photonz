import Darwin
import Dispatch
import Foundation
import PhotonzRender

/// Giving memory back to the Mac, for real, when Photonz no longer needs it.
///
/// Freeing a picture is not the same as the Mac getting it back: the
/// allocator keeps big freed blocks for reuse and they still count against
/// Photonz in Activity Monitor. On 2026-10-23, with every window closed, 224
/// of the probe's 425 MB was exactly that ("MALLOC_LARGE (empty)" in
/// `vmmap`). So a window closing hands the pages back, and memory running
/// short on the Mac empties the render caches too.
@MainActor
enum MemoryRelief {

    private static var pressureWatch: DispatchSourceMemoryPressure?
    private static var pendingRelief = false

    /// Hands freed pages back to the system, a moment from now so whatever is
    /// being let go this turn has actually gone. Several calls in a row are
    /// one relief.
    static func giveBackSoon() {
        guard !pendingRelief else { return }
        pendingRelief = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            MainActor.assumeIsolated {
                pendingRelief = false
                giveBackNow()
            }
        }
    }

    static func giveBackNow() {
        malloc_zone_pressure_relief(nil, 0)
    }

    /// Photonz's physical footprint: the number Activity Monitor shows.
    nonisolated static func footprintBytes() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.phys_footprint) : 0
    }

    /// Listens for the Mac running short of memory, once per launch.
    static func watchForPressure(openEditors: @escaping @MainActor () -> [EditorState]) {
        guard pressureWatch == nil else { return }
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated {
                DocumentRenderer.clearSharedCaches()
                for editor in openEditors() { editor.letGoOfCaches() }
                giveBackNow()
            }
        }
        source.resume()
        pressureWatch = source
    }
}
