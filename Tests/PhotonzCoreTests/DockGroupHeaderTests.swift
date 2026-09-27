import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// The heading of a dock group as the mocks draw it (`.dgrp-h` in
/// `docs/design/mocks/shared/components/dock.css`): a small caps title, a chip
/// right beside it, and the group's own buttons at the far edge.
@Suite struct DockGroupHeaderTests {
    @Test func theTitleIsSetInCapitals() {
        #expect(DockGroupHeader.title("Properties") == "PROPERTIES")
        #expect(DockGroupHeader.title("Position & Size") == "POSITION & SIZE")
        #expect(DockGroupHeader.title("Library") == "LIBRARY")
    }

    @Test func theTitleIsTenPointWithTheMocksLetterSpacing() {
        // font-size:10px; letter-spacing:.09em
        #expect(DockGroupHeader.titleSize == 10)
        #expect(abs(DockGroupHeader.titleTracking - 0.9) < 0.0001)
    }

    @Test func aCountChipSaysTheCountAndNothingWhenThereIsNone() {
        #expect(DockGroupHeader.countChip(2) == "2")
        #expect(DockGroupHeader.countChip(12) == "12")
        // An empty state is empty: no "0" pill beside a group holding nothing.
        #expect(DockGroupHeader.countChip(0) == nil)
        #expect(DockGroupHeader.countChip(-1) == nil)
    }

    @Test func aWordChipIsTheWordAndNothingWhenItIsBlank() {
        #expect(DockGroupHeader.chip("Media") == "Media")
        #expect(DockGroupHeader.chip(" Title ") == "Title")
        #expect(DockGroupHeader.chip("   ") == nil)
        #expect(DockGroupHeader.chip(nil) == nil)
    }

    @Test func theHeadersAreNextsAndOnByDefaultThere() {
        let name = FeatureCatalog.dockHeadersFlag
        #expect(FeatureCatalog.defaultSettings(for: .next).isEnabled(name))
        #expect(!FeatureCatalog.flags(for: .current).contains { $0.name == name })
    }
}
