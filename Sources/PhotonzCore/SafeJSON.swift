import CoreGraphics
import Foundation

/// Writes a reading out as JSON without ever taking the app down.
///
/// `JSONSerialization.data(withJSONObject:)` answers a NaN, an infinity or a
/// value JSON has no form for by raising an Objective-C exception, and `try?`
/// does not catch one. Raised inside a Swift task it unwinds through the
/// task's frames and leaves the thread's executor record pointing at a dead
/// one, so the app crashes at the next main-actor check, far from the cause
/// (2026-10-02: a recording drill wrote NaN and the probe died in
/// `MenuBarArranger`). Here a number that is not finite is written as `null`,
/// and anything else JSON cannot hold gives no data at all.
public enum SafeJSON {
    public static func data(from object: Any,
                            options: JSONSerialization.WritingOptions = []) -> Data? {
        let clean = sanitized(object)
        guard JSONSerialization.isValidJSONObject(clean) else { return nil }
        return try? JSONSerialization.data(withJSONObject: clean, options: options)
    }

    /// `object` with every NaN and infinity, at any depth, replaced by null.
    /// Everything else is handed back exactly as it came.
    public static func sanitized(_ object: Any) -> Any {
        if let dictionary = object as? [String: Any] { return dictionary.mapValues(sanitized) }
        if let array = object as? [Any] { return array.map(sanitized) }
        if let number = object as? Double, !number.isFinite { return NSNull() }
        if let number = object as? CGFloat, !number.isFinite { return NSNull() }
        if let number = object as? Float, !number.isFinite { return NSNull() }
        return object
    }
}
