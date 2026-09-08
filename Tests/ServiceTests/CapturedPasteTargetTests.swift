import AppKit
import ApplicationServices
import Testing
@testable import mrml

@MainActor
@Suite("Captured paste target safety")
struct CapturedPasteTargetTests {
    @MainActor private final class VerifiedSelection: PasteTargetChecking {
        func isStillValid() -> Bool { true }
    }

    @Test("Notion inspection failure categories use the original bounded walk", arguments: ["budget", "missing", "shape", "transport", "timeout_setup", "settable", "owner", "classes_missing", "optional_then_shape", "focus"])
    func notionInspectionReason(kind: String) {
        let fixture = NotionFixture(layout: .wrapped)
        switch kind {
        case "budget": fixture.costPerRead = 0.1
        case "missing": fixture.set(0, kAXRoleAttribute, result: .noValue, value: nil)
        case "shape": fixture.set(0, kAXRoleAttribute, value: "AXButton" as CFString)
        case "transport": fixture.set(0, kAXRoleAttribute, result: .cannotComplete, value: nil)
        case "timeout_setup": fixture.timeoutSucceeds = false
        case "settable": fixture.settable[kAXValueAttribute] = nil
        case "owner": fixture.owners[0] = nil
        case "classes_missing": fixture.set(0, "AXDOMClassList", result: .attributeUnsupported, value: nil)
        case "optional_then_shape":
            fixture.set(0, kAXSubroleAttribute, result: .noValue, value: nil)
            fixture.set(1, kAXRoleAttribute, value: "AXButton" as CFString)
        default: break
        }
        var reasons: [PasteTargetInvalidationReason] = []
        #expect(fixture.snapshot(frontmostProcessID: kind == "focus" ? 43 : 42, onFailure: { reasons.append($0) }) == nil)
        let expected: String
        switch kind {
        case "focus": expected = "focus_changed"
        case "budget": expected = "inspection_timed_out"
        case "missing", "settable", "owner", "classes_missing": expected = "metadata_unavailable"
        case "shape", "optional_then_shape": expected = "unsupported_structure"
        default: expected = "accessibility_unavailable"
        }
        #expect(reasons.map(\.rawValue) == [expected])
    }

    @Test("Capture selection preserves verified TextEdit capability identity")
    func verifiedSelectionPassesThrough() {
        let target = VerifiedSelection()
        #expect(CapturedPasteTarget.select(bundleIdentifier: "com.apple.TextEdit", capturedTarget: target) === target)
    }

    @Test("Failed capture outside exact native Notion retains legacy selection", arguments: [nil, "", "com.apple.TextEdit", "com.example.other", "notion.id.helper", "NOTION.ID"] as [String?])
    func otherFailedSelectionRemainsNil(bundleIdentifier: String?) {
        #expect(CapturedPasteTarget.select(bundleIdentifier: bundleIdentifier, capturedTarget: nil) == nil)
    }

    @Test("Native Notion without a verified body structure remains unsupported")
    func notionClassifierRemainsUnsupported() {
        var snapshot = ordinaryEditor()
        snapshot.bundleIdentifier = "notion.id"
        #expect(!snapshot.allowsCapture)
        #expect(!snapshot.allowsDelivery(capturedCaret: NSRange(location: 14, length: 0)))
    }

