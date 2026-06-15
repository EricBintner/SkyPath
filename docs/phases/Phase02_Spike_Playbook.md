# Phase 02 — Spike Playbook

This document is the operator's checklist for running the M02.0 feasibility spike defined in [`Phase02_VPS_Grounded_Occluded_Plan.md`](Phase02_VPS_Grounded_Occluded_Plan.md) §7. The spike code lives on `main` under `GeoTestARScene/GeoTestARScene/Spike/` and is gated at runtime by a `SHOW_SPIKE_MENU=1` environment variable so day-to-day builds run normally. Record findings in [`Phase02_Spike_Results.md`](Phase02_Spike_Results.md) as you go. After the spikes complete, the `Spike/` folder and the `// SPIKE:` hook in `ARViewController.swift` get deleted in one commit.

## 0. One-time setup (do this first)

### 0.1 Pull latest

```bash
git pull origin main
git submodule update --init --recursive
```

### 0.2 Xcode dependencies (add via SPM)

Open `GeoTestARScene/GeoTestARScene.xcodeproj` and add via **File → Add Package Dependencies…**:

| Package | URL | Reason |
|---|---|---|
| ARCore iOS SDK | `https://github.com/google-ar/arcore-ios-sdk` | Provides `GARSession`, Streetscape Geometry. Pin to **1.54.0** or later. |
| GLTFKit2 | `https://github.com/warrenm/GLTFKit2` | Needed for Spike B and later milestones; safe to add now. |

For each package, add the relevant products to the **GeoTestARScene** app target:
- ARCore iOS SDK → tick **`ARCore`** (the umbrella product) or at minimum the Geospatial subspec if offered.
- GLTFKit2 → tick **`GLTFKit2`**.

### 0.3 Google Cloud project + API key

ARCore Geospatial requires a Google Cloud API key with the **ARCore API** enabled.

