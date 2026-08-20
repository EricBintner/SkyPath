# SkyPath — Plan Loose Ends & Priorities

> Generated: 2026-06-27
>
> This document consolidates every gap, deferred item, and open question found by comparing the committed plan documents to the actual repo state. It is intended as a living checklist, not a plan rewrite. Update it as items are completed or new gaps are discovered.

---

## How this document was built

Each entry below cites either a **plan document** (`Phase01…`, `Phase02…`, `2026-06-15-ar-webgl-resource-management.md`, `Phase03…`) or the **actual code state** (file/line references). Gaps are grouped by phase/track. Items are marked:

- 🔴 **Blocking** — must be resolved before later work can proceed.
- 🟡 **Important** — has a clear user-visible impact or unblocks acceptance criteria.
- 🟢 **Cleanup / deferred** — safe to leave for a dedicated cleanup pass, but should not be forgotten.

---

## 1. Phase 01 — Restart Plan

Source: `docs/phases/Phase01_Restart_Plan.md`

| # | Item | State | Evidence / Notes |
|---|---|---|---|
| 1.1 | SceneKit baseline restored | ✅ Done | `ARViewController.swift` exists and compiles. |
| 1.2 | WebGL submodule attached | ✅ Done | `webgl-component/` is present; `Package.resolved` and build phase reference it. |
| 1.3 | Big USDZs stripped, `skypath_001.usdz` kept | ✅ Done | `.gitignore` blocks `*.usdz` except the smoke-test asset. |
| 1.4 | **Verify Xcode opens cleanly** | 🔴 Open | Docs list this unchecked. The active project is now `GeoTestARScene/SkyPath.xcodeproj`, but an untracked `GeoTestARScene/GeoTestARScene.xcodeproj/` still exists and may confuse builds / CI. |
| 1.5 | Reproducible "sliding" capture | 🟡 Moved to M02.2 | Ground-truth baseline still needs to be recorded on a documented NYC block. |

**Action needed:**
- Delete or `.gitignore` the stale `GeoTestARScene.xcodeproj/` directory.
- Confirm `SkyPath.xcodeproj` opens in Xcode with no missing-file errors.

---

## 2. Phase 02 — VPS-Grounded, Architecturally-Occluded AR

Source: `docs/phases/Phase02_VPS_Grounded_Occluded_Plan.md`, `Phase02_Spike_Playbook.md`, `Phase02_Spike_Results.md`, `Phase02_AI_Handoff.md`

### 2.1 M02.0 — Feasibility spikes

| # | Item | State | Evidence / Notes |
|---|---|---|---|
| 2.1.1 | Spike A implemented (ARGeoTracking + GARSession coexistence) | ✅ Done | `GeoTestARScene/GeoTestARScene/Spike/SpikeAViewController.swift` exists and imports `ARCore`. |
| 2.1.2 | Spike B implemented (SceneKit vs RealityKit renderer) | ✅ Done | Git history: `3db8370 SpikeB: implement SceneKit and RealityKit render paths`. |
| 2.1.3 | Spike C scaffolded (sliding baseline capture) | ✅ Done | `SpikeCViewController.swift` exists. |
| 2.1.4 | Spike Results doc filled in | 🔴 Open | `Phase02_Spike_Results.md` is still a blank template. No field data, no pose-stack decision, no renderer decision, no baseline metrics. |
| 2.1.5 | Spike cleanup commit | 🟡 Open | `Spike/` folder, the `// SPIKE:` hook in `ARViewController.swift:86-165`, and the `SHOW_SPIKE_MENU` scheme env var still exist. Should be removed in one commit after results are recorded. |

**Action needed:**
- Run the spikes on device and fill in `Phase02_Spike_Results.md`.
- Once results are in, do the single cleanup commit described in the playbook.

### 2.2 M02.1 — Pure baseline boot

| # | Item | State | Evidence / Notes |
|---|---|---|---|
| 2.2.1 | App launches on device and reaches `.localized` | 🟡 Partially verified | `ARViewController` starts `ARWorldTrackingConfiguration` in `viewWillAppear` then switches to `ARGeoTrackingConfiguration` after Start AR is tapped. No known crash, but no formal recorded verification. |
| 2.2.2 | Shared-data build phase copies canonical JSON | ✅ Done | `SkyPath.xcodeproj` has `BEEFCAFE2DB9562300D36E75 /* Copy shared data from webgl-component */`. `ARViewController.loadLocationData()` reads from `Models/models_to_place.json`. |

**Action needed:**
- Record a baseline boot verification note once a clean device build is run.

### 2.3 M02.2 — `earthFrame` + ARGeoAnchor parity

