# Agent-assisted dictation testing

Use a dedicated development build for routine tests. Confirm its bundle identity, executable path, version, and signing requirement before testing. A successful build does not establish permission or delivery.

## Desktop handoff

Obtain a bounded desktop handoff before agent-driven microphone, keyboard, or clipboard tests. Prepare synthetic speech and a disposable receiver first. Stop when the user takes back the computer. Do not alter production permissions or replace an active app as test setup without authorization.

## Acceptance procedure

1. Verify the exact candidate has the required macOS permissions. A helper process having permission does not prove the app has permission.
2. Focus a disposable editable target. Record its initial text through an independent read.
3. Use synthetic speech with a fixed expected sentence. Exercise the normal push-to-talk path without repairing focus or manually pasting the result.
4. Read the complete receiver value independently. Confirm the previous text survives and the expected text appears exactly once.
5. Correlate the recording, History result, and terminal paste diagnostic by capture identifier. A posted keyboard command proves dispatch; it does not prove receiver insertion.
6. Check clipboard restoration only while the test still owns the clipboard. Preserve external changes. Do not retry a refused paste without a fresh target and focus check.
7. Record candidate identity, observed results, and remaining limits in private test evidence. Restore test-owned state and stop all helpers before returning control.

## Safety coverage

Test ordinary delivery separately from changed targets, secure fields, unverifiable targets, and external clipboard replacement. Keep untested cases explicit. Never weaken target validation or security checks to make a test pass.

Model-runtime checks, layout previews, source tests, and live receiver acceptance establish different boundaries. Reuse prior evidence only when its relevant source and environment still match. Keep recordings, target identifiers, transcripts, process details, and diagnostic logs out of public documentation and release assets.
