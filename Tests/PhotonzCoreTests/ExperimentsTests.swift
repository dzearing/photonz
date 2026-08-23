import Foundation
import Testing
@testable import PhotonzCore

@Suite("Release")
struct ReleaseTests {

    @Test func publicIsTheDefault() {
        #expect(Release.default == .current)
        #expect(Release.current.isDefault)
        #expect(!Release.next.isDefault)
    }

    @Test func rawValuesAreStableStorageIdentifiers() {
        // Persisted in UserDefaults — renaming these silently resets people.
        #expect(Release.current.rawValue == "current")
        #expect(Release.next.rawValue == "next")
    }

    @Test func everyReleaseHasCopyAndItsOwnNamespace() {
        var namespaces: Set<String> = []
        for release in Release.allCases {
            #expect(!release.title.isEmpty)
            #expect(!release.tagline.isEmpty)
            namespaces.insert(release.storageNamespace)
        }
        #expect(namespaces.count == Release.allCases.count)
    }

    @Test func roundTripsThroughCodable() throws {
        let data = try JSONEncoder().encode(Release.next)
        #expect(try JSONDecoder().decode(Release.self, from: data) == .next)
    }
}

@Suite("FeatureParameterValue")
struct FeatureParameterValueTests {

    @Test func reportsItsKind() {
        #expect(FeatureParameterValue.number(3).kind == .number)
        #expect(FeatureParameterValue.string("hi").kind == .string)
        #expect(FeatureParameterValue.boolean(true).kind == .boolean)
        #expect(FeatureParameterValue.enumeration(cases: ["A", "B"], selection: "B").kind == .enumeration)
    }

    @Test func typedAccessorsOnlyAnswerForTheirOwnKind() {
        let number = FeatureParameterValue.number(7)
        #expect(number.numberValue == 7)
        #expect(number.stringValue == nil)
        #expect(number.booleanValue == nil)
        #expect(number.enumerationSelection == nil)

        let choice = FeatureParameterValue.enumeration(cases: ["Prefix", "Suffix"], selection: "Suffix")
        #expect(choice.enumerationSelection == "Suffix")
        #expect(choice.enumerationCases == ["Prefix", "Suffix"])
        #expect(choice.stringValue == nil)
    }

    @Test func roundTripsEveryCaseThroughCodable() throws {
        let values: [FeatureParameterValue] = [
            .number(1.5), .string("tag"), .boolean(true),
            .enumeration(cases: ["A", "B"], selection: "A"),
        ]
        for value in values {
            let data = try JSONEncoder().encode(value)
            #expect(try JSONDecoder().decode(FeatureParameterValue.self, from: data) == value)
        }
    }
}

@Suite("FeatureParameter")
struct FeatureParameterTests {

    private func placement() -> FeatureParameter {
        FeatureParameter(name: "placement", label: "Placement",
                         value: .enumeration(cases: ["Prefix", "Suffix"], selection: "Suffix"))
    }

    @Test func acceptsAValueOfTheSameKind() {
        var parameter = FeatureParameter(name: "hold", label: "Hold", value: .number(7))
        parameter.setValue(.number(12))
        #expect(parameter.value.numberValue == 12)
    }

    @Test func ignoresAValueOfTheWrongKind() {
        var parameter = FeatureParameter(name: "hold", label: "Hold", value: .number(7))
        parameter.setValue(.string("twelve"))
        #expect(parameter.value.numberValue == 7)
    }

    @Test func clampsNumbersToTheirBounds() {
        var parameter = FeatureParameter(name: "hold", label: "Hold", value: .number(7),
                                         bounds: NumberBounds(minimum: 1, maximum: 30, step: 1))
        parameter.setValue(.number(500))
        #expect(parameter.value.numberValue == 30)
        parameter.setValue(.number(-4))
        #expect(parameter.value.numberValue == 1)
    }