| # | Item | State | Evidence / Notes |
|---|---|---|---|
| 2.3.1 | Add `earthFrame` SCNNode at scene-graph root | 🟢 Implemented (simulator-verified) — device ACs pending | Design spec: `docs/superpowers/specs/2026-06-30-earthframe-node-hierarchy-design.md` (v2, scrutinized 2026-07-01). Implemented on branch `m02.2-earthframe` (Tasks 1–8): `earthFrame` added as an idempotent child of `sceneView.scene.rootNode` in `setupARView()` (guard `earthFrame?.parent == nil`), invariant-guarded via a `didSet` on `earthFrame` + `EarthFrameHierarchy.assertIdentity`. Unit tests green on iPhone 17 sim (`xcodebuild clean test`). Device-only ACs (`earthFrame` is a child of root at runtime, visual-unchanged) pending on-device verification. |
| 2.3.2 | Move anchors/content under `earthFrame/anchors/<id>` | 🟢 Implemented (simulator-verified) — device ACs pending | Same spec. Scope expanded: self-cleaning removal across **all** reset/restart/failure paths (`viewWillAppear`, `startGeoTrackingSession`, LIDAR, high-accuracy reload, `session:didFailWithError:`) — not just the reload — after scrutiny found v1's defense-in-depth was incomplete. `unloadModel` made `didRemove`-authoritative. Per-branch reparent, idempotent creation, `didSet`+pure-validator invariant, race fix. Implemented on branch `m02.2-earthframe` (Tasks 5–7): per-branch reparent in `renderer(_:didAdd:for:)` (plane/mesh→`earth_occluders`, geo placeholder+success→`earth_anchors`, with reparent-site `assertIdentity`); `clearEarthFrameChildrenAndTracking()` helper called from all 5 reset/restart/failure paths + `didRemove` authoritative per-node removal; high-accuracy reload flag-first race fix + `anchorsFrame` clear (does NOT call the full helper, to preserve the flag); `unloadModel` node-removal made unconditional (`else if`→`if`). Unit tests green on iPhone 17 sim. Device-only ACs (geo anchors render under `earth_anchors`, visual unchanged, orphan-free across Spike-dismiss / Start AR restart / LIDAR toggle / high-accuracy reload / session-failure during a localized walk) pending on-device verification. |
| 2.3.3 | Remove `setWorldOrigin` calls | 🟢 N/A | No `setWorldOrigin` calls were found in `ARViewController.swift`. |

**Action needed:**
- Implement `earthFrame` before any correction-loop work (M02.5).

### 2.4 M02.3 — Shared-data pipeline + GLTFKit2 + glb loading

This is the largest gap between the plan and the code.

| # | Item | State | Evidence / Notes |
|---|---|---|---|
| 2.4.1 | Add GLTFKit2 via Swift Package Manager | 🔴 Not added | `SkyPath.xcodeproj/Package.resolved` has no `GLTFKit2` pin. Project has only the `arcore-ios-sdk` package reference. |
| 2.4.2 | Build phase copies `.glb` files into bundle | ✅ Done | Build phase copies `webgl-component/skypath_models/*.glb` to `Models/`. |
| 2.4.3 | `Models.swift::LocationPoint` parses `sequence` | 🔴 Not parsed | `LocationPoint` (`Models.swift:8-22`) decodes only the legacy field set. |
| 2.4.4 | Parse `model_ground_offset` | 🔴 Not parsed | Same as above. Plan explicitly calls this "the most consequential" omission. |
| 2.4.5 | Parse `model_scale_x/y/z` | 🔴 Not parsed | Same as above. |
| 2.4.6 | `ARModelLocation` stores new fields | 🔴 Not added | `ARModelLocation` (`Models.swift:24-39`) lacks sequence, ground offset, and scale properties. |
| 2.4.7 | Loader resolves `model_variant` → `<modelsDir>/<variant>.glb` | 🔴 Not done | `preloadModels()` (`ARViewController.swift:464-492`) still resolves to `.usdz` via `Bundle.main.url(forResource: name, withExtension: "usdz")`. |
| 2.4.8 | Replace USDZ load with `GLTFAsset.load(...)` + `SCNScene(gltfAsset:)` | 🔴 Not done | Same as above; uses `SCNScene(url:)` on USDZ. |
| 2.4.9 | Apply ground offset and scale at placement | 🔴 Not done | `createContentNode(for:cachedModel:)` (`ARViewController.swift:687-732`) only applies rotation/tilt. |
| 2.4.10 | AC-0 verification (JSON change in webgl repo propagates to iOS with no iOS-side edit) | 🔴 Not done | Cannot verify until GLTFKit2 + `.glb` loading works end-to-end. |

**Action needed:**
- Add GLTFKit2 SPM dependency.
- Extend `LocationPoint`/`ARModelLocation` with the new schema fields.
- Rewrite model loading to consume `.glb` from the `Models/` bundle directory.
- Apply ground offset and per-axis scale in the placement transform.

### 2.5 M02.4 — GARSession + Streetscape Geometry occluders

| # | Item | State | Evidence / Notes |
|---|---|---|---|
| 2.5.1 | ARCore iOS SDK added | ✅ Done | `Package.resolved` pins `arcore-ios-sdk` 1.54.0; `ARCoreGeospatial`, `ARCoreGARSession` products linked. |
| 2.5.2 | API key wired | ✅ Done | `GeoTestARScene/xcconfigs/APIKeys.local.xcconfig` injects `ARCORE_API_KEY` into generated `Info.plist` via `INFOPLIST_KEY_ARCORE_API_KEY`. File is gitignored. |
| 2.5.3 | `GARSession` instantiated and fed `ARFrame`s | 🔴 Not done | `ARViewController` has no `GARSession` property and no `GARSession.update(_:)` call. |
| 2.5.4 | Streetscape Geometry converted to occluder nodes | 🔴 Not done | Current occlusion uses LiDAR `ARMeshAnchor` → `meshNodes` only when `isLidarDebugMode` is true. No Streetscape Geometry path exists. |
| 2.5.5 | Occluders parented under `earthFrame/occluders` | 🔴 Blocked by 2.3.1 | Cannot do until `earthFrame` exists. |

