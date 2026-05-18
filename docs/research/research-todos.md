# Research TODOs

Purpose: Validate assumptions before deep implementation. Track answers, links, and decisions.

## --------------------------------------------------------------------------
## 0) Rendering framework architecture (SceneKit vs RealityKit vs Metal) *Hight priority*
- Questions
  - Which stack best supports streaming large, dynamic meshes for occlusion and optional rendering from cesium-native?
  - RealityKit limits: MeshResource creation/update costs, max vertex/index counts, CustomMaterial flexibility for depth-only writes.
  - SceneKit limits: SCNGeometry creation/update costs, SCNTechnique/SCNProgram needs, multithreaded scene updates.
  - Metal path: complexity vs benefits for a dedicated depth-only occlusion pass and future full rendering.
  - Integration with ARKit features (ARMeshAnchors, scene reconstruction, depth occlusion) and long-term framework direction.
- Actions
  - Implement minimal occlusion-only pipelines in each stack:
    - SceneKit: SCNGeometry + depth-only SCNMaterial.
    - RealityKit: ModelEntity with OcclusionMaterial/CustomMaterial.
    - Metal: simple render pipeline with depth write only.
  - Microbenchmarks on device (triangle counts: ~10k/100k/1M):
    - Geometry creation time, CPU memory, draw time, FPS stability.
  - Measure conversion cost from a decoded 3D Tile primitive to each stack’s mesh format.
  - Define a renderer-agnostic mesh descriptor (positions, normals, indices, bounds, transform).
- Deliverables
  - Recommendation (near-term and long-term) and a `RendererBridge` interface spec with SceneKit and RealityKit adapters.
### Findings
- __SceneKit__: Practical for depth-only occlusion with low boilerplate. Depth-only via `SCNMaterial.writesToDepthBuffer = true` and disabling color writes (e.g., `SCNMaterial.colorBufferWriteMask = []`). Control draw order with `SCNNode.renderingOrder`. Mature ARKit interop and adequate performance when meshes are batched to reduce node/draw counts.
- __RealityKit__: Very simple occlusion path (`OcclusionMaterial`), but less control over depth-only nuances and less flexibility for large volumes of dynamically created meshes compared to SceneKit.
- __Metal__: Maximum control (custom depth-only pass, tighter memory & CPU/GPU scheduling), but highest complexity. Best as a long-term evolution once SceneKit occlusion is validated.
- __RendererBridge__: Keep a renderer-agnostic mesh descriptor: positions (Float32), normals (optional), indices (UInt32/UInt16), local bounds (AABB), and transform. Enables swapping SceneKit/RealityKit/Metal without changing cesium-native plumbing.

References:
- Google Photorealistic 3D Tiles require visible attribution; renderer choice must support on-screen credits. See Google Policies → Photorealistic 3D Tiles attribution.
  - https://developers.google.com/maps/documentation/tile/policies (Photorealistic 3D Tiles attribution section)

### Conclusions
- __Near-term__: Use SceneKit for occlusion-only rendering of streamed meshes. Implement depth-only materials and batching. Build the `RendererBridge` for mesh handoff.
- __Long-term__: Add a Metal path for full 3D Tiles rendering and fine-grained control, keeping SceneKit occlusion as a fallback. RealityKit remains optional for future features but is not required for initial occlusion.

## --------------------------------------------------------------------------
## 1) Google Photorealistic 3D Tiles
- Questions
  - Exact endpoint(s) and auth scheme for iOS (API key in URL vs header).
  - Verify service name and enablement in GCP: Map Tiles API (`tile.googleapis.com`); confirm Photorealistic 3D Tiles is part of this service.
  - Terms of use for occlusion-only rendering (invisible meshes) and VPS-like alignment.
  - Quotas, pricing, regional availability, rate limits.
  - On-device caching policy (allowed size, eviction strategy, persistence).
  - ATS (App Transport Security) exceptions required?