    @Test func keepsTheDeclaredCasesWhenTheSelectionChanges() {
        var parameter = placement()
        parameter.setValue(.enumeration(cases: ["Nonsense"], selection: "Prefix"))
        #expect(parameter.value.enumerationSelection == "Prefix")
        #expect(parameter.value.enumerationCases == ["Prefix", "Suffix"])
    }

    @Test func ignoresASelectionThatIsNotOneOfTheCases() {
        var parameter = placement()
        parameter.setValue(.enumeration(cases: ["Prefix", "Suffix"], selection: "Sideways"))
        #expect(parameter.value.enumerationSelection == "Suffix")
    }

    @Test func selectingByNameIsShorthandForTheEnumerationCase() {
        var parameter = placement()
        parameter.select("Prefix")
        #expect(parameter.value.enumerationSelection == "Prefix")
        parameter.select("Sideways")
        #expect(parameter.value.enumerationSelection == "Prefix")
    }
}

@Suite("FeatureFlag")
struct FeatureFlagTests {

    private func flag(enabled: Bool = false) -> FeatureFlag {
        FeatureFlag(
            name: "demo", title: "Demo", description: "A flag for tests.",
            isEnabled: enabled,
            parameters: [
                FeatureParameter(name: "count", label: "Count", value: .number(2),
                                 bounds: NumberBounds(minimum: 0, maximum: 10, step: 1)),
                FeatureParameter(name: "label", label: "Label", value: .string("hi")),
                FeatureParameter(name: "loud", label: "Loud", value: .boolean(false)),
                FeatureParameter(name: "where", label: "Where",
                                 value: .enumeration(cases: ["Prefix", "Suffix"], selection: "Suffix")),
            ])
    }

    @Test func readsParametersByName() {
        let demo = flag()
        #expect(demo.number("count") == 2)
        #expect(demo.string("label") == "hi")
        #expect(demo.boolean("loud") == false)
        #expect(demo.selection("where") == "Suffix")
        #expect(demo.number("missing") == nil)
    }

    @Test func writesParametersByName() {
        var demo = flag()
        demo.setParameter("count", to: .number(5))
        #expect(demo.number("count") == 5)
    }

    @Test func writingAnUnknownParameterIsANoOp() {
        var demo = flag()
        demo.setParameter("nope", to: .number(5))
        #expect(demo.parameters.count == 4)
    }

    @Test func parameterOrderIsPreservedForTheDialog() {
        #expect(flag().parameters.map(\.name) == ["count", "label", "loud", "where"])
    }
}

@Suite("FeatureFlagSettings")
struct FeatureFlagSettingsTests {

    private var catalog: [FeatureFlag] {
        [
            FeatureFlag(name: "alpha", title: "Alpha", description: "First.", isEnabled: false,
                        parameters: [FeatureParameter(name: "size", label: "Size", value: .number(4),
                                                      bounds: NumberBounds(minimum: 1, maximum: 8, step: 1))]),
            FeatureFlag(name: "beta", title: "Beta", description: "Second.", isEnabled: true,
                        parameters: [FeatureParameter(name: "mode", label: "Mode",
                                                      value: .enumeration(cases: ["A", "B"], selection: "A"))]),
        ]
    }

    @Test func readsEnabledStateAndValues() {
        let settings = FeatureFlagSettings(flags: catalog)
        #expect(!settings.isEnabled("alpha"))
        #expect(settings.isEnabled("beta"))
        #expect(!settings.isEnabled("unknown"))
        #expect(settings.number("alpha", "size") == 4)
        #expect(settings.selection("beta", "mode") == "A")
    }

    @Test func togglesAndEditsFlags() {
        var settings = FeatureFlagSettings(flags: catalog)
        settings.setEnabled(true, for: "alpha")
        settings.setParameter("size", of: "alpha", to: .number(6))
        #expect(settings.isEnabled("alpha"))
        #expect(settings.number("alpha", "size") == 6)
    }

    @Test func reconcileKeepsStoredStateForFlagsThatStillExist() {
        var stored = FeatureFlagSettings(flags: catalog)
        stored.setEnabled(true, for: "alpha")
        stored.setParameter("size", of: "alpha", to: .number(7))
        let merged = stored.reconciled(with: catalog)
        #expect(merged.isEnabled("alpha"))
        #expect(merged.number("alpha", "size") == 7)
    }

