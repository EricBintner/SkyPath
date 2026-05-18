# Phase 01 — Restart Plan

## Why this restart exists

A SceneKit-based pre-Metal build (last-known-good: 2025-06-21, archived at `../Old/GeoTestAR copy 10`) rendered correctly and ran on device, but virtual content **slid relative to the physical world** as the user walked and turned. To fix this, a custom Metal renderer was built that streamed Google Photorealistic 3D Tiles via `cesium-native` and attempted to bind them as depth-only occluders fused with ARKit.

That track never reached working occlusion. The bridge code grew to ~3,000 lines of Swift/Obj-C++ wrapping ~30 lines of Metal shader, much of it fragile coordinate-frame branching, and the foundational "Apple's kits can't anchor architectural-scale AR" premise turned out to be misleading — the code actually used `ARGeoTrackingConfiguration` + `ARGeoAnchor` already. We are parking that track (archived locally at `../SkyPath/`) and restarting from the SceneKit baseline with a different fix strategy.

## What this repo IS (committed decisions)

- **Renderer / AR stack**: Apple SceneKit + ARKit, as inherited from the pre-Metal baseline (`GeoTestARScene/`).
- **Pose**: `ARGeoTrackingConfiguration` + `ARGeoAnchor` (Apple GeoTracking), as inherited.
- **Asset source of truth**: the glTF/`.glb` models in `webgl-component/skypath_models/`. The webgl deployment already renders these correctly via Cesium; both sides should converge on the same files so the iOS app and the web app never drift apart. See [`GeoTestARScene/GeoTestARScene/ASSETS.md`](../../GeoTestARScene/GeoTestARScene/ASSETS.md).

## What this repo IS NOT (explicit non-goals)

- No custom Metal renderer.
- No `cesium-native` on-device streaming.
- No Google Photorealistic 3D Tiles on the iOS side. (Tiles remain relevant for the webgl viewer — that's the webgl repo's call.)
- No RealityKit migration in this phase.

## What's TBD (Phase 02 will pick one per row)

| Question | Candidates | Notes |
|---|---|---|
| iOS asset pipeline | (a) runtime glb loader (GLTFKit2 → SceneKit); (b) build-time `glb → usdz` conversion; (c) maintain both formats by hand | (c) is rejected — that's the drift problem we're trying to avoid. |
| Geo-pose stack | (a) stay on ARGeoTracking; (b) layer ARCore Geospatial (`GARSession`) on top; (c) move to ARCore primary | Research in `docs/research/VPS-research.md` §1 and `research-todos.md` §4. |
| Architectural occlusion | (a) ARCore Streetscape Geometry (LOD1/LOD2 building meshes, iOS-supported); (b) ARKit LiDAR scene reconstruction (close-range only); (c) none in Phase 02 | Geospatial Depth API is Android-only — not on the table for iOS. |
| "Sliding" root cause | yaw drift, GPS/VPS drift, anchor placement timing, compositing order | Need a reproducible field capture before designing a fix. |

## First measurable goal

A clean device build of the restored SceneKit baseline running the existing `skypath_locations*.json` placement, plus a recorded field session that reproduces the sliding behavior in a documented way. From that ground-truth capture we'll write Phase 02 — and only then commit to a specific fix.

The baseline will not run fully out of the box: the four largest USDZ models were stripped from the repo (see `ASSETS.md`). At minimum we need to either restore one of them as a Git LFS asset for development, or land the asset pipeline work first.

## Background notes

- `docs/research/VPS-research.md` — VPS landscape (ARKit GeoTracking vs ARCore Geospatial vs hybrid), occlusion approaches.
- `docs/research/research-todos.md` — open questions with confirmed findings on `cesium-native` budgets, Google Map Tiles attribution, ARKit GeoTracking gating, etc. Most still apply.

## Status

- [x] SceneKit baseline restored from `Old/GeoTestAR copy 10`.
- [x] WebGL component attached as submodule.
- [x] Big USDZs stripped; `*.usdz` git-ignored except `skypath_001.usdz` (3.7 MB, kept as smoke-test asset).
- [x] Phase 01 plan committed (this doc).
- [ ] Verify Xcode opens the project cleanly (no missing-file errors beyond expected USDZ gaps).
- [ ] Decide and land the iOS asset pipeline (Phase 02 row 1).
- [ ] Reproducible "sliding" capture in the field.
- [ ] Phase 02 plan drafted.
