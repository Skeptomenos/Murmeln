import Foundation
import Testing
@testable import mrml

@Suite("Paste Operational Record Tests")
struct PasteOperationalRecordTests {
    @Test("Inspection refusal categories round trip through the closed record", arguments: [
        PasteTargetInvalidationReason.inspectionTimedOut, .metadataUnavailable, .unsupportedStructure
    ])
    func inspectionReasonRoundTrips(reason: PasteTargetInvalidationReason) throws {
        let record = try #require(PasteOperationalRecord(timestamp: "now", appVersion: "1", appBuild: "1",
            captureID: "capture", timing: PasteTiming(commandOutcome: .blocked(.cancelled),
                clipboardDisposition: .unchanged, commandSentElapsedMs: nil, totalElapsedMs: 0,
                pasteAttemptID: "attempt", decision: .init(stage: .initialPreflight, reason: .targetInvalid,
                    targetPolicy: .unverifiedNotion, targetInvalidation: reason))))
        #expect(try JSONDecoder().decode(PasteOperationalRecord.self, from: JSONEncoder().encode(record)) == record)
    }

    @Test("Version one records remain readable with unknown diagnostics and code identity")
    func legacyRecordRemainsReadable() throws {
        let data = Data("""
        {"schema_version":1,"event":"paste_attempt","level":"info","timestamp":"now","app_version":"1","app_build":"1","capture_id":"c","paste_attempt_id":"p","command_outcome":"posted","clipboard_disposition":"restored","blocker":null,"post_access_state":true,"secure_input_state":false,"elapsed_ms":1}
        """.utf8)
        let record = try JSONDecoder().decode(PasteOperationalRecord.self, from: data)
        #expect(record.schemaVersion == 1 && record.decision == nil && record.appCodeHash == nil)
        #expect(try JSONDecoder().decode(PasteOperationalRecord.self, from: JSONEncoder().encode(record)) == record)
        var extended = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        extended["target_policy"] = "legacy"
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(PasteOperationalRecord.self, from: JSONSerialization.data(withJSONObject: extended))
        }
    }

    @Test("Version two round trips the sampled decision, modifier masks and running code identity")
    func diagnosticRecordRoundTrips() throws {
        let record = try diagnosticRecord()
        #expect(record.schemaVersion == 2)
        #expect(record.appCodeHash == String(repeating: "a", count: 40))
        #expect(record.decision?.modifiers == .init(before: 0, atDecision: 0x20000000))
        #expect(try JSONDecoder().decode(PasteOperationalRecord.self, from: JSONEncoder().encode(record)) == record)
    }

    @Test("Version two rejects open or inconsistent diagnostic fields", arguments: [
        "unknown_stage", "unknown_reason", "unknown_policy", "unknown_invalidation", "partial_decision",
        "partial_modifiers", "missing_modifiers", "negative_flags", "string_flags", "wrong_stage",
        "wrong_blocker", "posted_reason", "unrelated_invalidation", "missing_target_invalidation",
        "invalid_hash", "uppercase_hash", "extra_payload", "unknown_version"
    ])
    func rejectsInvalidDiagnosticSchema(change: String) throws {
        let encoded = try JSONEncoder().encode(diagnosticRecord())
        var fields = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        switch change {
        case "unknown_stage": fields["decision_stage"] = "arbitrary"
        case "unknown_reason": fields["decision_reason"] = "arbitrary"
        case "unknown_policy": fields["target_policy"] = "arbitrary"
        case "unknown_invalidation": fields["target_invalidation"] = "arbitrary"
        case "partial_decision": fields["decision_reason"] = NSNull()
        case "partial_modifiers": fields["modifier_flags_before"] = NSNull()
        case "missing_modifiers": fields.removeValue(forKey: "modifier_flags_before")
        case "negative_flags": fields["modifier_flags_before"] = -1
        case "string_flags": fields["modifier_flags_at_decision"] = "raw"
        case "wrong_stage": fields["decision_stage"] = "admission"
        case "wrong_blocker": fields["blocker"] = "secure_input_active"
        case "posted_reason": fields["decision_reason"] = "command_posted"
        case "unrelated_invalidation": fields["target_invalidation"] = "caret_changed"
        case "missing_target_invalidation": fields["decision_reason"] = "target_invalid"
        case "invalid_hash": fields["app_code_hash"] = "not a code identity"
        case "uppercase_hash": fields["app_code_hash"] = String(repeating: "A", count: 40)
        case "extra_payload": fields["window_title"] = "must remain forbidden"
        case "unknown_version": fields["schema_version"] = 3
        default: Issue.record("unhandled case")
        }
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(PasteOperationalRecord.self, from: JSONSerialization.data(withJSONObject: fields))
        }
    }

    private func diagnosticRecord() throws -> PasteOperationalRecord {
        try #require(PasteOperationalRecord(timestamp: "now", appVersion: "2.3.0", appBuild: "1",
            appCodeHash: String(repeating: "a", count: 40), captureID: "capture", timing: PasteTiming(
                commandOutcome: .blocked(.cancelled), clipboardDisposition: .restored,
                commandSentElapsedMs: nil, totalElapsedMs: 100, pasteAttemptID: "attempt",
                postAccessState: true, secureInputState: false,
                decision: .init(stage: .beforePost, reason: .modifiersChanged, targetPolicy: .legacy,
                    modifiers: .init(before: 0, atDecision: 0x20000000)))))
    }

    @Test("Decoder rejects forbidden extra fields", arguments: ["transcript", "clipboard_data", "target_app", "pid", "path", "owner", "error_description"])
    func decoderRejectsExtraFields(field: String) throws {
        let data = Data("""
        {"schema_version":1,"event":"paste_attempt","level":"info","timestamp":"now","app_version":"1","app_build":"1","capture_id":"c","paste_attempt_id":"p","command_outcome":"posted","clipboard_disposition":"restored","blocker":null,"post_access_state":true,"secure_input_state":false,"elapsed_ms":1,"\(field)":"forbidden"}
        """.utf8)
        #expect(throws: DecodingError.self) { _ = try JSONDecoder().decode(PasteOperationalRecord.self, from: data) }
    }

    @Test("Posted record encodes the exact privacy allowlist")
    func postedRecordEncodesExactPrivacyAllowlist() throws {
        let timing = PasteTiming(
            commandOutcome: .posted,
            clipboardDisposition: .restored,
            commandSentElapsedMs: 10,
            totalElapsedMs: 20,
            pasteAttemptID: "attempt-posted",
            postAccessState: true,
            secureInputState: false
        )
        let record = try #require(PasteOperationalRecord(
            timestamp: "2026-08-15T12:00:00.000Z",
            appVersion: "2.6.1",
            appBuild: "626",
            captureID: "capture-posted",
            timing: timing
        ))

        let data = try JSONEncoder().encode(record)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let allowedKeys: Set<String> = [
            "schema_version", "event", "level", "timestamp", "app_version", "app_build",
            "capture_id", "paste_attempt_id", "command_outcome", "clipboard_disposition",
            "blocker", "post_access_state", "secure_input_state", "elapsed_ms",
            "app_code_hash", "decision_stage", "decision_reason", "target_policy", "target_invalidation",
            "modifier_flags_before", "modifier_flags_at_decision",
        ]

        #expect(Set(object.keys) == allowedKeys)
        #expect(object["schema_version"] as? Int == 2)
        #expect(object["event"] as? String == "paste_attempt")
        #expect(object["level"] as? String == "info")
        #expect(object["command_outcome"] as? String == "posted")
        #expect(object["clipboard_disposition"] as? String == "restored")
        #expect(object["blocker"] is NSNull)
        #expect(object["post_access_state"] as? Bool == true)
        #expect(object["secure_input_state"] as? Bool == false)

        let json = try #require(String(data: data, encoding: .utf8))
        for forbidden in [
            "transcript", "text_length", "clipboard_data", "target_app", "pid", "path",
            "account_id", "prompt", "model_output", "error_description",
        ] {
            #expect(!json.contains(forbidden))
        }
    }

    @Test("Blocked record derives warning, exact blocker, and unchecked Secure Input")
    func blockedRecordDerivesSafeFields() throws {
        let timing = PasteTiming(
            commandOutcome: .blocked(.postEventAccessDenied),
            clipboardDisposition: .transcriptPreserved,
            commandSentElapsedMs: nil,
            totalElapsedMs: 21,
            pasteAttemptID: "attempt-blocked",
            postAccessState: false,
            secureInputState: nil
        )
        let record = try #require(PasteOperationalRecord(
            timestamp: "2026-08-15T12:00:00.000Z",
            appVersion: "2.6.1",
            appBuild: "626",
            captureID: "capture-blocked",
            timing: timing
        ))

        let data = try JSONEncoder().encode(record)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["level"] as? String == "warning")
        #expect(object["command_outcome"] as? String == "blocked")
        #expect(object["blocker"] as? String == "post_event_access_denied")
        #expect(object["post_access_state"] as? Bool == false)
        #expect(object["secure_input_state"] is NSNull)
    }

    @Test("Not-attempted timing cannot create an operational record")
    func notAttemptedCannotCreateRecord() {
        let timing = PasteTiming(
            commandOutcome: .notAttempted,
            clipboardDisposition: .unchanged,
            commandSentElapsedMs: nil,
            totalElapsedMs: 0
        )

        #expect(PasteOperationalRecord(
            timestamp: "2026-08-15T12:00:00.000Z",
            appVersion: "2.6.1",
            appBuild: "626",
            captureID: "capture-empty",
            timing: timing
        ) == nil)
    }

    @Test("Decoder rejects an invalid event or outcome invariant")
    func decoderRejectsInvalidInvariant() throws {
        let invalid = Data(
            """
            {"schema_version":1,"event":"arbitrary","level":"info","timestamp":"now","app_version":"1","app_build":"1","capture_id":"c","paste_attempt_id":"p","command_outcome":"blocked","clipboard_disposition":"restored","blocker":null,"post_access_state":null,"secure_input_state":null,"elapsed_ms":1}
            """.utf8
        )

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(PasteOperationalRecord.self, from: invalid)
        }
    }
}