    @Test func reconcileDropsFlagsThatAreNoLongerInTheCatalog() {
        let stale = FeatureFlagSettings(flags: [
            FeatureFlag(name: "gone", title: "Gone", description: "Removed.", isEnabled: true, parameters: []),
        ])
        let merged = stale.reconciled(with: catalog)
        #expect(merged.flags.map(\.name) == ["alpha", "beta"])
    }

    @Test func reconcileAddsNewCatalogFlagsWithTheirDefaults() {
        let merged = FeatureFlagSettings(flags: []).reconciled(with: catalog)
        #expect(merged.flags.map(\.name) == ["alpha", "beta"])
        #expect(merged.isEnabled("beta"))
        #expect(merged.number("alpha", "size") == 4)
    }

    @Test func reconcileTakesCopyAndBoundsFromTheCatalogNotFromStorage() {
        let stale = FeatureFlagSettings(flags: [
            FeatureFlag(name: "alpha", title: "Old name", description: "Old words.", isEnabled: true,
                        parameters: [FeatureParameter(name: "size", label: "Old label", value: .number(99))]),
        ])
        let merged = stale.reconciled(with: catalog)
        let alpha = merged.flag(named: "alpha")
        #expect(alpha?.title == "Alpha")
        #expect(alpha?.description == "First.")
        #expect(alpha?.parameter(named: "size")?.label == "Size")
        // Stored 99 is out of the catalog's bounds, so it clamps.
        #expect(alpha?.number("size") == 8)
    }

    @Test func reconcileFallsBackWhenAStoredValueChangedType() {
        let stale = FeatureFlagSettings(flags: [
            FeatureFlag(name: "alpha", title: "Alpha", description: "First.", isEnabled: false,
                        parameters: [FeatureParameter(name: "size", label: "Size", value: .string("big"))]),
        ])
        #expect(stale.reconciled(with: catalog).number("alpha", "size") == 4)
    }

    @Test func reconcileRejectsAnEnumSelectionThatIsNoLongerOffered() {
        let stale = FeatureFlagSettings(flags: [
            FeatureFlag(name: "beta", title: "Beta", description: "Second.", isEnabled: true,
                        parameters: [FeatureParameter(name: "mode", label: "Mode",
                                                      value: .enumeration(cases: ["A", "B", "C"], selection: "C"))]),
        ])
        let merged = stale.reconciled(with: catalog)
        #expect(merged.selection("beta", "mode") == "A")
        #expect(merged.flag(named: "beta")?.parameter(named: "mode")?.value.enumerationCases == ["A", "B"])
    }

    @Test func searchWithNoQueryReturnsEverything() {
        let settings = FeatureFlagSettings(flags: catalog)
        #expect(settings.flags(matching: "").map(\.name) == ["alpha", "beta"])
        #expect(settings.flags(matching: "   ").map(\.name) == ["alpha", "beta"])
    }

    @Test func searchMatchesTitleCaseInsensitively() {
        #expect(FeatureFlagSettings(flags: catalog).flags(matching: "BET").map(\.name) == ["beta"])
    }

    @Test func searchMatchesDescriptionAndParameterLabels() {
        let settings = FeatureFlagSettings(flags: catalog)
        #expect(settings.flags(matching: "second").map(\.name) == ["beta"])
        #expect(settings.flags(matching: "size").map(\.name) == ["alpha"])
    }

    @Test func searchNeedsEveryTermToMatchSomewhere() {
        let settings = FeatureFlagSettings(flags: catalog)
        #expect(settings.flags(matching: "beta mode").map(\.name) == ["beta"])
        #expect(settings.flags(matching: "beta size").isEmpty)
    }

    @Test func searchWithNoMatchesComesBackEmpty() {
        #expect(FeatureFlagSettings(flags: catalog).flags(matching: "zzz").isEmpty)
    }

