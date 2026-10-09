// Times a walk as macOS schedules the app a person is using, not as it
// schedules an app left in the background. Probe-only, like the rest of the
// harness.
//
// A walk keeps the probe behind every other app so the person at the Mac can
// work (`holdTheFront`), and RunningBoard gives such an app the darwin role
// UI_NON_FOCAL. The app in front holds UI_FOCAL. The role decides which cores a
// main thread wakes on: measured 2026-10-08 with Time Profiler on
// `undo-redo-cost-walk`, every Undo and Redo in a background probe ran its
// first 26 to 36ms on an efficiency core before it moved to a performance
// core, and every one in a probe held in front (`setup.front`) ran on a
// performance core from its first sample. Same build, same walk, ten presses
// each, run twice:
//
//   background, a timer firing every 50ms   u75 r68 u62 r51 u65 r57 u63 r74 u67 r72
//   the same, holding UI_FOCAL              u42 r49 u44 r45 u44 r44 u47 r57 u45 r56
//
// The timer alone moved nothing, so it is the role and not a warm thread. A
// person's Command Z reaches an app holding UI_FOCAL, so that is the role a
// walk times under. This was the gap a runner could not explain on 2026-10-07:
// the same Undo read slower after the walk sat idle a beat before the press,
// which is how long a background thread takes to be put on a slow core.
//
// RunningBoard sets the role back whenever it reconsiders the app (once at
// launch, in that run), so the walk takes it again before every step.
#if PHOTONZ_PLAYTEST
import Darwin

@MainActor
final class PlaytestSchedulingRole {
    static let shared = PlaytestSchedulingRole()

    // Private in the SDK (`PRIVATE` in xnu's sys/resource.h), stable since
    // macOS 10.12: `setpriority(PRIO_DARWIN_ROLE, 0, PRIO_DARWIN_ROLE_UI_FOCAL)`
    // on its own process is what `taskpolicy` and RunningBoard use.
    private static let darwinRole: Int32 = 6
    private static let uiFocal: Int32 = 1

    /// Takes the front app's role when the probe does not already hold it.
    /// True when it holds it afterwards.
    @discardableResult
    func takeTheFrontAppsRole() -> Bool {
        if getpriority(Self.darwinRole, 0) == Self.uiFocal { return true }
        _ = setpriority(Self.darwinRole, 0, Self.uiFocal)
        return getpriority(Self.darwinRole, 0) == Self.uiFocal
    }
}
#endif
