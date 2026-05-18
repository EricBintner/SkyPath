# AI Handoff — Phase 02, M02.0

A self-contained briefing for whichever AI agent (Claude, Cursor, Windsurf, Codex, Gemini, future-you) picks up this project from a fresh session. **Read this entire doc before doing anything else.** Then read the five referenced docs (§5). Then act.

This handoff was last updated at commit `f5c4155` on branch `main` (the only branch). If the working tree is ahead of that, treat it as authoritative and update this doc when you stop.

---

## 1. 60-second orientation

**Project**: SkyPath — an iOS geospatial AR app that places architectural-scale virtual buildings at real-world NYC locations, plus a sibling web viewer (`webgl-component/`, separate repo deployed to Vercel). Goal: virtual content stays anchored to the world as the user walks, and is correctly occluded by real buildings.

**Where we are in the work**:
- A pre-Metal SceneKit baseline (June 2025) rendered fine but virtual content **slid** as the user walked. A Metal + `cesium-native` rebuild was attempted to fix this and never reached working occlusion. Both have been abandoned.
- This repo (`EricBintner/SkyPath`) is a restart from the SceneKit baseline (`Old/GeoTestAR copy 10`) with a new fix strategy. See `Phase01_Restart_Plan.md`.
- We've drafted `Phase02_VPS_Grounded_Occluded_Plan.md` (architecture: Apple GeoTracking primary + ARCore Streetscape Geometry for occlusion meshes + SceneKit depth-only material + an `earthFrame` SCNNode with bounded EMA corrections instead of `setWorldOrigin` resets).
- Two key claims in the plan are unverified by any shipping reference app: (a) whether `ARGeoTrackingConfiguration` + `GARSession` can coexist on iOS, and (b) whether SceneKit's depth-only material composes cleanly with Streetscape Geometry meshes at 50–100 m range. **M02.0 is a feasibility spike to resolve both.**
- Spike code is already scaffolded under `GeoTestARScene/GeoTestARScene/Spike/`. Spike A (pose-stack coexistence test) is fully implemented in Swift. Spike B (renderer bake-off) is scaffolded with TODOs. Spike C (sliding-baseline capture) is a telemetry harness.
- The spike code is gated at runtime by `SHOW_SPIKE_MENU=1` in the Xcode scheme — day-to-day builds run the normal AR flow.

**What you do next**: §7.

---

## 2. Mission for this phase

Phase 02 succeeds when **all five acceptance criteria** in `Phase02_VPS_Grounded_Occluded_Plan.md` §1 pass on a real iPhone on a documented NYC block:

- **AC-0**: iOS reads its placement data from the canonical JSON in `webgl-component/`, not from a duplicate iOS-side file.
- **AC-1**: Lateral drift of placed anchors after a 50 m walk-and-return ≤ 1.0 m.
- **AC-2**: Yaw error of placed anchors after a 90° stationary pan ≤ 3°.
- **AC-3**: Virtual content correctly hidden by real building facades for ≥ 80 % of facade pixel area.
- **AC-4**: 5-minute walk-and-return loop with no user-visible "jump" > 30 cm or > 5° yaw.

Phase 02 has been broken into milestones M02.0 → M02.7 (see `Phase02_VPS_Grounded_Occluded_Plan.md` §7). **You are at M02.0.** All later milestones depend on M02.0's outcomes.

---

## 3. Scope discipline — non-negotiable

Codified in `AGENTS.md` at the repo root. Summary:

**You may only touch the AR screen surface**:
- `GeoTestARScene/GeoTestARScene/ARViewController.swift` and AR-only types it spawns
- `GeoTestARScene/GeoTestARScene/Spike/` (the spike code)
- `GeoTestARScene/GeoTestARScene/Models.swift` and the canonical `models_to_place.json` schema
- AR-only utilities under `utilities/`
- Build-phase scripts that copy shared data from `webgl-component/`
- Docs under `docs/phases/`, `docs/research/`

**You must not touch unless explicitly asked**:
- `MapViewController.swift` and anything driving the Map tab
- `LocationsViewController.swift` and WebView/Vercel wiring
- `InfoViewController.swift` and global navigation
- `AppDelegate.swift`, `SceneDelegate.swift`, tab/navigation controllers
- The `webgl-component/` submodule contents — that's a separate repo (`EricBintner/cesium-google-3dtiles`)

**Why**: past rebuild attempts caused regressions in working subsystems (Map, WebView, navigation). The rule contains AR-rebuild blast radius. If a change "needs" to touch shared code, stop and ask first. Do not solve it by quietly modifying out-of-scope files.