    @Test func roundTripsThroughCodable() throws {
        var settings = FeatureFlagSettings(flags: catalog)
        settings.setEnabled(true, for: "alpha")
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(FeatureFlagSettings.self, from: data) == settings)
    }
}

@Suite("FeatureCatalog")
struct FeatureCatalogTests {

    @Test func everyReleaseGetsAFlagList() {
        for release in Release.allCases {
            #expect(!FeatureCatalog.flags(for: release).isEmpty)
        }
    }

    @Test func namesAreUniqueAndParameterNamesAreUniquePerFlag() {
        for release in Release.allCases {
            let flags = FeatureCatalog.flags(for: release)
            #expect(Set(flags.map(\.name)).count == flags.count)
            for flag in flags {
                #expect(Set(flag.parameters.map(\.name)).count == flag.parameters.count)
                #expect(!flag.title.isEmpty)
                #expect(!flag.description.isEmpty)
            }
        }
    }

    @Test func theReleaseTagFlagIsOnInNextAndOffInCurrent() {
        // Next announces itself in window titles; Current stays untouched.
        #expect(FeatureCatalog.defaultSettings(for: .next).isEnabled(FeatureCatalog.releaseTagFlag))
        #expect(!FeatureCatalog.defaultSettings(for: .current).isEnabled(FeatureCatalog.releaseTagFlag))
    }

    @Test func theReleaseTagLabelDefaultsToTheReleaseName() {
        #expect(FeatureCatalog.defaultSettings(for: .next)
            .string(FeatureCatalog.releaseTagFlag, FeatureCatalog.releaseTagLabel) == Release.next.title)
    }

    @Test func theHoverMeasureFlagIsNextOnlyAndOnByDefault() {
        // Section 3 of docs/design/next-measure.md: the readout exists only in
        // Next (default on there), and Current never even lists the flag.
        #expect(FeatureCatalog.defaultSettings(for: .next).isEnabled(FeatureCatalog.measureHoverFlag))
        #expect(!FeatureCatalog.flags(for: .current).contains { $0.name == FeatureCatalog.measureHoverFlag })
        #expect(FeatureCatalog.defaultSettings(for: .next)
            .number(FeatureCatalog.measureHoverFlag, FeatureCatalog.measureHoverRadius)
            == ElementBounds.defaultMaxRadius)
    }

    @Test func theAlignmentFlagIsNextOnlyAndOnByDefault() {
        // Section 9 of docs/design/next-measure.md (decision D1): alignment
        // checks exist only in Next (default on there) with a px tolerance.
        #expect(FeatureCatalog.defaultSettings(for: .next).isEnabled(FeatureCatalog.measureAlignFlag))
        #expect(!FeatureCatalog.flags(for: .current).contains { $0.name == FeatureCatalog.measureAlignFlag })
        #expect(FeatureCatalog.defaultSettings(for: .next)
            .number(FeatureCatalog.measureAlignFlag, FeatureCatalog.measureAlignTolerance) == 1)
    }

    @Test func theMeasurePanelFlagIsNextOnlyAndOnByDefault() {
        // Sections 6-7 of docs/design/next-measure.md: the Measurements panel
        // and spec-list export exist only in Next, default on there.
        #expect(FeatureCatalog.defaultSettings(for: .next).isEnabled(FeatureCatalog.measurePanelFlag))
        #expect(!FeatureCatalog.flags(for: .current).contains { $0.name == FeatureCatalog.measurePanelFlag })
    }

    @Test func theToastTimingFlagShipsWithTheBuiltInSeconds() {
        let settings = FeatureCatalog.defaultSettings(for: .current)
        #expect(!settings.isEnabled(FeatureCatalog.captureToastTimingFlag))
        #expect(settings.number(FeatureCatalog.captureToastTimingFlag, FeatureCatalog.captureToastHold) == 7)
        #expect(settings.number(FeatureCatalog.captureToastTimingFlag, FeatureCatalog.captureToastFade) == 3)
    }
}

