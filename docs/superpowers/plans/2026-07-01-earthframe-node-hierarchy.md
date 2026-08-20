# earthFrame Node Hierarchy Implementation Plan (M02.2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an `earthFrame` SCNNode hierarchy at the scene-graph root, reparent ARKit's per-anchor nodes under it, and make every session reset/restart/failure path self-cleaning — the foundation for M02.4 occluders and M02.5 VPS correction.

**Architecture:** A pure-SceneKit `EarthFrameHierarchy` factory builds `earthFrame`/`earth_anchors`/`earth_occluders` (all identity transform). `ARViewController` adds `earthFrame` to the scene root (idempotent), reparents each ARKit anchor node into the matching child in `renderer(_:didAdd:for:)`, and calls one `clearEarthFrameChildrenAndTracking()` helper from every reset/restart/failure site because ARKit's auto-removal of reparented nodes is undocumented. `earthFrame.transform` is pinned to identity (enforced by a `didSet` + pure validator) until the M02.5 transform spec.

**Tech Stack:** Swift, SceneKit, ARKit, Xcode 16 synchronized-folder targets, Swift Testing (`import Testing`/`@Test`/`#expect`), `xcodebuild`.

**Spec:** `docs/superpowers/specs/2026-06-30-earthframe-node-hierarchy-design.md` (v2).
**Build/test setup:** see memory `ios-build-test-setup.md` — project `GeoTestARScene/SkyPath.xcodeproj`, scheme `GeoTestARScene`, destination `platform=iOS Simulator,id=B2A25A43-FBCD-4B24-97EC-9EE7E0E82CE3` (iPhone 17, OS 26.5). App and test targets are synchronized-folder targets (drop a `.swift` file in, no `project.pbxproj` edit).

**Conventions for every commit:** end the commit message with
```
Co-Authored-By: Claude <noreply@anthropic.com>
```

---

### Task 1: Feature branch + fix the test-target import (spec D5)

**Files:**
- Modify: `GeoTestARScene/GeoTestARSceneTests/GeoTestARSceneTests.swift:9`

- [ ] **Step 1: Create the feature branch**

Run:
```bash
git checkout -b m02.2-earthframe
```
Expected: `Switched to a new branch 'm02.2-earthframe'`

- [ ] **Step 2: Fix the stale `@testable import`**

In `GeoTestARScene/GeoTestARSceneTests/GeoTestARSceneTests.swift`, change line 9 from:

```swift
@testable import GeoTestARScene
```
to:
```swift
@testable import SkyPath
```

(The app target was renamed to `SkyPath`; the module is `SkyPath`. The test target is a synchronized-folder target, so this single broken import was blocking the whole target from compiling on a clean build.)

- [ ] **Step 3: Verify the test target compiles on a clean build**

Run:
```bash
xcodebuild clean build-for-testing \
  -project GeoTestARScene/SkyPath.xcodeproj -scheme GeoTestARScene \
  -destination 'platform=iOS Simulator,id=B2A25A43-FBCD-4B24-97EC-9EE7E0E82CE3' \
  -only-testing:SkyPathTests
```
Expected: `** BUILD SUCCEEDED **` (the existing `example()` test compiles; no test logic added yet).

- [ ] **Step 4: Commit**

```bash
git add GeoTestARScene/GeoTestARSceneTests/GeoTestARSceneTests.swift
git commit -m "fix(tests): @testable import SkyPath (module renamed from GeoTestARScene)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: `EarthFrameHierarchy.make()` — structure, names, identity (TDD)

**Files:**
- Create: `GeoTestARScene/GeoTestARScene/EarthFrameHierarchy.swift`
- Create (test): `GeoTestARScene/GeoTestARSceneTests/EarthFrameHierarchyTests.swift`

- [ ] **Step 1: Write the failing test**

Create `GeoTestARScene/GeoTestARSceneTests/EarthFrameHierarchyTests.swift`:

```swift
import Testing
import SceneKit
@testable import SkyPath

struct EarthFrameHierarchyTests {

