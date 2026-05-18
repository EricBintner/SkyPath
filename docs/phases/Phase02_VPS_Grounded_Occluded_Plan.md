# Phase 02 — VPS-Grounded, Architecturally-Occluded AR

> **TL;DR.** Run Apple ARKit `ARGeoTrackingConfiguration` as the primary geo-pose source. Run ARCore `GARSession` in parallel — not for pose, but to get **Streetscape Geometry** building meshes, which feed a SceneKit depth-only occlusion pass. Park all geo-content under one `earthFrame` SCNNode that receives **bounded, stillness-gated EMA corrections** rather than abrupt `setWorldOrigin` resets. Load models at runtime via **GLTFKit2** from the webgl submodule.

This phase produces a build that (a) does not slide noticeably while a user walks an NYC block and (b) occludes virtual content behind real buildings within ~80% of visible facades. No Metal renderer. No `cesium-native`. No Photorealistic 3D Tiles on-device.

> **Conditionality.** The "Apple primary + Google for meshes" pose stack (§3) and the "SceneKit depth-only material" renderer choice (§5) are first-principles engineering, not validated by a shipping reference app for this specific combination. They are gated on M02.0 spike outcomes (§7). Fallback paths are documented.

---

## 0. Scope and architectural ground rules

### Scope discipline — AR screen only

All work in this plan touches the **AR screen surface only**: `ARViewController.swift`, models the AR code consumes, AR-specific feature flags, AR HUD overlays, the build phase that copies shared data into the iOS bundle, and docs.

**Out of scope unless explicitly asked**: `MapViewController.swift`, `LocationsViewController.swift` and any WebView/Vercel wiring, `InfoViewController.swift`, `AppDelegate` / `SceneDelegate`, top-level navigation, anything inside the `webgl-component/` submodule. The Map and WebView work today and must not regress because of AR rebuild work.

This is also recorded in `AGENTS.md` at the repo root.

### Shared data — single source of truth

The webgl submodule is canonical for **both** the `.glb` model binaries and the geospatial placement JSON. iOS consumes copies via a build phase. There are not two parallel copies of the same data to keep in sync — there is one, in the webgl repo, and iOS bumps a submodule commit to pick up changes. See §6 for the current state, the open reconciliation questions (the iOS and webgl `models_to_place.json` files have already drifted), and the build-phase mechanism.

### What this plan does not commit to until the spike resolves

- **Whether `ARGeoTrackingConfiguration` and `GARSession` can run together on iOS.** Google's iOS samples pair `GARSession` with `ARWorldTrackingConfiguration`. The combination we want is plausible but not documented.
- **Whether SceneKit + Streetscape Geometry as depth-only occluder gives clean results at 50–100 m range**, or whether RealityKit's `OcclusionMaterial` is the cleaner path.

Both are M02.0 deliverables.

---

## 1. Success criteria (acceptance tests)

The build is "Phase 02 done" when all four pass on a single test device on a documented NYC block:

| # | Test | Threshold |
|---|---|---|
| **AC-0** | iOS reads its placement data from the canonical JSON copied out of `webgl-component/` via the build phase — not from a separate iOS-side file. Both the iOS app and the webgl viewer render the same model variants at the same coordinates. | No divergence. |
| **AC-1** | Place 3 ARGeoAnchored objects from the canonical placement JSON. Walk 50 m of the block forward, return, place a fresh checkpoint anchor, measure displacement of original anchors at their nominal latitude/longitude. | Lateral drift ≤ **1.0 m** |
| **AC-2** | Stand still at a documented spot. Look down a street with tall buildings on both sides. Slowly pan left↔right 90°. | Yaw error of placed anchors ≤ **3°** measured against a reference compass post. |
| **AC-3** | Place content behind a building facade. Move so the facade is between camera and content. | Content correctly hidden for ≥ **80%** of facade pixel area. |
| **AC-4** | 5-minute continuous walk-and-return loop. No reset/restart. | No user-visible "jump" > 30 cm or > 5° yaw at any moment. |

If any test fails by a wide margin, we revisit the architecture before patching. Small failures get logged into Phase 03 backlog.

---

## 2. Architecture overview