1. In [Google Cloud Console](https://console.cloud.google.com/), select or create a project.
2. APIs & Services → Library → enable **ARCore API**.
3. APIs & Services → Credentials → Create credentials → API key.
4. Restrict the key:
   - **Application restrictions** → iOS apps → add bundle ID `com.ericbintner.GeoTestARScene` (or whatever the GeoTestARScene target's bundle ID is — check the project settings).
   - **API restrictions** → restrict to **ARCore API** only.
5. Copy the key.

Free quota is 1,000 sessions/min and 100,000 requests/min — plenty for the spike.

### 0.4 Store the API key (gitignored)

The ARCore API key is read from the generated `Info.plist` at runtime. The project is already wired to pull it from a local, gitignored xcconfig:

- `GeoTestARScene/xcconfigs/APIKeys.local.xcconfig` is already added to the **GeoTestARScene** target's Debug and Release configurations.
- The directory has its own `.gitignore` (`*`) as defense-in-depth, so even renamed key files can't be committed by accident.
- The root `.gitignore` also ignores `*.local.xcconfig`.

**What you do:**

1. Create an iOS-restricted **API key** in Google Cloud Console (not OAuth / service account):
   - APIs & Services → Credentials → Create credentials → **API key**.
   - Application restrictions → **iOS apps** → bundle ID `com.ericbintner.GeoTestARScene`.
   - API restrictions → **ARCore API** only.
2. Open `GeoTestARScene/xcconfigs/APIKeys.local.xcconfig`.
3. Replace `YOUR_KEY_HERE` with the key string.
4. Build and run. The key is injected into the generated `Info.plist` as `ARCORE_API_KEY`.

The spike code reads `Bundle.main.object(forInfoDictionaryKey: "ARCORE_API_KEY") as? String`. Quick-test alternative (don't commit): paste the key inline at the `// HACK:` line in `SpikeAViewController.swift`.

### 0.5 Add the Spike sources to the Xcode project

In Xcode's Project Navigator, right-click the **GeoTestARScene** group → **Add Files to "GeoTestARScene"…** → select the entire **`Spike/`** folder. Make sure the option "Create groups" is selected and the target membership is **GeoTestARScene**.

Files you should now see in the Xcode project:
- `Spike/SpikeMenuViewController.swift`
- `Spike/SpikeAViewController.swift`
- `Spike/SpikeBViewController.swift`
- `Spike/SpikeCViewController.swift`

### 0.6 Enable the spike menu in the Xcode scheme

The spike menu is gated by an environment variable so normal builds are unaffected. To turn it on for spike testing:

1. Xcode → **Product → Scheme → Edit Scheme…**
2. Pick the **Run** action in the left sidebar.
3. Select the **Arguments** tab.
4. Under **Environment Variables**, add:
   - Name: `SHOW_SPIKE_MENU`
   - Value: `1`
5. Close the scheme editor. Subsequent ⌘R launches will pop the spike menu on the AR tab. To return to normal behavior, uncheck the variable in the scheme.

Search for `// SPIKE:` in `ARViewController.swift` to see the hook code. All spike-related code (`Spike/` folder + the `// SPIKE:` block) is removed in a single commit after the spikes complete.

### 0.7 Build & deploy to device

Spike work requires a real iPhone outdoors. Simulator and indoor builds will sit in `.notLocalized` forever.

- Plug in an iPhone (A12+, iOS 16+ recommended).
- Select the device in the Xcode scheme picker.
- ⌘R.
- First-launch will prompt for camera + precise location permissions. Allow both.
- Walk outside before tapping "Start Spike A" — VPS localization is line-of-sky-required.

---

## 1. Spike A — Pose stack coexistence

**Goal**: confirm `ARGeoTrackingConfiguration` + `GARSession` (with Geospatial + Streetscape Geometry enabled) work together on iOS.

**Procedure** (~30 minutes of field time):

1. Walk outdoors to a documented test spot with sky visible and Look Around imagery present (any NYC street with buildings on both sides is fine).
2. From the iOS app, tap **Spike A — Pose Coexistence** in the menu.
3. Hold the phone roughly horizontally, sweep slowly to give the system feature points to localize against.
4. Wait up to 60 seconds. Watch the on-screen HUD; it shows four lines:
   - `AR.GeoTracking: <state> <accuracy>` (Apple's pose)
   - `GAR.Earth: <state>` (Google's pose)
   - `GAR.YawAccuracy: <degrees>` (Google's numeric yaw uncertainty)
   - `Streetscape geometries: <count>`
5. **Pass criteria**:
   - `AR.GeoTracking` reaches `localized` with `medium` or `high` accuracy within 60 s.
   - `GAR.Earth` reaches `enabled` state with non-nil camera transform within 60 s.
   - `Streetscape geometries` becomes ≥ 1 within 90 s.
   - No exception logged to Xcode console.
6. **If it passes**: record the time-to-localize for each, then move on to Spike B with the same pose configuration (ARGeoTrackingConfiguration as primary).
7. **If it fails** (e.g. one or both refuse to localize, GARSession throws, console shows errors): record what happened in `Phase02_Spike_Results.md`, then switch to the fallback — replace `ARGeoTrackingConfiguration` with `ARWorldTrackingConfiguration` in `SpikeAViewController.swift` (`// FALLBACK:` marker) and re-run. The fallback should localize via GARSession alone, in which case Spike B and the rest of the plan switch to "ARCore-primary" mode (documented in Phase 02 §3 fallback).

## 2. Spike B — Renderer bake-off

**Goal**: decide between SceneKit (depth-only `SCNMaterial`) and RealityKit (`OcclusionMaterial`) as the renderer for Streetscape Geometry occluders.

`SpikeBViewController.swift` ships as a scaffold. You'll fill in the two render paths once Spike A's outcome tells you which `ARSessionConfiguration` to use.

**Procedure**:

1. Implement the two render paths inside the marked `// TODO: spike-b sceneKit` / `// TODO: spike-b realityKit` sections. Each ~80 lines: take a captured `GARStreetscapeGeometry.mesh`, build a node/entity from it with the appropriate occlusion material, place a debug magenta cube at 50 m, 80 m, 120 m from the camera looking down the street, render.
2. Toggle between modes using the segmented control at the top.
3. Stand at the test spot. Look at each of the three debug cubes through one or more building facades.
4. Visually verify the cube is hidden behind the facade in each mode. Note FPS and any z-fighting / acne at building edges.
5. **Pass criteria** for either renderer:
   - Occlusion appears correct at 50 m, 80 m, and 120 m.
   - FPS ≥ 30 with the visible Streetscape geometries loaded.
   - No flicker, no obvious z-fighting at facade edges.
6. **Pick the winner**: whichever passes; if both pass, the one with fewer LOC wins (we'll be maintaining this).
7. **If neither passes**: depth precision is the issue. Tune `SCNCamera.zNear`/`zFar` (SceneKit) or the equivalent in RealityKit. If still failing, escalate — the occlusion architecture itself needs rework before continuing.

## 3. Spike C — Sliding baseline capture

**Goal**: capture quantitative drift on the unmodified SceneKit baseline so later milestones have a ground truth to beat.

`SpikeCViewController.swift` ships as a thin wrapper that runs the existing `ARViewController` logic with prominent OSLog telemetry added at every anchor-update and frame-update boundary.

**Procedure**:

1. Walk to the start of a documented NYC block. Note the GPS coordinates of three visual landmarks (a doorway, a sign, a curb cut) you can return to within centimeters.
2. Tap **Spike C — Sliding baseline**.
3. Wait until the HUD reports `.localized` `.medium` or `.high`.
4. Place three test anchors over the landmarks (the screen tap places one at the camera's current screen-center).
5. Start screen-recording (iOS Control Center).
6. Walk 50 m down the block. Note when content goes through obvious "slip" events.
7. Return to the start landmarks. Look at each placed anchor: did it stay on the landmark or drift?
8. Use the screen recording to measure the apparent drift at each landmark in cm (compare anchor position to the real landmark position).
9. Record three values: drift at landmark #1, #2, #3, plus any yaw-rotation drift estimate.
10. Save the screen recording somewhere (e.g. attach to the spike results doc as a Files URL).

There is no pass/fail here — Spike C is purely a measurement. The numbers become the baseline for AC-1, AC-2, AC-4.

---

## 4. Recording results

Open [`Phase02_Spike_Results.md`](Phase02_Spike_Results.md). Fill in each of the three sections as you complete the spike. Be specific: paste numbers, paste console snippets, attach screenshots.

Once all three sections are filled in:

- Commit the results doc directly to `main` (this is a solo-dev workflow; no PR required).
- The spike code stays on `main` until M02.1 begins. At that point: delete the `Spike/` folder, remove the `// SPIKE:` hook in `ARViewController.swift`, and drop the `SHOW_SPIKE_MENU` env var from the scheme — one cleanup commit.

## 4.5 Known limitations / things you may have to adapt

These are honest gaps to expect during the spike. None block the spike itself; they're warnings so you don't burn time blaming the code when the SDK behaves slightly differently.

- **ARCore Swift API drift**. Spike A uses `GARSession(apiKey:bundleIdentifier:)` and `garFrame.streetscapeGeometries`. Different SDK versions sometimes spell these slightly differently (`GARSession.session(apiKey:bundleIdentifier:error:)`, etc.) and Swift bridging adds its own twists. If the Spike A file shows a small compile error after adding the package, fix the offending method call to whatever the installed SDK exposes — the names will be discoverable from the autocomplete or from the SDK's `GARSession.h`. Don't change the surrounding logic.
- **`GARSession.earth` nullability**. In some SDK versions it's nullable. If you see a crash on `gar.earth`, change to `guard let earth = gar.earth else { return }` and pipe a "GAR.Earth: not ready yet" line into the HUD.
- **`streetscapeGeometries` shape**. May be an `Array`, `Set`, or `NSSet`-bridged collection. Spike A only uses `.count`; Spike B's render path will need a stable iteration order — make a sorted array by `identifier` if needed.
- **Normal AR flow currently broken**. Because `models_to_place.json` was removed from the iOS source tree in commit `995fafb` (it now lives canonically in `webgl-component/`), the regular AR flow will find no models until the M02.3 build phase lands. The spike code is unaffected — it doesn't read `models_to_place.json`.
- **iOS Models.swift schema**. `LocationPoint` does not parse `sequence`, `model_ground_offset`, `model_scale_x/y/z` from the JSON. These fields are present in the canonical webgl `models_to_place.json` and are silently dropped on iOS today. The "ground offset" omission is the most consequential — content may sit at terrain level rather than its intended Y offset. Address in M02.3.

## 5. After the spike

Per Phase 02 §7 M02.0 exit criteria, the spike is done when:

- [ ] Pose stack decision is committed in writing in `Phase02_Spike_Results.md`.
- [ ] Renderer decision is committed in writing.
- [ ] Sliding baseline metrics are recorded.
- [ ] Phase 02 §3 and §5 are updated on `main` to reflect the chosen path (drop the "gated on Spike X" language; promote the chosen option from "candidate" to "decided").
- [ ] `Spike/` folder + `// SPIKE:` hook in `ARViewController.swift` deleted; `SHOW_SPIKE_MENU` env var removed from the Xcode scheme.

Then proceed to M02.1 directly on `main`.
