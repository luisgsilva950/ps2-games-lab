# PS2 Games Lab

A local Rails workspace for importing PS2 disc images, chatting about modifications through an OpenAI-compatible endpoint, and opening preserved originals in PCSX2.

**Working today:** ISO drag-and-drop import, private read-only originals with SHA-256 verification, persistent conversations, incremental replies over Server-Sent Events (SSE), and a configured desktop launcher.

**Not implemented:** binary inspection tools for the model, patch proposals/approval, modified-image builds, game-specific asset editors, or online multiplayer. Chat cannot modify or inspect the ISO. This application is a lab, not a universal natural-language game editor.

## Screenshots

These screenshots were captured from the running Rails app using small synthetic ISO9660 fixtures and a deterministic local OpenAI-compatible streaming fixture. They show real import, persistence, and UI behavior—not real model reasoning, a bootable PS2 game, or verified PCSX2 playback. No game or BIOS files are in this repository.

### Import and library

![Running library with ISO drop zone and configuration status](docs/images/library.png)

### Game workspace and chat

![Running game workspace with persisted chat, original hash, and playback setup](docs/images/chat-workspace.png)

## Run locally

Requirements: Ruby **3.4.2** (see .ruby-version), Bundler, and enough free disk space for multi-gigabyte images. SQLite is used through Active Record; no Redis or PostgreSQL is needed. Import works without a model or emulator configured.

~~~sh
git clone git@github.com:luisgsilva950/ps2-games-lab.git
cd ps2-games-lab
bin/setup --skip-server
bin/dev
~~~

Open **http://127.0.0.1:3000**. The development process starts Rails, the Tailwind watcher, and the Solid Queue worker. Keep all three running; importing and model replies depend on the worker. Set PORT before bin/dev to change the HTTP port.

Only run this application locally. There is no user authentication or hardened public-upload deployment. Do not bind it to the public internet.

## Configure chat

Export configuration in the same terminal before starting bin/dev:

~~~sh
export OPENAI_API_BASE="https://api.openai.com/v1"
export OPENAI_MODEL="your-provider-model-id"
read -s OPENAI_API_KEY
export OPENAI_API_KEY
bin/dev
~~~

On macOS shells, read -s accepts the key without echoing it; finish entry with Enter. Use your provider's exact model ID. For another OpenAI-compatible server, change OPENAI_API_BASE to its API base URL, typically ending in /v1. It must support streaming chat completions. Local servers may use a nonempty placeholder key if they do not require authentication.

.env.example documents the variables; **.env files are not automatically loaded**. Restart both Rails and the worker after configuration changes. Do not commit credentials or paste them into chat.

The endpoint receives the conversation and image metadata: name, size, SHA-256, and import status. **ISO contents are not transmitted.** Endpoint configuration is local environment configuration, not model-controlled input. Provider requests can incur charges.

One reply may be pending per image. Prompts are limited to 4,000 characters, replies to 8,000, and existing conversation plus a new prompt to 24,000. The full model prompt has a 32,000-character limit. Errors are recorded without displaying raw provider error bodies or credentials.

### SSE, not Action Cable

RubyLLM requests a streamed provider response. The job persists partial content at a bounded rate; the browser's EventSource receives escaped message snapshots from GET /game_images/:id/events. This also updates import progress. Connections close after completion or rotate after 25 seconds; automatic reconnect receives current persisted state rather than replaying duplicated tokens.

The composer is not replaced during partial updates. A final workspace refresh preserves an unsent draft, focus, and scroll. Navigating away closes the browser stream without cancelling the durable job. There is no WebSocket chat, Action Cable engine, or Solid Cable dependency. The server samples persisted state; the browser does not periodically poll page requests.

## Import an image

1. Extract your disc image before importing: **.iso only**. ZIP, 7z, CHD, and installers are not accepted.
2. Drop one ISO into the box to start automatically, or use the file picker and Import game button.
3. Watch upload progress. A background job checks the ISO9660 primary volume descriptor, copies the image into private managed storage, verifies its hash, and makes the original read-only.
4. The game workspace opens. Chat is enabled after import when model configuration is present.
5. PCSX2 launches automatically after import when configured. Missing setup does not prevent import or chat.

The ISO signature check identifies the supported disc format; it does not prove PS2 compatibility, authenticity, malware safety, or bootability. Keep your own backups. The application does not change the selected source file.

Allow up to **three times the image size in additional temporary space during upload/import**, plus your external source copy. Completed imports retain one managed copy. Hashing/copying large images takes time, but does not load the whole image into Ruby memory.

## Configure PCSX2 on macOS