@Suite("ReleaseTag")
struct ReleaseTagTests {

    @Test func appendsOrPrependsTheTag() {
        #expect(ReleaseTag.decorate("Shot.png", tag: "Next", placement: .suffix, uppercase: false)
            == "Shot.png (Next)")
        #expect(ReleaseTag.decorate("Shot.png", tag: "Next", placement: .prefix, uppercase: false)
            == "(Next) Shot.png")
    }

    @Test func uppercasesOnRequest() {
        #expect(ReleaseTag.decorate("Shot.png", tag: "Next", placement: .suffix, uppercase: true)
            == "Shot.png (NEXT)")
    }

    @Test func aBlankTagLeavesTheTitleAlone() {
        #expect(ReleaseTag.decorate("Shot.png", tag: "   ", placement: .suffix, uppercase: false) == "Shot.png")
    }

    @Test func placementParsesFromTheStoredCaseName() {
        #expect(ReleaseTag.Placement(name: "Prefix") == .prefix)
        #expect(ReleaseTag.Placement(name: "Suffix") == .suffix)
        #expect(ReleaseTag.Placement(name: "Sideways") == nil)
        #expect(ReleaseTag.Placement.allNames == ["Prefix", "Suffix"])
    }
}

@Suite("AppNaming")
struct AppNamingTests {

    @Test func publicKeepsThePlainName() {
        #expect(AppNaming.appName(base: "Photonz", release: .current, isDevBuild: false) == "Photonz")
    }

    @Test func otherReleasesAreNamedAfterThemselves() {
        #expect(AppNaming.appName(base: "Photonz", release: .next, isDevBuild: false) == "Photonz Next")
    }

    @Test func devBuildsKeepTheirSuffixOnTheEnd() {
        #expect(AppNaming.appName(base: "Photonz", release: .current, isDevBuild: true) == "Photonz (Dev)")
        #expect(AppNaming.appName(base: "Photonz", release: .next, isDevBuild: true) == "Photonz Next (Dev)")
    }

    @Test func theBaseNameComesBackOutOfADevBundleName() {
        #expect(AppNaming.baseName(fromBundleName: "Photonz (Dev)") == "Photonz")
        #expect(AppNaming.baseName(fromBundleName: "Photonz") == "Photonz")
    }

    @Test func aNameAlreadyCarryingTheReleaseIsNotDoubled() {
        // Re-deriving from an already-decorated name must be a no-op, so a
        // round trip through the bundle name can't produce "Photonz Next Next".
        let name = AppNaming.appName(base: "Photonz", release: .next, isDevBuild: true)
        #expect(AppNaming.appName(base: AppNaming.baseName(fromBundleName: name),
                                  release: .next, isDevBuild: true) == name)
    }
}

@Suite("ExperimentsStore")
struct ExperimentsStoreTests {

    @Test func startsOnCurrentWithCatalogDefaults() {
        let store = ExperimentsStore(defaults: InMemoryExperimentsDefaults())
        #expect(store.selectedRelease == .current)
        #expect(store.settings(for: .current) == FeatureCatalog.defaultSettings(for: .current))
    }

    @Test func remembersTheSelectedRelease() {
        let defaults = InMemoryExperimentsDefaults()
        ExperimentsStore(defaults: defaults).selectedRelease = .next
        #expect(ExperimentsStore(defaults: defaults).selectedRelease == .next)
    }

    @Test func anUnknownStoredReleaseFallsBackToCurrent() {
        let defaults = InMemoryExperimentsDefaults()
        defaults.setExperimentsString("legacy", forKey: ExperimentsStore.releaseKey)
        #expect(ExperimentsStore(defaults: defaults).selectedRelease == .current)
    }

