# AR ⇄ WebGL Mutual-Exclusion Resource Management — Design

**Date:** 2026-06-15
**Status:** Approved design, pending implementation plan
**Component:** `GeoTestARScene/GeoTestARScene/` (iOS app tab host)

## Overview

The app hosts four tabs in `ViewController`: AR (`ARViewController`), WebGL/Cesium
(`LocationsViewController`'s WKWebView), Map (`MapViewController`), and Info
(`InfoViewController`). Today every controller, once created, is retained forever and
keeps its heavy resources resident. In particular, after the WebGL tab is first opened,
the AR scene **and** the Cesium WebGL scene are both live in memory simultaneously. This
co-residency is the memory pressure that crashes the in-app WKWebView (see
`docs/phases/Phase03_WebGL_Model_Optimization.md` and the WebView memory-ceiling finding).

This feature enforces that **AR and WebGL are never resident at the same time**: whenever
one becomes active, the other's heavy resources are released. Preserving scene state
across switches is explicitly a non-goal.

## Goals

- At most one of **{AR, WebGL}** holds heavy GPU/memory resources at any moment.
- Activating AR releases WebGL; activating WebGL releases AR.
- Map (light) also releases both heavy subsystems when entered.
- Info is a transparent peek: it releases nothing.
- No regression of the WebGL fly-to crash across repeated AR ⇄ WebGL switching.

## Non-Goals

- Preserving WebGL camera state or AR localization across switches (we accept a reload /
  re-localize on return).
- App background/foreground resource handling (possible follow-up, not in this scope).
- Changing the WebGL content itself (covered by Phase 03).

## Current State (as built)

- `ViewController.switchToView(_:)` hides all container views, shows the selected one,
  and currently: pauses the AR session when leaving AR (`pauseARSession`), resumes it when
  entering AR (`resumeARSession`), and calls `pauseWebContent`/`resumeWebContent` when
  leaving/entering WebGL.
- `ARViewController.pauseARSession()` only calls `sceneView.session.pause()` +
  `LocationManager.stopUpdatingLocation()`. The `ARSCNView`, scene graph, and placed GLB
  model nodes stay fully in memory.
- AR content is placed via `ARGeoAnchor`s and the SceneKit `renderer(_:nodeFor:)` delegate;
  `startGeoTrackingSession()` runs the config with `.resetTracking, .removeExistingAnchors`,
  re-localizing and re-placing content on each (re)start. AR is gated by a "Start AR"
  button (`startARButton.isHidden == true` means AR was started).
- `LocationsViewController.pauseWebContent()`/`resumeWebContent()` evaluate JS that gates on
  `window.Cesium.viewer`, which `main.js` never assigns — so they are effectively **no-ops**.
  The WKWebView loads a remote URL (`defaultURL`).
- Controller retention: AR + Map created in `viewDidLoad`; WebGL + Info lazy-created on first
  visit. None are ever released.

## Design

### Definitions

- **Pause** — cheap, stops activity without freeing memory (e.g., `session.pause()` stops the
  AR camera).
- **Release** — actually frees the heavy GPU/memory:
  - WebGL: navigate the web view to `about:blank`.
  - AR: remove placed model content (geo-anchors / model nodes) so GLB geometry/textures free.

### Invariant

At most one of {AR, WebGL} is *released==false* (resident) at any time. Map and Info never
hold heavy resources of their own.

### Trigger rule (destination-keyed, in `switchToView`)

| Tap destination | AR memory | WebGL memory | AR camera |
|---|---|---|---|
| **AR** | activate (re-place) | **release** (`about:blank`) | resume |
| **WebGL** (listView) | **release** (remove nodes) | activate (load URL) | already paused |
| **Map** | **release** | **release** | pause |
| **Info** | keep (paused) | keep | pause if leaving AR |

Rationale: activating a heavy tab (AR/WebGL/Map) releases the other heavy subsystem; Info
releases nothing. AR's *camera* pauses whenever AR is not the visible tab (unchanged); AR's
*memory* frees only when WebGL or Map takes over. When leaving AR for Info, WebGL is already
released (it was released when AR activated), so the invariant still holds with only the
paused AR resident.

### Component changes

**`LocationsViewController`**
- Add `releaseWebGL()`: `webView.load(URLRequest(url: URL(string: "about:blank")!))`; set
  `private var isReleased = true`.
- Add `activateWebGL()`: if `isReleased` (or never loaded), load `defaultURL`; set
  `isReleased = false`.
- Remove/replace the no-op `pauseWebContent`/`resumeWebContent` calls in the switch logic
  with `releaseWebGL`/`activateWebGL`. (The JS-eval methods may be deleted.)

**`ARViewController`**
- Add `releaseAR()`: existing pause behavior (`session.pause()`,
  `LocationManager.stopUpdatingLocation()`) **plus** remove placed AR content so GLB memory
  frees — remove the geo-anchors and their nodes (and clear any cached loaded model scenes).
  Guarded so it is a no-op when AR was never started (`startARButton` visible).
- `activateAR()`: the existing resume path (`resumeARSession()` →
  `startGeoTrackingSession()`), which already resets tracking and re-places content.
- Keep `ARSCNView` allocated (empty) between activations.

**`ViewController.switchToView(_:)`**
- Replace the current pause/resume + pauseWebContent/resumeWebContent blocks with calls that
  implement the trigger-rule table above, using `release*/activate*`.
- Add small state guards so a destination that is already active does not re-release/activate
  (note: `switchToView` already early-returns when `viewState == currentViewState`).

### Edge cases

- **First visit / lazy init:** `activateWebGL()` must trigger the initial load on the first
  listView visit (today the lazy-init path loads the URL in `viewDidLoad`; ensure activate is
  idempotent with that).
- **AR never started:** `releaseAR()` and `activateAR()` no-op when `startARButton` is visible.
- **Double-trigger safety:** guard with the `isReleased` flag (WebGL) and the
  started/paused state (AR).
- **Map churn:** entering Map releases both heavy subsystems; bouncing Map ⇄ AR re-localizes
  AR each time. Accepted; revisit only if it proves annoying.

## Testing / Verification (manual, on device)

1. Cycle **AR → WebGL → AR → WebGL** several times; the fly-to crash must not recur.
2. With the WebGL diagnostics gauge present: it should appear only while WebGL is active, and
   the Cesium page should fully reload (loader) on each activation.
3. Returning to AR re-localizes and re-places models.
4. Xcode memory graph: confirm only one heavy subsystem is resident at a time (AR scene gone
   while WebGL active, and vice-versa).
5. Info peek from AR: AR stays resident (paused); no reload of either subsystem on return.

## Open Questions

None — Map treated as a heavy destination that releases both (tunable later if needed).