---

## 4. Repository layout

```
/Volumes/Thunderbolt/XcodeProjects/SkyPath2025/SkyPath-Restart/  ← here
├── AGENTS.md                             ← scope + shared-data rules (READ FIRST)
├── README.md                             ← orientation pointer
├── .gitignore                            ← hardened; do not weaken
├── .gitmodules                           ← pins webgl-component submodule
├── GeoTestARScene/
│   └── GeoTestARScene/
│       ├── ARViewController.swift        ← AR tab, ~935 lines (the AR screen)
│       ├── ViewController.swift          ← tab controller (OUT OF SCOPE)
│       ├── MapViewController.swift       ← OUT OF SCOPE
│       ├── LocationsViewController.swift ← OUT OF SCOPE
│       ├── InfoViewController.swift      ← OUT OF SCOPE
│       ├── AppDelegate.swift             ← OUT OF SCOPE
│       ├── SceneDelegate.swift           ← OUT OF SCOPE
│       ├── Models.swift                  ← LocationPoint + ARModelLocation (in scope)
│       ├── ARModelLocationExtension.swift
│       ├── LocationSequence.swift
│       ├── ViewControllerProtocols.swift
│       ├── utilities/LocationManager.swift
│       ├── Spike/
│       │   ├── SpikeMenuViewController.swift     ← picker, gated by SHOW_SPIKE_MENU=1
│       │   ├── SpikeAViewController.swift        ← FULL impl, pose-stack coexistence
│       │   ├── SpikeBViewController.swift        ← SCAFFOLD with TODOs
│       │   └── SpikeCViewController.swift        ← telemetry harness for sliding baseline
│       ├── SHARED_DATA.md                ← model/JSON pipeline strategy
│       ├── skypath_001.usdz              ← 3.7 MB smoke-test asset (kept)
│       ├── Base.lproj/Main.storyboard    ← (OUT OF SCOPE)
│       └── Assets.xcassets/              ← (OUT OF SCOPE)
├── webgl-component/                      ← SUBMODULE, OUT OF SCOPE for this repo
│   ├── models_to_place.json              ← canonical placement (39 entries)
│   ├── skypath_models/*.glb              ← canonical models
│   └── … (web viewer code)
└── docs/
    ├── phases/
    │   ├── Phase01_Restart_Plan.md       ← restart context
    │   ├── Phase02_VPS_Grounded_Occluded_Plan.md ← THE PLAN
    │   ├── Phase02_Spike_Playbook.md     ← operator's M02.0 checklist
    │   ├── Phase02_Spike_Results.md      ← empty template (operator fills in)
    │   └── Phase02_AI_Handoff.md         ← THIS FILE
    └── research/
        ├── VPS-research.md               ← background landscape
        ├── research-todos.md             ← old open questions, mostly resolved
        └── references.md                 ← cited URLs by topic
```

Sibling folders at `/Volumes/Thunderbolt/XcodeProjects/SkyPath2025/`:
- `Old/` — cold archive of prior project copies. Useful for archaeology only.
- `SkyPath/` — parked Metal-track snapshot. **Do not modify.** Reference it if you need to see what was tried and why it didn't work.

---

## 5. Docs to read fully, in order

Before touching any code, read these five files completely:

1. **`AGENTS.md`** — scope rules and shared-data rules. Internalize before anything else.
2. **`docs/phases/Phase02_VPS_Grounded_Occluded_Plan.md`** — the architecture and decisions. ~470 lines.
3. **`docs/phases/Phase02_Spike_Playbook.md`** — operator-side procedure for M02.0. ~190 lines.
4. **`GeoTestARScene/GeoTestARScene/SHARED_DATA.md`** — webgl ↔ iOS data flow.
5. **`docs/phases/Phase01_Restart_Plan.md`** — why this restart exists. ~60 lines.

Skim:
- `docs/research/VPS-research.md` — VPS landscape (Apple vs Google vs Niantic).
- `docs/research/references.md` — cited sources grouped by topic. Use as a starting point if you need to verify a claim.

---

## 6. Decisions already made — do not relitigate

These are committed. Reopen only with explicit user direction and a clearly named new failure mode that makes the old decision wrong.