```
                  ┌──────────────────────────────────────────────────┐
                  │ ARMetalViewController-style host (KEEP SceneKit) │
                  │                                                  │
                  │  ARSCNView (ARGeoTrackingConfiguration primary)  │
                  │     ├─ ARSession  →  GARSession  (frame-fed)     │
                  │     │     │             │                        │
                  │     │     │             ├─ Streetscape Geometry  │
                  │     │     │             │   (building meshes)    │
                  │     │     │             └─ Geospatial pose       │
                  │     │     │                 (used as cross-check │
                  │     │     │                  only, NOT primary)  │
                  │     │     └─ ARGeoAnchor[]                       │
                  │     │                                            │
                  │     └─ Scene graph                                │
                  │            └─ earthFrame SCNNode  ← bounded      │
                  │                  ├─ Occluders  (depth-only mat)  │
                  │                  └─ Content    (glb via GLTFKit2)│
                  └──────────────────────────────────────────────────┘
```

Three independent loops drive this:

1. **Pose loop** (per ARSession frame, 60 Hz). Drains `ARSessionDelegate` updates; pushes the same frame into `GARSession.update(_:error:)` so Google can also localize. No pose decisions yet.
2. **Occlusion loop** (per frame, throttled to ~10 Hz). Reads `GARSession.streetscapeGeometries`; diffs against last snapshot; creates/updates/removes occluder `SCNNode`s under `earthFrame`. Throttled because mesh rebuilds are expensive.
3. **Correction loop** (event-driven, mostly idle). Watches for `ARGeoAnchor.transform` deltas, IMU stillness, and yaw-uncertainty signals from both pose systems. Applies bounded EMA adjustments to `earthFrame.transform`.

---

## 3. Pose strategy — "Apple primary, Google sanity-check" (gated on Spike A)

> **Status.** This is the target pose stack. It is **conditional on Spike A in M02.0** confirming that `ARGeoTrackingConfiguration` and `GARSession` can coexist on iOS. Google's public iOS samples pair `GARSession` only with `ARWorldTrackingConfiguration`; the combination we want is not documented as supported or unsupported. If Spike A shows it doesn't work, the fallback (described at the end of this section) is `ARWorldTrackingConfiguration` + ARCore Geospatial pose as primary.

### Why hybrid

| Source | Strength | Weakness |
|---|---|---|
| ARKit `ARGeoTrackingConfiguration` | Dense Look Around coverage in NYC; ARKit-native (no extra dep); axes ENU-aligned automatically; tight ARGeoAnchor updates flow back into the scene graph | Status enum only (`.high` / `.medium` / `.low`) — no numeric uncertainty; degrades silently in re-localization windows |
| ARCore `GARSession` Geospatial | Numeric `orientationYawAccuracy` and `horizontalAccuracy` exposed; Streetscape Geometry meshes; global coverage | Typical ~5 m / 5° accuracy; adds CocoaPods/SPM dependency; Google billing kicks in past free quota; runs on top of an ARSession anyway |
| Niantic Lightship | Crowdsourced VPS, strong NYC, well-engineered pose graph + hierarchical map cache | Yet another SDK; coverage skewed to Niantic POIs; recommendation: not in Phase 02 |

**Decision**: ARKit drives the pose. We start `ARGeoTrackingConfiguration` (not `ARWorldTrackingConfiguration`) and read `ARGeoTrackingStatus.accuracy`. GARSession runs in parallel only to give us `streetscapeGeometries` and a numeric yaw-uncertainty signal we use as a *gate* for when bounded corrections may be applied — it is **not** the source of placement transforms.

### Sequencing on session start

```
viewDidAppear
   → start ARSession with ARGeoTrackingConfiguration (worldAlignment = .gravityAndHeading)
   → start GARSession(apiKey:bundleIdentifier:) with
        config.geospatialMode = .enabled
        config.streetscapeGeometryMode = .enabled
   → HUD: "Look around to localize" until ARGeoTrackingStatus.state == .localized
   → Gate content placement on: state == .localized && accuracy ∈ {.medium, .high}
```

