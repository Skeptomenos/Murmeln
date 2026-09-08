<p align="center">
  <img src="icon/app-icon.png" alt="Murmeln" width="128" height="128">
</p>

<h1 align="center">Murmeln</h1>

<p align="center">
  <strong>Push-to-talk dictation for macOS — on-device first on Apple Silicon</strong>
</p>

<p align="center">
  Hold <kbd>Fn</kbd>, speak, release. Your words are pasted where you're typing.<br>
  An open-source, local-first alternative to cloud dictation apps.
</p>

---

## Mission

Murmeln turns spoken thought into pasted text with as little friction as possible — hold a key, speak, release, keep typing. It should feel trustworthy, fast, and invisible.

The best Murmeln experience runs **on-device on Apple Silicon**: your audio is transcribed locally and never leaves your Mac. Cloud and local-server backends remain supported as alternatives, but on-device is the center of the product.

---

## How it feels

**Push-to-talk** — Focus any text field, hold <kbd>Fn</kbd> (>400ms), speak, release. The text appears where your cursor is.

**Hands-free (lock mode)** — Double-tap <kbd>Right Option</kbd> to start recording without holding anything; tap it again to stop and paste. Good for longer dictation.

A minimal line indicator under the notch shows recording / processing state, so you always know what Murmeln is doing without it getting in your way.

If automatic paste is blocked, a persistent notice offers **Copy transcript**, **Check again**, **Show result in History**, and **Dismiss**. The notice does not take keyboard focus or display the transcript. The same actions remain in the menu.

Murmeln retains the exact final result in History before attempting paste. Denied paste permission leaves the clipboard unchanged. When Secure Input is active, automatic paste is limited to a verified ordinary TextEdit editor: the same editor and empty caret must remain selected from recording start through delivery. Other or unverifiable targets stay blocked. Murmeln does not read the editor's text to make this decision. Copy is an explicit action: click it, choose your text field, then press <kbd>⌘</kbd><kbd>V</kbd>. Check again only checks permission and Secure Input; clearing a blocker never causes a delayed paste. If another paste owns the clipboard, Copy reports busy and needs a fresh click.

History shows whether each result was saved. A failed save keeps the text available in the current session and cancels normal Quit. Retry save, copy the result, or use the separately confirmed **Quit anyway** action. Copy is not proof of a disk save. Successful Copy and Dismiss hide the notice and clear its warning icon without deleting the result. A failed or busy Copy keeps the notice actionable. At the 50-entry limit, Murmeln pauses capture if it cannot safely make space; save or explicitly delete an entry in History to continue.

If paste access is denied, **Open Accessibility Settings** opens the relevant System Settings page. Enable the exact Murmeln instance under **Privacy & Security → Accessibility**. Opening Settings does not grant access; Murmeln checks the permission again when you return. **Restart** waits for the replacement app to launch before exiting. A launch failure keeps the current app available and reports an error. If the new copy cannot be stopped after a failed restart, recording stays paused until that copy is quit.

Clipboard preservation is best effort across processes. Murmeln checks every advertised representation and the clipboard generation, and skips automatic paste when preservation is incomplete. A posted paste command does not prove the target inserted the text. File promises, target-read timing, process termination and power loss remain separate limits.

---

## Quick Start

### 1. Install the app

