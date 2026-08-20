# earthFrame Node Hierarchy — Design Spec (M02.2)

> Status: Design approved 2026-06-30; revised v2 2026-07-01 after 5-agent adversarial scrutiny; pending implementation.
> Source plan: `docs/phases/Phase02_VPS_Grounded_Occluded_Plan.md` §M02.2 (items 2.3.1, 2.3.2, 2.3.3).
> Loose-ends ref: `docs/loose-ends-and-priorities.md` §2.3, §9 Track B item 6.
> Verification: 3-agent design-verification workflow (2026-06-30) + 5-agent spec-scrutiny workflow (2026-07-01). Findings folded in.
>
> **Changelog:**
> - 2026-06-30 v1: initial design + 3-agent verification (reparent-safe-under-identity; self-cleaning removal; test-import fix).
> - 2026-07-01 v2: scrutiny found missed removal paths (`viewWillAppear`, `startGeoTrackingSession`, LIDAR, `session(_:didFailWithError:)`), a partly-ineffective `unloadModel` edit, per-branch reparent insertion requirement, idempotency/re-entrancy guard, stronger invariant enforcement (`didSet` + pure validator), plan §5 contradiction flagged, AC verifiability split (simulator vs device), simulator proxy test, `-only-testing:SkyPathTests`, clean-build caveat, app-side file placement, race fix in high-accuracy reload.

## 1. Goal

Add a stable `earthFrame` SCNNode at the scene-graph root and reparent ARKit's per-anchor nodes into a named hierarchy beneath it, so that:

- M02.4 (Streetscape Geometry occluders) can parent occluder nodes under `earthFrame/occluders`.
- M02.5 (bounded reactive correction loop) has a single node (`earthFrame`) whose transform carries the EMA anti-slide correction for geo content.

`earthFrame.transform` is pinned to **identity** in this milestone. No correction is applied yet. Identity is chosen deliberately so the reparent is visually jump-free (world transform unchanged). Plan §4's ENU/ECEF seeding (`session.getGeoLocation(forPoint:)`, `GeoTransforms.swift`, `seededEarth`) and the "transform = ENU origin in ARKit world space" label are **deferred to M02.5** with the MERGED-005 transform spec.

## 2. Verification summary (what shaped the design)

**3-agent design verification (2026-06-30)** confirmed reparenting is safe under identity but surfaced: removal relies on undocumented ARKit behavior once reparented; the high-accuracy reload can orphan nodes; and the test target doesn't compile (`@testable import GeoTestARScene` while the module is `SkyPath`).

**5-agent spec scrutiny (2026-07-01)** reversed-engineered the full `ARViewController.swift` and empirically ran `xcodebuild test`. It found the v1 self-cleaning was incomplete (see §3.4), the `unloadModel` edit was partly a no-op (§3.4), the reparent must be inserted per-branch not trailing (§3.3), and split acceptance criteria into simulator-verifiable vs device-only (§8). It also confirmed: the app target is a synchronized-folder target (no pbxproj edit to add the factory file), `APIKeys.local.xcconfig` exists, `ENABLE_TESTABILITY=YES`, and — after the D5 import fix on a **clean** build — the host launches on the iPhone 17 simulator and Swift Testing tests pass. So AC5/AC6 are verifiable in this environment; AC2 and the runtime parts of AC1/AC4 require the user's device (ARGeoTrackingConfiguration is unsupported on simulator).

One scrutiny note: the v1 `@testable import` failure is only reproducible on a **clean** build (incremental builds reuse stale `.o` and silently succeed). AC5 verification must use a clean build.

## 3. Design

### 3.1 Hierarchy

```
sceneView.scene.rootNode
└── earthFrame                 (name "earth_frame", transform == identity, invariant-guarded)
    ├── earth_anchors          (name "earth_anchors")   ← reparented ARGeoAnchor nodes + content
    └── earth_occluders        (name "earth_occluders") ← reparented ARPlaneAnchor / ARMeshAnchor nodes
```