    @Test("The observed native Notion body editor permits capture and delivery")
    func observedNotionBodyEditor() throws {
        let fixture = NotionFixture()
        let snapshot = try #require(fixture.snapshot())
        #expect(snapshot.allowsCapture)
        #expect(snapshot.allowsDelivery(capturedCaret: NSRange(location: 1, length: 0), capturedNotionStructure: snapshot.notionStructure))
        #expect(snapshot.notionStructure?.ancestors.count == 19)
        #expect(!fixture.attributeReads.contains(kAXValueAttribute))
        #expect(Set(fixture.attributeReads).isSubset(of: [kAXRoleAttribute, kAXSubroleAttribute, kAXEnabledAttribute,
            kAXParentAttribute, kAXSelectedTextRangeAttribute, kAXInsertionPointLineNumberAttribute, "AXDOMClassList"]))
        #expect(Set(fixture.settableReads) == [kAXValueAttribute, kAXSelectedTextRangeAttribute])
    }

    @Test("The observed direct Notion AXParent path permits capture and delivery")
    func observedDirectNotionBodyEditor() {
        let fixture = NotionFixture(layout: .direct)
        let snapshot = fixture.snapshot()

        #expect(snapshot?.allowsCapture == true)
        #expect(snapshot?.allowsDelivery(capturedCaret: NSRange(location: 1, length: 0), capturedNotionStructure: snapshot?.notionStructure) == true)
        #expect(snapshot?.notionStructure?.ancestors.count == 18)
        #expect(!fixture.attributeReads.contains(kAXValueAttribute))
        #expect(!fixture.readNodes.contains(2) && fixture.readNodes.contains(11))
    }

    @Test("Notion accepts absent subroles only with consistent absence status and value", arguments: NotionFixtureLayout.allCases)
    func notionAbsentSubroles(layout: NotionFixtureLayout) {
        for status: AXError in [.noValue, .attributeUnsupported] {
            let fixture = NotionFixture(layout: layout)
            for index in [0, 1, 2, 4, 6, 7, 8, 9, 10, 11, 12].filter({ layout.reachableIndices.contains($0) }) {
                fixture.set(index, kAXSubroleAttribute, result: status, value: nil)
            }
            #expect(fixture.snapshot()?.allowsCapture == true)
            fixture.set(0, kAXSubroleAttribute, result: status, value: kCFBooleanTrue)
            #expect(fixture.snapshot() == nil)
        }
    }

    @Test("Notion rejects malformed, secure, and unknown leaf or ancestor subroles", arguments: NotionFixtureLayout.allCases)
    func notionInvalidSubroles(layout: NotionFixtureLayout) {
        let samples: [CapturedPasteTarget.AttributeRead] = [
            .init(result: .success, value: nil), .init(result: .success, value: kCFBooleanTrue),
            .init(result: .noValue, value: "AXUnknown" as CFString), .init(result: .attributeUnsupported, value: NSNumber(value: 2)),
            .init(result: .cannotComplete, value: nil), .init(result: .success, value: "AXUnknown" as CFString),
            .init(result: .success, value: "AXSecureTextField" as CFString),
            .init(result: .success, value: "AXDialog" as CFString)
        ]
        for index in [0, 1, 3, 5, 10, 11, 12, 19].filter({ layout.reachableIndices.contains($0) }) {
            for sample in samples {
                let fixture = NotionFixture(layout: layout)
                fixture.set(index, kAXSubroleAttribute, result: sample.result, value: sample.value)
                #expect(fixture.snapshot() == nil)
            }
        }
    }

    @Test("Notion insertion line requires an available nonnegative integer distinct from NSNotFound")
    func notionInsertionLineTypes() {
        let invalid: [CapturedPasteTarget.AttributeRead] = [
            .init(result: .success, value: kCFBooleanTrue), .init(result: .success, value: NSNumber(value: 0.5)),
            .init(result: .success, value: NSNumber(value: -1)), .init(result: .success, value: NSNumber(value: NSNotFound)),
            .init(result: .success, value: NSNumber(value: UInt64.max)), .init(result: .success, value: "0" as CFString),
            .init(result: .success, value: nil), .init(result: .noValue, value: nil),
            .init(result: .cannotComplete, value: NSNumber(value: 0))
        ]
        for sample in invalid {
            let fixture = NotionFixture()
            fixture.set(0, kAXInsertionPointLineNumberAttribute, result: sample.result, value: sample.value)
            #expect(fixture.snapshot() == nil)
        }
        for line in [0, 1, 20] {
            let fixture = NotionFixture()
            fixture.set(0, kAXInsertionPointLineNumberAttribute, value: NSNumber(value: line))
            #expect(fixture.snapshot()?.notionStructure?.insertionLine == line)
        }
    }

    @Test("Notion requires current value and range editability, enabled true, and a collapsed valid caret", arguments: NotionFixtureLayout.allCases)
    func notionLeafReadiness(layout: NotionFixtureLayout) {
        for name in [kAXValueAttribute, kAXSelectedTextRangeAttribute] {
            for value: Bool? in [nil, false] {
                let fixture = NotionFixture(layout: layout)
                fixture.settable[name] = value
                #expect(fixture.snapshot() == nil)
            }
        }
        let enabledSamples: [CapturedPasteTarget.AttributeRead] = [
            .init(result: .attributeUnsupported, value: nil), .init(result: .success, value: kCFBooleanFalse),
            .init(result: .success, value: NSNumber(value: 1)), .init(result: .success, value: nil),
            .init(result: .cannotComplete, value: kCFBooleanTrue)
        ]
        for sample in enabledSamples {
            let fixture = NotionFixture(layout: layout)
            fixture.set(0, kAXEnabledAttribute, result: sample.result, value: sample.value)
            #expect(fixture.snapshot() == nil)
        }
        for range in [CFRange(location: -1, length: 0), CFRange(location: NSNotFound, length: 0),
                      CFRange(location: 1, length: 1), CFRange(location: 1, length: NSNotFound)] {
            let fixture = NotionFixture(layout: layout)
            var value = range
            fixture.set(0, kAXSelectedTextRangeAttribute, value: AXValueCreate(.cfRange, &value))
            #expect(fixture.snapshot() == nil)
        }
        let fixture = NotionFixture(layout: layout)
        fixture.set(0, kAXSelectedTextRangeAttribute, value: kCFBooleanTrue)
        #expect(fixture.snapshot() == nil)
    }

    @Test("Notion refuses the page title, editor root, and mismatched critical body structure", arguments: NotionFixtureLayout.allCases)
    func notionBodyStructure(layout: NotionFixtureLayout) {
        for (index, name, value) in [
            (0, kAXRoleAttribute, "AXTextField"), (0, kAXSubroleAttribute, "AXApplicationGroup"),
            (1, kAXRoleAttribute, "AXTextArea"), (3, kAXRoleAttribute, "AXGroup"),
            (3, kAXSubroleAttribute, "AXLandmarkMain"), (5, kAXSubroleAttribute, "AXApplicationGroup"),
            (6, kAXRoleAttribute, "AXSheet"), (12, kAXRoleAttribute, "AXDialog")
        ] {
            let fixture = NotionFixture(layout: layout)
            fixture.set(index, name, value: value as CFString)
            #expect(fixture.snapshot() == nil)
        }
        for index in (0...5).filter({ layout.reachableIndices.contains($0) }) {
            let fixture = NotionFixture(layout: layout)
            fixture.set(index, "AXDOMClassList", value: ["notion-page-title"] as CFArray)
            #expect(fixture.snapshot() == nil)
        }
        let rootFixture = NotionFixture(layout: layout)
        rootFixture.parents[0] = 3
        #expect(rootFixture.snapshot() == nil)
        let themeFixture = NotionFixture(layout: layout)
        themeFixture.set(9, "AXDOMClassList", value: ["notion-unobserved-container"] as CFArray)
        #expect(themeFixture.snapshot() == nil)
    }

    @Test("Notion requires the native scroll area in both content profiles", arguments: NotionFixtureLayout.allCases)
    func notionMissingNativeScrollAreaRefused(layout: NotionFixtureLayout) {
        let fixture = NotionFixture(layout: layout)
        fixture.parents[10] = 12
        #expect(fixture.snapshot() == nil)
    }

    @Test("Notion paragraph semantics cannot be replaced by title, sidebar, or dialog structures", arguments: NotionFixtureLayout.allCases)
    func notionSemanticAnchorsRemainRequired(layout: NotionFixtureLayout) {
        for tokens in [["notion-page-block", "notion-selectable"], ["notion-sidebar-container"],
                       ["notion-selectable"], ["notion-selectable", "notion-text-block", "notion-search"]] {
            let fixture = NotionFixture(layout: layout)
            fixture.set(1, "AXDOMClassList", value: tokens as CFArray)
            #expect(fixture.snapshot() == nil)
        }
        for index in [4, 5] {
            let skippedAnchor = NotionFixture(layout: layout)
            skippedAnchor.parents[index - 1] = index + 1
            #expect(skippedAnchor.snapshot() == nil)
        }
        let otherWindow = NotionFixture(layout: layout)
        otherWindow.set(12, kAXRoleAttribute, value: "AXWindow" as CFString)
        otherWindow.set(12, kAXSubroleAttribute, value: "AXStandardWindow" as CFString)
        #expect(otherWindow.snapshot() == nil)
        let nestedWebArea = NotionFixture(layout: layout)
        nestedWebArea.set(12, kAXRoleAttribute, value: "AXWebArea" as CFString)
        #expect(nestedWebArea.snapshot() == nil)
    }

    @Test("Notion role reads require successful strings at every retained element", arguments: NotionFixtureLayout.allCases)
    func notionRoleParsing(layout: NotionFixtureLayout) {
        for index in [0, 1, 3, 5, 10, 11, 12, 19].filter({ layout.reachableIndices.contains($0) }) {
            for sample in [CapturedPasteTarget.AttributeRead(result: .success, value: kCFBooleanTrue),
                           .init(result: .success, value: nil), .init(result: .cannotComplete, value: "AXGroup" as CFString)] {
                let fixture = NotionFixture(layout: layout)
                fixture.set(index, kAXRoleAttribute, result: sample.result, value: sample.value)
                #expect(fixture.snapshot() == nil)
            }
        }
    }

    @Test("Notion structural class arrays are typed, bounded, and absent only on observed native ancestors", arguments: NotionFixtureLayout.allCases)
    func notionStructuralClassParsing(layout: NotionFixtureLayout) {
        let invalid: [CapturedPasteTarget.AttributeRead] = [
            .init(result: .success, value: kCFBooleanTrue), .init(result: .success, value: "notion-text-block" as CFString),
            .init(result: .success, value: ["notion-selectable", "notion-text-block", NSNumber(value: 1)] as CFArray),
            .init(result: .success, value: Array(repeating: "token", count: 129) as CFArray),
            .init(result: .success, value: [String(repeating: "a", count: 129)] as CFArray),
            .init(result: .success, value: ["notion-selectable", "notion-text-block\n"] as CFArray),
            .init(result: .attributeUnsupported, value: nil), .init(result: .noValue, value: nil),
            .init(result: .attributeUnsupported, value: [] as CFArray), .init(result: .cannotComplete, value: [] as CFArray)
        ]
        for sample in invalid {
            let fixture = NotionFixture(layout: layout)
            fixture.set(1, "AXDOMClassList", result: sample.result, value: sample.value)
            #expect(fixture.snapshot() == nil)
        }
        for index in [11, 19].filter({ layout.reachableIndices.contains($0) }) {
            let validFixture = NotionFixture(layout: layout)
            #expect(validFixture.snapshot()?.allowsCapture == true)
            for sample in invalid where !(sample.result == .attributeUnsupported && sample.value == nil) {
                let fixture = NotionFixture(layout: layout)
                fixture.set(index, "AXDOMClassList", result: sample.result, value: sample.value)
                #expect(fixture.snapshot() == nil)
            }
        }
        for sample in invalid {
            let fixture = NotionFixture(layout: layout)
            fixture.set(12, "AXDOMClassList", result: sample.result, value: sample.value)
            #expect(fixture.snapshot() == nil)
        }
    }

    @Test("Notion parent traversal refuses missing, malformed, cyclic, foreign, and over-depth chains", arguments: NotionFixtureLayout.allCases)
    func notionTraversalFailures(layout: NotionFixtureLayout) {
        let missing = NotionFixture(layout: layout)
        missing.parents[7] = nil
        #expect(missing.snapshot() == nil)
        let cycle = NotionFixture(layout: layout)
        cycle.parents[7] = 3
        #expect(cycle.snapshot() == nil)
        #expect(zip(cycle.readNodes, cycle.attributeReads).filter { $0.0 == 3 && $0.1 == kAXRoleAttribute }.count == 1)
        let selfCycle = NotionFixture(layout: layout)
        selfCycle.parents[0] = 0
        #expect(selfCycle.snapshot() == nil)
        let foreign = NotionFixture(layout: layout)
        foreign.owners[7] = 77
        #expect(foreign.snapshot() == nil)
        #expect(!foreign.readNodes.contains(7))
        let unavailableOwner = NotionFixture(layout: layout)
        unavailableOwner.owners[7] = nil
        #expect(unavailableOwner.snapshot() == nil)
        for sample in [CapturedPasteTarget.AttributeRead(result: .cannotComplete, value: nil),
                       .init(result: .success, value: kCFBooleanTrue)] {
            let malformed = NotionFixture(layout: layout)
            malformed.set(7, kAXParentAttribute, result: sample.result, value: sample.value)
            #expect(malformed.snapshot() == nil)
        }
        let noWebArea = NotionFixture(layout: layout)
        noWebArea.parents[9] = 11
        #expect(noWebArea.snapshot() == nil)
        let noNativeContainer = NotionFixture(layout: layout)
        noNativeContainer.parents[10] = 19
        #expect(noNativeContainer.snapshot() == nil)
        let earlyWindow = NotionFixture(layout: layout)
        earlyWindow.parents[3] = 19
        #expect(earlyWindow.snapshot() == nil)
        let excessive = NotionFixture(layout: layout)
        for _ in 0..<17 { excessive.insertNativeParent() }
        #expect(excessive.snapshot() == nil)
        #expect(excessive.attributeReads.filter { $0 == kAXParentAttribute }.count == 32)
    }

    @Test("Notion delivery retains every parent identity, caret, insertion line, and released modifiers", arguments: NotionFixtureLayout.allCases)
    func notionDeliveryIdentity(layout: NotionFixtureLayout) throws {
        let fixture = NotionFixture(layout: layout)
        let captured = try #require(fixture.snapshot())
        let proof = try #require(captured.notionStructure)
        #expect(!captured.allowsDelivery(capturedCaret: NSRange(location: 1, length: 0)))
        let refreshed = try #require(fixture.snapshot())
        #expect(refreshed.allowsDelivery(capturedCaret: NSRange(location: 1, length: 0), capturedNotionStructure: proof))
        #expect(!refreshed.allowsDelivery(capturedCaret: NSRange(location: 2, length: 0), capturedNotionStructure: proof))
        for flag: CGEventFlags in [.maskSecondaryFn, .maskAlternate, .maskCommand, .maskControl, .maskShift] {
            let held = try #require(fixture.snapshot(modifiers: flag))
            #expect(held.allowsCapture)
            #expect(!held.allowsDelivery(capturedCaret: NSRange(location: 1, length: 0), capturedNotionStructure: proof))
        }
        let caps = try #require(fixture.snapshot(modifiers: .maskAlphaShift))
        #expect(caps.allowsDelivery(capturedCaret: NSRange(location: 1, length: 0), capturedNotionStructure: proof))
        fixture.set(0, kAXInsertionPointLineNumberAttribute, value: NSNumber(value: 1))
        let changedLine = try #require(fixture.snapshot())
        #expect(!changedLine.allowsDelivery(capturedCaret: NSRange(location: 1, length: 0), capturedNotionStructure: proof))
        fixture.set(0, kAXInsertionPointLineNumberAttribute, value: NSNumber(value: 0))
        fixture.replaceParentIdentity(at: 7)
        let changedParent = try #require(fixture.snapshot())
        #expect(!changedParent.allowsDelivery(capturedCaret: NSRange(location: 1, length: 0), capturedNotionStructure: proof))
        fixture.set(1, "AXDOMClassList", value: ["notion-page-title"] as CFArray)
        #expect(fixture.snapshot() == nil)
    }

    @Test("Notion refuses a different structural profile even when parent identities are reused")
    func notionProfileChangeWithSameIdentities() throws {
        let fixture = NotionFixture(layout: .direct)
        let captured = try #require(fixture.snapshot())
        let proof = try #require(captured.notionStructure)
        fixture.set(3, kAXRoleAttribute, value: "AXGroup" as CFString)
        fixture.set(3, kAXSubroleAttribute, result: .noValue, value: nil)
        fixture.set(3, "AXDOMClassList", value: ["notion-page-content"] as CFArray)
        fixture.set(4, kAXRoleAttribute, value: "AXTextArea" as CFString)
        fixture.set(4, kAXSubroleAttribute, value: "AXApplicationGroup" as CFString)
        fixture.set(4, "AXDOMClassList", value: [] as CFArray)
        fixture.set(5, kAXSubroleAttribute, result: .noValue, value: nil)
        fixture.set(5, "AXDOMClassList", value: ["notion-scroller"] as CFArray)
        fixture.set(6, kAXSubroleAttribute, value: "AXLandmarkMain" as CFString)
        fixture.set(6, "AXDOMClassList", value: ["notion-frame"] as CFArray)

        let changed = try #require(fixture.snapshot())
        let changedProof = try #require(changed.notionStructure)

        #expect(changedProof.ancestors.count == proof.ancestors.count)
        #expect(zip(changedProof.ancestors, proof.ancestors).allSatisfy { CFEqual($0, $1) })
        #expect(!changed.allowsDelivery(capturedCaret: NSRange(location: 1, length: 0), capturedNotionStructure: proof))
    }

    @Test("Notion bounds cumulative reads and refuses timeout setup failure", arguments: NotionFixtureLayout.allCases)
    func notionReadBudget(layout: NotionFixtureLayout) {
        let fixture = NotionFixture(layout: layout)
        fixture.costPerRead = 0.06
        #expect(fixture.snapshot() == nil)
        #expect(fixture.attributeReads.count < 10)
        #expect(fixture.timeouts.allSatisfy { $0 > 0 && $0 <= 0.2 })
        #expect(fixture.timeouts.contains { $0 < 0.1 })
        #expect(fixture.clock < 0.32)
        let timeoutFailure = NotionFixture(layout: layout)
        timeoutFailure.timeoutSucceeds = false
        #expect(timeoutFailure.snapshot() == nil)
        #expect(timeoutFailure.attributeReads.isEmpty)
    }

    @Test("Notion refuses caret or leaf-safety changes during ancestor reads",
          arguments: NotionFixtureLayout.allCases, ["range", "line", "secure-subrole", "editable", "range-settable", "enabled", "role", "classes"])
    func notionLeafChangeDuringParentWalk(layout: NotionFixtureLayout, change: String) {
        let fixture = NotionFixture(layout: layout)
        defer { fixture.afterAttributeRead = nil }
        var changed = false
        fixture.afterAttributeRead = { index, name in
            guard index == 19, name == "AXDOMClassList" else { return }
            changed = true
            switch change {
            case "range":
                var range = CFRange(location: 2, length: 0)
                fixture.set(0, kAXSelectedTextRangeAttribute, value: AXValueCreate(.cfRange, &range))
            case "line": fixture.set(0, kAXInsertionPointLineNumberAttribute, value: NSNumber(value: 1))
            case "secure-subrole": fixture.set(0, kAXSubroleAttribute, value: "AXSecureTextField" as CFString)
            case "editable": fixture.settable[kAXValueAttribute] = false
            case "range-settable": fixture.settable[kAXSelectedTextRangeAttribute] = false
            case "enabled": fixture.set(0, kAXEnabledAttribute, value: kCFBooleanFalse)
            case "role": fixture.set(0, kAXRoleAttribute, value: "AXTextField" as CFString)
            case "classes": fixture.set(0, "AXDOMClassList", value: ["notion-page-title"] as CFArray)
            default: Issue.record("Unexpected fixture change")
            }
        }

        var reason: PasteTargetInvalidationReason?
        let snapshot = fixture.snapshot(onFailure: { reason = $0 })

        #expect(changed)
        #expect(snapshot == nil)
        if change == "range" { #expect(reason == .caretChanged) }
        if change == "line" { #expect(reason == .structureChanged) }
    }

    @Test("Notion leaf revalidation shares the ancestor traversal deadline", arguments: NotionFixtureLayout.allCases)
    func notionLeafRevalidationBudget(layout: NotionFixtureLayout) {
        let fixture = NotionFixture(layout: layout)
        defer { fixture.afterAttributeRead = nil }
        var reachedWindow = false
        fixture.afterAttributeRead = { index, name in
            guard index == 19, name == "AXDOMClassList" else { return }
            reachedWindow = true
            fixture.clock = 0.249
            fixture.costPerRead = 0.002
        }

        let snapshot = fixture.snapshot()

        #expect(reachedWindow)
        #expect(snapshot == nil)
        #expect(fixture.timeouts.last.map { $0 > 0 && $0 <= 0.0011 } == true)
    }

    enum NotionFixtureLayout: CaseIterable, Sendable {
        case wrapped
        case direct

        var reachableIndices: [Int] {
            Array(0..<20).filter { self == .wrapped || $0 != 2 }
        }
    }

    @MainActor private final class NotionFixture {
        var elements = (0..<20).map { AXUIElementCreateApplication(pid_t(1000 + $0)) }
        var attributes: [Int: [String: CapturedPasteTarget.AttributeRead]] = [:]
        var parents: [Int: Int] = Dictionary(uniqueKeysWithValues: (0..<19).map { ($0, $0 + 1) })
        var owners: [Int: pid_t] = Dictionary(uniqueKeysWithValues: (0..<20).map { ($0, 42) })
        var settable = [kAXValueAttribute: true, kAXSelectedTextRangeAttribute: true]
        var attributeReads: [String] = []
        var settableReads: [String] = []
        var readNodes: [Int] = []
        var timeouts: [Float] = []
        var clock: TimeInterval = 0
        var costPerRead: TimeInterval = 0
        var timeoutSucceeds = true
        var afterAttributeRead: ((Int, String) -> Void)?

        init(layout: NotionFixtureLayout = .wrapped) {
            for index in 0..<20 {
                set(index, kAXRoleAttribute, value: "AXGroup" as CFString)
                set(index, kAXSubroleAttribute, result: .noValue, value: nil)
                set(index, "AXDOMClassList", value: [] as CFArray)
            }
            set(0, kAXRoleAttribute, value: "AXTextArea" as CFString)
            set(0, kAXEnabledAttribute, value: kCFBooleanTrue)
            var range = CFRange(location: 1, length: 0)
            set(0, kAXSelectedTextRangeAttribute, value: AXValueCreate(.cfRange, &range))
            set(0, kAXInsertionPointLineNumberAttribute, value: NSNumber(value: 0))
            set(0, "AXDOMClassList", value: ["editor-token", "plain-editor"] as CFArray)
            set(1, "AXDOMClassList", value: ["notion-selectable", "notion-text-block"] as CFArray)
            set(2, "AXDOMClassList", value: ["notion-page-content"] as CFArray)
            set(3, kAXRoleAttribute, value: "AXTextArea" as CFString)
            set(3, kAXSubroleAttribute, value: "AXApplicationGroup" as CFString)
            set(4, "AXDOMClassList", value: ["notion-scroller", "layout-token"] as CFArray)
            set(5, kAXSubroleAttribute, value: "AXLandmarkMain" as CFString)
            set(5, "AXDOMClassList", value: ["notion-frame"] as CFArray)
            set(7, "AXDOMClassList", value: ["notion-cursor-listener"] as CFArray)
            set(9, "AXDOMClassList", value: ["notion-body", "notion-dark-theme"] as CFArray)
            set(10, kAXRoleAttribute, value: "AXWebArea" as CFString)
            set(11, kAXRoleAttribute, value: "AXScrollArea" as CFString)
            set(11, kAXSubroleAttribute, result: .attributeUnsupported, value: nil)
            set(11, "AXDOMClassList", result: .attributeUnsupported, value: nil)
            set(19, kAXRoleAttribute, value: "AXWindow" as CFString)
            set(19, kAXSubroleAttribute, value: "AXStandardWindow" as CFString)
            set(19, "AXDOMClassList", result: .attributeUnsupported, value: nil)
            if layout == .direct {
                parents[1] = 3
            }
        }

        func set(_ index: Int, _ name: String, result: AXError = .success, value: CFTypeRef?) {
            attributes[index, default: [:]][name] = .init(result: result, value: value)
        }

        func replaceParentIdentity(at index: Int) {
            elements[index] = AXUIElementCreateApplication(pid_t(2000 + index))
        }

        func insertNativeParent() {
            let index = elements.count
            elements.append(AXUIElementCreateApplication(pid_t(1000 + index)))
            owners[index] = 42
            attributes[index] = attributes[12]
            parents[index] = parents[18]
            parents[18] = index
        }

        func snapshot(modifiers: CGEventFlags = [], frontmostProcessID: pid_t = 42, onFailure: ((PasteTargetInvalidationReason) -> Void)? = nil) -> CapturedPasteTarget.Snapshot? {
            let reader = CapturedPasteTarget.NotionAXReader(attribute: { element, name in
                let index = self.elements.firstIndex { CFEqual($0, element) }!
                self.attributeReads.append(name)
                self.readNodes.append(index)
                self.clock += self.costPerRead
                defer { self.afterAttributeRead?(index, name) }
                if let sample = self.attributes[index]?[name] { return sample }
                if name == kAXParentAttribute, let parent = self.parents[index] {
                    return .init(result: .success, value: self.elements[parent])
                }
                return .init(result: .noValue, value: nil)
            }, isSettable: { _, name in
                self.settableReads.append(name)
                self.clock += self.costPerRead
                return self.settable[name]
            }, processID: { element in
                let index = self.elements.firstIndex { CFEqual($0, element) }!
                return self.owners[index]
            }, setTimeout: { _, timeout in
                self.timeouts.append(timeout)
                return self.timeoutSucceeds
            }, uptime: { self.clock })
            return CapturedPasteTarget.readNotionSnapshot(editor: elements[0], window: elements[19], processID: 42,
                                                          frontmostProcessID: frontmostProcessID, modifierFlags: modifiers, reader: reader, onFailure: onFailure)
        }
    }

    private func ordinaryEditor() -> CapturedPasteTarget.Snapshot {
        .init(processID: 42, frontmostProcessID: 42, bundleIdentifier: "com.apple.TextEdit",
              role: "AXTextArea", subrole: nil, subroleReadIsValid: true,
              enabledState: .value(true), isEditable: true, matchesCapturedFocus: true,
              selectedRange: NSRange(location: 14, length: 0))
    }

    @Test("The same delivery snapshot identifies refusal reasons without changing eligibility")
    func typedDeliveryInvalidationReasons() {
        let caret = NSRange(location: 14, length: 0)
        let cases: [(String, (inout CapturedPasteTarget.Snapshot) -> Void, PasteTargetInvalidationReason?)] = [
            ("valid", { _ in }, nil),
            ("focus", { $0.matchesCapturedFocus = false }, .focusChanged),
            ("different-process", { $0.frontmostProcessID = 99 }, .focusChanged),
            ("missing-role", { $0.role = nil }, .accessibilityUnavailable),
            ("missing-editability", { $0.isEditable = nil }, .accessibilityUnavailable),
            ("missing-range", { $0.selectedRange = nil }, .accessibilityUnavailable),
            ("changed-caret", { $0.selectedRange = NSRange(location: 15, length: 0) }, .caretChanged),
            ("selection", { $0.selectedRange = NSRange(location: 14, length: 1) }, .caretChanged),
            ("modifier", { $0.modifierFlags = .maskSecondaryFn }, .modifiersHeld),
            ("unsupported-editor", { $0.role = "AXTextField" }, .structureUnverifiable),
            ("unavailable-enabled", { $0.enabledState = .unavailable }, .accessibilityUnavailable)
        ]
        for (name, mutation, reason) in cases {
            var snapshot = ordinaryEditor()
            mutation(&snapshot)
            #expect(snapshot.deliveryInvalidationReason(capturedCaret: caret) == reason, Comment(rawValue: name))
            #expect((snapshot.deliveryInvalidationReason(capturedCaret: caret) == nil)
                == snapshot.allowsDelivery(capturedCaret: caret), Comment(rawValue: name))
        }
    }

    @Test("Notion parent identity changes are distinct from unavailable structure")
    func typedNotionStructureInvalidationReasons() throws {
        let fixture = NotionFixture()
        let captured = try #require(fixture.snapshot())
        let caret = try #require(captured.selectedRange)
        fixture.replaceParentIdentity(at: 12)
        let changed = try #require(fixture.snapshot())
        #expect(changed.deliveryInvalidationReason(capturedCaret: caret,
            capturedNotionStructure: captured.notionStructure) == .structureChanged)
        var unavailable = captured
        unavailable.notionStructure = nil
        #expect(unavailable.deliveryInvalidationReason(capturedCaret: caret,
            capturedNotionStructure: captured.notionStructure) == .structureUnverifiable)
    }

    @Test("Initial unverified Notion capture has a specific persistent reason")
    func typedInitialCaptureInvalidationReason() {
        let target = UnverifiedPasteTarget()
        #expect(!target.isStillValid())
        #expect(target.invalidationReason() == .initialCaptureUnverifiable)
        #expect(target.diagnosticPolicy == .unverifiedNotion)
    }

    @Test("Unverified Notion selection preserves the original failed capture sample",
          arguments: [PasteTargetInvalidationReason.accessibilityUnavailable, .focusChanged, .structureUnverifiable, .inspectionTimedOut, .metadataUnavailable, .unsupportedStructure])
    func typedInitialCaptureFailurePropagation(reason: PasteTargetInvalidationReason) {
        let target = CapturedPasteTarget.select(bundleIdentifier: "notion.id", capturedTarget: nil, captureFailure: reason)
        #expect(target?.invalidationReason() == reason)
        #expect(target?.diagnosticPolicy == .unverifiedNotion)
        #expect(target?.isStillValid() == false)
        #expect(CapturedPasteTarget.select(bundleIdentifier: "com.apple.TextEdit", capturedTarget: nil,
            captureFailure: reason) == nil)
    }

    @Test("Capture permits the recording gesture while delivery requires its release")
    func recordingModifiers() {
        var snapshot = ordinaryEditor()
        let caret = NSRange(location: 14, length: 0)
        #expect(snapshot.allowsCapture && snapshot.allowsDelivery(capturedCaret: caret))
        for flag: CGEventFlags in [.maskSecondaryFn, .maskAlternate, .maskCommand, .maskControl, .maskShift] {
            snapshot.modifierFlags = flag
            #expect(snapshot.allowsCapture)
            #expect(!snapshot.allowsDelivery(capturedCaret: caret))
        }
        snapshot.modifierFlags = .maskAlphaShift
        #expect(snapshot.allowsDelivery(capturedCaret: caret))
    }

    @Test("Only the same empty caret can receive a result")
    func caretChangesRejectDelivery() {
        var snapshot = ordinaryEditor()
        #expect(!snapshot.allowsDelivery(capturedCaret: NSRange(location: 13, length: 0)))
        for range: NSRange? in [nil, NSRange(location: 14, length: 1), NSRange(location: NSNotFound, length: 0)] {
            snapshot.selectedRange = range
            #expect(!snapshot.allowsCapture)
            #expect(!snapshot.allowsDelivery(capturedCaret: NSRange(location: 14, length: 0)))
        }
    }

    @Test("Changed identity and unavailable, secure or unknown editor attributes fail closed")
    func unsafeMetadataRejectsCapture() {
        let mutations: [(inout CapturedPasteTarget.Snapshot) -> Void] = [
            { $0.processID = 0 }, { $0.frontmostProcessID = nil }, { $0.frontmostProcessID = 43 },
            { $0.bundleIdentifier = "com.example.other" }, { $0.matchesCapturedFocus = false },
            { $0.role = nil }, { $0.role = "AXTextField" }, { $0.subrole = "AXSecureTextField" },
            { $0.subrole = "AXOther" }, { $0.subroleReadIsValid = false },
            { $0.enabledState = .value(false) }, { $0.enabledState = .unavailable },
            { $0.isEditable = false }, { $0.isEditable = nil }
        ]
        for mutate in mutations {
            var snapshot = ordinaryEditor()
            mutate(&snapshot)
            #expect(!snapshot.allowsCapture)
            #expect(!snapshot.allowsDelivery(capturedCaret: NSRange(location: 14, length: 0)))
        }
    }

    @Test("TextEdit unknown subrole and unsupported enabled retain the editability requirement")
    func observedTextEditMetadata() {
        var snapshot = ordinaryEditor()
        snapshot.subrole = "AXUnknown"
        snapshot.enabledState = .unsupported
        #expect(snapshot.allowsCapture)
        #expect(snapshot.allowsDelivery(capturedCaret: NSRange(location: 14, length: 0)))
        snapshot.isEditable = nil
        #expect(!snapshot.allowsCapture)
    }

    @Test("An absent TextEdit subrole requires both an absence result and a nil value")
    func absentSubroleRejectsMalformedValues() {
        for result: AXError in [.attributeUnsupported, .noValue] {
            #expect(CapturedPasteTarget.isValidSubroleRead(result: result, value: nil))
            for value: CFTypeRef in [kCFBooleanTrue, NSNumber(value: 2), "AXUnknown" as CFString] {
                #expect(!CapturedPasteTarget.isValidSubroleRead(result: result, value: value))
            }
        }
        #expect(CapturedPasteTarget.isValidSubroleRead(result: .success, value: "AXUnknown" as CFString))
        #expect(!CapturedPasteTarget.isValidSubroleRead(result: .success, value: nil))
        #expect(!CapturedPasteTarget.isValidSubroleRead(result: .success, value: kCFBooleanTrue))
        #expect(!CapturedPasteTarget.isValidSubroleRead(result: .cannotComplete, value: nil))
        #expect(!CapturedPasteTarget.isValidSubroleRead(result: .cannotComplete, value: "AXUnknown" as CFString))
    }
}