**Action needed:**
- Add `GARSession` lifecycle in `ARViewController`.
- Add `GARStreetscapeGeometry` → `SCNGeometry` conversion (or RealityKit equivalent, depending on Spike B result).
- Parent occluders under `earthFrame`.

### 2.6 M02.5 — Bounded reactive correction loop

| # | Item | State | Evidence / Notes |
|---|---|---|---|
| 2.6.1 | IMU stillness detector | 🔴 Not done | No `CMMotionManager` / `deviceMotion` usage found in `ARViewController`. |
| 2.6.2 | EMA correction on `earthFrame.transform` | 🔴 Blocked | Requires `earthFrame`. |
| 2.6.3 | Clamp bounds (≤0.5° yaw, ≤5 cm translation) | 🔴 Blocked | Requires correction loop. |
| 2.6.4 | Gate on GAR yaw uncertainty < 5° and stillness / `.high` accuracy | 🔴 Blocked | Requires GARSession integration. |
| 2.6.5 | Repeat Spike C walk and compare | 🔴 Blocked | Requires everything above. |

### 2.7 M02.6 / M02.7 — Field testing and documentation pass

| # | Item | State | Evidence / Notes |
|---|---|---|---|
| 2.7.1 | AC-0 through AC-4 pass on a documented block | 🔴 Not started | Acceptance criteria are still aspirational. |
| 2.7.2 | Update plan with as-built notes and open Phase 03 stub | 🟢 Deferred | Do after field testing. |

---

## 3. AR ⇄ WebGL Resource Management

Source: `docs/superpowers/plans/2026-06-15-ar-webgl-resource-management.md`

| # | Item | State | Evidence / Notes |
|---|---|---|---|
| 3.1 | Add `releaseWebGL()` / `activateWebGL()` | ✅ Done | `LocationsViewController.swift:94-108`. |
| 3.2 | Add `releaseAR()` / `activateAR()` | 🔴 Missing | Grep for `func releaseAR` or `func activateAR` in `ARViewController.swift` returns nothing. |
| 3.3 | Wire mutual-exclusion policy into `switchToView` | 🔴 Not done | `ViewController.switchToView(_:)` (`ViewController.swift:380-469`) still uses the old DevTools-gated `pauseWebContent()`/`resumeWebContent()` block. It never calls `releaseWebGL()`, `activateWebGL()`, or AR release/activate. |
| 3.4 | On-device verification | 🔴 Not done | Cannot verify until 3.2 and 3.3 are done. |
| 3.5 | Delete unused `pauseWebContent()` / `resumeWebContent()` | 🟢 Cleanup | Plan explicitly says this is a follow-up cleanup. |
| 3.6 | Deferred unit-test target + extract pure `resourceActions()` function | 🟢 Deferred | Captured at the bottom of the resource-management plan. |

**Action needed:**
- Implement `releaseAR()` / `activateAR()`.
- Replace the old DevTools-gated web pause/resume block with the destination-keyed policy from the plan.
- Run the verification steps from Task 4 of the plan.

---

## 4. Phase 03 — WebGL Model & Memory Optimization

Source: `docs/phases/Phase03_WebGL_Model_Optimization.md`

| # | Item | State | Evidence / Notes |
|---|---|---|---|
| 4.1 | Interim tileset memory cap (100 MB cache, SSE 16) | ✅ Done | `webgl-component/main.js:1392-1393`. |
| 4.2 | Record on-device `peak=` baseline | 🟡 Partially done | Diagnostics exist, but no documented baseline number is recorded in the plan. |
| 4.3 | Inspect texture inventory | 🟡 Not documented | No `npx @gltf-transform/cli inspect` output is captured in the repo. |
| 4.4 | Right-size textures | 🔴 Not done | No `skypath_02.resized.glb` or similar files. |
| 4.5 | Re-encode to KTX2 / Basis Universal | 🔴 Not done | Models still use `EXT_texture_webp`. |
| 4.6 | Geometry compression (`EXT_meshopt_compression`) | 🔴 Not done | No compressed model output. |
| 4.7 | Decide how to spend freed headroom | 🔴 Not decided | Blocked until memory reduction is measured. |
| 4.8 | Resolve Cesium CSS/engine version mismatch | 🔴 Not done | `webgl-component/index.html:7` loads CSS `1.129`; `index.html:122` loads engine `1.121`. |
| 4.9 | Remove temporary diagnostics block | 🔴 Not done | `webgl-component/main.js` still has the `TEMPORARY iOS-CRASH DIAGNOSTICS` block (~lines 693–842). |
| 4.10 | Add optional `webViewWebContentProcessDidTerminate(_:)` handler | 🟢 Optional | `LocationsViewController.swift` does not implement this delegate method. |
| 4.11 | Fix latent `pauseWebContent` no-op | 🟢 Cleanup | JS checks `window.Cesium.viewer`, but `main.js` uses module-scope `viewer` and does not assign it there. Since the plan moves to `releaseWebGL`, this is cleanup. |

