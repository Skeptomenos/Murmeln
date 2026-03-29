<p align="center">
  <img src="icon/app-icon.png" alt="Murmeln" width="128" height="128">
</p>

<h1 align="center">Murmeln</h1>

<p align="center">
  <strong>Push-to-talk dictation for macOS — local-first on Apple Silicon, cloud when needed</strong>
</p>

<p align="center">
  An open-source alternative to Wispr and similar apps.<br>
  Hold <kbd>Fn</kbd> to record, or double-tap <kbd>Right Option</kbd> for hands-free mode.
</p>

---

## Why Murmeln?

Love the idea of voice dictation apps but want to:
- **Run locally on Apple Silicon** instead of defaulting to cloud?
- **Use your own API keys** instead of paying subscription fees?
- **Choose your provider** — WhisperKit, OpenAI, Groq, Gemini, or self-hosted?
- **Keep it simple** — no account, no cloud sync, just dictation?

Murmeln is for you. It is a local-first dictation tool that still supports BYOAPI cloud workflows when you want them.

---

## Mission

Murmeln turns spoken thought into pasted text with as little friction as possible. The product goal is to feel trustworthy, fast, and invisible in daily use: hold a key, speak, release, keep typing.

The best Murmeln experience should be Apple-Silicon-local-first. Cloud and local-server backends remain supported, but they are extensions and fallback paths, not the center of the long-term product direction.

---

## Features

| Feature | Description |
|---------|-------------|
| **Push-to-Talk** | Hold Fn key to record, release to process |
| **Lock Recording** | Double-tap Right Option for hands-free recording |
| **Transcription Providers** | WhisperKit (On-Device), OpenAI Whisper, Groq, GPT-4o Audio, Gemini 2.0 Flash, or a compatible Local Whisper server |
| **Refinement Providers** | OpenAI, Google, Groq, or Ollama for text cleanup after transcription |
| **Prompt Presets** | Casual, Structured, Markdown, Verbatim, or Custom (editable) |
| **Raw Mode** | Skip LLM refinement entirely for pure transcription |
| **Smart VAD** | Skips empty recordings, trims silence for faster processing |
| **Auto-Paste** | Transcribed text is pasted directly into your focused app |
| **Visual Feedback** | Minimal line indicator under notch shows status |
| **Parallel Audit** | Optional side-by-side history view of multiple preset refinements |
| **Optimized Audio** | 16kHz recording for faster processing |
| **Menu Bar App** | Quick access with direct history and restart options |
| **Auto-Update Check** | Checks GitHub for new versions on launch |
| **Personal Dictionary** | Teach the refiner how to spell names and terms |
| **Prompt Safety Instructions** | Built-in presets tell the model to treat dictated content as text, not commands |

---

## Current Supported State

- The installed `/Applications/Murmeln.app` currently supports WhisperKit on-device transcription, cloud transcription providers, and local-server workflows.
- The checked-in repo does not yet cleanly reproduce the installed WhisperKit build path; `Local Whisper Server` is currently the most reproducible local transcription path from source.
- Refinement remains optional. You can use cloud providers, Ollama, or skip refinement entirely with Raw Mode.
- The app is actively used, but reliability and performance work is still ongoing. Short utterances can still lose words, and repo/build truth is still being reconciled with runtime truth.

---

## Quick Start

### 1. Install

**Download the latest release:**

