#!/usr/bin/env python3
"""
Murmeln Cohere bridge — persistent stdin/stdout protocol.
Messages on stdin: "<audio_path>|<language>\n"
Messages on stdout: "READY\n" (on startup), "OK|<transcript>\n" or "ERROR|<message>\n"
"""

import sys

MODEL_ID = "CohereLabs/cohere-transcribe-03-2026"

try:
    from mlx_audio.stt import load

    model = load(MODEL_ID)
    print("READY", flush=True)
except Exception as e:
    print(f"LOAD_ERROR|{e}", flush=True)
    sys.exit(1)

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    parts = line.split("|", 1)
    audio_path = parts[0]
    language = parts[1] if len(parts) > 1 else "en"
    try:
        result = model.generate(audio_path, language=language)
        transcript = result.text.strip()
        print(f"OK|{transcript}", flush=True)
    except Exception as e:
        print(f"ERROR|{e}", flush=True)
