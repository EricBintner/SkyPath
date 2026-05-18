# Phase 01 — Restart Plan

## Why this restart exists

A SceneKit-based pre-Metal build (last-known-good: 2025-06-21, archived at `../Old/GeoTestAR copy 10`) rendered correctly and ran on device, but virtual content **slid relative to the physical world** as the user walked and turned. To fix this, a custom Metal renderer was built that streamed Google Photorealistic 3D Tiles via `cesium-native` and attempted to bind them as depth-only occluders fused with ARKit.

That track never reached working occlusion. The bridge code grew to ~3,000 lines of Swift/Obj-C++ wrapping ~30 lines of Metal shader, much of it fragile coordinate-frame branching, and the foundational "Apple's kits can't anchor architectural-scale AR" premise turned out to be misleading — the code actually used `ARGeoTrackingConfiguration` + `ARGeoAnchor` already. We are parking that track (archived locally at `../SkyPath/`) and restarting from the SceneKit baseline with a different fix strategy.

## What this repo IS (committed decisions)

- **Renderer / AR stack**: Apple SceneKit + ARKit, as inherited from the pre-Metal baseline (`GeoTestARScene/`).
- **Pose**: `ARGeoTrackingConfiguration` + `ARGeoAnchor` (Apple GeoTracking), as inherited.
- **Shared data source of truth**: the webgl submodule (`webgl-component/`) holds the canonical glTF model binaries **and** the canonical geospatial placement JSON. Both iOS and the web viewer read from the same files. See [`GeoTestARScene/GeoTestARScene/SHARED_DATA.md`](../../GeoTestARScene/GeoTestARScene/SHARED_DATA.md).

## What this repo IS NOT (explicit non-goals)

- No custom Metal renderer.
- No `cesium-native` on-device streaming.
- No Google Photorealistic 3D Tiles on the iOS side. (Tiles remain relevant for the webgl viewer — that's the webgl repo's call.)
- No RealityKit migration in this phase.

## Decisions made in Phase 02 (these were TBD when this doc was first written)

See [`Phase02_VPS_Grounded_Occluded_Plan.md`](Phase02_VPS_Grounded_Occluded_Plan.md) for the full reasoning. Summary:

| Question | Decision |
|---|---|
| iOS asset pipeline | **GLTFKit2** (Swift Package). Build phase copies `webgl-component/skypath_models/*.glb` into the iOS bundle. Single source of truth = webgl submodule. |
| Geo-pose stack | **Apple `ARGeoTrackingConfiguration` primary** for placement; **ARCore `GARSession` in parallel** strictly to get Streetscape Geometry meshes and a numeric yaw-uncertainty signal. ARCore *Geospatial Anchors* are not used. |
| Architectural occlusion | **ARCore Streetscape Geometry** (LOD2 building meshes) → SCNGeometry with depth-only SCNMaterial. LiDAR fusion deferred to Phase 03. |
| "Sliding" root cause / fix | Mitigated by a single `earthFrame` SCNNode receiving bounded, stillness-gated EMA corrections — no `setWorldOrigin` resets. See Phase 02 §4. |

## First measurable goal

A clean device build of the restored SceneKit baseline running the existing `skypath_locations*.json` placement, plus a recorded field session that reproduces the sliding behavior in a documented way. From that ground-truth capture we'll write Phase 02 — and only then commit to a specific fix.

The baseline will not run fully out of the box: the four largest USDZ models were stripped from the repo (see [`SHARED_DATA.md`](../../GeoTestARScene/GeoTestARScene/SHARED_DATA.md)). The Phase 02 build-phase pipeline (M02.3) closes that gap by pulling models from the webgl submodule.

## Background notes

- `docs/research/VPS-research.md` — VPS landscape (ARKit GeoTracking vs ARCore Geospatial vs hybrid), occlusion approaches.
- `docs/research/research-todos.md` — open questions with confirmed findings on `cesium-native` budgets, Google Map Tiles attribution, ARKit GeoTracking gating, etc. Most still apply.

## Status

- [x] SceneKit baseline restored from `Old/GeoTestAR copy 10`.
- [x] WebGL component attached as submodule.
- [x] Big USDZs stripped; `*.usdz` git-ignored except `skypath_001.usdz` (3.7 MB, kept as smoke-test asset).
- [x] Phase 01 plan committed (this doc).
- [x] Phase 02 plan drafted — see [`Phase02_VPS_Grounded_Occluded_Plan.md`](Phase02_VPS_Grounded_Occluded_Plan.md).
- [ ] Verify Xcode opens the project cleanly (no missing-file errors beyond expected USDZ gaps).
- [ ] Reproducible "sliding" capture in the field. (Now milestone M02.2.)

> Phase 01 is the *restart-the-tree* phase. Phase 02 is the *make-it-work* phase. They share the repo state but distinct intent.
