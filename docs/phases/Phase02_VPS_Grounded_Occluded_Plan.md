# Phase 02 — VPS-Grounded, Architecturally-Occluded AR

> **TL;DR.** Run Apple ARKit `ARGeoTrackingConfiguration` as the primary geo-pose source. Run ARCore `GARSession` in parallel — not for pose, but to get **Streetscape Geometry** building meshes, which feed a SceneKit depth-only occlusion pass. Park all geo-content under one `earthFrame` SCNNode that receives **bounded, stillness-gated EMA corrections** rather than abrupt `setWorldOrigin` resets. Load models at runtime via **GLTFKit2** from the webgl submodule.

This phase produces a build that (a) does not slide noticeably while a user walks an NYC block and (b) occludes virtual content behind real buildings within ~80% of visible facades. No Metal renderer. No `cesium-native`. No Photorealistic 3D Tiles on-device.

---

## 1. Success criteria (acceptance tests)

The build is "Phase 02 done" when all four pass on a single test device on a documented NYC block:

| # | Test | Threshold |
|---|---|---|
| **AC-1** | Place 3 ARGeoAnchored objects from `skypath_locations.json`. Walk 50 m of the block forward, return, place a fresh checkpoint anchor, measure displacement of original anchors at their nominal latitude/longitude. | Lateral drift ≤ **1.0 m** |
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

## 3. Pose strategy — "Apple primary, Google sanity-check"

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

## 5. Architectural occlusion — Streetscape Geometry into SceneKit

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

## 6. Asset pipeline — GLTFKit2 from the webgl submodule

### Goal

iOS loads the **same** `.glb` files used by the webgl viewer. No parallel USDZ tree, no manual conversion drift.

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

### Bundling glb files into the iOS app at build time

The submodule path `webgl-component/skypath_models/*.glb` is not in the iOS target's bundle by default. Add a Run Script build phase:

```bash
# Build phase: "Copy glb models from webgl submodule"
SRC="${SRCROOT}/../webgl-component/skypath_models"
DST="${BUILT_PRODUCTS_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/Models"
mkdir -p "$DST"
cp -R "$SRC/"*.glb "$DST/"
```

At runtime:

```swift
let modelsDir = Bundle.main.bundleURL.appendingPathComponent("Models")
let glbURL = modelsDir.appendingPathComponent("\(modelName).glb")
```

Updating the webgl repo's `.glb` files and bumping the submodule commit is the **only** path for changing iOS assets. Drift between platforms becomes structurally impossible.

### `models_to_place.json` schema update

The existing JSON references things like `"modelName": "skypath_01"`. Keep that string identical — it now resolves to `Models/skypath_01.glb`. No JSON migration needed; just remove the `.usdz` suffix assumption in the loader.

---

## 7. Implementation milestones

Each milestone is ~1-3 days of focused work and has an explicit exit criterion. Land them sequentially.

### M02.1 — Pure baseline boot
- **Do**: Open the project in Xcode, fix any build errors from the restart copy. Confirm the existing SceneKit code path runs on device.
- **Exit**: App launches on an iPhone 13 Pro or newer, gets a `.localized` ARGeoTrackingStatus, draws nothing useful but doesn't crash.
- **Verifies**: We start from a known-good state.

### M02.2 — `earthFrame` + ARGeoAnchor parity (no content yet)
- **Do**: Add `earthFrame` SCNNode at scene-graph root. Move anchor creation/update logic to parent anchor-content under `earthFrame/anchors/<id>`. Remove any `setWorldOrigin` calls.
- **Exit**: Three test anchors render small debug spheres at their lat/lon. Walk a block; observe sliding behavior. **Document the sliding** — video, screenshots, OSLog capture. This is the baseline against which fixes are measured.
- **Verifies**: Reproducible sliding behavior + new node hierarchy works.

