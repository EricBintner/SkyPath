# Asset strategy

**Source of truth for 3D models: the webgl submodule.** Path: `webgl-component/skypath_models/*.glb`.

| Logical model | webgl source (glTF) | iOS bundled (USDZ) |
|---|---|---|
| skypath_01 (main building) | `skypath_models/skypath_01.glb` (13 MB) | not bundled |
| skypath_02 | `skypath_models/skypath_02.glb` (12 MB) | not bundled |
| skypath_column | `skypath_models/skypath_column.glb` (2.6 MB) | not bundled |
| skypath_001 (test variant) | (not in webgl) | `skypath_001.usdz` (3.7 MB) — kept as smoke-test asset |
| duck (placeholder) | `skypath_models/duck.glb` (0.1 MB) | not bundled |

## Why we stripped the bundled USDZs

The legacy `skypath_01.usdz` (45 MB), `skypath_01_OLD.usdz` (44 MB), `skypath_01_2024.usdz` (39 MB), and `skypath_column.usdz` (13 MB) were removed before the first commit. Reasons:

1. They are duplicates of the `.glb` files in the webgl submodule, but ~5× larger.
2. Carrying parallel copies in USDZ and glTF is exactly the drift problem that bit us before — webgl-side updates wouldn't propagate to iOS without manual conversion.
3. Pushing 145 MB of binary to the main repo just to inherit the SceneKit baseline doesn't move us forward.

`.gitignore` blocks `*.usdz` going forward, except for `skypath_001.usdz` which stays in the bundle as a small smoke-test asset.

## How the iOS app will consume the glb files — TBD, Phase 02

Three options on the table:

1. **Runtime glb loader on iOS** — [GLTFKit2](https://github.com/warrenm/GLTFKit2) feeds glTF into SceneKit/Metal/RealityKit. One asset format across web + iOS. Adds one Swift dependency.
2. **Build-time `glb → usdz` conversion** — Reality Converter or `usdcat`/`usdzconvert` from a build script. iOS stays purely Apple-native at runtime, but the build pipeline needs macOS-only tooling and the conversion is sometimes lossy on materials/textures.
3. **Both** — ship USDZ at runtime for fast launch, regenerate from glb whenever the webgl source changes. Most robust, most plumbing.

Until Phase 02 lands, any `models_to_place.json` entry pointing at a stripped USDZ will fail at runtime. That gap is intentional and load-bearing for the Phase 02 design conversation — don't paper over it by re-bundling USDZs.

## Misc files left in the repo

- `art.scnassets/ship.scn`, `art.scnassets/texture.png` — Apple's ARKit project-template defaults. Harmless. Remove later if unused.
- `skypath_locations*.json`, `models_to_place.json` — placement data. References model names; will need updating once the asset pipeline decision is made.
