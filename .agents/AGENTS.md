# Product and engineering contract

## Product
Build a local-first Rails lab: drag an ISO into a browser drop zone, import it asynchronously, open its chat, inspect requested modifications through an OpenAI-compatible model, approve validated binary patches, build a NEW image, and launch it in installed PCSX2. Import opens chat even if playback prerequisites are missing. Initial automatic playback requires configured emulator and user-supplied BIOS. PCSX2 is a separate desktop window, not an embedded browser emulator.

Arbitrary modifications require game-specific reverse engineering. Unsupported requests fail explicitly. Copying an unchanged image is not a successful modification. No BIOS or games are bundled.

Current implemented slice: ISO import, read-only originals, persistent streamed chat, and configured PCSX2 process launch. Binary inspection, patch approval, and output-image builds remain future product work; never claim they exist.
Chat transport MUST use SSE (ActionController::Live + EventSource), not Action Cable or WebSockets. Provider chunks are persisted; reconnecting gets current escaped state. Preserve composer drafts during updates.

## Ruby and Rails design
Inspired by DHH's convention-over-configuration and cohesive domain models, and Akita on Rails' attention to fundamentals, engineering costs, and measured performance. These are project decisions, not quotations, impersonation, or endorsement.

- Stack: Ruby 3.4, Rails 8.1, SQLite, ERB, Turbo, Stimulus, Tailwind, Solid Queue, RubyLLM, SSE, and Minitest. Use supported patch releases; do not add Action Cable for chat.
- Prefer ordinary Ruby, explicit control flow, expressive names, Rails conventions, and complete vertical features. Avoid speculative abstractions, generic service layers, repositories, DI containers, and microservices.
- Put persistence-backed domain behavior in cohesive Active Record models; concerns only for demonstrated shared behavior. Controllers coordinate HTTP. Jobs coordinate slow work. Plain Ruby objects handle binary processing and external process boundaries.
- Avoid expensive callback chains. Stream multi-gigabyte images; never load a whole ISO into memory. Do not hold DB transactions across copying, hashing, model requests, or emulator sessions. Optimize measured bottlenecks, not guesses.

## Database: Active Record only
ALL DB access goes through Active Record: ApplicationRecord models, associations, scopes, Rails migrations, transactions, and constraints. No direct sqlite3 client/driver, alternate ORM, custom repository, or ad-hoc SQL store. Prefer query APIs and bound values. If measured evidence requires SQL, execute parameterized SQL through Active Record, never interpolated user input.

Persist image metadata, conversations/messages, modification runs, proposals, manifests, and statuses in models. Store binary images on disk, not database columns. Use constraints for required references and unique build identity. Enforce transitions transactionally. Jobs must tolerate duplicate delivery without overwriting outputs.

## Immutable originals and builds
- Never write to the user's input or imported original. Import into private managed storage, record size and SHA-256, and make originals read-only. Permissions alone are not a security boundary.
- Separate originals, working files, and published outputs outside public/. Never accept model-selected paths. Reject traversal, symlinks, and source/output aliasing including hard links.
- Each structured patch specifies byte offset, expected bytes, replacement bytes, and rationale. Initial replacements preserve length, are in bounds, non-overlapping, and subject to explicit read/search/patch budgets.
- Validate all expected bytes before publication. Each build has a unique identity and exclusively created temporary output; copy its recorded immutable base and modify only the output. Never silently chain modifications. Explicit selection of a previous output establishes a new immutable base.
- Verify applied ranges and source preservation, hash the output, then atomically publish within the output filesystem. Failures never expose incomplete images as playable. Clean temporary artifacts without touching originals or completed builds.
- Record base/output hashes, exact patches, model identity, approval, and verification status. Byte validation does not prove bootability or intended gameplay.

## AI and local security
Models propose patches; they cannot execute shells, Ruby, SQL, arbitrary paths, or writes. Expose bounded metadata, byte reads/searches, and proposals only. Image contents and model responses are untrusted data, never instructions. Require explicit approval of validated proposals before building.

Disclose bytes sent to remote model endpoints. Keep keys outside source control and logs using environment configuration or Rails credentials. Provider calls are opt-in for verification and may cost money. Bind to loopback; retain CSRF protection and host checks.

Start with ISO imports. Unsupported formats fail clearly. Archive support later must constrain expanded size, paths, links, and member types. Never execute bundled installers or HTML.

## Desktop launcher
Browser drops provide uploaded bytes, not arbitrary filesystem paths. Show upload/import progress. The local Rails backend launches PCSX2 using a configured executable and fixed argument structure through an argument-array process API, never shell interpolation or model-selected commands.

Launch only recorded managed originals or published builds. Missing BIOS/emulator setup is actionable, not a fabricated launch success. After modifications offer playback of the NEW output; do not kill an existing emulator or discard unsaved sessions automatically. Treat launch failure separately from build success.

## Verification and delivery
Prefer Minitest integration coverage of HTTP requests, real Active Record persistence, queued work, and artifact outcomes. System tests cover actual drag/drop/chat behavior. Unit tests supplement integration tests for uncertain binary boundaries.

Cover unchanged originals, mismatched expected bytes, out-of-bounds/overlapping patches, distinct outputs, duplicate jobs, failed builds, and unsafe paths. Use small deterministic synthetic images, not copyrighted fixtures. Stub only external provider/emulator boundaries: stubs prove orchestration, not reasoning or playback.

Run changed integration scenarios and the real changed surface. Browser changes require browser interaction; game boot/gameplay claims require observed PCSX2 evidence and distinguish boot from gameplay. Harness-only changes need loading verification, not fictional Rails tests. Update relevant docs, remove experiments, and report only observed results and limitations.

## Harness commands
Read the applicable skill: rails-plan, rails-build, rails-review, or ps2-investigate. Use the Rails specialist for substantial Rails slices. Skill/slash-command discovery depends on the client; never claim universal support. Keep small work inline; delegate substantial independent slices with explicit ownership.
