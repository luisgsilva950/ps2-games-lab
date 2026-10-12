# Changelog

## 2026-10-12

- Added validated per-game PCSX2 2.8.2 resolution, renderer, texture filtering, audio synchronization, and frame-limiter settings. Save, reset-to-inherit, and save-and-launch work without AI credentials or ISO modifications; launch failures retain saved settings.
- Made settings the primary game workspace controls and kept the existing SSE assistant optional/collapsible. Composer drafts, provider/model selections, and expanded state survive tuning submissions; final stream refreshes also preserve unsaved tuning choices.
- Apply tuning through native per-disc PCSX2 configuration while retaining preexisting native tuning values for reset, unrelated controller overrides, and saves. Refuse playback launches while PCSX2 is already running rather than closing the user's session.
- Removed lab control mapping, keyboard profiles, game assignments, and PCSX2 import/export hooks. Existing native PCSX2 settings and exported profiles remain user-controlled.
- Documented PS5 DualSense USB/Bluetooth setup and configuration in the lab-launched PCSX2 instance; added an in-app setup guide.
- Redesigned the library and conversation workspace with a neutral palette, compact navigation, clearer hierarchy, and responsive layouts. ISO drop/import, SSE replies, draft preservation, and playback configuration states remain intact.
- Replaced permanent library/workspace sidebars with full-width primary content, compact import/playback controls, and expandable configuration, metadata, and controller guides. Removed sidebar-driven blank space and kept normal document scrolling on desktop and mobile.
- Added bounded PS2 title search against CoolROM’s public search page, escaped in-app results, and new-tab game-page links. Downloads and extraction remain manual; Rails never downloads game files or executes website content. Verified live search, external handoff, empty results, invalid input, mobile layout, and preservation of the selected ISO during Turbo updates.
- Added per-reply vendor selection for Google Gemini or OpenAI / compatible, editable model IDs, immutable assistant provider/model snapshots, and provider-aware streamed replies. Composer drafts and next-reply selections survive the final SSE refresh, including vendor switches during an in-flight response; legacy unsnapshotted history does not override the configured default.
- Documented server-side Gemini configuration with `CHAT_PROVIDER=gemini`, `GEMINI_API_KEY`, and optional `GEMINI_MODEL` (default `gemini-2.5-flash`), alongside existing OpenAI model/base settings. Added Gemini key log filtering and disclosure that switching vendors sends prior completed history and image metadata, never ISO bytes, to the selected vendor.
- Verified a live Gemini reply through browser submission, Solid Queue, native RubyLLM transport, persistence, and SSE. Verified provider/model/draft preservation through an in-flight SSE fixture and without browser storage, mobile layout, and an updated running-application chat screenshot. All 28 tests (318 assertions), Rails loading, RuboCop, and Brakeman passed.
- Removed successful-send flash banners and kept chat sends at the current composer position. Verified desktop and mobile submission plus SSE completion with a local streaming fixture, including unavailable browser storage; errors remain visible.

## 2026-10-11

- Added Rails 8.1 local library with automatic ISO drag/drop, upload progress, background import, read-only private originals, and SHA-256 verification.
- Added persistent OpenAI-compatible chat with streamed replies and SSE/EventSource progress; disabled Action Cable and removed Solid Cable.
- Added configured PCSX2 desktop launcher, isolated emulator profile, original-integrity checks, and explicit setup/launch statuses.
- Added integration coverage, CI test execution, AI specialist/task harness, and screenshots of the running synthetic-fixture workflow.
- Added automatic development/test loading from Git-ignored `.env`, with `.env.example` setup instructions.
- Fixed PCSX2 2.8.2 custom data-directory layout so the emulator reads the generated BIOS configuration.
- Verified a real local Midnight Club 3: DUB Edition Remix import, preserved source/copy hashes, BIOS loading, Metal initialization, and game ELF execution. Visual gameplay and controller input remain unverified.
- Fixed security CI file-access findings without ignores or disabled checks: moved image IO into the validated model boundary, enforced canonical UUIDs/fixed filenames, and rejected storage-parent and reply-lock links.
- Added failing-before/passing-after security regressions and verified browser import plus partial/completed SSE chat through the real worker; all local CI commands pass.
- Fixed the newly exposed gem-audit failure by upgrading RubyLLM from 1.16 to patched 2.0, preserving Chat Completions compatibility explicitly, and refreshing advisory data in GitHub CI and bin/ci. CVE-2026-67987 is fixed rather than ignored. Verified the upgraded SDK with the integration suite and browser partial/completed SSE replies through the real worker and a local HTTP model fixture.
- Upgraded RubyLLM to the requested 2.1.0 release. Verified all 14 integration tests (90 assertions), security scans, and an actual chat job consuming a streamed local HTTP response. The one-time Bundler cooldown override does not change the user’s global configuration.
- Binary inspection, patch approval, and modified-image builds are not part of this release.
