# Murmeln

A lightweight macOS menu bar app for push-to-talk dictation. Hold the **Fn key** to record, release to transcribe and auto-paste into any application.

## Features

- **Push-to-Talk**: Hold Fn key to record, release to process
- **Multiple Transcription Providers**:
  - OpenAI Whisper
  - Groq Whisper (fast, free tier available)
  - GPT-4o Audio (native audio understanding)
  - Gemini 2.0 Flash (native audio understanding)
  - Local Whisper (self-hosted)
- **LLM Refinement**: Optional post-processing to clean up transcriptions
- **Auto-Paste**: Automatically pastes transcribed text into the focused application
- **Visual Feedback**: Floating overlay shows recording/processing status
- **Menu Bar Integration**: Lives quietly in your menu bar

## Requirements

- macOS 14.0 (Sonoma) or later
- API key for your chosen transcription provider (except Local Whisper)

## Installation

### From Source

```bash
git clone https://github.com/Skeptomenos/Murmeln.git
cd Murmeln
xcodebuild -scheme Murmeln -configuration Release build
```

The built app will be in `~/Library/Developer/Xcode/DerivedData/Murmeln-*/Build/Products/Release/Murmeln.app`

Copy it to `/Applications` and launch.

## Configuration

1. Click the microphone icon in the menu bar
2. Select **Settings...**
3. Configure your transcription provider and API key
4. Optionally configure LLM refinement for cleaner output

### Transcription Providers

| Provider | Speed | Cost | Notes |
|----------|-------|------|-------|
| OpenAI Whisper | Fast | $0.006/min | Most reliable |
| Groq Whisper | Very Fast | Free tier | Great for testing |
| GPT-4o Audio | Fast | Higher | Native audio, can refine in one call |
| Gemini 2.0 Flash | Fast | Free tier | Native audio, can refine in one call |
| Local Whisper | Varies | Free | Requires local server at `localhost:8080` |

### LLM Refinement

When enabled, transcriptions are post-processed by an LLM to:
- Remove filler words ("um", "uh", "like")
- Fix grammar and punctuation
- Structure text more clearly

Native audio models (GPT-4o Audio, Gemini 2.0 Flash) can do transcription and refinement in a single API call.

## Permissions

Murmeln requires the following permissions:

### Microphone Access
Required for audio recording. macOS will prompt on first use.

### Accessibility Access
Required for the Fn key hotkey to work globally. Grant in:
**System Settings → Privacy & Security → Accessibility**

### Automation (System Events)
Required for auto-paste functionality. macOS will prompt on first use.

## Usage

1. Launch Murmeln (appears in menu bar as a microphone icon)
2. Focus the application where you want text inserted
3. **Hold Fn key** to start recording
4. Speak your text
5. **Release Fn key** to stop and process
6. Text is automatically pasted

### Menu Bar Icons

- 🎤 `mic` - Ready
- 🎤 `mic.fill` - Recording
- ✨ `sparkles` - Processing

## Architecture

Built with Swift 6 and strict concurrency:
- SwiftUI for UI
- Actor-based audio recording for thread safety
- Async/await throughout (no Combine)
- AppleScript for reliable paste simulation

## Troubleshooting

### "Murmeln would like to access the microphone"
Click **OK** to grant. Required for recording.

### Fn key not working
1. Open **System Settings → Privacy & Security → Accessibility**
2. Find Murmeln and enable it
3. You may need to remove and re-add the app

### Text not pasting
1. When prompted, allow Murmeln to control System Events
2. Ensure the target application accepts keyboard input

### Microphone permission keeps asking
This happens with ad-hoc signed builds. For persistent permission, the app needs proper code signing.

## License

MIT

## Credits

Built with ❤️ for fast, frictionless dictation.
