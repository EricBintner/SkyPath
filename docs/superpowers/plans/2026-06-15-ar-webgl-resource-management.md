# AR ⇄ WebGL Resource Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ensure the AR scene and the Cesium WebGL scene are never resident in memory at the same time — activating one releases the other's heavy resources.

**Architecture:** Three Swift changes. `LocationsViewController` gains `releaseWebGL()` (navigate the WKWebView to `about:blank`) / `activateWebGL()` (reload the URL). `ARViewController` gains `releaseAR()` (pause session, remove placed anchors/nodes, drop the USDZ `modelCache` and occlusion meshes) / `activateAR()` (rebuild `modelCache`, resume). `ViewController.switchToView(_:)` applies a destination-keyed policy that calls these.

**Tech Stack:** Swift, UIKit, ARKit/SceneKit (`ARSCNView`, `ARGeoAnchor`), WebKit (`WKWebView`).

**Spec:** `docs/superpowers/specs/2026-06-15-ar-webgl-resource-management-design.md`

---

## Testing approach (read first)

This project has **no unit-test target**, and the behavior here is UIKit/ARKit/WebKit
resource lifecycle that cannot be meaningfully unit-tested without a harness this project
doesn't have. Adding one for this change is out of scope (YAGNI). Therefore each task is
verified by **(a) a compile/build check** and **(b) on-device manual verification** (Task 4),
which is the honest verification for this domain. Build checks:

- **Primary:** open the project in Xcode and press **⌘B** → expect **Build Succeeded**.
- **Optional CLI compile check** (adjust project/scheme names to the current rename state —
  the project is mid-rename from `GeoTestARScene` to `SkyPath`):
  ```bash
  xcodebuild -project GeoTestARScene/SkyPath.xcodeproj -scheme GeoTestARScene \
    -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build
  ```

## File structure

| File | Responsibility | Change |
|---|---|---|
| `GeoTestARScene/GeoTestARScene/LocationsViewController.swift` | WebGL/WKWebView host | add `isReleased` flag + `releaseWebGL()`/`activateWebGL()` |
| `GeoTestARScene/GeoTestARScene/ARViewController.swift` | AR scene host | add `releaseAR()`/`activateAR()` |
| `GeoTestARScene/GeoTestARScene/ViewController.swift` | Tab host / `switchToView` | replace AR + web pause/resume blocks with the resource policy |

---

## Task 1: WebGL release/activate

**Files:**
- Modify: `GeoTestARScene/GeoTestARScene/LocationsViewController.swift`

- [ ] **Step 1: Add the `isReleased` flag**

In the `// Data` / properties area near the top of the class (next to `private var webView: WKWebView!`, ~line 11), add:

```swift
    // True when the web view has been navigated to about:blank to free WebGL memory.
    private var isReleased = false
```

- [ ] **Step 2: Add `releaseWebGL()` and `activateWebGL()`**

Add these methods inside the `// MARK: - Web Content Management` section (e.g., just above `func pauseWebContent()`):

```swift
    /// Frees the Cesium WebGL GPU/memory by navigating the web view to about:blank.
    /// The WebContent process releases its graphics resources. Reverse with activateWebGL().
    func releaseWebGL() {
        guard webView != nil, !isReleased else { return }
        print("Releasing WebGL resources (about:blank)")
        webView.load(URLRequest(url: URL(string: "about:blank")!))
        isReleased = true
    }

    /// Reloads the Cesium page if it was previously released. No-op on first activation,
    /// since viewDidLoad already loaded the URL (isReleased starts false).
    func activateWebGL() {
        guard isReleased else { return }
        print("Activating WebGL resources (reloading \(defaultURL))")
        loadWebsite(url: defaultURL)
        isReleased = false
    }
```

(`loadWebsite(url:)` and `defaultURL` already exist as private members of this class.)

- [ ] **Step 3: Build check**