- Actions
  - Create a minimal curl request that retrieves tileset metadata with API key.
  - Confirm sample tiles for a single NYC block.
  - In the Google Cloud Console, confirm Map Tiles API is enabled for the project and note the SKU used for Photorealistic 3D Tiles.
- Deliverables
  - Confirmed request pattern, error handling, and basic metadata fields.

### Findings
- __Endpoint & auth__: Root tileset URL is `https://tile.googleapis.com/v1/3dtiles/root.json?key=YOUR_API_KEY`. Renderer then fetches tiles using a time-limited session derived from the root request. Source: "Getting tiles" section.
  - https://developers.google.com/maps/documentation/tile/3d-tiles
- __Usage limits__: Photorealistic 3D Tiles quotas (per project):
  - Max 10,000 root tileset queries per day.
  - Timed session tokens allow up to 3 hours of renderer tile requests from a single root request.
  - Unlimited renderer-originating tile requests per day; renderer rate limit 12,000 QPM.
  - https://developers.google.com/maps/documentation/tile/usage-and-billing (Usage limits → Photorealistic 3D Tiles)
- __Caching & offline__: No pre-fetch/index/store/cache beyond the Agreement’s limited conditions. Must respect HTTP `Cache-Control` and `ETag` headers (e.g., `max-age`, `stale-while-revalidate`, `must-revalidate`, `private`). Offline/non-visualization use (e.g., analysis/extraction) prohibited.
  - https://developers.google.com/maps/documentation/tile/policies (Pre-fetching, caching, or storage of content)
- __Attribution__: Must aggregate and display attributions for visible tiles (e.g., glTF `asset.copyright`) on-screen. JS/Unreal/Unity have toggles like `showCreditsOnScreen`—we must implement a native equivalent overlay.
  - https://developers.google.com/maps/documentation/tile/policies (Photorealistic 3D Tiles attribution)
- __ATS__: `tile.googleapis.com` is HTTPS with modern TLS; no ATS exceptions expected. Only add ATS keys if contacting non-TLS endpoints (not planned). Reference: NSAppTransportSecurity.
  - https://developer.apple.com/documentation/bundleresources/information_property_list/nsapptransportsecurity
- __Example request__ (root tileset):
  - curl: `curl -s "https://tile.googleapis.com/v1/3dtiles/root.json?key=$MAP_TILES_API_KEY"`

### Conclusions
- Use `URLSession` GET to `.../v1/3dtiles/root.json?key=...`; no ATS exception required.
- Implement on-screen attribution overlay sourced from glTF `asset.copyright` of visible tiles.
- Respect HTTP caching headers via `URLCache` (in-memory + on-disk), but do not implement offline persistence beyond protocol directives.
- Design around the 3-hour session window by refreshing the root tileset at or before expiry; monitor root query quota (10k/day) and renderer rate limits.

## --------------------------------------------------------------------------
## 2) cesium-native integration details
- Questions
  - Using `CesiumCurl::CurlAssetAccessor` vs custom URLSession accessor: pros/cons.
  - Minimal `IPrepareRendererResources` shape for SceneKit: what data to capture.
  - Threading model for `prepareInLoadThread` and `prepareInMainThread`.
  - Tile memory budgeting knobs (LRU, request concurrency, decode concurrency).
- Actions
  - Build a one-tile offline sample and inspect glTF primitive structure.
  - Prototype a triangle mesh handoff format (positions, normals, indices, bounds).
- Deliverables
  - Notes on API surfaces we must implement and the smallest viable mesh format.

### Findings
- __Asset access__: cesium-native uses `IAssetAccessor` to fetch content. Default `CurlAssetAccessor` is available, but iOS can implement a custom accessor using `URLSession` to leverage platform caching, ATS, and metrics.
  - https://cesium.com/learn/cesium-native/ref-doc/classCesiumAsync_1_1IAssetAccessor.html
