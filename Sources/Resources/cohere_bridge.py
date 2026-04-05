#!/usr/bin/env python3
"""
Murmeln Cohere bridge — persistent stdin/stdout protocol.
Messages on stdin: "<audio_path>|<language>\n"
Messages on stdout: "READY\n" (on startup), "OK|<transcript>\n" or "ERROR|<message>\n"

P0-2: All outgoing messages escape embedded newlines as literal \\n so Swift
processLine() receives exactly one protocol line per message.
"""

import sys

MODEL_ID = "CohereLabs/cohere-transcribe-03-2026"

try:
    from mlx_audio.stt import load

    model = load(MODEL_ID)
    print("READY", flush=True)
except Exception as e:
    msg = str(e).replace("\n", "\\n")
    print(f"LOAD_ERROR|{msg}", flush=True)
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
        transcript = result.text.strip().replace("\n", "\\n")
        print(f"OK|{transcript}", flush=True)
    except Exception as e:
        msg = str(e).replace("\n", "\\n")
        print(f"ERROR|{msg}", flush=True)
