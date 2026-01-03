# Handover: Prompt Engineering für Murmeln

**Erstellt:** 2026-01-04
**Status:** Offen - zur Delegation

---

## Kontext

Murmeln ist eine Push-to-Talk Dictation App für macOS. Nach der Transkription wird der Text durch ein LLM "refined" (Filler-Words entfernen, Grammatik, optional Strukturierung).

Wir haben **Prompt Presets** implementiert:
- Casual (WhatsApp, Chat)
- Structured (Listen, Notizen)
- LLM Prompt (für AI-Prompts)
- Verbatim (minimal)
- Custom

---

## Problem

Der **LLM Prompt** Preset ist schwer zu balancieren:

| Zu wenig | Genau richtig | Zu viel (aktuell) |
|----------|---------------|-------------------|
| Nur Cleanup, keine Struktur | Markdown-Headers für Themen, Bullet Points für Listen | Erfindet Templates, Platzhalter, Code, Tabellen |

### Beispiel des Problems

**Input (gesprochen):**
> "Bitte erstelle ein Handover-Dokument bezüglich LLM-Optimierung damit wir das in einer anderen Session übergeben können"

**Output (70B Modell):**
```markdown
## Hand-Over-Document für LLM-Optimierung
### Aktueller Stand
* Wir haben bereits [listieren Sie hier die bisherigen Schritte]
* Wir haben [listieren Sie hier die Herausforderungen]
...
```

Das Modell hat Platzhalter und Template-Struktur erfunden, die nie gesprochen wurden.

---

## Was wir versucht haben

### Prompt-Iterationen

1. **Erste Version (zu kreativ):**
   ```
   Structure this as a clear AI prompt. Use markdown (headers, lists, code blocks) where appropriate.
   ```
   → Ergebnis: Komplette Dokumentation mit Code-Beispielen

2. **Zweite Version (zu restriktiv):**
   ```
   Fix grammar and punctuation. Do NOT add content, structure, examples, code, or formatting that wasn't spoken.
   ```
   → Ergebnis: Nur Cleanup, keine Struktur

3. **Dritte Version (balanciert, aber immer noch zu kreativ):**
   ```
   Clean up this dictation. Fix grammar and punctuation. Use markdown headers (##) only if the speaker clearly separates topics. Use bullet points only for items the speaker listed. NEVER add placeholders, templates, examples, or content not explicitly spoken.
   ```
   → Ergebnis: Immer noch Templates und Platzhalter

### Modell-Beobachtungen

| Modell | Verhalten |
|--------|-----------|
| `llama-3.3-70b-versatile` | Zu "hilfreich", erfindet Struktur |
| `llama-3.1-8b-instant` | Folgt Anweisungen wörtlicher, weniger kreativ |

---

## Offene Fragen

1. **Ist der LLM Prompt Preset überhaupt sinnvoll?**
   - Casual funktioniert gut für die meisten Use Cases
   - Vielleicht ist "strukturieren für LLM" ein Anti-Pattern

2. **Modell vs. Prompt:**
   - Ist das Problem der Prompt oder das 70B Modell?
   - Sollten wir für LLM Prompt automatisch ein kleineres Modell empfehlen?

3. **Alternativer Ansatz:**
   - Statt "strukturiere für LLM" vielleicht "formatiere als Markdown"?
   - Oder zwei Stufen: Erst Verbatim transkribieren, dann optional strukturieren?

---

## Empfehlung

1. **Kurzfristig:** LLM Prompt Preset entfernen oder umbenennen zu "Markdown" mit sehr restriktivem Prompt
2. **Testen:** `llama-3.1-8b-instant` statt 70B für diesen Use Case
3. **Langfristig:** User-Feedback sammeln, welche Presets tatsächlich genutzt werden

---

## Dateien

- `Sources/Models/AppSettings.swift` - PromptPreset enum mit allen Prompts
- `Sources/Views/SettingsView.swift` - Preset-Picker UI

---

## Nächste Schritte für diese Session

1. Prompt weiter iterieren ODER
2. LLM Prompt Preset vorerst entfernen ODER
3. Kleineres Modell testen

Entscheidung liegt beim Bearbeiter dieser Session.