- __Renderer resources__: Tiles flow through background and main-thread prep hooks: `prepareInLoadThread` (CPU-heavy decode like Draco, quantization, mesh packing) and `prepareInMainThread` (renderer object creation). This is orchestrated during `Tileset.updateView(...)` with asynchronous loads.
  - https://cesium.com/learn/cesium-native/ref-doc/rendering-3d-tiles.html
- __View & selection__: Provide one or more `ViewState`s (camera pos, dir, up, viewport, FOV) each frame to drive selection, loading, and refinement.
  - https://cesium.com/learn/cesium-native/ref-doc/rendering-3d-tiles.html
- __Budgeting knobs__: `TilesetOptions` exposes controls like `maximumCachedBytes`, `maximumSimultaneousTileLoads`, and `requestHeaders`, plus renderer-related options.
  - https://cesium.com/learn/cesium-native/ref-doc/structCesium3DTilesSelection_1_1TilesetOptions.html
- __Minimal handoff format__: A `RendererMesh` payload with positions (f32), indices (u16/u32), normals (optional), local AABB, and model-to-world transform is sufficient for occlusion-only SceneKit geometry.

### Conclusions
- __Phase 1__: Use the provided `CurlAssetAccessor` to reduce integration risk and validate selection/visibility and threading. Implement a SceneKit path that builds `SCNGeometry` with a depth-only material in `prepareInMainThread`.
- __Phase 2__: Replace with a `URLSession`-based `IAssetAccessor` for system caching/telemetry and unified networking. Add tile-level metrics and backpressure.
- Configure `TilesetOptions` with conservative concurrency (`maximumSimultaneousTileLoads`) and a bounded cache (`maximumCachedBytes`), tuning with on-device profiling while staying within Google usage limits and attribution requirements.

## --------------------------------------------------------------------------
## 3) ARKit ↔ Earth frame transforms
- Questions
  - Convert WGS84 to ECEF and local ENU with cesium-native utilities.
  - Maintain ARKit world ↔ ENU transform including scale and handedness.
  - Choosing an origin (first geo anchor? fixed reference?) and drift handling.
- Actions
  - Document a transform pipeline with matrices and coordinate conventions.
  - Validate FOV/viewport mapping to `Cesium3DTilesSelection::ViewState`.
- Deliverables
  - A short spec for the transform math used in the app.

### Findings (initial)
- Apple provides geographic AR via `ARGeoTrackingConfiguration` and anchors via `ARGeoAnchor` on iOS.
  - https://developer.apple.com/documentation/arkit/argeotrackingconfiguration
  - https://developer.apple.com/documentation/arkit/argeoanchor
- We will map WGS84 → ECEF → local ENU around a chosen origin, and maintain a transform between ENU and ARKit world coordinates for camera/view state.

### Conclusions (initial)
- Choose a stable origin (first reliable `ARGeoAnchor` or a fixed reference). Use right-handed ENU with 1 meter = 1 unit. Document the full matrix pipeline and align camera to cesium-native `ViewState`.

## --------------------------------------------------------------------------
## 4) VPS anchoring options on iOS (choose best path)
- Questions
  - ARKit GeoTracking (`ARGeoTrackingConfiguration`) coverage, accuracy in NYC, conditions (Look Around availability), startup/relocation behavior.
  - Google ARCore Geospatial API (iOS) coverage/accuracy, Street View dependency, licensing, integration path with ARKit.
  - Using 3D Tiles geometry as a geometric prior/refinement (not a full VPS): match ARKit planes/reconstruction/edges to tiles (ICP-like) to reduce yaw/translation drift.
  - Hybrid approach feasibility: initial global pose from ARKit GeoTracking or ARCore Geospatial, refined via 3D Tiles mesh alignment.
- Actions
  - Create a comparison matrix (coverage, accuracy, dependencies, cost, offline behavior, iOS support) for ARKit GeoTracking vs ARCore Geospatial vs 3D Tiles refinement.
  - Literature review on large-scale AR alignment using city meshes; identify practical alignment signals (planes, façades, curb edges).
  - Prototype a coarse refinement step over a small NYC block using ARKit planes/reconstruction against a local 3D Tiles mesh.
