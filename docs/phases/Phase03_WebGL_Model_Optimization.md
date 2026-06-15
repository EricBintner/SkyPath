# Phase 03 — WebGL Model & Memory Optimization

This document is the operator's plan for optimizing the SkyPath 3D content in the
Cesium WebGL component (`webgl-component/`, deployed to Vercel and loaded by the iOS
app's `LocationsViewController` WKWebView). Its primary purpose is to reclaim GPU
memory so the Google Photorealistic 3D Tiles can run at **full detail** on-device
without crashing the iOS WKWebView WebContent process.

> Numbering is a suggestion — renumber to fit the roadmap. This track is about the
> web component, not the AR/SceneKit work in Phases 01–02.

## 0. Background — why this phase exists

A "fly to" inside the in-app web view crashed the page (white screen, sometimes an
auto-reload first). Root cause, established by on-screen diagnostics on a physical
iPhone (see the temporary diagnostics block in `webgl-component/main.js`):

- The crash is the **iOS WKWebView WebContent/GPU process being killed when GPU
  memory exceeds the per-process ceiling** (~200 MB observed on device). It is *not*
  a WebP decode failure (textures render correctly), *not* a JS bug (desktop and the
  iOS Simulator never crash), and *not* a Cesium logic error.
- The same page in **mobile Safari on the same phone runs fine and peaks at ~129 MB** —
  Safari gets a higher per-process memory ceiling than a third-party app's WKWebView.
  So the content is not too heavy for the device; it is too heavy for the app's
  WebView budget specifically. This regressed when the app moved to the **iOS 18 SDK**
  (commit `673b792`) / a newer device iOS, which tightened that budget.
- The dominant driver was **tile-cache bloat**: `Cesium3DTileset.fromUrl(url, {})`
  used Cesium's 512 MB desktop default cache, which ballooned the tileset texture
  memory to ~209 MB and crashed the process.

**Already shipped (interim fix, in `main.js`):** the Google tileset is now created
with `cacheBytes: 100MB`, `maximumCacheOverflowBytes: 24MB`, and
`maximumScreenSpaceError: 16` (full detail). This stops the crash. This phase makes
that headroom durable and creates room to push tile detail *below* SSE 16 if desired.

### Current content facts

- **39 placements** in `models_to_place.json`, all reusing **2 GLB assets**:
  - `skypath_models/skypath_02.glb` (~12 MB; 27 `EXT_texture_webp`, 21 `image/webp`)
  - `skypath_models/skypath_column.glb` (~2.5 MB; 8 `EXT_texture_webp`)
  - (`skypath_01.glb` and `duck.glb` exist but are not referenced by the current JSON.)
- Each placement adds a primary model entity plus up to 4 column entities
  (`viewer.entities.add({ model: { uri } })`, `main.js:444`), so ~195 model entities total.
- All entities with the same `uri` share GPU geometry/textures via Cesium's
  reference-counted `ResourceCache`. So per-instance duplication is **not** the main
  cost — **texture format and resolution are.** WebP textures decode to *uncompressed
  RGBA* in GPU memory; the format only shrinks download size, not VRAM.

## 1. Goal & exit criteria

**Goal:** reduce the GPU/VRAM footprint of the placed models so Google 3D Tiles render
at full detail (`maximumScreenSpaceError ≤ 16`) with on-device peak memory staying
safely under the WKWebView ceiling (target: peak ≤ ~180 MB, ~20 MB margin).

**Exit criteria:**

- [ ] `skypath_02.glb` and `skypath_column.glb` re-encoded to **KTX2 / Basis Universal**
      (`KHR_texture_basisu`), textures right-sized, geometry compressed.
- [ ] Models render correctly on device (visual parity, no `'WEBP' … err=-50` decode
      spam in the Xcode console — KTX2 bypasses the platform image decoder entirely).
- [ ] On-device `peak=` (from the diagnostics gauge) at SSE 16 is reduced vs. the
      pre-phase baseline by a measured amount, with margin under the ceiling.
- [ ] Decision recorded on whether the freed headroom is spent on lower SSE (sharper
      tiles) or kept as safety margin.
- [ ] Temporary diagnostics block removed from `main.js`; optional iOS safety net added
      (see §6).
- [ ] Cesium engine/CSS version mismatch resolved (see §6).

## 2. Prerequisites & tooling

No build system in `webgl-component` — these are one-off asset transforms run locally.
Node 22 + `npx` are available.

| Tool | Install | Use |
|---|---|---|
| glTF-Transform CLI | `npx @gltf-transform/cli@latest` (no global install needed) | inspect, resize, compress, re-encode textures |
| KTX-Software (`toktx`/`ktx`) | `brew install ktx` | Basis/KTX2 texture encoder backing gltf-transform's `etc1s`/`uastc` |

Verify device capability is already confirmed: the diagnostics logged
`GPU: Apple GPU | MAX_TEX=16384 | WebGL2=true`. **WebGL2 is required for KTX2/Basis
transcoding in Cesium** — confirmed present.

**Safety:** always write to NEW files (e.g. `skypath_02.ktx2.glb`) and keep originals.
A/B test before replacing. Models are served from the Vercel deploy of
`webgl-component/skypath_models/`; changes go live only after the submodule is pushed.

## 3. Milestone A — Inspect & baseline

1. Record the pre-phase on-device baseline: with the current build, fly to a location
   and note the diagnostics `peak=` value and whether it crashes at SSE 16.
2. Inspect the assets:
   ```bash
   cd webgl-component/skypath_models
   npx @gltf-transform/cli@latest inspect skypath_02.glb
   npx @gltf-transform/cli@latest inspect skypath_column.glb
   ```
   Note per-texture **dimensions**, **mime type**, count, and total texture bytes.

**Acceptance:** baseline `peak=` recorded; texture inventory (sizes/formats) documented.

## 4. Milestone B — Right-size textures

Often the single biggest VRAM win, and invisible at phone viewing distances.

1. Decide a max dimension appropriate to how large the models appear on screen
   (start with 1024; try 512 for the column).
2. Resize:
   ```bash
   npx @gltf-transform/cli@latest resize skypath_02.glb skypath_02.resized.glb \
       --width 1024 --height 1024
   ```
3. A/B the resized model in the page; confirm no visible quality loss at tour distances.

**Acceptance:** textures ≤ target dimension; visual parity at tour camera distances.

## 5. Milestone C — Re-encode to KTX2 / Basis

Moves textures off WebP (uncompressed RGBA in VRAM) to GPU-compressed KTX2 that stays
compressed on the GPU (~4–8× less VRAM) and skips the iOS image decoder.

1. Encode (run on the resized output from §4). Recommend **UASTC** for the visible
   segment (higher quality) and **ETC1S** for the column (smaller):
   ```bash
   npx @gltf-transform/cli@latest uastc skypath_02.resized.glb skypath_02.ktx2.glb \
       --level 2 --rdo 4 --zstd 18
   npx @gltf-transform/cli@latest etc1s skypath_column.resized.glb skypath_column.ktx2.glb \
       --quality 200
   ```
2. Verify the WebP extension is gone and Basis is present:
   ```bash
   LC_ALL=C grep -ac "EXT_texture_webp" skypath_02.ktx2.glb   # expect 0
   LC_ALL=C grep -ac "KHR_texture_basisu" skypath_02.ktx2.glb # expect > 0
   ```
3. Swap filenames in `models_to_place.json` / `modelBasePath` usage (or replace the
   originals once validated), deploy, and confirm on device:
   - Models render correctly (UASTC/ETC1S can shift color/banding — eyeball it).
   - The `'WEBP' … err=-50` lines disappear from the Xcode console.
   - Diagnostics `peak=` at SSE 16 drops vs. the §3 baseline.

**Acceptance:** models on KTX2, render correctly, measured `peak=` reduction on device.

## 6. Milestone D — Geometry, cleanup & spend the headroom

1. Geometry compression (Cesium supports `EXT_meshopt_compression`):
   ```bash
   npx @gltf-transform/cli@latest optimize skypath_02.ktx2.glb skypath_02.final.glb \
       --compress meshopt --texture-compress ktx2
   ```
   (`optimize` also runs dedup/weld/prune; review its summary.)
2. **Decide how to spend the freed budget.** Using the diagnostics gauge, either:
   - lower the tileset `maximumScreenSpaceError` below 16 for sharper tiles while
     keeping `peak ≤ ~180 MB`, or
   - keep SSE 16 and bank the headroom as crash margin.
3. **Resolve the Cesium version mismatch:** `index.html` loads Cesium **CSS 1.129** but
   **engine 1.121**. Align both to 1.129 (or the latest tested), retest on device — a
   newer engine may also improve iOS WebGL/texture behavior.
4. **Remove the temporary diagnostics block** in `main.js` (search
   `TEMPORARY iOS-CRASH DIAGNOSTICS`).
5. **Optional safety net (iOS, no deploy needed):** add
   `webViewWebContentProcessDidTerminate(_:)` to `LocationsViewController.swift` to
   `reload()` on any future content-process crash. The system explicitly logged "the
   client did not handle it"; this converts a white screen into auto-recovery.

**Acceptance:** geometry compressed; SSE decision recorded; version mismatch fixed;
diagnostics removed; (optional) terminate handler added.

## 7. Deployment workflow

- `webgl-component/` is a git submodule (`github.com/EricBintner/cesium-google-3dtiles`)
  that **auto-deploys to `cesium-google-3d-2.vercel.app` on push to `main`**.
- The iOS app loads that remote URL, so JS/asset changes need **no Xcode rebuild** —
  just push, then fully quit + relaunch the app. The `build=` stamp in the gauge
  confirms the device picked up fresh code (WKWebView caches `main.js`; a full quit is
  usually enough, delete+reinstall clears it for certain).
- Verify a deploy is live:
  ```bash
  curl -s "https://cesium-google-3d-2.vercel.app/main.js?cb=$RANDOM" | grep build=
  ```

## 8. Known constraints / gotchas

- **The ceiling is the app's WKWebView, not the GPU.** Safari survives where the app
  crashes. There is no public API to raise a third-party WKWebView's WebContent memory
  limit, so the only lever is reducing memory — this phase plus the tile-cache cap.
- **Whole-app memory pressure matters.** AR + SceneKit + Map are held in memory
  alongside the web view; high app-wide memory makes iOS quicker to kill the web
  process. If memory headroom is still tight after this phase, consider releasing
  heavy subsystems (e.g. tearing down AR/SceneKit resources) while the web tab is
  active, beyond the existing `pauseWebContent()` call.
- **`pauseWebContent`/`resumeWebContent` are currently no-ops for Cesium.** They gate on
  `window.Cesium.viewer`, which `main.js` never assigns (the viewer is a module-scope
  `var`; diagnostics now expose `window.viewer`). If real pause-on-hide is wanted,
  point those scripts at `window.viewer` and set `requestRenderMode`/`shouldAnimate`.
- **KTX2 needs WebGL2** (confirmed available) and Cesium's Basis transcoder; test the
  actual transcode on-device, not just desktop.
