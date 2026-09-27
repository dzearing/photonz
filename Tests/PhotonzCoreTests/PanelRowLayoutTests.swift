import CoreGraphics
import PhotonzCore
import Testing

/// Every panel row reads like the mock's `.irow` (`inspector.css`): a small
/// faint label in a 76pt column and the control beside it, dropping under the
/// label only when the control cannot fit (task
/// `panel-row-labels-are-one-size-and-sit-in-one-col`, 2026-09-27).
struct PanelRowLayoutTests {
    // MARK: - The mock's numbers

    @Test func theLabelColumnIsTheMocks() {
        // `.irow{grid-template-columns:var(--rl-w,76px) 1fr;gap:var(--s3)}`
        #expect(PanelRowLayout.labelColumn == 76)
        #expect(PanelRowLayout.labelGap == 12)
        // `.irow>.rl{color:var(--faint);font-size:10.5px}`
        #expect(PanelRowLayout.labelSize == 10.5)
    }

    @Test func theControlStartsWhereTheColumnEnds() {
        #expect(PanelRowLayout.controlLeading == 88)
    }

    // MARK: - What a control gets

    @Test func theControlGetsTheRowLessTheColumnAndTheGap() {
        // The default dock: 290pt, less the panel's 14pt margin both sides.
        #expect(PanelRowLayout.controlWidth(rowWidth: 262) == 174)
        // The narrowest dock, 220pt.
        #expect(PanelRowLayout.controlWidth(rowWidth: 192) == 104)
    }

    @Test func aRowNarrowerThanTheColumnLeavesTheControlNothingRatherThanLessThanNothing() {
        #expect(PanelRowLayout.controlWidth(rowWidth: 40) == 0)
    }

    // MARK: - Beside or under

    @Test func aControlThatFitsSitsBesideItsLabel() {
        #expect(PanelRowLayout.sitsBeside(controlMinimum: 104, rowWidth: 192))
        #expect(PanelRowLayout.sitsBeside(controlMinimum: 60, rowWidth: 262))
    }

    @Test func aControlThatWouldBeCutDropsUnderItsLabel() {
        #expect(!PanelRowLayout.sitsBeside(controlMinimum: 104.5, rowWidth: 192))
        // A shadow's slider inside Effects, stepped in 24pt, at the narrowest
        // dock: a 60pt track and a 56pt field do not fit in 80pt.
        #expect(!PanelRowLayout.sitsBeside(controlMinimum: 116, rowWidth: 168))
    }

    // MARK: - Where it ships

    @Test func itShipsOnByDefaultInNextOnly() {
        #expect(FeatureCatalog.defaultSettings(for: .next)
            .isEnabled(FeatureCatalog.panelRowsInOneColumnFlag))
        #expect(!FeatureCatalog.flags(for: .current)
            .contains { $0.name == FeatureCatalog.panelRowsInOneColumnFlag })
    }
}
