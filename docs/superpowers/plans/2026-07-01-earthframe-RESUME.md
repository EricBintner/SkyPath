# Resume prompt — M02.2 earthFrame node hierarchy

> Paste this into a fresh/compacted session to continue exactly where we left off.

## What we're doing

SkyPath iOS app (`GeoTestARScene/SkyPath.xcodeproj`), working toward **ARCore VPS for the AR screen**. Current milestone: **M02.2 — earthFrame node hierarchy** (the scene-graph foundation for M02.4 Streetscape occluders and M02.5 VPS correction loop).

## Status (as of 2026-07-01)

- **Design spec v2 approved + adversarially scrutinized** (5-agent scrutiny, fixes folded in).
- **Implementation plan written** (9 tasks, TDD-ordered).
- **Execution NOT yet started.** Still on `main`; no feature branch created yet. Tasks #4–#12 in the todo list correspond to plan Tasks 1–9, all pending.
- No code changed yet for M02.2 (only docs/memory updated).

## Key files (read these first)

- **Plan (execute this):** `docs/superpowers/plans/2026-07-01-earthframe-node-hierarchy.md` — 9 tasks with complete code + exact xcodebuild commands.
- **Spec (the design):** `docs/superpowers/specs/2026-06-30-earthframe-node-hierarchy-design.md` (v2; changelog at top; decisions D1–D10).
- **Loose-ends (issue tracker + decision log):** `docs/loose-ends-and-priorities.md` — §2.3 (M02.2 rows), §8 (MERGED-001…030), §7/§10 decision logs.
- **Build/test setup (memory):** `ios-build-test-setup.md` — see below.

## Build/test setup (verified empirically 2026-07-01)

- Project: `GeoTestARScene/SkyPath.xcodeproj` (NOT the stale `GeoTestARScene/GeoTestARScene.xcodeproj/`).
- Scheme: `GeoTestARScene`. App module name: `SkyPath` (test target had stale `@testable import GeoTestARScene` — Plan Task 1 fixes it).
- Destination: `platform=iOS Simulator,id=B2A25A43-FBCD-4B24-97EC-9EE7E0E82CE3` (iPhone 17, OS 26.5). Pin it explicitly.
- App + test targets are Xcode 16 synchronized-folder targets — drop a `.swift` in `GeoTestARScene/GeoTestARScene/` (app) or `GeoTestARScene/GeoTestARSceneTests/` (tests); **no `project.pbxproj` edit**.
- Use `-only-testing:SkyPathTests`. The import-trap failure only reproduces on a **clean** build (`xcodebuild clean`).
- `APIKeys.local.xcconfig` exists locally (gitignored); `ENABLE_TESTABILITY=YES`. App builds + tests run on the simulator (ARGeoTracking is device-only, but pure-SceneKit tests run on sim).

## How to execute (user-approved: Subagent-Driven Development)

Use the `superpowers:subagent-driven-development` skill. Fresh subagent per plan task + two-stage review after each (spec compliance, then code quality). Never dispatch parallel implementers (same-file conflicts). Templates: `subagent-driven-development/implementer-prompt.md`, `spec-reviewer-prompt.md`, `code-quality-reviewer-prompt.md`.

**Resume point:** dispatch the implementer for **Plan Task 1** (create branch `m02.2-earthframe` + fix `@testable import` at `GeoTestARSceneTests/GeoTestARSceneTests.swift:9`), then proceed T2 → T9, marking tasks #4–#12 complete as you go.

Model sizing: T1–T4, T8 are mechanical (cheap/fresh-context fine); T5–T7 are ARViewController integration (judgment); reviews use the `superpowers:code-reviewer` agent type.

## Conventions & constraints

- Don't implement on `main` — Plan Task 1 branches to `m02.2-earthframe` first.
- End every commit message with `Co-Authored-By: Claude <noreply@anthropic.com>`.
- **Device-only ACs** (visual-unchanged, runtime under-root, orphan-free across a localized walk) need the user's device — Claude can only verify simulator-verifiable ACs (factory tests, reparent-math proxy, invariant test, clean build, test run).
- Ultracode is on: use Workflow for substantive verification; lean toward thoroughness.
- User wants **all planning/decisions documented** — keep appending to the loose-ends decision log (§7 and §10) as choices are made.
- Carry-overs (NOT in M02.2): M02.4 Streetscape occluders; M02.5 correction loop + MERGED-005 transform spec (must flip `m02_5CorrectionEnabled` and revisit D4 occluder structure before lifting the identity invariant); the `unloadModel`/`didAdd` anchor-bookkeeping fix.

## Pointers to other relevant memory

- `[[ios-build-test-setup]]` — full build/test reference.
- `[[deferred-ios-test-target]]` — empty test targets exist.
- `[[webview-gpu-memory-ceiling]]` — the AR⇄WebGL resource ceiling (why resource management matters).