---

## 5. Housekeeping & cross-cutting

| # | Item | State | Evidence / Notes |
|---|---|---|---|
| 5.1 | Stale untracked `GeoTestARScene.xcodeproj/` | 🔴 Open | Untracked at repo root; confuses active project identity. |
| 5.2 | Untracked `visual_directions.html` | 🟡 Open | At repo root. Purpose unclear — experiment, trash, or new doc? |
| 5.3 | Untracked `.claude/` | 🟢 Fine | Local Claude configuration; expected untracked. |
| 5.4 | No iOS unit-test target | 🟢 Deferred | Recorded in resource-management plan and memory. |
| 5.5 | `research-todos.md` still contains out-of-scope cesium-native/Metal research | 🟢 Cleanup risk | Future agents may re-explore abandoned paths. Consider adding a header or archiving obsolete sections. |
| 5.6 | `AGENTS.md` Atlas characterizes `Phase02_Spike_Results.md` as "stable" | 🟢 Cleanup | Revisit once spikes are completed and results doc is populated. |
| 5.7 | `Package.resolved` is gitignored | 🟡 Policy question | `.gitignore` ignores `Package.resolved`, so the exact SPM pin set is not committed. This is a team policy call; current `SkyPath.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` exists but is ignored. |

---

## 6. Suggested priority order

1. 🔴 **Finish M02.0 spikes + record results** — unblocks pose/renderer decisions for everything else.
2. 🔴 **M02.3: add GLTFKit2 + `.glb` loading + parse new schema fields** — unblocks actual content rendering and AC-0.
3. 🔴 **M02.2: add `earthFrame` node hierarchy** — foundation for M02.4/M02.5.
4. 🔴 **Resource management: implement `releaseAR`/`activateAR` and wire policy** — finishes work already half-merged.
5. 🟡 **M02.4: add `GARSession` + Streetscape Geometry occluders** — depends on spike results and earthFrame.
6. 🟡 **M02.5: bounded correction loop** — depends on earthFrame + GARSession.
7. 🟡 **Phase 03 WebGL optimization** — KTX2, version alignment, diagnostics cleanup.
8. 🟢 **Housekeeping** — delete stale Xcode project, decide on `visual_directions.html`, archive stale research sections.

---

## 7. Decision log (add entries as choices are made)

