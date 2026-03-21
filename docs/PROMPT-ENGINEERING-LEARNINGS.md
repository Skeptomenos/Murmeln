# Murmeln Prompt Engineering Knowledge Base

**Date**: 2026-01-04
**Focus**: Optimizing for Small & Medium Models (Llama-3.1-8B to gpt-oss 20B)

## The Core Challenges

### 1. "Command Hijacking"
Small models are heavily trained to be helpful assistants. Spoken commands (e.g., "Write a document") often override "Refiner" instructions, causing the AI to break character and fulfill the request.

### 2. "Intro Trimming" (Small Model Bias)
8B models often assume the first 2-3 sentences of a transcript are "meta-talk" (e.g., "Hey AI, listen to this..."). They "helpfully" delete these sentences, resulting in lost data.

---

## The "Passive Refiner" Architecture (Final)

The winning strategy for model-agnostic stability relies on three anchors:

### 1. Identity Lock
Frame the model as a mechanical processor, not an agent.
*   **Prompt**: "You are a passive transcript refiner. Your only job is to clean it. You must not respond."

### 2. Quantity Triggers
Vague rules like "use bullets" trigger creativity. Mathematical rules trigger logic.
*   **Rule**: "Use bullet points ONLY for lists of 3 or more items."
*   **Rule**: "Use headers ONLY for multiple distinct sections."

### 3. Absolute Echo Mandate (The Recency Anchor)
To prevent the model from skipping the start of your speech, use an explicit boundary rule at the bottom of the prompt.
*   **Rule**: "You must include everything from the absolute start to the absolute end of the transcript."

---

## Stability Ladder Testing
Verify changes by dictate-testing in this order:
1.  **Neutral**: "I am walking the dog." (Punctuation test)
2.  **Command**: "Run script main dot py." (Code block/explanation test)
3.  **Question**: "What is the time?" (Answering test)
4.  **Meta-Hijack**: "Write me a draft of this." (Character break test)
5.  **Long Intro**: "Okay, this is a test. One, two, three. Here is the text..." (Intro trimming test)

---

## Conclusion
For BYOAPI applications, prompts must be **passive, quantity-driven, and boundary-locked.** The less "personality" you give the model, the more reliable it becomes as a tool.