👉 [**Download the latest release**](https://github.com/Skeptomenos/Murmeln/releases/latest), open the DMG, and drag `Murmeln.app` to `/Applications`. Right-click → **Open** the first time (the app is unsigned).

<details>
<summary>Build from source</summary>

```bash
git clone https://github.com/Skeptomenos/Murmeln.git
cd Murmeln
xcodebuild -scheme Murmeln -configuration Release -derivedDataPath build build
cp -r build/Build/Products/Release/Murmeln.app /Applications/
```
</details>

<details>
<summary>Develop locally with stable signing</summary>

Use **Murmeln Dev** for local work. Create its dedicated signing identity once, then build:

```bash
bash scripts/setup-dev-signing.sh
bash scripts/build-dev.sh
```

Setup stores a non-extractable private key in your user keychain and trusts the certificate for code signing only. It reuses an existing identity and refuses to replace a damaged or ambiguous one. Keep this identity across rebuilds: ad-hoc signatures change the app identity and can leave Accessibility permission tied to an older build.

The build script requires that identity, verifies the signed app, and writes to `build-dev/`. It does not launch the app. Pass a different output directory if a build there is running. Switching from an older ad-hoc build may need a fresh Accessibility grant for the exact new Dev app, followed by a normal restart.

This local certificate is free and needs no Apple Developer account. It is not Developer ID signing or notarization for distribution. Production signing is unchanged. Run `bash validate.sh` after setup for the full local gate; it includes a check that different binaries retain the same signing requirement.

</details>

### 2. Set up on-device transcription (recommended)

Launch Murmeln → menu bar mic icon → **Settings…** → **Transcription**. Pick an on-device model and click **Download Model**. Murmeln shows live progress, continues downloads while you inspect another model, and lets you cancel an active download or delete an installed model later.

**Parakeet v3 (Multilingual)** is the default: it is fast, supports 25 languages, and auto-detects the spoken language. No account, terminal setup, or external runtime is required.

### 3. Grant permissions

| Permission | Why |
|------------|-----|
| **Microphone** | Record your voice (prompted on first use) |
| **Accessibility** | Global <kbd>Fn</kbd> hotkey — System Settings → Privacy & Security → Accessibility |

---

## On-device model catalog

All catalog models run in-process on Apple Silicon and download from the Settings UI.

| Model | Download | Languages | Notes |
|-------|----------|-----------|-------|
| **Parakeet v3 (Multilingual)** | ~470 MB | 25 | **Default.** Fast and language auto-detecting. |
| **Parakeet v2 (English)** | ~470 MB | English | Slightly higher English accuracy than v3. |
| **Cohere Transcribe INT8** | ~2.1 GB | 14 | Requires an explicit language. The first use after each app launch can take about 90 seconds and briefly use substantial memory. |
| **WhisperKit (Whisper)** | ~600 MB* | English, German, French, Spanish, Italian | Pick the dictation language explicitly; short utterances are unreliable with auto-detection. |

\*The concrete WhisperKit variant determines the exact download size.

## Other backends

Cloud and local-server backends remain available when you want them.

| Backend | Type | Notes |
|---------|------|-------|
| **Cloud (OpenAI · Groq · Gemini · GPT-4o)** | Cloud | Bring your own API key. Gemini and GPT-4o transcribe + refine in one call. |
| **Local Whisper Server** | Local server | Point at a compatible server on `localhost`. |

**Optional refinement** cleans up the raw transcript (grammar, filler words, formatting) using OpenAI, Google, Groq, or local **Ollama** — or turn it off entirely with **Raw Mode** for verbatim, maximum-speed output.

---

## Good to know

- **Prompt presets** shape how dictation is refined — *Casual*, *Structured*, *Markdown*, *Verbatim*, or your own custom presets. Built-in presets treat dictated content as text, never as commands.
- **Settings** — compact, resizable windows with plain sections on one background under Transcription, Refinement, Writing, and Recording. Choose System, Light, or Dark appearance in the sidebar; Dark is the default for Settings and History. Advanced prompt and server options expand when needed.
- **Personal dictionary** — teach the refiner to spell names, acronyms, and technical terms correctly (Settings → Writing).
- **History** — select a past dictation, read its full text, and choose **Copy Text**. Final and original text share a plain reading surface. A distinct original opens below the result for comparison. Prompt details stay collapsed. With Parallel Audit enabled, compare preset results under **Variants & prompt details**.
- **Update check** — Murmeln checks GitHub on launch and, when a newer version is out, opens the release page so you can download it.

### Limitation: password fields

Secure Input can prevent global hotkey observation. If <kbd>Fn</kbd> is not detected, leave the password or secure-entry field first. Murmeln also monitors Fn while its own UI is active. Hotkey detection and automatic-paste permission are separate checks.

---

## Requirements

- macOS 26.0 or later
- Apple Silicon
- For cloud backends: an API key for your chosen provider

---

## License

MIT — use it, fork it, improve it.

<p align="center">
  Built with ❤️ for fast, frictionless dictation.
</p>