| Decision | Why |
|---|---|
| **SceneKit + ARKit**, not Metal | The previous Metal rebuild burned ~3,000 LOC for a ~30-line shader and never worked. SceneKit was sufficient for what we actually need (depth-only occlusion of relatively few meshes). |
| **No `cesium-native` on iOS** | Memory growth, novel territory, attribution + session-refresh policy overhead. Streetscape Geometry gives us the meshes we actually need. |
| **No Photorealistic 3D Tiles streamed on-device** | Same reasons. |
| **No RealityKit migration in this phase** | RealityKit is a candidate renderer for Spike B, but a full SceneKit → RealityKit migration is deferred. The baseline is SceneKit; we keep it. |
| **`webgl-component/` is canonical for models AND placement JSON** | Drift between platforms is the failure mode we just got rid of. iOS bundles copies via a build phase (M02.3). |
| **No `setWorldOrigin` for ongoing drift correction** | Abrupt; user-visible. We use a single `earthFrame` SCNNode with bounded EMA corrections instead. |
| **Apple `ARGeoTrackingConfiguration` primary, Google `GARSession` for meshes** | Apple has better Look Around coverage in NYC; Google has Streetscape Geometry. **Gated on Spike A.** Fallback path documented if A fails. |
| **GLTFKit2 for glb loading** | Actively maintained, SwiftPM-installable, Khronos-blessed; Apple has no native glb. |
| **Scope: AR screen only** | Map, WebView, global UI are working; AR rebuild work must not regress them. |
| **One branch, not two** | Solo project; spike code is throwaway gated by `SHOW_SPIKE_MENU=1`, no branch ceremony needed. |
| **iOS-side `models_to_place.json` is gone** | Removed in commit `995fafb`. `.gitignore` blocks re-introduction. The M02.3 build phase repopulates it from webgl. |

---

## 7. Next concrete actions — in order

You are at M02.0. **You cannot land code that compiles + runs on device.** The user must do the Xcode-side steps (SPM, API key, scheme env var, file registration). Your job is to:

### 7.1 Verify orientation

```bash
cd /Volumes/Thunderbolt/XcodeProjects/SkyPath2025/SkyPath-Restart
git status               # should be clean on main
git log --oneline -5     # confirm you're at f5c4155 or later
ls AGENTS.md README.md docs/phases/  # confirm structure
```

Read the five docs in §5 of this file.

### 7.2 Check if the operator has run M02.0 yet

Open `docs/phases/Phase02_Spike_Results.md`. If any of the Spike A/B/C sections have filled-in numbers, the spike is partially done — your work picks up wherever it left off. If the file is still the empty template, the spike hasn't started.

### 7.3 Branch by state

**If spike results doc is still the empty template**:
- Your work this session is to support the operator running the spike. They have to do the in-person/Xcode steps (`Phase02_Spike_Playbook.md` §0). You can:
  - Verify the spike Swift sources compile in principle (read them; check imports; flag any ARCore Swift API drift you spot).
  - Pre-fill the Spike B render-path TODOs based on the Playbook §2 instructions, BUT only after the operator confirms Spike A's pose-stack outcome — Spike B's `ARSessionConfiguration` choice depends on it.
  - Improve the HUD or telemetry in the Spike VCs if you spot gaps.

**If Spike A is recorded as PASS**:
- Implement Spike B render paths in `SpikeBViewController.swift`. Both SceneKit (`SCNMaterial` depth-only) and RealityKit (`OcclusionMaterial`) variants. The TODO comments in the file are detailed enough to follow.
- Use the SAME `ARSessionConfiguration` that Spike A confirmed worked.

**If Spike A is recorded as FAIL** (fallback path):
- Switch all spike VCs to use `ARWorldTrackingConfiguration` instead of `ARGeoTrackingConfiguration`. Spike A's `Fallback` switch already does this for that one VC; update Spike B and C similarly.
- Plan §3 fallback section becomes the load-bearing pose strategy.