Apple sample code and the WWDC 2020 session 10611 walk-through document this lifecycle ([Apple — Tracking geographic locations in AR](https://developer.apple.com/documentation/arkit/tracking-geographic-locations-in-ar)).

### Why we don't use Google Geospatial Anchors

Geospatial Anchors (`GARAnchor` of type WGS84/Terrain/Rooftop) give us nothing ARGeoAnchor doesn't already give us in NYC, and they require server resolution (asynchronous, returns `GARFutureState`). Apple's geo-anchors are synchronous, automatically tracked, and update their transforms on the ARSession delegate. We use Apple anchors. Period.

We **do** use Streetscape Geometry. See §5.

### Fallback if Spike A fails

If `GARSession` cannot run alongside `ARGeoTrackingConfiguration`:

1. Switch the ARSession to `ARWorldTrackingConfiguration` (no Apple geo).
2. Use `GARSession`'s `earth.cameraGeospatialTransform` as the only absolute pose.
3. Place content via `GARAnchor` of type `Rooftop` or `Terrain` instead of `ARGeoAnchor`.
4. Lose Apple's tight geo-anchor delegate updates; gain Google's numeric accuracy fields and reach.
5. The anti-sliding architecture (§4) is unchanged — `earthFrame` still absorbs correction. The source of corrections becomes Google's `GARGeospatialTransform` updates instead of Apple's anchor delegates.

This is what Google's official iOS samples do today. It is a worse fit for NYC (Apple's Look Around coverage is denser than ARCore's NYC coverage in our experience), but it is a complete and working architecture.

---

## 4. Anti-sliding — the bounded reactive correction pattern

This is the core engineering problem. Apple's `ARGeoAnchor` does its own correction internally (it updates anchor transforms via the delegate as VPS refines pose), but the prior build still slid because:

- Content was attached to a global frame whose transform could shift along with the underlying anchors, creating visual drift relative to the world.
- ARKit's yaw drift accumulates and Apple's geo refinements snap rather than smooth.
- Placements done before `.localized` inherit pose errors that propagate forever.

The fix is a **single intermediate frame** that absorbs all earth-↔-AR mismatch, with corrections applied as bounded, low-frequency, stillness-gated nudges.

### `earthFrame` — the load-bearing SCNNode

Every geo-anchored model and every occluder is parented under one node:

```
sceneView.scene.rootNode
    └── earthFrame  (transform = ENU origin in ARKit world space)
         ├── earthFrame/anchors/<id>  (one per ARGeoAnchor; updated by delegate)
         ├── earthFrame/occluders/<gar-geom-id>  (Streetscape Geometry meshes)
         └── earthFrame/freeContent/...
```

`earthFrame.transform` is the **only** thing the correction loop ever touches. We do **not** call `session.setWorldOrigin(...)` after the initial seed — that's a hard reset and it jumps.

### Seeding `earthFrame` (one-time, on first `.localized`+`.high|.medium`)

1. Wait for `ARGeoTrackingStatus.state == .localized` AND `accuracy ∈ {.high, .medium}`.
2. Get current camera position and the corresponding lat/lon/alt via `session.getGeoLocation(forPoint:)`.
3. Compute ECEF→ENU transform at that lat/lon (the `GeoTransforms.swift` math from the Metal track is reusable here — pure math, no Cesium dependency).
4. Set `earthFrame.transform` so that the ENU origin sits at the camera's current position.
5. Persist `seededEarth = true`. No further seeding for this session.

### Per-frame correction (event-driven, throttled)

Every time ARKit hands us an updated `ARGeoAnchor.transform` (via `session(_:didUpdate:)`):

1. Compute the implied earth→AR transform from this single anchor: `T_implied = anchor.transform × ENU_at_anchor⁻¹`.
2. Compute residual: `Δ = T_implied × earthFrame.transform⁻¹` (small rotation + small translation).
3. Apply a fraction (EMA `α`, e.g. 0.05) of `Δ` to `earthFrame.transform`. Clamp to:
   - `|Δyaw|` per update ≤ 0.5°
   - `|Δxy|` per update ≤ 5 cm
   - `|Δz|` per update ≤ 5 cm
4. **Gate** the update: only apply if
   - GARSession yaw uncertainty < 5° (we trust the geo pose right now), AND
   - IMU stillness detector says user is roughly stationary (`device motion magnitude < 0.05 m/s² for 0.5 s`), OR
   - `accuracy == .high` (Apple's own confidence signal).

This is the standard pattern in production outdoor-AR products — bounded reactive correction with stillness gating. It is what Niantic does (smoothed pose-graph updates during stationary moments) and what Apple Maps' AR walking mode does internally.

### IMU stillness detection

```swift
// Pseudocode — single-source-of-truth in ARViewController.swift
let mag = simd_length(deviceMotion.userAcceleration)
let stillSamples = (mag < 0.05) ? stillSamples + 1 : 0
let isStill = stillSamples >= 30  // ~0.5 s at 60 Hz
```

### Why this avoids the "sliding" we saw before

- Content is attached to a node we control, not to ARKit's world origin.
- Corrections are *bounded* per update — even a 30° actual geo correction trickles in at ≤0.5°/update; over a few seconds of stillness the residual is absorbed without a visible jump.
- During motion, no corrections fire; visual drift is masked by the user's own motion (small misalignments are imperceptible while walking).
- The single point of authority for earth↔AR is `earthFrame.transform`. There is no second coordinate system we're cross-referencing.

---

## 5. Architectural occlusion — Streetscape Geometry, renderer TBD by Spike B

> **Status.** The occlusion *source* (Streetscape Geometry meshes from `GARSession`) is decided. The *renderer* that consumes those meshes — SceneKit with a depth-only `SCNMaterial` vs RealityKit with `OcclusionMaterial` — is **conditional on Spike B in M02.0**. We have strong reference impls for each component individually (SceneKit depth-only material: documented; LiDAR-mesh occlusion via this pattern: [haris008/SceneKit-Occlusion](https://github.com/haris008/SceneKit-Occlusion)); we do not have a public shipping reference for *this exact composition* (Streetscape Geometry → SCNGeometry → depth-only occluder at 50–100 m range). Spike B closes that gap with a controlled experiment.

### Why Streetscape Geometry

| Option | Coverage in NYC | Mesh fidelity | iOS support | Effort |
|---|---|---|---|---|
| **Streetscape Geometry (Google)** | Full | LOD2 buildings (roofs match shape, chimneys may poke out) | Yes ([iOS guide](https://developers.google.com/ar/develop/ios/geospatial/streetscape-geometry)) | Low — meshes arrive as ready-to-render vertex/index buffers |
| ARKit `ARMeshAnchor` (LiDAR) | LiDAR devices only; close-range | Highly accurate within ~10 m | Yes | Low for close-range, useless beyond LiDAR range |
| Photoreal 3D Tiles via cesium-native | Full | Photorealistic | Possible but punishing (we tried) | High — abandoned in prior phase |
| Manual OSM/CityGML import | Manual upkeep | Whatever you ingest | Yes | High and drifts over time |

**Decision**: Streetscape Geometry. Optionally augment with LiDAR mesh at close range in a later phase.

> Note: **Geospatial Depth API is Android-only** ([Google docs](https://developers.google.com/ar/develop/depth)). We render depth ourselves from the Streetscape mesh, which is the next-best thing.

### Conversion: GARStreetscapeGeometry → SCNNode

`GARStreetscapeGeometry` exposes `.mesh` (vertex + index buffers) and `.meshTransform` (origin transform). The mesh is in a local space; the transform places it in the session's world. Conversion is mechanical:

```swift
func makeOccluderNode(_ geom: GARStreetscapeGeometry) -> SCNNode {
    let mesh = geom.mesh
    let positionSource = SCNGeometrySource(vertices: mesh.vertices)
    let element = SCNGeometryElement(indices: mesh.triangleIndices,
                                     primitiveType: .triangles)
    let scnGeom = SCNGeometry(sources: [positionSource], elements: [element])

    let mat = SCNMaterial()
    mat.writesToDepthBuffer = true
    mat.colorBufferWriteMask = []       // <- depth only, no color
    mat.readsFromDepthBuffer = true
    mat.isDoubleSided = false
    scnGeom.materials = [mat]

    let node = SCNNode(geometry: scnGeom)
    node.simdTransform = geom.meshTransform   // <- placed in session world
    node.renderingOrder = -1                  // <- draw BEFORE content
    return node
}
```

This is the documented SceneKit "invisible occluder" pattern ([Apple — writesToDepthBuffer](https://developer.apple.com/documentation/scenekit/scnmaterial/writestodepthbuffer)). Virtual objects behind these meshes get correctly depth-tested away; the camera image shows through.

### Lifecycle

`GARSession` exposes a delegate-style `streetscapeGeometries` collection on each frame. We track which ones we already have nodes for by `GARStreetscapeGeometry.identifier`:

- **New geometry** (id not seen): build node, parent to `earthFrame/occluders`.
- **Updated geometry** (mesh changed): rebuild SCNGeometry (vertex source + element); keep node identity.
- **Tracking lost**: remove node from scene graph.

Throttle: never rebuild a mesh more than 4× per second per geometry. The meshes are stable; rapid rebuilds are a sign of jitter, not refinement.

### Putting occluders under `earthFrame`

The Streetscape meshes come in **ARSession world space**, which (after our seed) coincides with `earthFrame`'s frame. They go directly under `earthFrame/occluders/`. When `earthFrame.transform` is corrected (§4), occluders and content move together — they stay aligned.

---

## 6. Shared data pipeline — webgl submodule is the single source of truth

### Goal

Both the iOS app and the webgl viewer consume the **same** 3D model binaries and the **same** geospatial placement JSON. Drift between the two platforms becomes structurally impossible because there is only one canonical copy.

### Current state — drift already happened

Eight placement-data files exist across the two repos as of the start of Phase 02. The two `models_to_place.json` files (one in `GeoTestARScene/GeoTestARScene/`, one in `webgl-component/`) share schema and IDs but disagree on `model_variant` (iOS says `skypath_01`, webgl says `skypath_02` at the same `6thAve_W58th_Model` ID). Other variants (`models_to_place copy.json`, `skypath_locations_green.json`, `skypath_locations_original 2.json`, etc.) are likely stale.

**Open reconciliation questions** (defer to the user — do not edit JSON files without explicit ask):
1. For each `id` in the canonical `models_to_place.json`, which `model_variant` is correct — `skypath_01`, `skypath_02`, or something else?
2. Which of the variant files (`models_to_place copy.json`, `models_to_place_copied.json`, `skypath_locations*.json`, `skypath_tour_full_corrected.json`) is real vs stale?
3. Are `skypath_locations.json` and `models_to_place.json` consumed for different purposes (different schemas), or is one legacy?

These are resolved in the `cesium-google-3dtiles` repo first, then iOS picks up the change via submodule bump.

### Architecture

```
webgl-component/                         ← submodule, single source of truth
├── models_to_place.json                 ← canonical placement
├── skypath_models/
│   ├── skypath_01.glb
│   ├── skypath_02.glb
│   ├── skypath_column.glb
│   └── duck.glb
└── … (web viewer code unrelated to AR)

GeoTestARScene/  Build Phase  →  Models/  (in the iOS bundle)
                                 ├── models_to_place.json   (copied)
                                 ├── skypath_01.glb         (copied)
                                 └── …

iOS runtime:
    let modelsDir = Bundle.main.bundleURL.appendingPathComponent("Models")
    let placements = try JSONDecoder().decode([Placement].self,
        from: Data(contentsOf: modelsDir.appendingPathComponent("models_to_place.json")))
    // Each placement.model_variant → "<modelsDir>/<model_variant>.glb"
```

Both files (`.glb` and `.json`) are gitignored at the iOS project root — the iOS repo never carries its own copy of either. The build phase copies them in fresh on every build.

### Build phase script

```bash
# Build phase: "Copy shared data from webgl submodule"
set -e
SRC="${SRCROOT}/../webgl-component"
DST="${BUILT_PRODUCTS_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/Models"
mkdir -p "$DST"
cp "$SRC/models_to_place.json" "$DST/"
cp -R "$SRC/skypath_models/"*.glb "$DST/"
```

Add as a Run Script phase in the `GeoTestARScene` target, **before** "Copy Bundle Resources." Fail the build if the submodule isn't initialized (the `set -e` and `cp` will fail loudly if `models_to_place.json` isn't there).

### Loader: GLTFKit2

[GLTFKit2 (warrenm, MIT)](https://github.com/warrenm/GLTFKit2) is the actively-maintained Objective-C / Swift glTF 2.0 loader. SwiftPM-installable. Conversion path: `GLTFAsset → SCNScene` via `+[SCNScene sceneWithGLTFAsset:]` (SceneKit path; equivalent paths exist for Metal and RealityKit if Spike B selects RealityKit).

### Loader: GLTFKit2

[GLTFKit2 (warrenm, MIT)](https://github.com/warrenm/GLTFKit2) is the actively-maintained Objective-C / Swift glTF 2.0 loader. It builds as an XCFramework or via Swift Package Manager. Conversion path: `GLTFAsset → SCNScene` via `+[SCNScene sceneWithGLTFAsset:]`.

```swift
// Async load, callback-style
GLTFAsset.load(with: glbURL, options: [:]) { [weak self] progress, status, asset, error, _ in
    guard status == .complete, let asset = asset else { return }
    let scnScene = SCNScene(gltfAsset: asset)
    let modelNode = scnScene.rootNode.clone()
    DispatchQueue.main.async {
        self?.attach(modelNode, for: locationID)
    }
}
```

The Khronos open-source glTF Viewer iOS app uses exactly this stack (SceneKit + GLTFKit2 + DracoSwift + libktx) — there's a real production reference here.

### Loader changes from the prior SceneKit baseline

The pre-Metal baseline loaded `*.usdz` directly via SceneKit. Phase 02 swaps that for the GLTFKit2 path. Concrete changes:

- `Models.swift` parsing of `models_to_place.json`: the field name `model_variant` already holds a logical name like `"skypath_01"`. Remove any `.usdz` suffix assumption in the loader; resolve to `<modelsDir>/<model_variant>.glb` instead.
- Loader call sites switch from `SCNScene(named:)` / `SCNReferenceNode` to `GLTFAsset.load(with: url, options:)` + `SCNScene.sceneWithGLTFAsset:`.
- USDZ-specific code paths (Reality Composer authoring, USDZ archives) are removed.

---

## 7. Implementation milestones

Each milestone is ~1-3 days of focused work and has an explicit exit criterion. Land them sequentially. M02.0 is non-negotiable — its outcomes decide whether §3 and §5 stand or pivot to their fallbacks.

### M02.0 — Feasibility spike (~2 days, throwaway code on a separate branch)

The plan over §3 and §5 contains two first-principles claims that have no public shipping reference. M02.0 closes those gaps before the rest of the work runs.

**Spike A — Pose stack coexistence.** Highest-risk unknown. ~half day.
- Build a minimal view controller. Start an `ARSession` with `ARGeoTrackingConfiguration` (`worldAlignment = .gravityAndHeading`). Initialize a `GARSession` with API key + bundle id. Feed each `ARFrame` to `GARSession.update(_:error:)`. Enable `GARGeospatialModeEnabled` + `GARStreetscapeGeometryModeEnabled`.
- **Pass criteria**: both sessions reach localized state within 60 s outdoors; both expose valid transforms each frame; no exceptions thrown; `streetscapeGeometries` becomes non-empty.
- **Fail action**: switch the ARSession to `ARWorldTrackingConfiguration`; adopt the fallback architecture documented in §3. Re-test in the same spike branch.

**Spike B — Renderer bake-off.** ~1 day.
- Two ~200-line throwaway view controllers, both consuming the same captured `GARStreetscapeGeometry.mesh` data (capture once from Spike A and replay):
  - **SceneKit variant**: `ARSCNView` + `SCNGeometry` with `SCNMaterial.writesToDepthBuffer = true`, `colorBufferWriteMask = []`, `readsFromDepthBuffer = true`, `renderingOrder = -1`. Place a debug magenta cube 60 m behind a building.
  - **RealityKit variant**: `ARView` + `MeshResource` with `OcclusionMaterial()`. Same debug cube setup.
- **Measure**:
  - Does occlusion render correctly at 50 m, 80 m, 120 m camera-to-occluder distance?
  - Z-fighting / acne at building edges?
  - FPS with 20 occluder meshes simultaneously?
  - Lines of code to wire each path (proxy for ongoing maintenance cost).
- **Pass criteria**: at least one renderer occludes cleanly at all three distances at ≥ 30 FPS with no visible artifacts.
- **Pick the winner**: whichever wins on correctness first, FPS second, code-complexity tiebreaker. Write the decision (with the measured numbers) into `docs/phases/Phase02_Spike_Results.md`.
- **Fail action**: if neither works at distance, depth precision is the issue — investigate `SCNCamera.zNear/zFar` tuning or RealityKit camera bounds before retrying. If still failing, escalate: the occlusion architecture itself needs rework before continuing.

**Spike C — Sliding baseline capture.** ~half day.
- Take the unchanged SceneKit baseline from the M02.1 starting point. Run it on a documented NYC block. Place three test anchors. Walk 50 m, return. Record video + OSLog + accelerometer trace. Mark drift at fixed visual checkpoints.
- **Output**: a `docs/phases/Phase02_Spike_Results.md` section with measured displacement in meters at each checkpoint. This is the ground-truth against which the bounded-correction loop is later measured.
- **No pass/fail** — this is a measurement exercise.

**M02.0 exit criteria**:
- `docs/phases/Phase02_Spike_Results.md` exists with three sections answering A, B, C.
- Pose stack decision is committed in writing (Apple-primary vs ARCore-primary).
- Renderer decision is committed in writing (SceneKit vs RealityKit).
- Sliding baseline metrics are recorded.

All M02.0 code is throwaway. Do not ship it. M02.1 onward starts from the unmodified `main` baseline and applies decisions from M02.0.

### M02.1 — Pure baseline boot
- **Do**: Open the project in Xcode, fix any build errors from the restart copy. Confirm the existing SceneKit code path runs on device.
- **Exit**: App launches on an iPhone 13 Pro or newer, gets a `.localized` ARGeoTrackingStatus, draws nothing useful but doesn't crash.
- **Verifies**: We start from a known-good state.

### M02.2 — `earthFrame` + ARGeoAnchor parity (no content yet)
- **Do**: Add `earthFrame` SCNNode at scene-graph root. Move anchor creation/update logic to parent anchor-content under `earthFrame/anchors/<id>`. Remove any `setWorldOrigin` calls.
- **Exit**: Three test anchors render small debug spheres at their lat/lon. (M02.0 Spike C already captured the sliding baseline; here we just confirm the new node hierarchy doesn't change the sliding behavior.)
- **Verifies**: Reproducible sliding behavior is preserved + new node hierarchy works.

### M02.3 — Shared-data pipeline + GLTFKit2 + glb loading
- **Do**: Add GLTFKit2 via Swift Package Manager. Add the build phase from §6 that copies `webgl-component/models_to_place.json` and `webgl-component/skypath_models/*.glb` into the bundle's `Models/` folder. Update `Models.swift` to read the placement JSON from `Bundle.main`'s `Models/` folder, and to resolve `model_variant` to `<modelsDir>/<variant>.glb` (no USDZ assumption). Replace USDZ load calls with `GLTFAsset.load(...)` + `SCNScene.sceneWithGLTFAsset:`. Use `skypath_column.glb` as the first end-to-end test (smallest file).
- **Exit**: At least one model from the canonical (webgl-side) `models_to_place.json` loads and renders at its anchor location. Verify by changing the JSON in `webgl-component` on a feature branch + bumping the submodule + rebuilding — the iOS app picks up the change with no iOS-side edit.
- **Verifies**: Shared-data pipeline closes the loop with the webgl submodule. AC-0.

### M02.4 — `GARSession` parallel, Streetscape Geometry occluders
- **Do**: Apply the pose-stack decision from Spike A and the renderer decision from Spike B. Add ARCore iOS SDK via SPM or CocoaPods. Pair the chosen ARSession configuration with `GARSession`; feed each ARFrame; enable Geospatial + Streetscape Geometry modes. Convert geometries to occluder nodes under `earthFrame/occluders` using the renderer Spike B picked. Tint them debug-magenta during bring-up so we can see them.
- **Exit**: Stand in front of a building. Toggle debug tint off; place a virtual sphere on the far side of the building; the sphere is correctly hidden.
- **Verifies**: Occlusion mechanism works in isolation.

### M02.5 — Bounded reactive correction loop
- **Do**: Implement the IMU stillness detector. Implement the EMA correction on `earthFrame.transform` driven by the pose-stack-appropriate signals (`ARGeoAnchor` delegate updates if Spike A passed; `GARGeospatialTransform` updates if it didn't). Gate on numeric yaw uncertainty < 5° and stillness. Tune `α`, the per-update clamps, and the throttle.
- **Exit**: Repeat the M02.0 Spike C walk; compare against the Spike C baseline metrics. Measure perceived drift at fixed checkpoints. Yaw error after 5 minutes within ±3°.
- **Verifies**: AC-1, AC-2, AC-4 from §1.

### M02.6 — Field testing + tuning
- **Do**: Run AC-0 through AC-4 on a documented block. Tune EMA `α`, clamp values, stillness thresholds. Record telemetry: drift, yaw error, occlusion accuracy.
- **Exit**: All five acceptance criteria pass.

### M02.7 — Documentation pass
- **Do**: Update `docs/phases/Phase02_VPS_Grounded_Occluded_Plan.md` with as-built notes. Open Phase 03 stub for: glb→USDZ build-time conversion (if we want fast cold launches), close-range LiDAR mesh fusion, Niantic Lightship pilot, multi-device device-matrix testing.

---

## 8. Risks and explicit open questions

Top of list = highest-risk unknowns we resolve in M02.0 before committing the rest of the plan.

1. **🔴 `ARGeoTrackingConfiguration` + `GARSession` coexistence is undocumented**. Google's iOS samples pair `GARSession` only with `ARWorldTrackingConfiguration`. The combination is plausible (GARSession just consumes ARFrame, which is configuration-agnostic) but not confirmed. **Resolution**: Spike A in M02.0. **Fallback**: documented in §3 ("Fallback if Spike A fails").
2. **🔴 SceneKit + Streetscape Geometry as depth-only occluder at distance has no shipping reference**. Each component is documented in isolation; the composition is first-principles. **Resolution**: Spike B in M02.0. **Fallback**: RealityKit `OcclusionMaterial`. If both fail, depth-buffer precision is the issue and the occlusion architecture needs rework.
3. **🔴 Drift between iOS-side and webgl-side `models_to_place.json`** (different `model_variant` at the same `id`). Cleaned up by adopting webgl as canonical (§6), but the user must still reconcile the variant choices in the webgl repo first. **Resolution**: user-driven, separate from M02.0.
4. **🟡 ARCore Geospatial quotas / billing past free tier**. Limits: 1,000 sessions/min, 100,000 requests/min. Production scale would need a billed Google Cloud project. **Mitigation**: development is free; flip the billing switch before public launch.
5. **🟡 Streetscape Geometry mesh latency**. Meshes arrive only after Geospatial localization (~10 s warm-up). **Mitigation**: gate content placement on `.localized`; show "looking around" HUD until occluders appear.
6. **🟡 Pre-localization placement**. If the user places content before `.localized`, drift is unbounded. **Mitigation**: gate user placement on `.localized` + `.high|.medium` accuracy. Apple already provides this signal.
7. **🟢 iPhone-without-LiDAR coverage**. ARGeoTracking works on A12+ devices. LiDAR is optional, used only for close-range fusion in Phase 03.
8. **🟢 Build phase + submodule on CI**. CI must `git submodule update --init` before building. **Mitigation**: documented in `README.md`. Add to CI script.
9. **🟢 ARGeoTracking accuracy degradation in winter / fog / crowds**. **Mitigation**: bounded-correction architecture means degraded pose updates correct slowly without jumping. If accuracy drops to `.low`, freeze corrections and show a HUD warning.

Legend: 🔴 must resolve in M02.0 or before any subsequent milestone. 🟡 known issue, handled by named mitigation. 🟢 manageable, documented for awareness.

---

## 9. What this plan rejects

- **Custom Metal renderer**. Rejected — already burned a phase on it. SceneKit + a depth-only material is sufficient for the occlusion this requires.
- **cesium-native on iOS**. Rejected — no production prior art; iOS port was still upcoming as of late 2025; we already proved out the integration cost.
- **Photorealistic 3D Tiles on iOS**. Rejected — Geospatial Depth being Android-only means even with the tiles streamed, we'd still need to render depth ourselves. Streetscape Geometry gives us the depth-providing meshes directly with far less plumbing.
- **`setWorldOrigin` for ongoing drift correction**. Rejected — abrupt, user-visible, and Apple themselves treat its corrections as "jumps." We use a bounded EMA on an intermediate frame instead.
- **Maintaining USDZ and glb in parallel**. Rejected — this is exactly the drift problem we're trying to fix.
- **RealityKit migration**. Deferred to a later phase. RealityKit would force a rewrite of all the SceneKit material plumbing for marginal benefit at this stage.

---

## 10. Phase 03 backlog (not committed yet)

- glb → USDZ build-time conversion for faster cold launch.
- LiDAR `ARMeshAnchor` fusion with Streetscape Geometry within 10 m for close-range occlusion fidelity.
- Multi-device device-matrix tests (iPhone 13 Pro, iPhone 15, iPhone SE 3rd gen).
- Telemetry pipeline: per-session pose error logs, opt-in field reports.
- Niantic Lightship VPS pilot in a contained sub-area to compare against ARGeoTracking.
- Investigate Apple Vision Pro / visionOS port path (RealityKit-only world; would force a partial rewrite).
- Refinement: ICP-style local pose tweaking by matching ARKit planes against Streetscape Geometry footprints.

---

## 11. References

All citations live in [`docs/research/references.md`](../research/references.md). Key sources for this plan:

- Apple: ARGeoTrackingConfiguration, ARGeoAnchor, "Tracking geographic locations in AR", WWDC 2020 session 10611.
- Google: ARCore Geospatial API, Streetscape Geometry for iOS, GARSession docs, Geospatial usage quotas.
- Khronos: open-source iOS glTF viewer (SceneKit + GLTFKit2 reference architecture).
- Niantic: Lightship VPS architecture posts (background, not adopted in Phase 02).
- warrenm: GLTFKit2 README and Swift load patterns.
