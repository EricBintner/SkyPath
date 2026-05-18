# Agent rules for SkyPath

Conventions any agent (Claude, Cursor, Windsurf, human contributor) should follow when working in this repo.

## Scope discipline — AR screen only

**All Phase 02+ AR rebuild work touches the AR screen and its supporting types only.** Do not modify the Map, the WebView/Vercel wiring, the global UI (tab controller, AppDelegate, SceneDelegate, navigation), or the `webgl-component/` submodule contents unless explicitly asked.

In-scope files (rough guide):
- `GeoTestARScene/GeoTestARScene/ARViewController.swift` and any new AR-only types it spawns
- `GeoTestARScene/GeoTestARScene/Models.swift` and `models_to_place.json` parsing (consumed by AR)
- AR feature flags, AR HUD overlays, AR-only utility files under `utilities/`
- Build-phase scripts that copy shared data from the webgl submodule into the iOS bundle
- Docs under `docs/phases/`, `docs/research/`

Out-of-scope unless explicitly asked:
- `MapViewController.swift`, anything driving the map tab
- `LocationsViewController.swift`, web/Vercel content viewing
- `InfoViewController.swift` and global navigation
- `AppDelegate.swift`, `SceneDelegate.swift`, tab/navigation controllers
- `webgl-component/` (separate repo at `EricBintner/cesium-google-3dtiles`)

**Why**: past rebuilds caused regressions in working subsystems. The Map and WebView work today; do not put them at risk for AR work.

**When in doubt**: stop and ask before touching anything outside the AR surface.

## Shared data — single source of truth

The webgl submodule (`webgl-component/`) is the canonical source for **both** 3D model binaries (`.glb`) **and** geospatial placement data (the placement JSON files). iOS consumes copies via a build phase. Updating either:

1. Make the change in the `cesium-google-3dtiles` repo first.
2. Bump the submodule commit in this repo.
3. Both web viewer and iOS app pick up the new data on next build.

Never edit a copy of shared data on the iOS side directly — that re-introduces the drift problem we just got rid of.

See `docs/phases/Phase02_VPS_Grounded_Occluded_Plan.md` §6 for details and current open reconciliation questions.

## Verify before claiming

When the agent finishes a code change, confirm it built and ran (or say explicitly that it didn't). Don't declare a feature working off code-reading alone — AR especially needs device verification.
