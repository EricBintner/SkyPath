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