**If Spike B is recorded with a renderer winner**:
- Update `Phase02_VPS_Grounded_Occluded_Plan.md` §3 and §5 to drop the "gated on Spike X" language and lock in the chosen pose stack + renderer.
- Delete the unused render path from `SpikeBViewController.swift` (we don't need to keep both once one wins).

**If all three spikes are recorded**:
- M02.0 is done. Begin M02.1 directly on `main`.
- Cleanup commit: `rm -r GeoTestARScene/GeoTestARScene/Spike/`, remove the `// SPIKE:` block from `ARViewController.swift`, ask operator to drop `SHOW_SPIKE_MENU` from the Xcode scheme.
- Then proceed to M02.1 per the plan (§7 of the Plan).

### 7.4 If user gives a different instruction

Honor it. The scope rule still applies; the plan is a guide, not a mandate. If their instruction would violate the scope rule (touch Map/WebView/global UI), ask before acting.

---

## 8. Anti-patterns observed in prior phases

Things that wasted real time. Don't repeat them.

1. **Building a custom Metal renderer to solve a coordinate-frame problem.** The previous attempt rebuilt rendering when the actual bug was anchor placement timing + yaw drift + setWorldOrigin jumps. Solve the coordinate problem with code, not with a renderer rewrite.
2. **Maintaining parallel asset trees on iOS and webgl.** Caused silent drift (same `id` → different `model_variant`). Now structurally prevented; do not undo.
3. **Asserting things work without device verification.** AR especially can pass `swift build` and fail in the field. Don't claim a feature works from code reading alone.
4. **Adding "while we're in here" cleanups outside the current task.** Past rebuilds regressed working subsystems this way. The scope rule exists to stop it.
5. **Over-asserting from first principles when no shipping reference exists.** The original Phase 02 plan committed to "SceneKit + Streetscape Geometry depth-only occluder at distance" without evidence; M02.0 spike exists because of that over-assertion. Honest plans flag gaps.
6. **`setWorldOrigin` for ongoing correction.** Documented as a known cause of visible jumps. Use the `earthFrame` SCNNode with bounded EMA instead (Plan §4).
7. **Caring about local folder naming.** `SkyPath-Restart` is fine; renaming to match the GitHub repo name is a different ticket and not blocking work.
8. **Two-branch ceremony for solo work.** We tried it; it was friction. Spike code on `main`, gated at runtime, is the established pattern.

---

## 9. Tools available + workarounds

### MCP servers in this Claude Code session

As of last check, only `claude_ai_Google_Drive` is registered. **`mcp__prep_*` tools (SourcePrep) are NOT available** — `ToolSearch` returns zero hits for `prep`, `mcp__prep`, or any SourcePrep variant. The `AGENTS.md` SourcePrep block documents the integration but the server isn't started in this process.

If you see prep tools register in your `ToolSearch` results, use them as AGENTS.md says: always pass `project_id: "bfbe8ab2-7adc-4c6c-983c-03edeac767e8"`. Start tasks with `prep()`, run `prep_impact(file_path=...)` before editing hub files.

If prep tools aren't available, fall back to:
- `Read` for known paths.
- `Bash` with `grep -rn`, `find . -name "..."`, and `git log --oneline` for archaeology.
- `Agent` with `subagent_type: Explore` for broader codebase questions.

### Network

`WebSearch` and `WebFetch` work from the main agent thread (tested). Sub-agents may have restricted network access depending on environment; if a sub-agent reports network errors, do the searches yourself.

### gh CLI

Not installed in this environment. For GitHub operations (PRs, repo settings, branch deletion), the operator must do them via web or you can use raw `git push origin --delete <branch>` style commands.

### Xcode

Not directly accessible. SPM dependencies, scheme env vars, build-phase scripts, project navigator file registration — all require the operator. Document what they need to do in the relevant Playbook section.

---

## 10. Verification standard

`AGENTS.md` says: "When the agent finishes a code change, confirm it built and ran (or say explicitly that it didn't)."

For this project specifically:
- "Confirms it builds" = the operator ran ⌘B in Xcode and reported success.
- "Confirms it runs" = the operator launched on a real iPhone and saw expected behavior.
- "Compiles in principle" / "should compile" / "looks correct" = **not confirmed**. Say so explicitly in your handoff.
- AR features fundamentally need device verification — they cannot pass on simulator and they often pass on `swift build` while failing in the field.

When you cannot test something yourself (Xcode-side or device-side), structure your message to clearly say "I've written / changed X; verification step Y is required and I cannot perform it."

---

## 11. User preferences observed (calibration data)

Behaviors confirmed across this session:

- **Wants tight, direct responses.** No throat-clearing; no "Great question!"; minimal preamble before doing the thing. Bullet points and tables welcome.
- **Wants to be second-guessed.** When proposing a plan, also flag what could be wrong with it. The user explicitly asked to "scrutinize" and "reverse-engineer" plans.
- **Will catch over-engineering.** Multi-branch git workflows for solo dev work; speculative abstractions; "while we're in here" expansions — all flagged. Keep solutions proportionate.
- **Prefers single source of truth for shared concepts.** Asset format, placement JSON, scope rules, plan docs — one canonical location, mirrored if needed but not edited in two places.
- **Cares about reversibility before destructive moves.** Snapshot before changing course; rename rather than delete; preserve `Old/` and `SkyPath/` (the Metal track) as cold storage.
- **Honest about evidence gaps is valued over confident assertions.** When citing a paper or claiming a pattern works, distinguish "documented and shipping" from "plausible from first principles."

When in doubt: short, direct, evidence-aware, scope-bounded. Ask before doing externally-visible or hard-to-reverse things.

---

## 12. Recurring traps in this codebase

Stuff you will hit. Document any new ones you find.

1. **Spike Swift sources won't compile until SPM dependencies are added.** They `import ARCore` and `import GLTFKit2`. Adding the packages is an Xcode-UI action the operator does (`Phase02_Spike_Playbook.md` §0.2). If they haven't done it yet, the build fails before runtime.
2. **Normal AR flow won't render models until M02.3 lands.** `ARViewController` calls `Bundle.main.url(forResource: "models_to_place", withExtension: "json")` and returns nil because the iOS-side JSON was deleted (commit `995fafb`). The M02.3 build phase that copies the canonical JSON from `webgl-component/` hasn't been added yet. Spike VCs don't hit this — they don't read the placement JSON.
3. **iOS `LocationPoint` schema gap.** Doesn't parse `sequence`, `model_ground_offset`, `model_scale_x/y/z` from the JSON. Webgl canonical JSON has them. M02.3 milestone description includes fixing this.
4. **ARCore Swift API drift.** SDK 1.54+ exposes `GARSession(apiKey:bundleIdentifier:)`; older versions use `GARSession.session(apiKey:bundleIdentifier:error:)`. Method spellings sometimes shift across versions. If a Spike file shows a small compile error after adding the package, change the offending method call to whatever the installed SDK exposes — don't change surrounding logic.
5. **`GARSession.earth` nullability.** Sometimes nullable depending on SDK version. Defensive `guard let earth = gar.earth else { ... }` is safer than direct dot access.
6. **`xcconfigs/` folder is not in git.** Operator creates it on first run (`Phase02_Spike_Playbook.md` §0.4). The actual `APIKeys.local.xcconfig` is gitignored by `*.local.xcconfig`.
7. **Bundle ID** is `com.ericbintner.GeoTestARScene` (confirmed from `project.pbxproj`). API key restrictions in Google Cloud Console must use this exact string.
8. **A `moodels/` typo folder** exists in `GeoTestARScene/GeoTestARScene/` (likely empty). Not addressed; not blocking; out of scope without explicit ask.
9. **AGENTS.md gets touched by SourcePrep's prep-onboard flow.** It writes a `<!-- prep-managed-start --> ... <!-- prep-managed-end -->` block. That block is auto-managed; don't hand-edit inside it. Hand-edit only the sections above the marker.
10. **`docs/phases/.localized` and `docs/phases/models_to_place.json`** showed up as "hub files" in the SourcePrep atlas — those paths don't actually exist on disk. SourcePrep is resolving markdown links as if they were sibling files. Ignore those entries; it's a known indexing quirk.

---

## 13. Final checklist before you say "done" for any milestone

- [ ] Did you touch any out-of-scope file (Map, WebView, AppDelegate, etc.)?  → revert.
- [ ] Did you modify the `webgl-component/` submodule?  → revert; that's a separate repo.
- [ ] Did you add an iOS-side copy of `models_to_place.json` or any `.glb`?  → revert; canonical lives in webgl.
- [ ] Did you weaken `.gitignore` (e.g., remove the `*.usdz` rule)?  → revert.
- [ ] Did you push to `main` without operator awareness?  → at minimum, summarize the push in your handoff.
- [ ] Did you claim "it works" without device verification?  → restate as "code change applied; device verification still required."
- [ ] Did you update the relevant `docs/phases/` doc to reflect the new state?  → if you changed plan-affecting facts, the docs need to track.
- [ ] Did you remove the `// SPIKE:` block from `ARViewController.swift` when M02.0 is done?  → only at the M02.0 cleanup commit, not before.

---

## 14. What to put in your own handoff when you stop

Update this file before you stop, in this section:

> **As of commit `<sha>` on `<date>`:**
> - Spike A status: (not started / running / PASS / FAIL with fallback PASS / FAIL)
> - Spike B status:
> - Spike C status:
> - Outstanding operator-side actions: (e.g., "needs to add ARCore SDK via SPM", "needs to record AC-2 drift measurement")
> - Outstanding agent-side actions: (e.g., "need to implement Spike B SceneKit render path once Spike A outcome confirmed")
> - Surprises / new traps: (anything not already in §12)
> - Decision changes since last handoff: (anything that overturned §6)

Keep this section terse. The rest of the doc carries the long-form context.
