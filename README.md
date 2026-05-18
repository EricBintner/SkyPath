# SkyPath

iOS geospatial AR experience: place architectural-scale virtual models at real-world locations with VPS-quality anchoring, alongside a standalone web viewer.

This repository is a **restart** of the SkyPath project. See [`docs/phases/Phase01_Restart_Plan.md`](docs/phases/Phase01_Restart_Plan.md) for the why and the direction.

## Structure

- `GeoTestARScene/` — iOS SceneKit + ARKit app (Xcode project)
- `webgl-component/` — Standalone Cesium + Google Photorealistic 3D Tiles viewer; deployed to Vercel. Tracked here as a git submodule of [`EricBintner/cesium-google-3dtiles`](https://github.com/EricBintner/cesium-google-3dtiles). Also the **single source of truth for 3D models AND geospatial placement JSON** — see [`GeoTestARScene/GeoTestARScene/SHARED_DATA.md`](GeoTestARScene/GeoTestARScene/SHARED_DATA.md).
- `AGENTS.md` — repo-wide conventions for any agent (human or AI) working on this code, including the AR-screen-only scope rule.
- `docs/phases/` — Phased plans, in order. Start with [Phase 01](docs/phases/Phase01_Restart_Plan.md) for the *why*, then [Phase 02](docs/phases/Phase02_VPS_Grounded_Occluded_Plan.md) for the *what we're building*.
- `docs/research/` — Background research and citation index ([`references.md`](docs/research/references.md)) on VPS, ARKit GeoTracking, ARCore Geospatial, occlusion approaches. Carried forward from prior work.

## Cloning

```bash
git clone https://github.com/EricBintner/SkyPath.git
cd SkyPath
git submodule update --init --recursive
```

## Building

Open `GeoTestARScene/GeoTestARScene.xcodeproj` in Xcode. Device build is required for AR validation. Some asset loading will fail until the shared-data pipeline lands in Phase 02 — see [`SHARED_DATA.md`](GeoTestARScene/GeoTestARScene/SHARED_DATA.md).

## Origin

This repo restarts from `Old/GeoTestAR copy 10` (dated 2025-06-21) — the last-known working pre-Metal SceneKit baseline in the prior workspace. A subsequent Metal + `cesium-native` rebuild was attempted and is now archived locally; it is not carried into this repo. Phase 01 explains what is and is not in scope.