### M02.3 — GLTFKit2 + glb loading
- **Do**: Add GLTFKit2 via Swift Package Manager. Add the build script to copy `webgl-component/skypath_models/*.glb` into the bundle. Replace USDZ load calls with GLTFKit2 load calls. Use the smaller `skypath_column.glb` as the first end-to-end test.
- **Exit**: At least one model from `models_to_place.json` loads and renders at its anchor location.
- **Verifies**: Asset pipeline closes the loop with the webgl submodule.

### M02.4 — `GARSession` parallel, Streetscape Geometry occluders
- **Do**: Add ARCore iOS SDK via SPM or CocoaPods. Pair `ARSession` with `GARSession`; feed each ARFrame; enable Geospatial + Streetscape Geometry modes. Convert geometries to depth-only SCNNodes under `earthFrame/occluders`. Tint them debug-magenta with `colorBufferWriteMask = .all` during bring-up so we can see them.
- **Exit**: Stand in front of a building. Toggle debug tint off; place a virtual sphere on the far side of the building; the sphere is correctly hidden.
- **Verifies**: Occlusion mechanism works in isolation.

### M02.5 — Bounded reactive correction loop
- **Do**: Implement the IMU stillness detector. Implement the EMA correction on `earthFrame.transform` driven by `ARGeoAnchor` delegate updates, gated by `GARGeospatialTransform.orientationYawAccuracy < 5°` and stillness. Tune `α`, the per-update clamps, and the throttle.
- **Exit**: Repeat the M02.2 sliding-walk; compare to baseline video. Measure perceived drift at fixed checkpoints. Yaw error after 5 minutes within ±3°.
- **Verifies**: AC-1, AC-2, AC-4 from §1.

### M02.6 — Field testing + tuning
- **Do**: Run AC-1 through AC-4 on a documented block. Tune EMA `α`, clamp values, stillness thresholds. Record telemetry: drift, yaw error, occlusion accuracy.
- **Exit**: All four acceptance criteria pass.

### M02.7 — Documentation pass
- **Do**: Update `docs/phases/Phase02_VPS_Grounded_Occluded_Plan.md` with as-built notes. Open Phase 03 stub for: glb→USDZ build-time conversion (if we want fast cold launches), close-range LiDAR mesh fusion, Niantic Lightship pilot, multi-device device-matrix testing.

---

## 8. Risks and explicit open questions

1. **`ARGeoTrackingConfiguration` and `GARSession` compatibility**. Google's docs and samples typically pair `GARSession` with `ARWorldTrackingConfiguration`. Whether `GARSession.update(_:error:)` accepts frames from an `ARGeoTrackingConfiguration` is not explicitly documented. **Mitigation**: empirically verify in M02.4. If incompatible, fall back to `ARWorldTrackingConfiguration` and synthesize the geo pose ourselves from `GARSession.earth`'s pose.
2. **ARCore Geospatial quotas / billing past free tier**. Quota: 1,000 sessions/min, 100,000 requests/min. Production scale would need a billed Google Cloud project. **Mitigation**: development is free; flip the billing switch when we promote past internal testing.
3. **Streetscape Geometry mesh latency**. Meshes arrive only after Geospatial localization; the first ~10 s of a session has no occluders. **Mitigation**: gate content placement on `.localized` anyway; show "looking around" HUD until occluders appear.
4. **Pre-localization placement**. If the user places content before `.localized`, drift is unbounded. **Mitigation**: gate user placement on `.localized` + `.high|.medium` accuracy. Apple already provides this signal.
5. **iPhone-without-LiDAR coverage**. ARGeoTracking works on A12+ devices, so this is mostly fine. LiDAR is a nice-to-have for close-range occlusion in Phase 03, not required for Phase 02.
6. **Build phase + submodule on CI**. The "copy glb" build phase reads from a submodule. CI must `git submodule update --init` before building. **Mitigation**: documented in `README.md`. Add to CI script.
7. **What if Apple's NYC ARGeoTracking accuracy degrades in winter / fog / crowds?** Empirical question. **Mitigation**: the bounded-correction architecture means even degraded pose updates correct slowly without jumping — graceful degradation is built in. If accuracy drops to `.low`, freeze corrections and show a HUD warning.

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