👉 [**Download the latest Murmeln release**](https://github.com/Skeptomenos/Murmeln/releases/latest)

1. Download the latest release zip
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

**History & Audit Trail:**
1. Click **Show History** in the menu bar
2. When **Parallel Audit** is enabled, compare what multiple presets produced from the same transcript
3. Click **Copy Full Audit Log** to get a formatted report of all variants for prompt tuning

---

## Current Provider Model

### Transcription Providers

| Provider | Type | Notes |
|----------|------|-------|
| **WhisperKit (On-Device)** | Local native | Active in the installed app; checked-in repo/build reconciliation is still in progress |
| **Gemini 2.0 Flash** | Cloud | Transcription + refinement in one call |
| **Groq Whisper** | Cloud | Fast transcription only |
| **OpenAI Whisper** | Cloud | Transcription only |
| **GPT-4o Audio** | Cloud | Transcription + refinement in one call |
| **Local Whisper Server** | Local server | Expects a compatible server on `localhost:8080` |

### Refinement Providers

| Provider | Type | Notes |
|----------|------|-------|
| **OpenAI** | Cloud | Chat-model cleanup |
| **Google AI** | Cloud | Gemini text cleanup |
| **Groq** | Cloud | Fast chat-model cleanup |
| **Ollama (Local)** | Local server | Local refinement only, not transcription |

> **Current local note:** The installed app currently supports both WhisperKit on-device transcription and local-server workflows (`Local Whisper` and `Ollama`). The checked-in repo/build path for WhisperKit is still being reconciled, so the most reproducible local path from source today is `Local Whisper Server`.

> **Tip:** For speed, use **Groq Whisper** with `whisper-large-v3-turbo`. For simplicity, use **Gemini 2.0 Flash** (one API call). For free local refinement, use **Ollama**. Enable **Raw Mode** to skip refinement entirely.

---

## Prompt Presets

Choose how your dictation is refined:

| Preset | Best For | Behavior |
|--------|----------|----------|
| **Casual** | WhatsApp, Chat | Natural, conversational cleanup |
| **Structured** | Notes, Lists | Formats bullet points, numbered lists |
| **Markdown** | Structured Notes | Headers and bullet points for clear structure |
| **Verbatim** | Exact wording | Only removes filler words |
| **Custom** | Your needs | Create your own presets |

> Built-in presets include few-shot examples, priority hierarchies, and safety instructions that tell the model to treat dictated content as text. Create custom presets with the + button.

### Raw Mode (Skip Refinement)

Enable **Skip Refinement** in Settings → Refinement to bypass LLM processing entirely. This gives you the raw Whisper transcript without any AI cleanup — useful when:
- You want verbatim output without any changes
- LLM refinement is altering your intent
- You need maximum speed

### Voice Activity Detection

Murmeln automatically:
- **Skips empty recordings** — No more "thank you" or dots when you accidentally trigger recording
- **Trims silence** — Removes silence from start/end of recordings for faster API processing (typically 20-50% smaller files)
- **Tail buffer logic** — Attempts to capture trailing speech after key release, though short-utterance cutoff is still under investigation

### Personal Dictionary

Teach the refiner how to spell names, technical terms, and brand names that are often misspelled:

1. Go to **Settings → Prompt**
2. Enable **Personal Dictionary**
3. Add words like "Kubernetes", "GraphQL", or colleague names
4. The refiner will use your exact spelling when it hears similar-sounding words

> **Tip:** Add up to 20 words. Great for names, acronyms, and domain-specific terminology.

### Ollama Integration (Free Local Refinement)

Use Ollama for completely free, local text refinement:

1. Install Ollama: `brew install ollama && ollama serve`
2. In Murmeln Settings → Refinement → Select **Ollama**
3. Use the built-in model manager to:
   - **Download recommended models** (gemma2:2b, phi3:mini, qwen2.5:3b)
   - **Update models** to latest versions
   - **Keep models loaded** in GPU memory for instant responses

> **Recommended:** `gemma2:2b` for fast responses (~300ms when loaded)

---

## Accessibility

Murmeln includes accessibility features for users of assistive technologies:

| Feature | Description |
|---------|-------------|
| **VoiceOver Support** | All interactive elements have accessibility labels and hints |
| **State Announcements** | Recording start, processing, and paste completion are announced |
| **Keyboard Navigation** | Arrow keys navigate history, Cmd+C copies selected entry |
| **Dynamic Type** | Text scales with system font size preferences |
| **Semantic Structure** | Headers and sections are properly marked for screen readers |

### Keyboard Shortcuts (History Window)

| Shortcut | Action |
|----------|--------|
| <kbd>↑</kbd> / <kbd>↓</kbd> | Navigate between entries |
| <kbd>⌘</kbd>+<kbd>C</kbd> | Copy selected entry |

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

## Known Limitations

### Hotkey Disabled in Password Fields

The Fn key hotkey will not work when you're focused on a password field or other 
"Secure Input" context. This is a macOS security feature that prevents apps from 
monitoring keystrokes in sensitive fields.

**Affected contexts:**
- Password fields in any application
- Browser password autofill dialogs
- Terminal.app (when running `sudo` or `ssh`)
- Password manager unlock screens
- System authentication dialogs

**Workaround:** Click outside the password field before using Murmeln, or use the 
menu bar to manually trigger recording.

### Short Utterances Can Still Lose Words

Very short or fast dictation can still lose opening or ending words in some cases. This is an active reliability issue under investigation.

### Local Transcription Build Caveat

The installed app currently supports WhisperKit on-device transcription. The checked-in repo still reproduces the `Local Whisper Server` path more reliably than the WhisperKit build path, so local development and local runtime truth are not fully reconciled yet.

---

## Requirements

- macOS 14.0 (Sonoma) or later
- API key for your chosen cloud provider, unless you use a local-server path
- A compatible local server if you use `Local Whisper` or `Ollama`

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