**Relationship to the plan's hierarchy.** Plan §4 specifies per-anchor named containers `earthFrame/anchors/<id>` and `earthFrame/occluders/<gar-geom-id>`, plus a third `earthFrame/freeContent/...` branch. This spec **substitutes direct reparent of the ARKit auto-managed node** for the per-anchor wrapper: the ARKit anchor node is itself the per-anchor container (it already carries that anchor's content), so wrapper nodes are redundant for M02.2. To preserve the plan's per-anchor addressability/debuggability, the reparent sets `node.name = anchor.identifier.uuidString` (§3.3). The plan's `earthFrame/freeContent` branch is **deferred** (§6) — no non-anchored content exists yet.

### 3.2 Pure, testable factory (idempotent)

A pure SceneKit type (no AR session, no UIKit) builds and names the hierarchy:

```swift
struct EarthFrameHierarchy {
    let earthFrame: SCNNode      // "earth_frame"
    let anchorsFrame: SCNNode    // "earth_anchors", child of earthFrame
    let occludersFrame: SCNNode  // "earth_occluders", child of earthFrame
    static func make() -> EarthFrameHierarchy
    /// Pure Bool check — unit-testable without trapping the process.
    static func isIdentity(_ earthFrame: SCNNode) -> Bool
    /// Asserts identity; called from the `earthFrame` `didSet`, reparent sites, and tests.
    /// No-op in Release; asserts on `isIdentity`.
    static func assertIdentity(_ earthFrame: SCNNode, file: StaticString = #file, line: UInt = #line)
}
```

All three nodes have identity transform. **File placement:** `EarthFrameHierarchy.swift` in the app source folder `GeoTestARScene/GeoTestARScene/`. The SkyPath app target is itself an Xcode 16 synchronized-folder target (`fileSystemSynchronizedGroups = GeoTestARScene`), so the file is auto-included with **no `project.pbxproj` edit** — same mechanism as the test target.

**Idempotency / re-entrancy:** `ARViewController` builds the hierarchy **once** (lazy property) and guards the root-add: `if earthFrame.parent == nil { sceneView.scene.rootNode.addChildNode(earthFrame) }`. `setupARView()` creates a fresh `ARSCNView` on every call, so without this guard a second setup would orphan a second hierarchy or re-parent the same node across scenes — exactly the ghost-node class D3 prevents.

### 3.3 Reparent in `renderer(_:didAdd:for:)` — per-branch, not trailing

`renderer(_:didAdd:for:)` has early `return`s at `:625` (plane), `:633` (mesh), and guard-returns at `:641` (non-geo/no-name) and `:660` (model not in cache / placeholder). There is **no single reachable trailing point**. Insert the reparent explicitly inside each branch:

- **Plane** (`ARPlaneAnchor`): `occludersFrame.addChildNode(node)` just before the `:625` return.
- **Mesh** (`ARMeshAnchor`): `occludersFrame.addChildNode(node)` just before the `:633` return.
- **Geo success** (`ARGeoAnchor` with cached model): `anchorsFrame.addChildNode(node)` after `:670`; set `node.name = geoAnchor.identifier.uuidString`.
- **Geo placeholder** (`:655-660`, model not in cache): reparent the placeholder node under `anchorsFrame` too (set `node.name`), so placeholders are tracked consistently. (Decision: placeholders live under `earth_anchors`.)

`addChildNode` auto-removes from the old parent; do **not** manually set `node.transform` — ARKit re-asserts the local transform next frame. Under identity `earthFrame`, world transform is unchanged across the reparent.

This deliberately deviates from Apple's `ARSCNViewDelegate` guidance ("add child content; don't reparent the auto-managed node"). Safe only under the identity invariant (§3.5). Documented and guarded.

### 3.4 Self-cleaning removal — one helper across ALL reset/restart/failure paths

Because reparenting makes ARKit auto-removal of reparented nodes undocumented/unreliable, **every** path that resets/restarts/fails the session must explicitly clear the earth frames and tracking dicts. v1 only covered the high-accuracy reload; scrutiny found the same risk at `viewWillAppear`, `startGeoTrackingSession`, the LIDAR branch, and `session(_:didFailWithError:)`.

Add one helper and call it from every reset site:

```swift
private func clearEarthFrameChildrenAndTracking() {
    anchorsFrame.childNodes.forEach { $0.removeFromParentNode() }
    occludersFrame.childNodes.forEach { $0.removeFromParentNode() }
    loadedLocations.removeAll()
    planeNodes.removeAll()
    meshNodes.removeAll()
    highAccuracyModelPlaced = false
    highAccuracyFrameCounter = 0
}
```

