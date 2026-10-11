---
name: ps2-investigate
description: Investigate a PS2 modification read-only before proposing a bounded patch.
---

Read AGENTS.md and .agents/AGENTS.md. Identify exact image revision, size, SHA-256, and requested observable change. Never write the source.

Inspect bounded metadata, relevant file layout, executable headers, and byte ranges. Distinguish disc offsets from executable virtual addresses. Document how candidates were found; never assume regions/revisions share addresses.

Propose patches only when original bytes and interpretation have evidence. Include offsets, expected/replacement bytes, rationale, uncertainties, and an emulator verification scenario. Length-changing assets or filesystem rebuilds need game-specific work outside the initial patch engine. Report missing prerequisites or unsupported changes; never fabricate a patch.