| Date | Decision | Rationale |
|---|---|---|
| 2026-06-27 | Created this loose-ends document | Need a single source of truth for gaps before prioritizing next work. |
| 2026-06-27 | Added adversarial scrutiny findings (see §8) | Multi-agent review found new blocking issues around ARCore API signature, bundle ID mismatch, Spike C delegate bug, and resource-management race conditions. |
| 2026-06-30 | Verified this doc against repo | Spot-checked all 🔴 blocking + priority claims; all accurate except §5.4 "no unit-test target" (stale — `GeoTestARSceneTests`/`UITests` exist; self-corrected in §8 MERGED-024). Updated memory `deferred-ios-test-target.md`. |
| 2026-06-30 | earthFrame design (M02.2) approved; spec written | `docs/superpowers/specs/2026-06-30-earthframe-node-hierarchy-design.md`. 3-agent verification: reparent-under-identity is safe, but ARKit auto-removal of reparented nodes is undocumented → self-cleaning removal now in scope (D3); test target had stale `@testable import GeoTestARScene` (module renamed `SkyPath`) → fix in scope (D5). earthFrame pinned to identity until M02.5 transform spec (MERGED-005) (D2). Carry-over D4: occluders must not receive EMA correction; structure revisit needed before lifting identity. |
| 2026-07-01 | earthFrame spec scrutinized → v2 | 5-agent scrutiny reverse-engineered `ARViewController.swift` and empirically ran `xcodebuild test`. v2 fixes: self-cleaning extended to ALL reset/restart/failure paths (viewWillAppear, startGeoTrackingSession, LIDAR, session:didFailWithError:), `unloadModel` made `didRemove`-authoritative (v1 edit was a partial no-op), per-branch reparent insertion, idempotent earthFrame creation (D7), `didSet`+pure-validator invariant (D8), AC verifiability split simulator-vs-device (D9), `-only-testing:SkyPathTests` (D6), clean-build caveat, race fix in high-accuracy reload. Plan §5 "occluders move with content" flagged as incorrect (MERGED-011). Empirically confirmed: tests run on iPhone 17 sim (OS 26.5) after D5 fix; app target is synchronized-folder (no pbxproj edit for factory file); APIKeys.local.xcconfig present; ENABLE_TESTABILITY=YES. |
| 2026-07-01 | M02.2 earthFrame implemented (simulator-verified) | Executed the 9-task plan via subagent-driven-development on branch `m02.2-earthframe` (commits: 381063f docs → 54688a1 T1 import fix → 7ed3c4b T2 factory → 5f67802 T3 isIdentity test → d562fc1 T4 reparent proxy test → d19164b T5 ARViewController wire → 4a5a470 T6 reparent+asserts → c6b01c0 T7 self-cleaning → f37e1f8 T8 worldPosition doc). `xcodebuild clean test` green (4 tests, 2 suites); `xcodebuild clean build` green. **Spec↔plan gaps found & fixed during execution** (spec wins over plan): (a) Task 6 — spec §3.5/D8 requires `EarthFrameHierarchy.assertIdentity` at the reparent sites, but the plan's Task 6 code omitted it; added the 4 reparent-site asserts so the implementation matches the spec (and the `assertIdentity` doc comment becomes accurate). (b) Task 7 — the plan's Step 8 "Change from" inaccurately showed `if let node`; the real code had `} else if let node` (which would SKIP node removal when an anchor existed, leaving a ghost); applied the unconditional `if let node` per the comment's stated intent ("node removal is unconditional"). (c) Discovered: the per-test `-only-testing:SkyPathTests/EarthFrameHierarchyTests/<method>` filter reports "Executed 0 tests" for Swift Testing tests in this toolchain — use the suite-level filter `-only-testing:SkyPathTests/EarthFrameHierarchyTests` instead. Device-only ACs (visual-unchanged, runtime under-root, orphan-free across a localized walk) pending on-device verification. |
| 2026-07-01 | M02.2 final holistic review → ready to merge (pending device ACs) | Final whole-feature review (Opus) against spec v2 §3/§8: spec-complete, all simulator-verifiable ACs covered by real (non-tautological) tests + clean build/test; invariant integrity confirmed (zero writes to `earthFrame.transform` in the diff); self-cleaning traced across every `session.run`/restart/failure path with no missed path; regression risk to existing geo/plane/mesh flows negligible (reparent under identity `earthFrame` preserves world transforms; no code iterates `sceneView.scene.rootNode.childNodes` or does root-relative hit-testing). **Verdict: ready to merge, pending device-only ACs.** Three Minor doc/clarity items deferred to the M02.7 doc pass (none affect correctness): (1) spec §3.5 slightly oversells the `didSet` — it fires on `earthFrame` property reassignment, not on in-place `earthFrame.simdTransform` mutation (the reparent-site asserts cover that gap); spec wording to be clarified in M02.7. (2) High-accuracy reload uses an inlined partial clear (`loadedLocations` + `anchorsFrame` children) instead of the shared `clearEarthFrameChildrenAndTracking()` helper — justified (occluders must persist across a geo reload); an optional `clearGeoAnchorChildren()` sibling would self-document. (3) `unloadModel`'s comment frames `didRemove` as "the authoritative cleaner," which is true for ARKit-initiated removals but not for `unloadModel`-initiated removals of placed models (where `session.remove` is skipped per the documented carry-over, so `didRemove` doesn't fire and the synchronous `node.removeFromParentNode()` is the cleaner); comment to be reworded in M02.7. |

---

## 8. New issues from adversarial scrutiny (2026-06-27)

These findings came from a parallel three-lens review (technical correctness, sequencing/dependencies, WebGL/resource management). They are ranked by severity. Verified findings are marked.

### 🔴 Blocking

| ID | Issue | Where | Suggested action | Verified |
|---|---|---|---|---|
| MERGED-001 | M02.3 is unimplemented: loader still uses `.usdz`, GLTFKit2 not added, `Models.swift` parses only legacy schema, and the plan scopes work to out-of-scope `ViewController.swift`. | `ARViewController.swift:464-492`; `Models.swift:8-39`; `ViewController.swift:570-608`; `Phase02_VPS_Grounded_Occluded_Plan.md §M02.3`; `AGENTS.md` | Move `getSequenceFor(id:)` out of `ViewController.swift`; add GLTFKit2; extend schema; rewrite `preloadModels()`. | ✅ Confirmed |
| MERGED-002 | Spike C uses wrong ARKit delegate selector `session(_:didUpdate geoTrackingStatus:)` instead of `session(_:didChange:)`. | `SpikeCViewController.swift:142`; `ARViewController.swift:853`; `Phase02_AI_Handoff.md §12` | Rename selector; verify OSLog fires on device before running baseline walk. | ✅ Confirmed |
| MERGED-003 | Spike code calls `try GARSession(apiKey:bundleIdentifier:)` as throwing initializer, but ARCore 1.54 documents a class factory `sessionWithAPIKey:bundleIdentifier:error:`. | `SpikeAViewController.swift:144`; `SpikeBViewController.swift:195`; `Phase02_Spike_Playbook.md §4.5` | Verify actual imported Swift signature in a scratch build; update spike code and playbook. | ℹ️ Already documented as known API drift in playbook §4.5, but the spike code itself may still need a compile fix. |
| MERGED-004 | Active bundle ID is `com.ericbintner.SkyPath`, but spike docs still instruct restricting ARCore API key to old `com.ericbintner.GeoTestARScene`. | `project.pbxproj` `PRODUCT_BUNDLE_IDENTIFIER`; `Phase02_Spike_Playbook.md §0.3-0.4`; `Phase02_AI_Handoff.md §12.7` | Update Google Cloud key restriction to new bundle ID, or revert bundle ID and update docs. | ✅ Confirmed |
| MERGED-005 | Anti-slide `earthFrame` correction math is hand-wavy: `T_implied = anchor.transform × ENU_at_anchor⁻¹` lacks definitions for `ENU_at_anchor`, reference frame, multiplication order, and matrix interpolation. | `Phase02_VPS_Grounded_Occluded_Plan.md §4` | Write a short transform spec defining ENU_at_anchor and proving the update before coding M02.5. | ✅ Confirmed |
| MERGED-006 | `about:blank` may not actually free WKWebView WebContent/GPU memory; no `webViewWebContentProcessDidTerminate(_:)` crash handler exists. | `LocationsViewController.swift:94-108`; resource-management design spec; `Phase03_WebGL_Model_Optimization.md §6` | Validate with on-device memory graph; implement terminate handler; consider stronger teardown if needed. | — |
| MERGED-007 | Resource-management policy is half-merged: `releaseWebGL`/`activateWebGL` exist, but `releaseAR`/`activateAR` are missing and `ViewController.switchToView` still uses old DevTools-gated pause/resume. | `LocationsViewController.swift:92-108`; `ViewController.swift:389-399,448-466`; `ARViewController.swift:100-102`; resource-management plan §Task 2-3 | Implement `releaseAR`/`activateAR`; replace old pause/resume block with destination-keyed policy. | — |