Call sites:
- **`viewWillAppear` (`:96-103`)** — before `sceneView.session.run(configuration)`. This fires on app launch **and on dismiss of the fullScreen Spike modal** (`:162-163`), which downgrades the session from Geo back to WorldTracking without `.removeExistingAnchors`. Without this clear, reparented geo content dangles as ghosts on Spike-return. (The parent `ViewController` tab-switch path is unaffected — it calls `pause/resumeARSession` directly, not `viewWillAppear`.)
- **`startGeoTrackingSession` (`:284`, `:288`)** and the **LIDAR-debug branch (`:257`)** — immediately before each `session.run(... .removeExistingAnchors)`. v1's defense-in-depth rationale applies identically here; trusting `didRemove` at the reload but not here was an internal inconsistency.
- **High-accuracy reload (`:946-950`)** — immediately after the `session.remove` loop and before placing the two closest models. **Race fix:** set `highAccuracyModelPlaced = true` **before** the remove loop (not at `:956`), so a concurrently-dispatched `updateNearbyModels` (main queue, `:407`) cannot pass the `:534` guard and re-add a node during the clear window. Add an in-code breadcrumb: `// MERGED-009: high-accuracy hard reset still exists; full redesign deferred — do not rely on this for drift correction`.
- **`session(_:didFailWithError:)` (`:840`)** — a failed session is non-recoverable; clear and require a fresh Start AR.
- **`sessionWasInterrupted`** — do **not** clear (interruption may resume); leave the graph intact.

**`renderer(_:didRemove:)` (`:822-834`)** — for every anchor type (geo, plane, mesh), call `node.removeFromParentNode()` in addition to the existing dictionary bookkeeping. `removeFromParentNode()` on an already-removed node is a no-op, so the per-node removal here and the `forEach` clear in the helper are intentionally idempotent; the `forEach` exists specifically for the async window where `didRemove` hasn't fired yet.

**`unloadModel(id:)` (`:734-743`)** — scrutiny found the v1 edit was partly a no-op: `didAdd` **overwrites** `loadedLocations[id]` with the bare `allLocations` entry at `:659`/`:674` (which has `.anchor == nil`), then sets `.node` at `:678-680`. So post-`didAdd`, `loadedLocations[id].anchor == nil` and `.node == ARKit anchor node`; `unloadModel` takes the `else if let node = location.node` branch and **never calls `session.remove`** for didAdd-processed models. This is a pre-existing bookkeeping bug. Resolution (minimal, no behavior change to placement): make `didRemove` the **authoritative cleaner** (it already removes the node per above) and have `unloadModel` call `session.remove(anchor)` when an anchor is known **plus** `node.removeFromParentNode()` unconditionally; document that the `anchor != nil` branch is a safety net for the narrow pre-`didAdd` window, not the primary path. Leave the deeper bookkeeping fix (preserve `.anchor` across the `didAdd` overwrite) as a noted carry-over; do **not** bundle it into M02.2.

### 3.5 Identity invariant — `didSet` + pure validator

`earthFrame` must remain identity until M02.5 ships a transform spec (MERGED-005). v1 used only a snapshot `assert`, which is a no-op in Release and unchecked mid-session. Stronger design:

- A `didSet` observer on the `earthFrame` property that calls `EarthFrameHierarchy.assertIdentity(earthFrame)` whenever the transform is set, gated by an `m02_5CorrectionEnabled` flag (default `false`). Continuous, debug+Release signal, and makes AC4 unit-testable.
- `EarthFrameHierarchy.assertIdentity(_:)` is a pure static func (`assert(earthFrame.simdTransform == matrix_identity_float4x4, ...)`) called by the `didSet`, the reparent sites, and a unit test. `SCNNode.simdTransform` is `simd_float4x4`; `matrix_identity_float4x4` is the same type; `float4x4` is `Equatable` — the comparison compiles.
- In Release, `assert` is a no-op but the `didSet` still fires (it is not guarded by `assert`); the flag is the real gate. Document that the invariant is enforced continuously via `didSet`, and that M02.5 flips the flag before assigning a non-identity transform.

