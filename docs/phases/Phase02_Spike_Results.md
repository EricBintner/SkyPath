# Phase 02 — Spike Results

Fill this in as each spike completes. Be concrete: paste numbers, console excerpts, screenshot URLs. The decisions made here unblock the rest of Phase 02; vague answers will cost real time later.

## Environment

- **Spike device**: (e.g. iPhone 15 Pro, iOS 17.5)
- **Spike location**: (lat/lon or street intersection)
- **Spike date(s)**: (YYYY-MM-DD)
- **Weather/visibility**: (matters for VPS localization)
- **ARCore iOS SDK version**: (e.g. 1.54.0)
- **GLTFKit2 version**: (e.g. 0.5.x)

---

## Spike A — Pose stack coexistence

### Configuration tested

- `ARGeoTrackingConfiguration` with `worldAlignment = .gravityAndHeading`
- `GARSession` with `geospatialMode = .enabled`, `streetscapeGeometryMode = .enabled`

### Observed behavior

- Time-to-`ARGeoTracking.state == .localized`: ___ s
- Time-to-`GAR.Earth.earthState == .enabled` with non-nil transform: ___ s
- Time-to-first Streetscape geometry: ___ s
- Reported yaw uncertainty when both localized: ___°
- Reported horizontal accuracy when both localized: ___ m
- Console errors / exceptions during 60 s of operation:

```
(paste anything that landed in the Xcode console)
```

### Outcome

- [ ] **PASS** — both pose systems localize and coexist; Streetscape geometries arrive
- [ ] **FAIL** — describe what broke, then re-test with the `// FALLBACK:` config and record below

### Fallback test (only if PASS = false)

- Switched ARSession to `ARWorldTrackingConfiguration`
- Time-to-`GAR.Earth.earthState == .enabled`: ___ s
- Outcome: ___

### Decision recorded

**Pose stack going forward (M02.1+)**:
- [ ] ARKit `ARGeoTrackingConfiguration` primary + GARSession secondary (for meshes only)
- [ ] ARCore `GARSession` primary + `ARWorldTrackingConfiguration` (fallback path)

Reasoning:
> (one paragraph)

---

## Spike B — Renderer bake-off (SceneKit depth-only vs RealityKit OcclusionMaterial)

### Setup

- Debug cubes placed at 50 m, 80 m, 120 m along the camera's forward axis (post-localization).
- Streetscape geometries loaded and inserted as occluders.

### SceneKit (`SCNMaterial.writesToDepthBuffer = true`, `colorBufferWriteMask = []`)

- Cube hidden behind facade at 50 m: yes / no
- Cube hidden behind facade at 80 m: yes / no
- Cube hidden behind facade at 120 m: yes / no
- FPS with N occluder meshes loaded (N = ___): ___ FPS
- Z-fighting or acne at facade edges: yes / no (describe if yes)
- LOC for the SceneKit render path: ___ lines

### RealityKit (`OcclusionMaterial()`)

- Cube hidden behind facade at 50 m: yes / no
- Cube hidden behind facade at 80 m: yes / no
- Cube hidden behind facade at 120 m: yes / no
- FPS with N occluder meshes loaded (N = ___): ___ FPS
- Z-fighting or acne at facade edges: yes / no
- LOC for the RealityKit render path: ___ lines

### Decision recorded

**Renderer going forward**:
- [ ] SceneKit
- [ ] RealityKit
- [ ] Neither works at distance — see escalation notes below

Reasoning:
> (one paragraph; cite the specific advantage that broke the tie)

Escalation notes (if neither passed):
> (describe what failed; lay out next experiment)

---

## Spike C — Sliding baseline capture

### Test block

- Block: (street name + cross streets)
- Walking distance: ___ m
- Number of test anchors placed: ___
- Wallclock duration: ___ minutes

### Drift measurements

| Landmark | Placed at (visual) | After 50m walk + return (visual displacement) |
|---|---|---|
| #1 | (description) | ___ cm |
| #2 | (description) | ___ cm |
| #3 | (description) | ___ cm |

- Yaw drift estimate after 5 minutes of walking: ___°
- Largest observed "slip" event: ___ cm, occurred when ___ (e.g. turning a corner, GPS losing fix)

### Screen recording

- Path: (file path or share URL)

### Notes

> Anything the numbers don't capture — feel-quality observations, hypotheses about root cause, edge cases.

---

## Aggregate decisions feeding M02.1+

Once all three spikes are recorded, summarize what changes about the Phase 02 plan:

1. **Pose stack**: (final pick)
2. **Renderer**: (final pick)
3. **Updates to Phase 02 plan**:
   - § 3: replace "gated on Spike A" with the decided pose stack
   - § 5: replace "gated on Spike B" with the decided renderer
   - § 1 AC thresholds: still appropriate vs the Spike C baseline numbers? If the baseline is worse than expected, AC thresholds may need to relax; if better, tighten.
4. **Surprises**: anything we didn't anticipate that future phases need to budget for.