### 🟡 Major

| ID | Issue | Where | Suggested action |
|---|---|---|---|
| MERGED-008 | `ARViewController.viewWillAppear` pre-warms with `ARWorldTrackingConfiguration` instead of starting `ARGeoTrackingConfiguration` immediately. | `ARViewController.swift:96-102` vs `:220-300`; `Phase02_VPS_Grounded_Occluded_Plan.md §M02.1` | Start `ARGeoTrackingConfiguration` immediately if supported; gate placement on `.localized`. |
| MERGED-009 | High-accuracy reload logic destroys all anchors and replaces them with only two closest models — a mid-session hard reset. | `ARViewController.swift:935-957` | Remove or flag-gate this reset; rely on bounded correction loop instead. |
| MERGED-010 | M02.5 correction loop lacks CoreMotion stillness detector and `didUpdate anchors:` handler. | `ARViewController.swift` (no CoreMotion); `Phase02_VPS_Grounded_Occluded_Plan.md §4,§M02.5` | Add CoreMotion and anchor-update telemetry in M02.4 before EMA tuning. |
| MERGED-011 | Occluder coordinate convention under `earthFrame` is undefined once EMA corrections shift `earthFrame.transform`. | `Phase02_VPS_Grounded_Occluded_Plan.md §5` | Document convention: keep `earthFrame` fixed after seeding, or convert `geom.meshTransform` to earthFrame-local. **Update 2026-07-01:** earthFrame spec D4 confirms occluders must NOT receive the EMA correction and flags plan §5 ("occluders and content move together") as **incorrect** — plan §5 slated for correction in the M02.7 doc pass. Four M02.5 options enumerated in the spec. |
| MERGED-012 | Loose-ends doc serializes spikes before infrastructure, but infrastructure (earthFrame, GLTFKit2, resource wiring) does not require spikes. | `docs/loose-ends-and-priorities.md §6`; `Phase02_VPS_Grounded_Occluded_Plan.md §1,§7` | Restate priority order to allow parallel infrastructure work; gate only truly conditional milestones on spikes. |
| MERGED-013 | `activateWebGL()` has a race: `releaseWebGL()` starts async `about:blank` navigation; `activateWebGL()` may reload before it completes. | `LocationsViewController.swift:94-108`; `webgl-component/main.js` | Serialize via `WKNavigationDelegate`; add JS cleanup of tour/entities on release. |
| MERGED-014 | Phase 03 assumes KTX2/Basis savings without verifying Cesium version compatibility or iOS transcoding. CSS 1.129 is paired with engine 1.121. | `webgl-component/index.html:7,:122`; `Phase03_WebGL_Model_Optimization.md §Milestone D,§6` | Align engine/CSS to 1.129 first; run one-device KTX2 smoke test before bulk conversion. |
| MERGED-015 | On-screen memory gauge only sums tileset memory, ignores placed model entities and viewer state. | `webgl-component/main.js:821-835`; `Phase03_WebGL_Model_Optimization.md §5` | Extend gauge to include model memory; do not use tileset-only metric as acceptance criteria. |
| MERGED-016 | Texture right-sizing lacks an objective quality threshold or comparison tooling. | `Phase03_WebGL_Model_Optimization.md §5` | Define SSIM/texel-per-meter threshold before resizing. |
| MERGED-017 | Spike B assumes raw `GARVertex`/`GARIndexTriangle` byte layout and may silently fail on large meshes. | `SpikeBViewController.swift:307-336,362-385` | Validate buffer layout against ARCore headers; add failure HUD count. |
| MERGED-018 | `webViewWebContentProcessDidTerminate(_:)` would touch `LocationsViewController.swift`, which is out of scope per `AGENTS.md`. | `Phase03_WebGL_Model_Optimization.md §Milestone D`; `AGENTS.md` | Get explicit permission, or document the scope conflict and drop the iOS safety net. |
| MERGED-019 | Phase 02 fallback path says `GARSession.earth.cameraGeospatialTransform`, but `earth` lives on `GARFrame`, not `GARSession`. | `Phase02_VPS_Grounded_Occluded_Plan.md §3`; `SpikeAViewController.swift:280` | Edit plan to reference `garFrame.earth.cameraGeospatialTransform`. |