### 3.6 Unused extension

`SCNNode.worldPosition` (`:1008-1015`) is unused. Add a doc comment: returns **world-space** position (valid as root-relative only while `earthFrame` is identity). Defer deletion to a separate cleanup.

## 4. Decisions (recorded for later tracing)

- **D1 — Reparent the ARKit auto-managed anchor nodes** under `earth_anchors` / `earth_occluders`, inserted **per-branch** (§3.3), with `node.name = anchor.identifier.uuidString`. Substitutes the plan's per-anchor wrapper containers (the ARKit node is itself the container); deviation acknowledged. Deviates from Apple guidance; safe under the identity invariant (D8).
- **D2 — Pin `earthFrame.transform` to identity for M02.2.** Plan §4 ENU/ECEF seeding deferred to M02.5. Identity chosen for jump-free reparent.
- **D3 — Uniform self-cleaning via one helper** (`clearEarthFrameChildrenAndTracking`) across **all** reset/restart/failure paths: `viewWillAppear`, `startGeoTrackingSession` (both branches), LIDAR branch, high-accuracy reload, `session(_:didFailWithError:)`; plus per-node `removeFromParentNode` in `didRemove`; plus `unloadModel` calls `session.remove` + unconditional `removeFromParentNode` with `didRemove` authoritative. Race fix: `highAccuracyModelPlaced = true` before the remove loop. In-scope because reparenting makes ARKit auto-removal undocumented.
- **D4 — Carry-over to M02.5: occluders must NOT receive the EMA correction.** Occluder (mesh/plane, later Streetscape) anchors live in the **raw ARKit/camera world frame**. This **contradicts plan §5** ("Putting occluders under earthFrame" → "occluders and content move together — they stay aligned"), which is **incorrect**: a corrected `earthFrame` would shift occluders out of the camera frame and break real-world occlusion. **Plan §5 is flagged for correction in the M02.7 documentation pass.** Options for M02.5 (decision deferred to the MERGED-005 transform spec):
  1. Keep `earthFrame` fixed at identity after seeding; apply correction elsewhere (MERGED-011 action (a)).
  2. Move occluders to a separate identity `occluderFrame` under root; only geo content under a corrected `earthFrame`.
  3. Don't reparent ARKit nodes under a non-identity parent — keep them under root per Apple guidance; apply EMA to a **child content node** under each geo anchor (ARKit overwrites only the anchor node's own transform, never children's). Avoids double-application and `transform`-vs-`worldTransform` pitfalls. (Cleanest per 2026-06-30 reparent-semantics review.)
  4. Per-frame convert `geom.meshTransform` to earthFrame-local (MERGED-011 action (b)) — bake the inverse correction into each occluder's transform each frame.
  Current M02.2 structure (`earth_occluders` under `earthFrame`) is valid **only** while `earthFrame` is identity (D2).
- **D5 — Fix the test-target import.** `GeoTestARSceneTests.swift:9` `@testable import GeoTestARScene` → `@testable import SkyPath`. Prerequisite for any unit test. Failure is only reproducible on a **clean** build. No `project.pbxproj` edit (synchronized folders).
- **D6 — Tests use Swift Testing** (`import Testing`, `@Test`, `#expect`) in a new `EarthFrameHierarchyTests.swift` in `GeoTestARSceneTests/`. Run with `-only-testing:SkyPathTests` to avoid coupling to the UITests target's stale `TEST_TARGET_NAME = GeoTestARScene`.
- **D7 — Idempotent earthFrame creation.** Build once (lazy); guard root-add with `if earthFrame.parent == nil`. Prevents ghost hierarchies on re-setup.
- **D8 — Invariant via `didSet` + pure validator.** `EarthFrameHierarchy.assertIdentity(_:)` called from a `didSet` on `earthFrame` (gated by `m02_5CorrectionEnabled`), the reparent sites, and a unit test. Continuous signal; makes AC4 unit-testable.
- **D9 — AC verifiability split.** Structure/factory/invariant tests are simulator-verifiable (Claude here). Visual-unchanged and runtime-under-root claims are device-only (ARGeoTracking unsupported on simulator). A simulator-inferable proxy test (worldTransform-preservation across reparent) covers the math behind "visually unchanged" (§5).
- **D10 — Stale `GeoTestARScene.xcodeproj/` (MERGED-028) is unrelated to M02.2.** Verified it does not affect `xcodebuild -project SkyPath.xcodeproj` build/test. Left to Track-B cleanup; not a prerequisite.

