# Changelog

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
- Binary inspection, patch approval, and modified-image builds are not part of this release.