### 🟢 Minor / cleanup

| ID | Issue | Where | Suggested action |
|---|---|---|---|
| MERGED-020 | SceneKit occluder recipe sets `readsFromDepthBuffer = true`, which may cause self-occlusion artifacts. | `Phase02_VPS_Grounded_Occluded_Plan.md §5`; `SpikeBViewController.swift:65` | Set `readsFromDepthBuffer = false` on occluder material; verify in Spike B. |
| MERGED-021 | Web viewer applies only uniform scale from `model_scale_x`; iOS plan says honor all three axes. | `webgl-component/main.js:398`; `Phase02_VPS_Grounded_Occluded_Plan.md §M02.3` | Align webgl to non-uniform scale or remove y/z fields from schema. |
| MERGED-022 | `Package.resolved` is gitignored, so SPM pins are not committed. | `.gitignore:34`; `SkyPath.xcodeproj/project.xcworkspace/.../Package.resolved` | Decide policy: unignore for reproducibility, or document intentional unpinned builds. |
| MERGED-023 | Spike A/B enable Geospatial/Streetscape modes without `isGeospatialModeSupported`/`isStreetscapeGeometryModeSupported` checks. | `SpikeAViewController.swift:151-153`; `SpikeBViewController.swift:197-198`; `Phase02_Spike_Playbook.md §0.2` | Add supportability checks before `setConfiguration`. |
| MERGED-024 | Project already has `SkyPathTests`/`GeoTestARSceneTests` target; plans say no test target exists. | `GeoTestARSceneTests/GeoTestARSceneTests.swift`; resource-management plan; `Phase02_AI_Handoff.md §9` | Update plans: target exists but is empty; deferred tests should land there. |
| MERGED-025 | AC-3 "80% of facade pixel area" has no measurement protocol. | `Phase02_VPS_Grounded_Occluded_Plan.md §1` | Define screen-recording / image-diff protocol. |
| MERGED-026 | Spike cleanup docs do not explicitly say to keep ARCore SPM package after deleting spike sources. | `Phase02_Spike_Playbook.md §0.2`; `Phase02_VPS_Grounded_Occluded_Plan.md §M02.0,§M02.4` | Add explicit cleanup step: retain ARCore and GLTFKit2 packages. |
| MERGED-027 | Map tab is assumed light; no memory profile evidence. | Resource-management design spec; `ViewController.swift:64-67` | Profile Map memory/GPU on device; update policy if needed. |
| MERGED-028 | Untracked stale `GeoTestARScene.xcodeproj/` exists. | `GeoTestARScene/GeoTestARScene.xcodeproj/` | Delete and/or `.gitignore` old project directory. |
| MERGED-029 | Plan calls SSE 16 "full detail"; lower SSE = higher detail in Cesium. | `Phase03_WebGL_Model_Optimization.md §0,§5`; `main.js:1392` | Replace "full detail" with "default detail (SSE 16)". |
| MERGED-030 | Phase 03 uses unpinned `npx @gltf-transform/cli@latest` and `brew install ktx`. | `Phase03_WebGL_Model_Optimization.md §Milestone B` | Pin tool versions and document them. |

---

## 9. Revised priority order

After the scrutiny pass, the priority order is updated to reflect true dependencies and allow parallel work:

**Track A — Spikes (requires device + field time):**
1. 🔴 Fix Spike C delegate selector bug (`MERGED-002`).
2. 🔴 Resolve bundle ID / ARCore API key mismatch (`MERGED-004`).
3. 🔴 Verify/fix `GARSession` Swift signature compile issue (`MERGED-003`).
4. 🔴 Run spikes A/B/C and record results in `Phase02_Spike_Results.md`.

**Track B — Infrastructure (can proceed in parallel with spikes):**
5. 🔴 Add GLTFKit2 + `.glb` loading + schema fields (`MERGED-001`).
6. 🔴 Add `earthFrame` node hierarchy (`2.3.1`).
7. 🔴 Implement `releaseAR`/`activateAR` and wire resource policy (`MERGED-007`).
8. 🟡 Clean up stale `GeoTestARScene.xcodeproj/` (`MERGED-028`).

**Track C — Conditional on spike results:**
9. 🟡 Implement `GARSession` + Streetscape Geometry occluders.
10. 🟡 Implement bounded correction loop (blocked by earthFrame + GARSession + CoreMotion).

**Track D — WebGL optimization (mostly independent):**
11. 🟡 Align Cesium engine/CSS versions; remove temporary diagnostics.
12. 🟡 KTX2/Basis asset optimization after version alignment.

---

## 10. Decision log (continued)

