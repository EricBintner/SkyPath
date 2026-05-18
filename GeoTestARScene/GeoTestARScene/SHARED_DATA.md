# Shared data strategy

The webgl submodule (`webgl-component/`, pinned to `EricBintner/cesium-google-3dtiles`) is the **single source of truth for both** 3D model binaries and geospatial placement data consumed by the iOS AR app. iOS bundles copies via a build phase. Drift between platforms becomes structurally impossible.

## What's shared

| Data | Canonical location | iOS bundle path |
|---|---|---|
| Placement records (lat/lon, rotation, tilt, model_variant, column offsets, scales) | `webgl-component/models_to_place.json` | `Bundle.main`/`Models/models_to_place.json` |
| Main building variants | `webgl-component/skypath_models/skypath_01.glb`, `skypath_02.glb` | `Bundle.main`/`Models/skypath_0X.glb` |
| Column models | `webgl-component/skypath_models/skypath_column.glb` | `Bundle.main`/`Models/skypath_column.glb` |
| Placeholder/test | `webgl-component/skypath_models/duck.glb` | `Bundle.main`/`Models/duck.glb` |

Both `.glb` and the placement JSON are gitignored at the iOS project root — iOS never carries its own copies in git. The build phase copies them in fresh on every build.

## The build phase

Add a Run Script phase to the `GeoTestARScene` target, **before** "Copy Bundle Resources":

```bash
set -e
SRC="${SRCROOT}/../webgl-component"
DST="${BUILT_PRODUCTS_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/Models"
mkdir -p "$DST"
cp "$SRC/models_to_place.json" "$DST/"
cp -R "$SRC/skypath_models/"*.glb "$DST/"
```

`set -e` + a missing source file means the build fails loudly if the submodule isn't initialized.

## How to update shared data

Always edit the webgl repo first:

```bash
# In a clone of EricBintner/cesium-google-3dtiles
git checkout -b update-placement
# edit models_to_place.json or replace .glb files
git commit -am "Update placements: ..."
git push

# Back in SkyPath
cd webgl-component
git pull origin main
cd ..
git add webgl-component
git commit -m "Bump webgl-component to <commit-hash>"
git push
```

Both web viewer (next Vercel deploy) and iOS app (next Xcode build) now pick up the new data. There is never a separate "iOS update" step.

## Canonical files — resolved

The user confirmed the canonical files are the ones currently in the `cesium-google-3dtiles` repo. iOS-side copies have been deleted; `.gitignore` now blocks them from re-appearing.

| Canonical (webgl repo) | iOS side |
|---|---|
| `webgl-component/models_to_place.json` (39 entries, `model_variant: skypath_02` for `6thAve_W58th_Model`) | Removed; supplied by build phase in M02.3 |
| `webgl-component/skypath_models/*.glb` | Already gitignored; supplied by build phase |
| `webgl-component/models_to_place copy.json` | (Webgl-side cleanup — not in scope for this repo) |
| `webgl-component/models_to_place_copied.json` | (Webgl-side cleanup — not in scope for this repo) |
| `webgl-component/skypath_tour_full_corrected.json` | (Webgl-side cleanup — not in scope for this repo) |
| (legacy) `skypath_locations.json`, `skypath_locations_green.json`, `skypath_locations_original 2.json` | Deleted from iOS — not referenced by Swift code |

The "copy"/"copied" variants in the webgl repo are flagged here as candidate cleanup but are out of scope for this iOS repo. They do not affect iOS — only `models_to_place.json` is read by the iOS build phase and the webgl viewer.

## What stays in the iOS bundle directly

- `art.scnassets/ship.scn`, `art.scnassets/texture.png` — Apple's ARKit project-template defaults. Harmless. Remove later if unused.
- `skypath_001.usdz` (3.7 MB) — small smoke-test asset, kept so the SceneKit USDZ code path has at least one valid input during baseline boot. Not used in the production pipeline.

## What this strategy rejects

- **Maintaining iOS-only model or JSON copies.** Rejected — drift is the failure mode.
- **Manual glb → usdz conversion checked into the iOS repo.** Rejected — same drift problem.
- **Pulling data over HTTP at runtime from Vercel.** Considered, rejected for Phase 02: adds a network failure mode, complicates offline behavior, doesn't materially change update cost vs a submodule bump. Could revisit in a later phase if the shared-data set grows large.
