import Foundation

/// What a walk's `"offline": true` puts on the probe (`PlaytestSetup.offline`):
/// a sandbox profile that lets the app reach this Mac's own loopback, where
/// Ask's model servers and the walk harness listen, and nothing beyond it.
/// The probe applies it to itself once, and every program it starts after
/// inherits it, so the model servers are as cut off as the app.
public enum PlaytestOffline {
    public static let profile = """
        (version 1)
        (allow default)
        (deny network-outbound (remote ip))
        (allow network-outbound (remote ip "localhost:*"))
        """
}