    @Test func flagEditsPersistAcrossStores() {
        let defaults = InMemoryExperimentsDefaults()
        let store = ExperimentsStore(defaults: defaults)
        store.setEnabled(true, flag: FeatureCatalog.captureToastTimingFlag, in: .current)
        store.setParameter(FeatureCatalog.captureToastHold,
                           of: FeatureCatalog.captureToastTimingFlag, to: .number(12), in: .current)

        let reopened = ExperimentsStore(defaults: defaults)
        #expect(reopened.settings(for: .current).isEnabled(FeatureCatalog.captureToastTimingFlag))
        #expect(reopened.settings(for: .current)
            .number(FeatureCatalog.captureToastTimingFlag, FeatureCatalog.captureToastHold) == 12)
    }

    @Test func releasesDoNotShareFlagState() {
        let defaults = InMemoryExperimentsDefaults()
        let store = ExperimentsStore(defaults: defaults)
        store.setEnabled(true, flag: FeatureCatalog.captureToastTimingFlag, in: .next)
        #expect(store.settings(for: .next).isEnabled(FeatureCatalog.captureToastTimingFlag))
        #expect(!store.settings(for: .current).isEnabled(FeatureCatalog.captureToastTimingFlag))
        // And the round trip is lossless in both directions.
        let reopened = ExperimentsStore(defaults: defaults)
        #expect(reopened.settings(for: .next).isEnabled(FeatureCatalog.captureToastTimingFlag))
        #expect(!reopened.settings(for: .current).isEnabled(FeatureCatalog.captureToastTimingFlag))
    }

    @Test func eachReleaseWritesToItsOwnKey() {
        let defaults = InMemoryExperimentsDefaults()
        let store = ExperimentsStore(defaults: defaults)
        for release in Release.allCases {
            store.setEnabled(true, flag: FeatureCatalog.captureToastTimingFlag, in: release)
        }
        let keys = Set(Release.allCases.map { ExperimentsStore.settingsKey(for: $0) })
        #expect(keys.count == Release.allCases.count)
        for key in keys { #expect(defaults.experimentsData(forKey: key) != nil) }
    }

    @Test func corruptStoredDataFallsBackToCatalogDefaults() {
        let defaults = InMemoryExperimentsDefaults()
        defaults.setExperimentsData(Data("not json".utf8),
                                    forKey: ExperimentsStore.settingsKey(for: .current))
        #expect(ExperimentsStore(defaults: defaults).settings(for: .current)
            == FeatureCatalog.defaultSettings(for: .current))
    }

    @Test func storedStateIsReconciledWithTheCurrentCatalog() throws {
        // Someone's saved state from an older build: one flag that no longer
        // exists, and nothing about the flags that do.
        let defaults = InMemoryExperimentsDefaults()
        let stale = FeatureFlagSettings(flags: [
            FeatureFlag(name: "retired", title: "Retired", description: "Gone.", isEnabled: true, parameters: []),
        ])
        defaults.setExperimentsData(try JSONEncoder().encode(stale),
                                    forKey: ExperimentsStore.settingsKey(for: .current))
        let settings = ExperimentsStore(defaults: defaults).settings(for: .current)
        #expect(settings.flag(named: "retired") == nil)
        #expect(settings.flags.map(\.name) == FeatureCatalog.flags(for: .current).map(\.name))
    }

    @Test func resetRestoresTheCatalogDefaultsForOneReleaseOnly() {
        let defaults = InMemoryExperimentsDefaults()
        let store = ExperimentsStore(defaults: defaults)
        store.setEnabled(true, flag: FeatureCatalog.captureToastTimingFlag, in: .current)
        store.setEnabled(true, flag: FeatureCatalog.captureToastTimingFlag, in: .next)
        store.resetToDefaults(for: .current)
        #expect(store.settings(for: .current) == FeatureCatalog.defaultSettings(for: .current))
        #expect(store.settings(for: .next).isEnabled(FeatureCatalog.captureToastTimingFlag))
    }

    @Test func updateAppliesAnInPlaceEdit() {
        let store = ExperimentsStore(defaults: InMemoryExperimentsDefaults())
        store.update(.next) { $0.setEnabled(true, for: FeatureCatalog.releaseTagFlag) }
        #expect(store.settings(for: .next).isEnabled(FeatureCatalog.releaseTagFlag))
    }
}