Xcode **⌘B** → expect **Build Succeeded**. (Methods are unused until Task 3; that's fine.)

- [ ] **Step 4: Commit**

```bash
git add GeoTestARScene/GeoTestARScene/LocationsViewController.swift
git commit -m "Add releaseWebGL/activateWebGL to free WebGL resources via about:blank"
```

---

## Task 2: AR release/activate

**Files:**
- Modify: `GeoTestARScene/GeoTestARScene/ARViewController.swift`

- [ ] **Step 1: Add `releaseAR()` and `activateAR()`**

Add these methods immediately after `resumeARSession()` (~line 181):

```swift
    /// Frees AR heavy resources so AR is not resident while WebGL/Map is active:
    /// pauses the session, removes all placed geo-anchors and their nodes, and drops the
    /// loaded USDZ model templates and occlusion meshes. Reverse with activateAR().
    func releaseAR() {
        print("Releasing AR resources")
        pauseARSession()
        for id in Array(loadedLocations.keys) {
            unloadModel(id: id)
        }
        modelCache.removeAll()
        planeNodes.values.forEach { $0.removeFromParentNode() }
        planeNodes.removeAll()
        meshNodes.values.forEach { $0.removeFromParentNode() }
        meshNodes.removeAll()
        isGeoTrackingLocalized = false
        highAccuracyModelPlaced = false
        highAccuracyFrameCounter = 0
    }

    /// Rebuilds the model cache freed by releaseAR (if needed) and resumes the session,
    /// which re-localizes and re-places content. The session resume is a no-op if AR was
    /// never started (the Start AR button is still visible).
    func activateAR() {
        print("Activating AR resources")
        if modelCache.isEmpty {
            preloadModels()
        }
        resumeARSession()
    }
```

(`loadedLocations`, `unloadModel(id:)`, `modelCache`, `planeNodes`, `meshNodes`,
`isGeoTrackingLocalized`, `highAccuracyModelPlaced`, `highAccuracyFrameCounter`,
`preloadModels()`, `pauseARSession()`, and `resumeARSession()` are all existing members
of this class.)

- [ ] **Step 2: Build check**

Xcode **⌘B** → expect **Build Succeeded**.

- [ ] **Step 3: Commit**

```bash
git add GeoTestARScene/GeoTestARScene/ARViewController.swift
git commit -m "Add releaseAR/activateAR to free AR scene + USDZ model memory"
```

---

## Task 3: Wire the resource policy into switchToView

**Files:**
- Modify: `GeoTestARScene/GeoTestARScene/ViewController.swift:389-399` (delete) and `:448-461` (replace)

- [ ] **Step 1: Delete the old AR pause/resume block**

Remove this block (currently ~lines 389-399, before the "hide all container views" code):

```swift
        // Handle AR session management when leaving AR view
        if currentViewState == .arView && viewState != .arView {
            print("Leaving AR View - pausing session")
            arViewController.pauseARSession()
        }
        
        // Handle AR session resumption when returning to AR view
        if currentViewState != .arView && viewState == .arView {
            print("Returning to AR View - resuming session")
            arViewController.resumeARSession()
        }
```

Its behavior is folded into the policy in Step 2.

- [ ] **Step 2: Replace the old web-content block with the resource policy**

Replace this block (currently ~lines 448-461, after the show-container `switch`):

```swift
        // Handle web view resource management when switching to/from Cesium web view
        if currentViewState == .listView && viewState != .listView {
            // Leaving web view - pause web content
            print("Leaving Cesium web view - pausing content")
            if locationsViewController != nil {
                locationsViewController.pauseWebContent()
            }
        } else if viewState == .listView && currentViewState != .listView {
            // Entering web view - resume web content
            print("Entering Cesium web view - resuming content")
            if locationsViewController != nil {
                locationsViewController.resumeWebContent()
            }
        }
```

with:

```swift
        // --- Heavy-resource policy ---------------------------------------------------
        // AR and WebGL must never be resident at the same time. Activating a heavy tab
        // (AR / WebGL / Map) releases the other heavy subsystem; Info releases nothing.
        // Spec: docs/superpowers/specs/2026-06-15-ar-webgl-resource-management-design.md
        // Note: for .listView the lazy-init above guarantees locationsViewController != nil;
        // for .arView/.mapView it may be nil (WebGL never opened), so use optional chaining.
        switch viewState {
        case .arView:
            locationsViewController?.releaseWebGL()
            arViewController.activateAR()
        case .listView:
            arViewController.releaseAR()
            locationsViewController.activateWebGL()
        case .mapView:
            arViewController.releaseAR()
            locationsViewController?.releaseWebGL()
        case .infoView:
            // Transparent peek: keep both heavy subsystems as-is, but still stop the
            // AR camera if we were just in AR.
            if currentViewState == .arView {
                arViewController.pauseARSession()
            }
        }
        // -----------------------------------------------------------------------------
```

- [ ] **Step 3: Build check**

Xcode **⌘B** → expect **Build Succeeded**.

- [ ] **Step 4: Commit**

```bash
git add GeoTestARScene/GeoTestARScene/ViewController.swift
git commit -m "Enforce AR/WebGL mutual exclusion in switchToView resource policy"
```

---

## Task 4: On-device verification

**Files:** none (manual verification on a physical iPhone — AR + the WebGL crash only
reproduce on device).

- [ ] **Step 1: Build & run on a physical iPhone** (Xcode ⌘R, device selected).

- [ ] **Step 2: Crash regression — the original bug**

Cycle **AR → WebGL → AR → WebGL** several times, doing a "fly to" each time you're in WebGL.
Expected: no white-screen crash; each WebGL entry shows the loader and reloads fresh.

- [ ] **Step 3: WebGL released when AR active**

From WebGL, switch to AR. Expected (Xcode console): `Releasing WebGL resources (about:blank)`.
Switch back to WebGL: `Activating WebGL resources (reloading …)` and the page reloads.

- [ ] **Step 4: AR released when WebGL active**

From AR (after tapping Start AR and localizing), switch to WebGL. Expected console:
`Releasing AR resources`. Return to AR: `Activating AR resources`, AR re-localizes and
re-places models.

- [ ] **Step 5: Info is a transparent peek**

From AR, tap Info, then back to AR. Expected: AR does **not** fully reload (no
`Releasing AR resources` / `Activating AR resources` pair from the Info hop — only a camera
pause). From WebGL, tap Info, then back to WebGL: the page does **not** reload.

- [ ] **Step 6: Memory confirmation**

With Xcode's memory graph (Debug Navigator), confirm only one heavy subsystem is resident at
a time: the AR scene is gone while WebGL is active, and the Cesium WebGL gauge disappears
while AR is active.

- [ ] **Step 7: Commit any fixes** discovered during verification, then mark the plan done.

---

## Notes

- The now-unused `pauseWebContent()` / `resumeWebContent()` methods in
  `LocationsViewController` (and the matching no-op JS) can be deleted in a follow-up cleanup
  commit; left in place here to keep this change focused.
- The temporary on-screen WebGL diagnostics in `main.js` remain useful for Step 6 and should
  be removed as part of Phase 03, not here.

## Deferred future work — automated tests (TODO, separate effort)

This change is verified by compile + on-device manual checks because the project has no
test target. To make the resource policy regression-proof later, do this as its own plan:

- [ ] **Add an iOS unit-test target** (`GeoTestARSceneTests`) to the Xcode project.
- [ ] **Extract the destination→action decision** from `switchToView` into a pure function,
      e.g. `func resourceActions(for destination: ViewState, from current: ViewState) -> ResourceActions`
      where `ResourceActions` is a small struct of booleans
      (`releaseAR`, `activateAR`, `releaseWebGL`, `activateWebGL`, `pauseARCamera`).
      `switchToView` then just executes the returned actions. This isolates the policy so it
      is testable without UIKit/ARKit/WebKit.
- [ ] **Unit-test `resourceActions`** for all destination × current-state combinations against
      the trigger-rule table in the spec (e.g. `.arView` → `releaseWebGL && activateAR`;
      `.infoView` from `.arView` → only `pauseARCamera`; `.mapView` → `releaseAR && releaseWebGL`).
- [ ] **Unit-test the `isReleased` flag transitions** on a `LocationsViewController` double
      (release sets it true; activate from released reloads and clears it; activate when not
      released is a no-op).