- Deliverables
  - Recommendation doc selecting the anchoring approach, with integration plan and fallback strategy.

### Findings (updated)
- ARKit GeoTracking (NYC note):
  - In NYC, skip coverage preflight; rely on runtime `ARGeoTrackingStatus` and `.localized` gating for placement. `checkAvailability(at:)` remains useful for out-of-city or unknown regions.
  - ARKit docs: `ARGeoTrackingConfiguration` API and `checkAvailability(at:)`.
    - https://developer.apple.com/documentation/arkit/argeotrackingconfiguration
- ARCore Geospatial (iOS):
  - Enable ARCore API in Google Cloud and authorize with API key via `GARSession sessionWithAPIKey:bundleIdentifier:error:`.
    - https://developers.google.com/ar/develop/ios/geospatial/quickstart
  - Gate anchor placement with horizontal/heading accuracy thresholds to avoid flicker; sample thresholds provided in the quickstart.
- Streetscape Geometry (optional in ARCore mode):
  - Enable with `GARGeospatialModeEnabled` and `GARStreetscapeGeometryModeEnabled`.
  - Obtain meshes via `GARFrame.streetscapeGeometries`, hit-test with `GARSession.raycastStreetscapeGeometry:direction:error:`, and anchor with `createAnchorOnStreetscapeGeometry:transform:error:`. Supports LOD1/LOD2.
    - https://developers.google.com/ar/develop/ios/geospatial/streetscape-geometry
- 3D Tiles for local refinement (policy-compliant):
  - Use photorealistic 3D Tiles geometry only for visualization-aligned, in-session refinement (no storage, extraction, or offline use). Respect HTTP `Cache-Control` and `ETag`.
    - Policies: https://developers.google.com/maps/documentation/tile/policies
  - Root tileset URL and ~3-hour session window (refresh root before expiry):
    - https://developers.google.com/maps/documentation/tile/3d-tiles
  - Attribution required: aggregate and display visible tiles’ `asset.copyright` on-screen.
    - Own renderer guidance: https://developers.google.com/maps/documentation/tile/create-renderer#display-attributions
    - Renderer best practices: https://developers.google.com/maps/documentation/tile/use-renderer

### Conclusions (updated)
- Primary: ARKit GeoTracking with coverage localization/accuracy gates for anchor/model placement.
- Fallback: ARCore Geospatial on iOS when ARKit is unavailable or unstable; optionally use Streetscape Geometry to attach anchors to building meshes.
- Hybrid: Apply small, bounded refinement (e.g., ±3–5° yaw / small translation) using nearby 3D Tiles geometry; implement via an intermediate transform node so anchors remain stable. Keep usage strictly in-session and visualization-aligned to comply with policies.
- Integration notes (Original app): add coverage preflight in `ARViewController.swift`; gate placements on `.localized` + accuracy thresholds; add an optional `refinementNode`; implement an attribution overlay.

## --------------------------------------------------------------------------
## 5) SceneKit occlusion quality
- Questions
  - Depth-only material setup in SceneKit for stable occlusion (no color writes).
  - Z precision issues at city scale; mesh decimation vs quality tradeoffs.
  - Draw call and node count budgets for sustained FPS.
- Actions
  - Build a tiny occluder mesh and measure performance.
  - Determine batching strategy (merge by tile or by block).
- Deliverables
  - Best-practice recipe for invisible occluders on iOS devices.

### Findings (updated)
- Depth-only SceneKit occluders:
  - Use a depth-only material: `SCNMaterial.writesToDepthBuffer = true`; `SCNMaterial.colorBufferWriteMask = []`; control ordering via `SCNNode.renderingOrder`. Batch meshes; prefer 16-bit indices where feasible.
