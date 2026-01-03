<p align="center">
  <img src="icon/app-icon.png" alt="Murmeln" width="128" height="128">
</p>

<h1 align="center">Murmeln</h1>

<p align="center">
  <strong>Push-to-talk dictation for macOS — Bring Your Own API Key</strong>
</p>

<p align="center">
  An open-source alternative to Wispr and similar apps.<br>
  Hold <kbd>Fn</kbd> to record, or double-tap <kbd>Right Option</kbd> for hands-free mode.
</p>

---

## Why Murmeln?

Love the idea of voice dictation apps but want to:
- **Use your own API keys** instead of paying subscription fees?
- **Choose your provider** — OpenAI, Groq, Gemini, or self-hosted?
- **Keep it simple** — no account, no cloud sync, just dictation?

Murmeln is for you. It's the **BYOAPI** (Bring Your Own API) dictation tool.

---

## Features

| Feature | Description |
|---------|-------------|
| **Push-to-Talk** | Hold Fn key to record, release to process |
| **Lock Recording** | Double-tap Right Option for hands-free recording |
| **Multiple Providers** | OpenAI Whisper, Groq, GPT-4o Audio, Gemini 2.0 Flash, Local Whisper |
| **Smart Refinement** | LLM cleans up filler words, fixes grammar |
| **Auto-Paste** | Transcribed text is pasted directly into your focused app |
| **Visual Feedback** | Minimal line indicator under notch shows status |
| **Menu Bar App** | Lives quietly in your menu bar |

---

## Quick Start

### 1. Install

**Download the latest release:**

👉 [**Download Murmeln v1.0.0**](https://github.com/Skeptomenos/Murmeln/releases/latest)

1. Download `Murmeln-v1.0.0.zip`
2. Unzip and drag `Murmeln.app` to `/Applications`
3. Right-click → **Open** (required for unsigned apps)

<details>
<summary><strong>Build from source</strong></summary>

```bash
git clone https://github.com/Skeptomenos/Murmeln.git
cd Murmeln
xcodebuild -scheme Murmeln -configuration Release -derivedDataPath build build
cp -r build/Build/Products/Release/Murmeln.app /Applications/
```
</details>

### 2. Configure

1. Launch Murmeln (appears in menu bar)
2. Click the mic icon → **Settings...**
3. Add your API key for your preferred provider

### 3. Use

**Push-to-Talk Mode:**
1. Focus any text field
2. **Hold Fn** (>400ms) → speak → **release Fn**
3. Text appears automatically

**Lock Recording Mode:**
1. Focus any text field
2. **Double-tap Right Option** → speak hands-free
3. **Tap Right Option** again to stop
4. Text appears automatically

---

## Providers

| Provider | Speed | Cost | One-Call Refinement |
|----------|-------|------|---------------------|
| **Gemini 2.0 Flash** | Fast | Free tier | ✅ Yes |
| **Groq Whisper** | Very Fast | Free tier | ❌ No |
| **OpenAI Whisper** | Fast | $0.006/min | ❌ No |
| **GPT-4o Audio** | Fast | Higher | ✅ Yes |
| **Local Whisper** | Varies | Free | ❌ No |

> **Tip:** Gemini 2.0 Flash is recommended — fast, free tier, and handles transcription + refinement in one API call.

---

## Permissions

Murmeln needs three permissions to work:

| Permission | Why | How to Grant |
|------------|-----|--------------|
| **Microphone** | Record your voice | Prompt on first use |
| **Accessibility** | Global Fn key hotkey | System Settings → Privacy & Security → Accessibility |
| **Automation** | Auto-paste text | Prompt on first use |

---

## Troubleshooting

<details>
<summary><strong>Fn key not working</strong></summary>

1. Open **System Settings → Privacy & Security → Accessibility**
2. Find Murmeln and toggle it **off** then **on**
3. Restart Murmeln
</details>

<details>
<summary><strong>Text not pasting</strong></summary>

1. Allow Murmeln to control System Events when prompted
2. Make sure the target app has an active text field
</details>

<details>
<summary><strong>Microphone permission keeps asking</strong></summary>

This happens with unsigned builds. For persistent permission, the app needs code signing with a Developer ID.
</details>

---

## Requirements

- macOS 14.0 (Sonoma) or later
- API key for your chosen provider (except Local Whisper)

---

## Tech Stack

- **Swift 6** with strict concurrency
- **SwiftUI** for the UI
- **Actor-based** audio recording
- **Async/await** throughout

---

## License

MIT — Use it, fork it, improve it.

---

<p align="center">
  Built with ❤️ for fast, frictionless dictation.
</p>
