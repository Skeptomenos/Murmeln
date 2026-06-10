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

If Murmeln can't deliver the paste because Accessibility isn't granted or you're in a password field, it tells you and leaves the transcript on your clipboard — so a manual <kbd>⌘</kbd><kbd>V</kbd> recovers your words instead of losing them.

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

### 2. Set up on-device transcription (recommended)

Murmeln's primary backend is **Cohere on-device via MLX** — fast, fully local, multilingual, and the recommended way to use the app. It needs a one-time setup:

```bash
# 1. Install the on-device speech engine (Python 3.10+, Apple Silicon)
pip install mlx-audio

# 2. Accept the model terms once at:
#    https://huggingface.co/CohereLabs/cohere-transcribe-03-2026
# 3. Authenticate Hugging Face so the model can download:
hf auth login
```

Then launch Murmeln → menu bar mic icon → **Settings…** → **Transcription** → select **Cohere (On-Device)**. The model downloads on first use and stays loaded for instant transcription afterwards.

> Prefer zero setup? Choose **WhisperKit (On-Device)** instead — it runs entirely in-app with no Python and no account, just a slightly slower model download. Or use a cloud provider with your own API key (see [Backends](#backends)).

### 3. Grant permissions

| Permission | Why |
|------------|-----|
| **Microphone** | Record your voice (prompted on first use) |
| **Accessibility** | Global <kbd>Fn</kbd> hotkey — System Settings → Privacy & Security → Accessibility |

---

## Backends

On-device is the recommended path; cloud and local-server backends are supported alternatives when you want them.

| Backend | Type | Notes |
|---------|------|-------|
| **Cohere (On-Device)** | Local · MLX | **Recommended.** Fast, multilingual, runs on-device. Needs the one-time setup above. |
| **WhisperKit (On-Device)** | Local · CoreML | Zero-config local option, downloads its model in-app. |
| **Cloud (OpenAI · Groq · Gemini · GPT-4o)** | Cloud | Bring your own API key. Gemini and GPT-4o transcribe + refine in one call. |
| **Local Whisper Server** | Local server | Point at a compatible server on `localhost`. |

**Optional refinement** cleans up the raw transcript (grammar, filler words, formatting) using OpenAI, Google, Groq, or local **Ollama** — or turn it off entirely with **Raw Mode** for verbatim, maximum-speed output.

---

## Good to know

- **Prompt presets** shape how dictation is refined — *Casual*, *Structured*, *Markdown*, *Verbatim*, or your own custom presets. Built-in presets treat dictated content as text, never as commands.
- **Personal dictionary** — teach the refiner to spell names, acronyms, and technical terms correctly (Settings → Prompt).
- **History** — review past dictations from the menu bar; with Parallel Audit enabled, compare what different presets produced from the same transcript.
- **Update check** — Murmeln checks GitHub on launch and, when a newer version is out, opens the release page so you can download it.

### Limitation: password fields

The <kbd>Fn</kbd> hotkey can't fire while a password field or other macOS "Secure Input" context is focused (Terminal under `sudo`/`ssh`, password managers, auth dialogs). Click outside the secure field first, or trigger recording from the menu bar.

---

## Requirements

- macOS 14.0 (Sonoma) or later
- On-device backends (Cohere/MLX, WhisperKit) require **Apple Silicon**; cloud and local-server backends also run on Intel Macs
- For Cohere on-device: Python 3.10+ with `mlx-audio`, plus a free Hugging Face account to download the (gated) model once
- For cloud backends: an API key for your chosen provider

---

## License

MIT — use it, fork it, improve it.

<p align="center">
  Built with ❤️ for fast, frictionless dictation.
</p>