    @Test func make_buildsNamedIdentityHierarchy() {
        let h = EarthFrameHierarchy.make()

        #expect(h.earthFrame.name == "earth_frame")
        #expect(h.anchorsFrame.name == "earth_anchors")
        #expect(h.occludersFrame.name == "earth_occluders")

        #expect(h.anchorsFrame.parent === h.earthFrame)
        #expect(h.occludersFrame.parent === h.earthFrame)
        #expect(h.earthFrame.childNodes.count == 2)

        #expect(h.earthFrame.simdTransform == matrix_identity_float4x4)
        #expect(h.anchorsFrame.simdTransform == matrix_identity_float4x4)
        #expect(h.occludersFrame.simdTransform == matrix_identity_float4x4)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
xcodebuild test \
  -project GeoTestARScene/SkyPath.xcodeproj -scheme GeoTestARScene \
  -destination 'platform=iOS Simulator,id=B2A25A43-FBCD-4B24-97EC-9EE7E0E82CE3' \
  -only-testing:SkyPathTests/EarthFrameHierarchyTests/make_buildsNamedIdentityHierarchy
```
Expected: FAIL — "cannot find 'EarthFrameHierarchy' in scope" (the type does not exist yet).

- [ ] **Step 3: Write minimal implementation**

Create `GeoTestARScene/GeoTestARScene/EarthFrameHierarchy.swift`:

```swift
import SceneKit

/// Pure-SceneKit factory for the earthFrame node hierarchy (M02.2).
///
/// `earthFrame` is added as a child of `sceneView.scene.rootNode` and will carry
/// the EMA anti-slide correction in M02.5. Its two children group ARKit anchor
/// nodes: geo content under `earth_anchors`, occluders (plane/mesh, later
/// Streetscape Geometry) under `earth_occluders`.
///
/// `earthFrame.transform` MUST stay identity until the M02.5 transform spec
/// (MERGED-005) lifts the invariant. ARKit writes each anchor node's `transform`
/// as if it were parented to the scene root; with an identity `earthFrame` the
/// reparent is visually jump-free. A non-identity `earthFrame` would silently
/// displace every reparented anchor. `assertIdentity(_:)` enforces the invariant
/// and is exercised (via `isIdentity`) in unit tests.
struct EarthFrameHierarchy {
    let earthFrame: SCNNode
    let anchorsFrame: SCNNode
    let occludersFrame: SCNNode

    static func make() -> EarthFrameHierarchy {
        let earth = SCNNode()
        earth.name = "earth_frame"

        let anchors = SCNNode()
        anchors.name = "earth_anchors"
        earth.addChildNode(anchors)

        let occluders = SCNNode()
        occluders.name = "earth_occluders"
        earth.addChildNode(occluders)

        return EarthFrameHierarchy(earthFrame: earth, anchorsFrame: anchors, occludersFrame: occluders)
    }

    /// Pure Bool check — unit-testable without trapping the process.
    static func isIdentity(_ earthFrame: SCNNode) -> Bool {
        earthFrame.simdTransform == matrix_identity_float4x4
    }

    /// Asserts `earthFrame` is at identity. Called from the `earthFrame` `didSet`
    /// observer, the reparent sites, and (via `isIdentity`) unit tests. No-op in
    /// Release builds; asserts on `isIdentity`.
    static func assertIdentity(_ earthFrame: SCNNode,
                               file: StaticString = #file, line: UInt = #line) {
        assert(isIdentity(earthFrame),
               "earthFrame must stay identity until M02.5 transform spec (MERGED-005)",
               file: file, line: line)
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
xcodebuild test \
  -project GeoTestARScene/SkyPath.xcodeproj -scheme GeoTestARScene \
  -destination 'platform=iOS Simulator,id=B2A25A43-FBCD-4B24-97EC-9EE7E0E82CE3' \
  -only-testing:SkyPathTests/EarthFrameHierarchyTests/make_buildsNamedIdentityHierarchy
```
Expected: PASS — `✔ Test make_buildsNamedIdentityHierarchy() passed`, `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add GeoTestARScene/GeoTestARScene/EarthFrameHierarchy.swift \
        GeoTestARScene/GeoTestARSceneTests/EarthFrameHierarchyTests.swift
git commit -m "feat(m02.2): add EarthFrameHierarchy factory + structure test

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: Identity invariant validator (TDD, spec D8 / AC4)

**Files:**
- Modify (test): `GeoTestARScene/GeoTestARSceneTests/EarthFrameHierarchyTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `EarthFrameHierarchyTests.swift` (inside the struct):

```swift
    @Test func isIdentity_detectsNonIdentity() {
        let h = EarthFrameHierarchy.make()
        #expect(EarthFrameHierarchy.isIdentity(h.earthFrame) == true)

        var t = matrix_identity_float4x4
        t.columns.3 = SIMD4<Float>(1, 2, 3, 1) // translation → non-identity
        h.earthFrame.simdTransform = t

        #expect(EarthFrameHierarchy.isIdentity(h.earthFrame) == false)
    }
```

- [ ] **Step 2: Run the test to verify it passes (implementation already exists from Task 2)**

Run:
```bash
xcodebuild test \
  -project GeoTestARScene/SkyPath.xcodeproj -scheme GeoTestARScene \
  -destination 'platform=iOS Simulator,id=B2A25A43-FBCD-4B24-97EC-9EE7E0E82CE3' \
  -only-testing:SkyPathTests/EarthFrameHierarchyTests/isIdentity_detectsNonIdentity
```
Expected: PASS. (`isIdentity` was implemented in Task 2 Step 3; this test characterizes it. If it FAILS, `isIdentity` is wrong — fix the implementation, not the test.)

- [ ] **Step 3: Commit**

```bash
git add GeoTestARScene/GeoTestARSceneTests/EarthFrameHierarchyTests.swift
git commit -m "test(m02.2): characterize EarthFrameHierarchy.isIdentity non-identity detection

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4: Reparent math proxy test (spec D9 / AC2 proxy)

**Files:**
- Modify (test): `GeoTestARScene/GeoTestARSceneTests/EarthFrameHierarchyTests.swift`

This is a characterization test of the SceneKit math that justifies "visually unchanged" — it needs no app code.

- [ ] **Step 1: Write the test**

Append to `EarthFrameHierarchyTests.swift` (inside the struct):

```swift
    @Test func reparentUnderIdentityParentPreservesWorldTransform() {
        // A non-identity child (translation) parented under an identity "old parent".
        var childTransform = matrix_identity_float4x4
        childTransform.columns.3 = SIMD4<Float>(2, 0, -1, 1)
        let child = SCNNode()
        child.simdTransform = childTransform

        let oldParent = SCNNode()          // identity
        oldParent.addChildNode(child)
        let worldBefore = child.simdWorldTransform

        // Reparent under an identity earthFrame (what EarthFrameHierarchy.make builds).
        let earthFrame = SCNNode()         // identity
        earthFrame.addChildNode(child)     // reparent

        #expect(child.simdWorldTransform == worldBefore)
    }
```

- [ ] **Step 2: Run the test to verify it passes**

Run:
```bash
xcodebuild test \
  -project GeoTestARScene/SkyPath.xcodeproj -scheme GeoTestARScene \
  -destination 'platform=iOS Simulator,id=B2A25A43-FBCD-4B24-97EC-9EE7E0E82CE3' \
  -only-testing:SkyPathTests/EarthFrameHierarchyTests/reparentUnderIdentityParentPreservesWorldTransform
```
Expected: PASS. (Confirms the mathematical basis of "visually unchanged": reparenting under an identity parent preserves world transform.)

- [ ] **Step 3: Commit**

```bash
git add GeoTestARScene/GeoTestARSceneTests/EarthFrameHierarchyTests.swift
git commit -m "test(m02.2): reparent under identity parent preserves worldTransform (AC2 proxy)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 5: Wire `earthFrame` into `ARViewController` — properties, idempotent creation, invariant `didSet`

**Files:**
- Modify: `GeoTestARScene/GeoTestARScene/ARViewController.swift` (properties block + `setupARView()`)

This is integration code (not unit-testable without a live AR session); verified by build.

- [ ] **Step 1: Add the earthFrame properties**

In `ARViewController.swift`, immediately after the `occlusionMaterial` lazy var block (after the closing `}` of `private lazy var occlusionMaterial: SCNMaterial = { ... }()` around line 67), insert:

```swift

    // MARK: - earthFrame hierarchy (M02.2)
    // earthFrame is a child of sceneView.scene.rootNode. Its transform MUST stay
    // identity until the M02.5 transform spec (MERGED-005): ARKit writes each
    // anchor node's transform as if parented to root, so an identity earthFrame
    // makes reparenting visually jump-free. The didSet enforces the invariant.
    private var m02_5CorrectionEnabled = false
    private var earthFrame: SCNNode? {
        didSet {
            if let earthFrame, !m02_5CorrectionEnabled {
                EarthFrameHierarchy.assertIdentity(earthFrame)
            }
        }
    }
    private var anchorsFrame: SCNNode?
    private var occludersFrame: SCNNode?
```

- [ ] **Step 2: Build the hierarchy idempotently in `setupARView()`**

In `setupARView()` (around line 327-351), insert this block immediately before the final `print("🎥 ARSCNView created and constrained with Auto Layout")` line:

```swift
        // earthFrame hierarchy (M02.2). Idempotent: build once, guard against re-add
        // so a second setupARView() cannot orphan a second hierarchy.
        if earthFrame?.parent == nil {
            let hierarchy = EarthFrameHierarchy.make()
            earthFrame = hierarchy.earthFrame
            anchorsFrame = hierarchy.anchorsFrame
            occludersFrame = hierarchy.occludersFrame
            sceneView.scene.rootNode.addChildNode(hierarchy.earthFrame)
        }

```

- [ ] **Step 3: Build to verify it compiles**

Run:
```bash
xcodebuild build \
  -project GeoTestARScene/SkyPath.xcodeproj -scheme GeoTestARScene \
  -destination 'platform=iOS Simulator,id=B2A25A43-FBCD-4B24-97EC-9EE7E0E82CE3'
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add GeoTestARScene/GeoTestARScene/ARViewController.swift
git commit -m "feat(m02.2): add earthFrame hierarchy to ARViewController (idempotent, invariant-guarded)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 6: Reparent ARKit anchor nodes per-branch in `renderer(_:didAdd:for:)`

**Files:**
- Modify: `GeoTestARScene/GeoTestARScene/ARViewController.swift:609-684` (`renderer(_:didAdd:for:)`)

The method has early `return`s, so the reparent is inserted inside each branch.

- [ ] **Step 1: Reparent plane anchors under `earth_occluders`**

Find the plane branch. Change:

```swift
                node.addChildNode(planeNode)
                planeNodes[planeAnchor.identifier] = planeNode
            }
            return // We've handled the plane anchor, so we can exit.
```
to:
```swift
                node.addChildNode(planeNode)
                planeNodes[planeAnchor.identifier] = planeNode
            }
            occludersFrame?.addChildNode(node)
            return // We've handled the plane anchor, so we can exit.
```

- [ ] **Step 2: Reparent mesh anchors under `earth_occluders`**

Find the mesh branch. Change:

```swift
            meshNodes[meshAnchor.identifier] = meshNode
            node.addChildNode(meshNode)
            return
```
to:
```swift
            meshNodes[meshAnchor.identifier] = meshNode
            node.addChildNode(meshNode)
            occludersFrame?.addChildNode(node)
            return
```

- [ ] **Step 3: Reparent geo placeholder nodes under `earth_anchors`**

Find the placeholder branch (model not in cache). Change:

```swift
            // Still update loadedLocations so we know we tried to load this anchor.
            loadedLocations[locationID] = locationData
            return
        }
```
to:
```swift
            // Still update loadedLocations so we know we tried to load this anchor.
            loadedLocations[locationID] = locationData
            node.name = geoAnchor.identifier.uuidString
            anchorsFrame?.addChildNode(node)
            return
        }
```

- [ ] **Step 4: Reparent geo success nodes under `earth_anchors`**

Find the success path. Change:

```swift
        // Add the content node to the ARKit-provided node for this anchor.
        node.addChildNode(contentNode)
```
to:
```swift
        // Add the content node to the ARKit-provided node for this anchor.
        node.addChildNode(contentNode)
        node.name = geoAnchor.identifier.uuidString
        anchorsFrame?.addChildNode(node)
```

- [ ] **Step 5: Build to verify it compiles**

Run:
```bash
xcodebuild build \
  -project GeoTestARScene/SkyPath.xcodeproj -scheme GeoTestARScene \
  -destination 'platform=iOS Simulator,id=B2A25A43-FBCD-4B24-97EC-9EE7E0E82CE3'
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add GeoTestARScene/GeoTestARScene/ARViewController.swift
git commit -m "feat(m02.2): reparent ARKit anchor nodes under earth_anchors/earth_occluders

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 7: Self-cleaning removal — helper + all reset/restart/failure paths + `didRemove` + `unloadModel` doc

**Files:**
- Modify: `GeoTestARScene/GeoTestARScene/ARViewController.swift` (viewWillAppear, startGeoTrackingSession, session:didFailWithError:, renderer(_:didRemove:), unloadModel, high-accuracy reload, new helper)

- [ ] **Step 1: Add the `clearEarthFrameChildrenAndTracking()` helper**

Add this private method to `ARViewController` (e.g. immediately before `// MARK: - ARSCNViewDelegate` around line 608):

```swift
    /// Removes all reparented anchor/occluder nodes and resets node-tracking dicts
    /// (M02.2 D3). Called from every session reset/restart/failure path because
    /// ARKit's auto-removal of reparented (non-root-parented) nodes is undocumented.
    /// Also resets the high-accuracy reload state so a restart is a clean fresh start.
    private func clearEarthFrameChildrenAndTracking() {
        anchorsFrame?.childNodes.forEach { $0.removeFromParentNode() }
        occludersFrame?.childNodes.forEach { $0.removeFromParentNode() }
        loadedLocations.removeAll()
        planeNodes.removeAll()
        meshNodes.removeAll()
        highAccuracyModelPlaced = false
        highAccuracyFrameCounter = 0
    }

```

- [ ] **Step 2: Call it in `viewWillAppear` before the bare WorldTracking run**

Change:

```swift
        // Run a basic session to show the camera feed. Geo-tracking will be started by the user.
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravityAndHeading
        sceneView.session.run(configuration)
```
to:
```swift
        // Run a basic session to show the camera feed. Geo-tracking will be started by the user.
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravityAndHeading
        clearEarthFrameChildrenAndTracking()
        sceneView.session.run(configuration)
```

- [ ] **Step 3: Call it in the LIDAR-debug branch before its `session.run`**

Change:

```swift
            sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
            sceneView.session.delegate = self
            return // Skip the rest of the geo-tracking setup
```
to:
```swift
            clearEarthFrameChildrenAndTracking()
            sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
            sceneView.session.delegate = self
            return // Skip the rest of the geo-tracking setup
```

- [ ] **Step 4: Call it in both geo `session.run` branches**

Change:

```swift
        if shouldResetTracking() {
            print("▶️ Starting fresh AR session with tracking reset")
            sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        } else {
            print("▶️ Resuming AR session without tracking reset")
            // Don't reset tracking - this preserves the coordinate system
            sceneView.session.run(configuration, options: [.removeExistingAnchors])
        }
```
to:
```swift
        if shouldResetTracking() {
            print("▶️ Starting fresh AR session with tracking reset")
            clearEarthFrameChildrenAndTracking()
            sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        } else {
            print("▶️ Resuming AR session without tracking reset")
            // Don't reset tracking - this preserves the coordinate system
            clearEarthFrameChildrenAndTracking()
            sceneView.session.run(configuration, options: [.removeExistingAnchors])
        }
```

- [ ] **Step 5: Call it in `session(_:didFailWithError:)`**

Change:

```swift
    func session(_ session: ARSession, didFailWithError error: Error) {
        print("❌ AR Session error: \(error.localizedDescription)")
        updateStatus("AR Session error: \(error.localizedDescription)")
    }
```
to:
```swift
    func session(_ session: ARSession, didFailWithError error: Error) {
        print("❌ AR Session error: \(error.localizedDescription)")
        updateStatus("AR Session error: \(error.localizedDescription)")
        // A failed session is non-recoverable; clear reparented nodes and tracking
        // (a fresh Start AR is required). M02.2 D3 — do not rely on ARKit auto-removal.
        clearEarthFrameChildrenAndTracking()
    }
```

- [ ] **Step 6: Make `renderer(_:didRemove:)` self-cleaning per node**

Change:

```swift
        } else if let meshAnchor = anchor as? ARMeshAnchor {
            print("🗑️ LIDAR MESH: Removing mesh anchor: \(meshAnchor.identifier)")
            meshNodes.removeValue(forKey: meshAnchor.identifier)
        }
    }
```
to:
```swift
        } else if let meshAnchor = anchor as? ARMeshAnchor {
            print("🗑️ LIDAR MESH: Removing mesh anchor: \(meshAnchor.identifier)")
            meshNodes.removeValue(forKey: meshAnchor.identifier)
        }
        // Authoritative node removal for every anchor type. ARKit auto-removal of
        // reparented nodes is undocumented, so remove explicitly. Idempotent: a
        // no-op if ARKit already removed the node.
        node.removeFromParentNode()
    }
```

- [ ] **Step 7: Fix the high-accuracy reload — flag-first race fix + anchorsFrame clear + breadcrumb**

Change:

```swift
                        if !twoClosestLocations.isEmpty {
                            print("🎯 Top \(twoClosestLocations.count) closest locations found.")
                            sceneView.session.currentFrame?.anchors.forEach { anchor in
                                if anchor is ARGeoAnchor { sceneView.session.remove(anchor: anchor) }
                            }
                            loadedLocations.removeAll()
                            print("🗑️ Removed all previous geo-anchors.")
                            
                            for location in twoClosestLocations {
                                print("📍 Placing high-accuracy model for: \(location.id)")
                                loadModelAtLocation(location)
                            }
                            highAccuracyModelPlaced = true
                        }
```
to:
```swift
                        if !twoClosestLocations.isEmpty {
                            print("🎯 Top \(twoClosestLocations.count) closest locations found.")
                            // MERGED-009: high-accuracy hard reset still exists; full redesign deferred
                            // — do not rely on this for drift correction. Set the flag BEFORE clearing so a
                            // concurrently-dispatched updateNearbyModels (main queue) cannot pass its
                            // !highAccuracyModelPlaced guard and re-add nodes during the clear window.
                            highAccuracyModelPlaced = true
                            sceneView.session.currentFrame?.anchors.forEach { anchor in
                                if anchor is ARGeoAnchor { sceneView.session.remove(anchor: anchor) }
                            }
                            loadedLocations.removeAll()
                            // Self-cleaning (M02.2 D3): ARKit auto-removal of reparented nodes is
                            // undocumented, so explicitly clear reparented geo content.
                            anchorsFrame?.childNodes.forEach { $0.removeFromParentNode() }
                            print("🗑️ Removed all previous geo-anchors.")
                            
                            for location in twoClosestLocations {
                                print("📍 Placing high-accuracy model for: \(location.id)")
                                loadModelAtLocation(location)
                            }
                        }
```

- [ ] **Step 8: Document the `unloadModel` carry-over**

Change:

```swift
    private func unloadModel(id: String) {
        guard let location = loadedLocations.removeValue(forKey: id) else {
            return
        }
        if let anchor = location.anchor {
            sceneView.session.remove(anchor: anchor)
        }
        if let node = location.node {
            node.removeFromParentNode()
        }
    }
```
to:
```swift
    private func unloadModel(id: String) {
        guard let location = loadedLocations.removeValue(forKey: id) else {
            return
        }
        // M02.2: node removal is unconditional and prevents earth_anchors ghosts.
        // didRemove is the authoritative cleaner (it also calls removeFromParentNode).
        // NOTE (carry-over, NOT fixed in M02.2): didAdd overwrites loadedLocations[id]
        // with the bare allLocations entry (anchor == nil), so for placed models
        // location.anchor is nil and session.remove is NOT called here — the anchor
        // is left in the session. The deeper fix (preserve .anchor across the didAdd
        // overwrite) is deferred; see spec §6.
        if let anchor = location.anchor {
            sceneView.session.remove(anchor: anchor)
        }
        if let node = location.node {
            node.removeFromParentNode()
        }
    }
```

- [ ] **Step 9: Build to verify it compiles**

Run:
```bash
xcodebuild build \
  -project GeoTestARScene/SkyPath.xcodeproj -scheme GeoTestARScene \
  -destination 'platform=iOS Simulator,id=B2A25A43-FBCD-4B24-97EC-9EE7E0E82CE3'
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 10: Commit**

```bash
git add GeoTestARScene/GeoTestARScene/ARViewController.swift
git commit -m "feat(m02.2): self-cleaning earthFrame removal across all reset/restart/failure paths

- clearEarthFrameChildrenAndTracking() helper called from viewWillAppear,
  startGeoTrackingSession (LIDAR + both geo branches), session:didFailWithError:
- didRemove calls node.removeFromParentNode() for every anchor type
- high-accuracy reload: flag-first race fix + anchorsFrame clear + MERGED-009 breadcrumb
- unloadModel: document the didAdd anchor-bookkeeping carry-over (deferred)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 8: Doc-comment the unused `worldPosition` extension (spec §3.6)

**Files:**
- Modify: `GeoTestARScene/GeoTestARScene/ARViewController.swift:1007-1015`

- [ ] **Step 1: Add the doc comment**

Change:

```swift
// MARK: - SCNNode Extensions
extension SCNNode {
    var worldPosition: SCNVector3 {
```
to:
```swift
// MARK: - SCNNode Extensions
extension SCNNode {
    /// World-space position (extracted from `presentation.worldTransform`).
    /// Valid as root-relative position ONLY while `earthFrame` is identity
    /// (M02.2 invariant); once M02.5 applies a correction to `earthFrame`,
    /// callers needing root-relative position must use `convertPosition`.
    var worldPosition: SCNVector3 {
```

- [ ] **Step 2: Build to verify it compiles**

Run:
```bash
xcodebuild build \
  -project GeoTestARScene/SkyPath.xcodeproj -scheme GeoTestARScene \
  -destination 'platform=iOS Simulator,id=B2A25A43-FBCD-4B24-97EC-9EE7E0E82CE3'
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add GeoTestARScene/GeoTestARScene/ARViewController.swift
git commit -m "docs(m02.2): clarify SCNNode.worldPosition is world-space, identity-earthFrame-only

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 9: Final verification + update loose-ends doc

**Files:**
- Modify: `docs/loose-ends-and-priorities.md` (§2.3.1, §2.3.2 status)

- [ ] **Step 1: Run the full unit-test suite on a clean build**

Run:
```bash
xcodebuild clean test \
  -project GeoTestARScene/SkyPath.xcodeproj -scheme GeoTestARScene \
  -destination 'platform=iOS Simulator,id=B2A25A43-FBCD-4B24-97EC-9EE7E0E82CE3' \
  -only-testing:SkyPathTests
```
Expected: all four `EarthFrameHierarchyTests` tests pass + the existing `example()` test passes; `** TEST SUCCEEDED **`.

- [ ] **Step 2: Build the app target clean**

Run:
```bash
xcodebuild clean build \
  -project GeoTestARScene/SkyPath.xcodeproj -scheme GeoTestARScene \
  -destination 'platform=iOS Simulator,id=B2A25A43-FBCD-4B24-97EC-9EE7E0E82CE3'
```
Expected: `** BUILD SUCCEEDED **` with no missing-file errors.

- [ ] **Step 3: Update the loose-ends doc — mark simulator-verifiable parts done**

In `docs/loose-ends-and-priorities.md`, change the §2.3.1 and §2.3.2 rows' State from `🟡 Spec written (v2)` to `🟢 Implemented (simulator-verified) — device ACs pending`, and append to the Evidence column of 2.3.2: `Implemented on branch m02.2-earthframe; unit tests green on iPhone 17 sim. Device-only ACs (visual-unchanged, runtime under-root, orphan-free across a localized walk) pending on-device verification.`

- [ ] **Step 4: Commit**

```bash
git add docs/loose-ends-and-priorities.md
git commit -m "docs(m02.2): mark earthFrame hierarchy implemented (simulator-verified, device ACs pending)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Verification summary (which ACs are covered where)

**Simulator-verifiable (Claude):**
- AC1 (structure) — Task 2 test.
- AC2-proxy (reparent math) — Task 4 test.
- AC3/AC4 (invariant detection) — Task 3 test.
- AC5 (test target compiles + tests pass, clean build) — Task 9 Step 1.
- AC6 (app builds, no missing-file) — Task 9 Step 2.

**Device-only (user, after merge):**
- AC2-runtime (geo anchors render under `earth_anchors`; visual unchanged).
- AC1-runtime (`earthFrame` is a child of `sceneView.scene.rootNode` at runtime).
- AC7 (no orphans across Spike-dismiss / Start AR restart / LIDAR toggle / high-accuracy reload / session-failure during a localized walk).

**Audited-clear (recorded in spec §9, no action):** spike isolation, scene persistence, tracking dicts, `viewWillDisappear`/`deinit`, `setWorldOrigin` N/A (2.3.3).

## After implementation

- Open a PR from `m02.2-earthframe` to `main` (only when the user asks).
- The device-only ACs require the user's on-device run; record results in `Phase02_Spike_Results.md` / the M02.2 baseline boot note.
- Carry-overs for the next milestone: M02.4 Streetscape occluders (under `earth_occluders`); M02.5 correction loop + the MERGED-005 transform spec (must flip `m02_5CorrectionEnabled` and revisit D4 occluder structure before lifting the identity invariant); the `unloadModel`/`didAdd` anchor-bookkeeping fix.