| Date | Decision | Rationale |
|---|---|---|
| 2026-06-27 | Created this loose-ends document | Need a single source of truth for gaps before prioritizing next work. |
| 2026-06-27 | Added adversarial scrutiny findings (see §8) | Multi-agent review found new blocking issues around ARCore API signature, bundle ID mismatch, Spike C delegate bug, and resource-management race conditions. |
| 2026-06-30 | Verified this doc against repo | Spot-checked all 🔴 blocking + priority claims; all accurate except §5.4 "no unit-test target" (stale — `GeoTestARSceneTests`/`UITests` exist; self-corrected in §8 MERGED-024). Updated memory `deferred-ios-test-target.md`. |
| 2026-06-30 | earthFrame design (M02.2) approved; spec written | `docs/superpowers/specs/2026-06-30-earthframe-node-hierarchy-design.md`. 3-agent verification: reparent-under-identity is safe, but ARKit auto-removal of reparented nodes is undocumented → self-cleaning removal now in scope (D3); test target had stale `@testable import GeoTestARScene` (module renamed `SkyPath`) → fix in scope (D5). earthFrame pinned to identity until M02.5 transform spec (MERGED-005) (D2). Carry-over D4: occluders must not receive EMA correction; structure revisit needed before lifting identity. |
| 2026-07-01 | earthFrame spec scrutinized → v2 | 5-agent scrutiny reverse-engineered `ARViewController.swift` and empirically ran `xcodebuild test`. v2 fixes: self-cleaning extended to ALL reset/restart/failure paths (viewWillAppear, startGeoTrackingSession, LIDAR, session:didFailWithError:), `unloadModel` made `didRemove`-authoritative (v1 edit was a partial no-op), per-branch reparent insertion, idempotent earthFrame creation (D7), `didSet`+pure-validator invariant (D8), AC verifiability split simulator-vs-device (D9), `-only-testing:SkyPathTests` (D6), clean-build caveat, race fix in high-accuracy reload. Plan §5 "occluders move with content" flagged as incorrect (MERGED-011). Empirically confirmed: tests run on iPhone 17 sim (OS 26.5) after D5 fix; app target is synchronized-folder (no pbxproj edit for factory file); APIKeys.local.xcconfig present; ENABLE_TESTABILITY=YES. |
| 2026-07-01 | M02.2 earthFrame implemented (simulator-verified) | Executed the 9-task plan via subagent-driven-development on branch `m02.2-earthframe` (commits: 381063f docs → 54688a1 T1 import fix → 7ed3c4b T2 factory → 5f67802 T3 isIdentity test → d562fc1 T4 reparent proxy test → d19164b T5 ARViewController wire → 4a5a470 T6 reparent+asserts → c6b01c0 T7 self-cleaning → f37e1f8 T8 worldPosition doc). `xcodebuild clean test` green (4 tests, 2 suites); `xcodebuild clean build` green. **Spec↔plan gaps found & fixed during execution** (spec wins over plan): (a) Task 6 — spec §3.5/D8 requires `EarthFrameHierarchy.assertIdentity` at the reparent sites, but the plan's Task 6 code omitted it; added the 4 reparent-site asserts so the implementation matches the spec (and the `assertIdentity` doc comment becomes accurate). (b) Task 7 — the plan's Step 8 "Change from" inaccurately showed `if let node`; the real code had `} else if let node` (which would SKIP node removal when an anchor existed, leaving a ghost); applied the unconditional `if let node` per the comment's stated intent ("node removal is unconditional"). (c) Discovered: the per-test `-only-testing:SkyPathTests/EarthFrameHierarchyTests/<method>` filter reports "Executed 0 tests" for Swift Testing tests in this toolchain — use the suite-level filter `-only-testing:SkyPathTests/EarthFrameHierarchyTests` instead. Device-only ACs (visual-unchanged, runtime under-root, orphan-free across a localized walk) pending on-device verification. |
| 2026-07-01 | M02.2 final holistic review → ready to merge (pending device ACs) | Final whole-feature review (Opus) against spec v2 §3/§8: spec-complete, all simulator-verifiable ACs covered by real (non-tautological) tests + clean build/test; invariant integrity confirmed (zero writes to `earthFrame.transform` in the diff); self-cleaning traced across every `session.run`/restart/failure path with no missed path; regression risk to existing geo/plane/mesh flows negligible (reparent under identity `earthFrame` preserves world transforms; no code iterates `sceneView.scene.rootNode.childNodes` or does root-relative hit-testing). **Verdict: ready to merge, pending device-only ACs.** Three Minor doc/clarity items deferred to the M02.7 doc pass (none affect correctness): (1) spec §3.5 slightly oversells the `didSet` — it fires on `earthFrame` property reassignment, not on in-place `earthFrame.simdTransform` mutation (the reparent-site asserts cover that gap); spec wording to be clarified in M02.7. (2) High-accuracy reload uses an inlined partial clear (`loadedLocations` + `anchorsFrame` children) instead of the shared `clearEarthFrameChildrenAndTracking()` helper — justified (occluders must persist across a geo reload); an optional `clearGeoAnchorChildren()` sibling would self-document. (3) `unloadModel`'s comment frames `didRemove` as "the authoritative cleaner," which is true for ARKit-initiated removals but not for `unloadModel`-initiated removals of placed models (where `session.remove` is skipped per the documented carry-over, so `didRemove` doesn't fire and the synchronous `node.removeFromParentNode()` is the cleaner); comment to be reworded in M02.7. |