Install PCSX2 from [its official download page](https://pcsx2.net/downloads/) and supply a BIOS you have the right to use. Nothing proprietary is bundled or downloaded automatically.

~~~sh
export PCSX2_EXECUTABLE="/Applications/PCSX2.app/Contents/MacOS/PCSX2"
export PCSX2_BIOS_PATH="/absolute/path/to/your/ps2-bios.bin"
bin/dev
~~~

The executable name/location above is illustrative: use the actual executable inside your installed .app, **not the .app directory**. PCSX2_BIOS_PATH can be a readable BIOS file or a directory; directory mode picks the first sorted readable .bin/.rom file. Prefer an explicit main BIOS file so auxiliary ROM files are not selected by mistake. PCSX2 is responsible for validating the firmware.

The launcher uses the [documented PCSX2 Qt CLI](https://pcsx2.net/docs/advanced/cli) with a fixed argument array: -datapath, -batch, --, and the managed ISO. It never constructs a shell command from a prompt or filename. It verifies image size/hash and refuses symlink/hardlink originals before launching.

Settings and saves are isolated under storage/pcsx2/<digest-of-resolved-BIOS-path>/, separate from your normal PCSX2 profile. Initial inis/PCSX2.ini selects the supplied BIOS; existing settings are preserved. Configure your DualSense/controller within this lab-specific emulator profile. Existing emulator sessions are not killed automatically.

**Launched means a process was started—not that a window rendered, the BIOS loaded, or the game booted.** An emulator that exits after startup may still have this status. Verify actual playback in the desktop window. A browser cannot embed or directly launch PCSX2; the local Rails backend starts it on the same machine.

## Architecture and safety

| Component | Responsibility |
| --- | --- |
| Rails 8.1.4 / Ruby 3.4 | Local monolith, HTTP, domain behavior |
| Active Record / SQLite | Image metadata, messages, and durable job state |
| ERB / Turbo / Stimulus / Tailwind | Library, upload progress, chat, responsive UI |
| Solid Queue | Background import and provider jobs |
| RubyLLM | OpenAI-compatible streaming transport |
| ActionController::Live / EventSource | SSE delivery; no Action Cable |
| Private filesystem storage | Large images and isolated PCSX2 settings |
| Minitest integration tests | HTTP, real persistence, artifacts, failures, and SSE |

All DB access uses Active Record. Game images are files, not database blobs. Files are addressed by generated validated storage identities, not model-selected paths. The model has no shell, binary-read tools, or write access. Originals are exclusively created, hash-verified, and read-only. Duplicate import jobs do not overwrite originals. Failed imports never expose partial images as ready.

A future modification workflow must create a unique separate output from a recorded immutable base, require validated length-preserving patches and explicit approval, and distinguish patch validity from emulator/gameplay verification. That workflow is not available in this release.

## Tests and verification

~~~sh
bin/rails test
bin/rails zeitwerk:check
bin/rubocop
bin/brakeman --quiet --no-pager
~~~

The integration suite uses deterministic synthetic images, real SQLite/Active Record, and a local HTTP streaming fixture at the provider boundary. It covers source preservation, read-only exact copies, duplicate jobs, rejected archives/invalid images, existing-output collisions, chat context ordering, pending-request exclusion, provider failures/secret redaction, unsafe or mutated launch inputs, SSE reconnect snapshots, HTML escaping, and missing-image errors.

Observed verification for this release:

- 12 integration tests, 82 assertions passed.
- Browser file-picker upload and automatic drop import completed through the real Solid Queue worker.
- Browser observed partial SSE content before completion; an unsent draft survived completion.
- Desktop and 390px-wide UI checked; no horizontal overflow at 390px.
- Zeitwerk loading and Ruby style checks passed.
- Launcher started a real /usr/bin/true process surrogate and preserved the original hash. **Actual PCSX2 boot/gameplay has not been verified.**

Brakeman currently reports seven file-access warnings for model-derived managed image paths and the numeric reply-lock filename. Those paths use generated/validated identifiers rather than user-supplied filesystem paths; the warnings remain visible and are not suppressed. The Brakeman security CI job currently fails on them. A clean static-analysis result is not claimed. RubyLLM 1.16 also emits an upstream legacy Active Record API deprecation at boot; this app uses its context/chat API, not the legacy acts_as API.

## Troubleshooting

- **Import stays pending:** ensure bin/dev's jobs process is running. Check log/development.log and the worker output.
- **Import fails:** use an extracted ISO9660 image and check free disk space. Retry as a new import; existing originals are never overwritten.
- **Chat is disabled:** set OPENAI_API_KEY and OPENAI_MODEL; restart the app and worker. Configuration presence alone does not prove provider access.
- **Response fails:** check streaming chat support, API base, model ID, credentials, and provider billing/network status. No fake fallback response is generated.
- **SSE buffers behind a proxy:** disable proxy response buffering/compression for text/event-stream. The app sets X-Accel-Buffering: no; direct localhost is the supported setup.
- **Playback is disabled:** configure both emulator and BIOS paths and restart. Inspect the PCSX2 window for startup/firmware errors.
- **Mac blocks the emulator:** follow the official PCSX2 installation guidance; the lab does not disable Gatekeeper.

## AI engineering harness

Read AGENTS.md, then .agents/AGENTS.md. Principles are inspired by DHH's Rails conventions and Akita on Rails' focus on fundamentals and measured costs—not quotations or endorsement. Prefer cohesive Active Record models, simple Ruby, integration tests, and explicit security boundaries.

Reusable task prompts:

- Read .agents/skills/rails-plan/SKILL.md and plan a feature.
- Read .agents/skills/rails-build/SKILL.md and implement a complete Rails feature.
- Read .agents/skills/rails-review/SKILL.md and review a change.
- Read .agents/skills/ps2-investigate/SKILL.md and investigate a specific game modification read-only.

The Rails specialist is .agents/agents/rails-specialist.md. Discovery/slash-command support depends on your AI client. These are developer-assistant instructions, not runtime model permissions.

## Rights and repository hygiene

Only import images and BIOS files you have the right to use. This project is not affiliated with Sony, Rockstar, or PCSX2. Publishing modified games/assets requires the necessary rights; private experimentation does not grant redistribution rights.

Git excludes storage/, tmp/, logs, .env secrets, config/master.key, and disc/archive files. Screenshots use synthetic fixtures. Keep games, firmware, saves, databases, and API keys out of commits.
