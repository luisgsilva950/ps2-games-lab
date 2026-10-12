# Changelog

## 2026-10-12

- Removed lab control mapping, keyboard profiles, game assignments, and PCSX2 import/export hooks. Existing native PCSX2 settings and exported profiles remain user-controlled.
- Documented PS5 DualSense USB/Bluetooth setup and configuration in the lab-launched PCSX2 instance; added an in-app setup guide.
- Redesigned the library and conversation workspace with a neutral palette, compact navigation, clearer hierarchy, and responsive layouts. ISO drop/import, SSE replies, draft preservation, and playback configuration states remain intact.
- Replaced permanent library/workspace sidebars with full-width primary content, compact import/playback controls, and expandable configuration, metadata, and controller guides. Removed sidebar-driven blank space and kept normal document scrolling on desktop and mobile.

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