## 5. Testing (TDD)

Pure-SceneKit tests in `GeoTestARSceneTests/EarthFrameHierarchyTests.swift` (Swift Testing), all simulator-runnable:

- `EarthFrameHierarchy.make()` returns three non-nil nodes named `"earth_frame"`, `"earth_anchors"`, `"earth_occluders"`.
- `anchorsFrame` and `occludersFrame` are children of `earthFrame`; `earthFrame` has exactly two children.
- All three `simdTransform == matrix_identity_float4x4`.
- **Invariant (AC4):** `EarthFrameHierarchy.isIdentity(_)` returns `true` for a fresh hierarchy and `false` after setting `earthFrame.simdTransform` to non-identity (exercises the detection logic without trapping; `assertIdentity` is the thin assert wrapper over `isIdentity`).
- **Reparent math (AC2 proxy):** create a parent with identity transform, a child with a known transform; record `child.worldTransform`; reparent child under the identity parent; assert `worldTransform` is unchanged across the reparent. Unit-verifies the mathematical basis of "visually unchanged" without ARKit.

Run (clean build; pinned destination):

```
xcodebuild clean build-for-testing \
  -project GeoTestARScene/SkyPath.xcodeproj -scheme GeoTestARScene \
  -destination 'platform=iOS Simulator,id=B2A25A43-FBCD-4B24-97EC-9EE7E0E82CE3' \
  -only-testing:SkyPathTests
xcodebuild test-without-building \
  -project GeoTestARScene/SkyPath.xcodeproj -scheme GeoTestARScene \
  -destination 'platform=iOS Simulator,id=B2A25A43-FBCD-4B24-97EC-9EE7E0E82CE3' \
  -only-testing:SkyPathTests
```

Empirically confirmed (2026-07-01): the host `SkyPath.app` launches on the iPhone 17 simulator (OS 26.5) — ARKit isn't touched fatally at launch because `viewWillAppear` runs `ARWorldTrackingConfiguration` (simulator-supported), and `ARGeoTrackingConfiguration` sits behind the user-initiated Start flow guarded by `isSupported`. The WKWebView/Cesium stack (`LocationsViewController`) is not instantiated at launch. So pure-SceneKit tests run without device hardware. The §7 "simulator launch may stall" risk is downgraded to a non-issue.

The ARViewController integration (reparent + self-cleaning across all reset sites) needs a live ARGeo session and is **device-verified** (M02.2 baseline boot note); the factory extraction + validator are what make the structural logic unit-testable here.

## 6. Out of scope (carry-overs)

- Streetscape Geometry occluders (M02.4) — `earth_occluders` is ready for them.
- EMA correction loop + the MERGED-005 transform spec (M02.5) — gated by D2/D4/D8's flag.
- Plan §4 ENU/ECEF seeding + `seededEarth` (M02.5).
- Plan's `earthFrame/freeContent` branch (deferred until non-anchored content exists).
- CoreMotion stillness detector (M02.5).
- Occluder material `readsFromDepthBuffer` (MERGED-020).
- The deeper MERGED-009 redesign (should the high-accuracy hard reset exist?) — this spec only prevents it from orphaning reparented nodes and leaves a code breadcrumb; it does **not** redesign the reset.
- The `unloadModel`/`didAdd` anchor-bookkeeping bug (preserve `.anchor` across the `didAdd` overwrite) — noted carry-over, not bundled.
- Deleting `SCNNode.worldPosition` (only doc-commented here).
- Stale `GeoTestARScene.xcodeproj/` removal (Track-B cleanup, MERGED-028; unrelated to M02.2).
- **Plan item 2.3.3 (remove `setWorldOrigin` calls): N/A — none exist in `ARViewController.swift` (verified).**