- Cesium-native tiles + budgets:
  - Configure `TilesetOptions.maximumCachedBytes` (bounded) and `maximumSimultaneousTileLoads` (conservative) and tune on device.
    - https://cesium.com/learn/cesium-native/ref-doc/structCesium3DTilesSelection_1_1TilesetOptions.html
  - Photorealistic 3D Tiles memory growth (iOS) — status: resolved:
  - cesium-native issue #739 has been resolved; the prior workaround (periodic tileset recreation) is no longer required. For ground-level AR, typical usage patterns should not exhibit unbounded growth; continue routine memory profiling.
    - https://github.com/CesiumGS/cesium-native/issues/739
  - Attribution overlay requirement:
    - Aggregate visible tiles’ glTF `asset.copyright`; semicolon-separate; sort by frequency; render as a bottom-line overlay. Must display Google logo/data attributions per policies. CesiumJS uses `showCreditsOnScreen`—implement native equivalent.
      - Policies (attribution): https://developers.google.com/maps/documentation/tile/policies#photorealistic_3d_tiles
      - Own renderer (display attributions): https://developers.google.com/maps/documentation/tile/create-renderer#display-attributions
  - Session + caching reminders:
    - Refresh the root tileset before the ~3-hour session window expires; respect `Cache-Control`/`ETag`; no offline storage beyond protocol directives.
      - 3D Tiles (Getting tiles): https://developers.google.com/maps/documentation/tile/3d-tiles
      - Policies (caching): https://developers.google.com/maps/documentation/tile/policies#pre-fetching_caching_or_storage_of_content

### Conclusions (updated)
- Adopt SceneKit depth-only material preset + batching; set conservative cesium-native budgets; implement an attribution overlay; validate on target devices and tune; monitor memory with routine profiling (no periodic tileset recreation required; issue #739 resolved).

## --------------------------------------------------------------------------
## 6) Security and key management
- Questions
  - Where to store keys (xcconfig + Info.plist expansion) and avoid leaking.
  - Build variants and key scoping (Debug vs Release).
- Actions
  - Finalize `../complete/setup-keys.md` and project .gitignore for local overrides.
- Deliverables
  - Agreed process for keys, rotation, and CI handling.

### Findings (initial)
- Follow Google Maps Platform security guidance: restrict keys (application restriction to iOS bundle IDs), restrict APIs (Map Tiles API only), separate keys per app/environment, monitor usage, rotate keys safely.
  - https://developers.google.com/maps/api-security-best-practices

### Conclusions (initial)
- Store `MAP_TILES_API_KEY` in `xcconfigs` (e.g., `SkyPath/xcconfigs/APIKeys.xcconfig`) and expand into `Info.plist` at build time. Keep the real file out of version control; commit an `*.example` template. Apply key restrictions in Cloud Console.

## 7) Performance, caching, and network
- Questions
  - Expected bandwidth for Manhattan routes; warm cache behavior.
  - On-disk cache size, invalidation policy, and integrity.
  - Threading model for decode/prepare; frame pacing.
- Actions
  - Establish telemetry: tile loads, decode time, geometry counts, mem.
  - Define initial budgets and adjust based on profiling.
- Deliverables
  - Performance checklist and initial target budgets.

### Findings (initial)
- Respect HTTP caching headers when using Map Tiles API (no offline storage beyond protocol). Use `URLCache` and ETag-based revalidation. Control cesium-native budgets via `TilesetOptions` (e.g., `maximumCachedBytes`, `maximumSimultaneousTileLoads`).
  - https://developers.google.com/maps/documentation/tile/policies
  - https://cesium.com/learn/cesium-native/ref-doc/structCesium3DTilesSelection_1_1TilesetOptions.html

### Conclusions (initial)
- Implement telemetry (tile requests, decode/prepare timings, mesh counts, memory). Start with conservative concurrency and cache sizes, then tune with device profiling while staying within Google usage limits and attribution requirements.