## 7. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Silent drift if `earthFrame` ever gets a transform | `didSet` + `assertIdentity` validator, flag-gated (D8); continuous, not snapshot |
| Reparented nodes not auto-removed by ARKit | Uniform `clearEarthFrameChildrenAndTracking` on all reset/restart/failure paths + per-node `removeFromParentNode` in `didRemove` (D3) |
| `viewWillAppear` modal-dismiss orphans | Helper called in `viewWillAppear` before `session.run` (D3) |
| High-accuracy reload race with proximity loop | `highAccuracyModelPlaced = true` before remove loop (D3) |
| `unloadModel` no-op / `session.remove` not called | `didRemove` authoritative; `unloadModel` calls `session.remove` when anchor known + unconditional `removeFromParentNode` (D3) |
| Apple guidance violation | Documented deviation; safe under identity invariant |
| M02.5 occluder misalignment if structure unchanged | D4 carry-over + plan §5 flagged for correction; structure revisited before lifting identity |
| Double-removal reads as dead code | Documented idempotent (§3.4) |
| Re-entrant `setupARView` creates ghost hierarchy | Idempotent creation + `parent == nil` guard (D7) |
| AC2/AC1-runtime/AC4-runtime need a device | D9 split; simulator proxy test for the math; device verification noted |
| Test import bug masked by warm DerivedData | Clean-build requirement in §5 (D5) |

## 8. Acceptance criteria

**Simulator-verifiable (Claude, here):**
1. `EarthFrameHierarchy.make()` produces the named, identity-transform, two-child hierarchy (unit test).
2. (Proxy for visual-unchanged) reparenting a node under an identity-transformed parent preserves `worldTransform` (unit test).
3. `EarthFrameHierarchy.assertIdentity` traps/flags on a non-identity `earthFrame` (unit test; AC4).
4. `GeoTestARSceneTests` target compiles on a **clean** build (D5 import fix) and `EarthFrameHierarchyTests` passes via `-only-testing:SkyPathTests` on the simulator (AC5).
5. `SkyPath.xcodeproj` builds with no missing-file errors (AC6).

**Device-only (user):**
6. Geo anchor nodes render under `earth_anchors`; plane/mesh occluders under `earth_occluders`; rendering visually unchanged from pre-change (ARGeoTracking needs a device).
7. `earthFrame` exists as a child of `sceneView.scene.rootNode` at runtime; `didSet`/validator does not fire during a normal localized session.
8. No orphaned nodes after: Spike-modal dismiss, Start AR restart, LIDAR toggle, high-accuracy reload, and a session-failure simulation — across a localized walk.

**Audited-clear (recorded, no action):**
9. `setWorldOrigin` plan item 2.3.3 is N/A (verified absent).
10. MERGED-009 in-code breadcrumb present at the high-accuracy reload site.

## 9. Audited-clear paths (verified safe under reparenting, no change needed)

Recorded so reviewers know these were checked by the 2026-07-01 code-path audit:

- **Spike paths isolated:** SpikeA/B/C each use their own `ARSCNView` and session; their `rootNode.addChildNode` calls (SpikeB `:302`, `:405`) touch their own scenes, not `ARViewController`'s. `spikeButton` is a UIKit button. The only interaction is modal present/dismiss → `viewWillAppear` (covered by D3).
- **`sceneView.scene` persists** across every `session.run` (created once in `setupARView` `:329`, never replaced), so `earthFrame` added once persists.
- **Tracking dicts don't assume parent==root:** `modelCache` holds off-scene templates (`.clone()` only); `loadedLocations[id].node` is the ARKit anchor node itself; `planeNodes`/`meshNodes` map anchor UUID → child content node. All valid after reparenting.
- **`viewWillDisappear` (`:166`)** → `pauseARSession` → `session.pause()` preserves anchors/nodes (no removal, no orphan).
- **`deinit` (`:179`)** removes only notification observers; ARC tears down the whole scene graph including `earthFrame` — no earthFrame-specific cleanup needed.
- **`orientationDidChange` (`:184`), `clearSessionState` (`:524`), `focusOnLocation` (`:746`)** perform no node removal; `focusOnLocation`'s pulse `SCNAction` is parent-agnostic.
- **No code** iterates `sceneView.scene.rootNode.childNodes`, does root-relative `hitTest`/`convertPosition`, or `enumerateChildNodes` from root (grep-confirmed). The `:482` `rootNode` is the cached model `SCNScene`'s own root, unrelated.